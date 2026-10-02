//! The lints. Each `*.rs` (or directory with a `mod.rs`) in this folder is one module that exposes
//! `pub fn register(reg: &mut Registry)`; build.rs generates the `pub mod` list and `register()`
//! below from the directory listing, so adding a lint means adding a file here and nothing else.
//! A helper two or more lints share goes in `src/dm/` (also auto-discovered), not here.

include!(concat!(env!("OUT_DIR"), "/lints_gen.rs"));
