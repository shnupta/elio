const FdHandler = @import("../Engine.zig").FdHandler;
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

/// Create a connection with an already connected socket.
pub fn create(socket: BufferedSocket) Connection {
    // TODO: probably want to pass the engine here and immediately register the fd
    return Connection{
        .socket = socket,
        .state = .connected,
        .handler = undefined,
    };
}

fn readable(_: *anyopaque) void {}

fn writeable(_: *anyopaque) void {
    // var self: *Connection = @ptrCast(ctx);
}

const Connection = @This();
