const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;
const Args = std.process.Args;

const reification = @import("reification.zig");
const validation = @import("validation.zig");

// make the structs public to access them from main
pub const ArgsStruct = reification.ArgsStruct;
pub const Arg = reification.Arg; 
pub const OptArg = reification.OptArg;
pub const Flag = reification.Flag;

pub const ParseErrors = error { HelpShown, MissingArgument, MissingValue, UnknownArgument, UnexpectedArgument };

/// The function parses 
pub fn parseArgs(comptime args_def: anytype, args_iter: *Args.Iterator, stdout: *Io.Writer, stderr: *Io.Writer) !ArgsStruct(args_def){
    _ = stdout;
    _ = stderr;

    // this will throw a compile error if not valid
    validation.validateDefinition(args_def);

    // create the reificated type 
    const ResultType = ArgsStruct(args_def);
    // 1. Check if ResultType has a cmd with typeInfo(ResultType).@"struct".fileds { if f.name == cmd}
    // 2. That is going to be a Union, use the below line to get the enums
    const UnionTag = std.meta.Tag(ResultType.cmd);
    // 3. use std.meta.stringToEnum(UnionTagType, current_arg) to check!
    
    // Rule 1: every subcommands must be at the beginning.
    while(true) {
        const current_arg = args_iter.next();
        
        if (std.meta.stringToEnum(UnionTag, current_arg)) {
            // és una commanda!
            std.debug.print("Això és una commands\n", .{});
        } else {
            std.debug.print("Això no és una commanda", .{});
        }

        
    }


}
// ULL aquí he posat anyerror mentre no reescric la funció per anar amb commands i que hi puguin haver-hi llistes buides :)
pub fn old_parseArgs(allocator: Allocator, comptime args_def: anytype, args_iter: *Args.Iterator, stdout: *Io.Writer, stderr: *Io.Writer) anyerror!ArgsStruct(args_def) {
    _ = allocator;
    validation.validateDefinition(args_def);
    
    const ResultType = ArgsStruct(args_def);
    var result: ResultType = undefined;
    
    // options must be initialized to default value
    inline for (args_def.optional) |opt| {
        @field(result, opt.field_name) = opt.default_value;
    }

    // all flags to false by default 
    inline for (args_def.flags) |flg| {
        @field(result, flg.field_name) = false;
    }
    
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

