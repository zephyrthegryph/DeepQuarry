//! Persistent canonical project state. Semantic identities exclude allocation
//! history and source offsets; each output generation receives fresh table IDs.
use super::*;
use dm_store::{Change, Key, Store};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::sync::{
    atomic::{AtomicUsize, Ordering},
    Mutex, OnceLock,
};

const MAX_SKELETON: usize = 96 * 1024 * 1024;

#[derive(Clone, Serialize, Deserialize)]
pub(super) struct OwnedPendingProc {
    pub owner: Option<u32>,
    pub owner_path: String,
    pub verb: bool,
}

#[derive(Clone, Serialize, Deserialize)]
pub(super) struct SkeletonMetadata {
    pub strings: StringIndex,
    pub proc_paths: HashSet<Vec<u8>>,
    pub class_paths: HashMap<String, u32>,
    pub pending: Vec<OwnedPendingProc>,
    pub dynamic: Vec<PendingDynamic>,
    pub initializer_globals: HashMap<String, u32>,
    pub global_proc_ids: HashMap<String, u32>,
    pub shared: Arc<SharedLowerBindings>,
    pub invocations: Vec<InvocationPlan>,
}

#[derive(Clone, Serialize, Deserialize)]
pub(super) struct InvocationPlan {
    pub path: String,
    pub params: Vec<ParsedParameter>,
    pub metadata: ProcMetadata,
    pub static_ids: HashMap<String, u32>,
    pub bindings: LowerBindings,
    /// Source-independent invocation semantics, hashed once with the prefix.
    pub frame_digest: String,
}

pub(super) struct FrozenSkeleton {
    pub image: Dmb,
    pub metadata: SkeletonMetadata,
    resident_charge: AtomicUsize,
}

impl FrozenSkeleton {
    pub(super) fn new(image: Dmb, metadata: SkeletonMetadata) -> Self {
        Self {
            image,
            metadata,
            resident_charge: AtomicUsize::new(MAX_SKELETON * 2),
        }
    }
    fn encode(&self) -> Option<Vec<u8>> {
        // One serialization buffer: the prefix can be large, and two temporary
        // JSON buffers followed by concatenation unnecessarily duplicate it.
        let mut bytes = b"DMSKEL02".to_vec();
        bytes.extend_from_slice(&0_u64.to_le_bytes());
        serde_json::to_writer(&mut bytes, &self.image).ok()?;
        let image_size = bytes.len().checked_sub(16)?;
        bytes[8..16].copy_from_slice(&(image_size as u64).to_le_bytes());
        serde_json::to_writer(&mut bytes, &self.metadata).ok()?;
        let decoded_size = bytes.len();
        self.resident_charge
            .store(decoded_size.saturating_mul(2), Ordering::Relaxed);
        if std::env::var_os("DM_BUILD_TRACE").is_some() {
            eprintln!("DM_BUILD_TRACE declaration skeleton: image {} bytes, metadata {} bytes, retained charge {} bytes, persistence cap {} bytes", image_size, decoded_size - image_size - 16, decoded_size.saturating_mul(2), MAX_SKELETON);
        }
        if decoded_size > MAX_SKELETON {
            return None;
        }
        Some(lz4_flex::compress_prepend_size(&bytes))
    }

    fn decode(bytes: &[u8]) -> Option<Self> {
        if bytes.len() < 4 || bytes.len() > MAX_SKELETON {
            return None;
        }
        let size = u32::from_le_bytes(bytes[..4].try_into().ok()?) as usize;
        if size > MAX_SKELETON {
            return None;
        }
        let mut decoded = vec![0; size];
        if lz4_flex::decompress_into(&bytes[4..], &mut decoded).ok()? != size {
            return None;
        }
        if decoded.len() < 16 || &decoded[..8] != b"DMSKEL02" {
            return None;
        }
        let image_size =
            usize::try_from(u64::from_le_bytes(decoded[8..16].try_into().ok()?)).ok()?;
        let end = 16usize.checked_add(image_size)?;
        let image = serde_json::from_slice(decoded.get(16..end)?).ok()?;
        let metadata: SkeletonMetadata = serde_json::from_slice(decoded.get(end..)?).ok()?;
        // This is a pre-procedure image; reject corrupt cached wire allocations.
        // Procedure-valued defaults still contain unresolved placeholders at
        // this stage. Full reference validation belongs to the final image.
        Some(Self {
            image,
            metadata,
            resident_charge: AtomicUsize::new(size.saturating_mul(2)),
        })
    }
}

