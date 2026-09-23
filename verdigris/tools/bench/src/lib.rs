//! Criterion benchmark harness for verdigris (`cargo bench -p vg-bench`).
//!
//! Benches live in `benches/`, one file per crate. The planned world-snapshot
//! benches (gas step, heat step, network commit, command application; see
//! `doc/rewrite/rust_core.md` section 12) land here once those crates are
//! host-buildable.
