const std = @import("std");
const Type = std.builtin.Type;

const validation = @import("validation.zig");

/// Creates a struct (reification) according to the definition description. 
/// definition is an tuple containing tuples with the following four possible names 
/// - .required: contains Arg structs. Will be created as a struct field with type T.
/// - .optional: contains OptArg structs. Will be created as a struct field with type ?T. 
/// - .flags: contains Flag structs. Will be created as a struct field with type bool (false by default)
/// - .commands: contains tuples named as the command option, which contain a ".required", ".optional", ".flags". Will be created as a union called "cmd", which will have all the labels as option
pub fn ArgsStruct(comptime definition: anytype) type {
    
    const definition_type = @TypeOf(definition);
    const len_req = if (@hasField(definition_type, "required")) definition.required.len else 0;
    const len_opt = if (@hasField(definition_type, "optional")) definition.optional.len else 0;
    const len_flg = if (@hasField(definition_type, "flags")) definition.flags.len else 0;
    const arg_len = len_req + len_opt + len_flg;
   
    const len_cmd = if (@hasField(definition_type, "commands")) @typeInfo(@TypeOf(definition.commands)).@"struct".fields.len else 0;
    const are_commands = if (len_cmd > 0) 1 else 0;
        
    const len = arg_len + are_commands;
    
    var names: [len][]const u8 = undefined;
    var types: [len]type = undefined;
    var attrs: [len]Type.StructField.Attributes = undefined;
    
    // fill required args, they are the first ones
    var i: usize = 0;
    if (len_req > 0) {
        inline for (definition.required) |arg| {
            names[i] = arg.field_name;
            types[i] = arg.type_id;
            
            attrs[i] = .{
                .default_value_ptr = null,  // no default value 
                .@"comptime" = false,       // save it when compiled (user will be able to use it) 
                .@"align" = null,           // natural alignment
            };
            i += 1;
        }
    }
    

    // fill optional arguments
    if (len_opt > 0) {
        inline for (definition.optional) |arg| {
            names[i] = arg.field_name;
            types[i] = arg.type_id;
            
            // we point to the default value
            const ptr: *const anyopaque = @ptrCast(&arg.default_value);
            attrs[i] = .{
                .default_value_ptr = ptr,   // pick the provided default :)
                .@"comptime" = false,       // save it when compiled (user will be able to use it) 
                .@"align" = null,           // natural alignment
            };
            i += 1;
        }
    } 
    
    
    // fill flags
    if (len_flg > 0) {
        inline for (definition.flags) |arg| {
            names[i] = arg.field_name;
            types[i] = bool;
            
            // Flags default to false
            const false_val = false; 
            const ptr: *const anyopaque = @ptrCast(&false_val);

            attrs[i] = .{ 
                .@"comptime" = false,        
                .@"align" = null,           // nartural alignment
                .default_value_ptr = ptr    // a pointer to a false
            };
            i += 1;
        }
    }
    
    // parse commands 
    if (len_cmd > 0) {
        const CommandUnion = GenerateCommandUnion(definition.commands); // here the recursion is propagated.
        
        names[i] = "cmd"; 
        types[i] = CommandUnion;
        
        attrs[i] = .{
            .default_value_ptr = null,
            .@"comptime" = false,
            .@"align" = null,
        };
        i += 1;
    }
    
    return @Struct(.auto, null, &names, &types, &attrs);
}

/// Auxiliar function to ArgsStruct which, given a definition.commands, creates a TaggedUnion
/// with an Enum being all the commands listed in the tuple.
fn GenerateCommandUnion(comptime commands_def: anytype) type {
    const Cmd: type = @TypeOf(commands_def);
    const fields_info = @typeInfo(Cmd).@"struct".fields;
    const len = fields_info.len;

    const CurrentCommandsEnum = std.meta.FieldEnum(Cmd);
    
    var names: [len][]const u8 = undefined;
    var types: [len]type = undefined;
    var attrs: [len]Type.UnionField.Attributes = undefined;
    
    inline for (fields_info, 0..) |field, i| {
        names[i] = field.name;

        const cmd_def = @field(commands_def, field.name);
        const CmdStruct = ArgsStruct(cmd_def); // recursive call to ArgsStruct

        types[i] = CmdStruct;

        attrs[i] = .{ .@"align" = @alignOf(CmdStruct) };
    }

    return @Union(.auto, CurrentCommandsEnum, &names, &types, &attrs);
}