fn shared_skeletons() -> &'static Mutex<dm_store::SharedArtifacts<FrozenSkeleton>> {
    static SHARED: OnceLock<Mutex<dm_store::SharedArtifacts<FrozenSkeleton>>> = OnceLock::new();
    SHARED.get_or_init(|| Mutex::new(dm_store::SharedArtifacts::new(256)))
}

/// One state owner per worktree/configuration. Disk stages are content addressed
/// and shared; mutable query identities and source locations stay session local.
#[derive(Default)]
pub(crate) struct CanonicalSession {
    pub graph: crate::ProjectProcedureGraph,
    pub maps: crate::maps::MapInitializerSession,
    pub active_keys: BTreeSet<crate::ProcKey>,
    project: Option<std::path::PathBuf>,
    configuration: Option<String>,
    skeleton: Option<(String, Arc<FrozenSkeleton>)>,
    pub skeleton_revision: String,
    pub skeleton_hits: usize,
    pub skeleton_misses: usize,
    pub emission_stats: ArtifactReuseStats,
}

impl CanonicalSession {
    pub(crate) fn bind_configuration(
        &mut self,
        project: &Path,
        configuration: &str,
        cache_root: Option<&Path>,
    ) {
        let identity = std::fs::canonicalize(project).unwrap_or_else(|_| project.to_owned());
        if self.project.as_ref() == Some(&identity)
            && self.configuration.as_deref() == Some(configuration)
        {
            return;
        }
        let root = cache_root
            .map(Path::to_path_buf)
            .unwrap_or_else(|| crate::lower_cache::default_cache_root(project));
        let project_identity = format!("{}\0{configuration}", identity.display());
        self.graph = crate::ProjectProcedureGraph::open(&root, &project_identity);
        self.maps = crate::maps::MapInitializerSession::open(&root, &project_identity);
        self.skeleton = None;
        self.project = Some(identity);
        self.configuration = Some(configuration.to_owned());
    }

    pub(crate) fn resident_bytes(&self) -> usize {
        // Prefixes with equal content identities share one immutable allocation
        // across sessions. Divide its conservative charge among live Arc owners.
        self.graph
            .resident_bytes()
            .saturating_add(self.maps.resident_bytes())
            .saturating_add(self.skeleton.as_ref().map_or(0, |(_, prefix)| {
                prefix
                    .resident_charge
                    .load(Ordering::Relaxed)
                    .div_ceil(Arc::strong_count(prefix).max(1))
            }))
    }
    /// Final pool-pressure fallback drops only the immutable prefix. Procedure
    /// identities, facts and prepared inputs survive its later reconstruction.
    pub(crate) fn release_skeleton(&mut self) -> usize {
        let before = self.resident_bytes();
        self.skeleton = None;
        before.saturating_sub(self.resident_bytes())
    }
    pub(crate) fn bind_project(&mut self, project: &Path, cache_root: &Path) {
        let identity = std::fs::canonicalize(project).unwrap_or_else(|_| project.to_owned());
        if self.project.as_ref() == Some(&identity) {
            return;
        }
        self.graph = crate::ProjectProcedureGraph::open(cache_root, &identity.to_string_lossy());
        self.maps =
            crate::maps::MapInitializerSession::open(cache_root, &identity.to_string_lossy());
        self.skeleton = None;
        self.project = Some(identity);
        self.configuration = None;
    }
    pub(super) fn skeleton(
        &mut self,
        key: &str,
        root: Option<&Path>,
    ) -> Option<Arc<FrozenSkeleton>> {
        if let Some((stored, skeleton)) = &self.skeleton {
            if stored == key {
                self.skeleton_hits += 1;
                return Some(Arc::clone(skeleton));
            }
        }
        if let Some(value) = shared_skeletons()
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .get(key)
        {
            self.skeleton = Some((key.to_owned(), Arc::clone(&value)));
            self.skeleton_revision = key.to_owned();
            self.skeleton_hits += 1;
            return Some(value);
        }
        let store = Store::open(root?.join("skeleton.redb")).ok()?;
        let record = store
            .read_many(&[Key::new("frozen-skeleton-v1", key)], None)
            .ok()?;
        let value = FrozenSkeleton::decode(record.values.first()?.as_deref()?)?;
        let value = shared_skeletons()
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .intern(key.to_owned(), value);
        self.skeleton = Some((key.to_owned(), Arc::clone(&value)));
        self.skeleton_revision = key.to_owned();
        self.skeleton_hits += 1;
        Some(value)
    }

