//! Optional process-local engine retention for the shared request pipeline.
//! Source revisions and mutable output inventories remain request-local.
use crate::{engine::EngineSnapshot, engine_link::EngineLinkFacts};
use std::{
    collections::BTreeMap,
    path::PathBuf,
    sync::{Arc, Mutex},
};

#[path = "runner_host_memo.rs"]
mod memo;

/// A single bounded engine slot. The CLI uses a temporary owner; a long-lived
/// caller may reuse it across requests without retaining a build lease.
pub struct BuildHost {
    engine: Option<Arc<RetainedEngine>>,
    memo: Option<memo::ResidentMemo>,
}

#[derive(Eq, PartialEq)]
struct EngineConfiguration {
    project: PathBuf,
    defines: BTreeMap<String, String>,
    bootstrap_catalog: bool,
    schema: u128,
}

pub(crate) struct RetainedEngine {
    configuration: EngineConfiguration,
    pub(crate) bytes: Arc<[u8]>,
    pub(crate) snapshot: EngineSnapshot,
    links: Mutex<Option<EngineLinkFacts>>,
}

impl Default for BuildHost {
    fn default() -> Self {
        Self {
            engine: None,
            memo: Some(memo::ResidentMemo::default()),
        }
    }
}
impl BuildHost {
    /// CLI adapter: no resident candidates or memo-record construction without disk.
    pub fn one_shot() -> Self {
        Self {
            engine: None,
            memo: None,
        }
    }

    pub(crate) fn clear_regions(&mut self) {
        if self.memo.is_some() {
            self.memo = Some(memo::ResidentMemo::default());
        }
    }

    pub(crate) fn expansion_memo<'a>(
        &'a self,
        disk: Option<&'a dyn dm_preprocess::regions::ExpansionMemo>,
    ) -> Option<impl dm_preprocess::regions::ExpansionMemo + 'a> {
        match &self.memo {
            Some(resident) => Some(resident.with_disk(disk)),
            None => disk.map(memo::MemoView::disk_only),
        }
    }

    pub(crate) fn engine(
        &mut self,
        project: PathBuf,
        defines: BTreeMap<String, String>,
        bootstrap_catalog: bool,
        bytes: Vec<u8>,
    ) -> Result<Arc<RetainedEngine>, String> {
        let configuration = EngineConfiguration {
            project,
            defines,
            bootstrap_catalog,
            schema: 1,
        };
        if let Some(retained) = &self.engine {
            // A digest is never sufficient admission for this retained owner.
            if retained.configuration == configuration && retained.bytes.as_ref() == bytes {
                return Ok(Arc::clone(retained));
            }
        }
        let snapshot = EngineSnapshot::from_bytes(&bytes, configuration.schema)
            .map_err(|error| format!("engine template: {error:?}"))?;
        let snapshot = if bootstrap_catalog {
            snapshot
                .with_bootstrap_catalog()
                .map_err(|error| format!("engine catalog: {error:?}"))?
        } else {
            snapshot
        };
        let retained = Arc::new(RetainedEngine {
            configuration,
            bytes: bytes.into(),
            snapshot,
            links: Mutex::new(None),
        });
        if self.memo.is_some() {
            self.memo = Some(memo::ResidentMemo::default());
        }
        self.engine = Some(Arc::clone(&retained));
        Ok(retained)
    }
}

impl RetainedEngine {
    /// Return a mutable request overlay without altering the pinned baseline.
    /// First capture stays at the ordinary pipeline's linking-input boundary.
    pub(crate) fn link_overlay(&self) -> Result<EngineLinkFacts, String> {
        let mut retained = self
            .links
            .lock()
            .map_err(|_| "retained engine links poisoned")?;
        if retained.is_none() {
            *retained = Some(crate::engine_link::capture(&self.bytes, &self.snapshot)?);
        }
        let baseline = retained.as_ref().expect("captured engine links");
        Ok(EngineLinkFacts {
            inventory: baseline.inventory.clone(),
            references: baseline.references.clone(),
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    fn capture(host: &mut BuildHost, defines: BTreeMap<String, String>) -> Arc<RetainedEngine> {
        host.engine(
            PathBuf::from("E:/fixture/world.dme"),
            defines,
            true,
            include_bytes!("../../../fixtures/native_template.bin").to_vec(),
        )
        .unwrap()
    }
    #[test]
    fn one_shot_without_disk_has_no_memo_and_engine_capture_does_not_enable_it() {
        let mut host = BuildHost::one_shot();
        assert!(host.expansion_memo(None).is_none());
        capture(&mut host, BTreeMap::new());
        assert!(host.expansion_memo(None).is_none());
        host.clear_regions();
        assert!(host.expansion_memo(None).is_none());
        assert!(BuildHost::default().expansion_memo(None).is_some());
    }
    #[test]
    fn exact_configuration_reuses_owner_and_request_overlay_is_independent() {
        let mut host = BuildHost::default();
        let first = capture(&mut host, BTreeMap::new());
        assert!(first.links.lock().unwrap().is_none());
        let mut overlay = first.link_overlay().unwrap();
        let expected_entries = overlay.inventory.entries.len();
        let expected_references = overlay.references.references.len();
        assert!(expected_entries > 0);
        overlay.inventory.entries.clear();
        overlay.references.references.clear();
        let second = capture(&mut host, BTreeMap::new());
        assert!(Arc::ptr_eq(&first, &second));
        let independent = second.link_overlay().unwrap();
        assert_eq!(independent.inventory.entries.len(), expected_entries);
        assert_eq!(independent.references.references.len(), expected_references);
        let changed = capture(
            &mut host,
            BTreeMap::from([("CITESTING".into(), "1".into())]),
        );
        assert!(!Arc::ptr_eq(&first, &changed));
    }
    #[test]
    fn invalid_changed_engine_does_not_replace_authenticated_owner() {
        let mut host = BuildHost::default();
        let first = capture(&mut host, BTreeMap::new());
        assert!(host
            .engine(
                PathBuf::from("E:/fixture/world.dme"),
                BTreeMap::new(),
                true,
                vec![0]
            )
            .is_err());
        let again = capture(&mut host, BTreeMap::new());
        assert!(Arc::ptr_eq(&first, &again));
    }
}
