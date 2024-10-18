/// Convenience wrapper around std.posix.socket_t
/// Interfaces with the Engine to handle fd events
const std = @import("std");

const Socket = @This();

pub const Type = enum {
    tcp,
    // udp,

    const Self = @This();

    fn toNative(self: Self) u32 {
        return switch (self) {
            .tcp => std.posix.SOCK.STREAM,
            // .udp => std.posix.SOCK.DGRAM,
        };
    }
};

pub const AddressFamily = enum {
    ipv4, // ipv6

    const Self = @This();

    fn toNative(self: Self) u32 {
        return switch (self) {
            .ipv4 => std.posix.AF.INET,
        };
    }
};

socket: std.posix.socket_t,

pub fn create(af: AddressFamily, socket_type: Type) !Socket {
    const flags = socket_type.toNative() | std.posix.SOCK.NONBLOCK;
    const sock = try std.posix.socket(af.toNative(), flags, 0);
    return Socket{
        .socket = sock,
    };
}

pub fn fd(self: *const Socket) std.posix.fd_t {
    return self.socket;
}

pub fn bind(self: *Socket, addr: []const u8, port: u16) !void {
    const parsed_addr = try std.net.Address.parseIp4(addr, port);
    const addr_ptr: *const std.posix.sockaddr = @ptrCast(&parsed_addr);
    try std.posix.bind(self.socket, addr_ptr, parsed_addr.getOsSockLen());
}

pub fn listen(self: *Socket) std.posix.ListenError!void {
    try std.posix.listen(self.socket, 0);
}

pub fn close(self: *Socket) void {
    std.posix.close(self.socket);
}

pub fn connect(self: *Socket, addr: []const u8, port: u16) !void {
    const parsed_addr = try std.net.Address.parseIp4(addr, port);
    const addr_ptr: *const std.posix.sockaddr = @ptrCast(&parsed_addr);
    std.posix.connect(self.socket, addr_ptr, parsed_addr.getOsSockLen()) catch |err| {
        if (err != std.posix.ConnectError.WouldBlock) {
            return err;
        }
    };
}

pub fn accept(self: *Socket) std.posix.AcceptError!Socket {
    var addr: std.posix.sockaddr.in = undefined;
    var addr_len: std.posix.socklen_t = @sizeOf(std.posix.sockaddr.in);
    const addr_ptr: *std.posix.sockaddr = @ptrCast(&addr);
    const new_sock = try std.posix.accept(self.socket, addr_ptr, &addr_len, 0);
    errdefer std.posix.close(new_sock);

    return Socket{
        .socket = new_sock,
    };
}

pub fn enablePortReuse(self: *Socket, enabled: bool) !void {
    var val: c_int = if (enabled) 1 else 0;
    try std.posix.setsockopt(
        self.socket,
        std.posix.SOL.SOCKET,
        std.posix.SO.REUSEADDR,
        std.mem.asBytes(&val),
    );
}

pub fn write(self: *Socket, bytes: []const u8) !usize {
    std.debug.print("writing to socket\n", .{});
    return try std.posix.write(self.socket, bytes);
}
