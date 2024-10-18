const std = @import("std");
const Engine = @import("../Engine.zig");
const FdHandler = Engine.FdHandler;
const FdEvents = Engine.FdEvents;
const BufferedSocket = @import("../BufferedSocket.zig");
const Socket = @import("../Socket.zig");

/// Interface for tcp state events
pub const Handler = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        connected: *const fn (ctx: *anyopaque, conn: *Connection) void,
        disconnected: *const fn (ctx: *anyopaque, conn: *Connection) void,
    };

    pub fn connected(self: *Handler, conn: *Connection) void {
        self.vtable.connected(self.ptr, conn);
    }
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
    .errored = errored,
};

pub fn init(allocator: std.mem.Allocator, engine: *Engine, handler: Handler) !Connection {
    return Connection{
        .socket = try BufferedSocket.create(allocator, Socket.AddressFamily.ipv4, Socket.Type.tcp, .{}),
        .state = .disconnected,
        .handler = handler,
        .engine = engine,
    };
}

pub fn connect(self: *Connection, addr: []const u8, port: u16) !void {
    self.state = .connecting;
    try self.socket.connect(addr, port);
    try self.engine.registerFd(self.socket.fd(), FdHandler{ .ptr = self, .vtable = &fd_table }, FdEvents{ .write = true });
}

/// Create a connection with an already connected socket.
pub fn createConnected(allocator: std.mem.Allocator, engine: *Engine, socket: BufferedSocket) !*Connection {
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

pub fn writeSlice(self: *Connection, slice: []const u8) !void {
    try self.socket.writeSlice(slice);
    self.engine.updateFd(self.socket.fd(), FdEvents{ .read = true, .write = true });
}

fn readable(_: *anyopaque, _: std.posix.fd_t) void {}

fn writeable(ctx: *anyopaque, _: std.posix.fd_t) void {
    var self: *Connection = @alignCast(@ptrCast(ctx));
    switch (self.state) {
        .disconnected => unreachable,
        .connecting => {
            // TODO: update fd
            self.state = .connected;
            self.engine.updateFd(self.socket.fd(), FdEvents{ .read = true });
            self.handler.connected(self);
        },
        .connected => {
            // TODO: handle errors
            self.engine.updateFd(self.socket.fd(), FdEvents{ .read = true });
            self.socket.doWrite() catch {
                std.debug.print("failed to write in writeable callback\n", .{});
            };
        },
    }
}

fn errored(ctx: *anyopaque, _: std.posix.fd_t) void {
    std.debug.print("ERROR\n", .{});
    var self: *Connection = @alignCast(@ptrCast(ctx));
    self.engine.unregisterFd(self.socket.fd());
    // TODO: notify handler of the correct thing (closed vs. error)
    // get last socket error
}

const Connection = @This();
