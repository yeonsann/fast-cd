const std = @import("std");
const c = @cImport({
    @cInclude("ncurses.h");
    @cInclude("dirent.h");
    @cInclude("unistd.h");
    @cInclude("sys/stat.h");
});

const CdFile = "/tmp/zig-tui-cd";

// ================= State =================
const UiState = struct {
    show_hidden: bool = false,

    filtering: bool = false,
    filter_buf: [128]u8 = undefined,
    filter_len: usize = 0,
};

// ================= Helpers =================
fn min(a: usize, b: usize) usize {
    return if (a < b) a else b;
}

fn writeCd(path: []const u8) !void {
    var file = try std.fs.createFileAbsolute(CdFile, .{ .truncate = true });
    defer file.close();

    try file.writeAll("cd \"");
    try file.writeAll(path);
    try file.writeAll("\"\n");
}

fn isDir(path: []const u8) bool {
    var st: c.struct_stat = undefined;
    if (c.stat(path.ptr, &st) != 0) return false;
    return (st.st_mode & c.S_IFMT) == c.S_IFDIR;
}

fn alphaLess(_: void, a: []u8, b: []u8) bool {
    return std.ascii.lessThanIgnoreCase(a, b);
}

fn matchesFilter(name: []const u8, ui: *UiState) bool {
    if (ui.filter_len == 0) return true;
    return std.ascii.indexOfIgnoreCase(
        name,
        ui.filter_buf[0..ui.filter_len],
    ) != null;
}

fn reloadEntries(
    allocator: std.mem.Allocator,
    entries: *std.ArrayListUnmanaged([]u8),
    ui: *UiState,
) !void {
    for (entries.items) |e| allocator.free(e);
    entries.clearRetainingCapacity();

    const dir = c.opendir(".");
    if (dir == null) return;
    defer _ = c.closedir(dir);

    var ent = c.readdir(dir);
    while (ent != null) : (ent = c.readdir(dir)) {
        const name = std.mem.sliceTo(&ent.?.*.d_name, 0);

        if (std.mem.eql(u8, name, ".")) continue;
        if (!std.mem.eql(u8, name, "..") and !isDir(name)) continue;

        if (!ui.show_hidden and name[0] == '.' and !std.mem.eql(u8, name, "..")) {
            continue;
        }

        if (!matchesFilter(name, ui)) continue;

        try entries.append(allocator, try allocator.dupe(u8, name));
    }

    std.sort.insertion([]u8, entries.items, {}, alphaLess);
}

// ================= Drawing =================
fn clearRegion(start: usize, rows: usize) void {
    var i: usize = 0;
    while (i < rows) : (i += 1) {
        _ = c.move(@as(c_int, @intCast(start + i)), 0);
        _ = c.clrtoeol();
    }
}

fn drawHeader(cwd: []const u8, width: usize) void {
    _ = c.attron(c.A_BOLD);
    _ = c.move(0, 0);
    _ = c.clrtoeol();
    _ = c.mvprintw(0, 0, "%.*s", @as(c_int, @intCast(width)), cwd.ptr);
    _ = c.attroff(c.A_BOLD);
}

fn drawEntries(
    entries: std.ArrayListUnmanaged([]u8),
    selected: usize,
    scroll: usize,
    start: usize,
    rows: usize,
    width: usize,
) void {
    var i: usize = 0;
    while (i < rows and scroll + i < entries.items.len) : (i += 1) {
        const idx = scroll + i;
        const y = start + i;

        _ = c.move(@as(c_int, @intCast(y)), 0);
        _ = c.clrtoeol();

        if (idx == selected) _ = c.attron(c.A_REVERSE);
        const name = entries.items[idx];
        const n = min(width, name.len);

        _ = c.mvprintw(
            @as(c_int, @intCast(y)),
            0,
            "%.*s",
            @as(c_int, @intCast(n)),
            name.ptr,
        );

        if (idx == selected) _ = c.attroff(c.A_REVERSE);
    }
}

