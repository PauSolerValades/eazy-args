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
    //const typeInfo = @typeInfo(T);

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
    var positional_started = false;

    while (args.next()) |current_arg| {
        
        if (std.mem.eql(u8, current_arg, "-h") or std.mem.eql(u8, current_arg, "--help")) {
            try parse.printUsage(definition, stdout);
            return error.HelpShown;
        }
        
        var flag_detected = false;
        if (!positional_started and std.mem.startsWith(u8, current_arg, "-")) {
            
            if (std.mem.eql(u8, current_arg, "--")) {
                positional_started = true;
                continue;
            }


            const eq_index = std.mem.indexOf(u8, current_arg, "=");
            if (eq_index) |_| {
                try stderr.print("Error: argument '{s}' uses an '=' to specify the value, this is not POSIX compliant\n", .{current_arg});
            }

            if (has_flags) {
                inline for (definition.flags) |flag| {
                    const is_short = std.mem.eql(u8, current_arg, "--" ++ flag.field_name);
                    const is_long = std.mem.eql(u8, current_arg, "-" ++ flag.field_short);

                    if(is_short or is_long) {

                        @field(result, flag.field_name) = true;
                        flag_detected = true;
                    }
                }
            }

           if (!flag_detected and has_options) {
                inline for (definition.options) |opt| {
                    const is_short = std.mem.eql(u8, current_arg, "--" ++ opt.field_name);
                    const is_long = std.mem.eql(u8, current_arg, "-" ++ opt.field_short);

                    if(is_short or is_long) {
                        const val = args.next(); 
                        if (val) |v| {
                            @field(result, opt.field_name) = parse.parseValue(opt.type_id, v) catch |err| {
                                try parse.printValueError(stderr, err, opt.field_name, v, opt.type_id);
                                return err;
                            };
                        } else {
                            try stderr.print("Error: null value on options '{s}'\n", .{current_arg});
                        }
                        
                        
                        flag_detected = true;
                    }
                }
            }
        }
                     
        if (flag_detected) continue;
        
        if (!positional_started and has_commands) {
            // get the type of the command field
            // serach in the ReArgs because we are looking for the Union to get which commands
            // have been already defined
            // It could be done in definition.commands and iterate over there but that would waste a part
            // of what has been done in Reify, where the Enum has been generated
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
                        const parsedCmd = try parseArgsPosixRecursive(def_subcmd, args, stdout, stderr); // POINTER TO THE SAME ITERATOR
                        result.cmd = @unionInit(CommandUnion, name, parsedCmd);              

                        return result;
                    }
                }
            } 
        }
    
        // positional arguments
        positional_started = true;

        if (std.mem.startsWith(u8, current_arg, "-")) {
            try stderr.writeAll("Error: flag detected when required argument expected.\n");
        }

        if (has_required) {
            if (parsed_required >= definition.required.len) {
                try stderr.print("Error: UnexpectedArgument '{s}'\n", .{current_arg});
                return error.UnexpectedArgument;
            }

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
        
               
        // some safety checks
        // if (has_flags and parsed_flags > definition.flags.len) {
        //     try stderr.print("Error: Incorrect number of flags detected. Should be at most {d} but are {d}", .{definition.flags.len, parsed_flags});
        //     return error.InvalidFlags;
        // }
        //
        // if (has_options and parsed_options > definition.options.len) {
        //     try stderr.print("Error: Incorrect number of options detected. Should at most {d} but are {d}", .{definition.options.len, parsed_options});
        //     return error.InvalidOptions;
        // }

        if (has_required and parsed_required != definition.required.len) {
            try stderr.print("Error: Incorrect number of required arguments detected. Should be {d} but are {d}.", .{definition.required.len, parsed_required});
            return error.UnexpertedArgument;
        }

        if (has_commands) {
            try stderr.writeAll("Error: .command found at same level as .required.\n");
        }
    }
    
    return result;
}


