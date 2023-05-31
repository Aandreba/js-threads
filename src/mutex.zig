const std = @import("std");
const Mutex = @This();

pub fn lock(self: *Mutex) void {
    _ = self;
    // TODO wasm futex
}
