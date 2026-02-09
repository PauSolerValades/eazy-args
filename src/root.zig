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
pub const Argument = structs.Argument; 
pub const Option = structs.Option;
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
    validation.validateDefinition(definition, 0);
   
    // if the user passes just the program name
    if (args.len == 1) {
        try parse.printUsage(definition, stdout, args[0]);
        return error.HelpShown;
    }
    const consumed = try gpa.alloc(bool, args.len);
    defer gpa.free(consumed);
    @memset(consumed, false);
    consumed[0] = true;

    const exename = std.fs.path.basename(args[0]);

    const context = parse.ContextNode{ .name = exename };

    // call the recursive version to adapt it
    return gnu.parseArgsRecursive(definition, args, consumed, &context, stdout, stderr);
}

/// POSIX compliant argument parsing (https://pubs.opengroup.org/onlinepubs/9699919799/basedefs/V1_chap12.html)
/// Summay: utilty [-flags] [-options p] [-a|-b] [-f[option_arg]] [required] (TBD: or is not implemented, nor the [ ])
/// The restricivity of POSIX forces the flags of the commands to be exactly after the command (git -v init "path" if v is defined
/// as an application flag). The advantage is that the parsing algorithm is exactly $O(n)$ where n is the number of arguments in args.
/// This also allows us to use an Args.Iterator with no dynamic memory (not in Windows tho)
pub fn parseArgsPosix(comptime definition: anytype, args: *Args.Iterator, stdout: *Io.Writer, stderr: *Io.Writer) anyerror!Reify(definition) {
    
    validation.validateDefinition(definition, 0);
    
    // _ = args.skip(); // skip the program name
    const program_name = args.next();
    
    if (program_name) |name| {
        const context = parse.ContextNode{ .name = name };

        return posix.parseArgsPosixRecursive(definition, args, &context, stdout, stderr);
    } 

    try parse.printUsageCtx(definition, null, stdout);
    return error.HelpShown;

}


const testing = std.testing;
const ta = testing.allocator; 
const tio = testing.io;
var w = std.Io.File.stdout().writer(tio, &.{});
const nullout = &w.interface;
const IteratorGeneral = std.process.Args.IteratorGeneral;

const Arg = structs.Argument; 
const Opt = structs.Option;


test "Normal parsing: required, flags, options" {
    const def = .{
        .required = .{ Arg(u32, "count", "The number of items") },
        .flags = .{ Flag("verbose", "v", "Enable verbose output") },
        .options = .{ Opt([]const u8, "mode", "m", "default", "Operation mode") },
    };
    // GNU "pgm 42 -v --mode fast" 
    {
        const args = &[_][]const u8{ "pgm", "42", "-v", "--mode", "fast" };
        const result = try parseArgs(ta, def, args, nullout, nullout);

        try testing.expectEqual(@as(u32, 42), result.count);
        try testing.expectEqual(true, result.verbose);
        try testing.expectEqualStrings("fast", result.mode);
    }
    // GNU "pgm -v 42 --mode fast"
    {
        const args = &[_][]const u8{ "pgm", "-v", "42", "--mode", "fast" };
        const result = try parseArgs(ta, def, args, nullout, nullout);

        try testing.expectEqual(@as(u32, 42), result.count);
        try testing.expectEqual(true, result.verbose);
        try testing.expectEqualStrings("fast", result.mode);
    }
}

