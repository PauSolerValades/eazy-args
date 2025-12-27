const std = @import("std");

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

