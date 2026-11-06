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
mod derived_entry_policy;
mod derived_reads_judge;
mod derived_schema_policy;
mod derived_reads_metadata;
#[cfg(feature="native-policy")]mod reactive_raw_lexical_source;
#[cfg(feature="native-policy")]pub mod captured_derived_reads;
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
#[cfg(all(test,feature="legacy-sem",feature="native-policy"))]
#[path="../../dmb/crates/dm-analysis/src/original_base_terms.rs"]mod original_base_terms;

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

pub mod tracked_policy;
#[cfg(feature="native-policy")]mod tracked_named_arguments_native;
#[cfg(feature="native-policy")]pub mod captured_tracked_pages;

#[cfg(all(test,feature="legacy-sem"))]mod tracked_policy_tests;

pub mod sem_reads_policy;
mod raw_publishers_policy;
#[cfg(feature="native-policy")]pub mod captured_sem_reads;

#[cfg(all(test,feature="legacy-sem"))]mod sem_reads_policy_tests;

pub mod untracked_inputs_policy;
#[cfg(feature="native-policy")]pub mod captured_untracked_inputs;

#[cfg(all(test,feature="legacy-sem"))]mod untracked_inputs_policy_tests;

pub mod required_scope_policy;
#[cfg(all(test,feature="legacy-sem"))]mod required_scope_policy_tests;

#[cfg(feature="native-policy")]pub mod required_scope_registry;

pub mod cli_arguments;

pub mod state_schema_data;
pub mod state_schema_policy;
#[cfg(all(test,feature="legacy-sem"))]mod state_schema_policy_tests;

#[cfg(feature="native-policy")]pub mod captured_state_schema_pages;

pub mod lifecycle_policy;
#[cfg(feature="native-policy")]pub mod captured_lifecycle_pages;
#[cfg(all(test,feature="legacy-sem"))]mod lifecycle_policy_tests;

pub mod sys_loot_policy;
#[cfg(feature="native-policy")]pub mod captured_sys_loot_pages;
#[cfg(all(test,feature="legacy-sem"))]mod sys_loot_policy_tests;

pub mod instance_list_policy;
#[cfg(feature="native-policy")]pub mod captured_instance_list_pages;

#[cfg(all(test,feature="legacy-sem"))]mod instance_list_policy_tests;

pub mod cache_policy;
#[cfg(feature="native-policy")]pub mod captured_cache_bytes;
#[cfg(all(test,feature="legacy-sem"))]mod cache_policy_tests;

pub mod sys_ownership_forms_policy;
#[cfg(feature="native-policy")]pub mod captured_sys_ownership_forms_pages;
#[cfg(all(test,feature="legacy-sem"))]mod sys_ownership_forms_policy_tests;

/// Unique API lexical policy over existing original views.
pub mod api_policy;
#[cfg(feature="native-policy")]pub mod captured_api_pages;

pub mod sys_fields_policy;
#[cfg(feature="native-policy")]pub mod captured_sys_fields_pages;

pub mod sys_appearance_policy;
#[cfg(feature="native-policy")]pub mod captured_sys_appearance_pages;

/// Pure canonical descriptor aliases for frozen external oracle examples only.
#[cfg(feature="unified-oracle")]pub mod original_policy_descriptors;

pub mod raw_tree_report;
mod notice_publisher_policy;
pub mod raw_tree_cooldown_policy;
pub mod raw_tree_declaration_block_policy;
pub mod raw_tree_duplicate_input_key_policy;
pub mod raw_tree_interactions_policy;
pub mod raw_tree_latent_policy;
pub mod raw_tree_pollers_policy;
pub mod raw_tree_read_back_policy;
pub mod raw_tree_cap_bits_policy;
#[cfg(feature="native-policy")]pub mod captured_raw_tree_pages;

/// Pure canonical descriptor aliases for frozen external oracle examples only.

