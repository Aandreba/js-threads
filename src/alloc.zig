const std = @import("std");

const Allocator = std.mem.Allocator;
const Thread = @import("root").Thread;

var alloc_mutex: Thread.Mutex = .{};
var inner_alloc = std.heap.page_allocator;

pub const thread_safe_allocator: Allocator = .{
    .ptr = undefined,
    .vtable = &Allocator.VTable{ .alloc = alloc, .free = free, .resize = resize },
};

fn alloc(_: *anyopaque, len: usize, ptr_align: u8, ret_addr: usize) ?[*]u8 {
    alloc_mutex.lock();
    defer alloc_mutex.unlock();
    return inner_alloc.rawAlloc(len, ptr_align, ret_addr);
}

fn free(_: *anyopaque, buf: []u8, log2_buf_align: u8, ret_addr: usize) void {
    alloc_mutex.lock();
    defer alloc_mutex.unlock();
    return inner_alloc.rawFree(buf, log2_buf_align, ret_addr);
}

fn resize(_: *anyopaque, buf: []u8, log2_buf_align: u8, new_len: usize, ret_addr: usize) bool {
    alloc_mutex.lock();
    defer alloc_mutex.unlock();
    return inner_alloc.rawResize(buf, log2_buf_align, new_len, ret_addr);
}
