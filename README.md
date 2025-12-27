# EasyArgsZig

I've seen a cool video of preprocessor magic in C (easy-args) and I couldn't help but imagine if if could be done with some compile-time magic.

My idea is to generate an input struct _at compile-time_ with just some information from the user in idiomatic Zig with structs.

```zig
const definitions = .{
    .required = .{
      Arg(u32, "limit", "Limits are meant to be broken"),
      Arg(bool, "verbose", "print a little, or print a lot"),
      Arg([]const u8, "username", "who are you dear?"),
    },
    .optional = .{
      OptArg(u32, "--break", "-b", 100, "Stop before the limit"),
    },
    .flag = .{
      Flag("--verbose", "-v", "Print a little, print a lot but now with a flag"),
    }
};
```

Then, call a parser which verifies the arguments provided match the given description, like this:

```

const config: InputStruct = try parseArgs(allocator, definitions) 
```


If they match, config will contain all the data properly parsed. If not, it will let you know and print the usage.

Luckily, I've managed to ensemble a working prototype real fast! This can be nice, so I'll keep working on it :)

## TODO:

[ ] Create `OptArg` and `Flag` structs. Remember to check that no flags are repeated
[ ] Update GeneratorStruct to handle a struct of lists 
[ ] Default values: where do I store them in comptime? i need to do some research arround that (`default_value_ptr`)
[ ] New Parser: first fill the Arg normals, and then search for `-s` or `--string` for the flags and the OptArg
[x] ValueParser: make it parse all the types appropiately, using std
[ ] 
