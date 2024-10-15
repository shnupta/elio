const std = @import("std");
const elio = @import("elio");
const Connection = elio.tcp.Connection;
const Server = elio.tcp.Server;

fn newConnection(_: *anyopaque, _: Connection) void {
    std.debug.print("New connection accepted!\n", .{});
}

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    var engine = elio.Engine.init(allocator);

    const vtable = Server.Handler.VTable{
        .newConnection = newConnection,
    };

    var server = try Server.init(allocator, Server.Handler{ .ptr = undefined, .vtable = &vtable }, .{});
    try server.bindAndListen(&engine, "0.0.0.0", 8899);

    std.debug.print("I have an engine! {d}\n", .{engine.x});

    try engine.start();
}

test "simple test" {
    var list = std.ArrayList(i32).init(std.testing.allocator);
    defer list.deinit(); // try commenting this out and see if zig detects the memory leak!
    try list.append(42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}
