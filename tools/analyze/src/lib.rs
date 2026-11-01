//! DeepQuarry's lint/analysis engine. See `tools/analyze/README.md`.
//!
//! One load of the source tree ([`tree`]), one comment/string stripping ([`strip`]), one ALLOW
//! implementation ([`allow`]), one baseline implementation ([`baseline`]), one on-disk cache
//! ([`cache`]); every lint is a [`lint::Lint`] in `src/lints/`.

pub mod native_cli_client;
pub mod allow;
#[cfg(feature = "legacy-sem")]
pub mod base_vars_dead;
pub mod baseline;
pub mod policy_judge;
pub mod keys_policy;
pub mod key_policy_control;
pub mod auto_setter_calls_policy;
pub mod auto_tracking_policy;
mod auto_tracking_emitter;
pub mod typed_set_calls_policy;
#[cfg(feature="native-policy")]mod auto_typed_set_calls_native;
#[cfg(feature="native-policy")]
mod auto_tracking_native;
#[cfg(feature="native-policy")]
pub mod captured_keys;
#[cfg(feature="native-policy")]
pub mod captured_keys_pages;
#[cfg(feature="native-policy")]
mod captured_keys_source;
pub mod raw_key_calls_policy;
#[cfg(feature = "legacy-sem")]
pub mod cache;
#[cfg(feature = "legacy-sem")]
pub mod codemod;
#[cfg(feature = "legacy-sem")]
pub mod codemods;
pub mod dm;
#[cfg(feature = "legacy-sem")]
pub mod frontend;
#[cfg(feature = "legacy-sem")]
pub mod gens;
pub mod incr;
pub mod lint;
pub mod lints;
#[cfg(feature = "legacy-sem")]
pub mod parity;
pub mod parity_types;
#[cfg(not(feature = "legacy-sem"))]
pub use parity_types as parity;
#[cfg(feature = "native-policy")]
pub mod captured_raw_file;
#[cfg(feature = "native-policy")]
pub mod captured_raw_policy;
#[cfg(feature = "native-policy")]
pub mod captured_raw_cohort;
pub mod pat;
mod raw_name_match;
#[cfg(feature = "legacy-sem")]
pub mod run;
pub mod scopes;
pub mod reactive_facts;
pub mod reactive_hooks_policy;
pub(crate) mod plans_policy;
#[cfg(feature = "legacy-sem")]
pub mod sem;
#[cfg(feature = "legacy-sem")]
pub mod shared;
pub mod strip;
pub mod tree;
pub mod util;

pub mod native_policy_roster;
pub const LEGACY_SEMANTICS_ENABLED: bool = cfg!(feature = "legacy-sem");

#[cfg(feature = "native-policy")]
pub mod captured_decl_policy;
pub mod lifecycle_source;

pub mod base_var_candidate_policy;
pub mod base_var_hot_policy;
#[cfg(feature = "native-policy")]
pub mod captured_base_var_candidates;
#[cfg(feature = "native-policy")]
pub mod captured_base_var_hot_policy;
#[cfg(feature = "native-policy")]
pub mod captured_base_vars_policy;
#[cfg(feature = "native-policy")]
pub mod captured_init_policy;
pub mod raw_declaration_policy;
pub mod raw_marker_policy;
pub mod value_schema_policy;

pub mod base_var_metadata;
#[cfg(feature = "native-policy")]
pub mod captured_policy_metadata;

#[cfg(feature = "native-policy")]
pub mod captured_requirement_bool;

#[cfg(feature = "native-policy")]
pub mod captured_untyped_member;
pub mod untyped_member_policy;

#[cfg(feature = "native-policy")]
pub mod captured_untyped;
pub mod untyped_policy_metadata;

#[cfg(feature = "native-policy")]
pub mod captured_player_link;
pub mod player_link_policy;

#[cfg(feature = "native-policy")]
pub mod captured_sparse_slots;
pub mod sparse_slots_policy;

#[cfg(feature = "native-policy")]
pub mod captured_weak_raw_read;
pub mod weak_relation_policy;

#[cfg(feature = "native-policy")]
pub mod captured_system_accessors;
pub mod generator_test_scope;
pub mod raw_type_vars_policy;
pub mod system_accessors_policy;

#[cfg(feature = "native-policy")]
pub mod captured_rel_write;
pub mod rel_write_policy;
pub mod relation_decl_policy;

pub mod raw_ownership_policy;

#[cfg(feature = "native-policy")]
pub mod captured_stored_refs;
pub mod stored_refs_policy;

pub mod captured_generator_budget;

#[cfg(feature = "native-policy")]
pub mod captured_stats;
pub mod stats_policy;

pub mod actions_policy;
#[cfg(feature = "native-policy")]
pub mod captured_actions;

#[cfg(feature = "native-policy")]
pub mod captured_pool;
pub mod pool_policy;

pub mod declare_ids_policy;
#[cfg(feature = "native-policy")]
pub mod captured_declare_ids;

pub mod declare_policy;
#[cfg(feature = "native-policy")]
pub mod captured_declare;

pub mod ui_types_policy;
pub mod raw_entry_proc_policy;
pub mod raw_runtime_observer_policy;
#[cfg(feature="native-policy")]pub mod captured_ui_types;

#[cfg(feature="native-policy")]mod captured_marker_rows;

pub mod tracked_lists_policy;
#[cfg(feature="native-policy")]pub mod captured_tracked_lists;

