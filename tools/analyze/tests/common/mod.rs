//! The tests' front end: every model is built from the compiler's front end (dmbc), the one parse analysis has.
//! Each test calls [`dmbc_parse`] before it builds a model; the registration is process-wide and happens once.

use std::sync::Once;

static ONCE: Once = Once::new();

/// Registers dmbc's front end as the model's front end.
pub fn dmbc_parse() {
    ONCE.call_once(|| {
        dmbc::analysis_frontend::register_analysis_provider();
    });
}
