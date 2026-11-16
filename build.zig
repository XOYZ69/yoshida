const std = @import("std");
const manifest = @import("build.zig.zon");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const strip = b.option(bool, "strip", "Leave debug info out of the CLI and server binaries");
    // "dev" marks a preview build: the CLI, the server and the editor show it
    // beside the version. Release builds leave it empty. The environment
    // variable lets CI set it once for every build step (npm run wasm,
    // scripts/release.sh, docker build).
    const channel = b.option([]const u8, "channel", "Build channel shown beside the version, e.g. dev (default: $YOSHIDA_CHANNEL, else none)") orelse
        b.graph.environ_map.get("YOSHIDA_CHANNEL") orelse "";

    // The render core: no file or network I/O, used by every front end.
    const core = createCore(b, target, optimize, channel);

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
    const wasm_core = createCore(b, wasm_target, .ReleaseSmall, channel);
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
    // Expression syntax only (parse, tokens, format), for the editor's main
    // thread: no project, no renderer.
    const expr_wasm = b.addExecutable(.{
        .name = "expr",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/wasm/expr.zig"),
            .target = wasm_target,
            .optimize = .ReleaseSmall,
            .imports = &.{.{ .name = "exprjson", .module = b.createModule(.{
                .root_source_file = b.path("src/core/exprjson.zig"),
                .target = wasm_target,
                .optimize = .ReleaseSmall,
            }) }},
        }),
    });
    expr_wasm.entry = .disabled;
    expr_wasm.rdynamic = true;
    const expr_wasm_install = b.addInstallArtifact(expr_wasm, .{ .dest_dir = .{ .override = .{ .custom = "web" } } });
    const wasm_step = b.step("wasm", "Build yoshida.wasm and expr.wasm into zig-out/web");
    wasm_step.dependOn(&wasm_install.step);
    wasm_step.dependOn(&expr_wasm_install.step);

    // Tests
    const tests = b.addTest(.{ .root_module = core });
    const test_step = b.step("test", "Run core and server tests");
    test_step.dependOn(&b.addRunArtifact(tests).step);
    const server_tests = b.addTest(.{ .root_module = server.root_module });
    test_step.dependOn(&b.addRunArtifact(server_tests).step);
    const cli_tests = b.addTest(.{ .root_module = cli.root_module });
    test_step.dependOn(&b.addRunArtifact(cli_tests).step);
}

fn createCore(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, channel: []const u8) *std.Build.Module {
    const core = b.createModule(.{
        .root_source_file = b.path("src/core/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    // The version lives in build.zig.zon only; scripts/version.mjs bumps it
    // and keeps the other copies (web/package.json, docs) in sync.
    const options = b.addOptions();
    options.addOption([]const u8, "version", manifest.version);
    options.addOption([]const u8, "channel", channel);
    core.addOptions("build_options", options);
    core.addIncludePath(b.path("src/c/include"));
    core.addIncludePath(b.path("src/c"));
    core.addCSourceFile(.{
        .file = b.path("src/c/stb_impl.c"),
        .flags = &.{ "-ffreestanding", "-fno-builtin-malloc", "-std=c99", "-O2" },
    });
    return core;
}
