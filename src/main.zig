const std = @import("std");
const tui = @import("zigtui");
const builtin = @import("builtin");

const Mode = enum { Normal, Search };
const Direction = enum { Up, Down };

fn filterSubsetBySubstring(
    allocator: std.mem.Allocator,
    list: *std.ArrayList([]const u8),
    needle: []const u8,
) !std.ArrayList([]const u8) {
    var out = try std.ArrayList([]const u8).initCapacity(allocator, list.items.len);

    for (list.items) |s| {
        if (std.mem.indexOf(u8, s, needle) != null) {
            try out.append(allocator, s);
        }
    }

    return out;
}

const DirectoryItem = struct {
    name: []const u8,
};

fn min(a: usize, b: usize) usize {
    return if (a < b) a else b;
}

fn initialPath(allocator: std.mem.Allocator) ![]const u8 {
    return try std.process.getCwdAlloc(allocator);
}

fn byName(_: void, a: DirectoryItem, b: DirectoryItem) bool {
    return std.mem.lessThan(u8, a.name, b.name);
}

const AppState = struct {
    allocator: std.mem.Allocator,

    mode: Mode,
    searchQuery: std.ArrayList(u8),

    cwd_path: std.ArrayList(u8), // absolute path
    cwd: std.fs.Dir,

    directories: std.ArrayList(DirectoryItem),
    selected: usize = 0,
    showHidden: bool = false,

    pub fn init(allocator: std.mem.Allocator) !AppState {
        var path = try std.ArrayList(u8).initCapacity(allocator, 256);
        const searchQuery = try std.ArrayList(u8).initCapacity(allocator, 256);

        const initial_path = try initialPath(allocator);
        defer allocator.free(initial_path);
        try path.appendSlice(allocator, initial_path);

        const dir = try std.fs.openDirAbsolute(path.items, .{ .iterate = true });

        return .{
            .allocator = allocator,
            .cwd_path = path,
            .cwd = dir,
            .mode = Mode.Normal,
            .searchQuery = searchQuery,
            .directories = try std.ArrayList(DirectoryItem).initCapacity(allocator, 256),
        };
    }

    pub fn deinit(self: *AppState) void {
        for (self.directories.items) |item| {
            self.allocator.free(item.name);
        }
        self.directories.deinit(self.allocator);
        self.searchQuery.deinit(self.allocator);
        self.cwd_path.deinit(self.allocator);
        self.cwd.close();
    }

    fn clearDirectories(self: *AppState) void {
        for (self.directories.items) |item| {
            self.allocator.free(item.name);
        }
        self.directories.clearRetainingCapacity();
    }

    pub fn loadDirectories(self: *AppState) !void {
        self.selected = 0;
        self.clearDirectories();

        var it = self.cwd.iterate();
        while (try it.next()) |entry| {
            if (entry.kind == .directory) {
                if (!self.showHidden) {
                    if (entry.name.len > 0 and entry.name[0] == '.') {
                        continue;
                    } else {
                        const name = try self.allocator.dupe(u8, entry.name);
                        try self.directories.append(self.allocator, .{ .name = name });
                    }
                } else {
                    const name = try self.allocator.dupe(u8, entry.name);
                    try self.directories.append(self.allocator, .{ .name = name });
                }
            }
        }

        std.mem.sortUnstable(DirectoryItem, self.directories.items, {}, byName);
    }

    pub fn select(self: *AppState, dir: Direction) void {
        const len = self.directories.items.len;
        if (len == 0) return;

        self.selected = switch (dir) {
            .Up => min(self.selected + 1, len - 1),
            .Down => if (self.selected > 0) self.selected - 1 else 0,
        };
    }

    pub fn enterSelected(self: *AppState) !void {
        if (self.directories.items.len == 0) return;

        const name = self.directories.items[self.selected].name;

        if (!std.mem.endsWith(u8, self.cwd_path.items, std.fs.path.sep_str)) {
            try self.cwd_path.append(self.allocator, std.fs.path.sep);
        }
        try self.cwd_path.appendSlice(self.allocator, name);

        self.cwd.close();
        self.cwd = try std.fs.openDirAbsolute(self.cwd_path.items, .{ .iterate = true });

        try self.loadDirectories();
    }

    pub fn goUp(self: *AppState) !void {
        const parent = std.fs.path.dirname(self.cwd_path.items) orelse return;

        self.cwd_path.shrinkRetainingCapacity(parent.len);

        self.cwd.close();
        self.cwd = try std.fs.openDirAbsolute(self.cwd_path.items, .{ .iterate = true });

        try self.loadDirectories();
    }

    pub fn toggleHiddenDirectories(self: *AppState) !void {
        self.showHidden = !self.showHidden;
        self.cwd.close();
        self.cwd = try std.fs.openDirAbsolute(self.cwd_path.items, .{ .iterate = true });

        try self.loadDirectories();
    }

    pub fn closeAndSwitchToDir(self: *AppState) !void {
        var file = try std.fs.createFileAbsolute("/tmp/fcd_move_dir", .{ .truncate = true });
        defer file.close();

        try file.writeAll("cd \"");
        try file.writeAll(self.cwd_path.items);
        try file.writeAll("\"\n");
    }

    pub fn loadFavorites(self: *AppState) !void {
        var file = try std.fs.createFileAbsolute("~/.fcd_favorites", .{});
        defer file.close();

        const buffer: []u8 = try self.allocator.alloc(u8, 1024);
        try file.readAll(buffer);
        std.debug.print(buffer, .{});
    }

    pub fn addToFavorites(_: *AppState) !void {
        var file = try std.fs.createFileAbsolute("~/.fcd_favorites", .{});
        defer file.close();

        try file.writeAll("/home/yeonsan/code/fastcd/");
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var backend = if (builtin.os.tag == .windows)
        try tui.backend.WindowsBackend.init(allocator)
    else
        try tui.backend.AnsiBackend.init(allocator);
    defer backend.deinit();

    var terminal = try tui.terminal.Terminal.init(allocator, backend.interface());
    defer terminal.deinit();

    var state = try AppState.init(allocator);
    defer state.deinit();
    try state.loadDirectories();

    var running = true;
    while (running) {
        const event = try backend.interface().pollEvent(100);

        switch (event) {
            .key => |key| {
                if (state.mode == Mode.Search) {
                    switch (key.code) {
                        .char => |c| {
                            state.searchQuery.appendAssumeCapacity(@as(u8, @intCast(c)));
                        },
                        .esc => {
                            state.searchQuery.clearRetainingCapacity();
                            state.mode = Mode.Normal;
                        },
                        .backspace => {
                            _ = state.searchQuery.pop();
                        },
                        else => {},
                    }
                } else {
                    switch (key.code) {
                        .char => |c| {
                            if (c == 'q') running = false;
                            if (c == 'j') state.select(.Up);
                            if (c == 'k') state.select(.Down);
                            if (c == '/') state.mode = Mode.Search;
                            if (c == 'H') {
                                try state.toggleHiddenDirectories();
                            }
                            if (c == 'o') {
                                try state.closeAndSwitchToDir();
                                running = false;
                            }
                        },
                        .enter => try state.enterSelected(),
                        .backspace => try state.goUp(),
                        .esc => running = false,
                        else => {},
                    }
                }
            },
            else => {},
        }

        const DrawContext = struct {
            state: *AppState,
            allocator: std.mem.Allocator,
        };

        const ctx = DrawContext{ .state = &state, .allocator = allocator };

        try terminal.draw(ctx, struct {
            fn render(draw_ctx: DrawContext, buf: *tui.render.Buffer) !void {
                const app = draw_ctx.state;
                const area = buf.getArea();

                const parent_block = tui.widgets.Block{};
                const parent_inner = parent_block.inner(.{ .x = area.x, .y = area.y, .height = area.height, .width = area.width });
                parent_block.render(area, buf);

                const split = parent_inner.splitHorizontal(parent_inner.width / 2);
                const left = split.left;
                const right = split.right;

                const left_block = tui.widgets.Block{
                    .title = app.cwd_path.items,
                    .borders = tui.widgets.Borders.all(),
                    .border_style = tui.style.Style{ .fg = .white },
                };
                left_block.render(left, buf);

                const left_inner = tui.render.Rect{
                    .x = left.x + 1,
                    .y = left.y + 1,
                    .width = left.width -| 2,
                    .height = left.height -| 2,
                };

                const right_block = tui.widgets.Block{
                    .title = "History",
                    .borders = tui.widgets.Borders.all(),
                    .border_style = tui.style.Style{ .fg = .white },
                };
                right_block.render(right, buf);

                _ = tui.render.Rect{
                    .x = right.x + 1,
                    .y = right.y + 1,
                    .width = right.width -| 2,
                    .height = right.height -| 2,
                };

                try drawDirectoriesList(left_inner, buf, app);
                try drawFooter(area, buf, app);
            }
        }.render);
    }

    try terminal.showCursor();
}

fn drawDirectoriesList(area: tui.Rect, buf: *tui.Buffer, state: *AppState) !void {
    const alloc: std.mem.Allocator = state.allocator;
    var tmpList = try std.ArrayList([]const u8).initCapacity(alloc, state.directories.items.len);
    defer tmpList.deinit(alloc);

    for (state.directories.items) |item| {
        try tmpList.append(alloc, item.name);
    }

    var filtered = try filterSubsetBySubstring(alloc, &tmpList, state.searchQuery.items);
    defer filtered.deinit(alloc);

    const items = try alloc.alloc(tui.widgets.ListItem, filtered.items.len);
    defer alloc.free(items);

    for (filtered.items, items) |src, *dst| {
        dst.* = .{ .content = src };
    }

    const list = tui.widgets.List{
        .items = items,
        .selected = state.selected,
        .highlight_style = tui.style.Style{ .bg = .blue },
    };

    list.render(area, buf);
}

fn drawFooter(area: tui.Rect, buf: *tui.Buffer, state: *AppState) !void {
    // Render footer
    const footer_y = area.y + area.height - 1;

    var help: []u8 = undefined;
    defer state.allocator.free(help);

    if (state.mode == Mode.Search) {
        help = try std.fmt.allocPrint(state.allocator, "Search: {s}", .{state.searchQuery.items});
    } else {
        help = try std.fmt.allocPrint(state.allocator, "[O] Change CWD [j/k] Navigate [Enter/Return] Enter / Leave Directory [H] Toggle hidden files [Q] Quit ", .{});
    }

    const help_x = area.x + (area.width -| @as(u16, @intCast(help.len))) / 2;
    buf.setString(help_x, footer_y, help, tui.Style{ .fg = .dark_gray });
}
