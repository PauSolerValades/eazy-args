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
    
    const entry_start = .{
        .required = .{ Arg([]const u8, "description", "What are you doing now?") },
        .options = .{ Opt(?u64, "projectid", "p", null, "Which project the entry belongs to")}
    };

    const project_create = .{
        .required = .{ Arg([]const u8, "description", "What project are you doing") },
        .options = .{ Opt(?u64, "parent", "p", null, "Which project is this under?")}
    };

    const project_rename = .{
        .required = .{ 
            Arg(u64, "projectid", "Project to change the name"),
            Arg([]const u8, "name", "New name for the project"),
        }
    };

 
    const def = .{
        .flags = .{ Flag("verbose", "v", "Print more" ) },
        .commands = .{
            .entry = .{
                .commands = .{
                .start = entry_start,
                .status = .{},
                .stop = .{},

                }
            },
            .project = .{
                .commands = .{
                    .create = project_create,
                    .rename = project_rename,
                }
            },
        }
    };

        
    const args = try init.minimal.args.toSlice(init.gpa);
    defer init.gpa.free(args);
    const arguments = argz.parseArgs(init.gpa, def, args, stdout, stderr) catch |err| {
        switch (err) {
            ParseErrors.HelpShown => try stdout.flush(),
            else => try stderr.flush(),
        }
        std.process.exit(0);
    };
    
    try stdout.print("Arguments: {any}\n", .{arguments});
    
    // access it with a switch, clean and easy (args haha)
    switch (arguments.cmd) {
        .entry => |entry_cmd| {
            switch (entry_cmd.cmd) {
                .start => |start_args| {
                    try stdout.print("'entry start' detected!\n", .{});
                    if (start_args.projectid) |pid| {
                        try stdout.print("Detected pid: {d}\n", .{pid});
                    } else {
                        try stdout.writeAll("No pid detected\n");
                    }
                },
                .stop => try stdout.writeAll("'entry stop' detected!\n"),
                .status => try stdout.writeAll("'entry status' detected!\n"),
            }
        },
        .project => |project_cmd| {
            switch (project_cmd.cmd) {
                .create => |create_args| {
                     try stdout.print("Creating project: {s}\n", .{create_args.description});
                },
                .rename => |rename_args| {
                     try stdout.print("Renaming ID {d} to {s}\n", .{rename_args.projectid, rename_args.name});
                }
            } 
        }
    }

    try stdout.flush();
}
