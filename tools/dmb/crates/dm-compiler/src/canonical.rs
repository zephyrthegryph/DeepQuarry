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
    pub bindings: Arc<InvocationOverlay>,
    /// Source-independent invocation semantics, hashed once with the prefix.
    pub frame_digest: String,
}

/// Retained frames contain only authored invocation overlays. Parameter semantics
/// already live in `params`; empty lowering maps are created only on cache misses.
#[derive(Clone, Default, PartialEq, Serialize, Deserialize)]
pub(super) struct InvocationOverlay {
    #[serde(skip_serializing_if = "Option::is_none")]
    current_type_path: Option<String>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    fields: Vec<String>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    globals: Vec<String>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    field_types: Vec<(String, String)>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    global_types: Vec<(String, String)>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    global_procs: Vec<String>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    hidden_owner_fields: Vec<String>,
}
impl From<LowerBindings> for InvocationOverlay {
    fn from(frame: LowerBindings) -> Self {
        let mut field_types: Vec<_> = frame.field_types.into_iter().collect();
        let mut global_types: Vec<_> = frame.global_types.into_iter().collect();
        field_types.sort();
        global_types.sort();
        Self {
            current_type_path: frame.current_type_path,
            fields: frame.fields.into_iter().collect(),
            globals: frame.globals.into_iter().collect(),
            field_types,
            global_types,
            global_procs: frame.global_procs.into_iter().collect(),
            hidden_owner_fields: frame.hidden_owner_fields.into_iter().collect(),
        }
    }
}
impl InvocationPlan {
    pub(super) fn lower_bindings(&self) -> LowerBindings {
        LowerBindings {
            current_proc_path: Some(self.path.clone()),
            current_type_path: self.bindings.current_type_path.clone(),
            parameters: self.params.iter().map(|p| p.name.clone()).collect(),
            parameter_type_flags: self.params.iter().map(|p| p.type_flags).collect(),
            parameter_value_sources: self.params.iter().map(|p| p.value_source).collect(),
            parameter_defaults: self.params.iter().map(|p| p.default.clone()).collect(),
            parameter_types: self
                .params
                .iter()
                .filter_map(|p| p.type_path.as_ref().map(|ty| (p.name.clone(), ty.clone())))
                .collect(),
            fields: self.bindings.fields.iter().cloned().collect(),
            globals: self.bindings.globals.iter().cloned().collect(),
            field_types: self.bindings.field_types.iter().cloned().collect(),
            global_types: self.bindings.global_types.iter().cloned().collect(),
            global_procs: self.bindings.global_procs.iter().cloned().collect(),
            hidden_owner_fields: self.bindings.hidden_owner_fields.iter().cloned().collect(),
            ..LowerBindings::default()
        }
    }
}

#[derive(Clone, Serialize, Deserialize)]
pub(super) struct InvocationSyntax {
    pub path: String,
    pub params: Vec<ParsedParameter>,
    pub metadata: ProcMetadata,
    pub statics: Vec<String>,
    #[serde(default)]
    pub frame: Option<(Arc<InvocationOverlay>, String)>,
    pub key: String,
}

