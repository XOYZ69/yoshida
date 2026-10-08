const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const strip = b.option(bool, "strip", "Leave debug info out of the CLI and server binaries");

    // The render core: no file or network I/O, used by every front end.
    const core = createCore(b, target, optimize);

    // CLI: yoshida check | render
    const cli = b.addExecutable(.{
        .name = "yoshida",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/cli/main.zig"),
            .target = target,
            .optimize = optimize,
            .strip = strip,
            .imports = &.{.{ .name = "yoshida", .module = core }},
        }),
    });
    b.installArtifact(cli);

    const run_cmd = b.addRunArtifact(cli);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);
    b.step("run", "Run the yoshida CLI").dependOn(&run_cmd.step);

    // Server: static web UI plus the render API, for Docker / home labs.
    const server = b.addExecutable(.{
        .name = "yoshida-server",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/server/main.zig"),
            .target = target,
            .optimize = optimize,
            .strip = strip,
            .imports = &.{.{ .name = "yoshida", .module = core }},
        }),
    });
    const server_install = b.addInstallArtifact(server, .{});
    b.getInstallStep().dependOn(&server_install.step);

    // WebAssembly build for the browser editor.
    const wasm_target = b.resolveTargetQuery(.{ .cpu_arch = .wasm32, .os_tag = .freestanding });
    const wasm_core = createCore(b, wasm_target, .ReleaseSmall);
    const wasm = b.addExecutable(.{
        .name = "yoshida",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/wasm/main.zig"),
            .target = wasm_target,
            .optimize = .ReleaseSmall,
            .imports = &.{.{ .name = "yoshida", .module = wasm_core }},
        }),
    });
    wasm.entry = .disabled;
    wasm.rdynamic = true;
    const wasm_install = b.addInstallArtifact(wasm, .{ .dest_dir = .{ .override = .{ .custom = "web" } } });
    b.step("wasm", "Build yoshida.wasm into zig-out/web").dependOn(&wasm_install.step);

    // Tests
    const tests = b.addTest(.{ .root_module = core });
    b.step("test", "Run core tests").dependOn(&b.addRunArtifact(tests).step);
}

fn createCore(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) *std.Build.Module {
    const core = b.createModule(.{
        .root_source_file = b.path("src/core/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    core.addIncludePath(b.path("src/c/include"));
    core.addIncludePath(b.path("src/c"));
    core.addCSourceFile(.{
        .file = b.path("src/c/stb_impl.c"),
        .flags = &.{ "-ffreestanding", "-fno-builtin-malloc", "-std=c99", "-O2" },
    });
    return core;
}
