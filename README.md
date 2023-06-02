## Usage

- From your main file, export a variable named `env` with all the functions you wish to import to your WASM module

## Known issues

- Build option `import_memory` will have to be set to `true`, requiring you to specify both inital and maximum Wasm memory on both your build file, and when calling `load` on your Js project.

- `@memcpy` panics if copying out-of-bounds pointers, even in zero-sized copies.
    - See [this issue](https://github.com/ziglang/zig/issues/15920)

- Futexes executed on the main thread will operate in busy-wait, as `Atomics.wait` panics on the main thread. In either case,
blocking the main thread for long periods of time isn't recommended.
