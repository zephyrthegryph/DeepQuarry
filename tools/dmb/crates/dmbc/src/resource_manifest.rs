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
use std::{
    collections::BTreeSet,
    io,
    sync::{Arc, OnceLock},
};
pub struct ObservedValidation {
    pub exact: bool,
    pub now: u128,
}
#[derive(Clone, Debug)]
pub struct ResourceManifest {
    version: u32,
    policy: u128,
    catalog: Arc<CatalogRecord>,
    catalog_identity: u128,
    inputs: Arc<InputSnapshot>,
    content: Arc<ResourceContent>,
    admitted_catalog: OnceLock<ResourceCatalog>,
}
/// Immutable archive layout contains no absolute source or publication paths.
#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct ResourceContent {
    pub(crate) order: Vec<usize>,
    pub(crate) archive: ResourceIdentity,
}
#[path = "resource_manifest_wire.rs"]
mod wire;
impl PartialEq for ResourceManifest {
    fn eq(&self, other: &Self) -> bool {
        self.version == other.version
            && self.policy == other.policy
            && self.catalog == other.catalog
            && self.catalog_identity == other.catalog_identity
            && self.inputs == other.inputs
            && self.content == other.content
    }
}
impl Eq for ResourceManifest {}
pub struct ValidatedResources {
    pub(crate) catalog: ResourceCatalog,
    pub(crate) inputs: InputSnapshot,
    pub(crate) content: Arc<ResourceContent>,
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
            catalog: Arc::clone(catalog.shared_record()),
            catalog_identity: catalog.identity(),
            inputs: Arc::new(inputs),
            content: Arc::new(ResourceContent { order, archive }),
            admitted_catalog: OnceLock::from(catalog.clone()),
        })
    }
    pub(crate) fn census(&self, census: &mut crate::heap_census::HeapCensus) {
        if census.arc_object("resources.input_proof", &self.inputs) {
            crate::runner_host::resources::inspect_snapshot(&self.inputs, census);
        }
        if census.arc_object("resources.archive_content", &self.content) {
            census.vec_payload("resources.archive_order", &self.content.order);
        }
        if !census.arc_object("resources.catalog", &self.catalog) {
            return;
        }
        census.vec_payload("resources.aliases", &self.catalog.aliases);
        for alias in &self.catalog.aliases {
            census.string("resources.aliases", &alias.name);
            census.path("resources.aliases", &alias.disk_path);
        }
        census.vec_payload("resources.contexts", &self.catalog.contexts);
        for context in &self.catalog.contexts {
            census.vec_payload("resources.contexts", context);
        }
        census.vec_payload("resources.lookups", &self.catalog.lookups);
        for lookup in &self.catalog.lookups {
            census.string("resources.lookups", &lookup.path);
        }
    }
    pub fn archive(&self) -> ResourceIdentity {
        self.content.archive
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
            if let Some(catalog) = self.admitted_catalog.get() {
                if !Arc::ptr_eq(catalog.shared_record(), &self.catalog)
                    || catalog.identity() != self.catalog_identity
                {
                    return Err(io::Error::new(
                        io::ErrorKind::InvalidData,
                        "resource catalog cached owner/identity differs",
                    ));
                }
                return Ok(catalog.clone());
            }
            let restored =
                ResourceCatalog::restore_shared(Arc::clone(&self.catalog), self.catalog_identity)?;
            // Concurrent first admissions may restore independently; only one immutable
            // owner is retained. Every later request still performs current admission below.
            let _ = self.admitted_catalog.set(restored);
            Ok::<_, io::Error>(self.admitted_catalog.get().unwrap().clone())
        }) {
            Ok(value) => value,
            Err(_) => return Ok(None),
        };
        let admitted = measured(
            observer,
            ResourceValidationStage::DemandAdmission,
            || -> io::Result<bool> {
                validate_order(&self.content.order, catalog.record().aliases.len())?;
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
            || authenticate(self.content.archive),
        )? {
            return Ok(None);
        }
        Ok(Some(ValidatedResources {
            catalog,
            inputs,
            content: Arc::clone(&self.content),
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
        // Resident hints carry no asset bytes and never replace current admission.
        let owner = crate::runner_host::resources::Resources::default();
        let configuration = crate::runner_host::resources::Configuration {
            policy: 3,
            project: "game/project.dme".into(),
            defines: Default::default(),
            output: "output/project.dme".into(),
            store: Some("store".into()),
            generated: Default::default(),
        };
        owner.remember(
            configuration.clone(),
            crate::runner_host::resources::Hint {
                pair: 7,
                manifest: std::sync::Arc::new(manifest.clone()),
                outputs: Arc::new(InputSnapshot::new(0)),
            },
        );
        let retained = owner.hint(&configuration).unwrap();
        assert_eq!(*retained.manifest, manifest);
        let mut changed = configuration.clone();
        changed.output = "other/project.dme".into();
        assert!(owner.hint(&changed).is_none());
        changed = configuration.clone();
        changed.defines.insert("MODE".into(), "1".into());
        assert!(owner.hint(&changed).is_none());
        changed = configuration.clone();
        changed.generated.insert("game/authored.dm".into());
        assert!(owner.hint(&changed).is_none());
        changed = configuration.clone();
        changed.policy += 1;
        assert!(owner.hint(&changed).is_none());
        assert!(std::sync::Arc::ptr_eq(
            &retained,
            &owner.hint(&configuration).unwrap()
        ));
        let demand = dm_resources::capture::discover_demand(&plan, &expanded, &[], &[]).unwrap();
        assert!(Arc::ptr_eq(&manifest.catalog, catalog.shared_record()));
        let clone = manifest.clone();
        assert!(Arc::ptr_eq(&clone.catalog, &manifest.catalog));
        assert!(Arc::ptr_eq(&clone.inputs, &manifest.inputs));
        assert!(Arc::ptr_eq(&clone.content, &manifest.content));
        #[derive(Serialize, Deserialize)]
        struct LegacyManifest {
            version: u32,
            policy: u128,
            catalog: CatalogRecord,
            catalog_identity: u128,
            inputs: InputSnapshot,
            order: Vec<usize>,
            archive: ResourceIdentity,
        }
        let legacy = LegacyManifest {
            version: manifest.version,
            policy: manifest.policy,
            catalog: (*manifest.catalog).clone(),
            catalog_identity: manifest.catalog_identity,
            inputs: (*manifest.inputs).clone(),
            order: manifest.content.order.clone(),
            archive: manifest.content.archive,
        };
        let legacy_bytes = dm_wire::encode(0x524d_0001, &legacy).unwrap();
        assert_eq!(
            legacy_bytes,
            dm_wire::encode(0x524d_0001, &manifest).unwrap()
        );
        let legacy_restored: ResourceManifest =
            dm_wire::decode(0x524d_0001, &legacy_bytes, dm_wire::MAX_BYTES).unwrap();
        assert_eq!(legacy_restored, manifest);
        // The durable wire remains the old record object, not a cache envelope.
        let wire = serde_json::to_vec(&manifest).unwrap();
        let restored: ResourceManifest = serde_json::from_slice(&wire).unwrap();
        assert!(restored.admitted_catalog.get().is_none());
        assert_eq!(serde_json::to_vec(&restored).unwrap(), wire);
        for candidate in [&manifest, &restored] {
            let first = candidate
                .validate(3, &demand, &provider, true, 20_000_000_000, |_| Ok(true))
                .unwrap()
                .unwrap();
            let second = candidate
                .validate(3, &demand, &provider, true, 20_000_000_000, |_| Ok(true))
                .unwrap()
                .unwrap();
            assert!(Arc::ptr_eq(&first.content, &candidate.content));
            assert!(Arc::ptr_eq(&first.content, &second.content));
            assert!(Arc::ptr_eq(
                first.catalog.shared_record(),
                second.catalog.shared_record()
            ));
            assert!(Arc::ptr_eq(
                first.catalog.shared_record(),
                &candidate.catalog
            ));
            assert!(candidate
                .validate(3, &demand, &provider, true, 20_000_000_000, |_| Ok(false))
                .unwrap()
                .is_none());
        }
        let mut changed_owner = manifest.clone();
        Arc::make_mut(&mut changed_owner.catalog).aliases[0].name = "changed.txt".into();
        assert!(changed_owner
            .validate(3, &demand, &provider, true, 20_000_000_000, |_| Ok(true))
            .unwrap()
            .is_none());
        let mut changed_identity = manifest.clone();
        changed_identity.catalog_identity ^= 1;
        assert!(changed_identity
            .validate(3, &demand, &provider, true, 20_000_000_000, |_| Ok(true))
            .unwrap()
            .is_none());
        // Deserialize exact bytes: serde_json::Value would round large u128 pins.
        let mut invalid_catalog: ResourceManifest = serde_json::from_slice(&wire).unwrap();
        Arc::make_mut(&mut invalid_catalog.catalog).aliases[0].name = "changed.txt".into();
        assert!(invalid_catalog
            .validate(3, &demand, &provider, true, 20_000_000_000, |_| Ok(true))
            .unwrap()
            .is_none());
        let mut invalid_order: ResourceManifest = serde_json::from_slice(&wire).unwrap();
        Arc::make_mut(&mut invalid_order.content).order = vec![0, 0];
        assert!(invalid_order
            .validate(3, &demand, &provider, true, 20_000_000_000, |_| Ok(true))
            .is_err());
        let stages = std::cell::RefCell::new(Vec::new());
        let observer = |measurement: ResourceValidationMeasurement| {
            assert!(measurement.seconds.is_finite() && measurement.seconds >= 0.0);
            stages.borrow_mut().push(measurement.stage);
        };
        assert!(retained
            .manifest
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
        assert!(retained
            .manifest
            .validate(3, &demand, &provider, false, 20_000_000_000, |_| Ok(false))
            .unwrap()
            .is_none());
        provider.bytes = b"new".to_vec();
        assert!(retained
            .manifest
            .validate(3, &demand, &provider, true, 20_000_000_000, |_| Ok(true))
            .unwrap()
            .is_none());
        provider.bytes = b"old".to_vec();
        provider.listing = FolderListing::Present(vec!["shadow.txt".into()]);
        assert!(retained
            .manifest
            .validate(3, &demand, &provider, false, 20_000_000_000, |_| Ok(true))
            .unwrap()
            .is_none());
        provider.listing = FolderListing::Missing;
        let changed = dm_preprocess::regions::ExpandedRegions {
            text: "/proc/p()\n    return 'new.txt'\n".into(),
            ..Default::default()
        };
        let changed = dm_resources::capture::discover_demand(&plan, &changed, &[], &[]).unwrap();
        assert!(retained
            .manifest
            .validate(3, &changed, &provider, false, 20_000_000_000, |_| Ok(true))
            .unwrap()
            .is_none());
        // A new exact configuration replaces the sole resident entry. External
        // readers remain valid until dropped, but the store owns no history.
        let old = std::sync::Arc::downgrade(&retained);
        let mut next = configuration.clone();
        next.output = "next/project.dme".into();
        owner.remember(
            next.clone(),
            crate::runner_host::resources::Hint {
                pair: 8,
                manifest: std::sync::Arc::new(manifest),
                outputs: Arc::new(InputSnapshot::new(0)),
            },
        );
        assert!(owner.hint(&configuration).is_none());
        assert_eq!(owner.hint(&next).unwrap().pair, 8);
        drop(retained);
        assert!(old.upgrade().is_none());
    }
}
