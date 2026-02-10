const std = @import("std");
const Io = std.Io;
const Args = std.process.Args;

pub const ParseErrors = error { HelpShown, MissingArgument, MissingValue, UnknownArgument, UnexpectedArgument };

/// Auxiliar function to put in stderr (writer) a recurrent
/// error management when parsing a value.
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
            try writer.print("Error: The type '{s}' defined for '{s}' is not supported.\n", .{ @typeName(T), arg_name });
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

pub const ContextNode = struct {
    name: []const u8,
    parent: ?*const ContextNode = null,
    
    pub fn format(
        self: ContextNode,
        writer: *Io.Writer,
    ) !void {
        if (self.parent) |p| {
            try p.format(writer);
            try writer.print(" {s}", .{self.name});
        } else {
            try writer.print("{s}", .{self.name});
        }
    }
};

/// Prints the help message. Depending on which level of the definition is called,
/// the behaviour will change.
pub fn printUsageCtx(comptime def: anytype, context: ?*const ContextNode, writer: *Io.Writer) !void {
    const T = @TypeOf(def);
    
    const is_root = if (context) |ctx| ctx.parent == null else true;
    // print description, if it's not found is left blank
    
    if (is_root and @hasField(T, "description")) {
        try writer.print("{s}\n\n", .{def.description});
    }
    
    try writer.writeAll("Usage: "); // usage line
    
    if (context) |ctx| {
        try writer.print("{f} ", .{ctx.*});
    } else {
        if (@hasField(T, "name")) {
            try writer.print("{s} ", .{def.name});
        } else {
            try writer.writeAll("app ");
        }
    }
    
    if (@hasField(T, "options") or @hasField(T, "flags")) {
        try writer.writeAll("[options] ");
    }

    // Print [commands] placeholder
    if (@hasField(T, "commands")) {
          try writer.writeAll("[commands]");
    } else if (@hasField(T, "required")) {
        inline for (def.required) |req| {
            try writer.print("<{s}> ", .{req.field_name});
        }
    }
    try writer.writeAll("\n");
    
    if (!is_root and @hasField(T, "description")) {
        try writer.print("\nDescription: {s}\n", .{def.description});
    }
    
    try writer.writeAll("\n");

    //options and flags
    if (@hasField(T, "options") or @hasField(T, "flags")) {
        try writer.writeAll("Options:\n");
        if (@hasField(T, "flags")) {
            inline for (def.flags) |flag| {
                try writer.print("  -{s}, --{s: <15} {s}\n", 
                    .{flag.field_short, flag.field_name, flag.help});
            }
        }
        if (@hasField(T, "options")) {
            inline for (def.options) |opt| {
                 try writer.print("  -{s}, --{s: <15} {s}\n", 
                    .{opt.field_short, opt.field_name, opt.help});
            }
        }
        try writer.writeAll("\n");
    }

    if (@hasField(T, "commands")) {
        try writer.writeAll("Commands:\n");
        try printCommandTree(def.commands, writer, 2);
        try writer.writeAll("\n");
    }

    if (@hasField(T, "required") and !@hasField(T, "commands")) {
        try writer.writeAll("Arguments:\n");
        inline for (def.required) |req| {
            try writer.print("  {s: <15} {s}\n", .{req.field_name, req.help});
        }
        try writer.writeAll("\n");
    }
}

/// Helper to print the tree recursively
fn printCommandTree(comptime cmds: anytype, writer: anytype, indent: usize) !void {
    const fields = @typeInfo(@TypeOf(cmds)).@"struct".fields;

    inline for (fields) |f| {
        const cmd_def = @field(cmds, f.name);
        
        // Print the Command Name + Description
        for (0..indent) |_| {
            try writer.writeByte(' ');
        }
        try writer.print("{s: <21}", .{f.name});
        
        if (@hasField(@TypeOf(cmd_def), "description")) {
            try writer.print(" {s}", .{cmd_def.description});
        }
        try writer.writeAll("\n");

        // Recursion to print all the subleafs!
        if (@hasField(@TypeOf(cmd_def), "commands")) {
            try printCommandTree(cmd_def.commands, writer, indent + 2);
        }
    }
}


const PeekIterator = struct { 
    iterator: Args.Iterator,
    current: ?[:0]const u8,

    pub fn init(self: @This(), args: *Args.Iterator) void {
        return PeekIterator{
            .iterator = &args,
            .current = self.iterator.next(),
        };
    }

    pub fn peek(self: @This()) ?[:0]const u8 {
        return self.current;
    }

    pub fn next(self: @This()) ?[:0]const u8 {
        const val = self.current;
        self.current = self.init.next();
        return val; 
    }
};



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


