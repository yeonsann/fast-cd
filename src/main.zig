const std = @import("std");
const tui = @import("zigtui");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize backend (platform-specific)
    var backend = if (@import("builtin").os.tag == .windows)
        try tui.backend.WindowsBackend.init(allocator)
    else
        try tui.backend.AnsiBackend.init(allocator);
    defer backend.deinit();

    // Initialize terminal
    var terminal = try tui.terminal.Terminal.init(allocator, backend.interface());
    defer terminal.deinit();

    // Hide cursor
    try terminal.hideCursor();

    // Main loop
    var running = true;
    while (running) {
        // Poll for events (100ms timeout)
        const event = try backend.interface().pollEvent(100);

        // Handle input
        switch (event) {
            .key => |key| {
                switch (key.code) {
                    .char => |c| {
                        if (c == 'q') running = false;
                    },
                    .esc => running = false,
                    else => {},
                }
            },
            else => {},
        }

        // Draw UI
        try terminal.draw({}, struct {
            fn render(_: void, buf: *tui.render.Buffer) !void {
                const area = buf.getArea();
                const block = tui.widgets.Block{
                    .title = "Hello ZigTUI - Press 'q' to quit",
                    .borders = tui.widgets.Borders.all(),
                    .border_style = tui.style.Style{ .fg = .cyan },
                };
                block.render(area, buf);
            }
        }.render);
    }

    try terminal.showCursor();
}
