//! Explicit typed fixture-policy roster; does not expand raw27 admission.
pub const LINTS: &[&str] = &["init", "decl", "base_vars"];
pub fn metadata(name: &str) -> Option<&'static crate::lint::Meta> {
    match name {
        "init" => Some(crate::lints::init::captured_metadata()),
        "decl" => Some(crate::lints::decl::captured_metadata()),
        "base_vars" => Some(&crate::base_var_metadata::META),
        _ => None,
    }
}
