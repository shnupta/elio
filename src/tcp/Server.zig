const std = @import("std");
const Engine = @import("../Engine.zig");
const FdHandler = Engine.FdHandler;
const FdEvents = Engine.FdEvents;
const BufferedSocket = @import("../BufferedSocket.zig");
const Socket = @import("../Socket.zig");
const Connection = @import("Connection.zig");

/// Interface for server events
pub const Handler = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        /// take ownership of the new connection
        newConnection: *const fn (ctx: *anyopaque, conn: *Connection) void,
    };

    pub fn newConnection(self: *Handler, conn: *Connection) void {
        self.vtable.newConnection(self.ptr, conn);
    }
};

allocator: std.mem.Allocator,
socket: BufferedSocket,
handler: Handler,
fd_vtable: FdHandler.VTable,
engine: *Engine,

const fd_vtable = FdHandler.VTable{
    .readable = readable,
    .writeable = writeable,
};

pub fn init(allocator: std.mem.Allocator, engine: *Engine, handler: Handler, options: BufferedSocket.Options) !Server {
    return Server{
        .allocator = allocator,
        .socket = try BufferedSocket.create(allocator, Socket.AddressFamily.ipv4, Socket.Type.tcp, options),
        .handler = handler,
        .fd_vtable = FdHandler.VTable{
            .readable = readable,
            .writeable = writeable,
        },
        .engine = engine,
    };
}

pub fn deinit(self: *Server) void {
    self.engine.unregisterFd(self.socket.fd());
    self.socket.close();
}

pub fn bindAndListen(self: *Server, addr: []const u8, port: u16) !void {
    try self.socket.enablePortReuse(true);
    try self.socket.bind(addr, port);
    try self.socket.listen();
    try self.engine.registerFd(self.socket.fd(), FdHandler{ .ptr = self, .vtable = &fd_vtable }, FdEvents{ .read = true });
}

fn accept(self: *Server) !*Connection {
    return Connection.create(self.allocator, try self.socket.accept(), self.engine);
}

fn readable(ctx: *anyopaque) void {
    var self: *Server = @alignCast(@ptrCast(ctx));
    const conn = self.accept() catch {
        return;
    };
    self.handler.newConnection(conn);
}

fn writeable(_: *anyopaque) void {}

const Server = @This();
