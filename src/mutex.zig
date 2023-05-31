const std = @import("std");
const builtin = @import("builtin");

const Mutex = @This();
const Futex = @import("futex.zig");
const Atomic = std.atomic.Atomic;

impl: Impl = .{},

/// Tries to acquire the mutex without blocking the caller's thread.
/// Returns `false` if the calling thread would have to block to acquire it.
/// Otherwise, returns `true` and the caller should `unlock()` the Mutex to release it.
pub fn tryLock(self: *Mutex) bool {
    return self.impl.tryLock();
}

/// Acquires the mutex, blocking the caller's thread until it can.
/// It is undefined behavior if the mutex is already held by the caller's thread.
/// Once acquired, call `unlock()` on the Mutex to release it.
pub fn lock(self: *Mutex) void {
    self.impl.lock();
}

/// Releases the mutex which was previously acquired with `lock()` or `tryLock()`.
/// It is undefined behavior if the mutex is unlocked from a different thread that it was locked from.
pub fn unlock(self: *Mutex) void {
    self.impl.unlock();
}

const Impl = struct {
    state: Atomic(u32) = Atomic(u32).init(unlocked),

    const unlocked = 0b00;
    const locked = 0b01;
    const contended = 0b11; // must contain the `locked` bit for x86 optimization below

    fn tryLock(self: *@This()) bool {
        // Lock with compareAndSwap instead of tryCompareAndSwap to avoid reporting spurious CAS failure.

        return self.lockFast("compareAndSwap");
    }

    fn lock(self: *@This()) void {
        // Lock with tryCompareAndSwap instead of compareAndSwap due to being more inline-able on LL/SC archs like ARM.

        if (!self.lockFast("tryCompareAndSwap")) {
            self.lockSlow();
        }
    }

    inline fn lockFast(self: *@This(), comptime cas_fn_name: []const u8) bool {
        // On x86, use `lock bts` instead of `lock cmpxchg` as:

        // - they both seem to mark the cache-line as modified regardless: https://stackoverflow.com/a/63350048

        // - `lock bts` is smaller instruction-wise which makes it better for inlining

        if (comptime builtin.target.cpu.arch.isX86()) {
            const locked_bit = @ctz(@as(u32, locked));
            return self.state.bitSet(locked_bit, .Acquire) == 0;
        }

        // Acquire barrier ensures grabbing the lock happens before the critical section

        // and that the previous lock holder's critical section happens before we grab the lock.

        const casFn = @field(@TypeOf(self.state), cas_fn_name);
        return casFn(&self.state, unlocked, locked, .Acquire, .Monotonic) == null;
    }

    fn lockSlow(self: *@This()) void {
        @setCold(true);

        // Avoid doing an atomic swap below if we already know the state is contended.

        // An atomic swap unconditionally stores which marks the cache-line as modified unnecessarily.

        if (self.state.load(.Monotonic) == contended) {
            Futex.wait(&self.state, contended);
        }

        // Try to acquire the lock while also telling the existing lock holder that there are threads waiting.

        //

        // Once we sleep on the Futex, we must acquire the mutex using `contended` rather than `locked`.

        // If not, threads sleeping on the Futex wouldn't see the state change in unlock and potentially deadlock.

        // The downside is that the last mutex unlocker will see `contended` and do an unnecessary Futex wake

        // but this is better than having to wake all waiting threads on mutex unlock.

        //

        // Acquire barrier ensures grabbing the lock happens before the critical section

        // and that the previous lock holder's critical section happens before we grab the lock.

        while (self.state.swap(contended, .Acquire) != unlocked) {
            Futex.wait(&self.state, contended);
        }
    }

    fn unlock(self: *@This()) void {
        // Unlock the mutex and wake up a waiting thread if any.

        //

        // A waiting thread will acquire with `contended` instead of `locked`

        // which ensures that it wakes up another thread on the next unlock().

        //

        // Release barrier ensures the critical section happens before we let go of the lock

        // and that our critical section happens before the next lock holder grabs the lock.

        const state = self.state.swap(unlocked, .Release);
        std.debug.assert(state != unlocked);

        if (state == contended) {
            Futex.wake(&self.state, 1);
        }
    }
};