/// Content-addressed declaration fragments survive whole-prefix allocation
/// replay. A new declaration changes only its own signature/settings/static
/// syntax; inherited metadata is an explicit fragment input.
#[derive(Default)]
pub(super) struct InvocationFragments {
    entries: BTreeMap<String, Arc<InvocationSyntax>>,
    signatures: BTreeMap<String, Arc<(String, Vec<ParsedParameter>)>>,
    pending: BTreeMap<String, Vec<u8>>,
    store: Option<Store>,
    bytes: usize,
}
impl InvocationFragments {
    const LIMIT: usize = 32 * 1024 * 1024;
    fn open(root: &Path) -> Self {
        let mut cache = Self::default();
        cache.store = Store::open(root.join("declaration-fragments.redb")).ok();
        // One bounded startup transaction; misses compile the small fragment
        // rather than opening a redb read for every procedure during a rebuild.
        let snapshot = cache.store.as_ref().and_then(|store| {
            store
                .snapshot_namespace(&Self::namespace(), 128_000, Self::LIMIT / 2, None)
                .ok()
        });
        if let Some(snapshot) = snapshot {
            for (key, bytes) in snapshot.records {
                if let Ok(value) = serde_json::from_slice::<InvocationSyntax>(&bytes) {
                    cache.retain(key.name, Arc::new(value), bytes.len());
                }
            }
        }
        cache
    }
    fn namespace() -> String {
        format!("invocation-syntax-v1-{}", env!("DM_EMISSION_FINGERPRINT"))
    }
    pub(super) fn signature(
        &mut self,
        item: &Item,
        owner: &str,
        verb: bool,
    ) -> Result<(String, Vec<ParsedParameter>), String> {
        let key = crate::lower_cache::shared_binding_fingerprint(&(owner, verb, &item.header));
        if let Some(value) = self.signatures.get(&key) {
            return Ok(value.as_ref().clone());
        }
        let value = member_signature(item, owner, verb)?;
        let size = key.len()
            + value.0.len()
            + value
                .1
                .iter()
                .map(|p| {
                    std::mem::size_of::<ParsedParameter>()
                        + p.name.len()
                        + p.type_path.as_ref().map_or(0, String::len)
                        + p.source_expression.as_ref().map_or(0, String::len)
                        + p.default.as_ref().map_or(0, String::len)
                })
                .sum::<usize>()
            + 128;
        if self.bytes + size <= Self::LIMIT {
            self.bytes += size;
            self.signatures.insert(key, Arc::new(value.clone()));
        }
        Ok(value)
    }
    pub(super) fn syntax(
        &mut self,
        item: &Item,
        path: &str,
        params: &[ParsedParameter],
        base: ProcMetadata,
    ) -> Result<Arc<InvocationSyntax>, String> {
        fn hash_items(hash: &mut Sha256, items: &[Item]) {
            hash.update((items.len() as u64).to_le_bytes());
            for item in items {
                hash.update([item.kind as u8]);
                hash.update((item.header.len() as u64).to_le_bytes());
                hash.update(item.header.as_bytes());
                hash_items(hash, &item.children);
            }
        }
        let mut hash = Sha256::new();
        hash.update(path.as_bytes());
        hash.update(item.header.as_bytes());
        hash_items(&mut hash, &item.children);
        hash.update(serde_json::to_vec(&base).map_err(|e| e.to_string())?);
        let key = format!("{:x}", hash.finalize());
        if let Some(value) = self.entries.get(&key) {
            return Ok(Arc::clone(value));
        }
        let (metadata, mut body) = proc_metadata_from_base(&item.children, base)?;
        let mut statics = Vec::new();
        extract_static_declarations(&mut body, &mut statics);
        let value = Arc::new(InvocationSyntax {
            path: path.to_owned(),
            params: params.to_vec(),
            metadata,
            statics,
            frame: None,
            key: key.clone(),
        });
        if let Ok(bytes) = serde_json::to_vec(value.as_ref()) {
            let size = bytes.len();
            if size <= 1024 * 1024 && self.bytes + size * 2 + key.len() + 128 <= Self::LIMIT {
                self.pending.insert(key.clone(), bytes);
                self.retain(key, Arc::clone(&value), size);
                if self.pending.values().map(Vec::len).sum::<usize>() > 4 * 1024 * 1024 {
                    self.flush();
                }
            }
        }
        Ok(value)
    }
    pub(super) fn frame(
        &mut self,
        syntax: &Arc<InvocationSyntax>,
        overlay: InvocationOverlay,
    ) -> (Arc<InvocationOverlay>, String) {
        if let Some((cached, digest)) = &syntax.frame {
            if cached.as_ref() == &overlay {
                return (Arc::clone(cached), digest.clone());
            }
        }
        let overlay = Arc::new(overlay);
        let plan = InvocationPlan {
            path: syntax.path.clone(),
            params: syntax.params.clone(),
            metadata: syntax.metadata.clone(),
            static_ids: HashMap::new(),
            bindings: Arc::clone(&overlay),
            frame_digest: String::new(),
        };
        let digest = crate::lower_cache::shared_binding_fingerprint(&plan.lower_bindings());
        if self.entries.contains_key(&syntax.key) {
            let mut updated = syntax.as_ref().clone();
            updated.frame = Some((Arc::clone(&overlay), digest.clone()));
            if let Ok(bytes) = serde_json::to_vec(&updated) {
                let extra = bytes
                    .len()
                    .saturating_sub(
                        serde_json::to_vec(syntax.as_ref()).map_or(bytes.len(), |old| old.len()),
                    )
                    .saturating_mul(2);
                if self.bytes.saturating_add(extra) <= Self::LIMIT {
                    self.bytes += extra;
                    self.entries.insert(syntax.key.clone(), Arc::new(updated));
                    self.pending.insert(syntax.key.clone(), bytes);
                    if self.pending.values().map(Vec::len).sum::<usize>() > 4 * 1024 * 1024 {
                        self.flush();
                    }
                }
            }
        }
        (overlay, digest)
    }
    fn retain(&mut self, key: String, value: Arc<InvocationSyntax>, wire_bytes: usize) {
        let size = wire_bytes.saturating_mul(2) + key.len() + 128;
        if self.bytes.saturating_add(size) <= Self::LIMIT {
            self.bytes += size;
            self.entries.insert(key, value);
        }
    }
    fn flush(&mut self) {
        let Some(store) = &self.store else {
            self.pending.clear();
            return;
        };
        let updates: Vec<_> = self
            .pending
            .iter()
            .map(|(key, bytes)| Change::Put(Key::new(Self::namespace(), key), bytes.clone()))
            .collect();
        if store.commit(&[], &updates, None).is_ok() {
            self.pending.clear();
        }
    }
    fn resident_bytes(&self) -> usize {
        self.bytes
            + self
                .pending
                .iter()
                .map(|(key, bytes)| key.capacity() + bytes.capacity() + 128)
                .sum::<usize>()
    }
}

