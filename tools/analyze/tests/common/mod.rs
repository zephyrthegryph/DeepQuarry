//! The tests' front end: every model is built from the compiler's parse (dmbc front end -> analysis tree), the one parse analysis has.
//! Each test calls [`dmbc_parse`] before it builds a model; the registration and the selection are process-wide and happen once.

use std::sync::Once;

static ONCE: Once = Once::new();

/// Registers dmbc's front end as the model's parse provider and selects it for this process.
pub fn dmbc_parse() {
    ONCE.call_once(|| {
        dmbc::analysis_tree::register_analysis_provider();
        std::env::set_var("DQ_ANALYZE_PARSE", "dmbc");
    });
}
