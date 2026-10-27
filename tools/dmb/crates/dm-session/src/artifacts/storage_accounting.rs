//! Exact logical cardinalities and explicit gaps in generic storage traversal.
use super::*;

/// Generic storage traversal never establishes complete heap-byte coverage.
/// Payload consumers may add independently measured allocations, but must not
/// turn logical entry counts or retention weights into exact container bytes.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ArtifactStorageCoverage {
    Partial,
}

/// Allocations not measured by `ObservedArtifactStore::visit_storage`.
/// An exclusion names a possible owner, not proof that it is currently allocated.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ArtifactStorageExclusion {
    StoreAndLockObject,
    BucketIndexNodes,
    LeaseRegistryNodes,
    LeaseRosterNodes,
    VariantClaimIndexNodes,
    PayloadObjectsAndChildren,
    ArcControlBlocks,
    AllocatorMetadata,
}

const EXCLUSIONS: &[ArtifactStorageExclusion] = &[
    ArtifactStorageExclusion::StoreAndLockObject,
    ArtifactStorageExclusion::BucketIndexNodes,
    ArtifactStorageExclusion::LeaseRegistryNodes,
    ArtifactStorageExclusion::LeaseRosterNodes,
    ArtifactStorageExclusion::VariantClaimIndexNodes,
    ArtifactStorageExclusion::PayloadObjectsAndChildren,
    ArtifactStorageExclusion::ArcControlBlocks,
    ArtifactStorageExclusion::AllocatorMetadata,
];

/// One locked diagnostic view of the SAME retained core. These counts describe
/// indexed owners only: escaped Arcs can outlive their last store claim, and
/// are outside this core's traversal. All byte coverage remains explicitly partial.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct ArtifactStorageAccounting {
    /// Diagnostic allocation identity only. Valid for one quiescent traversal;
    /// never stable across lifetimes, an output ID or artifact admission proof.
    pub core_address: usize,
    pub coverage: ArtifactStorageCoverage,
    pub exclusions: &'static [ArtifactStorageExclusion],
    pub buckets: usize,
    pub variants: usize,
    pub leases: usize,
    /// Sum of current exact-key claims in all lease rosters, including siblings.
    pub roster_keys: usize,
    /// Number of distinct physical variants claimed by one or more leases.
    pub claimed_variants: usize,
    /// Sum of reference counts across the physical variant claim index.
    pub claims: usize,
}

impl<T, Q, A, D> ObservedArtifactStore<T, Q, A, D> {
    /// Diagnostic only: report cardinalities, never estimate BTree node bytes.
    /// No payload copying, allocation, resolver replay or artifact admission runs.
    /// Complexity is O(buckets + leases + claimed variants).
    /// A separate `visit_storage` call takes a separate lock; callers requiring
    /// consistent combined diagnostics must inspect a quiescent retained core.
    pub fn storage_accounting(&self) -> ArtifactStorageAccounting {
        let state = self.state.write().unwrap_or_else(|error| error.into_inner());
        ArtifactStorageAccounting {
            core_address: self as *const Self as usize,
            coverage: ArtifactStorageCoverage::Partial,
            exclusions: EXCLUSIONS,
            buckets: state.buckets.len(),
            variants: state.buckets.values().map(|bucket| bucket.len()).sum(),
            leases: state.slots.count_ones() as usize,
            roster_keys: state.buckets.values().flatten().map(|entry| entry.holders.count()).sum(),
            claimed_variants: state
                .buckets
                .values()
                .flatten()
                .filter(|entry| !entry.holders.is_empty())
                .count(),
            claims: state.buckets.values().flatten().map(|entry| entry.holders.count()).sum(),
        }
    }
}

#[cfg(test)]
#[path = "storage_accounting_tests.rs"]
mod tests;
