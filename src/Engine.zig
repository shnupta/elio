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
        errored: *const fn (ctx: *anyopaque, fd: std.posix.fd_t) void,
        readable: *const fn (ctx: *anyopaque, fd: std.posix.fd_t) void,
        writeable: *const fn (ctx: *anyopaque, fd: std.posix.fd_t) void,
    };

    pub fn errored(self: *const FdHandler, fd: std.posix.fd_t) void {
        self.vtable.errored(self.ptr, fd);
    }

    pub fn readable(self: *const FdHandler, fd: std.posix.fd_t) void {
        self.vtable.readable(self.ptr, fd);
    }

    pub fn writeable(self: *const FdHandler, fd: std.posix.fd_t) void {
        self.vtable.writeable(self.ptr, fd);
    }
};

pub const FdEvents = struct {
    read: bool = false,
    write: bool = false,
};

pub const FdRegistrationError = error{AlreadyRegistered};

const FdEntry = struct {
    pollfd: std.posix.pollfd,
    handler: FdHandler,
    active: bool = true,
};

allocator: std.mem.Allocator,
stopping: bool = false,
running: bool = false,
fds: std.MultiArrayList(FdEntry),
newly_registered_fds: std.MultiArrayList(FdEntry),
x: i32,

const Self = @This();

pub fn init(allocator: std.mem.Allocator) Self {
    return Self{
        .allocator = allocator,
        .fds = std.MultiArrayList(FdEntry){},
        .newly_registered_fds = std.MultiArrayList(FdEntry){},
        .x = 1,
    };
}

pub fn deinit(self: *Self) void {
    self.fds.deinit(self.allocator);
    self.newly_registered_fds.deinit(self.allocator);
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
        if (!self.workToDo()) {
            self.stop();
            break;
        }

        var idx: usize = 0;
        while (idx < self.fds.len) {
            const fd_entry = self.fds.get(idx);
            if (!fd_entry.active) {
                self.fds.orderedRemove(idx);
                continue;
            }
            idx += 1;
        }

        while (self.newly_registered_fds.len > 0) {
            try self.fds.append(self.allocator, self.newly_registered_fds.pop());
        }

        // TODO: add some timing here so that we only poll every Xms
        // obvs still process any callbacks and alarms if we have them

        try self.poll();
    }
    self.running = false;
}

fn workToDo(self: *const Self) bool {
    return self.fds.len > 0 or self.newly_registered_fds.len > 0;
}

fn poll(self: *Self) !void {
    const result = try std.posix.poll(self.fds.items(.pollfd), 0);
    if (result <= 0) return;

    for (0..self.fds.slice().len) |idx| {
        const entry = self.fds.get(idx);
        if ((entry.pollfd.revents & std.posix.POLL.ERR) > 0) {
            entry.handler.errored(entry.pollfd.fd);
            continue;
        }
        if ((entry.pollfd.revents & std.posix.POLL.OUT) > 0) {
            entry.handler.writeable(entry.pollfd.fd);
            if (!entry.active) continue;
        }
        if ((entry.pollfd.revents & std.posix.POLL.IN) > 0) {
            entry.handler.readable(entry.pollfd.fd);
        }
    }
}

pub fn stop(self: *Self) void {
    self.stopping = true;
}

pub fn registerFd(self: *Self, fd: std.posix.fd_t, handler: FdHandler, events: FdEvents) !void {
    for (self.fds.items(.pollfd)) |pfd| {
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

    try self.newly_registered_fds.append(self.allocator, FdEntry{ .pollfd = std.posix.pollfd{
        .fd = fd,
        .events = poll_events,
        .revents = 0,
    }, .handler = handler });
}

pub fn updateFd(self: *Self, fd: std.posix.fd_t, events: FdEvents) void {
    for (self.fds.items(.pollfd)) |*pfd| {
        if (pfd.fd == fd) {
            var poll_events: i16 = std.posix.POLL.ERR;
            if (events.read) {
                poll_events |= std.posix.POLL.IN;
            }
            if (events.write) {
                poll_events |= std.posix.POLL.OUT;
            }
            pfd.events = poll_events;
            return;
        }
    }
}

pub fn unregisterFd(self: *Self, fd: std.posix.fd_t) void {
    for (0..self.fds.len) |idx| {
        var fd_entry = self.fds.get(idx);
        if (fd_entry.pollfd.fd == fd) {
            fd_entry.active = false;
        }
        self.fds.set(idx, fd_entry);
    }
}

// TODO
// pub fn updateFdd(self: *Self, fd: std.posix.fd_t, events: FdEvents) !void {
//
// }