#[derive(Default)]
pub(super) struct OwnerFrameQueries {
    snapshot_revision: String,
    current: HashMap<u32, (String, Arc<dm_codegen_byond::OwnerLowerBindings>)>,
    current_bytes: usize,
    records: BTreeMap<String, (String, Arc<dm_codegen_byond::OwnerLowerBindings>, usize)>,
    bytes: usize,
    store: Option<Store>,
    pending: BTreeMap<String, Vec<u8>>,
}
#[derive(Serialize, Deserialize)]
struct OwnerFrameWire {
    path: String,
    identity: String,
    frame: Arc<dm_codegen_byond::OwnerLowerBindings>,
}
impl OwnerFrameQueries {
    const LIMIT: usize = 16 * 1024 * 1024;
    fn namespace() -> String {
        format!("owner-frames-v1-{}", env!("DM_EMISSION_FINGERPRINT"))
    }
    fn charge(path: &str, identity: &str, frame: &dm_codegen_byond::OwnerLowerBindings) -> usize {
        path.len()
            + identity.len()
            + 128
            + frame
                .fields
                .iter()
                .map(|name| name.len() + 64)
                .sum::<usize>()
            + frame
                .field_types
                .iter()
                .map(|(name, ty)| name.len() + ty.len() + 96)
                .sum::<usize>()
    }
    fn open(root: &Path) -> Self {
        let mut queries = Self::default();
        queries.store = Store::open(root.join("declaration-fragments.redb")).ok();
        let snapshot = queries.store.as_ref().and_then(|store| {
            store
                .snapshot_namespace(&Self::namespace(), 128_000, Self::LIMIT / 2, None)
                .ok()
        });
        if let Some(snapshot) = snapshot {
            for (_, bytes) in snapshot.records {
                if let Ok(wire) = serde_json::from_slice::<OwnerFrameWire>(&bytes) {
                    let charge = Self::charge(&wire.path, &wire.identity, &wire.frame);
                    if queries.bytes.saturating_add(charge) <= Self::LIMIT {
                        if let Some((_, _, old)) = queries.records.remove(&wire.path) {
                            queries.bytes = queries.bytes.saturating_sub(old);
                        }
                        queries.bytes += charge;
                        queries
                            .records
                            .insert(wire.path, (wire.identity, wire.frame, charge));
                    }
                }
            }
        }
        queries
    }
    fn flush(&mut self) {
        let Some(store) = &self.store else {
            self.pending.clear();
            return;
        };
        let changes: Vec<_> = self
            .pending
            .iter()
            .map(|(key, bytes)| Change::Put(Key::new(Self::namespace(), key), bytes.clone()))
            .collect();
        if store.commit(&[], &changes, None).is_ok() {
            self.pending.clear();
        }
    }
    fn resident_bytes(&self) -> usize {
        self.bytes
            + self.current_bytes
            + self
                .pending
                .iter()
                .map(|(key, bytes)| key.capacity() + bytes.capacity() + 128)
                .sum::<usize>()
    }
    pub(super) fn bind_revision(&mut self, revision: &str) {
        if self.snapshot_revision != revision {
            self.snapshot_revision = revision.to_owned();
            self.current.clear();
            self.current_bytes = 0;
        }
    }
    fn retain_current(
        &mut self,
        owner: u32,
        identity: &str,
        frame: &Arc<dm_codegen_byond::OwnerLowerBindings>,
    ) {
        let charge = Self::charge("", identity, frame);
        if self.current_bytes.saturating_add(charge) <= 4 * 1024 * 1024
            && !self.current.contains_key(&owner)
        {
            self.current_bytes += charge;
            self.current
                .insert(owner, (identity.to_owned(), Arc::clone(frame)));
        }
    }
    /// A frame depends only on its local field inventory/type annotations and
    /// its parent's resolved frame. Values/defaults and physical table IDs are
    /// deliberately excluded, so unrelated structural edits preserve the query.
    pub(super) fn resolve(
        &mut self,
        owner: u32,
        dmb: &Dmb,
        shared: &SharedLowerBindings,
    ) -> Arc<dm_codegen_byond::OwnerLowerBindings> {
        self.resolve_inner(owner, dmb, shared, &mut HashSet::new())
            .1
    }
    fn resolve_inner(
        &mut self,
        owner: u32,
        dmb: &Dmb,
        shared: &SharedLowerBindings,
        visited: &mut HashSet<u32>,
    ) -> (String, Arc<dm_codegen_byond::OwnerLowerBindings>) {
        if let Some(value) = self.current.get(&owner) {
            return value.clone();
        }
        if !visited.insert(owner) {
            return (String::new(), Arc::new(Default::default()));
        }
        let class = &dmb.classes[owner as usize];
        let path = String::from_utf8_lossy(dmb.string(class.path_string_id()).unwrap_or_default())
            .into_owned();
        let parent = class.parent_class_id();
        let inherited = if parent != 0xffff {
            Some(self.resolve_inner(parent, dmb, shared, visited))
        } else {
            None
        };
        let mut local = LowerBindings::default();
        seed_builtin_fields(&path, &mut local);
        if let Some(types) = shared.member_types.get(&path) {
            for (name, ty) in types {
                local
                    .field_types
                    .entry(name.clone())
                    .or_insert_with(|| ty.clone());
            }
        }
        if let Some(declarations) = dmb.class_variable_declarations(owner as usize) {
            for (id, _) in declarations {
                if let Some(name) = dmb.string(dmb.variables[id as usize].name) {
                    local
                        .fields
                        .insert(String::from_utf8_lossy(name).into_owned());
                }
            }
        }
        let mut ordered_types: Vec<_> = local.field_types.iter().collect();
        ordered_types.sort_by(|a, b| a.0.cmp(b.0));
        let identity = crate::lower_cache::shared_binding_fingerprint(&(
            &path,
            &local.fields,
            &ordered_types,
            inherited.as_ref().map(|(digest, _)| digest),
        ));
        if let Some((stored, frame, _)) = self.records.get(&path) {
            if stored == &identity {
                let frame = Arc::clone(frame);
                self.retain_current(owner, &identity, &frame);
                visited.remove(&owner);
                return (identity, frame);
            }
        }
        if let Some((_, frame)) = inherited {
            local.fields.extend(frame.fields.iter().cloned());
            for (name, ty) in &frame.field_types {
                local
                    .field_types
                    .entry(name.clone())
                    .or_insert_with(|| ty.clone());
            }
        }
        let frame = Arc::new(dm_codegen_byond::OwnerLowerBindings {
            fields: local.fields,
            field_types: local.field_types,
        });
        let charge = Self::charge(&path, &identity, &frame);
        if let Some((_, _, old)) = self.records.remove(&path) {
            self.bytes = self.bytes.saturating_sub(old);
        }
        if charge <= Self::LIMIT {
            while self.bytes.saturating_add(charge) > Self::LIMIT {
                let Some(key) = self.records.keys().next().cloned() else {
                    break;
                };
                if let Some((_, _, old)) = self.records.remove(&key) {
                    self.bytes = self.bytes.saturating_sub(old);
                }
            }
            if let Ok(bytes) = serde_json::to_vec(&OwnerFrameWire {
                path: path.clone(),
                identity: identity.clone(),
                frame: Arc::clone(&frame),
            }) {
                if bytes.len() <= Self::LIMIT / 4 {
                    self.pending.insert(identity.clone(), bytes);
                }
                if self.pending.values().map(Vec::len).sum::<usize>() > 4 * 1024 * 1024 {
                    self.flush();
                }
            }
            self.bytes += charge;
            self.records
                .insert(path, (identity.clone(), Arc::clone(&frame), charge));
        }
        self.retain_current(owner, &identity, &frame);
        visited.remove(&owner);
        (identity, frame)
    }
}

