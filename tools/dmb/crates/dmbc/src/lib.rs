//! Native compiler client boundaries under construction in Phase 1.
//!
//! Publication has no dependency on the historical host, output journal or
//! generation/proof machinery. The cold pipeline and command-line driver will
//! consume this library once their declaration/lowering contracts are complete.

pub mod diagnostics;
pub mod debug_sources;
pub mod publish;

pub mod engine;
pub mod engine_abi_coverage;
mod native_callbacks;
pub mod type_values;
pub mod engine_link;
pub mod engine_host;
pub mod lowering;
pub mod procedure_policy;
pub mod driver_facts;
pub mod symbolic;
pub mod composition;
pub mod class_projection;
pub mod class_initialization;
pub mod class_inventory;
pub mod type_creation_order;
pub mod mob_writer;
pub mod argument_sources;
pub mod cold;
pub mod stage_measurements;
pub mod world_projection;
pub mod client_projection;
pub mod savefile_projection;
pub mod client_script;
pub mod resource_values;
pub mod world_writer;
pub mod initializer_policy;
pub mod initializer_lowering;
pub mod initializer_diagnostics;
pub mod native_inputs;
pub mod initialization_artifact;

pub mod map_projection;

pub mod assets;
pub mod map_initializers;

pub mod map_output;

pub mod map_identity;
pub mod map_artifacts;

pub mod non_text;

pub mod non_text_output;

pub mod resource_order;

pub mod skin;
pub mod captured_non_text_driver;
pub mod compile_driver;
pub mod required_types;

pub mod startup;
