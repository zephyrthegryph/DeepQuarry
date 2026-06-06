#[macro_use]
extern crate meowtonin;

pub mod panic;
pub mod random_map;
pub mod verdigris;

// Force-link auxmos's byondapi binds into libverdigris.so. Without this, the
// auxmos rlib's #[no_mangle] FFI exports may be stripped by the linker. The
// `as _` import is intentional — we only need the symbols, not name imports.
//
// Gated on x86 because byondapi-sys (auxmos's transitive dep) is 32-bit-only.
// See modular_dq/doc/atmos_migration.md decision §4 ("one library").
#[cfg(target_arch = "x86")]
#[allow(unused_imports)]
use auxmos as _;
