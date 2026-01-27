const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;

const reification = @import("reification.zig");
const validation = @import("validation.zig");
const structs = @import("structs.zig");

// make the structs public to access them from main
pub const ArgsStruct = reification.ArgsStruct;
pub const Arg = structs.Arg; 
pub const Opt = structs.Opt;
pub const Flag = structs.Flag;

pub const ParseErrors = error { HelpShown, MissingArgument, MissingValue, UnknownArgument, UnexpectedArgument };

/// PUBLIC ENTRY POINT
/// This is what the user calls with the raw OS arguments.
/// It automatically skips argv[0] (the program name).
pub fn parseArgs(comptime definition: anytype, args: []const []const u8, stdout: *Io.Writer, stderr: *Io.Writer) !ArgsStruct(definition) {
    
    // if the user passes just the program name
    if (args.len == 1) {
        try printUsage(definition, stdout);
        return error.HelpShown;
    }

    // call the recursive version to adapt it
    return parseArgsRecursive(definition, args[1..], stdout, stderr);
}

/// The function parses 
/// Rules on the parsing:
/// 1. Each level contains either a positional (required) or a command
/// 2. Once a required argument is found, no other commands can be found. (./pgrm cmd1 req cmd2 -> does not compile)
/// 3. All the required arguments must one after the other (eg ./prgm cmd1 r1, ..., rn, -f1,...,-fm, -o1, ..., -on). The order of required, flags, opt 
///     can be interchangable, and opt/flags can be mixed toghether
/// 4. No flags nor options can be between commands. If a flag/option is specific of a subcommand, add it before the last command.
fn parseArgsRecursive(comptime definition: anytype, args: []const[]const u8, stdout: *Io.Writer, stderr: *Io.Writer) anyerror!ArgsStruct(definition){
    
    if (std.mem.eql(u8, args[0], "help")) {
        try printUsage(definition, stdout);
        return error.HelpShown;
    }
    
    // this will throw a compile error if definition is not valid
    validation.validateDefinition(definition);

    // create the reificated struct, empty and ready to fill 
    const ReArgs: type = ArgsStruct(definition);
    var result: ReArgs = undefined;
    
    // as a standard, we check if a field exists in definition not in result : ReArgs
    // that means @hasField(definition, ...) and NOT @hasField(result, ...)
    const Definition = @TypeOf(definition);
    //const typeInfo = @typeInfo(T);

    const has_flags = @hasField(Definition, "flags");
    const has_optional = @hasField(Definition, "optional");
    // default flags to false
    if (has_flags) {
        inline for (definition.flags) |flag| {
            // we have to fill the struct
            // we are sure that definition IS the same as ReArgs struct
            @field(result, flag.field_name) = false;
        
        }
    }

    // default optionals to their values
    if (has_optional) {
        inline for (definition.optional) |opt| {
            @field(result, opt.field_name) = opt.default_value;
        }
    }
   
    var parsed_required: usize = 0;
    var parsed_flags: usize = 0;
    var parsed_options: usize = 0;
    var i: usize = 0;

    while (i < args.len) : (i += 1) {
        const current_arg = args[i];

        if (@hasField(Definition, "commands")) {
            // get the type of the command field
            // serach in the ReArgs because we are looking for the Union to get which commands
            // have been already defined
            // It could be done in definition.commands and iterate over there but that would waste a part
            // of what has been done in ArgsStruct, where the Enum has been generated
            const CommandUnion = comptime find_cmd: {
                const fields = @typeInfo(ReArgs).@"struct".fields;
                for (fields) |f| {
                    if (std.mem.eql(u8, f.name, "cmd")) {
                        break :find_cmd f.type;
                    }
                }
                unreachable; // if @hasField(definition, "commands") this is unreachable
            };

            const CommandTag = std.meta.Tag(CommandUnion);

            if (std.meta.stringToEnum(CommandTag, current_arg)) |command_tag| {
                // we need to access the definition.commands.@value(current_arg) (eg: def.commands.entry)
                // to do that we cannot use @field because current_arg is not comptime
                // we have to generate all the code for the possible args with the inline else.
                switch (command_tag) {
                    inline else => |tag| {
                        const name: []const u8 = @tagName(tag); // converts the enum into a string
                        const def_subcmd = @field(definition.commands, name);
                        // we know this is a valid command, so we recursively parse the Args 
                        const parsedCmd = try parseArgsRecursive(def_subcmd, args[(i+1)..], stdout, stderr);
                        result.cmd = @unionInit(CommandUnion, name, parsedCmd);              

                        return result;
                    }
                }
            } 
        }
        
        // PSEUDOCODE:
        // 1. We know the argument is not a command. Now, is the value a positional or a flag/option?
        // if (current_arg == flag or option), (according to has_element) parse the value, move on to next iteration
        // else its a required: enter in a loop to parse exactly the required arguments.
        // check how many flags/options are there, should add up to definition.flags.len. if they match we are done
        // else raise error
        if (std.mem.startsWith(u8, current_arg, "-")) {
            var matched = false;
           
            // if some of the arguments is help just return
            if (std.mem.eql(u8, current_arg, "-h") or std.mem.eql(u8, current_arg, "--help")) {
                try printUsage(definition, stdout);
                return error.HelpShown;
            }
           
            const eq_index = std.mem.indexOf(u8, current_arg, "=");
            
            const arg_key = if (eq_index) |idx| current_arg[0..idx] else current_arg;
            const arg_val_inline = if (eq_index) |idx| current_arg[idx+1..] else null;

            if (has_flags) {
                inline for (definition.flags) |flag| {
                    const is_short = std.mem.eql(u8, arg_key, "--" ++ flag.field_name);
                    const is_long = std.mem.eql(u8, arg_key, "-" ++ flag.field_short);

                    if(is_short or is_long) {

                        if (arg_val_inline != null) {
                            try stderr.print("Error: a flag ({s}) cannot take values.\n", .{arg_key});
                            return error.UnexpectedValue;
                        }

                        @field(result, flag.field_name) = true;
                        parsed_flags += 1;
                        matched = true;
                        // nota, aquí un break literalment no fa res.
                        // un inline ens està generant codi, ergo no és un for!
                    }
                }
            }

            if (!matched and @hasField(Definition, "optional")) {
                inline for (definition.optional) |opt| {
                    const is_short = std.mem.eql(u8, arg_key, "--" ++ opt.field_name);
                    const is_long = std.mem.eql(u8, arg_key, "-" ++ opt.field_short);

                    if(is_short or is_long) {
                        // is an --opt=val 
                        if (arg_val_inline) |val| {
                            @field(result, opt.field_name) = try parseValue(opt.type_id, val);
                        } else { // is an --opt val
                           
                            if (i+1 >= args.len) {
                                try stderr.print("Error: Option '{s}' does not have a value\n", .{opt.field_name});
                                return error.MissingValue;
                            }
                       
                            @field(result, opt.field_name) = try parseValue(opt.type_id, args[i+1]);
                            i += 1; 
                            parsed_options += 1;
                            // nota, aquí un break literalment no fa res.
                            // un inline ens està generant codi, ergo no és un for!

                        }
                        
                        matched = true;
                    }
                }
            }
            
            // if the flag/opt was actually found, next arg
            if (matched) continue;

            // here we could add a check like
            // try stderr.print("Error: whateve")
            // return error.UnknownArgument;
        }
    
        // at this point this is uneccessary, validateDefinition guarantees that
        // there is not a command and a required in the same level, but nevertheless..
        if (@hasField(Definition, "required")) {
            if (parsed_required >= definition.required.len) {
                try stderr.print("Error: UnexpectedArgument '{s}'\n", .{current_arg});
                return error.UnexpectedArgument;
            }

            // parse
            inline for (definition.required, 0..) |req, j| {
                if (j == parsed_required) 
                    @field(result, req.field_name) = try parseValue(req.type_id, current_arg);
                    parsed_required += 1;
            }
        } else {
            try stderr.writeAll("Error: catastrofic failure of the validation function. Cry.");
            return error.CatastroficStructure;
        }
        
               
        // some safety checks
        if (has_flags and parsed_flags > definition.flags.len) {
            try stderr.print("Error: Incorrect number of flags detected. Should be at most {d} but are {d}", .{definition.flags.len, parsed_flags});
            return error.InvalidFlags;
        }
        
        if (has_optional and parsed_options > definition.optional.len) {
            try stderr.print("Error: Incorrect number of options detected. Should at most {d} but are {d}", .{definition.optional.len, parsed_options});
            return error.InvalidOptions;
        }

        if (parsed_required != definition.required.len) {
            try stderr.print("Error: Incorrect number of required arguments detected. Should be {d} but are {d}.", .{definition.required.len, parsed_required});
            return error.UnexpertedArgument;
        }
    }
    
    return result;
}

