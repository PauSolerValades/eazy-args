const std = @import("std");
const Type = std.builtin.Type;


/// Creates the Argument Structure
/// name uses [:0] to avoid the \0 string
pub fn Arg(comptime T: type, comptime name: [:0]const u8, comptime description: []const u8) type {
    validateReserved(name, null);

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
    
    validateReserved(name, short);

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
    
    validateReserved(name, short);

    return struct {
        pub const type_id = bool;
        pub const field_name = name;
        pub const field_short = short;
        pub const default_value = false;
        pub const help = description;

        pub const is_flag = true;
    };

}

fn validateReserved(comptime name: []const u8, comptime short: ?[]const u8) void {
    // Check Long Name
    if (std.mem.eql(u8, name, "help")) {
        @compileError("Argument name 'help' is reserved by the library. Please pick a different name.");
    }

    // Check Short Name (if it exists)
    if (short) |s| {
        if (std.mem.eql(u8, s, "h")) {
            @compileError("Short argument 'h' is reserved for help. Please pick a different character.");
        }
    }
}

/// args_tuple is an anonymous struct containing three tuples, exactly
/// - .required: contains Arg structs
/// - .optional: contains OptArg structs
/// - .flags: contains Flag structs
/// This struct has been validated by the another part
pub fn ArgsStruct(comptime definition: anytype) type {
    const len_req = definition.required.len;
    const len_opt = definition.optional.len;
    const len_flg = definition.flags.len;

    const len = len_req + len_opt + len_flg;
    
    var names: [len][]const u8 = undefined;
    var types: [len]type = undefined;
    var attrs: [len]Type.StructField.Attributes = undefined;
    
    // Fill required args, they are the first ones
    var i: usize = 0;
    inline for (definition.required) |arg| {
        names[i] = arg.field_name;
        types[i] = arg.type_id;
        
        attrs[i] = .{
            .default_value_ptr = null,  // no fucking clue
            .@"comptime" = false,       // save it when compiled (user will be able to use it) 
            .@"align" = null,           // natural alignment
        };
        i += 1;
    }

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
    
    inline for (definition.flags) |arg| {
        names[i] = arg.field_name;
        types[i] = bool;
        
        // Flags default to false
        const false_val = false; 
        const ptr: *const anyopaque = @ptrCast(&false_val);

        attrs[i] = .{ 
            .@"comptime" = false,
            .@"align" = null, 
            .default_value_ptr = ptr 
        };
        i += 1;
    }

    return @Struct(.auto, null, &names, &types, &attrs);
}

/// as we can't make a specific struct for the definitions, we must validate whatever the user passes
/// is what its actually expected
pub fn validateDefinition(comptime defs: anytype) void {
    const T = @TypeOf(defs);
    const typeInfo = @typeInfo(T);

    if (typeInfo != .@"struct") {
        @compileError("Definitions must be a struct like .{ .required = ... }");
    }

    if (!@hasField(T, "required")) @compileError("Missing field: .required");
    if (!@hasField(T, "optional"))  @compileError("Missing field: .optional");
    if (!@hasField(T, "flags"))    @compileError("Missing field: .flags");
    
    const required: type = @TypeOf(defs.required);
    if (!@typeInfo(required).@"struct".is_tuple) 
        @compileError(".required must be a tuple `.{ ... }`");
}

