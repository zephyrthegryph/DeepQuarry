//! The lints. Each `*.rs` (or directory with a `mod.rs`) in this folder is one module that exposes
//! `pub fn register(reg: &mut Registry)`; build.rs generates the `pub mod` list and `register()`
//! below from the directory listing, so adding a lint means adding a file here. Files starting
//! with `_` are helpers and are not registered.

include!(concat!(env!("OUT_DIR"), "/lints_gen.rs"));
