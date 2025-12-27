const std = @import("std");
const eaz = @import("easy_args_zig");

const Arg = eaz.Arg;
const OptArg = eaz.OptArg;
const Flag = eaz.Flag;

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
            Arg(u32, "limit", "Limits are meant to be broken"),
            Arg([]const u8, "username", "who are you dear?"),
        },
        .optional = .{
            OptArg(u32, "break", "b", 100, "Stop before the limit"),
        },
        .flags = .{Flag("verbose", "v", "Print a little, print a lot"),},
    };

    const arguments = eaz.parseArgs(allocator, definitions, stdout, stderr) catch |err| {
        switch (err) {
            error.HelpShown => {
                try stdout.flush();
                std.process.exit(0);
            },
            else => {
                try stderr.flush();
                std.process.exit(0);
            }
        }    
    };
    
    // ------- Proofs of this thing is actually working you know
    // it's actually a new struct type
    const T = @TypeOf(arguments);
    try stdout.print("\n EazyArgs has created a whole new struct with the provided definition.\n", .{});
    try stdout.print("Type Name: {s}\n", .{@typeName(T)});
    
    try stdout.print("Let's check the alignment and bytes to make sure:\n", .{});
    try stdout.print("Size of definition generated struct: {d} bytes\n", .{@sizeOf(T)});
    try stdout.print("Limit offset: {d}\n", .{@offsetOf(T, "limit")});
    try stdout.print("Username offset: {d}\n", .{@offsetOf(T, "username")});
    try stdout.print("Break offset: {d}\n", .{@offsetOf(T, "break")});
    try stdout.print("Verbose offset: {d}\n", .{@offsetOf(T, "verbose")});
    
    // proof of names actually being in there
    const typeInfo = @typeInfo(T);
    try stdout.print("\n You can loop over all the fields, which whill be the same as in definition \n", .{});
    inline for (typeInfo.@"struct".fields) |f| {
       try stdout.print("Field '{s}' is type: {s}\n", .{ f.name, @typeName(f.type) });
    }

    // struct access
    try stdout.print("\n Lastly, the values are indeed the provided ones in the terminal\n", .{});
    try stdout.print("Limit:    {d}\n", .{arguments.limit});
    try stdout.print("Username: {s}\n", .{arguments.username});
    try stdout.print("Break: {d}\n", .{arguments.@"break"});
    try stdout.print("Verbose:  {any}\n", .{arguments.verbose});
    try stdout.flush();
}

