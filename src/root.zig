const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;

const arg_struct = @import("arg_structs.zig");

pub const ArgsStruct = arg_struct.ArgsStruct;
pub const Arg = arg_struct.Arg; // make the struct public for the import of the library
pub const OptArg = arg_struct.OptArg;
pub const Flag = arg_struct.Flag;

fn isHelp(s: []const u8) bool {
    return std.mem.eql(u8, s, "-h") or 
           std.mem.eql(u8, s, "--help") or 
           std.mem.eql(u8, s, "help"); // Catches the specific case you asked for!
}

pub fn parseArgs(allocator: Allocator, comptime args_def: anytype, stdout: *Io.Writer, stderr: *Io.Writer) !ArgsStruct(args_def) {
    arg_struct.validateDefinition(args_def);
    const ResultType = ArgsStruct(args_def);
    var result: ResultType = undefined;

    var args_iter = try std.process.argsWithAllocator(allocator);
    defer args_iter.deinit();

    _ = args_iter.skip(); 

    inline for (args_def.required, 0..) |req_def, i| {
        
        const arg_str = args_iter.next() orelse {
            try stderr.print("Error: Missing argument '{s}'\n", .{req_def.field_name});
            try printUsage(args_def, stderr);
            return error.MissingArgument;
        };
        
        // if first argument is help 
        if (i == 0) {
            if (std.mem.eql(u8, arg_str, "help")) {
                try printUsage(args_def, stdout);
                return error.HelpShown;
            }
        }

        // if --help or -h appears
        if (std.mem.eql(u8, arg_str, "-h") or std.mem.eql(u8, arg_str, "--help")) {
            try printUsage(args_def, stdout);
            return error.HelpShown;
        }

        @field(result, req_def.field_name) = try parseValue(req_def.type_id, arg_str);
    }


    while (args_iter.next()) |arg_str| {
        // must start with '-'
        if (arg_str.len < 2 or arg_str[0] != '-') {
            try stderr.print("Error: Unexpected argument '{s}'\n", .{arg_str});
            return error.UnexpectedArgument;
        }

        // check against all known options (Expects value)
        var matched = false;
        inline for (args_def.optional) |opt| {
            // Check long name (--) and short name (-)
            const is_long  = std.mem.eql(u8, arg_str[2..], opt.field_name);
            const is_short = std.mem.eql(u8, arg_str[1..], opt.field_short);

            if (is_long or is_short) {
                // Grab the value for this option
                const val_str = args_iter.next() orelse {
                    try stderr.print("Error: Option '{s}' requires a value\n", .{opt.field_name});
                    return error.MissingValue;
                };
                @field(result, opt.field_name) = try parseValue(opt.type_id, val_str);
                matched = true;
            }
        }

        // all known FLAGS (No value, just true)
        inline for (args_def.flags) |flg| {
            const is_long  = std.mem.eql(u8, arg_str[2..], flg.field_name);
            const is_short = std.mem.eql(u8, arg_str[1..], flg.field_short);

            if (is_long or is_short) {
                @field(result, flg.field_name) = true;
                matched = true;
            }
        }

        if (!matched) {
            try stderr.print("Error: Unknown argument '{s}'\n", .{arg_str});
            try printUsage(args_def, stderr);
            return error.UnknownArgument;
        }
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

    if (args_def.optional.len > 0 or args_def.flags.len > 0) {
        try writer.print(" [options]", .{});
    }

    inline for (args_def.required) |arg| {
        try writer.print(" <{s}>", .{arg.field_name});
    }
    try writer.print("\n\n", .{});

    if (args_def.required.len > 0) {
        try writer.print("Positional Arguments:\n", .{});
        inline for (args_def.required) |arg| {
            try writer.print("  {s:<12} ({s}): {s}\n", .{
                arg.field_name,
                @typeName(arg.type_id),
                arg.help,
            });
        }
        try writer.print("\n", .{});
    }

    if (args_def.optional.len > 0 or args_def.flags.len > 0) {
        try writer.print("Options:\n", .{});

        // Print Options (Key + Value)
        inline for (args_def.optional) |arg| {
            // Format: -p, --port <u32>
            try writer.print("  -{s}, --{s:<12} <{s}>: {s} (default: {any})\n", .{
                arg.field_short,
                arg.field_name,
                @typeName(arg.type_id),
                arg.help,
                arg.default_value,
            });
        }

        inline for (args_def.flags) |arg| {
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

