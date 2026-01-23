const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;

const eaz = @import("eazy_args");

const Arg = eaz.Arg;
const OptArg = eaz.OptArg;
const Flag = eaz.Flag;
const ParseErrors = eaz.ParseErrors;

// fn example1(allocator: Allocator, stdout: *Io.Writer, stderr: *Io.Writer) !void {
//     const definitions = .{
//         .required = .{
//             Arg(u32, "limit", "Limits are meant to be broken"),
//             Arg([]const u8, "username", "who are you dear?"),
//         },
//         .optional = .{
//             OptArg(u32, "break", "b", 100, "Stop before the limit"),
//         },
//         .flags = .{Flag("verbose", "v", "Print a little, print a lot"),},
//         .commands = .{},
//     };
//
//     const arguments = eaz.parseArgs(allocator, definitions, stdout, stderr) catch |err| {
//         switch (err) {
//             error.HelpShown => {
//                 try stdout.flush();
//             },
//             else => {
//                 try stderr.flush();
//             }
//         }    
//
//         std.process.exit(0);
//     };
//
//     // ------- Proofs of this thing is actually working you know
//     // it's actually a new struct type
//     const T = @TypeOf(arguments);
//     try stdout.print("\n EazyArgs has created a whole new struct with the provided definition.\n", .{});
//     try stdout.print("Type Name: {s}\n", .{@typeName(T)});
//
//     try stdout.print("Let's check the alignment and bytes to make sure:\n", .{});
//     try stdout.print("Size of definition generated struct: {d} bytes\n", .{@sizeOf(T)});
//     try stdout.print("Limit offset: {d}\n", .{@offsetOf(T, "limit")});
//     try stdout.print("Username offset: {d}\n", .{@offsetOf(T, "username")});
//     try stdout.print("Break offset: {d}\n", .{@offsetOf(T, "break")});
//     try stdout.print("Verbose offset: {d}\n", .{@offsetOf(T, "verbose")});
//
//     // proof of names actually being in there
//     const typeInfo = @typeInfo(T);
//     try stdout.print("\n You can loop over all the fields, which whill be the same as in definition \n", .{});
//     inline for (typeInfo.@"struct".fields) |f| {
//        try stdout.print("Field '{s}' is type: {s}\n", .{ f.name, @typeName(f.type) });
//     }
//
//     // struct access
//     try stdout.print("\n Lastly, the values are indeed the provided ones in the terminal\n", .{});
//     try stdout.print("Limit:    {d}\n", .{arguments.limit});
//     try stdout.print("Username: {s}\n", .{arguments.username});
//     try stdout.print("Break: {d}\n", .{arguments.@"break"});
//     try stdout.print("Verbose:  {any}\n", .{arguments.verbose});
//     try stdout.flush();
//
// }
//
pub fn main(init: std.process.Init) !void {
    // var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    // defer _ = gpa.deinit();
    // const allocator = gpa.allocator();
    
    var buffer: [1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &buffer);
    const stdout = &stdout_writer.interface;

    var buferr: [1024]u8 = undefined;
    var stderr_writer = std.Io.File.stdout().writer(init.io, &buferr);
    const stderr = &stderr_writer.interface;
    
    // example1(stdout, stderr);
    
    const definition = .{
        .commands = .{
            .entry = .{ 
                .required = .{ Arg([]const u8, "description", "What are you doing") },
                .optional = .{ OptArg(?usize, "project", "p", null, "Which project does the entry belong")},
            },
            .project = .{
                .commands = .{
                    .create = .{
                        .required = .{ Arg([]const u8, "Name", "Which project is this") },
                        .optional = .{ OptArg(?usize, "subproject", "sp", null, "Child of subprojectid") },
                    }, 
                    .list = .{},
                },
                .flags = .{ Flag("exa,mple", "ex", "Idk") },
            },
        },
        .flags = .{ Flag("verbose", "v", "Print a little, print a lot") }, 
    };    

    // const def_alternative = .{
    //     commands = .{
    //         .entry = .{
    //             Arg([]const u8, "description", "What are you doing"),
    //             OptArg(?usize, "project", "p", null, "Which project does the entry belong"),
    //         },
    //         .project = .{
    //             .commands = .{
    //                 create = .{
    //                     Arg([]const u8, "Name", "Which project is this"),
    //                     OptArg(?usize, "subproject", "sp", null, "Child of subprojectid"),
    //                 },
    //                 list = .{},
    //             },
    //             args = .{ Flag("example", "ex", "idk") },
    //         },
    //     },
    //     args = .{ Flag("verbose", "v", "print") },
    // };
    //
    
    // const arguments = try eaz.parseArgs(allocator, definition, stdout, stderr);
    var args = try init.minimal.args.iterateAllocator(init.arena.allocator()); // this is to make it multiplatform, for now
    const arguments = eaz.parseArgs(definition, &args, stdout, stderr) catch |err| {
        switch (err) {
            ParseErrors.HelpShown => try stdout.flush(),
            ParseErrors.UnexpectedArgument => {try stderr.writeAll("Error"); try stderr.flush(); },

            else => try stderr.flush(),
        }    

        std.process.exit(0);
    };

    try stdout.print("{any}\n", .{arguments});

}


