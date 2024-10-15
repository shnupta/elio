/// Convenience wrapper around std.posix.socket_t
/// Interfaces with the Engine to handle fd events
const std = @import("std");

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

pub const Options = struct {
    force_non_blocking: bool = false,
};

sock: std.posix.socket_t,

pub fn create(af: AddressFamily, socket_type: Type, options: Options) !Socket {
    var flags = socket_type.toNative();
    if (options.force_non_blocking) {
        flags |= std.posix.SOCK.NONBLOCK;
    }
    const sock = try std.posix.socket(af.toNative(), flags, 0);
    return Socket{
        .sock = sock,
    };
}

pub fn fd(self: *const Socket) std.posix.fd_t {
    return self.sock;
}

pub fn bind(self: *Socket, addr: []const u8, port: u16) !void {
    const parsed_addr = try std.net.Address.parseIp4(addr, port);
    const addr_ptr: *const std.posix.sockaddr = @ptrCast(&parsed_addr);
    try std.posix.bind(self.sock, addr_ptr, parsed_addr.getOsSockLen());
}

pub fn listen(self: *Socket) std.posix.ListenError!void {
    try std.posix.listen(self.sock, 0);
}

pub fn close(self: *Socket) void {
    std.posix.close(self.sock);
}

pub fn accept(self: *Socket) std.posix.AcceptError!Socket {
    var addr: std.posix.sockaddr.in = undefined;
    var addr_len: std.posix.socklen_t = @sizeOf(std.posix.sockaddr.in);
    const addr_ptr: *std.posix.sockaddr = @ptrCast(&addr);
    const new_sock = try std.posix.accept(self.sock, addr_ptr, &addr_len, 0);
    errdefer std.posix.close(new_sock);

    return Socket{
        .sock = new_sock,
    };
}

pub fn enablePortReuse(self: *Socket, enabled: bool) !void {
    var val: c_int = if (enabled) 1 else 0;
    try std.posix.setsockopt(
        self.sock,
        std.posix.SOL.SOCKET,
        std.posix.SO.REUSEADDR,
        std.mem.asBytes(&val),
    );
}

const Socket = @This();
