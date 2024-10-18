/// Socket with fixed size buffers for input and output.
/// Data can be written into the socket in blocks
/// to be flushed out in one go.
/// Similarly, data can be read in blocks and later flushed to
/// allow further data to be read from the underlying socket.
const std = @import("std");
const Socket = @import("Socket.zig");

pub const Options = struct {
    buffer_size: usize = 4 * 1024 * 1024, // 4MB
};

allocator: std.mem.Allocator,
options: Options,
socket: Socket,
write_buffer: []u8,
// TODO: unfortunately this isn't quite what I was looking for, I want moveable cursors
// to indicate the available read bytes and then catch up with the write cursor
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
        .socket = try Socket.create(af, socket_type),
        .write_buffer = write_buf,
        .write_stream = write_stream,
        .read_buffer = read_buf,
        .read_stream = read_stream,
    };
}

// Closes underlying socket and destroys itself.
// Not usable after calling close.
pub fn close(self: *BufferedSocket) void {
    self.socket.close();
    self.allocator.free(self.write_buffer);
    self.allocator.free(self.read_buffer);
}

pub fn fd(self: *const BufferedSocket) std.posix.fd_t {
    return self.socket.fd();
}

pub fn bind(self: *BufferedSocket, addr: []const u8, port: u16) !void {
    try self.socket.bind(addr, port);
}

pub fn listen(self: *BufferedSocket) std.posix.ListenError!void {
    try self.socket.listen();
}

pub fn connect(self: *BufferedSocket, addr: []const u8, port: u16) !void {
    try self.socket.connect(addr, port);
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
        .socket = try self.socket.accept(),
        .read_buffer = read_buf,
        .read_stream = read_stream,
        .write_buffer = write_buf,
        .write_stream = write_stream,
    };
}

pub fn enablePortReuse(self: *BufferedSocket, enabled: bool) !void {
    try self.socket.enablePortReuse(enabled);
}

pub fn writeSlice(self: *BufferedSocket, slice: []const u8) !void {
    try self.write_stream.writer().writeAll(slice);
}

// TODO: add function to check if there is still stuff in the write buffer
// so that I know when to update the fd to only read in connection
pub fn doWrite(self: *BufferedSocket) !void {
    const buf = self.write_stream.getWritten();
    const written = try self.socket.write(buf);
    const backtrack: i64 = @intCast(written - buf.len);
    if (backtrack == 0) {
        self.write_stream.reset();
        return;
    }
    // TODO: handle errors
    self.write_stream.seekBy(backtrack) catch {
        std.debug.print("failed to seek back. buf_len={d} written={d}\n", .{ buf.len, written });
    };
}

const BufferedSocket = @This();
