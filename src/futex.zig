const std = @import("std");
const builtin = @import("builtin");
const wasm = std.Target.wasm;

const Futex = @This();
const Atomic = std.atomic.Atomic;

comptime {
    if (!wasm.featureSetHas(builtin.cpu.features, .atomics)) {
        @compileError("WASM atomics aren't enabled");
    }
}

/// Checks if `ptr` still contains the value `expect` and, if so, blocks the caller until either:
/// - The value at `ptr` is no longer equal to `expect`.
/// - The caller is unblocked by a matching `wake()`.
/// - The caller is unblocked spuriously ("at random").
/// - The caller blocks for longer than the given timeout. In which case, `error.Timeout` is returned.
///
/// The checking of `ptr` and `expect`, along with blocking the caller, is done atomically
/// and totally ordered (sequentially consistent) with respect to other wait()/wake() calls on the same `ptr`.
pub fn timedWait(ptr: *const Atomic(u32), expect: u32, timeout_ns: u64) error{Timeout}!void {
    @setCold(true);

    // Avoid calling into the OS for no-op timeouts.
    if (timeout_ns == 0) {
        if (ptr.load(.SeqCst) != expect) return;
        return error.Timeout;
    }

    const timeout = if (std.math.cast(i64, timeout_ns)) |ns| ns else std.math.maxInt(i64);
    switch (memory_atomic_wait32(@constCast(&ptr.value), expect, timeout)) {
        0, 1 => return,
        2 => return error.Timeout,
        else => unreachable,
    }
}

/// Checks if `ptr` still contains the value `expect` and, if so, blocks the caller until either:
/// - The value at `ptr` is no longer equal to `expect`.
/// - The caller is unblocked by a matching `wake()`.
/// - The caller is unblocked spuriously ("at random").
///
/// The checking of `ptr` and `expect`, along with blocking the caller, is done atomically
/// and totally ordered (sequentially consistent) with respect to other wait()/wake() calls on the same `ptr`.
pub fn wait(ptr: *const Atomic(u32), expect: u32) void {
    @setCold(true);
    _ = memory_atomic_wait32(@constCast(&ptr.value), expect, -1);
}

/// Unblocks at most `max_waiters` callers blocked in a `wait()` call on `ptr`.
pub fn wake(ptr: *const Atomic(u32), max_waiters: u32) void {
    @setCold(true);

    // Avoid calling into the OS if there's nothing to wake up.
    if (max_waiters == 0) {
        return;
    }

    _ = memory_atomic_notify(@constCast(&ptr.value), max_waiters);
}

inline fn memory_atomic_wait32(ptr: *u32, exp: u32, timeout: i64) u32 {
    return asm volatile (
        \\local.get %[ptr]
        \\local.get %[exp]
        \\local.get %[timeout]
        \\memory.atomic.wait32 %[ret]
        : [ret] "=r" (-> u32),
        : [ptr] "r" (ptr),
          [exp] "r" (exp),
          [timeout] "r" (timeout),
        : "memory"
    );
}

inline fn memory_atomic_wait64(ptr: *u64, exp: u64, timeout: i64) u32 {
    return asm volatile (
        \\local.get %[ptr]
        \\local.get %[exp]
        \\local.get %[timeout]
        \\memory.atomic.wait64 %[ret]
        : [ret] "=r" (-> u32),
        : [ptr] "r" (ptr),
          [exp] "r" (exp),
          [timeout] "r" (timeout),
        : "memory"
    );
}

inline fn memory_atomic_notify(ptr: *u32, max_waits: u32) u32 {
    return asm volatile (
        \\local.get %[ptr]
        \\local.get %[wait]
        \\memory.atomic.notify %[ret]
        : [ret] "=r" (-> u32),
        : [ptr] "r" (ptr),
          [wait] "r" (max_waits),
        : "memory"
    );
}
