const std = @import("std");
const meta = std.meta;
const Type = std.builtin.Type;

const reification = @import("reification.zig");
const Arg = reification.Arg;
const OptArg = reification.OptArg;

pub fn main() !void {
    
    const definition = .{
        .commands = .{
            .entry = .{ 
                .required = .{ Arg([]const u8, "description", "What are you doing") },
                .optional = .{ OptArg(?usize, "project", "p", null, "Which project does the entry belong")},
                .flags = .{},
                .commands = .{},
            },
            .project = .{ 
                .required = .{ Arg([]const u8, "Name", "Which project is this") },
                .optional = .{ OptArg(?usize, "subproject", "sp", null, "Child of subprojectid") },
                .flags = .{},
                .commands = .{},
            },
        },
        .required = .{},
        .optional = .{},
        .flags = .{},
    };
    
    
    const Result: type = reification.ArgsStruct(definition);
    
    std.debug.print("{any}\n", .{Result});
    const typeInfo = @typeInfo(Result);
    
    std.debug.print("Struct Name: {s}\n", .{@typeName(Result)});
    std.debug.print("Fields found:\n", .{});
    
    inline for (typeInfo.@"struct".fields) |f| {
        std.debug.print(" - Name: '{s}', Type: {s}\n", .{f.name, @typeName(f.type)});

        // if (std.mem.eql(u8, @typeName(f.type), "union")) { 
        //     std.debug.print("{any}\n", .{@typeInfo(f.type).@"union".fields});
        // }
        //std.debug.print("{any}\n", .{@typeInfo(f.type).@"union".fields});

    }
    
    const Precision = enum {
        single,
        double,
    };
    const NormalUnion = union(Precision) {
        single: f32,
        double: f64,
    };

    const NormalStruct = struct{
        u: NormalUnion,
        b: usize,
    };
    
    const un = NormalUnion{.single = 3.2 };
    const b: usize = 2;
    const n = NormalStruct{.u = un, .b = b };
    const UnionTag = std.meta.Tag(@TypeOf(n.u));
    
    std.debug.print("{any}\n", .{UnionTag});
    
}


pub fn ArgsStructSketch(comptime definition: anytype) void {
    const CmdType: type = @TypeOf(definition.commands); 
    const cmd_info = @typeInfo(CmdType);

    inline for (cmd_info.@"struct".fields) |field| {
        const cmd_name = field.name;
        std.debug.print("{s}\n", .{cmd_name});
        const current_definition = @field(definition.commands, cmd_name); //this should be the definition struct
        std.debug.print("{any}\n", .{current_definition});
    }

}
