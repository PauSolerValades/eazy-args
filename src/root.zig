const std = @import("std");
const Allocator = std.mem.Allocator;
const arg_struct = @import("arg_structs.zig");
const Io = std.Io;

pub const ArgsStruct = arg_struct.ArgsStruct;
pub const Arg = arg_struct.Arg;

pub fn parseArgs(allocator: Allocator, comptime args_def: anytype, stderr: *Io.Writer) !ArgsStruct(args_def) {
    const ResultType = ArgsStruct(args_def);
    var result: ResultType = undefined;

    var args_iter = try std.process.argsWithAllocator(allocator);
    defer args_iter.deinit();

    _ = args_iter.skip(); 

    // THE ZIPPER: Iterate fields (Comptime) + consume args (Runtime)
    // We look at the *fields* of the generated type directly.
    const struct_fields = @typeInfo(ResultType).@"struct".fields;

    inline for (struct_fields) |field| {
        const arg_str = args_iter.next() orelse {
            std.debug.print("\n[ERROR] Missing argument: '{s}'\n\n", .{field.name});
            try printUsage(args_def, stderr);
            return error.MissingArgument;
        };
        const parsed_val = try parseValue(field.type, arg_str);
        
        // @field(result, name) allows us to access the struct field dynamically by string name
        @field(result, field.name) = parsed_val;
    }
    
    if (args_iter.next()) |_| {
        return error.TooManyArguments;
    }

    return result;
}

fn parseValue(comptime T: type, str: []const u8) !T {
    switch(@typeInfo(T)) {
        .int => return std.fmt.parseInt(T, str, 10),
        .float => return std.fmt.parseFloat(T, str),
        .bool => {
            if (std.mem.eql(u8, str, "true")) { return true; }
            else if (std.mem.eql(u8, str, "false")) { return false; }
            else { return error.InvalidArgument; }
        },
        else => {
            if (T == []const u8) {
                return str;
            }

            return error.UnsupportedType;
        },
    }

    
    return error.UnsupportedType;
}


fn printUsage(comptime args_def: anytype, writer: *Io.Writer) !void {

    try writer.print("Usage: app", .{});
    inline for (args_def) |arg| {
        std.debug.print(" <{s}>", .{arg.field_name});
    }
    std.debug.print("\n\nArguments:\n", .{});

    inline for (args_def) |arg| {
        const type_name = @typeName(arg.type_id);
        
        std.debug.print("  {s:<10} ({s}): {s}\n", .{
            arg.field_name, 
            type_name, 
            arg.help
        });
    }
    std.debug.print("\n", .{});
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

