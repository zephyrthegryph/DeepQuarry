//! The generators. Each `*.rs` here is one generator exposing `pub fn register(reg: &mut Vec<Box<dyn Generator>>)`;
//! build.rs finds them (there is no registry to edit). See `crate::sem::gen` for the API.

include!(concat!(env!("OUT_DIR"), "/gens_gen.rs"));
