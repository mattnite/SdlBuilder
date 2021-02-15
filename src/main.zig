const std = @import("std");
const download = @import("download");

usingnamespace std.build;
const Self = @This();

pub const LinkType = enum {
    system,
    static,
    shared,
};

/// null means use system lib
config: ?struct {
    b: *Builder,
    arena: std.heap.ArenaAllocator,
    base_path: []const u8,
    library_path: []const u8,
    cmake_step: *RunStep,
    make_step: *RunStep,
},

pub fn init(b: *Builder, link_type: LinkType) !Self {
    return if (link_type == .system)
        Self{ .config = null }
    else blk: {
        // TODO: use different make programs, error if they don't exist
        var arena = std.heap.ArenaAllocator.init(b.allocator);
        const allocator = &arena.allocator;
        errdefer arena.deinit();

        const base_path = try download.tar.gz(
            allocator,
            b.cache_root,
            "https://www.libsdl.org/release/SDL2-2.0.14.tar.gz",
            .{
                .name = "sdl-2.0.14",
            },
        );
        const build_path = try std.fs.path.join(allocator, &[_][]const u8{ base_path, "build" });
        const cmake = b.addSystemCommand(&[_][]const u8{
            "cmake", "-GNinja", "-B", build_path, base_path,
        });
        cmake.setEnvironmentVariable("CC", "zig cc");
        cmake.setEnvironmentVariable("CXX", "zig c++");

        const make = b.addSystemCommand(&[_][]const u8{
            "ninja", "-C", build_path,
        });
        make.setEnvironmentVariable("CC", "zig cc");
        make.setEnvironmentVariable("CXX", "zig c++");
        make.step.dependOn(&cmake.step);

        break :blk Self{
            .config = .{
                .b = b,
                .arena = arena,
                .base_path = base_path,
                .library_path = try std.fs.path.join(allocator, &[_][]const u8{
                    build_path, if (link_type == .static) "libSDL2.a" else "libSDL2-2.0.so",
                }),
                .cmake_step = cmake,
                .make_step = make,
            },
        };
    };
}

pub fn deinit(self: *Self) void {
    if (self.config) |config| {
        config.arena.deinit();
        config.b.allocator.free(config.base_path);
    }
}

pub fn link(self: Self, artifact: *LibExeObjStep) void {
    if (self.config) |config| {
        artifact.addObjectFile(config.library_path);
        artifact.step.dependOn(&config.make_step.step);
    } else {
        artifact.linkSystemLibrary("SDL2");
    }

    artifact.linkLibC();
}
