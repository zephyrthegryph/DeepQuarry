// The native system (code/datums/native/system.dm): Rust-owned state delivered through one outbox and
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
