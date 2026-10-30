//! Existing generator test-only scope, shared without a legacy model dependency.
pub const TEST_ONLY_DIRS: &[&str] = &["code/tests/", "code/modules/unit_tests/"];

/// The guard a generator wraps test-only declarations in.
pub const TEST_GUARD: &str = "#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)";

/// Whether a source file is compiled only in a test build, so whatever a generator writes for it must sit inside [`TEST_GUARD`].
pub fn test_only(rel: &str) -> bool {
    TEST_ONLY_DIRS.iter().any(|d| rel.starts_with(d))
}