    pub(super) fn store(
        &mut self,
        key: String,
        value: FrozenSkeleton,
        root: Option<&Path>,
    ) -> Arc<FrozenSkeleton> {
        if let (Some(root), Some(bytes)) = (root, value.encode()) {
            if let Ok(store) = Store::open(root.join("skeleton.redb")) {
                let _ = store.commit(
                    &[],
                    &[Change::Put(Key::new("frozen-skeleton-v1", &key), bytes)],
                    None,
                );
            }
        }
        let value = shared_skeletons()
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .intern(key.clone(), value);
        self.skeleton_revision = key.clone();
        self.skeleton = Some((key, Arc::clone(&value)));
        self.skeleton_misses += 1;
        value
    }
}

pub(super) fn skeleton_key(
    ast: &dm_syntax::AstFile,
    modified: &ModifiedTypes,
    builtins: &[u8],
    world: &str,
    resource_ids: &HashMap<String, u32>,
    debug: bool,
) -> String {
    fn items(hash: &mut Sha256, nodes: &[Item]) {
        hash.update((nodes.len() as u64).to_le_bytes());
        for node in nodes {
            hash.update([node.kind as u8]);
            hash.update((node.header.len() as u64).to_le_bytes());
            hash.update(node.header.as_bytes());
            items(hash, &node.children);
        }
    }
    let mut hash = Sha256::new();
    hash.update(b"canonical-skeleton-v3\0");
    hash.update(env!("DM_EMISSION_FINGERPRINT").as_bytes());
    hash.update(Sha256::digest(builtins));
    hash.update(world.as_bytes());
    hash.update([u8::from(debug)]);
    items(&mut hash, &ast.items);
    items(&mut hash, &modified.declarations);
    // Declaration defaults contain physical resource slots, not payload IDs.
    // A content edit can reuse the skeleton while replacing its archive refs;
    // changes to ordering/deduplication still invalidate the allocation plan.
    let mut resources: Vec<_> = resource_ids.iter().collect();
    resources.sort_by(|a, b| a.0.cmp(b.0));
    for (name, slot) in resources {
        hash.update((name.len() as u64).to_le_bytes());
        hash.update(name.as_bytes());
        hash.update(slot.to_le_bytes());
    }
    format!("{:x}", hash.finalize())
}

#[cfg(test)]
mod tests {
    use super::*;
    const BUILTINS: &[u8] = include_bytes!("../../../fixtures/native_template.bin");

    fn image(
        source: &str,
        frontend: &mut crate::frontend::OutlineSession,
        cache: &mut crate::lower_cache::ProcLoweringCache,
        catalog: Option<&dm_resources::ResourceCatalog>,
    ) -> Vec<u8> {
        let project = PreprocessedProject {
            text: source.to_owned(),
            origins: source
                .lines()
                .enumerate()
                .map(|(line, _)| dm_preprocess::Origin {
                    output_line: line + 1,
                    source_line: line + 1,
                    path: std::path::PathBuf::from("probe.dm").into(),
                })
                .collect(),
            ..Default::default()
        };
        let debug = crate::source_debug::SourceDebugIndex::new(&project, Path::new("."));
        let (dmb, _, _) = emit_global_procs_mode_with_frontend_catalog(
            source,
            BUILTINS,
            "canonical-probe",
            None,
            cache,
            None,
            None,
            2,
            Some(frontend),
            catalog,
            Some(&debug),
            None,
        )
        .unwrap();
        dmb.to_bytes().unwrap()
    }

