const std = @import("std");
const structs = @import("structs.zig");
const ArgKind = structs.ArgKind;

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
/// 3. Flags and optionss are optionss
pub fn validateDefinition(comptime definition: anytype, comptime depth: usize) void {
    const T = @TypeOf(definition);
    const typeInfo = @typeInfo(T);

    if (typeInfo != .@"struct") {
        @compileError("Definitions must be a struct");
    }
    
    comptime var has_required = false;
    comptime var has_commands = false;
    comptime var has_options = false;
    comptime var has_flags = false;
    comptime var has_name = false;
    comptime var has_description = false;
    // the definition validation must happen on compile time
    comptime {
        for (typeInfo.@"struct".fields) |field| {
            if (std.mem.eql(u8, field.name, "required")) {
                has_required = true;
            } else if (std.mem.eql(u8, field.name, "commands")) {
                has_commands = true;
            } else if (std.mem.eql(u8, field.name, "options")) {
                has_options = true;
            } else if (std.mem.eql(u8, field.name, "flags")) {
                has_flags = true;
            } else if (std.mem.eql(u8, field.name, "name")) {
                has_name = true;
            } else if (std.mem.eql(u8, field.name, "description")) {
                has_description = true;
            } else {
                @compileError("Field '" ++ field.name ++ "' is invalid. Allowed fields are: required/commands, options, flags. If the field is a command or the first level, description can appear. If it's just the first level, name is also allowed.");
            }
        }      
    }
    
    // check 
    if (has_name) {
        // allowed only at first level
        if (depth != 0) @compileError(".name is valid only at the first level of the definition");
        if (comptime !isStringLiteral(definition.name)) @compileError(".name must be a string");
    }  
    
    if (has_description and (comptime !isStringLiteral(definition.description))) @compileError(".definition must be a string.");
   

    if (has_commands) {
        if (has_required) @compileError(".commands and .required are mutually exclusive in the same level");

        if (has_options) validateSubfield(definition, .option);
        if (has_flags) validateSubfield(definition, .flag);

        const commands = definition.commands;
        const command_typeinfo = @typeInfo(@TypeOf(commands));
        if (command_typeinfo != .@"struct") @compileError("commands must contain an anonymous struct");
    
        inline for (command_typeinfo.@"struct".fields) |field| {
            validateDefinition(@field(definition.commands, field.name), depth + 1);
        }
    } else {
        // despite being mutually exclusive you might have two subcomands and none requried 
        if (has_required) validateSubfield(definition, .argument);
        if (has_options) validateSubfield(definition, .option);
        if (has_flags) validateSubfield(definition, .flag);
    }
}

fn validateSubfield(comptime definition: anytype, comptime kind: ArgKind) void {
    const name = switch(kind) {
        .argument => "required",
        .option => "options",
        .flag => "flags",
    };

    const subfield: type = @TypeOf(@field(definition, name));
    if (!@typeInfo(subfield).@"struct".is_tuple) @compileError(name ++ " must be a tuple `.{ ... }`");

    inline for (@typeInfo(subfield).@"struct".fields) |field| {
        const potential_arg = @field(@field(definition, name), field.name);
        if (potential_arg._kind != kind) @compileError("." ++ name ++ " must just contain " ++ kind);
    }

}

fn isStringLiteral(comptime param: anytype) bool {
    const T = @TypeOf(param);
    const info = @typeInfo(T);

    if (info != .pointer) return false;
    const ptr = info.pointer;

    // is just one item pointer
    if (ptr.size != .one) return false;
    
    // has to be const
    if (!ptr.is_const) return false;
    
    const child_info = @typeInfo(ptr.child);
    if (child_info != .array) return false; // it's an array

    return child_info.array.child == u8; // []const u8
}

const Arg = structs.Argument;
const Opt = structs.Option;
const Flag = structs.Flag;

test "normal definition" {
    {
        const definition = .{
            .required = .{ Arg(u32, "a", "aaa") },
            .flags = .{ Flag("verbose", "v", "Print Verbose") },
            .options = .{ Opt(u32, "bbbbb", "b", 1, "lots of b") },
        };

        validateDefinition(definition, 0); // this has to just not compile 
    }
    {
        const subdef = .{
            .required = .{ Arg(u32, "a", "aaa") },
            .flags = .{ Flag("verbose", "v", "Print Verbose") },
            .options = .{ Opt(u32, "bbbbb", "b", 1, "lots of b") },
        };

        const definition = .{
            .commands = .{
                .cmd1 = subdef,
                .cmd2 = subdef,
            },
        };
    
        validateDefinition(definition, 0);
    }
    {
        const subdef = .{
            .required = .{ Arg(u32, "a", "aaa") },
            .flags = .{ Flag("verbose", "v", "Print Verbose") },
            .options = .{ Opt(u32, "bbbbb", "b", 1, "lots of b") },
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
        
        validateDefinition(definition, 0);
    }
    // { //this does not compile!!
    //     const subdef = .{
    //         .required = .{ Arg(u32, "a", "aaa") },
    //         .flags = .{ Flag("verbose", "v", "Print Verbose") },
    //         .options = .{ Opt(u32, "bbbbb", "b", 1, "lots of b") },
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
    //     validateDefinition(definition, 0);
    // }
    // { //this does not compile!!
    //     const subdef = .{
    //         .required = .{ Arg(u32, "a", "aaa") },
    //         .flags = .{ Flag("verbose", "v", "Print Verbose") },
    //         .options = .{ Opt(u32, "bbbbb", "b", 1, "lots of b") },
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
    //                 .options = .{ Opt(u64, "zzzzz", "z", 1, "lots of z") },
    //             },
    //             .cmd2 = subdef,
    //         },
    //         .flags = .{ Flag("verbose", "v", "print verbose") },
    //     };
    //
    //     validateDefinition(definition, 0);
    // }
}

test "commands, names and definition" {
    
    const definition = .{
        .name = "my program",
        .required = .{ Arg(u32, "a", "aaa") },
        .flags = .{ Flag("verbose", "v", "Print Verbose") },
        .options = .{ Opt(u32, "bbbbb", "b", 1, "lots of b") },
    };

    validateDefinition(definition, 0);

}

test "descprition and acommands" {
   
    const definition = .{
        .commands = .{
            .cmd1 = .{
                .description = "This is cmd1",
                .commands = .{
                    .cmd11 = .{ .description = "This is cmd11" },
                    .cmd12 = .{ 
                        .description = "this is cmd12", 
                        .required = .{ Arg(u32, "a", "aaaa") },
                    },
                    .cmd13 = .{},
                }
            },
            .cmd2 = .{
                .description = "This is command 2",
                .required = .{ Arg(u32, "b", "bbbbb") },
            },
        },
        .flags = .{ Flag("verbose", "v", "print verbose") },
    };

    validateDefinition(definition, 0);
}