#[cfg(feature="native-policy")]pub mod workspace_fold_policy;
mod decl_policy;
#[cfg(feature="native-policy")]pub mod captured_decl_pages;

#[cfg(all(test,feature="legacy-sem"))]#[path="decl_policy_tests.rs"]mod decl_policy_tests;

mod init_policy;
#[cfg(feature="native-policy")]pub mod captured_init_pages;

#[cfg(all(test,feature="legacy-sem"))]#[path="init_policy_tests.rs"]mod init_policy_tests;

#[cfg(feature="native-policy")]pub mod captured_base_vars_pages;

#[cfg(all(test,feature="legacy-sem"))]
mod base_vars_workspace_policy_tests;

mod requirement_bool_policy;
#[cfg(feature="native-policy")]pub mod captured_requirement_bool_pages;

#[cfg(all(test,feature="legacy-sem"))]mod requirement_bool_workspace_tests;

pub mod manual_log_policy;

#[cfg(all(test,feature="legacy-sem",feature="native-policy"))]mod manual_log_policy_tests;

pub mod sfx_policy;
#[cfg(all(test,feature="legacy-sem",feature="native-policy"))]mod sfx_policy_tests;

pub mod sys_requirements_policy;
pub mod sys_string_names_policy;
#[cfg(feature="native-policy")]pub mod captured_sys_cross_pages;
#[cfg(all(test,feature="legacy-sem",feature="native-policy"))]mod sys_cross_policy_tests;
#[cfg(feature="native-policy")]pub mod captured_player_link_pages;

#[cfg(all(test,feature="legacy-sem"))]#[path="player_link_workspace_policy_tests.rs"]mod player_link_workspace_policy_tests;

#[cfg(feature="native-policy")]pub mod captured_untyped_member_pages;
#[cfg(all(test,feature="legacy-sem"))]#[path="untyped_member_workspace_policy_tests.rs"]mod untyped_member_workspace_policy_tests;

#[cfg(feature="native-policy")]pub mod captured_weak_raw_read_pages;
#[cfg(all(test,feature="legacy-sem"))]#[path="weak_raw_read_workspace_policy_tests.rs"]mod weak_raw_read_workspace_policy_tests;

pub mod sys_look_effects_policy;
pub mod sys_constructor_shadow_policy;
#[cfg(feature="native-policy")]pub mod captured_shadow_look_pages;

#[cfg(all(test,feature="legacy-sem",feature="native-policy"))]mod shadow_look_policy_tests;

pub mod expiry_policy;
#[cfg(feature="native-policy")]pub mod captured_expiry_pages;
#[cfg(all(test,feature="legacy-sem",feature="native-policy"))]mod expiry_policy_tests;

// One pure writer kernel is shared by native policies and the legacy adapter.
pub mod reactive_writer_policy;

#[cfg(feature="native-policy")]pub mod captured_rel_write_pages;
#[cfg(all(test,feature="legacy-sem"))]#[path="rel_write_undeclared_workspace_policy_tests.rs"]mod rel_write_undeclared_workspace_policy_tests;

pub mod sys_ui_policy;
#[cfg(feature="native-policy")]pub mod captured_sys_ui_pages;
#[cfg(all(test,feature="legacy-sem",feature="native-policy"))]mod sys_ui_policy_tests;

#[cfg(feature="native-policy")]pub mod untyped_policy_schemas;
#[cfg(feature="native-policy")]pub mod captured_untyped_pages;

#[cfg(all(test,feature="legacy-sem"))]#[path="untyped_workspace_policy_tests.rs"]mod untyped_workspace_policy_tests;

pub mod doc_snippets_policy;
#[cfg(feature="native-policy")]pub mod captured_doc_snippets_pages;

#[cfg(all(test,feature="native-policy"))]mod doc_snippets_policy_tests;

#[cfg(feature="native-policy")]pub mod captured_stored_refs_pages;

