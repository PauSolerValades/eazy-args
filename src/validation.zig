const std = @import("std");
const r = @import("reification.zig");

pub fn validateReservedKeywords(comptime name: []const u8, comptime short: ?[]const u8) void {
    // check long name
    if (std.mem.eql(u8, name, "help")) {
        @compileError("Argument name 'help' is reserved by the library. Please pick a different name.");
    }

    // check short name (if it exists)
    if (short) |s| {
        if (std.mem.eql(u8, s, "h")) {
            @compileError("Short argument 'h' is reserved for help. Please pick a different character.");
        }
    }
}

/// Validates the definition structure following, which follows this three rules:
/// 1. There cannot be a .commands and a required at the same level.
/// 2. You can nest any commands within each other as long as there is no .required.
///     Up to that point, a command must not appear.
/// 3. Flags and Optionals are optionals
pub fn validateDefinition(comptime definition: anytype) void {
    const T = @TypeOf(definition);
    const typeInfo = @typeInfo(T);

    if (typeInfo != .@"struct") {
        @compileError("Definitions must be a struct");
    }
    
    // const hasRequired = @hasField(T, "required");
    // const hasCommands = @hasField(T, "commands");
    // const hasOptional = @hasField(T, "optional");
    // const hasFlags    = @hasField(T, "flags"); 

    comptime var hasRequired = false;
    comptime var hasCommands = false;
    comptime var hasOptional = false;
    comptime var hasFlags    = false;
    
    // the comptime on the if is NEEDED for this to work
    inline for (typeInfo.@"struct".fields) |field| {
        if (comptime std.mem.eql(u8, field.name, "required")) {
            hasRequired = true;
        } else if (comptime std.mem.eql(u8, field.name, "commands")) {
            hasCommands = true;
        } else if (comptime std.mem.eql(u8, field.name, "optional")) {
            hasOptional = true;
        } else if (comptime std.mem.eql(u8, field.name, "flags")) {
            hasFlags = true;
        } else {
             @compileError("Field '" ++ field.name ++ "' is invalid. Allowed: required, optional, flags, commands.");
        }
    }      
  
    if (hasCommands) {
        if (hasRequired) @compileError(".commands and .required are mutually exclusive in the same level");
        
        if(hasOptional) validateOptional(definition);
        if(hasFlags) validateFlags(definition);

        const commands = definition.commands;
        const command_typeinfo = @typeInfo(@TypeOf(commands));
        if (command_typeinfo != .@"struct") @compileError("commands must contain an anonymous struct");
    
        inline for (command_typeinfo.@"struct".fields) |field| {
            validateDefinition(@field(definition.commands, field.name));
        }

    } else {
        
        const required: type = @TypeOf(definition.required);
        if (!@typeInfo(required).@"struct".is_tuple) @compileError("required must be a tuple `.{ ... }`");
        
        inline for (@typeInfo(required).@"struct".fields) |field| {
            const potential_arg = @field(definition.required, field.name);
            if (potential_arg._kind != r.ArgKind.arg) @compileError(".required must contain Arg()");
        }
    
        if (hasOptional) validateOptional(definition);
        if (hasFlags) validateFlags(definition);
    }
}

fn validateOptional(comptime definition: anytype) void {
    const optional: type = @TypeOf(definition.optional);
    if (!@typeInfo(optional).@"struct".is_tuple) @compileError("optional must be a tuple `.{ ... }`");
    
    inline for (@typeInfo(optional).@"struct".fields) |field| {

        const potential_arg = @field(definition.optional, field.name);
        if (potential_arg._kind != r.ArgKind.optarg) @compileError(".optional must contain OptArg()");
    }
}

fn validateFlags(comptime definition: anytype) void {
    const flags: type = @TypeOf(definition.flags);
    if (!@typeInfo(flags).@"struct".is_tuple) @compileError("flags must be a tuple `.{ ... }`");
    
    inline for (@typeInfo(flags).@"struct".fields) |field| {
        const potential_arg = @field(definition.flags, field.name);
        if (potential_arg._kind != r.ArgKind.flag) @compileError(".flags must contain Flag()");
    }
}

test "normal definition" {
    const Arg = r.Arg;
    const Opt = r.OptArg;
    const Flag = r.Flag;
    {
        const definition = .{
            .required = .{ Arg(u32, "a", "aaa") },
            .flags = .{ Flag("verbose", "v", "Print Verbose") },
            .optional = .{ Opt(u32, "bbbbb", "b", 1, "lots of b") },
        };

        validateDefinition(definition); // this has to just not compile 
    }
    {
        const subdef = .{
            .required = .{ Arg(u32, "a", "aaa") },
            .flags = .{ Flag("verbose", "v", "Print Verbose") },
            .optional = .{ Opt(u32, "bbbbb", "b", 1, "lots of b") },
        };

        const definition = .{
            .commands = .{
                .cmd1 = subdef,
                .cmd2 = subdef,
            },
        };
    
        validateDefinition(definition);
    }
    {
        const subdef = .{
            .required = .{ Arg(u32, "a", "aaa") },
            .flags = .{ Flag("verbose", "v", "Print Verbose") },
            .optional = .{ Opt(u32, "bbbbb", "b", 1, "lots of b") },
        };

        const definition = .{
            .commands = .{
                .cmd1 = .{
                    .commands = .{
                        .cmd11 = subdef,
                        .cmd12 = subdef,
                        .cmd13 = subdef,
                    }
                },
                .cmd2 = subdef,
            },
            .flags = .{ Flag("verbose", "v", "print verbose") },
        };
        
        validateDefinition(definition);
    }
    // { //this does not compile!!
    //     const subdef = .{
    //         .required = .{ Arg(u32, "a", "aaa") },
    //         .flags = .{ Flag("verbose", "v", "Print Verbose") },
    //         .optional = .{ Opt(u32, "bbbbb", "b", 1, "lots of b") },
    //     };
    //
    //     const definition = .{
    //         .commands = .{
    //             .cmd1 = .{
    //                 .required = .{
    //                     .cmd111 = subdef,
    //                     .flags = .{ Flag("aaaaaa", "a", "aaa")},
    //                 },
    //                 .cmd12 = subdef,
    //                 .cmd13 = subdef,
    //             },
    //             .cmd2 = subdef,
    //         },
    //         .flags = .{ Flag("verbose", "v", "print verbose") },
    //     };
    //
    //     validateDefinition(definition);
    // }
    // { //this does not compile!!
    //     const subdef = .{
    //         .required = .{ Arg(u32, "a", "aaa") },
    //         .flags = .{ Flag("verbose", "v", "Print Verbose") },
    //         .optional = .{ Opt(u32, "bbbbb", "b", 1, "lots of b") },
    //     };
    //
    //     const definition = .{
    //         .commands = .{
    //             .cmd1 = .{
    //                 .required = .{
    //                     .commands = .{
    //                         .cmd111 = subdef, 
    //                     },
    //                     .flags = .{ Flag("aaaaaa", "a", "aaa")},
    //                 },
    //                 .optional = .{ Opt(u64, "zzzzz", "z", 1, "lots of z") },
    //             },
    //             .cmd2 = subdef,
    //         },
    //         .flags = .{ Flag("verbose", "v", "print verbose") },
    //     };
    //
    //     validateDefinition(definition);
    // }
}