test "Normal parsing: 2 args, 2 flags, 2 options" {
    const def = .{
        .required = .{
            Arg(u32, "count", "Number of items to process"),
            Arg(f64, "scale", "Scaling factor to apply"),
        },
        .flags = .{
            Flag("verbose", "v", "Enable verbose output"),
            Flag("dryrun", "d", "Run without making changes"),
        },
        .options = .{
            Opt([]const u8, "mode", "m", "standard", "Operation mode"),
            Opt(i32, "threshold", "t", 10, "Numeric threshold"),
        },
    };
    
    // "pgm 42 1.5 -v -d --mode fast --threshold 25"
    {
        const args = &[_][]const u8{
            "pgm",
            "42",
            "1.5",
            "-v",
            "-d",
            "--mode", "fast",
            "--threshold", "25",
        };

        const result = try parseArgs(ta, def, args, nullout, nullout);

        try testing.expectEqual(@as(u32, 42), result.count);
        try testing.expectEqual(@as(f64, 1.5), result.scale);
        try testing.expectEqual(true, result.verbose);
        try testing.expectEqual(true, result.dryrun);
        try testing.expectEqualStrings("fast", result.mode);
        try testing.expectEqual(@as(i32, 25), result.threshold);
    }
    // "pgm 42 1.5 -v -d"
    {
        const args = &[_][]const u8{
            "pgm",
            "42",
            "1.5",
            "-v",
            "-d",
        };

        const result = try parseArgs(ta, def, args, nullout, nullout);

        try testing.expectEqual(@as(u32, 42), result.count);
        try testing.expectEqual(@as(f64, 1.5), result.scale);
        try testing.expectEqual(true, result.verbose);
        try testing.expectEqual(true, result.dryrun);
    }
    // "pgm 42 1.5 --mode fast --threshold 25"
    {
        const args = &[_][]const u8{
            "pgm",
            "42",
            "1.5",
            "--mode", "fast",
            "--threshold", "25",
        };

        const result = try parseArgs(ta, def, args, nullout, nullout);

        try testing.expectEqual(@as(u32, 42), result.count);
        try testing.expectEqual(@as(f64, 1.5), result.scale);
        try testing.expectEqualStrings("fast", result.mode);
        try testing.expectEqual(@as(i32, 25), result.threshold);
    }
    // MISSING ONE REQUIRED "pgm 42 -v -d --mode fast --threshold 25"
    {
        const args = &[_][]const u8{
            "pgm",
            "42",
            "-v",
            "-d",
            "--mode", "fast",
            "--threshold", "25",
        };


        try testing.expectError(error.MissingRequired, parseArgs(ta, def, args, nullout, nullout));
    }
    // NO REQUIREDS "pgm -v -d --mode fast -- threshold 25"
    {
        const args = &[_][]const u8{
            "pgm",
            "-v",
            "-d",
            "--mode", "fast",
            "--threshold", "25",
        };

        try testing.expectError(error.MissingRequired, parseArgs(ta, def, args, nullout, nullout));
    }
}


test "Parsing optional with ?type" {
    const entry_start = .{
        .required = .{ Arg([]const u8, "description", "What are you doing now?") },
        // Corrected: Name "projectid", Short "p"
        .options = .{ Opt(?u64, "projectid", "p", null, "Which project the entry belongs to")}
    };

    const def = .{
        .flags = .{ Flag("verbose", "v", "Print more" ) },
        .commands = .{
            .entry = .{
                .commands = .{
                    .start = entry_start,
                    .stop = .{},
                    .status = .{},
                }
            },
        }
    };
    // "tally entry start 'hello' -p 1"
    {
        const args = &[_][]const u8{ "tally", "entry", "start", "hello", "-p", "1" };
        const result = try parseArgs(ta, def, args, nullout, nullout);

        try testing.expectEqual(false, result.verbose);

        try testing.expect(result.cmd == .entry);
        try testing.expect(result.cmd.entry.cmd == .start);

        const start_cmd = result.cmd.entry.cmd.start;
        try testing.expectEqualStrings("hello", start_cmd.description);

        try testing.expect(start_cmd.projectid != null);
        try testing.expectEqual(@as(u64, 1), start_cmd.projectid.?);
    }
    // "tally entry start 'meeting'"
    {
        const args = &[_][]const u8{ "tally", "entry", "start", "meeting" };
        const result = try parseArgs(ta, def, args, nullout, nullout);

        const start_cmd = result.cmd.entry.cmd.start;
        try testing.expectEqualStrings("meeting", start_cmd.description);
        
        // Check that it is null
        try testing.expect(start_cmd.projectid == null);
    }
}

test "Two subcommands with shared definition" {
    const subdef = .{
        .required = .{ Arg(u32, "id", "Resource ID") },
        .flags = .{ Flag("force", "f", "Force operation") },
        .options = .{ Opt(u32, "retry", "r", 1, "Number of retries") },
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
        const result = try parseArgs(ta, def, args, nullout, nullout);

        try testing.expect(result.cmd == .delete); 
        // Verify values inside delete
        try testing.expectEqual(@as(u32, 100), result.cmd.delete.id);
        try testing.expectEqual(true, result.cmd.delete.force);
        try testing.expectEqual(@as(u32, 1), result.cmd.delete.retry); // Default value
    }

    // "update 50 -r 5"
    {
        const args = &[_][]const u8{ "pgm","update", "50", "-r", "5" };
        const result = try parseArgs(ta, def, args, nullout, nullout);

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
        .options = .{ Opt([]const u8, "user", "u", "admin", "User name") },
    };

    const args = &[_][]const u8{ "pgm","-g", "commit", "--amend", "fix bug" };
    
    const result = try parseArgs(ta, def, args, nullout, nullout);

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
    
    const result = try parseArgs(ta, def, args, nullout, nullout);
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
        const args = &[_][]const u8{ "pgm", "-h" };
        try testing.expectError(error.HelpShown, parseArgs(ta, def, args, nullout, nullout));
    }
    // "--help"
    {
        const args = &[_][]const u8{ "pgm", "--help" };
        try testing.expectError(error.HelpShown, parseArgs(ta, def, args, nullout, nullout));
    }
    //"help" (as a command/argument)
    {
        const args = &[_][]const u8{ "pgm", "help" };
        try testing.expectError(error.HelpShown, parseArgs(ta, def, args, nullout, nullout));
    }
    // empty args
    {
        const args = &[_][]const u8{"pgm"};
        try testing.expectError(error.HelpShown, parseArgs(ta, def, args, nullout, nullout));
    }
}

