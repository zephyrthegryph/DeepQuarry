//! Diagnostic generic-core cardinalities; never retention weights or heap sizes.
use super::*;
use dm_session::{ArtifactStorageAccounting, ArtifactStorageCoverage, ArtifactStorageExclusion};

impl HeapCensus {
    /// Call only at a quiescent census boundary, separately from payload visitors.
    /// Shared-core logical counts belong to the first alias in this boundary.
    pub(crate) fn artifact_storage_accounting(
        &mut self,
        owner: &str,
        accounting: ArtifactStorageAccounting,
    ) {
        let control = format!("{owner}.control");
        if !self
            .accounted_artifact_cores
            .insert(accounting.core_address)
        {
            self.owner(&control).shared_encounters += 1;
            return;
        }
        match accounting.coverage {
            ArtifactStorageCoverage::Partial => self.unknown(
                &control,
                "generic storage coverage is partial; logical counts below add no heap bytes and include all sibling leases, not a per-host charge",
            ),
        }
        for exclusion in accounting.exclusions {
            let reason = match exclusion {
                ArtifactStorageExclusion::StoreAndLockObject => "generic visitor excludes store/lock object storage; a caller may independently visit its actual owner",
                ArtifactStorageExclusion::BucketIndexNodes => "private generic-store bucket BTree node capacity unavailable",
                ArtifactStorageExclusion::LeaseRegistryNodes => "private generic-store lease registry BTree node capacity unavailable",
                ArtifactStorageExclusion::LeaseRosterNodes => "private generic-store lease roster BTree node capacity unavailable",
                ArtifactStorageExclusion::VariantClaimIndexNodes => "private generic-store physical variant claim BTree node capacity unavailable",
                ArtifactStorageExclusion::IncidenceIndexNodes => "private generic-store incidence/certificate/subscriber BTree node capacity unavailable",
                ArtifactStorageExclusion::PayloadObjectsAndChildren => "generic visitor exposes payload references; nested payload coverage requires the separate consumer traversal",
                ArtifactStorageExclusion::ArcControlBlocks => "shared generic-store Arc control block bytes unavailable",
                ArtifactStorageExclusion::AllocatorMetadata => "generic-store allocator metadata and allocation rounding unavailable",
            };
            self.unknown(&control, reason);
        }
        for (name, count) in [
            ("buckets", accounting.buckets),
            ("variants", accounting.variants),
            ("leases", accounting.leases),
            ("roster_keys", accounting.roster_keys),
            ("claimed_variants", accounting.claimed_variants),
            ("claims", accounting.claims),
        ] {
            self.observe_items(&format!("{control}.{name}"), count);
        }
        if let Some(incidence) = accounting.incidence {
            for (name, count) in [
                ("leaves", incidence.leaves),
                ("variants", incidence.variants),
                ("domains", incidence.domains),
                ("subscriptions", incidence.subscriptions),
            ] {
                self.observe_items(&format!("{control}.incidence.{name}"), count);
            }
        }
    }
}

#[cfg(test)]
#[path = "artifact_accounting_tests.rs"]
mod tests;
