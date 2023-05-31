const std = @import("std");
const Builder = std.build.Builder;

pub fn build(b: *std.build.Builder) void {
    _ = b.addModule("zigrc", std.build.CreateModuleOptions{
        .source_file = .{ .path = "libs/zigrc.zig" },
    });

    const docs = b.addStaticLibrary(.{
        .name = "js-threads",
        .file_root_source = .{ .path = "src/main.zig" },
    });
    docs.emit_docs = true;
    const docs_step = b.step("docs", "Generate documentation");
    docs_step.dependOn(&docs.step);

    const main_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/main.zig" },
    });
    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&main_tests.step);
}