/// parses the values from the command line
fn parseValue(comptime T: type, str: []const u8) !T {
    switch(@typeInfo(T)) {
        .int => return std.fmt.parseInt(T, str, 10),
        .float => return std.fmt.parseFloat(T, str),
        .bool => {
            if (std.mem.eql(u8, str, "true")) { return true; }
            else if (std.mem.eql(u8, str, "false")) { return false; }
            else { return error.InvalidArgument; }
        },
        else => {
            if (T == []const u8) {
                return str;
            }

            return error.UnsupportedType;
        },
    }

    
    return error.UnsupportedType;
}

fn printUsage(comptime definition: anytype, writer: *Io.Writer) !void {
    _ = definition;
    try writer.writeAll("This is the usage that I will definetly do xd\n");
    return;
}

fn OldPrintUsage(comptime definition: anytype, writer: *Io.Writer) !void {
    try writer.writeAll("Usage: app");

    if (@hasField(definition, "optional") and definition.optional.len > 0) {
        try writer.writeAll(" [options]");
    }
    if (@hasField(definition, "flags") and definition.flags.len > 0) {
        try writer.writeAll(" [options]");
    }

    inline for (definition.required) |arg| {
        try writer.print(" <{s}>", .{arg.field_name});
    }
    try writer.print("\n\n", .{});

    if (definition.required.len > 0) {
        try writer.print("Positional Arguments:\n", .{});
        inline for (definition.required) |arg| {
            try writer.print("  {s:<12} ({s}): {s}\n", .{
                arg.field_name,
                @typeName(arg.type_id),
                arg.help,
            });
        }
        try writer.print("\n", .{});
    }

    if (definition.optional.len > 0 or definition.flags.len > 0) {
        try writer.print("Options:\n", .{});

        // Print Options (Key + Value)
        inline for (definition.optional) |arg| {
            // Format: -p, --port <u32>
            try writer.print("  -{s}, --{s:<12} <{s}>: {s} (default: {any})\n", .{
                arg.field_short,
                arg.field_name,
                @typeName(arg.type_id),
                arg.help,
                arg.default_value,
            });
        }

        inline for (definition.flags) |arg| {
            try writer.print("  -{s}, --{s:<12}       : {s}\n", .{
                arg.field_short,
                arg.field_name,
                arg.help,
            });
        }
        try writer.print("\n", .{});
    }
}