#[cfg(all(test,feature="legacy-sem"))]#[path="stored_refs_workspace_policy_tests.rs"]mod stored_refs_workspace_policy_tests;

pub mod ownership_policy;
pub mod op_order_policy;
#[cfg(feature="native-policy")]
pub mod captured_op_order;
#[cfg(feature="native-policy")]pub mod captured_ownership_pages;
#[cfg(all(test,feature="legacy-sem",feature="native-policy"))]mod ownership_workspace_policy_tests;

pub mod layering_raw_policy;
pub mod engine_layering_policy;

#[cfg(feature="native-policy")]pub mod captured_engine_layering_pages;

#[cfg(all(test,feature="legacy-sem",feature="native-policy"))]mod engine_layering_workspace_policy_tests;

pub mod ui_actions_js;

#[cfg(any(feature="legacy-sem",feature="native-policy"))]pub(crate) mod ui_actions_normalizer;

#[cfg(any(feature="legacy-sem",feature="native-policy"))]pub(crate) mod ui_actions_hosts;

#[cfg(any(feature="legacy-sem",feature="native-policy"))]pub(crate) mod ui_actions_c2;

#[cfg(any(feature="legacy-sem",feature="native-policy"))]pub mod ui_actions_policy;

#[cfg(any(feature="legacy-sem",feature="native-policy"))]pub(crate) mod ui_actions_check;

#[cfg(feature="native-policy")]
pub mod captured_ui_actions;

#[cfg(all(test,feature="native-policy",feature="legacy-sem"))]mod ui_actions_workspace_policy_tests;

pub mod setter_publication_policy;
#[cfg(feature="native-policy")]pub mod captured_setter_publishes;

#[cfg(all(test,feature="legacy-sem",feature="native-policy"))]mod setter_publishes_workspace_policy_tests;

#[cfg(all(test,feature="legacy-sem",feature="native-policy",feature="unified-oracle"))]
mod op_order_workspace_policy_tests;

pub mod sys_reactive_policy;
#[cfg(feature="native-policy")]pub mod captured_sys_reactive;
#[cfg(all(test,feature="legacy-sem",feature="native-policy"))]mod sys_reactive_workspace_policy_tests;

pub mod lifeforms_policy;
#[cfg(feature="native-policy")]mod lifeforms_ctor_policy;
#[cfg(feature="native-policy")]pub mod captured_lifeforms;

#[cfg(all(test,feature="legacy-sem",feature="native-policy"))]mod lifeforms_workspace_policy_tests;


pub mod sem_handlers_policy;
pub mod sem_handlers_partial_recipe;
pub mod sem_handlers_output_policy;
#[cfg(feature="native-policy")]mod sem_handlers_output_native;
#[cfg(feature="native-policy")]pub(crate) mod sem_handlers_native;
#[cfg(all(test,feature="legacy-sem",feature="native-policy"))]mod sem_handlers_policy_tests;

pub mod silicon_actor_policy;
#[cfg(all(test,feature="legacy-sem",feature="native-policy"))]mod silicon_actor_policy_tests;

pub mod silicon_entry_policy;
#[cfg(feature="native-policy")]mod silicon_actor_native;
#[cfg(feature="native-policy")]pub mod captured_silicon_entry;
#[cfg(all(test,feature="legacy-sem",feature="native-policy",feature="unified-oracle"))]mod silicon_entry_workspace_policy_tests;

pub mod sem_handlers_escape_policy;

pub mod sem_handlers_pair_policy;

#[cfg(feature="native-policy")]mod sem_handlers_escape_native;

#[cfg(feature="native-policy")]mod sem_handlers_context_names_native;

#[cfg(feature="native-policy")]mod sem_handlers_pair_native;

#[cfg(feature="native-policy")]pub mod sem_handlers_structural_native;

#[cfg(feature="native-policy")]pub mod captured_sem_handlers_recipe;

pub mod sem_handlers_report_policy;

#[cfg(feature="native-policy")]pub mod captured_sem_handlers;
