const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;
const Args = std.process.Args;

const reification = @import("reification.zig");
const validation = @import("validation.zig");

// make the structs public to access them from main
pub const ArgsStruct = reification.ArgsStruct;
pub const Arg = reification.Arg; 
pub const OptArg = reification.OptArg;
pub const Flag = reification.Flag;

pub const ParseErrors = error { HelpShown, MissingArgument, MissingValue, UnknownArgument, UnexpectedArgument };

/// The function parses 
/// Rules on the parsing:
/// 1. Each level contains either a positional (required) or a command
/// 2. Once a required argument is found, no other commands can be found. (./pgrm cmd1 req cmd2 -> does not compile)
/// 3. All the required arguments must one after the other (eg ./prgm cmd1 r1, ..., rn, -f1,...,-fm, -o1, ..., -on). The order of required, flags, opt 
///     can be interchangable, and opt/flags can be mixed toghether
/// 4. No flags nor options can be between commands. If a flag/option is specific of a subcommand, add it before the last command.
pub fn parseArgs(comptime definition: anytype, args: []const[]const u8, stdout: *Io.Writer, stderr: *Io.Writer) anyerror!ArgsStruct(definition){

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
                    if (std.mem.eql(u8, f.name, "command")) {
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
                        const parsedCmd = try parseArgs(def_subcmd, args[(i+1)..], stdout, stderr);
                        result.command = @unionInit(CommandUnion, name, parsedCmd);              

                        return result;
                    }
                }
            } else {
                return error.InvalidCommand;
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

            if (has_flags) {
                inline for (definition.flags) |flag| {
                    const is_short = std.mem.eql(u8, current_arg, "--" ++ flag.field_name);
                    const is_long = std.mem.eql(u8, current_arg, "-" ++ flag.field_short);

                    if(is_short or is_long) {
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
                    const is_short = std.mem.eql(u8, current_arg, "--" ++ opt.field_name);
                    const is_long = std.mem.eql(u8, current_arg, "-" ++ opt.field_short);

                    if(is_short or is_long) {
                        if (i+1 >= args.len) {
                            try stderr.print("Error: Option '{s}' does not have a value\n", .{opt.field_name});
                            return error.MissingValue;
                        }

                        @field(result, opt.field_name) = try parseValue(opt.type_id, args[i+1]);
                        i += 1; // skip the next iteration
                        parsed_options += 1;
                        matched = true;
                        // nota, aquí un break literalment no fa res.
                        // un inline ens està generant codi, ergo no és un for!
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
        //
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
    
    // mock return until now
    return result;
}

// ULL aquí he posat anyerror mentre no reescric la funció per anar amb commands i que hi puguin haver-hi llistes buides :)
pub fn old_parseArgs(allocator: Allocator, comptime args_def: anytype, args_iter: *Args.Iterator, stdout: *Io.Writer, stderr: *Io.Writer) anyerror!ArgsStruct(args_def) {
    _ = allocator;
    validation.validateDefinition(args_def);
    
    const ResultType = ArgsStruct(args_def);
    var result: ResultType = undefined;
    
    // options must be initialized to default value
    inline for (args_def.optional) |opt| {
        @field(result, opt.field_name) = opt.default_value;
    }

    // all flags to false by default 
    inline for (args_def.flags) |flg| {
        @field(result, flg.field_name) = false;
    }
    
    inline for (args_def.required, 0..) |req_def, i| {
       
        const arg_str = args_iter.next() orelse {
            try stderr.print("Error: Missing argument '{s}'\n", .{req_def.field_name});
            try printUsage(args_def, stderr);
            return error.MissingArgument;
        };
        
        // if first argument is help 
        if (i == 0) {
            if (std.mem.eql(u8, arg_str, "help")) {
                try printUsage(args_def, stdout);
                return error.HelpShown;
            }
        }

        // if --help or -h appears
        if (std.mem.eql(u8, arg_str, "-h") or std.mem.eql(u8, arg_str, "--help")) {
            try printUsage(args_def, stdout);
            return error.HelpShown;
        }

        @field(result, req_def.field_name) = try parseValue(req_def.type_id, arg_str);
    }


    while (args_iter.next()) |arg_str| {
        // must NOT start with '-'
        if (arg_str.len < 2 or arg_str[0] != '-') {
            try stderr.print("Error: Unexpected argument '{s}'\n", .{arg_str});
            return error.UnexpectedArgument;
        }

        // check against all known options (Expects value)
        var matched = false;
        inline for (args_def.optional) |opt| {
            // Check long name (--) and short name (-)
            const is_long  = std.mem.eql(u8, arg_str[2..], opt.field_name);
            const is_short = std.mem.eql(u8, arg_str[1..], opt.field_short);

            if (is_long or is_short) {
                // Grab the value for this option
                const val_str = args_iter.next() orelse {
                    try stderr.print("Error: Option '{s}' requires a value\n", .{opt.field_name});
                    return error.MissingValue;
                };
                @field(result, opt.field_name) = try parseValue(opt.type_id, val_str);
                matched = true;
            }
        }

        // all known FLAGS (No value, just true)
        inline for (args_def.flags) |flg| {
            const is_long  = std.mem.eql(u8, arg_str[2..], flg.field_name);
            const is_short = std.mem.eql(u8, arg_str[1..], flg.field_short);

            if (is_long or is_short) {
                @field(result, flg.field_name) = true;
                matched = true;
            }
        }

        if (!matched) {
            try stderr.print("Error: Unknown argument '{s}'\n", .{arg_str});
            try printUsage(args_def, stderr);
            return error.UnknownArgument;
        }
    }

    return result;
}

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

