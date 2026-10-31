//! Reusable analysis consumes the shared source model directly.
pub mod checks;
pub mod checks_ambiguous_in;
pub mod tree_export;
pub mod typed_body;
pub mod typed_body_jsonl;
pub mod untyped;
pub mod untyped_native;
pub mod value_equations;
pub mod value_expressions;
pub mod value_program;
pub mod value_query;
pub mod value_schemas;

mod untyped_order;

pub mod base_var_declarations;
pub mod check_configuration;
pub mod check_policy;
pub mod checker_constant_shape;
pub mod checker_order;
pub mod checker_reachable;
pub mod checks_control_static;
pub mod checks_invalid_set;
pub mod declaration_queries;
pub mod lifecycle_declarations;
mod native_program;
pub mod policy_inputs;
pub mod records_data_only;
pub mod source_definitions;

pub mod checks_flow;

pub mod analyze_scope_config;
pub mod checks_control_policies;
pub mod checks_set_no_effect;

pub mod checks_parent_call;

pub mod checks_configured_control;

pub mod checker_context;

pub mod checker_evaluated_observer;

pub mod checker_call_facts;
pub mod checker_expression_visit;
pub mod checks_undefined_proc;

pub mod checker_variable_facts;
pub mod checks_undefined_variable;

pub mod checker_return_facts;

pub mod analyze_call_sites;
pub mod policy_body_demand;

pub mod checks_field_static;

pub mod checks_implicit_new;

pub mod checker_static_type_notes;
pub mod checks_proc_static;
pub mod checks_variable_visibility;
pub mod untyped_member_native;

pub mod player_link_native;

pub mod weak_raw_read_native;

pub mod checker_effects;

pub mod rel_write_native;

pub mod policy_body_observation;

mod checker_prefix_demand;

pub mod checks_unknown_linter_setting;
