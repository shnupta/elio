/// Socket with fixed size buffers for input and output.
/// Data can be written into the socket in blocks
/// to be flushed out in one go.
/// Similarly, data can be read in blocks and later flushed to
/// allow further data to be read from the underlying socket.
const std = @import("std");
const Socket = @import("Socket.zig");

pub const Options = struct {
    socket_options: Socket.Options = .{},
    buffer_size: usize = 4 * 1024 * 1024, // 4MB
};

allocator: std.mem.Allocator,
options: Options,
sock: Socket,
write_buffer: []u8,
write_stream: std.io.FixedBufferStream([]u8),
read_buffer: []u8,
read_stream: std.io.FixedBufferStream([]u8),

pub const CreateError = error{InvalidBufferSize};

pub fn create(allocator: std.mem.Allocator, af: Socket.AddressFamily, socket_type: Socket.Type, options: Options) !BufferedSocket {
    if (options.buffer_size <= 0) return CreateError.InvalidBufferSize;
    const read_buf = try allocator.alloc(u8, options.buffer_size);
    errdefer allocator.free(read_buf);
    const write_buf = try allocator.alloc(u8, options.buffer_size);
    errdefer allocator.free(write_buf);

    const read_stream = std.io.fixedBufferStream(read_buf);
    const write_stream = std.io.fixedBufferStream(write_buf);

    return BufferedSocket{
        .allocator = allocator,
        .options = options,
        .sock = try Socket.create(af, socket_type, options.socket_options),
        .write_buffer = write_buf,
        .write_stream = write_stream,
        .read_buffer = read_buf,
        .read_stream = read_stream,
    };
}

// Closes underlying socket and destroys itself.
// Not usable after calling close.
pub fn close(self: *BufferedSocket) void {
    self.sock.close();
    self.allocator.free(self.write_buffer);
    self.allocator.free(self.read_buffer);
}

pub fn fd(self: *const BufferedSocket) std.posix.fd_t {
    return self.sock.fd();
}

pub fn bind(self: *BufferedSocket, addr: []const u8, port: u16) !void {
    try self.sock.bind(addr, port);
}

pub fn listen(self: *BufferedSocket) std.posix.ListenError!void {
    try self.sock.listen();
}

// take ownership of the new buffered socket
pub fn accept(self: *BufferedSocket) !BufferedSocket {
    const read_buf = try self.allocator.alloc(u8, self.options.buffer_size);
    errdefer self.allocator.free(read_buf);
    const write_buf = try self.allocator.alloc(u8, self.options.buffer_size);
    errdefer self.allocator.free(write_buf);

    const read_stream = std.io.fixedBufferStream(read_buf);
    const write_stream = std.io.fixedBufferStream(write_buf);

    return BufferedSocket{
        .allocator = self.allocator,
        .options = self.options,
        .sock = try self.sock.accept(),
        .read_buffer = read_buf,
        .read_stream = read_stream,
        .write_buffer = write_buf,
        .write_stream = write_stream,
    };
}

pub fn enablePortReuse(self: *BufferedSocket, enabled: bool) !void {
    try self.sock.enablePortReuse(enabled);
}

const BufferedSocket = @This();
