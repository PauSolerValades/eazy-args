const std = @import("std");
const meta = std.meta;

pub fn main() !void {
    // lets try to parse a union with no other arguments
    
    const definition = .{
        .commands = .{
            .name1 = .{
                .required = .{f32},
                .optional = .{f64},
                .flags = .{},
            },
            .name2 = .{
                .required = .{u32},
                .optional = .{u64},
                .flags = .{},
            }
        }
    };
    
    
    ArgsStruct(definition);

    //std.debug.print("{any}\n", .{result});
}

pub fn ArgsStruct(comptime definition: anytype) void {
        //const ComandEnum = meta.FieldEnum(definition.command);
    const CmdType: type = @TypeOf(definition.commands); 
    const cmd_info = @typeInfo(CmdType);

    inline for (cmd_info.@"struct".fields) |field| {
        const cmd_name = field.name;
        std.debug.print("{s}\n", .{cmd_name});
    }

}
