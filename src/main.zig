const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;

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
    
    
    const gitu_def = .{
        // what's your programs name and what does it do
        .name = "gitu",
        .description = "Gitu - A simple git for example purposes.",
        
        // set global arguments for the whole program
        .flags = .{ Flag("verbose", "v", "Enable verbose logging") },
        .options = .{ Opt([]const u8, "config", "c", "~/.gituconfig", "Path to config file") },

        .commands = .{
            .init = .{ // simple command with 1 positional argument
                .required = .{ Arg([]const u8, "path", "Where to create the repository") },
                .flags = .{ Flag("bare", "b", "Create a bare repository") },
                .description = "Creates a new repository",
            },
            .commit = .{ // just options and flags
                .options = .{ Opt([]const u8, "message", "m", "Default Message", "Commit message") },
                .flags = .{ Flag("amend", "a", "Amend the previous commit") },
                .description = "Commits changes"
            },
            .remote = .{ 
                .commands = .{ // nested subcommands !
                    .add = .{
                        .required = .{  // multiple required args // gitu remote add <name> <url>
                            Arg([]const u8, "name", "Remote name (e.g. origin)"),
                            Arg([]const u8, "url", "Remote URL"),
                        },
                        .options = .{ Opt([]const u8, "track", "t", "master", "Branch to track") },
                        .description = "Add a new remote",
                    },
                    .show = .{
                        .required = .{ Arg([]const u8, "name", "Remote name to inspect") },
                        .description = "Show current remote"
                    },
                },
                .description = "Interacts with the server (remote)",
            },
        },
    };
    
    //convert the args into a slice
    const args = try init.minimal.args.toSlice(init.arena.allocator()); 
    const gnuargs = argz.parseArgs(init.gpa, gitu_def, args, stdout, stderr) catch |err| {
        switch (err) {
            ParseErrors.HelpShown => try stdout.flush(),
            else => try stderr.flush(),
        }    
        std.process.exit(0);
    };
    
    try stdout.print("{any}\n", .{gnuargs});
    // also, you can do it strict posix
    var iter = init.minimal.args.iterate(); 
    const arguments = argz.parseArgsPosix(gitu_def, &iter, stdout, stderr) catch |err| {
        switch (err) {
            ParseErrors.HelpShown => try stdout.flush(),
            else => try stderr.flush(),
        }    
        std.process.exit(0);
    };

    if (arguments.verbose) try stdout.print("[LOG] Verbose is ON\n", .{});
    try stdout.print("[CFG] Config path: {s}\n\n", .{arguments.config});

    // Switch on the Union
    switch (arguments.cmd) {
        .init => |cmd| {
            try stdout.print("COMMAND: INIT\n", .{});
            try stdout.print("Path: {s}\n   Bare: {}\n", .{cmd.path, cmd.bare});
            try inspectType(@TypeOf(cmd), "Init Subcommand", stdout);
        },
        .commit => |cmd| {
            try stdout.print("COMMAND: COMMIT\n", .{});
            try stdout.print("Msg: {s}\n   Amend: {}\n", .{cmd.message, cmd.amend});
            
            try inspectType(@TypeOf(cmd), "Commit Subcommand", stdout);
        },
        .remote => |remote_wrapper| {
            try stdout.print("COMMAND: REMOTE\n", .{});
            
            switch (remote_wrapper.cmd) {
                .add => |cmd| {
                    try stdout.print("\tSUBCOMMAND: ADD\n", .{});
                    try stdout.print("\tName:  {s}\n\tURL:\t{s}\n\tTrack: {s}\n", 
                        .{cmd.name, cmd.url, cmd.track});
                    
                    try inspectType(@TypeOf(cmd), "Remote Add Subcommand", stdout);
                },
                .show => |cmd| {
                    try stdout.print("\tSUBCOMMAND: SHOW\n", .{});
                    try stdout.print("\tName: {s}\n", .{cmd.name});
                    
                    try inspectType(@TypeOf(cmd), "Remote Show Subcommand", stdout);
                },
            }
        },
    }
    try stdout.flush();
}

fn inspectType(comptime T: type, label: []const u8, stdout: *Io.Writer) !void {
    
    try stdout.print("\nMEMORY LAYOUT: {s}\n", .{label});
    try stdout.print("Type Name : {s}\n", .{@typeName(T)});
    try stdout.print("Total Size: {d} bytes\n", .{@sizeOf(T)});
    try stdout.print("Alignment : {d} bytes\n", .{@alignOf(T)});
    
    try stdout.print("Fields:\n", .{});
    const info = @typeInfo(T);
    
    switch (info) {
        .@"struct" => |s| {
            inline for (s.fields) |f| {
                try stdout.print("  - {s:<15} | Type: {s:<15} | Offset: {d}\n", 
                    .{ f.name, @typeName(f.type), @offsetOf(T, f.name) });
            }
        },
        .@"union" => |u| {
            try stdout.print("  (Union Active Tag uses {d} bytes)\n", .{@sizeOf(u.tag_type.?)});
            inline for (u.fields) |f| {
                try stdout.print("  - {s:<15} | Type: {s:<15} | (Shared Memory)\n", 
                    .{ f.name, @typeName(f.type) });
            }
        },
        else => try stdout.print("  (Not a struct or union)\n", .{}),
    }
}



