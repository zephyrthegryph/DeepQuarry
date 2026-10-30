//! Build-time contract registry, also exercised by native unit tests.
//! This is not a source semantic model or a client-supplied runtime profile.
pub const COMMIT: &str = "58cf8f9c35b355199727627d07ae34a4e2846d67";
pub const RELEASE: &str = "1.99.1";
pub const TARGET: &str = "x86_64-pc-windows-msvc";
pub const SOURCE_SHA: &str = "b2f806b0f696a181018072625dceed25304aa97dfef6a79bac9800d529afdd0e";
pub const ALLOC_SHA: &str = "ef5df2b944db14679cc916d06ce7cb81968d741a5c10f5f5cf8f5b247c764d7a";
// Root must record the actual independent probe receipt BEFORE changing this.
// Audited installed source by itself deliberately issues no production permit.
pub const PROBE_APPROVED: bool = false;
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
