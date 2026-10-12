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
    IncidenceIndexNodes,
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
    ArtifactStorageExclusion::IncidenceIndexNodes,
    ArtifactStorageExclusion::PayloadObjectsAndChildren,
    ArtifactStorageExclusion::ArcControlBlocks,
    ArtifactStorageExclusion::AllocatorMetadata,
];

/// Logical incidence entries only; private BTree node bytes remain excluded.
/// Certificate, uncovered-domain and conflict indexes are not enumerated here.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct ArtifactIncidenceCounts {
    pub leaves: usize,
    pub variants: usize,
    pub domains: usize,
    pub subscriptions: usize,
}

/// One locked diagnostic view of the SAME retained core. These counts describe
/// indexed owners only: escaped Arcs can outlive their last store claim, and
/// are outside this core's traversal. All byte coverage remains explicitly partial.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct ArtifactStorageAccounting {
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
    pub incidence: Option<ArtifactIncidenceCounts>,
}

impl<T, Q, A, D> ObservedArtifactStore<T, Q, A, D> {
    /// Diagnostic only: report cardinalities, never estimate BTree node bytes.
    /// No payload copying, allocation, resolver replay or artifact admission runs.
    /// Complexity is O(buckets + leases + claimed variants + incidence leaves).
    /// A separate `visit_storage` call takes a separate lock; callers requiring
    /// consistent combined diagnostics must inspect a quiescent retained core.
    pub fn storage_accounting(&self) -> ArtifactStorageAccounting {
        let state = self.state.lock().unwrap_or_else(|error| error.into_inner());
        ArtifactStorageAccounting {
            coverage: ArtifactStorageCoverage::Partial,
            exclusions: EXCLUSIONS,
            buckets: state.buckets.len(),
            variants: state.buckets.values().map(Vec::len).sum(),
            leases: state.leases.len(),
            roster_keys: state.leases.values().map(BTreeMap::len).sum(),
            claimed_variants: state.claims.len(),
            claims: state.claims.values().map(|(_, claims)| claims).sum(),
            incidence: state.incidence.as_ref().map(|index| {
                let (leaves, variants, domains, subscriptions) = index.counts();
                ArtifactIncidenceCounts {
                    leaves,
                    variants,
                    domains,
                    subscriptions,
                }
            }),
        }
    }
}

#[cfg(test)]
#[path = "storage_accounting_tests.rs"]
mod tests;