pub mod global_policy;
pub mod write_policy;

pub mod raw_reactive_metadata_policy;

pub mod reactive_read_facts;

pub mod reactive_annotations_policy;

#[cfg(feature="native-policy")]mod reactive_original_source;

#[cfg(feature="native-policy")]mod reactive_annotations_native;

#[cfg(feature="native-policy")]mod reactive_policy_facts_native;
#[cfg(feature="native-policy")]mod reactive_policy_storage;

#[cfg(feature="native-policy")]mod reactive_reads_native;

#[cfg(feature="native-policy")]mod reactive_read_result;

#[cfg(feature="native-policy")]mod reactive_global_facts_native;

#[cfg(feature="native-policy")]pub mod captured_reactive_reads;
#[cfg(feature="native-policy")]pub mod reactive_raw_policy_pages;

pub mod reactive_variable_policy;

pub mod reactive_dependency_policy;

pub mod reactive_dependency_fold;

pub mod reactive_dependency_marker_policy;

pub mod reactive_read_key_policy;

pub mod reactive_reaction_policy;

#[cfg(feature="native-policy")]mod reactive_reaction_native;

#[cfg(feature="native-policy")]mod reactive_dependency_native;

pub(crate) mod deps_policy;

pub(crate) mod reactive_dependency_view;

#[cfg(feature="native-policy")]pub(crate) mod reactive_dependency_result;

pub(crate) mod reads_policy;
pub(crate) mod derived_reads_policy;

pub(crate) mod reactive_rank_policy;

#[cfg(feature="native-policy")]mod reactive_reads_generator_native;
#[cfg(feature="native-policy")]mod reactive_plans_generator_native;

pub(crate) mod derived_reads_collect_policy;
#[cfg(feature="native-policy")]mod reactive_derived_generator_native;

#[cfg(feature="native-policy")]pub mod captured_declaration_pages;

#[cfg(feature = "native-policy")]
pub mod captured_ui_pages;

#[cfg(feature="native-policy")]
pub mod captured_stats_pages;

#[cfg(feature="native-policy")]
pub mod captured_actions_pages;

#[cfg(feature="native-policy")]
pub mod captured_system_accessors_pages;

#[cfg(feature="native-policy")]
pub mod captured_declare_pages;

#[cfg(feature="native-policy")]
pub mod captured_tracked_lists_pages;

mod lifeform_source_policy;

#[cfg(all(test,feature="legacy-sem",feature="native-policy"))]
mod raw_policy_next_tests;

#[cfg(all(test,feature="legacy-sem",feature="native-policy"))]
mod deadline_policy_native_tests;

mod sys_hygiene_policy;
#[cfg(feature="native-policy")] pub mod captured_sys_hygiene_pages;

mod sys_resolvers_policy;
#[cfg(feature="native-policy")] pub mod captured_sys_resolvers_pages;

mod sys_tables_policy;
#[cfg(feature="native-policy")] pub mod captured_sys_tables_pages;

#[cfg(all(test,feature="legacy-sem",feature="native-policy"))]
mod native_pinned_expression_gap_tests;

pub mod system_boundary_report;
#[cfg(all(test,feature="legacy-sem"))]
mod system_boundary_report_tests;

#[cfg(all(test,feature="legacy-sem",feature="native-policy"))]
mod native_original_expression_debug_oracle;

mod system_boundary_policy;
#[cfg(feature="native-policy")]pub mod captured_system_boundary_pages;

mod check_grep_semantic_policy;

#[cfg(feature="native-policy")]
mod check_grep_native_semantics;

#[cfg(feature="native-policy")]
mod reactive_global_source;
#[cfg(feature="native-policy")]
mod generation_reactive_source;

#[cfg(feature="native-policy")]
pub mod captured_generation_auto;

#[cfg(feature="native-policy")]pub mod captured_generation_questions;

pub mod policy_finish;

pub mod allow_annotation_policy;
pub mod allow_registry_metadata;
#[cfg(feature="native-policy")]pub mod captured_allow_annotations;

pub(crate) mod allow_registry_fields;

#[cfg(all(feature="legacy-sem",feature="unified-oracle"))]
#[path="../examples/support/keys_original/marker.rs"]mod keys_old_marker;
#[cfg(all(feature="legacy-sem",feature="unified-oracle"))]
#[path="../examples/support/keys_original/calls.rs"]mod keys_old_calls;
#[cfg(all(feature="legacy-sem",feature="unified-oracle"))]
#[path="../examples/support/keys_original/entries.rs"]mod keys_old_entries;
#[cfg(all(feature="legacy-sem",feature="unified-oracle"))]
#[path="../examples/support/keys_original/decls.rs"]mod keys_old_decls;
#[cfg(all(feature="legacy-sem",feature="unified-oracle"))]
#[path="../examples/support/keys_original/policy.rs"]mod keys_old_policy;
#[cfg(all(feature="legacy-sem",feature="unified-oracle"))]
mod keys_old_system{use crate::tree::Tree;use std::sync::Arc;include!("../fixtures/original_policies/keys_system_lookup.rs");}
#[cfg(all(feature="legacy-sem",feature="unified-oracle"))]
pub mod keys_original_reference;
#[cfg(any(test,all(feature="legacy-sem",feature="unified-oracle")))]
#[path="../../dmb/shared/test_scratch.rs"]
mod test_scratch;