    #[test]
    fn canonical_edit_history_matches_fresh_for_body_and_structural_changes() {
        let original = "var/global/base = 1\n/datum/probe\n    var/field = 2\n    var/static/shared = 3\n/datum/probe/proc/read()\n    var/static/local = 4\n    return field + shared + local + base\n/proc/other()\n    return 9\n";
        let edited_body = original.replace(
            "return field +",
            "var/temporary = 7\n    return temporary + field +",
        );
        let structural =
            format!("var/global/added = 5\n{edited_body}/proc/added()\n    return added\n");
        let changed_default = structural.replace("var/field = 2", "var/field = 8");
        let mut frontend = crate::frontend::OutlineSession::new(None);
        let mut cache = crate::lower_cache::ProcLoweringCache::disabled();
        for source in [
            original,
            &edited_body,
            &structural,
            &changed_default,
            original,
        ] {
            let incremental = image(source, &mut frontend, &mut cache, None);
            let fresh = image(
                source,
                &mut crate::frontend::OutlineSession::new(None),
                &mut crate::lower_cache::ProcLoweringCache::disabled(),
                None,
            );
            assert_eq!(
                incremental, fresh,
                "incremental generation differs for {source}"
            );
        }
        assert!(frontend.canonical.graph.stats().resident_hits > 0);
        assert!(frontend.canonical.skeleton_hits > 0);
    }

    #[test]
    fn canonical_cold_restore_and_asset_content_edit_reuse_declarations() {
        let root = std::env::temp_dir().join(format!(
            "dm-canonical-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        std::fs::create_dir_all(&root).unwrap();
        let source = "/obj/probe\n    icon = 'probe.dmi'\n/proc/read()\n    return 'probe.dmi'\n";
        let mut catalog = dm_resources::ResourceCatalog {
            fingerprint: [1; 32],
            entries: vec![dm_resources::ResourceDescriptor {
                archive_name: "probe.dmi".into(),
                id: 7,
                kind: 2,
                content_digest: [1; 32],
            }],
        };
        let first;
        {
            let mut frontend = crate::frontend::OutlineSession::new(Some(root.clone()));
            frontend.canonical.graph = crate::ProjectProcedureGraph::open(&root, "cold-probe");
            let mut cache = crate::lower_cache::ProcLoweringCache::open(root.clone());
            first = image(source, &mut frontend, &mut cache, Some(&catalog));
            frontend.canonical.graph.flush().unwrap();
        }
        {
            let mut frontend = crate::frontend::OutlineSession::new(Some(root.clone()));
            frontend.canonical.graph = crate::ProjectProcedureGraph::open(&root, "cold-probe");
            let mut cache = crate::lower_cache::ProcLoweringCache::open(root.clone());
            assert_eq!(
                first,
                image(source, &mut frontend, &mut cache, Some(&catalog))
            );
            assert_eq!(frontend.canonical.skeleton_hits, 1);
            assert!(frontend.canonical.graph.stats().disk_hits > 0);
            let misses = frontend.canonical.skeleton_misses;
            // Aggregate pool pressure can leave only semantic candidates and
            // disk handles. The production path must refill code and preserve
            // canonical output when resource content changes afterward.
            frontend.canonical.graph.release_encoded_snapshot();
            frontend.canonical.graph.trim_decoded_to(0);
            catalog.fingerprint = [2; 32];
            catalog.entries[0].id = 8;
            catalog.entries[0].content_digest = [2; 32];
            let edited = image(source, &mut frontend, &mut cache, Some(&catalog));
            let fresh = image(
                source,
                &mut crate::frontend::OutlineSession::new(None),
                &mut crate::lower_cache::ProcLoweringCache::disabled(),
                Some(&catalog),
            );
            assert_eq!(edited, fresh);
            assert_ne!(first, edited);
            assert_eq!(frontend.canonical.skeleton_misses, misses);
        }
        std::fs::remove_dir_all(root).unwrap();
    }
}
