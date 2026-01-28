const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;
const Args = std.process.Args;

const reification = @import("reification.zig");
const validation = @import("validation.zig");
const structs = @import("structs.zig");
const gnu = @import("gnu_parse.zig");
const posix = @import("posix_parse.zig");
const parse = @import("parse.zig");

// make the structs public to access them from main
pub const Reify = reification.Reify;
pub const Arg = structs.Arg; 
pub const Opt = structs.Opt;
pub const Flag = structs.Flag;
pub const ParseErrors = parse.ParseErrors;


/// GNU "freestyle" parsing implementation. Options and flags can be expressed in any point of the command line, 
/// regardless in which nested level is the option or flag defined.
/// The trade-off for flexibility are (1) the use of a consumed (allocated) mask to keep track of which option has been parsed
/// (2) makes at most 3 iterations per every level of the definition to make sure none is skipped (roughly $O(3*n)$
/// times all the subcommands (m_i) and its depth (nested subcommands) (3) copy of args in dynamic memory to be able to iterate 
/// over the list several times.
/// TBD: fully compliance with the GNU Parsing Arguments (26.1.1 of https://sourceware.org/glibc/manual/latest/html_mono/libc.html#Program-Arguments)
/// That is (1) long and short flags (2) equal to set the value options (3) finishes by -- (4) multiple flags provided (what actually happens?)
pub fn parseArgs(gpa: Allocator, comptime definition: anytype, args: []const []const u8, stdout: *Io.Writer, stderr: *Io.Writer) !Reify(definition) {
   
    // this will throw a compile error if definition is not valid
    validation.validateDefinition(definition);
   
    // if the user passes just the program name
    if (args.len == 1) {
        try parse.printUsage(definition, stdout);
        return error.HelpShown;
    }
    const consumed = try gpa.alloc(bool, args.len);
    defer gpa.free(consumed);
    @memset(consumed, false);
    consumed[0] = true;

    // call the recursive version to adapt it
    return gnu.parseArgsRecursive(definition, args, consumed, stdout, stderr);
}

/// POSIX compliant argument parsing (https://pubs.opengroup.org/onlinepubs/9699919799/basedefs/V1_chap12.html)
/// Summay: utilty [-flags] [-options p] [-a|-b] [-f[option_arg]] [required] (TBD: or is not implemented, nor the [ ])
/// The restricivity of POSIX forces the flags of the commands to be exactly after the command (git -v init "path" if v is defined
/// as an application flag). The advantage is that the parsing algorithm is exactly $O(n)$ where n is the number of arguments in args.
/// This also allows us to use an Args.Iterator with no dynamic memory (not in Windows tho)
pub fn parseArgsPosix(comptime definition: anytype, args: *Args.Iterator, stdout: *Io.Writer, stderr: *Io.Writer) anyerror!Reify(definition) {
    
    validation.validateDefinition(definition);
    
    _ = args.skip(); // skip the program name

    if (!args.skip()) {
        try parse.printUsage(definition, stdout);
        return error.HelpShown;
    }

    
    return posix.parseArgsPosixRecursive(definition, args, stdout, stderr);
}


const testing = std.testing;
const tio = testing.io;
var w = std.Io.File.stdout().writer(tio, &.{});
const nullout = &w.interface;

test "Normal parsing: required, flags, optional" {
    const def = .{
        .required = .{ Arg(u32, "count", "The number of items") },
        .flags = .{ Flag("verbose", "v", "Enable verbose output") },
        .optional = .{ Opt([]const u8, "mode", "m", "default", "Operation mode") },
    };

    const args = &[_][]const u8{ "pgm", "42", "-v", "--mode", "fast" };
    const result = try parseArgs(def, args, nullout, nullout);

    try testing.expectEqual(@as(u32, 42), result.count);
    try testing.expectEqual(true, result.verbose);
    try testing.expectEqualStrings("fast", result.mode);
}

