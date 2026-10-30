//! Explicit typed fixture-policy roster; does not expand raw27 admission.
pub const LINTS: &[&str] = &[
    "init",
    "decl",
    "base_vars",
    "requirement_bool",
    "untyped_member",
    "player_link",
    "weak_raw_read",
    "rel_write_undeclared",
    "stored_refs",
    "untyped",
    "pool",
];
pub fn metadata(name: &str) -> Option<&'static crate::lint::Meta> {
    match name {
        "init" => Some(crate::lints::init::captured_metadata()),
        "decl" => Some(crate::lints::decl::captured_metadata()),
        "base_vars" => Some(&crate::base_var_metadata::META),
        "requirement_bool" => Some(crate::lints::requirement_bool::captured_metadata()),
        "untyped_member" => Some(&crate::untyped_member_policy::META),
        "stored_refs" => Some(crate::stored_refs_policy::metadata()),
        "rel_write_undeclared" => Some(crate::rel_write_policy::metadata()),
        "weak_raw_read" => Some(crate::weak_relation_policy::metadata()),
        "untyped" => Some(&crate::untyped_policy_metadata::META),
        "player_link" => Some(crate::player_link_policy::metadata()),
        "pool" => Some(&crate::pool_policy::META),
        _ => None,
    }
}
