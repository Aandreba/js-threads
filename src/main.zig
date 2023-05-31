const std = @import("std");
const builtin = @import("builtin");
var alloc = std.heap.page_allocator;

comptime {
    if (!builtin.target.isWasm()) {
        @compileError("JS threads are only supported on WASM targets");
    }

    // TODO check for bulk-memory and shared-memory features
}

pub const Thread = struct {
    idx: u32,

    pub const Mutex = @import("mutex.zig");

    fn spawn(comptime f: anytype, args: anytype) !Thread {
        const Args = @TypeOf(args);
        const Instance = struct {
            fn entryFn(raw_arg: *anyopaque) void {
                // @alignCast() below doesn't support zero-sized-types (ZST)
                if (@sizeOf(Args) < 1) {
                    return callFn(f, @as(Args, undefined));
                }

                const args_ptr = @ptrCast(*Args, @alignCast(@alignOf(Args), raw_arg));
                defer alloc.destroy(args_ptr);
                return callFn(f, args_ptr.*);
            }
        };
        _ = Instance;
    }
};

fn callFn(comptime f: anytype, args: anytype) void {
    @call(.auto, f, args);
}

export fn wasm_thread_entry_point(f: *const fn (*anyopaque) void, args: *anyopaque) void {
    @call(.auto, f, args);
}

extern fn spawn_worker(name_ptr: ?[*]const u8, name_len: usize, f: *const fn (*anyopaque) void, args: *anyopaque) void;
