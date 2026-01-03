const std = @import("std");
const Type = std.builtin.Type;

const validation = @import("validation.zig");

/// Creates the Argument Structure
/// name uses [:0] to avoid the \0 string
pub fn Arg(comptime T: type, comptime name: [:0]const u8, comptime description: []const u8) type {
    validation.validateReservedKeywords(name, null);

    return struct {
        pub const type_id = T;
        pub const field_name = name;
        pub const help = description;
    };
}

pub fn OptArg(comptime T: type, comptime name: [:0]const u8, comptime short: [:0]const u8, default: T, comptime description: []const u8) type {
    // validate both name and short do NOT start with -- and - respectively
    if (name[0] == '-') @compileError("Long name '" ++ name ++ "' must not start with '-'.");
    if (short[0] == '-') @compileError("Short name '" ++ short ++ "' must not start with '-'.");    
    
    validation.validateReservedKeywords(name, short);

    return struct {
        pub const type_id = T;
        pub const field_name = name;
        pub const field_short = short;
        pub const default_value = default;
        pub const help = description;
    };
}

pub fn Flag(comptime name: [:0]const u8, comptime short: [:0]const u8, comptime description: []const u8) type {
    // validate both name and short do NOT start with -- and - respectively
    if (name[0] == '-') @compileError("Long name '" ++ name ++ "' must not start with '-'.");
    if (short[0] == '-') @compileError("Short name '" ++ short ++ "' must not start with '-'.");    
    
    validation.validateReservedKeywords(name, short);

    return struct {
        pub const type_id = bool;
        pub const field_name = name;
        pub const field_short = short;
        pub const default_value = false;
        pub const help = description;

        pub const is_flag = true;
    };

}

/// args_tuple is an anonymous struct containing three tuples, exactly
/// - .required: contains Arg structs
/// - .optional: contains OptArg structs
/// - .flags: contains Flag structs
/// This struct has been validated by the another part
pub fn ArgsStruct(comptime definition: anytype) type {
    
    // const len_cmd = definition.comands.len;
    //
    // var nested_def: ?type = null;
    // if (len_cmd != 0) {
    //     // for element in comands: // hem de tenir un struct per a cada mètode, ja que hem de fer la unió
    //     //  nested_def = ArgsStruct(element);
    //     //
    //     // create union, plug that into the struct
    //     nested_def = ArgsStruct(definition);
    // }

    const len_req = definition.required.len;
    const len_opt = definition.optional.len;
    const len_flg = definition.flags.len;

    const len = len_req + len_opt + len_flg;
    
    var names: [len][]const u8 = undefined;
    var types: [len]type = undefined;
    var attrs: [len]Type.StructField.Attributes = undefined;
    
    // fill required args, they are the first ones
    var i: usize = 0;
    inline for (definition.required) |arg| {
        names[i] = arg.field_name;
        types[i] = arg.type_id;
        
        attrs[i] = .{
            .default_value_ptr = null,  // no default value 
            .@"comptime" = false,       // save it when compiled (user will be able to use it) 
            .@"align" = null,           // natural alignment
        };
        i += 1;
    }

    // fill optional arguments
    inline for (definition.optional) |arg| {
        names[i] = arg.field_name;
        types[i] = arg.type_id;
        
        // we point to the default value
        const ptr: *const anyopaque = @ptrCast(&arg.default_value);
        attrs[i] = .{
            .default_value_ptr = ptr,   // pick the provided default :)
            .@"comptime" = false,       // save it when compiled (user will be able to use it) 
            .@"align" = null,           // natural alignment
        };
        i += 1;
    }
    
    // fill flags
    inline for (definition.flags) |arg| {
        names[i] = arg.field_name;
        types[i] = bool;
        
        // Flags default to false
        const false_val = false; 
        const ptr: *const anyopaque = @ptrCast(&false_val);

        attrs[i] = .{ 
            .@"comptime" = false,        
            .@"align" = null,           // nartural alignment
            .default_value_ptr = ptr    // a pointer to a false
        };
        i += 1;
    }

    return @Struct(.auto, null, &names, &types, &attrs);
}




