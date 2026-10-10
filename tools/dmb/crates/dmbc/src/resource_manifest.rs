//! Asset-only session facts, separate from semantic memo stages.
//! Session authenticates the record; the pair store authenticates archive bytes.
use crate::{
    input_snapshot::{InputSnapshot, SnapshotProvider},
    publish::ResourceIdentity,
};
use dm_resources::{
    capture::ResourceDemand,
    catalog::{CatalogRecord, ResourceCatalog},
};
use serde::{Deserialize, Serialize};
use std::{collections::BTreeSet, io};
pub struct ObservedValidation {
    pub exact: bool,
    pub now: u128,
}
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct ResourceManifest {
    version: u32,
    policy: u128,
    catalog: CatalogRecord,
    catalog_identity: u128,
    inputs: InputSnapshot,
    order: Vec<usize>,
    archive: ResourceIdentity,
}
pub struct ValidatedResources {
    pub(crate) catalog: ResourceCatalog,
    pub(crate) inputs: InputSnapshot,
    pub(crate) archive: ResourceIdentity,
    pub(crate) order: Vec<usize>,
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ResourceValidationStage {
    CatalogRestore,
    DemandAdmission,
    InputValidation,
    ArchiveAuthentication,
}
#[derive(Clone, Copy, Debug)]
pub struct ResourceValidationMeasurement {
    pub stage: ResourceValidationStage,
    pub seconds: f64,
}
pub type ResourceValidationObserver<'a> = &'a dyn Fn(ResourceValidationMeasurement);
fn measured<T>(
    observer: Option<ResourceValidationObserver<'_>>,
    stage: ResourceValidationStage,
    run: impl FnOnce() -> T,
) -> T {
    let _profile = dm_profile::stage(match stage {
        ResourceValidationStage::CatalogRestore => "resources.catalog_restore",
        ResourceValidationStage::DemandAdmission => "resources.demand_validation",
        ResourceValidationStage::InputValidation => "resources.input_validation",
        ResourceValidationStage::ArchiveAuthentication => "resources.archive_authentication",
    });
    let start = std::time::Instant::now();
    let result = run();
    if let Some(observer) = observer {
        observer(ResourceValidationMeasurement {
            stage,
            seconds: start.elapsed().as_secs_f64(),
        });
    }
    result
}
impl ResourceManifest {
    /// Inputs must contain every selected asset and candidate/negative folder
    /// observation. The CLI constructs this subset from its recorded capture.
    pub fn capture(
        policy: u128,
        catalog: &ResourceCatalog,
        inputs: InputSnapshot,
        order: Vec<usize>,
        archive: ResourceIdentity,
    ) -> io::Result<Self> {
        inputs.check_structure()?;
        for alias in &catalog.record().aliases {
            if !inputs.contains_file(&alias.disk_path) {
                return Err(io::Error::new(
                    io::ErrorKind::InvalidData,
                    "resource manifest omits captured asset",
                ));
            }
        }
        validate_order(&order, catalog.record().aliases.len())?;
        Ok(Self {
            version: 1,
            policy,
            catalog: catalog.record().clone(),
            catalog_identity: catalog.identity(),
            inputs,
            order,
            archive,
        })
    }
    pub fn archive(&self) -> ResourceIdentity {
        self.archive
    }
    pub fn filesystem_proofs(&self) -> io::Result<crate::filesystem_proofs::BulkFileSystemProofs> {
        crate::filesystem_proofs::BulkFileSystemProofs::capture_snapshot(&self.inputs)
    }
    /// Returns None for an ordinary changed-input/archive miss. Provider errors
    /// propagate; neither a read failure nor unsupported lookup proves absence.
    pub fn validate(
        &self,
        policy: u128,
        demand: &ResourceDemand,
        provider: &impl SnapshotProvider,
        exact: bool,
        now: u128,
        authenticate: impl FnOnce(ResourceIdentity) -> io::Result<bool>,
    ) -> io::Result<Option<ValidatedResources>> {
        self.validate_observed(
            policy,
            demand,
            provider,
            ObservedValidation { exact, now },
            authenticate,
            None,
        )
    }
    /// Timings include unsuccessful admission attempts. Filesystem proof capture
    /// precedes this call and must be measured by the caller separately.
    pub fn validate_observed(
        &self,
        policy: u128,
        demand: &ResourceDemand,
        provider: &impl SnapshotProvider,
        validation: ObservedValidation,
        authenticate: impl FnOnce(ResourceIdentity) -> io::Result<bool>,
        observer: Option<ResourceValidationObserver<'_>>,
    ) -> io::Result<Option<ValidatedResources>> {
        let ObservedValidation { exact, now } = validation;
        if self.version != 1 || self.policy != policy {
            return Ok(None);
        }
        let catalog = match measured(observer, ResourceValidationStage::CatalogRestore, || {
            ResourceCatalog::restore(self.catalog.clone(), self.catalog_identity)
        }) {
            Ok(value) => value,
            Err(_) => return Ok(None),
        };
        let admitted = measured(
            observer,
            ResourceValidationStage::DemandAdmission,
            || -> io::Result<bool> {
                validate_order(&self.order, catalog.record().aliases.len())?;
                if catalog
                    .record()
                    .aliases
                    .iter()
                    .any(|alias| !self.inputs.contains_file(&alias.disk_path))
                {
                    return Ok(false);
                }

                if catalog.record().contexts.len() != 1
                    || catalog.record().contexts[0].as_slice() != demand.context.bytes()
                {
                    return Ok(false);
                }
                let requested: BTreeSet<&str> = demand
                    .literals
                    .iter()
                    .map(|literal| literal.path.as_str())
                    .collect();
                let previous: BTreeSet<&str> = catalog
                    .record()
                    .lookups
                    .iter()
                    .map(|lookup| lookup.path.as_str())
                    .collect();
                if requested != previous
                    || catalog.record().lookups.iter().any(|lookup| {
                        lookup.search_context != demand.context.identity()
                            || matches!(
                                lookup.outcome,
                                dm_resources::native_resolver::CapturedResourceOutcome::Unsupported
                            )
                    })
                {
                    return Ok(false);
                }
                for request in &demand.additional {
                    if !catalog.record().aliases.iter().any(|alias| {
                        alias.name == request.archive_name && alias.disk_path == request.disk_path
                    }) {
                        return Ok(false);
                    }
                }
                Ok(true)
            },
        )?;
        if !admitted {
            return Ok(None);
        }
        let Some((_, inputs)) =
            measured(observer, ResourceValidationStage::InputValidation, || {
                self.inputs.validate_for_reuse(provider, exact, now)
            })?
        else {
            return Ok(None);
        };
        if !measured(
            observer,
            ResourceValidationStage::ArchiveAuthentication,
            || authenticate(self.archive),
        )? {
            return Ok(None);
        }
        Ok(Some(ValidatedResources {
            catalog,
            inputs,
            archive: self.archive,
            order: self.order.clone(),
        }))
    }
}
fn validate_order(order: &[usize], count: usize) -> io::Result<()> {
    let unique: BTreeSet<usize> = order.iter().copied().collect();
    if order.len() != count
        || unique.len() != count
        || unique
            .iter()
            .next_back()
            .is_some_and(|index| *index >= count)
    {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            "resource manifest archive order incomplete",
        ));
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::input_snapshot::{FolderListing, Stamp};
    use dm_resources::capture::{CaptureConfig, CaptureProvider};
    use std::{
        collections::BTreeSet,
        path::{Path, PathBuf},
    };
    struct Inputs {
        bytes: Vec<u8>,
        listing: FolderListing,
    }
    impl SnapshotProvider for Inputs {
        fn stamp(&self, _: &Path) -> io::Result<Stamp> {
            Ok(Stamp {
                size: self.bytes.len() as u64,
                modified_ns: 1,
                file_id: Some(7),
            })
        }
        fn read(&self, path: &Path) -> io::Result<(Stamp, Vec<u8>)> {
            Ok((self.stamp(path)?, self.bytes.clone()))
        }
        fn list(&self, _: &Path) -> io::Result<FolderListing> {
            Ok(self.listing.clone())
        }
    }
    impl CaptureProvider for Inputs {
        fn read_candidate(&self, _: &Path) -> io::Result<Option<dm_resources::SharedBytes>> {
            Ok(Some(self.bytes.clone().into()))
        }
    }
    struct Tree;
    impl dm_ir::Resolver for Tree {
        fn resolve(&self, q: dm_ir::ResolveQuery) -> dm_ir::ResolvedMeaning {
            dm_ir::ResolvedMeaning::Unsupported(q)
        }
    }
    #[test]
    fn resource_manifest_requires_asset_archive_and_exact_current_demand_proofs() {
        let mut provider = Inputs {
            bytes: b"old".to_vec(),
            listing: FolderListing::Missing,
        };
        let plan = dm_preprocess::regions::DirectivePlan {
            project_dir: PathBuf::from("game"),
            ..Default::default()
        };
        let expanded = dm_preprocess::regions::ExpandedRegions {
            text: "/proc/p()\n    return 'asset.txt'\n".into(),
            ..Default::default()
        };
        let policy = dm_resources::capture::CapturePolicy {
            certified_raw_extensions: BTreeSet::from(["txt".into()]),
        };
        let captured = dm_resources::capture::capture_expanded(
            &plan,
            &expanded,
            CaptureConfig {
                policy: &policy,
                encoded: &[],
                additional: &[],
            },
            &provider,
        )
        .unwrap();
        let host = captured
            .into_resolver(Tree, &dm_ir::SymbolTable::default())
            .unwrap();
        let catalog = host.catalog();
        let asset = &catalog.record().aliases[0].disk_path;
        let mut inputs = InputSnapshot::new(10_000_000_000);
        inputs
            .record_file(asset, provider.stamp(asset).unwrap(), &provider.bytes)
            .unwrap();
        inputs
            .record_folder(Path::new("game"), provider.listing.clone())
            .unwrap();
        let archive = ResourceIdentity { bytes: 9, hash: 42 };
        let manifest = ResourceManifest::capture(3, &catalog, inputs, vec![0], archive).unwrap();
        let demand = dm_resources::capture::discover_demand(&plan, &expanded, &[], &[]).unwrap();
        let stages = std::cell::RefCell::new(Vec::new());
        let observer = |measurement: ResourceValidationMeasurement| {
            assert!(measurement.seconds.is_finite() && measurement.seconds >= 0.0);
            stages.borrow_mut().push(measurement.stage);
        };
        assert!(manifest
            .validate_observed(
                3,
                &demand,
                &provider,
                ObservedValidation {
                    exact: true,
                    now: 20_000_000_000
                },
                |value| Ok(value == archive),
                Some(&observer)
            )
            .unwrap()
            .is_some());
        assert_eq!(
            *stages.borrow(),
            vec![
                ResourceValidationStage::CatalogRestore,
                ResourceValidationStage::DemandAdmission,
                ResourceValidationStage::InputValidation,
                ResourceValidationStage::ArchiveAuthentication
            ]
        );
        assert!(manifest
            .validate(3, &demand, &provider, false, 20_000_000_000, |_| Ok(false))
            .unwrap()
            .is_none());
        provider.bytes = b"new".to_vec();
        assert!(manifest
            .validate(3, &demand, &provider, true, 20_000_000_000, |_| Ok(true))
            .unwrap()
            .is_none());
        provider.bytes = b"old".to_vec();
        provider.listing = FolderListing::Present(vec!["shadow.txt".into()]);
        assert!(manifest
            .validate(3, &demand, &provider, false, 20_000_000_000, |_| Ok(true))
            .unwrap()
            .is_none());
        provider.listing = FolderListing::Missing;
        let changed = dm_preprocess::regions::ExpandedRegions {
            text: "/proc/p()\n    return 'new.txt'\n".into(),
            ..Default::default()
        };
        let changed = dm_resources::capture::discover_demand(&plan, &changed, &[], &[]).unwrap();
        assert!(manifest
            .validate(3, &changed, &provider, false, 20_000_000_000, |_| Ok(true))
            .unwrap()
            .is_none());
    }
}
