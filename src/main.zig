const std = @import("std");
const builtin = @import("builtin");
const rc = @import("libs/zigrc.zig");
const thread_id = @import("id.zig");

pub const thread_safe_allocator = @import("alloc.zig").thread_safe_allocator;

const AtomicU32 = std.atomic.Atomic(u32);
const ThreadLock = rc.Arc(AtomicU32);

comptime {
    if (!builtin.target.isWasm()) {
        @compileError("JS threads are only supported on WASM targets");
    } else if (!rc.atomic_arc) {
        @compileError("atomic support is not enabled");
    } else if (!std.Target.wasm.featureSetHasAll(builtin.cpu.features, .{ .bulk_memory, .mutable_globals })) {
        @compileError("shared memory is not enabled");
    }
}

// This struct represents a kernel thread, and acts as a namespace for concurrency
// primitives that operate on kernel threads. For concurrency primitives that support
// both evented I/O and async I/O, see the respective names in the top level std namespace.
pub const Thread = struct {
    idx: u32,
    lock: ThreadLock,

    pub const SpawnConfig = std.Thread.SpawnConfig;
    pub const Futex = @import("futex.zig");
    pub const Mutex = @import("mutex.zig");
    pub const max_name_len = 0;
    pub const SetNameError = std.Thread.SetNameError;
    pub const GetNameError = std.Thread.GetNameError;
    pub const Id = u32;
    pub const SpawnError = std.Thread.SpawnError;
    pub const YieldError = std.Thread.YieldError;

    // TODO error handling
    pub fn spawn(config: SpawnConfig, comptime f: anytype, args: anytype) SpawnError!Thread {
        const Args = @TypeOf(args);
        // Stack size isn't available as Worker option
        _ = config;
        // Ensure main "worker" ends up with id 0.
        _ = thread_id.thread_id();

        const Instance = struct {
            fn entryFn(raw_arg: *anyopaque, futex_ptr: *AtomicU32) void {
                const futex = ThreadLock{ .value = futex_ptr, .alloc = thread_safe_allocator };
                defer {
                    futex_ptr.store(1, .Release);
                    Futex.wake(futex_ptr, 1);
                    futex.release();
                }

                // @alignCast() below doesn't support zero-sized-types (ZST)
                if (@sizeOf(Args) < 1) {
                    return callFn(f, @as(Args, undefined));
                }

                const args_ptr = @ptrCast(*Args, @alignCast(@alignOf(Args), raw_arg));
                defer thread_safe_allocator.destroy(args_ptr);
                return callFn(f, args_ptr.*);
            }
        };

        const args_ptr = try thread_safe_allocator.create(Args);
        args_ptr.* = args;
        errdefer thread_safe_allocator.destroy(args_ptr);

        var futex = try ThreadLock.init(thread_safe_allocator, AtomicU32.init(0));
        errdefer futex.release();

        const idx = spawn_worker(
            null,
            0,
            Instance.entryFn,
            if (@sizeOf(Args) < 1) undefined else @ptrCast(*anyopaque, args_ptr),
            futex.retain().value,
        );
        return Thread{ .idx = idx, .lock = futex };
    }

    pub fn setName(self: Thread, name: []const u8) SetNameError!void {
        _ = name;
        _ = self;
        return error.Unsupported;
    }

    pub fn getName(self: Thread, buffer_ptr: *[max_name_len:0]u8) GetNameError!?[]const u8 {
        _ = buffer_ptr;
        _ = self;
        @compileError("not yet implemented");
    }

    /// Returns the platform ID of the callers thread.
    /// Attempts to use thread locals and avoid syscalls when possible.
    pub fn getCurrentId() Id {
        return thread_id.thread_id();
    }

    /// Release the obligation of the caller to call `join()` and have the thread clean up its own resources on completion.
    /// Once called, this consumes the Thread object and invoking any other functions on it is considered undefined behavior.
    pub fn detach(self: Thread) void {
        defer self.deinit();
        // TODO
    }

    /// Waits for the thread to complete, then deallocates any resources created on `spawn()`.
    /// Once called, this consumes the Thread object and invoking any other functions on it is considered undefined behavior.
    pub fn join(self: Thread) void {
        defer self.deinit();
        while (self.lock.value.load(.Acquire) == 0)
            Futex.wait(self.lock.value, 0);
    }

    /// Yields the current thread potentially allowing other threads to run.
    pub fn yield() YieldError!void {
        @compileError("not yet implemented");
    }

    fn deinit(self: Thread) void {
        release_worker(self.idx);
        self.lock.release();
    }
};

fn callFn(comptime f: anytype, args: anytype) void {
    @call(.auto, f, args);
}

export fn wasm_thread_entry_point(f: *const fn (*anyopaque, *AtomicU32) void, args: *anyopaque, futex_ptr: *AtomicU32) void {
    (f)(args, futex_ptr);
}

extern fn spawn_worker(
    name_ptr: ?[*]const u8,
    name_len: usize,
    f: *const fn (*anyopaque, *AtomicU32) void,
    args: *anyopaque,
    futex_ptr: *AtomicU32,
) u32;
extern fn release_worker(idx: u32) void;
