# EazyArgs

A simple, type-safe, no boilerplate arg parser for Zig that leverages compile-time meta-programming to generate and fill an struct according to the provided definitions.
Absolutely inspired by @gouwsxander [easy-args](https://github.com/gouwsxander/easy-args) C library.

## Main Idea


EazyArgs leverages type [reification](https://en.wikipedia.org/wiki/Reification_(computer_science)) (create a type instead given a definition instead of explicitly writing it) to allow a much simpler and categorical definition. To parse your program arguments, you just need to define which `flags` the program accepts, which `options` and which `required` (positional) arguments are needed instead of defining the struct, as well as allowing to nest as many definitions as you want with `commands`.

+ **Simple, No Boilerplate**: Define your arguments once. The library generates the types, the validation, and the parser automatically.
+ **Categorical & Nested**: cleanly separate Flags, Options, and Positional arguments. Nest commands as deep as you need (e.g., git remote add origin).
+ [TODO] **Help Generation**: Usage strings are automatically generated from your definitions.
+ **Versatility**: Provides both a GNU and POSIX compliant argument parsing.
+ **Compile-time Specialized**: The validation happens at compile-time. The parser uses `inline` loops, meaning the resulting machine code is optimized specifically for your definition—no generic runtime overhead.

## Simple Example

Import the library and the argument structs and create a tuple like the following code:

```zig
const argz = @import("eazy_args");

const Arg = argz.Arguments;
const OptArg = argz.Option;
const Flag = argz.Flag;

const definition = .{
  .required = .{ // type, field name, description
    Arg(u32, "limit", "Limits are meant to be broken"),
    Arg([]const u8, "username", "Who are you?"),
  },
  .options = .{ // type, field_name, short, default, description
    Opt(u32, "break", "b", 100, "Stop before the limit"),
    Opt(f64, "step", "s", 1.0, "Subdivision of the interval"),
  },
  .flags = .{ // field_name, short, description - default is false
    Flag("verbose", "v", "More info"),
    Flag("optimization", "o", "Go faster, but at what cost?"),
  }
};
```

Then parse it with the `parseArgs` function.

```zig
const args = try init.minimal.args.toSlice(init.gpa); 
defer init.gpa.free(args);
const gnuargs = argz.parseArgs(init.gpa, definition, args, stdout, stderr) catch |err| {
  switch (err) {
    ParseErrors.HelpShown => try stdout.flush(),
    else => try stderr.flush(),
  }
  std.process.exit(0);
};
```


## Features

The function seen in the previous example, `parseArgs`, implements the GNU [Program Argument Syntax Conventions](https://sourceware.org/glibc/manual/latest/html_mono/libc.html#Program-Arguments). This is what imposes the least restrictive parsing rules, where any option can be in any order, that is `utility 100 "Pau" -b 100 -s 0.5 -v -o` and any combination of those - e.g. `utility -b 20 100 -v -o "Pau" -s 0.5`, despite being super bizarre, will be parsed -  and the `=` can be used to specify the value of options `--break=100`.

EazyArgs also provides a POSIX compliant with the [Utility Argument Syntax](https://pubs.opengroup.org/onlinepubs/9699919799/basedefs/V1_chap12.html) parse function, `parseArgsPosix` like the following code. (TODO: fix the = to not be possible, think to implement or and the [ ] name parsing)

```zig
var iter = init.minimal.args.iterate(); 
const posixargs = argz.parseArgsPosix(definition, &iter, stdout, stderr) catch |err| {
  switch (err) {
    ParseErrors.HelpShown => try stdout.flush(),
    else => try stderr.flush(),
  }
  std.process.exit(0);
};
```

`parseArgsPosix` will parse the commands in the following specific order:

```
utility_name [-a] [-b] [-c option_argument] [-d|-e] [-f[option_argument]] [required...]
```


The POSIX implementation has three main advantages directly related to the strict argument order when compared to `parseArgs`.
+ No dynamic memory: there is no need to use memory allocation, so no `Allocator` needed.
+ No arg slice: the function accepts a `*Args.Iterator` instead of an slice. This will require an allocator in Windows `var iter = init.minimal.args.iterateAllocator(allocator)`.
+ Efficiency: it's exactly $O(n)$ complexity, where n is the number of element in the *Args.Iterator. `parseArgs` requires three full sweeps over the original list for every different command and subcommands of that (it grows to the cube).


## Command example

Adding commands in the definition can be done with the following syntax:

```
const definition = .{
    .flags = .{ Flag("verbose", "v", "Enable detailed logging") },
    .commands = .{
        .query = .{
            .required = .{ Arg([]const u8, "statement", "The SQL statement to run") },
            .optional = .{
                Opt(u32, "limit", "l", 100, "Max rows to return"),
                Opt([]const u8, "format", "f", "table", "Output format"),
            },
        },
        .backup = .{
            .required = .{ Arg([]const u8, "path", "Destination file path") },
            .flags = .{ Flag("compress", "z", "GZIP compress the output") },
        },
    },
};
```

This will generate a `cmd: TaggedUnion` in the struct, where the Enum is `{query, backup}`. 

The parsed struct contains your global flags and a cmd field, which is a union of your subcommands.

```zig
const args = try eaz.parseArgs(definition, os_args, stdout, stderr);

// global flag access is at the root
if (args.verbose) {
    try stdout.print("[LOG] Verbose mode enabled\n", .{});
}

// active tag tells you which command has been selected
try stdout.print("Selected command: {s}\n", .{ @tagName(args.cmd) });
```

Since `cmd` is a tagged union, the most ergonomic way to handle logic is a switch statement. This gives you type-safe access to the specific fields of query or backup.

```
switch (args.cmd) {
    .query => |q| {
        try stdout.print("Running SQL: \"{s}\"\n", .{q.statement});
        // doSomeStuff(); 
        try stdout.print("Limit: {d} | Format: {s}\n", .{ q.limit, q.format });
    },
    .backup => |b| {
        try stdout.print("Backing up to: {s}\n", .{b.path});
        if (b.compress) {
            try stdout.print("(Compression enabled)\n", .{});
        }
        // doSomeStuff()
    },
}
```

## Nested Subcommands

A command can be added inside a command lable, as the following example

## Help String

Use `help` as a first argument to print the help string:

```
$: ./program help
Usage: app [options] <limit> <username>

Positional Arguments:
  limit        (u32): Limits are meant to be broken
  username     ([]const u8): who are you dear?

Options:
  -b, --break        <u32>: Stop before the limit (default: 100)
  -v, --verbose            : Print a little, print a lot
```


You cannot declare a positional argument called `help` nor a optional/flag called `--help` or `-h`, those are reserved and will throw a compile time error.

## API Reference

Arg (Positional)
+ Type: The Zig type to parse (e.g., u32, []const u8, bool).
+ Name: The field name in the struct.
+ Description: Help text displayed in usage.

OptArg (Optional Option)
+ Type: The value type. 
+ Name: Long flag name (e.g., "port" → --port).
+ Short: Short flag alias (e.g., "p" → -p).
+ Default: The value used if the flag is omitted (Must match Type).
+ Description: Help text.

Flag (Boolean Switch)
+ Name: Long flag name.
+ Short: Short flag alias.
+ Description: Help text.

Note: Flags are always bool and default to false.


