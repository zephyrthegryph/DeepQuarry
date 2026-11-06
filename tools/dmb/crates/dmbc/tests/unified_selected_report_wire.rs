//! Thin codec-only harness. Compiles the actual frame, spool and codec
//! sources without linking the monolithic dmbc cfg(test) executable.
pub use dmbc::{request, request_failure};
#[path = "../../../shared/test_scratch.rs"]
mod test_scratch;
#[path = "../src/generation_staging.rs"]
mod generation_staging;
#[path = "../src/selected_report_spool.rs"]
mod selected_report_spool;
#[path = "selected_report_wire_harness/mod.rs"]
mod daemon;
