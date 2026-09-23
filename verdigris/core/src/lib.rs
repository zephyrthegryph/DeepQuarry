//! `vg-core`: the domain-agnostic base every verdigris simulation builds on
//! (see `doc/rewrite/rust_core.md`).
//!
//! Rules for this crate:
//! - no `byondapi` (it builds and tests on the host, not only on i686);
//! - no global statics (tests run in parallel, and a `World` owns all state).

pub mod grid;
