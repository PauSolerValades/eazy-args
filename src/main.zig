const std = @import("std");
const eaz = @import("easy_args_zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    var buffer: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&buffer);
    const stdout = &stdout_writer.interface;

    var buferr: [1024]u8 = undefined;
    var stderr_writer = std.fs.File.stdout().writer(&buferr);
    const stderr = &stderr_writer.interface;
    
    const definitions = .{
        .required = .{
            eaz.Arg(u32, "limit", "Limits are meant to be broken"),
            eaz.Arg(bool, "verbose", "print a little, or print a lot"),
            eaz.Arg([]const u8, "username", "who are you dear?"),
        },
        .optional = .{
            eaz.OptArg(u32, "break", "b", 100, "Stop before the limit"),
        },
        .flags = .{eaz.Flag("hello", "he", "Print a little, print a lot but now with a flag"),},
    };

    const config = eaz.parseArgs(allocator, definitions, stdout, stderr) catch |err| {
        std.debug.print("Failed to parse args: {any}\n", .{err});
        return;
    };
    
    // ------- Proofs of this thing is actually working you know
    // it's actually a new struct type
    const T = @TypeOf(config);
    std.debug.print("\n--- Who is this struct? ---\n", .{});
    std.debug.print("Type Name: {s}\n", .{@typeName(T)});
    
    // proof of memory layout
    std.debug.print("Size: {d} bytes\n", .{@sizeOf(T)});
    std.debug.print("Limit offset: {d}\n", .{@offsetOf(T, "limit")});
    std.debug.print("Verbose offset: {d}\n", .{@offsetOf(T, "verbose")});
    
    // proof of names actually being in there
    const typeInfo = @typeInfo(T);
    std.debug.print("\n--- Field Inspection ---\n", .{});
    inline for (typeInfo.@"struct".fields) |f| {
       std.debug.print("Field '{s}' is type: {s}\n", .{ f.name, @typeName(f.type) });
    }

    // struct access
    std.debug.print("\n--- Result ---\n", .{});
    std.debug.print("Limit:    {d}\n", .{config.limit});
    std.debug.print("Verbose:  {any}\n", .{config.verbose});
    std.debug.print("Username: {s}\n", .{config.username});
}

