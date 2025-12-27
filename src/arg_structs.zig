const std = @import("std");
const Type = std.Type;

/// Creates the Argument Structure
/// name uses [:0] to avoid the \0 string
pub fn Arg(comptime T: type, comptime name: [:0]const u8, comptime description: []const u8) type {
    return struct {
        pub const type_id = T;
        pub const field_name = name;
        pub const help = description;
    };
}

fn GeneratedStruct(comptime args_tuple: anytype) type {
    const len = args_tuple.len;
    
    var names: [len][]const u8 = undefined;
    var types: [len]type = undefined;
    
    // fill the attributes
    var attrs: [len]Type.StructField.Attributes = undefined;

    inline for (args_tuple, 0..) |arg, i| {
        names[i] = arg.field_name;
        types[i] = arg.type_id;
        
        attrs[i] = .{
            .default_value_ptr = null,  // no fucking clue
            .@"comptime" = false,       // save it when compiled (user will be able to use it) 
            .@"align" = null,           // natural alignment
        };
    }
    
    // return an Struct with the data you've specified
    return @Struct(.auto, null, &names, &types, &attrs);
}

