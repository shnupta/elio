/// Main event loop construct.
///
/// After calling start, will sit spinning whilst there is work to
/// do (has registered file descriptors or callbacks) and whilst
/// stop has not been called.
const std = @import("std");

/// Interface for handling fd events
pub const FdHandler = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    // TODO: these things might error? or do i have to restrict them to no errors
    // if so, then I'll have to have the handler for server/connection cleanup
    // on errors
    // or i just panic
    pub const VTable = struct {
        readable: *const fn (ctx: *anyopaque) void,
        writeable: *const fn (ctx: *anyopaque) void,
    };

    pub fn readable(self: *const FdHandler) void {
        self.vtable.readable(self.ptr);
    }

    pub fn writeable(self: *const FdHandler) void {
        self.vtable.writeable(self.ptr);
    }
};

pub const FdEvents = struct {
    read: bool = false,
    write: bool = false,
};

pub const FdRegistrationError = error{AlreadyRegistered};

allocator: std.mem.Allocator,
stopping: bool = false,
running: bool = false,
poll_fds: std.ArrayList(std.posix.pollfd),
handlers: std.ArrayList(FdHandler),
x: i32,

const Self = @This();

pub fn init(allocator: std.mem.Allocator) Self {
    return Self{
        .allocator = allocator,
        .poll_fds = std.ArrayList(std.posix.pollfd).init(allocator),
        .handlers = std.ArrayList(FdHandler).init(allocator),
        .x = 1,
    };
}

pub fn deinit(self: *Self) void {
    self.poll_fds.deinit();
    self.handlers.deinit();
}

pub fn start(self: *Self) !void {
    if (self.running) {
        @panic("the engine has already been started, you cannot start again");
    }

    self.stopping = false;
    try self.run();
}

fn run(self: *Self) !void {
    self.running = true;
    while (!self.stopping) {
        // no work to do
        // TODO: check callbacks
        if (self.poll_fds.items.len == 0) {
            self.stop();
            break;
        }

        try self.poll();
    }
    self.running = false;
}

fn poll(self: *Self) !void {
    const result = try std.posix.poll(self.poll_fds.items, 0);
    if (result <= 0) return;

    // TODO: better polling behaviour

    // readers
    for (self.poll_fds.items, 0..) |*pfd, idx| {
        const handler = self.handlers.items[idx];
        if ((pfd.revents & std.posix.POLL.IN) == 1) {
            handler.readable();
        }
    }

    // writers
    for (self.poll_fds.items, 0..) |*pfd, idx| {
        const handler = self.handlers.items[idx];
        if ((pfd.revents & std.posix.POLL.OUT) == 1) {
            handler.writeable();
        }
    }
}

pub fn stop(self: *Self) void {
    self.stopping = true;
}

pub fn register_fd(self: *Self, fd: std.posix.fd_t, handler: FdHandler, events: FdEvents) !void {
    for (self.poll_fds.items) |*pfd| {
        if (pfd.fd == fd) {
            return FdRegistrationError.AlreadyRegistered;
        }
    }

    var poll_events: i16 = std.posix.POLL.ERR;
    if (events.read) {
        poll_events |= std.posix.POLL.IN;
    }
    if (events.write) {
        poll_events |= std.posix.POLL.OUT;
    }

    try self.poll_fds.append(std.posix.pollfd{
        .fd = fd,
        .events = poll_events,
        .revents = 0,
    });
    try self.handlers.append(handler);
}

// TODO
// pub fn update_fd(self: *Self, fd: std.posix.fd_t, events: FdEvents) !void {
//
// }
