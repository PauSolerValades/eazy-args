const validateReservedKeywords = @import("validation.zig").validateReservedKeywords;

pub const ArgKind = enum { arg, optarg, flag };

/// Creates the Argument Structure
/// name uses [:0] to avoid the \0 string
pub fn Arg(comptime T: type, comptime name: [:0]const u8, comptime description: []const u8) type {
    validateReservedKeywords(name, null);

    return struct {
        pub const type_id = T;
        pub const field_name = name;
        pub const help = description;
        pub const _kind: ArgKind = .arg;
    };
}

pub fn Opt(comptime T: type, comptime name: [:0]const u8, comptime short: [:0]const u8, default: T, comptime description: []const u8) type {
    // validate both name and short do NOT start with -- and - respectively
    if (name[0] == '-') @compileError("Long name '" ++ name ++ "' must not start with '-'.");
    if (short[0] == '-') @compileError("Short name '" ++ short ++ "' must not start with '-'.");    
    
    validateReservedKeywords(name, short);

    return struct {
        pub const type_id = T;
        pub const field_name = name;
        pub const field_short = short;
        pub const default_value = default;
        pub const help = description;
        pub const _kind: ArgKind = .optarg;
    };
}

pub fn Flag(comptime name: [:0]const u8, comptime short: [:0]const u8, comptime description: []const u8) type {
    // validate both name and short do NOT start with -- and - respectively
    if (name[0] == '-') @compileError("Long name '" ++ name ++ "' must not start with '-'.");
    if (short[0] == '-') @compileError("Short name '" ++ short ++ "' must not start with '-'.");    
    
    validateReservedKeywords(name, short);

    return struct {
        pub const type_id = bool;
        pub const field_name = name;
        pub const field_short = short;
        pub const default_value = false;
        pub const help = description;
        pub const is_flag = true;
        pub const _kind: ArgKind = .flag;
    };

}


