//! Version-qualified requested std Arc Layout, never an RSS assertion.
//! Unknown profiles and unapproved probe receipts issue NO production plan.
use std::{alloc::Layout, sync::atomic::AtomicUsize};
mod profile {
    include!(concat!(env!("OUT_DIR"), "/native_arc_profile.rs"));
}
#[repr(C, align(2))]
struct AuditedArcHeader {
    strong: AtomicUsize,
    weak: AtomicUsize,
}
#[derive(Debug, Clone, Copy)]
pub(super) struct NativeArcAllocationPlan {
    layout: Layout,
}
impl NativeArcAllocationPlan {
    fn geometry(value: Layout) -> Result<Self, &'static str> {
        if std::mem::size_of::<usize>() != 8
            || std::mem::size_of::<AtomicUsize>() != 8
            || std::mem::align_of::<AtomicUsize>() != 8
        {
            return Err("qualified Arc target primitive layout differs");
        }
        let layout = Layout::new::<AuditedArcHeader>()
            .extend(value)
            .map_err(|_| "qualified Arc Layout overflow")?
            .0
            .pad_to_align();
        Ok(Self { layout })
    }
    fn qualified(value: Layout) -> Result<Self, &'static str> {
        if !profile::CANDIDATE_MATCHED {
            return Err("original compiler/std Arc allocation profile is unsupported");
        }
        if !profile::PROBE_APPROVED {
            return Err(
                "actual Arc allocation probe is not yet approved for this exact compiler profile",
            );
        }
        Self::geometry(value)
    }
    #[cfg(not(dmb_arc_probe))]
    pub(super) fn canonical_value() -> Result<Self, &'static str> {
        Self::qualified(Layout::new::<super::AnswerValue>())
    }
    #[cfg(not(dmb_arc_probe))]
    pub(super) fn retention_lease() -> Result<Self, &'static str> {
        Self::qualified(Layout::new::<super::source_allocation::SourceLease>())
    }
    pub(super) fn layout(self) -> Layout {
        self.layout
    }
    /// TEST BINARY ONLY: compare actual requests to production geometry before
    /// root approves its receipt. This is never a source allocation permit.
    #[cfg(dmb_arc_probe)]
    pub(super) fn probe_candidate(value: Layout) -> Result<Self, &'static str> {
        if !profile::CANDIDATE_MATCHED {
            return Err("standalone probe compiler differs from candidate profile");
        }
        Self::geometry(value)
    }
    #[cfg(dmb_arc_probe)]
    pub(super) fn profile_description() -> &'static str {
        profile::DESCRIPTION
    }
}
#[cfg(all(test, not(dmb_arc_probe)))]
#[path = "../../source_arc_profile_policy.rs"]
mod policy;
#[cfg(all(test, not(dmb_arc_probe)))]
mod tests {
    use super::*;
    #[test]
    fn unapproved_or_unknown_profile_cannot_issue_original_value_roles() {
        if !profile::CANDIDATE_MATCHED || !profile::PROBE_APPROVED {
            assert!(NativeArcAllocationPlan::canonical_value().is_err());
            assert!(NativeArcAllocationPlan::retention_lease().is_err());
        } else {
            let value = NativeArcAllocationPlan::canonical_value().unwrap().layout();
            let lease = NativeArcAllocationPlan::retention_lease().unwrap().layout();
            let expected_value = Layout::new::<AuditedArcHeader>()
                .extend(Layout::new::<super::super::AnswerValue>())
                .unwrap()
                .0
                .pad_to_align();
            let expected_lease = Layout::new::<AuditedArcHeader>()
                .extend(Layout::new::<super::super::source_allocation::SourceLease>())
                .unwrap()
                .0
                .pad_to_align();
            assert_eq!(
                (value.size(), value.align()),
                (expected_value.size(), expected_value.align())
            );
            assert_eq!(
                (lease.size(), lease.align()),
                (expected_lease.size(), expected_lease.align())
            );
        }
    }
    #[test]
    fn same_version_foreign_artifact_and_unknown_target_cannot_qualify() {
        let mut p = policy::Candidate {
            commit: policy::COMMIT,
            release: policy::RELEASE,
            target: policy::TARGET,
            pointer_width: "64",
            source_sha: policy::SOURCE_SHA,
            alloc_sha: policy::ALLOC_SHA,
            has_pointer_atomics: true,
        };
        assert!(policy::matches(&p));
        p.alloc_sha = "foreign-same-version";
        assert!(!policy::matches(&p));
        p.alloc_sha = policy::ALLOC_SHA;
        p.target = "x86_64-unknown-linux-gnu";
        assert!(!policy::matches(&p));
        p.target = policy::TARGET;
        p.source_sha = "installed-source-unissued";
        assert!(!policy::matches(&p));
        p.source_sha = policy::SOURCE_SHA;
        p.commit = "same-release-foreign-commit";
        assert!(!policy::matches(&p));
        p.commit = policy::COMMIT;
        p.release = "foreign-release";
        assert!(!policy::matches(&p));
        p.release = policy::RELEASE;
        p.pointer_width = "32";
        assert!(!policy::matches(&p));
        p.pointer_width = "64";
        p.has_pointer_atomics = false;
        assert!(!policy::matches(&p));
    }
    #[test]
    fn original_geometry_checks_actual_native_alignment_and_overflow() {
        #[repr(align(4096))]
        struct High([u8; 3]);
        let _ = High([0; 3]).0;
        for value in [
            Layout::new::<()>(),
            Layout::new::<u8>(),
            Layout::new::<High>(),
            Layout::array::<u8>(7).unwrap(),
        ] {
            let plan = NativeArcAllocationPlan::geometry(value).unwrap().layout();
            assert!(plan.size() >= value.size());
            assert!(plan.align() >= value.align());
        }
        assert!(NativeArcAllocationPlan::geometry(
            Layout::from_size_align(isize::MAX as usize, 1).unwrap()
        )
        .is_err());
    }
}
