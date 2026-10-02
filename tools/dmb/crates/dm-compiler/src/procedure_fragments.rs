//! Disk-backed authored output DAG. Compact handles are independent of decoded
//! procedure bodies; source-order batches fetch only the flat output fragments
//! needed by the current generation. Semantic candidate identities gate reuse.
use std::collections::{HashMap, HashSet, VecDeque};
use std::sync::Arc;
use serde::{Serialize, Deserialize};
use byond_dmb::dmb::{Proc, Variable};
use dm_codegen_byond::relocatable::{OutputRelocation, OutputDebugRelocation};
use sha2::{Digest, Sha256};
const OBJECT_WINDOW: usize = 1024;

#[derive(Clone, Serialize, Deserialize)]
pub(super) enum StringRecipe {
    Bytes { old_id: u32, bytes: Arc<[u8]> },
    Debug { index: usize },
}
#[derive(Clone, Serialize, Deserialize)]
pub(super) struct HelperRecipe {
    pub parameter: usize,
    pub key: crate::ProcKey,
    pub descriptor: crate::ProcDescriptor,
    pub identity: String,
    pub dedup: String,
    pub statics: std::collections::BTreeMap<String, u32>,
}
pub(super) use dm_output::object_directory::{AllocationCounts,AllocationMask,ObjectWitness,WitnessObservation,ProcedureRowLayout,SiteKind};
#[derive(Serialize, Deserialize)]
pub(super) struct OutputFragment {
    pub body_base_relative: usize,
    pub debug_enabled: bool,
    pub unresolved_debug: Vec<usize>,
    pub strings: Vec<StringRecipe>,
    pub variables: Vec<Variable>,
    pub old_variable_base: u32,
    pub locals: Arc<[u32]>,
    pub arguments: Arc<[u32]>,
    pub record: Proc,
    pub relocations: Vec<OutputRelocation>,
    pub debug: Vec<OutputDebugRelocation>,
    pub helpers: Vec<HelperRecipe>,
    #[serde(default)] pub linked: Option<ObjectWitness>,
    #[serde(default)] pub code_digest: Option<String>,
    #[serde(default)] pub code_word_count: Option<u32>,
    #[serde(default)] pub allocated_rows: Option<ProcedureRowLayout>,
    #[serde(skip)]
    pub words: Arc<[u32]>,
}
impl OutputFragment {
    fn encode(&self) -> Option<Vec<u8>> {
        let metadata = rmp_serde::to_vec(self).ok()?;
        let mut result = Vec::with_capacity(12 + metadata.len() + self.words.len() * 4);
        result.extend_from_slice(if self.code_digest.is_some() { b"DMOUTF03" } else { b"DMOUTF02" });
        result.extend_from_slice(&u32::try_from(metadata.len()).ok()?.to_le_bytes());
        result.extend_from_slice(&metadata);
        if self.code_digest.is_none() { for word in self.words.iter() { result.extend_from_slice(&word.to_le_bytes()); } }
        if result.len() > 16 * 1024 * 1024 { return None; }
        let compressed = lz4_flex::compress_prepend_size(&result);
        let mut encoded = Vec::with_capacity(8 + compressed.len());
        encoded.extend_from_slice(b"DMOCMP04");
        encoded.extend_from_slice(&u32::try_from(self.words.len()).ok()?.to_le_bytes());
        encoded.extend_from_slice(&compressed);
        Some(encoded)
    }
    fn decode(encoded: &[u8]) -> Option<Self> {
        let compression_start=match encoded.get(..8)? {
            b"DMOCMP02"|b"DMOCMP03"=>8,
            b"DMOCMP04"=>12,
            _=>return None,
        };
        let declared_words=if compression_start==12 {Some(u32::from_le_bytes(encoded.get(8..12)?.try_into().ok()?))} else {None};
        if declared_words.is_some_and(|words|words>u16::MAX as u32) {return None;}
        let length=u32::from_le_bytes(encoded.get(compression_start..compression_start+4)?.try_into().ok()?) as usize;
        if length > 16 * 1024 * 1024 { return None; }
        let expanded = lz4_flex::decompress_size_prepended(encoded.get(compression_start..)?).ok()?;
        let bytes = expanded.as_slice();
        let version = bytes.get(..8)?;
        if version != b"DMOUTF01" && version != b"DMOUTF02" && version != b"DMOUTF03" { return None; }
        let length = u32::from_le_bytes(bytes.get(8..12)?.try_into().ok()?) as usize;
        let split = 12usize.checked_add(length)?;
        let mut fragment: Self = if version != b"DMOUTF01" {
            rmp_serde::from_slice(bytes.get(12..split)?).ok()?
        } else {
            serde_json::from_slice(bytes.get(12..split)?).ok()?
        };
        let words = bytes.get(split..)?;
        if words.len() % 4 != 0 || words.len() / 4 > u16::MAX as usize { return None; }
        fragment.words = words.chunks_exact(4).map(|word| u32::from_le_bytes(word.try_into().unwrap()))
            .collect::<Vec<_>>().into();
        if version == b"DMOUTF03" {
            if !words.is_empty() || !fragment.code_digest.as_ref().is_some_and(|digest|digest.len()==64)
                || declared_words.is_some_and(|words|fragment.code_word_count!=Some(words)) { return None; }
            return Some(fragment);
        }
        if !fragment.validate() { return None; }
        Some(fragment)
    }
    fn validate(&self) -> bool {
        let fragment=self;
        if fragment.code_word_count.is_some_and(|words|words as usize!=fragment.words.len()) {return false;}
        if fragment.allocated_rows.as_ref().is_some_and(|layout|!layout.valid() || layout.variable_count as usize!=fragment.variables.len()
            || fragment.record.code_locals_args!=[0,1,2]) {return false;}
        let valid_variable = |id: u32| if fragment.allocated_rows.is_some() {(id as usize)<fragment.variables.len()}
            else {id.checked_sub(fragment.old_variable_base).is_some_and(|offset| (offset as usize)<fragment.variables.len())};
        if fragment.locals.len() > u16::MAX as usize || fragment.arguments.len() > u16::MAX as usize
            || fragment.locals.iter().any(|&id| !valid_variable(id))
            || fragment.arguments.chunks_exact(4).any(|argument| !valid_variable(argument[2]))
            || fragment.helpers.iter().any(|helper| helper.parameter >= fragment.arguments.len() / 4)
            || fragment.arguments.len() % 4 != 0
            || fragment.relocations.iter().any(|relocation| relocation.offset as usize >= fragment.words.len()
                || (relocation.packed_tag.is_some() && relocation.offset as usize + 1 >= fragment.words.len()))
            || fragment.strings.iter().any(|recipe| matches!(recipe, StringRecipe::Debug { index } if *index >= fragment.debug.len()))
            || fragment.debug.iter().any(|debug| debug.file_offset as usize >= fragment.words.len()
                || debug.line_offset as usize >= fragment.words.len()) { return false; }
        if let Some(linked)=&fragment.linked {
            if linked.start.variables!=fragment.old_variable_base
                || linked.symbol_ids.len()!=fragment.relocations.len() || linked.debug_ids.len()!=fragment.debug.len()
                || !fragment.helpers.is_empty() { return false; }
            if fragment.relocations.iter().zip(&linked.symbol_ids).any(|(relocation,assigned)| {
                let at=relocation.offset as usize;
                let actual=match relocation.packed_tag { None=>fragment.words[at],Some(_)=>((fragment.words[at]>>8)<<16)|fragment.words[at+1] };
                actual!=*assigned
            }) || fragment.debug.iter().zip(&linked.debug_ids).any(|(mark,(file,line))|
                fragment.words[mark.file_offset as usize]!=*file || fragment.words[mark.line_offset as usize]!=*line) { return false; }
            let mapped_string=|id:u32|id==0xffff || fragment.strings.iter().any(|recipe|
                matches!(recipe,StringRecipe::Bytes{old_id,..} if *old_id==id));
            if fragment.variables.iter().any(|variable|!mapped_string(variable.name))
                || fragment.record.strings.iter().any(|id|!mapped_string(*id)) { return false; }
                        if !linked.valid() || fragment.recipe_identity().as_deref()!=Some(linked.recipe_identity.as_str()) { return false; }
            let mut expected_strings:Vec<_>=fragment.strings.iter().filter_map(|recipe|match recipe {
                StringRecipe::Bytes{old_id,..}=>Some(*old_id),StringRecipe::Debug{..}=>None,
            }).collect(); expected_strings.sort_unstable();
            if linked.string_ids!=expected_strings || linked.unresolved_debug!=fragment.unresolved_debug { return false; }
            let required=if fragment.allocated_rows.is_some() {AllocationMask::NONE} else {
                AllocationMask::VARIABLES.union(AllocationMask::LISTS).union(AllocationMask::PROCEDURES).union(AllocationMask::REFERENCES)};
            if linked.allocation_mask!=required { return false; }
            let mut next=linked.start.lists;
            for actual in fragment.record.code_locals_args.into_iter().filter(|_|fragment.allocated_rows.is_none()) {
                if next==0xffff { next+=1; }
                if actual!=next { return false; }
                let Some(value)=next.checked_add(1) else {return false;}; next=value;
            }
        }
        true
    }
    fn recipe_identity(&self)->Option<String> {
        // The certificate is excluded; all immutable operation recipes and
        // addressed code content contribute. Dense IDs are part of the recipe.
        let bytes=rmp_serde::to_vec(&(self.body_base_relative,self.debug_enabled,&self.unresolved_debug,&self.strings,
            &self.variables,self.old_variable_base,&self.locals,&self.arguments,&self.record,&self.relocations,
            &self.debug,&self.helpers,&self.code_digest,&self.code_word_count,&self.allocated_rows)).ok()?;
        let mut hash=Sha256::new();hash.update(b"procedure-output-recipe-v1");hash.update(bytes);
        Some(format!("{:x}",hash.finalize()))
    }
    fn charge(&self) -> usize {
        self.words.len() * 4 + self.variables.capacity() * std::mem::size_of::<Variable>()
            + (self.locals.len() + self.arguments.len()) * 4
            + self.strings.iter().map(|recipe| match recipe { StringRecipe::Bytes { bytes, .. } => bytes.len() + 64,
                StringRecipe::Debug { .. } => 64 }).sum::<usize>()
            + self.relocations.iter().map(|r| r.symbol.key.capacity() + 96).sum::<usize>()
            + self.debug.capacity() * std::mem::size_of::<OutputDebugRelocation>()
            + self.unresolved_debug.capacity() * std::mem::size_of::<usize>()
            + self.linked.as_ref().map_or(0,|linked|linked.symbol_ids.capacity()*4+linked.string_ids.capacity()*4+linked.debug_ids.capacity()*8
                +linked.semantic_identity.capacity()+linked.recipe_identity.capacity()+linked.unresolved_debug.capacity()*std::mem::size_of::<usize>()+256)
            + self.code_digest.as_ref().map_or(0,|digest|digest.capacity())
            + self.allocated_rows.as_ref().map_or(0,|_|64)
            + self.helpers.iter().map(|h| h.key.path.capacity() + h.identity.capacity() + h.dedup.capacity()
                + h.descriptor.body_digest.capacity() + h.descriptor.frame_digest.capacity()
                + h.statics.keys().map(|key| key.capacity() + 64).sum::<usize>() + 160).sum::<usize>() + 256
    }
}
#[derive(Clone, Serialize, Deserialize)]
struct Handle {
    descriptor: crate::ProcDescriptor,
    candidate: String,
    payload: String,
}
fn handle_charge(key: &crate::ProcKey, handle: &Handle) -> usize {
    key.path.capacity() + handle.descriptor.body_digest.capacity()
        + handle.descriptor.frame_digest.capacity() + handle.candidate.capacity()
        + handle.payload.capacity() + 192
}
#[derive(Default)]
pub(super) struct FragmentStats {
    pub reused: usize,
    pub relocated: usize,
    pub linked_rows_reused: usize,
    pub code_read_bytes: usize,
    pub code_hydration_seconds: f64,
    pub built: usize,
    pub batches: usize,
    pub disk_bytes: usize,
    pub replay_seconds: f64,
    pub read_seconds: f64,
    pub decode_seconds: f64,
    pub encode_seconds: f64,
    pub flush_seconds: f64,
    pub write_batches: usize,
}
struct Resident { fragment: Arc<OutputFragment>, charge: usize, used: u64 }
#[derive(Default)]
pub(super) struct ProcedureFragments {
    handles: HashMap<crate::ProcKey, Handle>,
    known_missing: HashSet<crate::ProcKey>,
    resident: HashMap<String, Resident>,
    recency: VecDeque<(String, u64)>,
    pending: Vec<dm_store::Change>,
    pending_bytes: usize,
    resident_bytes: usize,
    metadata_bytes: usize,
    tick: u64,
    workers: usize,
    store: Option<dm_store::Store>,
    namespace: String,
    blobs: String,
    code_blobs: String,
    pub stats: FragmentStats,
}
impl ProcedureFragments {
    pub fn open(root: &std::path::Path, identity: &str) -> Self {
        let store = dm_store::Store::open(root.join("output-fragments.redb")).ok();
        Self { store, namespace: format!("output-handles-v3-{}-{}", env!("DM_EMISSION_FINGERPRINT"),
            crate::incremental::digest(identity.as_bytes())),
            blobs: format!("output-blobs-v3-{}", env!("DM_EMISSION_FINGERPRINT")),
            code_blobs: format!("output-code-v1-{}",env!("DM_EMISSION_FINGERPRINT")), ..Self::default() }
    }
    pub fn set_workers(&mut self, workers: usize) { self.workers = workers.clamp(1, 4); }
    pub fn resident_bytes(&self) -> usize {
        self.resident_bytes + self.pending_bytes + self.recency.capacity() * 96 + self.metadata_bytes
    }
    fn install_handle(&mut self, key: crate::ProcKey, handle: Handle) {
        if let Some(old) = self.handles.remove(&key) {
            self.metadata_bytes = self.metadata_bytes.saturating_sub(handle_charge(&key, &old));
        }
        if self.known_missing.remove(&key) {
            self.metadata_bytes = self.metadata_bytes.saturating_sub(key.path.capacity() + 64);
        }
        self.metadata_bytes += handle_charge(&key, &handle);
        self.handles.insert(key, handle);
    }
    pub fn clear_decoded(&mut self) { self.flush(); self.resident.clear(); self.recency.clear(); self.resident_bytes = 0; }
    pub fn has_handle(&self, key: &crate::ProcKey) -> bool { self.handles.contains_key(key) }
    pub fn prefetch(&mut self, keys: &[crate::ProcKey]) {
        let Some(store) = self.store.clone() else { return; };
        // One addressed source-order window shares database ownership. Payload
        // byte limits and recursive split remain unchanged; decode work still
        // drains under its separate 64 MiB expanded-memory budget.
        for chunk in keys.chunks(OBJECT_WINDOW) {
            let missing: Vec<_> = chunk.iter().filter(|key| !self.handles.contains_key(*key)
                && !self.known_missing.contains(*key)).cloned().collect();
            if !missing.is_empty() {
                let rows: Vec<_> = missing.iter().map(|key| dm_store::Key::new(&self.namespace,
                    crate::lower_cache::shared_binding_fingerprint(key))).collect();
                if let Ok(batch) = store.read_many_bounded(&rows, 64 * 1024, 1024 * 1024, None) {
                    self.stats.batches += 1;
                    for (key, bytes) in missing.into_iter().zip(batch.values) {
                        if let Some(handle) = bytes.as_deref().and_then(|bytes| serde_json::from_slice::<Handle>(bytes).ok()) {
                            self.install_handle(key, handle);
                        } else {
                            let charge = key.path.capacity() + 64;
                            if self.known_missing.insert(key) { self.metadata_bytes += charge; }
                        }
                    }
                }
            }
            let payloads: Vec<_> = chunk.iter().filter_map(|key| self.handles.get(key))
                .filter(|h| !self.resident.contains_key(&h.payload)).map(|h| h.payload.clone())
                .collect::<std::collections::BTreeSet<_>>().into_iter().collect();
            self.refill(&store, &payloads);
        }
    }
    fn refill(&mut self, store: &dm_store::Store, payloads: &[String]) {
        if payloads.is_empty() { return; }
        let rows: Vec<_> = payloads.iter().map(|payload| dm_store::Key::new(&self.blobs, payload)).collect();
        let read_start = std::time::Instant::now();
        let read = store.read_many_bounded(&rows, 16 * 1024 * 1024, 8 * 1024 * 1024, None);
        self.stats.read_seconds += read_start.elapsed().as_secs_f64();
        match read {
            Ok(batch) => {
                self.stats.batches += 1;
                let inputs: Vec<_> = payloads.iter().cloned().zip(batch.values).zip(batch.witnesses)
                    .map(|((payload,bytes),witness)| {let valid=witness.value_digest.as_deref()==Some(payload.as_str());
                        (payload,if valid {bytes}else{None})}).collect();
                self.stats.disk_bytes += inputs.iter().filter_map(|(_, bytes)| bytes.as_ref()).map(Vec::len).sum::<usize>();
                let decode_start = std::time::Instant::now();
                let decode = |(payload, bytes): &(String, Option<Vec<u8>>)| {
                    let bytes = bytes.as_deref()?;
                    OutputFragment::decode(bytes).map(|fragment| (payload.clone(), Arc::new(fragment)))
                };
                let estimate = |(_, bytes): &(String, Option<Vec<u8>>)| {
                    let Some(bytes)=bytes.as_deref() else {return 0;};
                    let modern=bytes.get(..8)==Some(b"DMOCMP04".as_slice());
                    let at=if modern {12}else{8};
                    let metadata=bytes.get(at..at+4).map(|bytes|u32::from_le_bytes(bytes.try_into().unwrap()) as usize)
                        .unwrap_or(0).min(16*1024*1024).saturating_mul(3);
                    let code=if modern {bytes.get(8..12).map(|bytes|u32::from_le_bytes(bytes.try_into().unwrap()) as usize)
                        .unwrap_or(u16::MAX as usize).min(u16::MAX as usize)*4} else {u16::MAX as usize*4};
                    metadata.saturating_add(code+8)
                };
                // Compressed byte budgets do not bound decoded result retention.
                // Drain bounded output windows as well as bounded active jobs.
                let hydration_before=self.stats.code_hydration_seconds;
                let mut start = 0;
                while start < inputs.len() {
                    let mut end = start;
                    let mut bytes = 0usize;
                    while end < inputs.len() {
                        let charge = estimate(&inputs[end]);
                        if end > start && bytes.saturating_add(charge) > 64 * 1024 * 1024 { break; }
                        bytes = bytes.saturating_add(charge); end += 1;
                    }
                    let group = &inputs[start..end];
                    let decoded = dm_work::map_ordered(group,
                        dm_work::WorkLimits { workers: self.workers.max(1), max_active_bytes: 64 * 1024 * 1024 },
                        estimate, decode).unwrap_or_else(|_| group.iter().map(decode).collect());
                    let decoded: Vec<_> = decoded.into_iter().flatten().collect();
                    self.hydrate_code(store, decoded);
                    start = end;
                }
                self.stats.decode_seconds += (decode_start.elapsed().as_secs_f64()
                    -(self.stats.code_hydration_seconds-hydration_before)).max(0.0);
            }
            Err(error) if error.kind() == std::io::ErrorKind::InvalidInput && payloads.len() > 1 => {
                let middle = payloads.len() / 2;
                self.refill(store, &payloads[..middle]); self.refill(store, &payloads[middle..]);
            }
            _ => {}
        }
    }
    fn hydrate_code(&mut self, store: &dm_store::Store, fragments: Vec<(String, Arc<OutputFragment>)>) {
        let hydration_started=std::time::Instant::now();
        let names: Vec<_>=fragments.iter().filter_map(|(_,fragment)|fragment.code_digest.clone())
            .collect::<std::collections::BTreeSet<_>>().into_iter().collect();
        let mut words=HashMap::new();
        self.read_code_window(store,&names,&mut words);
        for (payload,mut fragment) in fragments {
            if let Some(name)=&fragment.code_digest {
                let Some(code)=words.get(name) else { continue; };
                let Some(fragment)=Arc::get_mut(&mut fragment) else { continue; };
                fragment.words=Arc::clone(code);
            }
            if fragment.validate() { self.retain_decoded(payload,fragment); }
        }
        self.stats.code_hydration_seconds+=hydration_started.elapsed().as_secs_f64();
    }
    fn read_code_window(&mut self, store: &dm_store::Store, names: &[String], words: &mut HashMap<String,Arc<[u32]>>) {
        if names.is_empty() { return; }
        let keys: Vec<_>=names.iter().map(|name|dm_store::Key::new(&self.code_blobs,name)).collect();
        let started=std::time::Instant::now();
        let result=store.read_many_bounded(&keys,16+u16::MAX as usize*8,8*1024*1024,None);
        self.stats.read_seconds+=started.elapsed().as_secs_f64();
        match result {
            Ok(batch)=>{
                self.stats.batches+=1;
                for ((name,bytes),witness) in names.iter().zip(batch.values).zip(batch.witnesses) {
                    let Some(bytes)=bytes else { continue; };
                    self.stats.disk_bytes+=bytes.len();
                    self.stats.code_read_bytes+=bytes.len();
                    // Store already verified the SHA in its envelope. Comparing
                    // that exact digest with the addressed name avoids a second
                    // full payload hash in this hydration layer.
                    if witness.value_digest.as_deref()!=Some(name.as_str()) {continue;}
                    let raw=if bytes.get(..8)==Some(b"DMWORD02".as_slice()) {
                        let Some(length)=bytes.get(8..12) else {continue;};
                        if u32::from_le_bytes(length.try_into().unwrap()) as usize>u16::MAX as usize*4 {continue;}
                        let Ok(raw)=lz4_flex::decompress_size_prepended(&bytes[8..]) else {continue;}; raw
                    } else if bytes.get(..8)==Some(b"DMWORD01".as_slice()) {bytes[8..].to_vec()}
                    else {continue;};
                    if raw.len()%4!=0 || raw.len()/4>u16::MAX as usize {continue;}
                    let code=raw.chunks_exact(4).map(|bytes|u32::from_le_bytes(bytes.try_into().unwrap())).collect::<Vec<_>>();
                    words.insert(name.clone(),code.into());
                }
            }
            Err(error) if error.kind()==std::io::ErrorKind::InvalidInput && names.len()>1 => {
                let middle=names.len()/2;
                self.read_code_window(store,&names[..middle],words);
                self.read_code_window(store,&names[middle..],words);
            }
            _=>{}
        }
    }
    fn retain_decoded(&mut self, payload: String, fragment: Arc<OutputFragment>) {
        if self.resident.contains_key(&payload) { return; }
        let charge = fragment.charge();
        if charge > 64 * 1024 * 1024 { return; }
        while self.resident_bytes + charge > 64 * 1024 * 1024 {
            let Some((oldest, tick)) = self.recency.pop_front() else { break; };
            if self.resident.get(&oldest).is_some_and(|entry| entry.used == tick) {
                if let Some(old) = self.resident.remove(&oldest) { self.resident_bytes -= old.charge; }
            }
        }
        self.tick += 1; self.resident_bytes += charge;
        self.recency.push_back((payload.clone(), self.tick));
        self.resident.insert(payload, Resident { fragment, charge, used: self.tick });
    }
    pub fn get(&mut self, key: &crate::ProcKey, descriptor: &crate::ProcDescriptor, candidate: &str) -> Option<Arc<OutputFragment>> {
        let handle = self.handles.get(key).filter(|handle| handle.descriptor == *descriptor && handle.candidate == candidate)?;
        let entry = self.resident.get_mut(&handle.payload)?;
        self.tick += 1; entry.used = self.tick;
        self.recency.push_back((handle.payload.clone(), self.tick));
        Some(Arc::clone(&entry.fragment))
    }
    pub fn retain(&mut self, key: crate::ProcKey, descriptor: crate::ProcDescriptor, candidate: String, mut fragment: OutputFragment) {
        let encode_start = std::time::Instant::now();
        let mut raw_code = Vec::with_capacity(fragment.words.len()*4);
        for word in fragment.words.iter() { raw_code.extend_from_slice(&word.to_le_bytes()); }
        let mut code=b"DMWORD02".to_vec();
        code.extend(lz4_flex::compress_prepend_size(&raw_code));
        let code_digest = format!("{:x}",Sha256::digest(&code));
        fragment.code_digest=Some(code_digest.clone());
        fragment.code_word_count=Some(fragment.words.len() as u32);
        let Some(recipe_identity)=fragment.recipe_identity() else {return;};
        if let Some(linked)=fragment.linked.as_mut() {linked.recipe_identity=recipe_identity;}
        let Some(bytes) = fragment.encode() else { return; };
        self.stats.encode_seconds += encode_start.elapsed().as_secs_f64();
        let payload = format!("{:x}", Sha256::digest(&bytes));
        let handle = Handle { descriptor, candidate, payload: payload.clone() };
        let Ok(handle_bytes) = serde_json::to_vec(&handle) else { return; };
        self.pending_bytes += bytes.len() + code.len() + handle_bytes.len();
        self.pending.push(dm_store::Change::Put(dm_store::Key::new(&self.code_blobs,code_digest),code));
        self.pending.push(dm_store::Change::Put(dm_store::Key::new(&self.blobs, &payload), bytes));
        self.pending.push(dm_store::Change::Put(dm_store::Key::new(&self.namespace,
            crate::lower_cache::shared_binding_fingerprint(&key)), handle_bytes));
        self.install_handle(key, handle);
        self.retain_decoded(payload, Arc::new(fragment)); self.stats.built += 1;
        // Keep the byte bound unchanged; tiny immutable fragments can share
        // larger transactions instead of paying a synchronous commit per 1024
        // procedures. Source-order emission and atomicity remain unchanged.
        if self.pending_bytes >= 8 * 1024 * 1024 || self.pending.len() >= 8192 { self.flush(); }
    }
    pub fn flush(&mut self) {
        if self.pending.is_empty() { return; }
        if let Some(store) = &self.store {
            let started = std::time::Instant::now();
            let write = store.commit(&[], &self.pending, None);
            self.stats.flush_seconds += started.elapsed().as_secs_f64();
            self.stats.write_batches += 1;
            if write.is_err() {
                // Persistence is derived state. Bound failed-write retention;
                // later builds can recompute nodes whose disk write was lost.
                if self.pending_bytes >= 16 * 1024 * 1024 { self.pending.clear(); self.pending_bytes = 0; }
                return;
            }
        }
        self.pending.clear(); self.pending_bytes = 0;
    }
    pub fn finish(&mut self, active: &std::collections::BTreeSet<crate::ProcKey>) {
        self.handles.retain(|key, _| active.contains(key)); self.known_missing.retain(|key| active.contains(key));
        self.metadata_bytes = self.handles.iter().map(|(key, handle)| handle_charge(key, handle)).sum::<usize>()
            + self.known_missing.iter().map(|key| key.path.capacity() + 64).sum::<usize>();
        self.recency.retain(|(key, tick)| self.resident.get(key).is_some_and(|entry| entry.used == *tick));
        self.flush();
    }
}
