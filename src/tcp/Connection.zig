const std = @import("std");
const Engine = @import("../Engine.zig");
const FdHandler = Engine.FdHandler;
const FdEvents = Engine.FdEvents;
const BufferedSocket = @import("../BufferedSocket.zig");

/// Interface for tcp state events
pub const Handler = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        connected: *const fn (ctx: *anyopaque) void,
        disconnected: *const fn (ctx: *anyopaque) void,
    };
};

const State = enum { disconnected, connecting, connected };

socket: BufferedSocket,
handler: Handler,
state: State,
engine: *Engine,

// TODO: handle remote disconnection
const fd_table = FdHandler.VTable{
    .writeable = writeable,
    .readable = readable,
};

/// Create a connection with an already connected socket.
pub fn create(allocator: std.mem.Allocator, socket: BufferedSocket, engine: *Engine) !*Connection {
    const conn = try allocator.create(Connection);
    conn.socket = socket;
    conn.state = .connected;
    conn.handler = undefined;
    conn.engine = engine;
    try engine.registerFd(socket.fd(), FdHandler{ .ptr = conn, .vtable = &fd_table }, FdEvents{ .read = true });

    return conn;
}

pub fn close(self: *Connection) void {
    self.engine.unregisterFd(self.socket.fd());
    self.socket.close();
}

pub fn setHandler(self: *Connection, handler: Handler) void {
    self.handler = handler;
}

fn readable(_: *anyopaque) void {}

fn writeable(_: *anyopaque) void {
    // var self: *Connection = @ptrCast(ctx);
}

const Connection = @This();