// "123 --mode=fast --count 5 -v"
test "Mixed assignment styles (= vs space)" {
    const def = .{
        .required = .{ Arg(u32, "id", "Resource ID") },
        .options = .{
            Opt([]const u8, "mode", "m", "default", "Operation mode"),
            Opt(u32, "count", "c", 1, "Item count"),
        },
        .flags = .{ Flag("verbose", "v", "Enable verbose") },
    };

    const args = &[_][]const u8{ "pgm", "123", "--mode=fast", "--count", "5", "-v" };
    const result = try parseArgs(ta, def, args, nullout, nullout);

    try testing.expectEqual(@as(u32, 123), result.id);
    try testing.expectEqualStrings("fast", result.mode);
    try testing.expectEqual(@as(u32, 5), result.count);
    try testing.expectEqual(true, result.verbose);
}


test {
    _ = @import("validation.zig");
    _ = @import("parse.zig");
}

test "POSIX: Normal parsing (Flags, Options, Required)" {
    const def = .{
        .required = .{ Arg(u32, "count", "The number of items") },
        .flags = .{ Flag("verbose", "v", "Enable verbose output") },
        .options = .{ Opt([]const u8, "mode", "m", "default", "Operation mode") },
    };

    // "pgm -v -m fast 42"
    {
        const fake_argv = &[_][*:0]const u8{ "pgm", "-v", "-m", "fast", "42"};
        const args = Args{ .vector = fake_argv }; 
        var iter = Args.Iterator.init(args);

        const result = try parseArgsPosix(def, &iter, nullout, nullout);
        
        try testing.expectEqual(@as(u32, 42), result.count);
        try testing.expectEqual(true, result.verbose);
        try testing.expectEqualStrings("fast", result.mode);
    }
    // "pgm --mode fast -v 42"
    {
        const fake_argv = &[_][*:0]const u8{ "pgm", "--mode", "fast", "-v", "42"};
        const args = Args{ .vector = fake_argv }; 
        var iter = Args.Iterator.init(args);

        const result = try parseArgsPosix(def, &iter, nullout, nullout);
        
        try testing.expectEqual(@as(u32, 42), result.count);
        try testing.expectEqual(true, result.verbose);
        try testing.expectEqualStrings("fast", result.mode);
    }
    // "pgm 42 -v"
    {
        const fake_argv = &[_][*:0]const u8{ "pgm", "42", "-v"};
        const args = Args{ .vector = fake_argv }; 
        var iter = Args.Iterator.init(args);

        // and then fail when it sees '-v'
        try testing.expectError(error.InvalidPosix, parseArgsPosix(def, &iter, nullout, nullout));
    }
    // "pgm 42 --mode fast"
    {
        const fake_argv = &[_][*:0]const u8{ "pgm", "42", "--mode", "fast"};
        const args = Args{ .vector = fake_argv }; 
        var iter = Args.Iterator.init(args);

        try testing.expectError(error.InvalidPosix, parseArgsPosix(def, &iter, nullout, nullout));
    }
}

test "POSIX: invalid '='" {
    const def = .{
        .required = .{ Arg(u32, "id", "ID") },
        .options = .{ Opt([]const u8, "mode", "m", "default", "Mode") },
    };
    // "pgm --mode=fast 123"
    {
        const fake_argv = &[_][*:0]const u8{ "pgm", "--mode=fast", "123" };
        const args = Args{ .vector = fake_argv }; 
        var iter = Args.Iterator.init(args);

        try testing.expectError(error.InvalidPosix, parseArgsPosix(def, &iter, nullout, nullout));
    }
}

