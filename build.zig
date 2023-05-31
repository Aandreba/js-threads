const std = @import("std");
const Builder = std.build.Builder;
const Target = std.Target;

pub fn build(b: *std.build.Builder) void {
    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    var target = default_target(.wasm32, .freestanding);
    target.cpu.features = std.Target.wasm.featureSet(&.{.atomics});

    const docs = b.addStaticLibrary(.{
        .name = "js-threads",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = std.zig.CrossTarget.fromTarget(target),
        .optimize = optimize,
    });
    docs.emit_docs = .emit;
    const docs_step = b.step("docs", "Generate documentation");
    docs_step.dependOn(&docs.step);

    const main_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/main.zig" },
    });
    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&main_tests.step);
}

fn default_target(arch: Target.Cpu.Arch, os_tag: Target.Os.Tag) Target {
    const os = os_tag.defaultVersionRange(arch);
    return Target{
        .cpu = Target.Cpu.baseline(arch),
        .abi = Target.Abi.default(arch, os),
        .os = os,
        .ofmt = Target.ObjectFormat.default(os_tag, arch),
    };
}
