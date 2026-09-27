// Comment this out if you are debugging problems that might be obscured by custom error handling in world/Error.
// Independent of DEBUG: production builds (no DEBUG, no file/line) still dedupe and log runtimes.
#define USE_CUSTOM_ERROR_HANDLER

/// If this is uncommented, Autowiki will generate edits and shut down the server.
/// Prefer the autowiki build target instead.
// #define AUTOWIKI

// We do not have dreamlua implemented
#define DISABLE_DREAMLUAU
