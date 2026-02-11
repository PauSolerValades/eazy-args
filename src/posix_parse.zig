const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;
const Args = std.process.Args;

const parse = @import("parse.zig");
const reification = @import("reification.zig");

const Reify = reification.Reify;
const parseErrors = parse.ParseErrors;
const ContextNode = parse.ContextNode;
const PeekIterator = parse.PeekIterator;

/// Implements a POSIX compilant parsing function of command line arguments. that is, for each level:
/// 1. Parse flags.
/// 2. Parse Options
/// 3. Parse required arguments.
/// If subcommands are provided, the options of that subcommand level must be provided before the positional argument.
/// (eg, "git -v init "/path/to/file" -p", where -v is an application command
/// a violation of that order will raise an error.
pub fn parseArgsPosixRecursive(comptime definition: anytype, args: *Args.Iterator, ctx: ?*const ContextNode, stdout: *Io.Writer, stderr: *Io.Writer) anyerror!Reify(definition){
    
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
            try parse.printUsageCtx(definition, ctx, stdout);
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
            
            // NOTE: to support both combined flags (-aAls) and combined value (-o1) you NEED to check the options first!
            // if you don't do it, the combined flag will be parsed as an option and blow up!
            
            // OPTIONS
            if (has_options) {
                inline for (definition.options) |opt| {
                    const is_long = std.mem.eql(u8, current_arg, "--" ++ opt.field_name);
                    const is_short = std.mem.eql(u8, current_arg, "-" ++ opt.field_short);
                   
                    const is_current_short = current_arg[0] == '-';
                    const is_current_long = std.mem.startsWith(u8, current_arg, "--");

                    // -02 => len > 2
                    if (is_current_short and !is_current_long and current_arg.len > 2) {
                        if (current_arg[1] == opt.field_short[0]) { // this is just one char long!
                            @field(result, opt.field_name) = parse.parseValue(opt.type_id, current_arg[2..]) catch |err| {
                                try parse.printValueError(stderr, err, opt.field_name, current_arg[2..], opt.type_id);
                                return err;
                            };

                            match = true;
                        }
                    } else if (is_short or is_long) {
                        const val = args.next(); 
                        if (val) |v| {
                            if (std.mem.startsWith(u8, v, "-")) {
                                try stderr.print("Error: option '{s}' has a value starting with '-' ({s})\n", .{current_arg, v});
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

            if (has_flags) {
                const is_current_long = current_arg[1] == '-';
                 
                // if it is a -la, len must be bigger than two. here we already know that it starts with -
                if (current_arg.len > 2 and !is_current_long) {
                    for (current_arg[1..]) |c| {
                        var char_is_valid_flag = false; 
                        
                        inline for (definition.flags) |flag| {
                            if (flag.field_short[0] == c) {
                                char_is_valid_flag = true;
                            }
                        }

                        if (!char_is_valid_flag){
                            try stderr.print("Error: invalid flag '{c}' in mixed flag '{s}'\n", .{c, current_arg});
                            return error.InvalidFlag;
                        }
                    }
                    
                    // if the code arrives here, every flag is correct
                    for (current_arg[1..]) |c| {
                        inline for (definition.flags) |flag| {
                            if (flag.field_short[0] == c) {
                                @field(result, flag.field_name) = true;
                            }
                        }
                    }
                    continue :args_loop;
                    //match = true;
                }

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

                        const current_node = ContextNode{
                            .name = name,
                            .parent = ctx,
                        };

                        const def_subcmd = @field(definition.commands, name);
                        const parsedCmd = try parseArgsPosixRecursive(def_subcmd, args, &current_node, stdout, stderr); // POINTER TO THE SAME ITERATOR
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
        try parse.printUsageCtx(definition, ctx, stdout);
        return error.HelpShown;
    }
    // safety checks
    if (has_required and parsed_required != definition.required.len) {
        try stderr.print("Error: Incorrect number of required arguments detected. Should be {d} but are {d}.\n", .{definition.required.len, parsed_required});
        return error.UnexpertedArgument;
    }

    if (has_commands) {
        try stderr.writeAll("Error: .command found at same level as .required.\n");
        return error.InvalidDefinition;
    }

    return result;
}

pub fn parseArgsErgonomicRecursive(comptime definition: anytype, iter: *PeekIterator, parent_stack: anytype, stdout: *Io.Writer, stderr: *Io.Writer) anyerror!Reify(definition){
    
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

    if (has_commands) {
        const next_arg_opt = iter.peek();

        if (next_arg_opt) |next_arg| {
            const CommandUnion = comptime find_cmd: {
                for (@typeInfo(ReArgs).@"struct".fields) |f| {
                    if (std.mem.eql(u8, f.name, "cmd")) break: find_cmd f.type;
                }
                unreachable;
            };


            // is next_arg a specific command name?
            if (std.meta.stringToEnum(std.meta.Tag(CommandUnion), next_arg)) |command_tag| {
                _ = iter.next(); // this updated the current in iter

                const new_entry = .{
                    .definition = definition,
                    .result_ptr = &result,
                };
                const new_stack = parent_stack ++ .{ new_entry };

                switch (command_tag) {
                    inline else => |tag| {
                        const name: []const u8 = @tagName(tag); // converts the enum into a string
                        const def_subcmd = @field(definition.commands, name);

                        const parsedCmd = try parseArgsErgonomicRecursive(def_subcmd, iter, new_stack, stdout, stderr); // POINTER TO THE SAME ITERATOR
                        result.cmd = @unionInit(CommandUnion, name, parsedCmd);

                        return result;
                    }
                }
            }
        }
    }
   
    var parsed_required: usize = 0;
    var is_args_empty = true;

    while (iter.next()) |current_arg| {
        
        is_args_empty = false;

        if (std.mem.eql(u8, current_arg, "-h") or std.mem.eql(u8, current_arg, "--help") or std.mem.eql(u8, current_arg, "help")) {
            // try parse.printUsageCtx(definition, ctx, stdout);
            try stdout.writeAll("This is the help eh\n");
            return error.HelpShown;
        }
       
        var match = false;
        // Everything that starts with '-' can be either a flag and an option
        if (std.mem.startsWith(u8, current_arg, "-")) {
            
            const eq_index = std.mem.indexOf(u8, current_arg, "=");
            if (eq_index) |_| {
                try stderr.print("Error: argument '{s}' uses an '=' to specify the value, this is not POSIX compliant\n", .{current_arg});
                return error.InvalidPosix;
            }
      
            if (try attemptMatchFlagOrOption(definition, &result, current_arg, iter, stderr)) {
                match = true;
            } else {
                // if in this level we have not found any option, we recurse back using the parent stack
                comptime var i = parent_stack.len;
                inline while (i > 0) : (i -= 1) {
                    const entry = parent_stack[i - 1];
                    if (try attemptMatchFlagOrOption(entry.definition, entry.result_ptr, current_arg, iter, stderr)) {
                        match = true;
                        break;
                    }
                } 
            }
            
            // if we found the option with something started with -, search for another
            if (match) {
                continue;
            } else { // if not found, explode, there cannot be a positional with -
                try stderr.print("Error: Unknown argument '{s}'\n", .{current_arg});
                return error.UnknownArgument;
            }
        }
        


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
            continue;
        } else {
            try stderr.print("Error: UnexpectedArgument '{s}'\n", .{current_arg});
            return error.UnexpectedArgument;
        }
    }
    
    if (is_args_empty) {
        //try parse.printUsageCtx(definition, ctx, stdout);
        try stdout.writeAll("This is the print message!\n");
        return error.HelpShown;
    }

    // safety checks
    if (has_required and parsed_required != definition.required.len) {
        try stderr.print("Error: Incorrect number of required arguments detected. Should be {d} but are {d}.\n", .{definition.required.len, parsed_required});
        return error.UnexpertedArgument;
    }

    if (has_commands) {
        try stderr.writeAll("Error: .command found at same level as .required.\n");
        return error.InvalidDefinition;
    }

    return result;
}

/// auxiliar function to detect flags, options, combined flags and combined options.
fn attemptMatchFlagOrOption(comptime definition: anytype, result: *Reify(definition), arg: [:0]const u8, iter: *PeekIterator, stderr: *Io.Writer) !bool {
    
    const Definition = @TypeOf(definition);
    
    // NOTE: to support both combined flags (-aAls) and combined value (-o1) you NEED to check the options first!
    // if you don't do it, the combined flag will be parsed as an option and blow up!
   

    if (@hasField(Definition, "options")) {
        inline for (definition.options) |opt| {
            const is_long = std.mem.eql(u8, arg, "--" ++ opt.field_name);
            const is_short = std.mem.eql(u8, arg, "-" ++ opt.field_short);
            
            const is_current_short = arg[0] == '-';
            const is_current_long = std.mem.startsWith(u8, arg, "--");

            // -02 => len > 2
            if (is_current_short and !is_current_long and arg.len > 2) {
                if (arg[1] == opt.field_short[0]) { // this is just one char long!
                    @field(result, opt.field_name) = parse.parseValue(opt.type_id, arg[2..]) catch |err| {
                        try parse.printValueError(stderr, err, opt.field_name, arg[2..], opt.type_id);
                        return err;
                    };
                    
                    return true;
                }
            } else if (is_short or is_long) {
                const val = iter.next(); 
                if (val) |v| {
                    if (std.mem.startsWith(u8, v, "-")) {
                        try stderr.print("Error: option '{s}' has a value starting with '-' ({s})\n", .{arg, v});
                        return error.InvalidPosix;
                    }
                    @field(result, opt.field_name) = parse.parseValue(opt.type_id, v) catch |err| {
                        try parse.printValueError(stderr, err, opt.field_name, v, opt.type_id);
                        return err;
                    };

                    return true;
                } else {
                    try stderr.print("Error: null value on options '{s}'\n", .{arg});
                    return error.InvalidOptions;
                }
            }
        }
    }


    if (@hasField(Definition, "flags")) {
        const is_current_long = arg[1] == '-';
            
        // if it is a -la, len must be bigger than two. here we already know that it starts with -
        if (arg.len > 2 and !is_current_long) {
            for (arg[1..]) |c| {
                var char_is_valid_flag = false; 
                
                inline for (definition.flags) |flag| {
                    if (flag.field_short[0] == c) {
                        char_is_valid_flag = true;
                    }
                }

                if (!char_is_valid_flag){
                    try stderr.print("Error: invalid flag '{c}' in mixed flag '{s}'\n", .{c, arg});
                    return error.InvalidFlag;
                }
            }
            
            // if the code arrives here, every flag is correct
            for (arg[1..]) |c| {
                inline for (definition.flags) |flag| {
                    if (flag.field_short[0] == c) {
                        @field(result, flag.field_name) = true;
                    }
                }
            }
            return true;
        }

        inline for (definition.flags) |flag| {
            const is_long = std.mem.eql(u8, arg, "--" ++ flag.field_name);
            const is_short = std.mem.eql(u8, arg, "-" ++ flag.field_short);

            if(is_short or is_long) {
                @field(result, flag.field_name) = true;
                return true;
            }
        }
    }
    
    return false;
}
