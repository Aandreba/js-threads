## Known issues

- By default, the zig compiler may not set a high enough `max_memory` value, crashing the program unexpectedly. You can fix that by adding a manual `max_size` to your library.