test "POSIX: Subcommands" {
    const subdef = .{
        .required = .{ Arg(u32, "id", "Resource ID") },
        .flags = .{ Flag("force", "f", "Force operation") },
        .options = .{ Opt(u32, "retry", "r", 1, "Number of retries") },
    };

    const def = .{
        .commands = .{
            .delete = subdef,
            .update = subdef,
        },
    };

    // "pgm delete -f 100" (Flag before ID)
    {
        const fake_argv = &[_][*:0]const u8{ "pgm", "delete", "-f", "100" };
        const args = Args{ .vector = fake_argv }; 
        var iter = Args.Iterator.init(args);

        const result = try parseArgsPosix(def, &iter, nullout, nullout);

        try testing.expect(result.cmd == .delete); 
        try testing.expectEqual(@as(u32, 100), result.cmd.delete.id);
        try testing.expectEqual(true, result.cmd.delete.force);
    }

    // FAIL: "pgm delete 100 -f" (Flag after ID)
    {
        const fake_argv = &[_][*:0]const u8{ "pgm", "delete", "100", "-f" };
        const args = Args{ .vector = fake_argv }; 
        var iter = Args.Iterator.init(args);

        // Error happens inside the subcommand parser recursion
        try testing.expectError(error.InvalidPosix, parseArgsPosix(def, &iter, nullout, nullout));
    }
}

test "POSIX: Multi-level Commands and Globals" {
    // Structure: pgm [global_flags] [command] [cmd_flags] [required]
    const def = .{
        .commands = .{
            .commit = .{
                .required = .{ Arg([]const u8, "msg", "Commit message") },
                .flags = .{ Flag("amend", "a", "Amend previous commit") },
            },
        },
        .flags = .{ Flag("git-dir", "g", "Use custom git dir") },
        .options = .{ Opt([]const u8, "user", "u", "admin", "User name") },
    };
    // "pgm -g commit --amend 'fix bug'"
    {
        const fake_argv = &[_][*:0]const u8{ "pgm", "-g", "commit", "--amend", "fix bug" };
        const args = Args{ .vector = fake_argv }; 
        var iter = Args.Iterator.init(args);

        const result = try parseArgsPosix(def, &iter, nullout, nullout);

        // Check Global
        try testing.expectEqual(true, result.@"git-dir");
        try testing.expect(result.cmd == .commit);
        
        // Check Command Specific
        try testing.expectEqual(true, result.cmd.commit.amend);
        try testing.expectEqualStrings("fix bug", result.cmd.commit.msg);
    }
    
    // FAIL: Global flag placed INSIDE subcommand
    // "pgm commit -g 'fix bug'"
    {
        const fake_argv = &[_][*:0]const u8{ "pgm", "commit", "-g", "fix bug" };
        const args = Args{ .vector = fake_argv }; 
        var iter = Args.Iterator.init(args);

        // The subcommand 'commit' does NOT know about '-g'. 
        // It will try to parse '-g' as the required 'msg' (if type matches) or fail flags check.
        // Since 'msg' is a string, it might actually parse "-g" as the message!
        // Let's check what happens:
        const result = parseArgsPosix(def, &iter, nullout, nullout);
        
        try testing.expectError(error.InvalidPosix, result);
        // It successfully parses, but the logic is wrong from a user perspective.
        // The commit message becomes "-g".
        // try testing.expectEqualStrings("-g", result.cmd.commit.msg);
    }
}

test "POSIX: Help Detection" {
    const def = .{ .required = .{ Arg(u32, "num", "A number") } };
    // "-h"
    {
        const fake_argv = &[_][*:0]const u8{ "pgm", "-h" };
        const args = Args{ .vector = fake_argv }; 
        var iter = Args.Iterator.init(args);
        try testing.expectError(error.HelpShown, parseArgsPosix(def, &iter, nullout, nullout));
    }
    // "--help"
    {
        const fake_argv = &[_][*:0]const u8{ "pgm", "--help" };
        const args = Args{ .vector = fake_argv }; 
        var iter = Args.Iterator.init(args);
        try testing.expectError(error.HelpShown, parseArgsPosix(def, &iter, nullout, nullout));
    }
    {
        const fake_argv = &[_][*:0]const u8{ "pgm", "help" };
        const args = Args{ .vector = fake_argv }; 
        var iter = Args.Iterator.init(args);
        try testing.expectError(error.HelpShown, parseArgsPosix(def, &iter, nullout, nullout));
    }
    // Empty args (Help shown because required arg missing)
    {
        const fake_argv = &[_][*:0]const u8{ "pgm" };
        const args = Args{ .vector = fake_argv }; 
        var iter = Args.Iterator.init(args);
        // This fails at the END of validation because 'num' is missing
        try testing.expectError(error.HelpShown, parseArgsPosix(def, &iter, nullout, nullout));
    }
}