const talloc = std.testing.allocator;
const expect = std.testing.expect;
const expectEqualStrings = std.testing.expectEqualStrings;

test "parseValue successful" {
    const p1 = try parseValue(u32, "16");
    try expect(@as(u32, 16) == p1);

    const p2 = try parseValue(u64, "219873");
    try expect(@as(u64, 219873) == p2);

    const p3 = try parseValue(u16, "8");
    try expect(@as(u16, 8) == p3);

    const p4 = try parseValue(i32, "-1");
    try expect(@as(i32, -1) == p4);

    const p5 = try parseValue(usize, "4");
    try expect(@as(usize, 4) == p5);
    
    const p6 = try parseValue(f64, "3.14");
    try expect(@as(f64, 3.14) == p6);

    const p7 = try parseValue(f32, "3");
    try expect(@as(f32, 3) == p7);

    const p8 = try parseValue(bool, "true");
    try expect(true == p8);

    const p9 = try parseValue(bool, "false");
    try expect(false == p9);

    const p10 = try parseValue([]const u8, "quelcom");
    try expectEqualStrings(p10, "quelcom");
}

const expectError = std.testing.expectError;
const ParseFloatError = std.fmt.ParseFloatError;
const ParseIntError = std.fmt.ParseIntError;

test "parseValue errors" {
    try expectError(ParseFloatError.InvalidCharacter, parseValue(f64, "a"));
    try expectError(ParseIntError.Overflow, parseValue(u8, "-1"));
    try expectError(ParseIntError.InvalidCharacter, parseValue(u8, "a"));

    try expectError(error.InvalidArgument, parseValue(bool, "ture"));
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