fn drawStatusBar(
    ui: *UiState,
    selected: usize,
    total: usize,
    row: usize,
    width: usize,
) void {
    _ = c.attron(c.A_REVERSE);
    _ = c.move(@as(c_int, @intCast(row)), 0);
    _ = c.clrtoeol();

    if (ui.filtering) {
        _ = c.mvprintw(
            @as(c_int, @intCast(row)),
            0,
            "/%.*s",
            @as(c_int, @intCast(ui.filter_len)),
            &ui.filter_buf,
        );
    } else {
        _ = c.mvprintw(
            @as(c_int, @intCast(row)),
            0,
            " j/k down/up | enter open | shift+h hidden | / filter | q quit ",
        );

        var buf: [64]u8 = undefined;
        const right = std.fmt.bufPrint(&buf, "{}/{}", .{ selected + 1, total }) catch "";
        if (right.len < width) {
            _ = c.mvprintw(
                @as(c_int, @intCast(row)),
                @as(c_int, @intCast(width - right.len)),
                "%s",
                right.ptr,
            );
        }
    }

    _ = c.attroff(c.A_REVERSE);
}

// ================= Main =================

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var ui = UiState{};
    var entries = std.ArrayListUnmanaged([]u8){};
    defer {
        for (entries.items) |e| allocator.free(e);
        entries.deinit(allocator);
    }

    _ = c.initscr();
    _ = c.noecho();
    _ = c.keypad(c.stdscr, true);
    _ = c.curs_set(0);
    defer _ = c.endwin();

    var selected: usize = 0;
    var scroll: usize = 0;

    try reloadEntries(allocator, &entries, &ui);

    while (true) {
        const rows: usize = @as(usize, @intCast(c.getmaxy(c.stdscr)));
        const width: usize = @as(usize, @intCast(c.getmaxx(c.stdscr)));

        const header_rows: usize = 1;
        const footer_rows: usize = 1;
        const list_rows =
            if (rows > header_rows + footer_rows)
                rows - header_rows - footer_rows
            else
                0;

        if (selected < scroll) scroll = selected;
        if (list_rows > 0 and selected >= scroll + list_rows) {
            scroll = selected - list_rows + 1;
        }

        _ = c.clear();

        const cwd = try std.fs.cwd().realpathAlloc(allocator, ".");
        defer allocator.free(cwd);

        drawHeader(cwd, width);
        clearRegion(header_rows, list_rows);
        drawEntries(entries, selected, scroll, header_rows, list_rows, width);
        drawStatusBar(&ui, selected, entries.items.len, rows - 1, width);

        _ = c.refresh();

        const ch = c.getch();

        if (ui.filtering) {
            switch (ch) {
                27 => { // ESC
                    ui.filtering = false;
                    ui.filter_len = 0;
                },
                '\n' => {
                    ui.filtering = false;
                    try reloadEntries(allocator, &entries, &ui);
                    selected = 0;
                    scroll = 0;
                },
                c.KEY_BACKSPACE, 127 => {
                    if (ui.filter_len > 0) ui.filter_len -= 1;
                },
                else => {
                    if (ui.filter_len < ui.filter_buf.len and ch >= 32 and ch < 127) {
                        ui.filter_buf[ui.filter_len] = @intCast(ch);
                        ui.filter_len += 1;
                    }
                },
            }
            continue;
        }

        switch (ch) {
            'q' => return,
            'k', c.KEY_UP => {
                if (selected > 0) selected -= 1;
            },
            'j', c.KEY_DOWN => {
                if (selected + 1 < entries.items.len) selected += 1;
            },
            '/' => {
                ui.filtering = true;
                ui.filter_len = 0;
            },
            'H', 8 => { // Ctrl+H
                ui.show_hidden = !ui.show_hidden;
                try reloadEntries(allocator, &entries, &ui);
                selected = 0;
                scroll = 0;
            },
            '\n', c.KEY_ENTER => {
                if (entries.items.len == 0) continue;
                const target = entries.items[selected];
                if (!isDir(target)) {
                    
                    continue;
                }

                if (c.chdir(target.ptr) == 0) {
                    try reloadEntries(allocator, &entries, &ui);
                    selected = 0;
                    scroll = 0;

                    const new_cwd = try std.fs.cwd().realpathAlloc(allocator, ".");
                    defer allocator.free(new_cwd);
                    try writeCd(new_cwd);
                }
            },

            else => {},
        }
    }
}
