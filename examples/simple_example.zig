const std = @import("std");

const argz = @import("eazy_args");

const Arg = argz.Argument;
const Opt = argz.Option;
const Flag = argz.Flag;
const ParseErrors = argz.ParseErrors;

pub fn main(init: std.process.Init) !void {

    var buffer: [1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &buffer);
    const stdout = &stdout_writer.interface;
    
    var buferr: [1024]u8 = undefined;
    var stderr_writer = std.Io.File.stdout().writer(init.io, &buferr);
    const stderr = &stderr_writer.interface;
 
    const definition = .{
        .required = .{ // type, field name, description
            Arg(u32, "limit", "Limits are meant to be broken"),
            Arg([]const u8, "username", "Who are you?"),
        },
        .options = .{ // type, field_name, short, default, description
            Opt(u32, "break", "b", 100, "Stop before the limit"),
            Opt(f64, "step", "s", 1.0, "Subdivision of the interval"),
        },
        .flags = .{ // field_name, short, description - default is false
            Flag("verbose", "v", "More info"),
            Flag("optimization", "o", "Go faster, but at what cost?"),
        }
    };
    
    // call GNU freestyle parser
    const args = try init.minimal.args.toSlice(init.gpa); 
    defer init.gpa.free(args);
    const gnuargs = argz.parseArgs(init.gpa, definition, args, stdout, stderr) catch |err| {
        switch (err) {
            ParseErrors.HelpShown => try stdout.flush(),
            else => try stderr.flush(),
        }    
        std.process.exit(0);
    };
    
    try stdout.print("Parsed with GNU:\n {any}\n", .{gnuargs});

    // // call the posix parser function. No allocator needed (not in windows tho)
    // var iter = init.minimal.args.iterate(); 
    // const posixargs = argz.parseArgsPosix(definition, &iter, stdout, stderr) catch |err| {
    //     switch (err) {
    //         ParseErrors.HelpShown => try stdout.flush(),
    //         else => try stderr.flush(),
    //     }
    //     std.process.exit(0);
    // };
    //
    // try stdout.print("Parsed with POSIX:\n {any}\n", .{posixargs});
    try stdout.flush();
}
