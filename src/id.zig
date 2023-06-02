const std = @import("std");

var thread_id_counter: u32 = 0;
export const thread_id_counter_ptr = &thread_id_counter;
pub extern fn thread_id() u32;

pub fn isMainWorker() bool {
    return thread_id() == 0;
}
