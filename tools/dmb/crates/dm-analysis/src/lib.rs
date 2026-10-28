//! Reusable analysis consumes the shared source model directly.
pub mod checks;
pub mod checks_ambiguous_in;
pub mod untyped;
pub mod value_equations;
pub mod value_expressions;
pub mod value_program;
pub mod value_query;
pub mod value_schemas;
pub mod untyped_native;
pub mod tree_export;
pub mod typed_body;
pub mod typed_body_jsonl;

mod untyped_order;

mod native_program;
pub mod checks_invalid_set;
pub mod declaration_queries;
pub mod check_policy;
pub mod lifecycle_declarations;
pub mod checker_order;
pub mod policy_inputs;
pub mod base_var_declarations;
