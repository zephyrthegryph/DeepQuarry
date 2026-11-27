//! DreamChecker, a robust static analysis and typechecking engine for DreamMaker (SpacemanDMM), run on the compiler front end's own
//! tree: [`native`]. The checks on dreammaker's object tree that this crate vendored are gone; their recorded output is the oracle
//! (`tests/corpus`).

extern crate dreammaker as dm;

pub mod native;