test "POSIX: mixed flags" {
    const def = .{ .flags = .{
        Flag("all", "a", "all"),
        Flag("almostall", "A", "Almost all"),
        Flag("list", "l", "Listl"),
        Flag("time", "t", "Sort by time"),
        },
    };
    {
        const fake_argv = &[_][*:0]const u8{ "pgm", "-aAlt" };
        const args = Args{ .vector = fake_argv }; 
        var iter = Args.Iterator.init(args);
        
        const result = try parseArgsPosix(def, &iter, nullout, nullout);
        
        try testing.expectEqual(true, result.all);
        try testing.expectEqual(true, result.almostall);
        try testing.expectEqual(true, result.list);
        try testing.expectEqual(true, result.time);

    }
    {
        const fake_argv = &[_][*:0]const u8{ "pgm", "-aA" };
        const args = Args{ .vector = fake_argv }; 
        var iter = Args.Iterator.init(args);
        
        const result = try parseArgsPosix(def, &iter, nullout, nullout);
        
        try testing.expectEqual(true, result.all);
        try testing.expectEqual(true, result.almostall);
        try testing.expectEqual(false, result.list);
        try testing.expectEqual(false, result.time);
    }

    {
        const fake_argv = &[_][*:0]const u8{ "pgm", "-A" };
        const args = Args{ .vector = fake_argv }; 
        var iter = Args.Iterator.init(args);
        
        const result = try parseArgsPosix(def, &iter, nullout, nullout);
        
        try testing.expectEqual(false, result.all);
        try testing.expectEqual(true, result.almostall);
        try testing.expectEqual(false, result.list);
        try testing.expectEqual(false, result.time);
    }
}

test "POSIX: mixed attached and separated options" {
    const def = .{ 
        .options = .{ 
            Opt(u64, "port", "p", 8080, "Port"), 
            Opt([]const u8, "ip", "i", "127.0.0.1", "IP address") // Added a default
        },
    };

    {
        const fake_argv = &[_][*:0]const u8{ "pgm", "-ilocalhost" };
        const args = Args{ .vector = fake_argv }; 
        var iter = Args.Iterator.init(args);
        
        const result = try parseArgsPosix(def, &iter, nullout, nullout);
        
        try std.testing.expectEqualStrings("localhost", result.ip);
        try std.testing.expectEqual(@as(u64, 8080), result.port); // Default check
    }

    {
        const fake_argv = &[_][*:0]const u8{ "pgm", "-p3000", "-i", "192.168.1.1" };
        const args = Args{ .vector = fake_argv }; 
        var iter = Args.Iterator.init(args);
        
        const result = try parseArgsPosix(def, &iter, nullout, nullout);
        
        try std.testing.expectEqual(@as(u64, 3000), result.port);
        try std.testing.expectEqualStrings("192.168.1.1", result.ip);
    }

    {
        const fake_argv = &[_][*:0]const u8{ "pgm", "-i10.0.0.5", "--port", "9090" };
        const args = Args{ .vector = fake_argv }; 
        var iter = Args.Iterator.init(args);
        
        const result = try parseArgsPosix(def, &iter, nullout, nullout);
        
        try std.testing.expectEqualStrings("10.0.0.5", result.ip);
        try std.testing.expectEqual(@as(u64, 9090), result.port);
    }

    {
        const fake_argv = &[_][*:0]const u8{ "pgm", "-p443", "-igoogle.com" };
        const args = Args{ .vector = fake_argv }; 
        var iter = Args.Iterator.init(args);
        
        const result = try parseArgsPosix(def, &iter, nullout, nullout);
        
        try std.testing.expectEqual(@as(u64, 443), result.port);
        try std.testing.expectEqualStrings("google.com", result.ip);
    }
}

test "POSIX: Conflict - Attached Option vs Flag Bundle" {
    const def = .{
        .flags = .{ 
            Flag("verbose", "v", "Enable verbose output") 
        },
        .options = .{ 
            Opt(u64, "port", "p", 8080, "Port") 
        },
    };


    // 2. Pass an attached option (-p80)
    // If the parser thinks this is a flag bundle, it will try to find a flag named 'p'.
    // It won't find it (since 'p' is an option), and it will crash.
    const fake_argv = &[_][*:0]const u8{ "pgm", "-p80" };
    
    const args = Args{ .vector = fake_argv }; 
    var iter = Args.Iterator.init(args);
    
    // 3. This will FAIL if Flags are parsed before Options
    const result = try parseArgsPosix(def, &iter, nullout, nullout);
    
    try std.testing.expectEqual(@as(u64, 80), result.port);
    try std.testing.expectEqual(false, result.verbose);
}

