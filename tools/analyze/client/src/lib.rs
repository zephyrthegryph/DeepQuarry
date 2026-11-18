//! Parser-free Analyze command and wire contracts.
pub mod cli_arguments;
pub mod native_cli_client;
pub mod native_policy_roster;
pub mod policy_report_wire;
pub mod report_work;
pub mod selected_exclusions_wire;

pub mod full_registry_check_wire;
pub mod full_registry_check_selection_wire;
pub mod schema_proposals_wire;
pub mod native_fix_wire;
pub mod native_baseline_update_wire;

pub mod native_checker_wire;

pub mod cli_usage;

pub mod native_check_cli_wire;

pub mod native_selftest_wire;

pub mod native_sem_utility_wire;

pub mod native_codemod_fixture_wire;
pub mod codemod_spec;
pub mod native_codemod_cli;
