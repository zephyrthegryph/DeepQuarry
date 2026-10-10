//! Native compiler client boundaries under construction in Phase 1.
//!
//! Publication has no dependency on the historical host, output journal or
//! generation/proof machinery. The cold pipeline and command-line driver will
//! consume this library once their declaration/lowering contracts are complete.

pub mod cache_maintenance;
pub mod cli;
pub mod debug_sources;
pub mod diagnostics;
pub mod expansion_memo;
pub mod filesystem_proofs;
pub mod frozen_inputs;
pub mod heap_census;
pub mod input_snapshot;
mod procedure_warnings;
pub use runner_host::disk as runner_disk;
pub mod map_memo;
pub mod output_cli;
pub mod pinned_target;
pub mod publish;
pub mod request;
pub mod request_failure;
pub mod request_runner;
pub mod resource_manifest;
pub mod runner_host;
mod runner_retained_census;
pub mod session;
pub mod telemetry;
pub mod verification;

pub mod argument_sources;
pub mod class_initialization;
pub mod class_inventory;
pub mod class_projection;
pub mod client_projection;
pub mod client_script;
pub mod cold;
pub mod composition;
pub mod driver_facts;
pub mod engine;
pub mod engine_abi_coverage;
pub mod engine_host;
pub mod engine_link;
pub mod initialization_artifact;
mod initializer_code;
pub use initializer_code::InitializerCode;
pub mod initializer_diagnostics;
pub mod initializer_lowering;
pub mod initializer_policy;
mod initializer_tokens;
pub mod intrinsic_initializer_facts;
pub mod lowering;
pub mod lowering_memo;
mod lowering_memo_compact;
mod lowering_memo_selection;
mod lowering_memo_wire;
pub mod mob_writer;
mod native_callbacks;
pub mod native_inputs;
pub mod procedure_policy;
pub mod resource_values;
pub mod savefile_projection;
pub mod selected_query;
pub mod stage_measurements;
pub mod symbolic;
pub mod type_creation_order;
pub mod type_values;
pub mod world_projection;
pub mod world_writer;

pub mod map_projection;

pub mod assets;
pub mod map_initializers;

pub mod map_output;

pub mod map_artifacts;
pub mod map_identity;

pub mod non_text;

pub mod non_text_output;

pub mod resource_order;

pub mod captured_non_text_driver;
pub mod compile_driver;
mod request_lease;
pub mod required_types;
pub mod skin;

#[cfg(test)]
mod modified_instance_receipts;
#[cfg(test)]
mod native_macro_receipts;
pub mod startup;
mod startup_allocation;
#[cfg(test)]
mod static_storage_receipts;

pub mod modified_output;
#[cfg(test)]
mod modified_output_tests;
pub mod pure_calls;

pub mod modified_initializers;

pub mod profile_host;

pub mod daemon;

mod analysis_export;

#[cfg(test)]
mod string_continuation_receipts;
