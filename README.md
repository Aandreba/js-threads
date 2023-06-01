## Usage

- From your main file, export a variable named `env` with all the functions you wish to import to your WASM module

## Known issues

- By default, the zig compiler may not set a high enough `max_memory` value, crashing the program unexpectedly. You can fix that by adding a manual `max_size` to your library.

- `@memcpy` panics if copying out-of-bounds pointers, even in zero-sized copies.
