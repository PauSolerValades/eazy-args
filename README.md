# EazyArgs

A simple, type-safe, no boilerplate arg parser for Zig that leverages compile-time meta-programming to generate and fill an struct according to the provided definitions.
Absolutely inspired by @gouwsxander [easy-args](https://github.com/gouwsxander/easy-args) C library.

## Main Idea


EazyArgs leverages type [reification](https://en.wikipedia.org/wiki/Reification_(computer_science)) (create a type from a given definition instead of explicitly writing the type) to allow a much simpler and categorical definition. To parse your program arguments, you just need to define which `flags` the program accepts, which `options` and which `required` (positional) arguments are needed instead of writing the struct code. Additionally, supports `commands` to nest definitions inside the main definition.

Features:
+ **Simple, No Boilerplate**: Define your arguments once. The library generates the types, the validation, and the parser automatically.
+ **Categorical & Nested**: cleanly separate Flags, Options, and Positional arguments. Nest commands as deep as you need (e.g., git remote add origin).
+ **Help Generation**: Usage strings are automatically generated from your definitions.
+ **Versatility**: Provides both a GNU and POSIX compliant argument parsing.
+ **Compile-time Specialized**: The validation happens at compile-time. The parser uses `inline` loops, meaning the resulting machine code is optimized specifically for your definition—no generic runtime overhead.

## Simple Example
_[See `examples/simple_example.zig`]_

Import the library and the following structs. Then create a tuple like the following code:

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

Parse it with the `parseArgs` function to obtain a struct with all the command line arguments parsed.

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

The function seen in the previous example, `parseArgs`, implements the GNU [Program Argument Syntax Conventions](https://pubs.opengroup.org/onlinepubs/9799919799/): any argument can be in provided at any point, that is `utility 100 "Pau" -b 100 -s 0.5 -v -o` and any permutation of those - e.g. `utility -b 20 100 -v -o "Pau" -s 0.5`, despite being super bizarre - will be properly parsed. If also supports providing and option as `--break=100` using the `=` instead of the space.

EazyArgs also provides a POSIX compliant with the [Utility Argument Syntax](https://pubs.opengroup.org/onlinepubs/9699919799/basedefs/V1_chap12.html) parse function, `parseArgsPosix` like the following code.

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
+ No arg slice: the function accepts a `*std.process.Args.Iterator` instead of an slice. This will require an allocator in Windows `var iter = init.minimal.args.iterateAllocator(allocator)`.
+ Efficiency: it's exactly $O(n)$ complexity, where n is the number of element in the *Args.Iterator. `parseArgs` requires three full sweeps over the original list for every different command and subcommands of that (it grows to the cube).

At the end of the README there is a section regarding fully compliance with POSIX standards. **WARNING**: at this time, not ALL functionality for POSIX is implemented, as well as the help string, which does not work! At the end of the document this is discussed more in depth.

## Command example
_[See `examples/database.zig`]_

Adding commands in the definition can be done adding a `command` label and defining the names of the commands, like the following snippet shows:

```zig
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

This will generate a `cmd: TaggedUnion` in the struct, where the Enum is `{query, backup}` (all the labels provided inside the command tuple). 

The parsed struct contains your global flags and a `cmd` field, which is a union of the subcommands provided.

```zig
const args = try argz.parseArgs(definition, iter, stdout, stderr);

// global flag access is at the root
if (args.verbose) {
    try stdout.print("[LOG] Verbose mode enabled\n", .{});
}

// active tag tells you which command has been selected
try stdout.print("Selected command: {s}\n", .{ @tagName(args.cmd) });
```

Since `cmd` is a tagged union, the most ergonomic way to branch the flow of the program is a switch statement on the `cmd` argument. This gives you type-safe access to the specific fields of query or backup.

```zig
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
_[See `exapmles/tally.zig`]_

Commands can be defined one inside the other adding a `command` inside the label, as the following example (a nice terminal time tracker) shows. The example uses variables to make the definition more readable.

```zig
 const entry_start = .{
    .required = .{ Arg([]const u8, "description", "What are you doing now?") },
    .options = .{ Opt(?u64, "projectid", "p", null, "Which project the entry belongs to")}
};

const project_create = .{
    .required = .{ Arg([]const u8, "description", "What project are you doing") },
    .options = .{ Opt(?u64, "parent", "p", null, "Which project is this under?")}
};

const project_rename = .{
    .required = .{ 
        Arg(u64, "projectid", "Project to change the name"),
        Arg([]const u8, "name", "New name for the project"),
    }
};

const def = .{
    .flags = .{ Flag("v", "verbose", "Print more" ) },
    .commands = .{
        .entry = .{
            .commands = .{
            .start = entry_start,
            .status = .{},
            .stop = .{},
            }
        },
        .project = .{
            .commands = .{
                .create = project_create,
                .rename = project_rename,
            }
        },
    }
};
```

To allow for multiple nesting within commands the following rules will be enforced by the compiler:
1. In each level there is either a `required` or a `commands`, they are mutually exclusive.
2. Once a `required` appears in a given level, no sublevel under it can contain a `command`.
3. `flags` and `options` are optional, and can or can't appear.

Once parsed, it can be accessed with nested switch statements:

```zig
const args = try init.minimal.args.toslice(init.gpa);
defer init.gpa.free(args);
const arguments = argz.parseargs(init.gpa, def, args, stdout, stderr) catch |err| {
    switch (err) {
        parseerrors.helpshown => try stdout.flush(),
        else => try stderr.flush(),
    }
    std.process.exit(0);
};

// access it with a switch, clean and easy (args haha)
switch (arguments.cmd) {
    .entry => |entry_cmd| {
        switch (entry_cmd.cmd) {
            .start => |start_args| {
                try stdout.print("'entry start' detected!\n", .{});
                if (start_args.projectid) |pid| {
                    try stdout.print("detected pid: {d}\n", .{pid});
                } else {
                    try stdout.writeall("no pid detected\n");
                }
            },
            .stop => try stdout.writeall("'entry stop' detected!\n"),
            .status => try stdout.writeall("'entry status' detected!\n"),
        }
    },
    .project => |project_cmd| {
        switch (project_cmd.cmd) {
            .create => |create_args| {
                  try stdout.print("creating project: {s}\n", .{create_args.description});
            },
            .rename => |rename_args| {
                  try stdout.print("renaming id {d} to {s}\n", .{rename_args.projectid, rename_args.name});
            }
        } 
    }
}
```


## Help String
_[See src/main.zig]_

Use `help` as a first argument to print the help string:

```
./gitu help
Gitu - A simple git for example purposes.
Usage: gitu [options] [commands]

Options:
  -v, --verbose         Enable verbose logging
  -c, --config          Path to config file

Commands:
  init                  Creates a new repository
  commit                Commits changes
  remote                Interacts with the server (remote)
    add                   Add a new remote
    show                  Show current remote
```

The descriptions in the help message must be specified in the definition, if not will be left empty; `.name` will appear in the usage, and `.description` describes every command or subcommand. The above message was generated from the following definition:

```
const gitu_definition = .{
    // what's your programs name and what does it do
    .name = "gitu",
    .description = "Gitu - A simple git for example purposes.",
    
    // set global arguments for the whole program
    .flags = .{ Flag("verbose", "v", "Enable verbose logging") },
    .options = .{ Opt([]const u8, "config", "c", "~/.gituconfig", "Path to config file") },

    .commands = .{
        .init = .{ // simple command with 1 positional argument
            .required = .{ Arg([]const u8, "path", "Where to create the repository") },
            .flags = .{ Flag("bare", "b", "Create a bare repository") },
            .description = "Creates a new repository",
        },
        .commit = .{ // just options and flags
            .options = .{ Opt([]const u8, "message", "m", "Default Message", "Commit message") },
            .flags = .{ Flag("amend", "a", "Amend the previous commit") },
            .description = "Commits changes"
        },
        .remote = .{ 
            .commands = .{ // nested subcommands !
                .add = .{
                    .required = .{  // multiple required args // gitu remote add <name> <url>
                        Arg([]const u8, "name", "Remote name (e.g. origin)"),
                        Arg([]const u8, "url", "Remote URL"),
                    },
                    .options = .{ Opt([]const u8, "track", "t", "master", "Branch to track") },
                    .description = "Add a new remote",
                },
                .show = .{
                    .required = .{ Arg([]const u8, "name", "Remote name to inspect") },
                    .description = "Show current remote"
                },
            },
            .description = "Interacts with the server (remote)",
        },
    },
};
```

The help message will change accordingly to which arguments/commands the user has written if the help flag `-h,--help` is invoked.

```
$: ./gitu init -h
Usage: eazy_args init [options] <path>

Description: Creates a new repository

Options:
  -b, --bare            Create a bare repository

Arguments:
  path            Where to create the repository
```


When invoked in nesting commands, help messages will also change according to which commands can appear:

```
$: ./gitu remote --help
Usage: eazy_args remote [commands]

Description: Interacts with the server (remote)

Commands:
  add                   Add a new remote
  show                  Show current remote
```

You cannot declare a command called `help` nor a optional/flag called `--help` or `-h`, those are reserved and will throw a compile error.

## API Reference

Argument - Positional arguments, allowed inside the `.required` tag
+ Type: The Zig type to parse (e.g., u32, []const u8, bool).
+ Name: The field name in the struct.
+ Description: Help text displayed in usage.

Option - Option with default value, allowed inside the `.option` tag 
+ Type: The value type. 
+ Name: Long flag name (e.g., "port" → --port).
+ Short: Short flag alias (e.g., "p" → -p).
+ Default: The value used if the flag is omitted (Must match Type).
+ Description: Help text.

Flag - Boolean option, needs no speficiation, defaults to `false`. Allowed inside the `.flags` tag
+ Name: Long flag name.
+ Short: Short flag alias.
+ Description: Help text.

ParseErrors - Errors returned by the parse functions
- HelpShown
- MissingArgument
- InvalidOptions
- InvalidFlags
- UnexpectedArgument
- UknownArgument
- MissingValue

## About _strict_ POSIX compliance

Right now, the following features are not supported, but will be:
- -- to denote the end (this is also not supported in GNU)
- concatenate multiple flags in one (eg `-abv ` instead of `-a -b -v`)
- Option with an optional argument -f[value], will be implemented with another object `LinkedOption` which can colive with `.option` 

Probably, the only option the library will not implement is mutually exclusive flags (`[-a|-b]`). This behaviour is much easily enforced by the user afterwards with simple if statements:

```
if (args.quiet and args.verbose) std.process.exit(0)
```

Rather than making something like the following snippet in the definition:
```
const def = .{
  .flags = .{
    .required = .{ Flag("quiet", "q", "Don't print"), Flag("verbose", "v", "Print more") },
    Flag("normal", "n", "another flag which is not exclusive"),
  }
}
```

But I have to think about it.

Lastly, POSIX does not allow a double representation of the same flag `-v/--verbose` so the `parseArgsPosix` should not allow it. I have mixed feelings about this: removing it would be the "correct" thing to make exactly POSIX but i feel long/short options and flags are super standard nowadays, so I really wonder if levaing the option and if you want an exactly posix compilant just don't use it is maybe the most user friendly approach?

# TODO:
+ Fix spacing in `printUsage`. Probably i will have to compute the min identation per every subcommand
+ Add a small usage when not all commands have been provided. That is, `tally entry start` now says `Error: Incorrect number of required arguments detected. Should be 1 but are 0.` which is techincally correct, but the user expects to see `Usage: tally entry start --projectid <description> `
+ Implement `printUsage` for POSIX: as i was already using an allocator in GNU style, i did not care that to know the path i had to use one. In POSIX no allocator is needed, i have to really think about what should I do. I don't think the path is going to disappear from the printUsage, so I'll probably use a generous buffer (512?)
+ POSIX functionalities: Described at the above section.
