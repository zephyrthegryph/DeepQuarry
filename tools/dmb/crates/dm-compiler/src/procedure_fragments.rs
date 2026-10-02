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
    #[serde(default)] pub wire_code:Option<dm_output::wire_image::VerifiedCodeHandle>,
    #[serde(skip)]
    pub words: Arc<[u32]>,
}
impl OutputFragment {
    /// Bounds and immutable recipe proof available without restoring code.
    /// Operand contents are authorized by the separately verified code object
    /// and exact linked assignment witness before physical reuse.
    fn validate_metadata(&self)->bool {
        let Some(words)=self.code_word_count else {return false;};
        if words>u16::MAX as u32||self.code_digest.as_ref().is_none_or(|digest|digest.len()!=64
            ||!digest.bytes().all(|byte|byte.is_ascii_hexdigit())) {return false;}
        if self.wire_code.as_ref().is_some_and(|handle|handle.word_count()!=words as usize) {return false;}
        if self.allocated_rows.as_ref().is_some_and(|layout|!layout.valid()
            ||layout.variable_count as usize!=self.variables.len()||self.record.code_locals_args!=[0,1,2]) {return false;}
        let valid_variable=|id:u32|if self.allocated_rows.is_some() {(id as usize)<self.variables.len()}
            else {id.checked_sub(self.old_variable_base).is_some_and(|offset|(offset as usize)<self.variables.len())};
        if self.locals.len()>u16::MAX as usize||self.arguments.len()>u16::MAX as usize||self.arguments.len()%4!=0
            ||self.locals.iter().any(|&id|!valid_variable(id))
            ||self.arguments.chunks_exact(4).any(|argument|!valid_variable(argument[2]))
            ||self.helpers.iter().any(|helper|helper.parameter>=self.arguments.len()/4)
            ||self.relocations.iter().any(|r|r.offset>=words||(r.packed_tag.is_some()&&r.offset.checked_add(1).is_none_or(|offset|offset>=words)))
            ||self.debug.iter().any(|mark|mark.file_offset>=words||mark.line_offset>=words)
            ||self.strings.iter().any(|recipe|matches!(recipe,StringRecipe::Debug{index} if *index>=self.debug.len())) {return false;}
        if let Some(linked)=&self.linked {
            if !linked.valid()||linked.start.variables!=self.old_variable_base||!self.helpers.is_empty()
                ||linked.symbol_ids.len()!=self.relocations.len()||linked.debug_ids.len()!=self.debug.len()
                ||linked.unresolved_debug!=self.unresolved_debug
                ||self.recipe_identity().as_deref()!=Some(linked.recipe_identity.as_str()) {return false;}
            let mut strings:Vec<_>=self.strings.iter().filter_map(|recipe|match recipe {StringRecipe::Bytes{old_id,..}=>Some(*old_id),_=>None}).collect();
            strings.sort_unstable();if strings!=linked.string_ids {return false;}
            let mapped=|id:u32|id==0xffff||strings.binary_search(&id).is_ok();
            if self.variables.iter().any(|variable|!mapped(variable.name))||self.record.strings.iter().any(|&id|!mapped(id)) {return false;}
            let required=if self.allocated_rows.is_some() {AllocationMask::NONE}else {
                AllocationMask::VARIABLES.union(AllocationMask::LISTS).union(AllocationMask::PROCEDURES).union(AllocationMask::REFERENCES)};
            if linked.allocation_mask!=required {return false;}
            if self.allocated_rows.is_none() {
                let mut next=linked.start.lists;
                for actual in self.record.code_locals_args {
                    if next==0xffff {next+=1;}if actual!=next {return false;}
                    let Some(value)=next.checked_add(1) else {return false;};next=value;
                }
            }
        } true
    }
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
            &self.debug,&self.helpers,&self.code_digest,&self.code_word_count,&self.allocated_rows,&self.wire_code)).ok()?;
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
            + self.wire_code.as_ref().map_or(0,|handle|handle.digest().len()+96)
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
    pub retained_projection_hits: usize,
    pub shared_projection_hits: usize,
    pub metadata_only_reused:usize,
    pub wire_relinked:usize,
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
struct Resident { fragment: Arc<OutputFragment>, charge: usize, used: u64, admitted: bool, revision: u64 }
#[derive(Default)]
pub(super) struct ProcedureFragments {
    handles: HashMap<crate::ProcKey, Handle>,
    known_missing: HashSet<crate::ProcKey>,
    resident: HashMap<String, Resident>,
    recency: VecDeque<(String, u64)>,
    pending: Vec<dm_store::Change>,
    pending_bytes: usize,
    resident_bytes: usize,
    admitted_bytes: usize,
    metadata_bytes: usize,
    tick: u64,
    revision: u64,
    workers: usize,
    store: Option<dm_store::Store>,
    namespace: String,
    blobs: String,
    code_blobs: String,
    code_store:Option<Arc<dm_output::wire_image::CodeObjectStore>>,
    pub stats: FragmentStats,
}
impl ProcedureFragments {
    pub fn open(root: &std::path::Path, identity: &str) -> Self {
        let store = dm_store::Store::open(root.join("output-fragments.redb")).ok();
        let code_store=dm_output::wire_image::CodeObjectStore::open(root).ok();
        Self { store, code_store,namespace: format!("output-handles-v3-{}-{}", env!("DM_EMISSION_FINGERPRINT"),
            crate::incremental::digest(identity.as_bytes())),
            blobs: format!("output-blobs-v3-{}", env!("DM_EMISSION_FINGERPRINT")),
            code_blobs: format!("output-code-v1-{}",env!("DM_EMISSION_FINGERPRINT")), ..Self::default() }
    }
    pub fn set_workers(&mut self, workers: usize) {
        self.workers = workers.clamp(1, 4);
        self.revision = self.revision.wrapping_add(1);
    }
    pub fn resident_bytes(&self) -> usize {
        self.resident_bytes + self.pending_bytes + self.recency.capacity() * 96 + self.metadata_bytes
            +self.code_store.as_ref().map_or(0,|store|store.resident_bytes())
    }
    pub fn decoded_bytes(&self)->usize {self.resident_bytes}
    pub fn code_store(&self)->Option<Arc<dm_output::wire_image::CodeObjectStore>> {self.code_store.clone()}
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
    pub fn clear_decoded(&mut self) { self.flush(); self.resident.clear(); self.recency.clear(); self.resident_bytes = 0; self.admitted_bytes = 0; }
    /// Drop only disposable current-window projections; preserve the stable
    /// admitted tier and compact handles until actual aggregate pressure asks
    /// for their space too.
    pub fn trim_transient(&mut self)->usize {
        let before=self.resident_bytes();
        self.resident.retain(|_,entry|entry.admitted);
        self.resident_bytes=self.admitted_bytes;
        self.recency.clear();self.recency.shrink_to_fit();
        before.saturating_sub(self.resident_bytes())
    }
    /// Target the decoded payload bytes, preferring admitted projections.
    /// Removal is oldest-use first within a tier, with digest ties deterministic.
    /// Handles and persistence buffers are not part of this payload target.
    pub fn trim_to(&mut self,limit:usize)->usize {
        let before=self.resident_bytes();
        let mut victims:Vec<_>=self.resident.iter().map(|(key,entry)|
            (entry.admitted,entry.used,key.clone())).collect();
        victims.sort_unstable();
        for (_,_,key) in victims {
            if self.resident_bytes<=limit {break;}
            if let Some(entry)=self.resident.remove(&key) {
                self.resident_bytes=self.resident_bytes.saturating_sub(entry.charge);
                if entry.admitted {self.admitted_bytes=self.admitted_bytes.saturating_sub(entry.charge);}
            }
        }
        self.recency.retain(|(key,tick)|self.resident.get(key).is_some_and(|entry|entry.used==*tick));
        self.recency.shrink_to_fit();
        before.saturating_sub(self.resident_bytes())
    }
    pub fn has_handle(&self, key: &crate::ProcKey) -> bool { self.handles.contains_key(key) }
    /// Addressed metadata-only window for the physical object composer. The
    /// returned selector must match current descriptor/candidate before use;
    /// no PreparedProc or code words are decoded here. Legacy inline-code
    /// fragments deliberately miss and take the normal hydrated fallback.
    pub fn read_metadata_batch(&mut self,keys:&[crate::ProcKey])->Vec<Option<(crate::ProcDescriptor,String,Arc<OutputFragment>)>> {
        if keys.len()>OBJECT_WINDOW {return keys.iter().map(|_|None).collect();}
        let Some(store)=self.store.clone() else {return keys.iter().map(|_|None).collect();};
        let missing:Vec<_>=keys.iter().filter(|key|!self.handles.contains_key(*key)&&!self.known_missing.contains(*key)).cloned().collect();
        let rows:Vec<_>=missing.iter().map(|key|dm_store::Key::new(&self.namespace,crate::lower_cache::shared_binding_fingerprint(key))).collect();
        if let Ok(batch)=store.read_many_bounded(&rows,64*1024,1024*1024,None) {
            for (key,bytes) in missing.into_iter().zip(batch.values) {
                if let Some(handle)=bytes.as_deref().and_then(|bytes|serde_json::from_slice::<Handle>(bytes).ok()) {self.install_handle(key,handle);}
            }
        }
        let payloads:Vec<_>=keys.iter().filter_map(|key|self.handles.get(key).map(|handle|handle.payload.clone())).collect();
        let mut decoded=HashMap::new();let mut retained=0usize;
        for payload in &payloads {if let Some(entry)=self.resident.get(payload) {
            let charge=entry.fragment.charge();if retained+charge<=32*1024*1024 {
                retained+=charge;decoded.insert(payload.clone(),Arc::clone(&entry.fragment));
                if entry.admitted&&entry.revision!=self.revision {self.stats.retained_projection_hits+=1;}
            }
        }}
        let missing:Vec<_>=payloads.into_iter().filter(|payload|!decoded.contains_key(payload)).collect();
        self.read_metadata_payloads(&store,&missing,&mut decoded,&mut retained);
        let output:Vec<_>=keys.iter().map(|key| {let handle=self.handles.get(key)?;
            Some((handle.descriptor.clone(),handle.candidate.clone(),Arc::clone(decoded.get(&handle.payload)?)))
        }).collect();
        if let Some(store)=&self.code_store {
            let handles=output.iter().filter_map(|entry|entry.as_ref().and_then(|(_,_,fragment)|fragment.wire_code.clone())).collect();
            let _=store.set_lookahead(handles);
        }
        output
    }
    fn read_metadata_payloads(&mut self,store:&dm_store::Store,payloads:&[String],decoded:&mut HashMap<String,Arc<OutputFragment>>,retained:&mut usize) {
        if payloads.is_empty() {return;}
        let rows:Vec<_>=payloads.iter().map(|payload|dm_store::Key::new(&self.blobs,payload)).collect();
        let started=std::time::Instant::now();
        let result=store.read_many_bounded(&rows,16*1024*1024,8*1024*1024,None);
        self.stats.read_seconds+=started.elapsed().as_secs_f64();
        match result {
            Ok(batch)=>{self.stats.batches+=1;for ((payload,bytes),witness) in payloads.iter().zip(batch.values).zip(batch.witnesses) {
                if decoded.contains_key(payload)||witness.value_digest.as_deref()!=Some(payload.as_str()) {continue;}
                let Some(bytes)=bytes else {continue;};
                self.stats.disk_bytes+=bytes.len();
                let started=std::time::Instant::now();
                let Some(fragment)=OutputFragment::decode(&bytes) else {continue;};
                if !fragment.words.is_empty()||!fragment.validate_metadata() {continue;}
                self.stats.decode_seconds+=started.elapsed().as_secs_f64();
                let charge=fragment.charge();if retained.saturating_add(charge)>32*1024*1024 {continue;}
                *retained+=charge;decoded.insert(payload.clone(),Arc::new(fragment));
            }},
            Err(error) if error.kind()==std::io::ErrorKind::InvalidInput&&payloads.len()>1=>{
                let middle=payloads.len()/2;self.read_metadata_payloads(store,&payloads[..middle],decoded,retained);
                self.read_metadata_payloads(store,&payloads[middle..],decoded,retained);
            },_=>{}
        }
    }
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
            let mut missing=Vec::new();
            for payload in payloads {
                if let Some(fragment)=crate::shared_artifacts::get::<OutputFragment>("output-fragment",&payload) {
                    self.retain_decoded(payload,fragment);self.stats.shared_projection_hits+=1;
                } else {missing.push(payload);}
            }
            self.refill(&store, &missing);
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
        let names: Vec<_>=fragments.iter().filter(|(_,fragment)|fragment.wire_code.is_none()).filter_map(|(_,fragment)|fragment.code_digest.clone())
            .collect::<std::collections::BTreeSet<_>>().into_iter().collect();
        let mut words=HashMap::new();
        self.read_code_window(store,&names,&mut words);
        let handles:Vec<_>=fragments.iter().filter_map(|(_,fragment)|fragment.wire_code.clone()).collect();
        self.read_wire_code_window(&handles,&mut words);
        for (payload,mut fragment) in fragments {
            if let Some(name)=fragment.wire_code.as_ref().map(|handle|handle.digest()).or(fragment.code_digest.as_deref()) {
                let Some(code)=words.get(name) else { continue; };
                let Some(fragment)=Arc::get_mut(&mut fragment) else { continue; };
                fragment.words=Arc::clone(code);
            }
            if fragment.validate() { self.retain_decoded(payload,fragment); }
        }
        self.stats.code_hydration_seconds+=hydration_started.elapsed().as_secs_f64();
    }
    /// Explicit compatibility hydration reads the same verified code leaf as
    /// physical publication, rather than persisting a duplicate representation.
    fn read_wire_code_window(&mut self,handles:&[dm_output::wire_image::VerifiedCodeHandle],words:&mut HashMap<String,Arc<[u32]>>) {
        let Some(store)=self.code_store.clone() else {return;};
        let mut start=0;
        while start<handles.len() {
            let mut end=start;let mut bytes=0usize;
            while end<handles.len()&&end-start<1024 {
                let charge=2+handles[end].word_count()*handles[end].object_width();
                if end>start&&bytes+charge>8*1024*1024 {break;}bytes+=charge;end+=1;
            }
            let started=std::time::Instant::now();let result=store.prefetch(&handles[start..end]);
            self.stats.read_seconds+=started.elapsed().as_secs_f64();self.stats.batches+=1;
            if result.is_ok() {for handle in &handles[start..end] {
                if words.contains_key(handle.digest()) {continue;}
                let Ok(raw)=store.restore(handle) else {continue;};self.stats.code_read_bytes+=raw.len();self.stats.disk_bytes+=raw.len();
                let code:Vec<u32>=if handle.object_width()==4 {raw[2..].chunks_exact(4).map(|word|u32::from_le_bytes(word.try_into().unwrap())).collect()}
                    else {raw[2..].chunks_exact(2).map(|word|u16::from_le_bytes(word.try_into().unwrap()) as u32).collect()};
                words.insert(handle.digest().to_owned(),code.into());
            }}start=end;
        }
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
        if charge > (64 * 1024 * 1024usize).saturating_sub(self.admitted_bytes) { return; }
        // Reserve half the existing budget for immutable, source-order admitted
        // projections. A whole-project sequential pass exceeds the cache and
        // otherwise evicts every earlier projection before the next revision.
        // Admission is stable, not an additional cache or a growing snapshot;
        // the other half remains the bounded current replay window.
        let admitted = self.admitted_bytes.saturating_add(charge) <= 32 * 1024 * 1024;
        while self.resident_bytes + charge > 64 * 1024 * 1024 {
            let Some((oldest, tick)) = self.recency.pop_front() else { break; };
            if self.resident.get(&oldest).is_some_and(|entry| entry.used == tick) {
                if let Some(old) = self.resident.remove(&oldest) { self.resident_bytes -= old.charge; }
            }
        }
        self.tick += 1; self.resident_bytes += charge;
        if admitted { self.admitted_bytes += charge; }
        else { self.recency.push_back((payload.clone(), self.tick)); }
        let fragment=crate::shared_artifacts::intern("output-fragment",&payload,fragment);
        self.resident.insert(payload, Resident { fragment, charge, used: self.tick, admitted, revision: self.revision });
    }
    pub fn get(&mut self, key: &crate::ProcKey, descriptor: &crate::ProcDescriptor, candidate: &str) -> Option<Arc<OutputFragment>> {
        let handle = self.handles.get(key).filter(|handle| handle.descriptor == *descriptor && handle.candidate == candidate)?;
        let entry = self.resident.get_mut(&handle.payload)?;
        self.tick += 1; entry.used = self.tick;
        if entry.admitted {
            if entry.revision != self.revision { self.stats.retained_projection_hits += 1; }
        }
        else { self.recency.push_back((handle.payload.clone(), self.tick)); }
        Some(Arc::clone(&entry.fragment))
    }
    pub fn retain(&mut self, key: crate::ProcKey, descriptor: crate::ProcDescriptor, candidate: String, mut fragment: OutputFragment) {
        let encode_start = std::time::Instant::now();
        fragment.code_word_count=Some(fragment.words.len() as u32);
        if fragment.wire_code.is_none() {fragment.wire_code=self.code_store.as_ref().and_then(|store|store.stage_words(&fragment.words,4).ok());}
        let legacy_code=if let Some(handle)=&fragment.wire_code {
            fragment.code_digest=Some(handle.digest().to_owned());None
        } else {
            let mut raw_code=Vec::with_capacity(fragment.words.len()*4);
            for word in fragment.words.iter() {raw_code.extend_from_slice(&word.to_le_bytes());}
            let mut code=b"DMWORD02".to_vec();code.extend(lz4_flex::compress_prepend_size(&raw_code));
            let digest=format!("{:x}",Sha256::digest(&code));fragment.code_digest=Some(digest.clone());Some((digest,code))
        };
        let Some(recipe_identity)=fragment.recipe_identity() else {return;};
        if let Some(linked)=fragment.linked.as_mut() {linked.recipe_identity=recipe_identity;}
        let Some(bytes) = fragment.encode() else { return; };
        self.stats.encode_seconds += encode_start.elapsed().as_secs_f64();
        let payload = format!("{:x}", Sha256::digest(&bytes));
        let handle = Handle { descriptor, candidate, payload: payload.clone() };
        let Ok(handle_bytes) = serde_json::to_vec(&handle) else { return; };
        self.pending_bytes += bytes.len() + handle_bytes.len();
        if let Some((code_digest,code))=legacy_code {self.pending_bytes+=code.len();
            self.pending.push(dm_store::Change::Put(dm_store::Key::new(&self.code_blobs,code_digest),code));}
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
        // Never publish a recipe that points at an uncommitted code leaf.
        if let Some(store)=&self.code_store {if store.flush().is_err() {return;}}
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
        let payloads: HashSet<_> = self.handles.values().map(|handle| handle.payload.as_str()).collect();
        self.resident.retain(|payload, _| payloads.contains(payload.as_str()));
        self.resident_bytes = self.resident.values().map(|entry| entry.charge).sum();
        self.admitted_bytes = self.resident.values().filter(|entry| entry.admitted).map(|entry| entry.charge).sum();
        self.recency.retain(|(key, tick)| self.resident.get(key).is_some_and(|entry| entry.used == *tick));
        self.flush();
    }
}
