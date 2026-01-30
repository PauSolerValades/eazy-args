const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;
const Args = std.process.Args;

const parse = @import("parse.zig");
const reification = @import("reification.zig");

const Reify = reification.Reify;
const parseErrors = parse.ParseErrors;

/// Implements a POSIX compilant parsing function of command line arguments. that is, for each level:
/// 1. Parse flags.
/// 2. Parse Options
/// 3. Parse required arguments.
/// If subcommands are provided, the options of that subcommand level must be provided before the positional argument.
/// (eg, "git -v init "/path/to/file" -p", where -v is an application command
/// a violation of that order will raise an error.
pub fn parseArgsPosixRecursive(comptime definition: anytype, args: *Args.Iterator, stdout: *Io.Writer, stderr: *Io.Writer) anyerror!Reify(definition){
    
    // create the reificated struct, empty and ready to fill 
    const ReArgs: type = Reify(definition);
    var result: ReArgs = undefined;
    
    // as a standard, we check if a field exists in definition not in result : ReArgs
    // that means @hasField(definition, ...) and NOT @hasField(result, ...)
    const Definition = @TypeOf(definition);

    const has_flags = @hasField(Definition, "flags");
    const has_options = @hasField(Definition, "options");
    const has_required = @hasField(Definition, "required");
    const has_commands = @hasField(Definition, "commands");

    // default flags to false
    if (has_flags) {
        inline for (definition.flags) |flag| {
            @field(result, flag.field_name) = false;
        }
    }

    // default optionss to their values
    if (has_options) {
        inline for (definition.options) |opt| {
            @field(result, opt.field_name) = opt.default_value;
        }
    }
   
    var parsed_required: usize = 0;

    var all_flags_and_options_parsed = false;
    var all_commands_parsed = false; // this means positional starts
    var is_args_empty = true; // això és molt cutre però no se m'acut res millor xd

    args_loop: while (args.next()) |current_arg| {
        
        is_args_empty = false;

        if (std.mem.eql(u8, current_arg, "-h") or std.mem.eql(u8, current_arg, "--help") or std.mem.eql(u8, current_arg, "help")) {
            try parse.printUsage(definition, stdout);
            return error.HelpShown;
        }
       
        var match = false;
        // Everything that starts with '-' can be either a flag and an option
        if (!all_flags_and_options_parsed and std.mem.startsWith(u8, current_arg, "-")) {
            
            const eq_index = std.mem.indexOf(u8, current_arg, "=");
            if (eq_index) |_| {
                try stderr.print("Error: argument '{s}' uses an '=' to specify the value, this is not POSIX compliant\n", .{current_arg});
                return error.InvalidPosix;
            }

            if (has_flags) {
                inline for (definition.flags) |flag| {
                    const is_long = std.mem.eql(u8, current_arg, "--" ++ flag.field_name);
                    const is_short = std.mem.eql(u8, current_arg, "-" ++ flag.field_short);

                    if(is_short or is_long) {
                        @field(result, flag.field_name) = true;
                        match = true;
                    }
                }
            }
            
            if (match) continue :args_loop;
            
            // OPTIONS
            if (has_options) {
                inline for (definition.options) |opt| {
                    const is_short = std.mem.eql(u8, current_arg, "--" ++ opt.field_name);
                    const is_long = std.mem.eql(u8, current_arg, "-" ++ opt.field_short);

                    if(is_short or is_long) {
                        const val = args.next(); 
                        if (val) |v| {
                            if (std.mem.startsWith(u8, v, "-")) {
                                try stderr.print("Error: option ' {s}' has a value starting with '-' ({s})\n", .{current_arg, v});
                                return error.InvalidPosix;
                            }
                            @field(result, opt.field_name) = parse.parseValue(opt.type_id, v) catch |err| {
                                try parse.printValueError(stderr, err, opt.field_name, v, opt.type_id);
                                return err;
                            };
                            match = true; 
                        } else {
                            try stderr.print("Error: null value on options '{s}'\n", .{current_arg});
                            return error.InvalidOptions;
                        }
                    }
                }
            }

            if (match) continue :args_loop;
        }
        
        // if your code arrives here, all '-' have been compared
        all_flags_and_options_parsed = true;

        // COMMANDS, call yourself to parse whatever is inside
        if (has_commands and !all_commands_parsed) {
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
                switch (command_tag) {
                    inline else => |tag| {
                        const name: []const u8 = @tagName(tag); // converts the enum into a string
                        const def_subcmd = @field(definition.commands, name);
                        const parsedCmd = try parseArgsPosixRecursive(def_subcmd, args, stdout, stderr); // POINTER TO THE SAME ITERATOR
                        result.cmd = @unionInit(CommandUnion, name, parsedCmd);              

                        return result;
                    }
                }
            } 
        }
   
        // REQUIRED
        all_commands_parsed = true;

        if (std.mem.startsWith(u8, current_arg, "-")) {
            try stderr.writeAll("Error: flag detected when required argument expected.\n");
            return error.InvalidPosix;
        }

        if (has_required) {
            if (parsed_required >= definition.required.len) {
                try stderr.print("Error: UnexpectedArgument '{s}'\n", .{current_arg});
                return error.UnexpectedArgument;
            }

            // no need for a boolean, all the requireds get parsed inmediately
            inline for (definition.required, 0..) |req, j| {
                if (j == parsed_required) 
                    @field(result, req.field_name) = parse.parseValue(req.type_id, current_arg) catch |err| {
                        try parse.printValueError(stderr, err, req.field_name, current_arg, req.type_id );
                        return err;
                    };
                    parsed_required += 1;
            }
        } else {
            try stderr.print("Error: UnexpectedArgument '{s}'\n", .{current_arg});
            return error.UnexpectedArgument;
        }
    }
    
    if (is_args_empty) {
        try parse.printUsage(definition, stdout);
        return error.HelpShown;
    }
    // safety checks
    if (has_required and parsed_required != definition.required.len) {
        try stderr.print("Error: Incorrect number of required arguments detected. Should be {d} but are {d}.", .{definition.required.len, parsed_required});
        return error.UnexpertedArgument;
    }

    if (has_commands) {
        try stderr.writeAll("Error: .command found at same level as .required.\n");
        return error.InvalidDefinition;
    }

    return result;
}


