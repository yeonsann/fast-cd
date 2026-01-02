const std = @import("std");
const tui = @import("zigtui");
const builtin = @import("builtin");

const Direction = enum { Up, Down };

const DirectoryItem = struct {
    name: []const u8,
};

fn min(a: usize, b: usize) usize {
    return if (a < b) a else b;
}

fn initialPath() []const u8 {
    return if (builtin.os.tag == .windows)
        "C:\\"
    else
        "/";
}

const AppState = struct {
    allocator: std.mem.Allocator,

    cwd_path: std.ArrayList(u8), // absolute path
    cwd: std.fs.Dir,

    directories: std.ArrayList(DirectoryItem),
    selected: usize = 0,

    pub fn init(allocator: std.mem.Allocator) !AppState {
        var path = try std.ArrayList(u8).initCapacity(allocator, 256);
        try path.appendSlice(allocator, initialPath());

        const dir = try std.fs.openDirAbsolute(path.items, .{ .iterate = true });

        return .{
            .allocator = allocator,
            .cwd_path = path,
            .cwd = dir,
            .directories = try std.ArrayList(DirectoryItem).initCapacity(allocator, 256),
        };
    }

    pub fn deinit(self: *AppState) void {
        for (self.directories.items) |item| {
            self.allocator.free(item.name);
        }
        self.directories.deinit(self.allocator);

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
        self.clearDirectories();

        var it = self.cwd.iterate();
        while (try it.next()) |entry| {
            if (entry.kind == .directory) {
                const name = try self.allocator.dupe(u8, entry.name);
                try self.directories.append(self.allocator, .{ .name = name });
            }
        }

        self.selected = 0;
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

        self.cwd_path.clearRetainingCapacity();
        try self.cwd_path.appendSlice(self.allocator, parent);

        self.cwd.close();
        self.cwd = try std.fs.openDirAbsolute(self.cwd_path.items, .{ .iterate = true });

        try self.loadDirectories();
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
            .key => |key| switch (key.code) {
                .char => |c| {
                    if (c == 'q') running = false;
                    if (c == 'j') state.select(.Up);
                    if (c == 'k') state.select(.Down);
                },
                .enter => try state.enterSelected(),
                .backspace => try state.goUp(),
                .esc => running = false,
                else => {},
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
                const alloc = draw_ctx.allocator;
                const area = buf.getArea();

                const block = tui.widgets.Block{
                    .title = app.cwd_path.items,
                    .borders = tui.widgets.Borders.all(),
                    .border_style = tui.style.Style{ .fg = .green },
                };
                block.render(area, buf);

                const inner = tui.render.Rect{
                    .x = area.x + 1,
                    .y = area.y + 1,
                    .width = area.width -| 2,
                    .height = area.height -| 2,
                };

                const items = try alloc.alloc(tui.widgets.ListItem, app.directories.items.len);
                defer alloc.free(items);

                for (app.directories.items, items) |src, *dst| {
                    dst.* = .{ .content = src.name };
                }

                const list = tui.widgets.List{
                    .items = items,
                    .selected = app.selected,
                    .highlight_style = tui.style.Style{ .bg = .blue },
                };

                list.render(inner, buf);
            }
        }.render);
    }

    try terminal.showCursor();
}
