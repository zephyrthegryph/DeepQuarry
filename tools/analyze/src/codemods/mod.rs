//! The codemods. Each `*.rs` here is one codemod exposing `pub fn register(reg: &mut Vec<Box<dyn Codemod>>)`;
//! build.rs finds them (there is no registry to edit). See `crate::codemod` for the framework and
//! `tools/analyze/README.md` ("Codemods") for how to write one.

include!(concat!(env!("OUT_DIR"), "/codemods_gen.rs"));
