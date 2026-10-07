//! Native compiler client boundaries under construction in Phase 1.
//!
//! Publication has no dependency on the historical host, output journal or
//! generation/proof machinery. The cold pipeline and command-line driver will
//! consume this library once their declaration/lowering contracts are complete.

pub mod diagnostics;
pub mod publish;

pub mod engine;
pub mod engine_host;
