//! The verdigris DLL. It owns no logic of its own beyond `material_power`; it
//! links the bind crates so BYOND loads exactly one library.

pub mod material_power;

#[cfg(target_arch = "x86")]
#[global_allocator]
static ALLOCATOR: vg_ffi::allocator::TrackingAllocator = vg_ffi::allocator::TrackingAllocator;

// Force-link the rlibs whose #[no_mangle] binds make up the DLL's exports.
// Without a reference, the linker may drop them.
#[cfg(target_arch = "x86")]
#[allow(unused_imports)]
use {vg_ffi as _, vg_gas as _};
