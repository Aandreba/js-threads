const std = @import("std");
const builtin = @import("builtin");
const thread_id = @import("id.zig");

const AtomicU32 = std.atomic.Atomic(u32);
pub const thread_safe_allocator = @import("alloc.zig").thread_safe_allocator;

comptime {
    if (!builtin.target.isWasm()) {
        @compileError("JS threads are only supported on WASM targets");
    } else if (!std.Target.wasm.featureSetHasAll(builtin.cpu.features, .{ .atomics, .bulk_memory, .mutable_globals })) {
        @compileError("shared memory is not enabled");
    }
}

// This struct represents a kernel thread, and acts as a namespace for concurrency
// primitives that operate on kernel threads. For concurrency primitives that support
// both evented I/O and async I/O, see the respective names in the top level std namespace.
pub const Thread = struct {
    idx: u32,
    lock: *AtomicU32,

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
                defer {
                    @atomicStore(u32, &futex_ptr.value, 1, .Release);
                    Futex.wake(futex_ptr, 1);
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

        var futex = try thread_safe_allocator.create(AtomicU32);
        futex.* = AtomicU32.init(0);
        errdefer thread_safe_allocator.destroy(futex);

        const idx = spawn_worker(
            null,
            0,
            Instance.entryFn,
            if (@sizeOf(Args) < 1) undefined else @ptrCast(*anyopaque, args_ptr),
            futex,
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
        while (@atomicLoad(u32, &self.lock.value, .Acquire) == 0) {
            Futex.wait(self.lock, 0);
        }
    }

    /// Yields the current thread potentially allowing other threads to run.
    pub fn yield() YieldError!void {
        @compileError("not yet implemented");
    }

    fn deinit(self: Thread) void {
        release_worker(self.idx);
        thread_safe_allocator.destroy(self.lock);
    }
};

fn callFn(comptime f: anytype, args: anytype) void {
    const bad_fn_ret = "expected return type of startFn to be 'u8', 'noreturn', 'void', or '!void'";

    switch (@typeInfo(@typeInfo(@TypeOf(f)).Fn.return_type.?)) {
        .NoReturn => {
            @call(.auto, f, args);
        },
        .Void => {
            @call(.auto, f, args);
        },
        .Int => |info| {
            if (info.bits != 8) {
                @compileError(bad_fn_ret);
            }
            // workers don't support exit status, ignore value
            _ = @call(.auto, f, args);
        },
        .ErrorUnion => |info| {
            if (info.payload != void) {
                @compileError(bad_fn_ret);
            }

            @call(.auto, f, args) catch |err| {
                eprint("error: {s}\n", .{@errorName(err)});
                // if (@errorReturnTrace()) |trace| {
                //     std.debug.dumpStackTrace(trace.*);
                // }
            };
        },
        else => {
            @compileError(bad_fn_ret);
        },
    }
}

// INTERNAL
fn eprint(comptime fmt: []const u8, args: anytype) void {
    var str = std.ArrayListUnmanaged(u8).fromOwnedSlice(thread_safe_allocator.alloc(u8, fmt.len) catch @panic("OOM"));
    defer str.deinit();

    std.fmt.format(str.writer(thread_safe_allocator), fmt, args) catch @panic("OOM");
    print_error(str.items.ptr, str.items.len);
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
extern fn print_error(ptr: [*]const u8, len: usize) void;
