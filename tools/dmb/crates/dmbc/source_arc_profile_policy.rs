//! Build-time contract registry, also exercised by native unit tests.
//! This is not a source semantic model or a client-supplied runtime profile.
pub const COMMIT: &str = "58cf8f9c35b355199727627d07ae34a4e2846d67";
pub const RELEASE: &str = "1.99.1";
pub const TARGET: &str = "x86_64-pc-windows-msvc";
pub const SOURCE_SHA: &str = "b2f806b0f696a181018072625dceed25304aa97dfef6a79bac9800d529afdd0e";
pub const ALLOC_SHA: &str = "ef5df2b944db14679cc916d06ce7cb81968d741a5c10f5f5cf8f5b247c764d7a";
// Qualified by the nine-case actual allocator receipt in
// fixtures/source_arc_profiles/rustc-58cf8f9c-win64-observation.json.
// Both the compiler tuple and local implementation digests must still match.
pub const PROBE_APPROVED: bool = true;
pub struct Candidate<'a> {
    pub commit: &'a str,
    pub release: &'a str,
    pub target: &'a str,
    pub pointer_width: &'a str,
    pub source_sha: &'a str,
    pub alloc_sha: &'a str,
    pub has_pointer_atomics: bool,
}
pub fn matches(p: &Candidate<'_>) -> bool {
    p.commit == COMMIT
        && p.release == RELEASE
        && p.target == TARGET
        && p.pointer_width == "64"
        && p.has_pointer_atomics
        && p.source_sha == SOURCE_SHA
        && p.alloc_sha == ALLOC_SHA
}

// The independent probe must be repeated when either local allocation geometry
// or final-strong ownership implementation changes. Registry excluded to avoid
// a self-referential hash; these exact source bytes are external build inputs.
pub const GEOMETRY_IMPLEMENTATION_SHA: &str =
    "d6c463079c536ae019a1074a1d9542251b89e0802b78b3623c97452eb9fb7e29";
pub const OWNERSHIP_IMPLEMENTATION_SHA: &str =
    "67c1b87673269aa660252cbaa896ced6e5fcf6e342e96c9c5001b08f2812300b";
pub fn implementation_matches(geometry: &str, ownership: &str) -> bool {
    geometry == GEOMETRY_IMPLEMENTATION_SHA && ownership == OWNERSHIP_IMPLEMENTATION_SHA
}
#[cfg(test)]
mod local_source_tests {
    use super::*;
    #[test]
    fn local_implementation_is_an_independent_exact_probe_domain() {
        assert!(implementation_matches(
            GEOMETRY_IMPLEMENTATION_SHA,
            OWNERSHIP_IMPLEMENTATION_SHA
        ));
        assert!(!implementation_matches(
            "changed geometry",
            OWNERSHIP_IMPLEMENTATION_SHA
        ));
        assert!(!implementation_matches(
            GEOMETRY_IMPLEMENTATION_SHA,
            "changed ownership"
        ));
        assert!(!implementation_matches("", ""));
    }
}