test "Two subcommands with shared definition" {
    const subdef = .{
        .required = .{ Arg(u32, "id", "Resource ID") },
        .flags = .{ Flag("force", "f", "Force operation") },
        .optional = .{ Opt(u32, "retry", "r", 1, "Number of retries") },
    };

    const def = .{
        .commands = .{
            .delete = subdef,
            .update = subdef,
        },
    };

    // "delete 100 --force"
    {
        const args = &[_][]const u8{ "pgm","delete", "100", "--force" };
        const result = try parseArgs(def, args, nullout, nullout);

        try testing.expect(result.cmd == .delete); 
        // Verify values inside delete
        try testing.expectEqual(@as(u32, 100), result.cmd.delete.id);
        try testing.expectEqual(true, result.cmd.delete.force);
        try testing.expectEqual(@as(u32, 1), result.cmd.delete.retry); // Default value
    }

    // "update 50 -r 5"
    {
        const args = &[_][]const u8{ "pgm","update", "50", "-r", "5" };
        const result = try parseArgs(def, args, nullout, nullout);

        try testing.expect(result.cmd == .update);
        try testing.expectEqual(@as(u32, 50), result.cmd.update.id);
        try testing.expectEqual(false, result.cmd.update.force);
        try testing.expectEqual(@as(u32, 5), result.cmd.update.retry);
    }
}

// "-g commit --amend 'fix bug'"
test "Subcommands with options/flags at multiple levels" {
    const def = .{
        .commands = .{
            .commit = .{
                .required = .{ Arg([]const u8, "msg", "Commit message") },
                .flags = .{ Flag("amend", "a", "Amend previous commit") },
            },
        },
        .flags = .{ Flag("git-dir", "g", "Use custom git dir") },
        .optional = .{ Opt([]const u8, "user", "u", "admin", "User name") },
    };

    const args = &[_][]const u8{ "pgm","-g", "commit", "--amend", "fix bug" };
    
    const result = try parseArgs(def, args, nullout, nullout);

    try testing.expectEqual(true, result.@"git-dir");
    try testing.expectEqualStrings("admin", result.user);

    try testing.expect(result.cmd == .commit);

    try testing.expectEqual(true, result.cmd.commit.amend);
    try testing.expectEqualStrings("fix bug", result.cmd.commit.msg);
}

test "Two nested subcommands" {
    const def = .{
        .commands = .{
            .cloud = .{
                .commands = .{
                    .server = .{
                        .commands = .{
                            .create = .{
                                .flags = .{ Flag("dry-run", "d", "Simulate") },
                                .required = .{ Arg([]const u8, "name", "Server Name") },
                            }
                        }
                    }
                }
            }
        }
    };

    const args = &[_][]const u8{ "pgm","cloud", "server", "create", "--dry-run", "my-web-app" };
    
    const result = try parseArgs(def, args, nullout, nullout);
    try testing.expect(result.cmd == .cloud);
    try testing.expect(result.cmd.cloud.cmd == .server);
    try testing.expect(result.cmd.cloud.cmd.server.cmd == .create);
    
    const final_cmd = result.cmd.cloud.cmd.server.cmd.create;
    try testing.expectEqual(true, final_cmd.@"dry-run");
    try testing.expectEqualStrings("my-web-app", final_cmd.name);
}

test "Help shown" {
    const def = .{
        .required = .{ Arg(u32, "num", "A number") },
    };
        
    // "-h"
    {
        const args = &[_][]const u8{ "pgm","-h" };
        // We expect parseArgs to return the error `HelpShown`
        try testing.expectError(error.HelpShown, parseArgs(def, args, nullout, nullout));
    }
    // "--help"
    {
        const args = &[_][]const u8{ "pgm","--help" };
        // We expect parseArgs to return the error `HelpShown`
        try testing.expectError(error.HelpShown, parseArgs(def, args, nullout, nullout));
    }

    //"help" (as a command/argument)
    {
        const args = &[_][]const u8{ "pgm","help" };
        try testing.expectError(error.HelpShown, parseArgs(def, args, nullout, nullout));
    }
    // empty args
    {
        const args = &[_][]const u8{"pgm"};
        try testing.expectError(error.HelpShown, parseArgs(def, args, nullout, nullout));
    }
}

// "123 --mode=fast --count 5 -v"
test "Mixed assignment styles (= vs space)" {
    const def = .{
        .required = .{ Arg(u32, "id", "Resource ID") },
        .optional = .{
            Opt([]const u8, "mode", "m", "default", "Operation mode"),
            Opt(u32, "count", "c", 1, "Item count"),
        },
        .flags = .{ Flag("verbose", "v", "Enable verbose") },
    };

    const args = &[_][]const u8{ "pgm", "123", "--mode=fast", "--count", "5", "-v" };
    const result = try parseArgs(def, args, nullout, nullout);

    try testing.expectEqual(@as(u32, 123), result.id);
    try testing.expectEqualStrings("fast", result.mode);
    try testing.expectEqual(@as(u32, 5), result.count);
    try testing.expectEqual(true, result.verbose);
}
