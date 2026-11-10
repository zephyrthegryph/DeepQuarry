// The native system (code/world/kernel/native.dm): Rust-owned state delivered through one outbox and
// read through one cache. The record kinds (NATIVE_REC_*), the pipe-device notice and the crossing
// detail sizes are generated from verdigris/ffi/src/frame.rs into verdigris/_bindings.dm.

/// A read key for native_read(): the component kind's code (VG_KIND_*) and the field id the generated
/// bindings name (VG_<COMPONENT>_FIELD_<NAME>).
#define NATIVE_KEY(code, field) ((code) * 256 + (field))
/// The component code of a NATIVE_KEY.
#define NATIVE_KEY_CODE(key) round((key) / 256)
/// The field of a NATIVE_KEY.
#define NATIVE_KEY_FIELD(key) ((key) % 256)

/// The frame's budget of normal and background wakes per wheel tick. Urgent wakes are never limited.
#define NATIVE_WAKE_BUDGET 2000
/// Wheel ticks one late frame may carry (skipped ticks are given to the pacer up to this).
#define NATIVE_MAX_CATCHUP 8
/// A native frame at least this long (ms) is logged with the Rust phases that grew (NATIVE_SLOW_FRAME in system.dm).
#define NATIVE_SLOW_FRAME_MS 30
/// The slow-frame log keeps this many lines per minute (a periodic 50 ms frame would otherwise log every ten seconds); slow_frames counts them all.
#define NATIVE_SLOW_FRAME_LOG_PER_MINUTE 20
/// A paced frame delivers records for this long (ms) and leaves the rest of its outbox for the next ticks, in order (deliver() in system.dm). One
/// frame's outbox was up to 370 APC reports (130 ms at boot, 30-55 ms every ten seconds in play), and a tick that long is shed by the kernel.
#define NATIVE_DELIVERY_BUDGET_MS 8
/// The least time between two NATIVE_DELIVERY_DEFERRED lines (REALTIMEOFDAY, ds); the streaks between them are summed into the next one.
#define NATIVE_DELIVERY_SUMMARY_INTERVAL (30 SECONDS)
/// A native frame at least this long (ms) is always logged, whatever the rate limit: it is the stall the log exists for.
#define NATIVE_STALL_FRAME_MS 500
