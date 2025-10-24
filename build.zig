pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const minised_dep = b.dependency("minised", .{});

    const minised = b.addExecutable(.{
        .name = "minised",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });
    minised.addCSourceFiles(.{
        .root = minised_dep.path("."),
        .files = &.{ "sedcomp.c", "sedexec.c" },
    });
    b.installArtifact(minised);

    const test_step = b.step("test", "run tests");
    inline for (tests) |t| {
        const sed_test = SedTestStep.init(b, .{
            .root = minised_dep.path("tests"),
            .artifact = minised,
            .name = t,
        });
        test_step.dependOn(&sed_test.step);
    }
}

const SedTestStep = struct {
    step: Step,
    root: LazyPath,
    name: []const u8,
    artifact: *std.Build.Step.Compile,

    pub const Options = struct {
        root: LazyPath,
        name: []const u8,
        artifact: *std.Build.Step.Compile,
    };

    pub fn init(b: *std.Build, options: Options) *SedTestStep {
        const step = Step.init(.{
            .id = .custom,
            .name = b.fmt("test {s}", .{options.name}),
            .owner = b,
            .makeFn = make,
        });

        const sed_test = b.allocator.create(SedTestStep) catch @panic("OOM");
        sed_test.* = .{
            .step = step,
            .root = options.root,
            .name = options.name,
            .artifact = options.artifact,
        };
        sed_test.root.addStepDependencies(&sed_test.step);
        sed_test.step.dependOn(&sed_test.artifact.step);
        return sed_test;
    }

    fn runAllowFail(
        b: *std.Build,
        argv: []const []const u8,
        out_code: *u8,
    ) ![]u8 {
        if (!process.can_spawn)
            return error.ExecNotSupported;

        const max_output_size = 400 * 1024;
        var child = std.process.Child.init(argv, b.allocator);
        child.stdin_behavior = .Ignore;
        child.stdout_behavior = .Pipe;
        child.stderr_behavior = .Pipe;
        child.env_map = &b.graph.env_map;

        try Step.handleVerbose2(b, null, child.env_map, argv);
        try child.spawn();

        var stdout: ArrayList(u8) = .empty;
        var stderr: ArrayList(u8) = .empty;
        errdefer stdout.deinit(b.allocator);
        errdefer stderr.deinit(b.allocator);

        try child.collectOutput(b.allocator, &stdout, &stderr, max_output_size);
        const term = try child.wait();
        switch (term) {
            .Exited => |code| {
                out_code.* = @as(u8, @truncate(code));
                return stdout.items;
            },
            .Signal, .Stopped, .Unknown => |code| {
                out_code.* = @as(u8, @truncate(code));
                return error.ProcessTerminated;
            },
        }
    }

    fn make(step: *std.Build.Step, options: std.Build.Step.MakeOptions) !void {
        _ = options;
        const b = step.owner;
        const allocator = b.allocator;
        const sed_test: *SedTestStep = @fieldParentPtr("step", step);

        const root_path = sed_test.root.getPath3(b, step);
        const sed_path = b.pathResolve(&.{ root_path.root_dir.path orelse ".", root_path.sub_path, b.fmt("{s}.sed", .{sed_test.name}) });
        const in_path = b.pathResolve(&.{ root_path.root_dir.path orelse ".", root_path.sub_path, b.fmt("{s}.in", .{sed_test.name}) });
        const artifact_path = sed_test.artifact.getEmittedBin().getPath3(b, step);

        var exit_code: u8 = undefined;
        const dirty_result = try runAllowFail(
            b,
            &.{ artifact_path.subPathOrDot(), "-f", sed_path, in_path },
            &exit_code,
        );
        const out_file = root_path.openFile(b.fmt("{s}.out", .{sed_test.name}), .{}) catch |err| {
            if (err == error.FileNotFound and exit_code != 0) {
                // failed (as expected)
                return;
            } else if (err == error.FileNotFound and exit_code == 0) {
                return step.fail("test {s} passed unexpectedly", .{sed_test.name});
            } else {
                return err;
            }
        };
        const out_content = try out_file.readToEndAlloc(allocator, 16 * 1024);
        const result = try std.mem.replaceOwned(u8, allocator, dirty_result, "\r\n", "\n");
        if (!std.mem.eql(u8, result, out_content)) {
            return step.fail("test {s} failed\n\texpected `{s}` got `{s}`\n\tcmd: {s} -f {s} {s}", .{ sed_test.name, out_content, result, artifact_path.subPathOrDot(), sed_path, in_path });
        }
    }
};

const tests = .{
    "8bit-class",
    "address",
    "address2",
    "arg-parsing",
    "arg-parsing2",
    "char-class",
    "comment-curly",
    "d-all-inverted",
    "d-all",
    "d-inverted",
    "d",
    "empty-lhs",
    "eof-inverted",
    "eof-newline",
    "eof",
    "escaped-ampersand",
    "graph-class",
    "group-star-+",
    "group-star-g",
    "group-star",
    "group-star2",
    "group-star3",
    "group",
    "label",
    "last-re",
    "lhs-backref",
    "N-n",
    "N-n2",
    "N",
    "p-all-inverted",
    "p-all",
    "print-class",
    "punct-class",
    "quotes",
    "range",
    "range2",
    "range3",
    "range4",
    "range5",
    "range6",
    "range7",
    "rhs-escapes",
    "s-+",
    "s-+2",
    "s-ampersand",
    "s-ampersand2",
    "s-group-star",
    "s-group-star2",
    "s-newline",
    "s-nth",
    "s-nth2",
    "s-nth3",
    "s-star",
    "s-star2",
    "s",
    "scomplex",
    "sg",
    "single-escaped-char",
    "t2-initrdinit",
    "tac",
    // "test-e", // skip because it uses shebang and test step does not support that
    "test",
    "uniq",
    // "w", // stderr pipe might not work, skip for now
    // "w2", // stderr pipe might not work, skip for now
    "wiki",
    "xbxcx",
    "y",
};

const std = @import("std");
const Build = std.Build;
const LazyPath = Build.LazyPath;
const Step = Build.Step;
const process = std.process;
const ArrayList = std.ArrayList;
