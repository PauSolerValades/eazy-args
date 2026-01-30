const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;

const parse = @import("parse.zig");
const reification = @import("reification.zig");

const Reify = reification.Reify;
const parseErrors = parse.ParseErrors;


/// The function parses 
/// Rules on the parsing:
/// 1. Each level contains either a positional (required) or a command
/// 2. Once a required argument is found, no other commands can be found. (./pgrm cmd1 req cmd2 -> does not compile)
/// 3. All the required arguments must one after the other (eg ./prgm cmd1 r1, ..., rn, -f1,...,-fm, -o1, ..., -on). The order of required, flags, opt 
///     can be interchangable, and opt/flags can be mixed toghether
/// 4. No flags nor options can be between commands. If a flag/option is specific of a subcommand, add it before the last command.
pub fn parseArgsRecursive(comptime definition: anytype, args: []const[]const u8, consumed: []bool, stdout: *Io.Writer, stderr: *Io.Writer) anyerror!Reify(definition){
   
    // if some element is help -h or --help just print help
    for (args, 0..) |arg, i| {
        if (!consumed[i] and (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "help"))) {
            try parse.printUsage(definition, stdout);
            return error.HelpShown;
        }
    }
       
    // create the reificated struct, empty and ready to fill 
    const ReArgs: type = Reify(definition);
    var result: ReArgs = undefined;
    
    // as a standard, we check if a field exists in definition not in result : ReArgs
    // that means @hasField(definition, ...) and NOT @hasField(result, ...)
    const Definition = @TypeOf(definition);

    const has_flags = @hasField(Definition, "flags");
    const has_options = @hasField(Definition, "options");
    // default flags to false
    if (has_flags) {
        inline for (definition.flags) |flag| {
            // we have to fill the struct
            // we are sure that definition IS the same as ReArgs struct
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
    var parsed_flags: usize = 0;
    var parsed_options: usize = 0;

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        if (consumed[i]) continue;

        const current_arg = args[i];
        
        if (std.mem.startsWith(u8, current_arg, "-")) {
            var matched = false;
           
            const eq_index = std.mem.indexOf(u8, current_arg, "=");
            
            const arg_key = if (eq_index) |idx| current_arg[0..idx] else current_arg;
            const arg_val_inline = if (eq_index) |idx| current_arg[idx+1..] else null;

            if (has_flags) {
                inline for (definition.flags) |flag| {
                    const is_short = std.mem.eql(u8, arg_key, "-" ++ flag.field_short);
                    const is_long = std.mem.eql(u8, arg_key, "--" ++ flag.field_name);

                    if(is_short or is_long) {

                        if (arg_val_inline != null) {
                            try stderr.print("Error: a flag ({s}) cannot take values.\n", .{arg_key});
                            return error.UnexpectedValue;
                        }

                        @field(result, flag.field_name) = true;
                        parsed_flags += 1;
                        matched = true;
                    }
                }
            }

            if (!matched and has_options) {
                inline for (definition.options) |opt| {
                    const is_short = std.mem.eql(u8, arg_key, "-" ++ opt.field_short);
                    const is_long = std.mem.eql(u8, arg_key, "--" ++ opt.field_name);

                    if(is_short or is_long) {
                        // is an --opt=val 
                        if (arg_val_inline) |val| {
                            @field(result, opt.field_name) = parse.parseValue(opt.type_id, val) catch |err| {
                                try parse.printValueError(stderr, err, arg_key, val, opt.type_id);
                                return err; 
                            };
                        } else { // is an --opt val
                            // serach the first non used argument 
                            var next_idx = i+1;
                            while (next_idx < args.len and consumed[next_idx]) : (next_idx += 1) {}
                            
                            if (next_idx >= args.len) {
                                try stderr.print("Error: Option '{s}' does not have a value\n", .{opt.field_name});
                                return error.MissingValue;
                            }
                            
                            const val = args[i+1];
                            @field(result, opt.field_name) = parse.parseValue(opt.type_id, val) catch |err| {
                                try parse.printValueError(stderr, err, arg_key, val, opt.type_id);
                                return err; 
                            };
                            consumed[next_idx] = true; 
                        }
                        
                        parsed_options += 1;
                        matched = true;
                    }
                }
            }
            
            // if the flag/opt was actually found, next arg
            if (matched) consumed[i] = true;

            // here we could add a check like
            // try stderr.print("Error: whateve")
            // return error.UnknownArgument;
        }
    } 
    if (@hasField(Definition, "commands")) {
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
        i = 0;
        while (i < args.len) : (i += 1) {
            const current_arg = args[i];
            if (std.meta.stringToEnum(CommandTag, current_arg)) |command_tag| {
                consumed[i] = true;
                // we need to access the definition.commands.@value(current_arg) (eg: def.commands.entry)
                // to do that we cannot use @field because current_arg is not comptime
                // we have to generate all the code for the possible args with the inline else.
                switch (command_tag) {
                    inline else => |tag| {
                        const name: []const u8 = @tagName(tag); // converts the enum into a string
                        const def_subcmd = @field(definition.commands, name);
                        // we know this is a valid command, so we recursively parse the Args 
                        const parsedCmd = try parseArgsRecursive(def_subcmd, args, consumed, stdout, stderr);
                        result.cmd = @unionInit(CommandUnion, name, parsedCmd);              

                        return result;
                    }
                }
            }
        }
        
    }

    i = 0;
    while (i < args.len) : (i += 1) {
        if (consumed[i]) continue;

        const current_arg = args[i];
        
        // safety check lol, a test failed
        if (std.mem.startsWith(u8, current_arg, "-")) {
            try stderr.print("Error: Unknown Argument {s}\n", .{current_arg});
            return error.UnknownArgument;
        }

        if (@hasField(Definition, "required")) {
            if (parsed_required > definition.required.len) {
                try stderr.print("Error: UnexpectedArgument '{s}'\n", .{current_arg});
                return error.UnexpectedArgument;
            }

            // parse
            inline for (definition.required, 0..) |req, j| {
                if (j == parsed_required) { 
                    @field(result, req.field_name) = parse.parseValue(req.type_id, current_arg) catch |err| {
                        try parse.printValueError(stderr, err, req.field_name, current_arg, req.type_id);
                        return err; 
                    };
                    parsed_required += 1;
                    consumed[i] = true;
                    break;
                }
            }
        } else {
            try stderr.writeAll("Error: catastrofic failure of the validation function. Cry.\n");
            return error.CatastroficStructure;
        }

    }
            
            
    // some safety checks
    if (has_flags and parsed_flags > definition.flags.len) { try stderr.print("Error: Incorrect number of flags detected. Should be at most {d} but are {d}\n", .{definition.flags.len, parsed_flags});
        return error.InvalidFlags;
    }
    
    if (has_options and parsed_options > definition.options.len) {
        try stderr.print("Error: Incorrect number of options detected. Should at most {d} but are {d}\n", .{definition.options.len, parsed_options});
        return error.InvalidOptions;
    }

    if (@hasField(Definition, "required") and parsed_required != definition.required.len) {
        try stderr.print("Error: Incorrect number of required arguments detected. Should be {d} but are {d}.\n", .{definition.required.len, parsed_required});
        return error.MissingRequired;
    }
    
    // last parse should not have a command
    if (@hasField(Definition, "commands")) {
        try stderr.writeAll("Error: Expected a command.\n");
        return error.MissingArgument;
    }
    
    
    return result;
}

