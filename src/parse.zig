const std = @import("std");
const Io = std.Io;

pub const ParseErrors = error { HelpShown, MissingArgument, MissingValue, UnknownArgument, UnexpectedArgument };

pub fn printValueError(
    writer: *Io.Writer, 
    err: anyerror, 
    arg_name: []const u8, 
    raw_value: []const u8, 
    comptime T: type
) !void {
    switch (err) {
        error.InvalidValue => {
            try writer.print("Error: Invalid value '{s}' for argument '{s}'. Expected type: {s}\n", .{ raw_value, arg_name, @typeName(T) });
        },
        error.UnsupportedType => {
            try writer.print("Error: [Bug] The type '{s}' defined for '{s}' is not supported by EazyArgs.\n", .{ @typeName(T), arg_name });
        },
        else => {
            try writer.print("Error: Failed to parse argument '{s}': {s}\n", .{ arg_name, @errorName(err) });
        }
    }
}

/// parses the values from the command line
pub fn parseValue(comptime T: type, str: []const u8) !T {
    switch(@typeInfo(T)) {
        .int => return std.fmt.parseInt(T, str, 10),
        .float => return std.fmt.parseFloat(T, str),
        .bool => {
            if (std.mem.eql(u8, str, "true")) { return true; }
            else if (std.mem.eql(u8, str, "false")) { return false; }
            else { return error.InvalidArgument; }
        },
        .optional => |opt| return try parseValue(opt.child, str), 
        
        else => {
            if (T == []const u8) {
                return str;
            }

            return error.UnsupportedType;
        },
    }

    
    return error.UnsupportedType;
}

pub fn printUsage(comptime definition: anytype, writer: *Io.Writer) !void {
    _ = definition;
    try writer.writeAll("This is the usage that I will definetly do xd\n");
    return;
}

fn OldPrintUsage(comptime definition: anytype, writer: *Io.Writer) !void {
    try writer.writeAll("Usage: app");

    if (@hasField(definition, "optional") and definition.optional.len > 0) {
        try writer.writeAll(" [options]");
    }
    if (@hasField(definition, "flags") and definition.flags.len > 0) {
        try writer.writeAll(" [options]");
    }

    inline for (definition.required) |arg| {
        try writer.print(" <{s}>", .{arg.field_name});
    }
    try writer.print("\n\n", .{});

    if (definition.required.len > 0) {
        try writer.print("Positional Arguments:\n", .{});
        inline for (definition.required) |arg| {
            try writer.print("  {s:<12} ({s}): {s}\n", .{
                arg.field_name,
                @typeName(arg.type_id),
                arg.help,
            });
        }
        try writer.print("\n", .{});
    }

    if (definition.optional.len > 0 or definition.flags.len > 0) {
        try writer.print("Options:\n", .{});

        // Print Options (Key + Value)
        inline for (definition.optional) |arg| {
            // Format: -p, --port <u32>
            try writer.print("  -{s}, --{s:<12} <{s}>: {s} (default: {any})\n", .{
                arg.field_short,
                arg.field_name,
                @typeName(arg.type_id),
                arg.help,
                arg.default_value,
            });
        }

        inline for (definition.flags) |arg| {
            try writer.print("  -{s}, --{s:<12}       : {s}\n", .{
                arg.field_short,
                arg.field_name,
                arg.help,
            });
        }
        try writer.print("\n", .{});
    }
}


const talloc = std.testing.allocator;
const expect = std.testing.expect;
const expectEqualStrings = std.testing.expectEqualStrings;

test "parseValue successful" {
    const p1 = try parseValue(u32, "16");
    try expect(@as(u32, 16) == p1);

    const p2 = try parseValue(u64, "219873");
    try expect(@as(u64, 219873) == p2);

    const p3 = try parseValue(u16, "8");
    try expect(@as(u16, 8) == p3);

    const p4 = try parseValue(i32, "-1");
    try expect(@as(i32, -1) == p4);

    const p5 = try parseValue(usize, "4");
    try expect(@as(usize, 4) == p5);
    
    const p6 = try parseValue(f64, "3.14");
    try expect(@as(f64, 3.14) == p6);

    const p7 = try parseValue(f32, "3");
    try expect(@as(f32, 3) == p7);

    const p8 = try parseValue(bool, "true");
    try expect(true == p8);

    const p9 = try parseValue(bool, "false");
    try expect(false == p9);

    const p10 = try parseValue([]const u8, "quelcom");
    try expectEqualStrings(p10, "quelcom");
}

const expectError = std.testing.expectError;
const ParseFloatError = std.fmt.ParseFloatError;
const ParseIntError = std.fmt.ParseIntError;

test "parseValue errors" {
    try expectError(ParseFloatError.InvalidCharacter, parseValue(f64, "a"));
    try expectError(ParseIntError.Overflow, parseValue(u8, "-1"));
    try expectError(ParseIntError.InvalidCharacter, parseValue(u8, "a"));

    try expectError(error.InvalidArgument, parseValue(bool, "ture"));
}