pub(super) struct FrozenSkeleton {
    pub image: Dmb,
    pub metadata: SkeletonMetadata,
    resident_charge: AtomicUsize,
}

impl FrozenSkeleton {
    pub(super) fn new(image: Dmb, metadata: SkeletonMetadata) -> Self {
        let charge = skeleton_heap(&image, &metadata);
        Self {
            image,
            metadata,
            resident_charge: AtomicUsize::new(charge),
        }
    }
    fn encode(&self) -> Option<Vec<u8>> {
        // One serialization buffer: the prefix can be large, and two temporary
        // JSON buffers followed by concatenation unnecessarily duplicate it.
        let mut bytes = b"DMSKEL03".to_vec();
        bytes.extend_from_slice(&0_u64.to_le_bytes());
        serde_json::to_writer(&mut bytes, &self.image).ok()?;
        let image_size = bytes.len().checked_sub(16)?;
        bytes[8..16].copy_from_slice(&(image_size as u64).to_le_bytes());
        serde_json::to_writer(&mut bytes, &self.metadata).ok()?;
        let decoded_size = bytes.len();
        if std::env::var_os("DM_BUILD_TRACE").is_some() {
            eprintln!("DM_BUILD_TRACE declaration skeleton: image {} bytes, metadata {} bytes, retained charge {} bytes, persistence cap {} bytes", image_size, decoded_size - image_size - 16, self.resident_charge.load(Ordering::Relaxed), MAX_SKELETON);
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
        if decoded.len() < 16 || &decoded[..8] != b"DMSKEL03" {
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
        Some(Self::new(image, metadata))
    }
}

/// Estimate owned heap allocations from decoded structures. JSON duplicates
/// parameter names and decimal encodings; using twice its size caused the pool
/// to evict an otherwise retainable prefix on every edited request.
fn skeleton_heap(image: &Dmb, metadata: &SkeletonMetadata) -> usize {
    fn vec_heap<T>(items: &Vec<T>) -> usize {
        items.capacity().saturating_mul(std::mem::size_of::<T>())
    }
    fn map_heap<K, V>(items: &HashMap<K, V>) -> usize {
        items
            .capacity()
            .saturating_mul(std::mem::size_of::<(K, V)>() + 16)
    }
    fn strings(items: &Vec<String>) -> usize {
        vec_heap(items) + items.iter().map(String::capacity).sum::<usize>()
    }
    fn pairs(items: &Vec<(String, String)>) -> usize {
        vec_heap(items)
            + items
                .iter()
                .map(|(a, b)| a.capacity() + b.capacity())
                .sum::<usize>()
    }
    fn text_map(items: &HashMap<String, String>) -> usize {
        map_heap(items)
            + items
                .iter()
                .map(|(a, b)| a.capacity() + b.capacity())
                .sum::<usize>()
    }
    fn id_map(items: &HashMap<String, u32>) -> usize {
        map_heap(items) + items.keys().map(String::capacity).sum::<usize>()
    }
    fn text_set(items: &BTreeSet<String>) -> usize {
        items
            .iter()
            .map(|s| s.capacity() + std::mem::size_of::<String>() + 32)
            .sum()
    }
    fn nested_map(items: &HashMap<String, HashMap<String, String>>) -> usize {
        map_heap(items)
            + items
                .iter()
                .map(|(name, members)| name.capacity() + text_map(members))
                .sum::<usize>()
    }
    fn nested_set(items: &HashMap<String, BTreeSet<String>>) -> usize {
        map_heap(items)
            + items
                .iter()
                .map(|(name, members)| name.capacity() + text_set(members))
                .sum::<usize>()
    }
    let mut bytes = std::mem::size_of::<FrozenSkeleton>()
        + vec_heap(&image.grid)
        + vec_heap(&image.classes)
        + vec_heap(&image.mobs)
        + vec_heap(&image.strings)
        + vec_heap(&image.lists)
        + vec_heap(&image.procs)
        + vec_heap(&image.variables)
        + vec_heap(&image.proc_references)
        + vec_heap(&image.instances)
        + vec_heap(&image.map_objects)
        + vec_heap(&image.resources)
        + image.header.version_line.capacity()
        + image.header.compatibility_line.capacity()
        + image.header.executor_line.as_ref().map_or(0, Vec::capacity);
    bytes += image
        .strings
        .iter()
        .map(|s| s.data.capacity())
        .sum::<usize>();
    bytes += image.lists.iter().map(vec_heap).sum::<usize>();
    bytes +=
        map_heap(&metadata.strings.0) + metadata.strings.0.keys().map(Vec::capacity).sum::<usize>();
    for map in [
        &metadata.strings.1,
        &metadata.strings.2,
        &metadata.strings.3,
        &metadata.strings.4,
    ] {
        bytes += id_map(map);
    }
    bytes += metadata.proc_paths.capacity() * (std::mem::size_of::<Vec<u8>>() + 16)
        + metadata.proc_paths.iter().map(Vec::capacity).sum::<usize>();
    bytes += id_map(&metadata.class_paths)
        + id_map(&metadata.initializer_globals)
        + id_map(&metadata.global_proc_ids);
    bytes += vec_heap(&metadata.pending)
        + metadata
            .pending
            .iter()
            .map(|p| p.owner_path.capacity())
            .sum::<usize>();
    bytes += vec_heap(&metadata.dynamic)
        + metadata
            .dynamic
            .iter()
            .map(|p| p.name.capacity() + p.expression.capacity())
            .sum::<usize>();
    bytes += vec_heap(&metadata.invocations);
    for plan in &metadata.invocations {
        bytes += plan.path.capacity()
            + plan.frame_digest.capacity()
            + vec_heap(&plan.params)
            + id_map(&plan.static_ids);
        for param in &plan.params {
            bytes += param.name.capacity()
                + param.type_path.as_ref().map_or(0, String::capacity)
                + param.source_expression.as_ref().map_or(0, String::capacity)
                + param.default.as_ref().map_or(0, String::capacity);
        }
        for value in [
            &plan.metadata.name,
            &plan.metadata.description,
            &plan.metadata.category,
        ] {
            bytes += value.as_ref().map_or(0, Vec::capacity);
        }
        let overlay = &plan.bindings;
        bytes += overlay
            .current_type_path
            .as_ref()
            .map_or(0, String::capacity)
            + strings(&overlay.fields)
            + strings(&overlay.globals)
            + strings(&overlay.global_procs)
            + strings(&overlay.hidden_owner_fields)
            + pairs(&overlay.field_types)
            + pairs(&overlay.global_types);
    }
    let shared = &metadata.shared;
    bytes += std::mem::size_of::<SharedLowerBindings>();
    for map in [
        &shared.member_types,
        &shared.member_globals,
        &shared.member_procs,
        &shared.member_proc_return_types,
    ] {
        bytes += nested_map(map);
    }
    for set in [&shared.known_member_fields, &shared.known_member_procs] {
        bytes += nested_set(set);
    }
    for map in [
        &shared.modified_instances,
        &shared.member_type_fingerprints,
        &shared.global_proc_return_types,
        &shared.parent_types,
        &shared.field_types,
        &shared.global_types,
        &shared.string_constants,
    ] {
        bytes += text_map(map);
    }
    for set in [&shared.fields, &shared.globals, &shared.global_procs] {
        bytes += text_set(set);
    }
    bytes += id_map(&shared.numeric_constants) + shared.fingerprint.capacity();
    bytes
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
    pub output_validation: byond_dmb::dmb::ReferenceValidationCache,
    pub output_projections: Arc<dm_codegen_byond::relocatable::OutputProjectionCache>,
    pub(super) invocation_fragments: InvocationFragments,
    pub(super) owner_frames: Arc<Mutex<OwnerFrameQueries>>,
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
        self.output_validation = Default::default();
        self.output_projections =
            Arc::new(dm_codegen_byond::relocatable::OutputProjectionCache::open(
                &root,
                env!("DM_EMISSION_FINGERPRINT"),
            ));
        self.invocation_fragments = InvocationFragments::open(&root);
        self.owner_frames = Arc::new(Mutex::new(OwnerFrameQueries::open(&root)));
        const_eval::bind_cache(&root);
        default_plans::bind_cache(&root);
        self.project = Some(identity);
        self.configuration = Some(configuration.to_owned());
    }

    pub(crate) fn resident_bytes(&self) -> usize {
        // Prefixes with equal content identities share one immutable allocation
        // across sessions. Divide its conservative charge among live Arc owners.
        self.graph
            .resident_bytes()
            .saturating_add(self.maps.resident_bytes())
            .saturating_add(self.output_validation.resident_bytes())
            .saturating_add(self.output_projections.resident_bytes())
            .saturating_add(self.invocation_fragments.resident_bytes())
            .saturating_add(
                self.owner_frames
                    .lock()
                    .unwrap_or_else(|e| e.into_inner())
                    .resident_bytes(),
            )
            .saturating_add(self.skeleton.as_ref().map_or(0, |(_, prefix)| {
                prefix
                    .resident_charge
                    .load(Ordering::Relaxed)
                    .div_ceil(Arc::strong_count(prefix).max(1))
            }))
    }
    pub(crate) fn flush_derived(&mut self) {
        self.invocation_fragments.flush();
        self.owner_frames
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .flush();
        const_eval::flush_cache();
        default_plans::flush_cache();
    }
    /// Output projections are expendable accelerators. Retain compact semantic
    /// owner/invocation fragments when releasing output buffers under pressure.
    pub(crate) fn release_auxiliary_caches(&mut self) -> usize {
        let before = self.resident_bytes();
        let _ = self.output_projections.flush();
        self.output_projections.clear();
        self.output_validation.clear();
        before.saturating_sub(self.resident_bytes())
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
        self.output_validation = Default::default();
        self.output_projections =
            Arc::new(dm_codegen_byond::relocatable::OutputProjectionCache::open(
                cache_root,
                env!("DM_EMISSION_FINGERPRINT"),
            ));
        self.invocation_fragments = InvocationFragments::open(cache_root);
        self.owner_frames = Arc::new(Mutex::new(OwnerFrameQueries::open(cache_root)));
        const_eval::bind_cache(cache_root);
        default_plans::bind_cache(cache_root);
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
            .read_many(&[Key::new("frozen-skeleton-v2", key)], None)
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
        self.invocation_fragments.flush();
        self.owner_frames
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .flush();
        const_eval::flush_cache();
        default_plans::flush_cache();
        if let (Some(root), Some(bytes)) = (root, value.encode()) {
            if let Ok(store) = Store::open(root.join("skeleton.redb")) {
                let _ = store.commit(
                    &[],
                    &[Change::Put(Key::new("frozen-skeleton-v2", &key), bytes)],
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
