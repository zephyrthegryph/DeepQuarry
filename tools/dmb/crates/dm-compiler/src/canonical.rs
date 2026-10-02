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

#[path = "skeleton_fragments.rs"]
mod skeleton_fragments;
#[path = "declaration_base.rs"]
mod declaration_base;
pub(super) use declaration_base::{DeclarationBase, declaration_base_key};
#[path = "declaration_delta.rs"]
mod declaration_delta;
#[path = "owner_binding_queries.rs"]
mod owner_binding_queries;
pub(super) use owner_binding_queries::OwnerBindingQueries;
pub(super) use declaration_delta::DeclarationInputs;


#[derive(Clone, Serialize, Deserialize)]
pub(super) struct OwnedPendingProc {
    pub owner: Option<u32>,
    pub owner_path: String,
    pub verb: bool,
}

/// Immutable wire lookup recipe. The decoded maps duplicate DMB text and are
/// only needed while allocating a generation, not while retaining a frontend.
#[derive(Clone,Serialize,Deserialize)]
pub(super) enum StringIndexRecipe {
    Packed(Arc<Vec<u8>>),
    Decoded(Arc<StringIndex>),
}
impl From<StringIndex> for StringIndexRecipe {
    fn from(index:StringIndex)->Self {
        if let Ok(bytes)=rmp_serde::to_vec_named(&index) {
            if bytes.len()<=256*1024*1024 {
                let packed=lz4_flex::compress_prepend_size(&bytes);
                if packed.len()<bytes.len() {return Self::Packed(Arc::new(packed));}
            }
        }
        Self::Decoded(Arc::new(index))
    }
}
impl StringIndexRecipe {
    pub(super) fn decode(&self)->Result<StringIndex,String> {
        match self {
            Self::Decoded(index)=>Ok(index.as_ref().clone()),
            Self::Packed(bytes)=>{
                if bytes.len()<4||u32::from_le_bytes(bytes[..4].try_into().unwrap()) as usize>256*1024*1024 {return Err("invalid string-index recipe size".into());}
                let decoded=lz4_flex::decompress_size_prepended(bytes).map_err(|error|error.to_string())?;
                rmp_serde::from_slice(&decoded).map_err(|error|error.to_string())
            }
        }
    }
    fn resident_bytes(&self)->usize {
        match self {
            Self::Packed(bytes)=>bytes.capacity()+64,
            Self::Decoded(index)=>rmp_serde::to_vec_named(index.as_ref()).map_or(0,|bytes|bytes.len()*3),
        }
    }
}

#[derive(Clone, Serialize, Deserialize)]
pub(super) struct SkeletonMetadata {
    pub strings: StringIndexRecipe,
    pub proc_paths: HashSet<Vec<u8>>,
    pub class_paths: HashMap<String, u32>,
    pub pending: Vec<OwnedPendingProc>,
    pub dynamic: Vec<PendingDynamic>,
    pub initializers: Vec<initializer_pipeline::InitializerRecipe>,
    pub modified_initializers: Vec<initializer_pipeline::InitializerRecipe>,
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
#[derive(Clone, Default, PartialEq, Eq, Hash, Serialize, Deserialize)]
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

/// Source offsets and executable body syntax do not participate in declaration
/// identity. A retained ancestor is significant only to reachability of settings.
pub(super) fn invocation_declaration_projection(items: &[Item]) -> Vec<Item> {
    items.iter().filter_map(|item| {
        let header = item.header.trim();
        let declaration = header.starts_with("set ") ||
            ["var/static/", "var/global/", "var/const/"].iter().any(|prefix| header.starts_with(prefix));
        let children = invocation_declaration_projection(&item.children);
        if !declaration && children.is_empty() { return None; }
        Some(Item { kind: item.kind, header: item.header.clone(), span: item.span, header_span: item.header_span, indent: item.indent, children })
    }).collect()
}

/// Content-addressed declaration fragments survive whole-prefix allocation
/// replay. A new declaration changes only its own signature/settings/static
/// syntax; inherited metadata is an explicit fragment input.
#[derive(Clone,Copy,Default)]
pub(super) struct InvocationCounters {pub signature_hits:usize,pub signature_misses:usize,pub syntax_hits:usize,pub syntax_misses:usize,pub frame_hits:usize,pub frame_misses:usize,pub point_reads:usize,pub batch_records:usize}
#[derive(Default)]
pub(super) struct InvocationFragments {
    entries: BTreeMap<String, Arc<InvocationSyntax>>,
    signatures: BTreeMap<String, Arc<(String, Vec<ParsedParameter>)>>,
    pending: BTreeMap<String, Vec<u8>>,
    pending_bytes: usize,
    store: Option<Store>,
    bytes: usize,
    signature_misses: BTreeSet<String>,
    disk_syntax_ready: bool,
    requested_syntax: BTreeMap<String, Arc<InvocationSyntax>>,
    requested_bytes: usize,
    requested_encoded: BTreeMap<String,Vec<u8>>,
    requested_encoded_bytes: usize,
    requested_signatures: BTreeMap<String, Arc<(String, Vec<ParsedParameter>)>>,
    requested_signature_bytes: usize,
    syntax_misses: BTreeSet<String>,
    handle_misses: BTreeSet<String>,
    window_declarations: HashMap<usize,(String,String)>,
    pub(super) counters: InvocationCounters,
    handles: BTreeMap<[u8;32],[u8;32]>,
}
impl InvocationFragments {
    const LIMIT: usize = 32 * 1024 * 1024;
    fn open(root: &Path) -> Self {
        let mut cache = Self::default();
        cache.store = Store::open(root.join("declaration-fragments.redb")).ok();
        cache.disk_syntax_ready = cache.store.as_ref().and_then(|store|
            store.read_many(&[Key::new("declaration-fragment-ready", Self::namespace())],None).ok())
            .is_some_and(|record|record.values.first().is_some_and(Option::is_some));
        cache
    }
    fn signature_namespace() -> String {
        format!("invocation-signatures-v2-{}", env!("DM_EMISSION_FINGERPRINT"))
    }
    fn namespace() -> String {
        format!("invocation-syntax-v4-{}", env!("DM_EMISSION_FINGERPRINT"))
    }
    fn handles_namespace() -> String { format!("invocation-syntax-handles-v3-{}",env!("DM_EMISSION_FINGERPRINT")) }
    fn digest_bytes(value:&str)->Option<[u8;32]> {if value.len()!=64{return None;}let mut bytes=[0u8;32];for(index,pair)in value.as_bytes().chunks_exact(2).enumerate(){let digit=|byte:u8|match byte {b'0'..=b'9'=>Some(byte-b'0'),b'a'..=b'f'=>Some(byte-b'a'+10),b'A'..=b'F'=>Some(byte-b'A'+10),_=>None};bytes[index]=(digit(pair[0])?<<4)|digit(pair[1])?;}Some(bytes)}
    fn digest_text(value:&[u8;32])->String {use std::fmt::Write;let mut result=String::with_capacity(64);for byte in value {let _=write!(result,"{byte:02x}");}result}
    fn remember_handle(&mut self,declaration:&str,payload:&str){if let Some((declaration,payload))=Self::digest_bytes(declaration).zip(Self::digest_bytes(payload)){if self.handles.contains_key(&declaration)||self.handles.len()<72_000 {self.handles.insert(declaration,payload);}}}
    pub(super) fn declaration_path(item:&Item,owner:&str,verb:bool)->Result<String,String> {
        let header=item.header.trim();let (raw,params)=header.split_once('(').ok_or_else(||format!("unsupported procedure header {header}"))?;
        if params.rsplit_once(") as ").is_none()&&!params.ends_with(')'){return Err(format!("unsupported procedure header {header}"));}
        let raw=raw.trim_end_matches('/');
        if owner.is_empty(){if !raw.starts_with("/proc/")||raw[6..].contains('/') {return Err(format!("bootstrap only supports global procs: {header}"));}return Ok(raw.into());}
        let marker=if verb {"verb/"}else{"proc/"};
        let name=raw.strip_prefix(marker).or_else(||raw.strip_prefix(&format!("{owner}/{marker}"))).or_else(||raw.strip_prefix(&format!("{owner}/"))).or_else(||(!raw.contains('/')).then_some(raw)).ok_or_else(||format!("unsupported member procedure header {header}"))?;
        if name.is_empty()||name.contains('/'){return Err(format!("unsupported procedure name: {header}"));}
        Ok(if raw==format!("{owner}/{name}"){raw.to_owned()}else if raw==name {format!("{owner}/{name}")}else{format!("{owner}/{marker}{name}")})
    }
    fn declaration_candidate(&self,item:&Item)->Option<Arc<InvocationSyntax>> {
        let (_,declaration)=self.window_declarations.get(&(item as *const Item as usize))?;
        let payload=Self::digest_text(self.handles.get(&Self::digest_bytes(declaration)?)?);
        self.entries.get(&payload).or_else(||self.requested_syntax.get(&payload)).cloned()
    }
    fn declaration_key(item:&Item,path:&str)->String {
        fn relevant(node:&Item)->bool {let header=node.header.trim();header.starts_with("set ")||["var/static/","var/global/","var/const/"].iter().any(|prefix|header.starts_with(prefix))||node.children.iter().any(relevant)}
        fn items(hash:&mut Sha256,nodes:&[Item]) {
            hash.update((nodes.iter().filter(|node|relevant(node)).count() as u64).to_le_bytes());
            for item in nodes.iter().filter(|node|relevant(node)) {hash.update([item.kind as u8]);hash.update((item.header.len() as u64).to_le_bytes());hash.update(item.header.as_bytes());items(hash,&item.children);}
        }
        let mut hash=Sha256::new();hash.update(path.as_bytes());hash.update(item.header.as_bytes());
        items(&mut hash,&item.children);
        format!("{:x}",hash.finalize())
    }
    /// A declaration handle selects a candidate, never certifies inherited
    /// settings. `syntax` checks the complete current key, including its base.
    /// The bounded window is consumed immediately by the ordered allocator.
    pub(super) fn prefetch_syntax(&mut self,inputs:&[(&Item,&str,bool)]) {
        self.requested_syntax.clear(); self.requested_bytes=0;
        self.requested_encoded.clear();self.requested_encoded_bytes=0;
        self.window_declarations.clear();
        self.requested_signatures.clear();self.requested_signature_bytes=0;
        let Some(store)=self.store.clone() else {return;};
        let mut handles=Vec::new();
        let mut payloads=BTreeSet::new();
        for (item,owner,verb) in inputs {
            let Ok(path)=Self::declaration_path(item,owner,*verb) else {continue;};
            let key=Self::declaration_key(item,&path);
            self.window_declarations.insert(*item as *const Item as usize,(path,key.clone()));
            if let Some(identity)=Self::digest_bytes(&key).and_then(|key|self.handles.get(&key)).map(Self::digest_text) {
                if !self.entries.contains_key(&identity)&&!self.syntax_misses.contains(&identity){payloads.insert(Key::new(Self::namespace(),identity));}
            } else if !self.handle_misses.contains(&key) {handles.push(Key::new(Self::handles_namespace(),key));}
        }
        self.counters.batch_records+=handles.len();
        default_plans::read_stage_batch(&store,&handles,128,1024*1024,&mut |key,bytes| {
            if let Some(identity)=bytes.and_then(|bytes|String::from_utf8(bytes).ok()).filter(|identity|identity.len()==64&&identity.bytes().all(|b|b.is_ascii_hexdigit())) {
                self.remember_handle(&key.name,&identity);
                if !self.entries.contains_key(&identity)&&!self.syntax_misses.contains(&identity) {payloads.insert(Key::new(Self::namespace(),identity));}
            } else if self.handle_misses.len()<128_000 {self.handle_misses.insert(key.name.clone());}
        });
        let payloads:Vec<_>=payloads.into_iter().collect();
        self.counters.batch_records+=payloads.len();
        default_plans::read_stage_batch(&store,&payloads,1024*1024,8*1024*1024,&mut |key,bytes| {
            if let Some(bytes)=bytes {
                let charge=bytes.len().saturating_mul(3)+key.name.len()+128;
                if self.requested_bytes.saturating_add(charge)<=16*1024*1024 {
                    if let Ok(value)=rmp_serde::from_slice::<InvocationSyntax>(&bytes) {if value.key==key.name {self.requested_bytes+=charge;self.requested_syntax.insert(key.name.clone(),Arc::new(value));}}
                } else {
                    let charge=bytes.len()+key.name.len()+128;
                    if self.requested_encoded_bytes.saturating_add(charge)<=16*1024*1024 {self.requested_encoded_bytes+=charge;self.requested_encoded.insert(key.name.clone(),bytes);}
                }
            } else if self.syntax_misses.len()<128_000 {self.syntax_misses.insert(key.name.clone());}
        });
        let missing:Vec<_>=inputs.iter().copied().filter(|(item,_,_)|self.declaration_candidate(item).is_none()).collect();
        self.prefetch_signatures(&missing);
    }
    pub(super) fn prefetch_signatures(&mut self, inputs:&[(&Item,&str,bool)]) {
        let Some(store)=self.store.clone() else {return;};
        let keys:Vec<_>=inputs.iter().map(|(item,owner,verb)|crate::lower_cache::shared_binding_fingerprint(&(*owner,*verb,&item.header)))
            .collect::<BTreeSet<_>>().into_iter().filter(|key|!self.signatures.contains_key(key)&&!self.requested_signatures.contains_key(key)&&!self.signature_misses.contains(key)).map(|key|Key::new(Self::signature_namespace(),key)).collect();
        self.counters.batch_records+=keys.len();
        for keys in keys.chunks(4096) {
            default_plans::read_stage_batch(&store,keys,1024*1024,8*1024*1024,&mut |key,bytes| {
                if let Some(bytes)=bytes {
                    if let Ok(value)=rmp_serde::from_slice::<(String,Vec<ParsedParameter>)>(&bytes) {
                        let size=bytes.len()*3+key.name.len()+128;
                        if self.bytes.saturating_add(size)<=Self::LIMIT {self.bytes+=size;self.signatures.insert(key.name.clone(),Arc::new(value));}
                        else if self.requested_signature_bytes.saturating_add(size)<=16*1024*1024 {
                            self.requested_signature_bytes+=size;self.requested_signatures.insert(key.name.clone(),Arc::new(value));
                        }
                    }
                } else if self.signature_misses.len()<128_000 {self.signature_misses.insert(key.name.clone());}
            });
        }
    }
    pub(super) fn signature(
        &mut self,
        item: &Item,
        owner: &str,
        verb: bool,
    ) -> Result<(String, Vec<ParsedParameter>), String> {
        if let Some(candidate)=self.declaration_candidate(item) {
            self.counters.signature_hits+=1;return Ok((candidate.path.clone(),candidate.params.clone()));
        }
        let key = crate::lower_cache::shared_binding_fingerprint(&(owner, verb, &item.header));
        if let Some(value) = self.signatures.get(&key) {
            self.counters.signature_hits+=1;return Ok(value.as_ref().clone());
        }
        if let Some(value)=self.requested_signatures.get(&key) {self.counters.signature_hits+=1;return Ok(value.as_ref().clone());}
        self.counters.signature_misses+=1;
        if !self.signature_misses.contains(&key) {
            self.counters.point_reads+=1;
            if let Some(bytes)=self.store.as_ref().and_then(|store|store.read_many_bounded(&[Key::new(Self::signature_namespace(),&key)],1024*1024,1024*1024,None).ok()).and_then(|read|read.values.into_iter().next().flatten()) {
                if let Ok(value)=rmp_serde::from_slice::<(String,Vec<ParsedParameter>)>(&bytes) {
                    let size=bytes.len()*3+key.len()+128;
                    if self.bytes.saturating_add(size)<=Self::LIMIT {self.bytes+=size;self.signatures.insert(key.clone(),Arc::new(value.clone()));}
                    return Ok(value);
                }
            }
            if self.signature_misses.len()<128_000 {self.signature_misses.insert(key.clone());}
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
            self.signatures.insert(key.clone(), Arc::new(value.clone()));
        } else if self.requested_signature_bytes.saturating_add(size)<=16*1024*1024 {
            self.requested_signature_bytes+=size;
            self.requested_signatures.insert(key.clone(),Arc::new(value.clone()));
        }
        // Persistence is independent of whether the optional decoded cache has
        // room. Large projects must not repeatedly derive the uncached suffix.
        if let Ok(bytes) = rmp_serde::to_vec_named(&value) {
            self.queue_pending(format!("signature:{key}"), bytes);
            if self.pending_bytes>4*1024*1024 {self.flush();}
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
        // The requested declaration window already hashed settings/statics.
        // Include inherited metadata in the final identity, and only build the
        // projected AST if semantic derivation is actually necessary.
        let declaration_key=self.window_declarations.get(&(item as *const Item as usize))
            .filter(|(cached,_)|cached==path).map(|(_,key)|key.clone())
            .unwrap_or_else(||Self::declaration_key(item,path));
        let mut hash=Sha256::new();hash.update(declaration_key.as_bytes());
        hash.update(serde_json::to_vec(&base).map_err(|e|e.to_string())?);
        let key=format!("{:x}",hash.finalize());
        if let Some(value) = self.entries.get(&key) {
            self.counters.syntax_hits+=1;return Ok(Arc::clone(value));
        }
        if let Some(value)=self.requested_syntax.get(&key) {self.counters.syntax_hits+=1;return Ok(Arc::clone(value));}
        if let Some(bytes)=self.requested_encoded.remove(&key) {
            self.requested_encoded_bytes=self.requested_encoded_bytes.saturating_sub(bytes.len()+key.len()+128);
            if let Ok(value)=rmp_serde::from_slice::<InvocationSyntax>(&bytes) {if value.key==key {self.counters.syntax_hits+=1;return Ok(Arc::new(value));}}
        }
        self.counters.syntax_misses+=1;
        if self.disk_syntax_ready && !self.syntax_misses.contains(&key) {
            self.counters.point_reads+=1;
            if let Some(bytes)=self.store.as_ref().and_then(|store|store.read_many_bounded(&[Key::new(Self::namespace(),&key)],1024*1024,1024*1024,None).ok()).and_then(|read|read.values.into_iter().next().flatten()) {
                if let Ok(value)=rmp_serde::from_slice::<InvocationSyntax>(&bytes) {
                    let value=Arc::new(value);self.queue_pending(format!("handle:{declaration_key}"),key.as_bytes().to_vec());self.retain(key,Arc::clone(&value),bytes.len());return Ok(value);
                }
            }
        }
        let declarations=invocation_declaration_projection(&item.children);
        let (metadata, mut body) = proc_metadata_from_base(&declarations, base)?;
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
        if let Ok(bytes) = rmp_serde::to_vec_named(value.as_ref()) {
            let size = bytes.len();
            if size <= 1024 * 1024 {
                self.queue_pending(key.clone(), bytes);
                self.queue_pending(format!("handle:{declaration_key}"),key.as_bytes().to_vec());
                self.retain(key, Arc::clone(&value), size);
                if self.pending_bytes > 4 * 1024 * 1024 {
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
                self.counters.frame_hits+=1;return (Arc::clone(cached), digest.clone());
            }
        }
        self.counters.frame_misses+=1;
        let overlay = Arc::new(overlay);
        // Hash the immutable semantic fragment directly, without constructing
        // and cloning a complete LowerBindings solely for serialization.
        let digest=crate::lower_cache::shared_binding_fingerprint(&(&syntax.path,&syntax.params,&overlay));
        {
            let mut updated = syntax.as_ref().clone();
            updated.frame = Some((Arc::clone(&overlay), digest.clone()));
            if let Ok(bytes) = rmp_serde::to_vec_named(&updated) {
                // The added immutable frame has a known typed footprint; do
                // not serialize the original syntax a second time to measure it.
                let strings=|values:&[String]|values.iter().map(|value|value.capacity()+std::mem::size_of::<String>()).sum::<usize>();
                let pairs=|values:&[(String,String)]|values.iter().map(|(name,value)|name.capacity()+value.capacity()+std::mem::size_of::<(String,String)>()).sum::<usize>();
                let extra=digest.capacity()+std::mem::size_of::<InvocationOverlay>()+overlay.current_type_path.as_ref().map_or(0,String::capacity)+strings(&overlay.fields)+strings(&overlay.globals)+strings(&overlay.global_procs)+strings(&overlay.hidden_owner_fields)+pairs(&overlay.field_types)+pairs(&overlay.global_types);
                let retained=self.entries.contains_key(&syntax.key);
                let requested_charge=if self.requested_syntax.contains_key(&syntax.key){extra}else{bytes.len().saturating_mul(3)+syntax.key.len()+128};
                if (retained&&self.bytes.saturating_add(extra)<=Self::LIMIT)
                    || (!retained&&self.requested_bytes.saturating_add(requested_charge)<=16*1024*1024) {
                    if retained {self.bytes+=extra;self.entries.insert(syntax.key.clone(),Arc::new(updated));}
                    else {self.requested_bytes+=requested_charge;self.requested_syntax.insert(syntax.key.clone(),Arc::new(updated));}
                }
                // Portable frame artifacts must survive even when the optional
                // decoded cache is full. Otherwise uncached suffixes repeatedly
                // restore frame-less syntax and rederive their frame every edit.
                if bytes.len()<=1024*1024 {
                    self.queue_pending(syntax.key.clone(),bytes);
                    if self.pending_bytes>4*1024*1024 {self.flush();}
                }
            }
        }
        (overlay, digest)
    }
    fn release_decoded(&mut self) {
        self.flush();
        self.entries.clear();self.signatures.clear();self.bytes=0;
        self.requested_syntax.clear();self.requested_bytes=0;
        self.requested_encoded.clear();self.requested_encoded_bytes=0;
        self.requested_signatures.clear();self.requested_signature_bytes=0;
        self.window_declarations.clear();
    }
    fn retain(&mut self, key: String, value: Arc<InvocationSyntax>, wire_bytes: usize) {
        let size = wire_bytes.saturating_mul(2) + key.len() + 128;
        if self.bytes.saturating_add(size) <= Self::LIMIT {
            self.bytes += size;
            self.entries.insert(key, value);
        }
    }
    fn queue_pending(&mut self,key:String,bytes:Vec<u8>) {
        if let Some(handle)=key.strip_prefix("handle:") {if let Ok(payload)=std::str::from_utf8(&bytes){self.remember_handle(handle,payload);}self.handle_misses.remove(handle);}
        else if let Some(signature)=key.strip_prefix("signature:") {self.signature_misses.remove(signature);}
        else {self.syntax_misses.remove(&key);}
        self.pending_bytes=self.pending_bytes.saturating_add(bytes.len());
        if let Some(old)=self.pending.insert(key,bytes) {self.pending_bytes=self.pending_bytes.saturating_sub(old.len());}
    }
    fn flush(&mut self) {
        if self.pending.is_empty(){return;}
        let started=std::time::Instant::now();let records=self.pending.len();let bytes=self.pending_bytes;
        let Some(store) = &self.store else {
            self.pending.clear();self.pending_bytes=0;
            return;
        };
        let mut updates: Vec<_> = self
            .pending
            .iter()
            .map(|(key, bytes)| {
                if let Some(key) = key.strip_prefix("signature:") {
                    Change::Put(Key::new(Self::signature_namespace(), key), bytes.clone())
                } else if let Some(key) = key.strip_prefix("handle:") {
                    Change::Put(Key::new(Self::handles_namespace(), key), bytes.clone())
                } else {
                    Change::Put(Key::new(Self::namespace(), key), bytes.clone())
                }
            })
            .collect();
        updates.push(Change::Put(Key::new("declaration-fragment-ready",Self::namespace()),vec![1]));
        if store.commit(&[], &updates, None).is_ok() {
            self.pending.clear();self.pending_bytes=0;
        }
        if started.elapsed().as_millis()>100&&std::env::var_os("DM_BUILD_TRACE").is_some(){eprintln!("DM_BUILD_TRACE slow invocation publication: records={records} bytes={bytes} {:.3}s",started.elapsed().as_secs_f64());}
    }
    fn resident_bytes(&self) -> usize {
        self.bytes
            + self.handles.len()*112
            + self.requested_bytes + self.requested_encoded_bytes + self.requested_signature_bytes
            + (self.syntax_misses.len()+self.handle_misses.len())*128
            + self
                .pending
                .iter()
                .map(|(key, bytes)| key.capacity() + bytes.capacity() + 128)
                .sum::<usize>()
    }
    fn release_requested(&mut self) {
        self.requested_syntax.clear();self.requested_bytes=0;
        self.requested_encoded.clear();self.requested_encoded_bytes=0;
        self.requested_signatures.clear();self.requested_signature_bytes=0;
    }
}

#[derive(Default)]
pub(super) struct OwnerFrameQueries {
    snapshot_revision: String,
    current: HashMap<u32, (String, Arc<dm_codegen_byond::OwnerLowerBindings>,usize)>,
    current_bytes: usize,
    records: BTreeMap<String, (String, Arc<dm_codegen_byond::OwnerLowerBindings>, usize)>,
    bytes: usize,
    store: Option<Store>,
    pending: BTreeMap<String, Vec<u8>>,
    pending_bytes: usize,
}
#[derive(Serialize, Deserialize)]
struct OwnerFrameWire {
    path: String,
    identity: String,
    parent_identity: Option<String>,
    local: dm_codegen_byond::OwnerLowerBindings,
}
impl OwnerFrameQueries {
    const LIMIT: usize = 16 * 1024 * 1024;
    fn namespace() -> String {
        format!("owner-frame-recipes-v2-{}", env!("DM_EMISSION_FINGERPRINT"))
    }
    fn compose(parent:Option<&Arc<dm_codegen_byond::OwnerLowerBindings>>,local:&dm_codegen_byond::OwnerLowerBindings)->Arc<dm_codegen_byond::OwnerLowerBindings> {
        let mut frame=parent.map(|frame|frame.as_ref().clone()).unwrap_or_default();
        // im inserts can copy a shared tree path even for equal entries. Keep
        // inherited roots intact when local recipes repeat builtin inventories.
        for name in &local.fields {
            if !frame.fields.contains(name) { frame.fields.insert(name.clone()); }
        }
        for (name,ty) in &local.field_types {
            if frame.field_types.get(name) != Some(ty) {
                frame.field_types.insert(name.clone(),ty.clone());
            }
        }
        Arc::new(frame)
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
        queries
    }
    fn flush(&mut self) {
        let Some(store) = &self.store else {
            self.pending.clear();
            self.pending_bytes = 0;
            return;
        };
        let changes: Vec<_> = self
            .pending
            .iter()
            .map(|(key, bytes)| Change::Put(Key::new(Self::namespace(), key), bytes.clone()))
            .collect();
        if store.commit(&[], &changes, None).is_ok() {
            self.pending.clear();
            self.pending_bytes = 0;
        }
    }
    fn resident_bytes(&self) -> usize {
        // Current and cross-revision indexes borrow the same immutable frames.
        // Charge their payload once, while charging each index entry separately.
        let mut seen=HashSet::new();
        let mut bytes=self.pending.iter().map(|(key,bytes)|key.capacity()+bytes.capacity()+128).sum::<usize>();
        for (path,(identity,frame,charge)) in &self.records {
            bytes+=path.capacity()+identity.capacity()+128;
            if seen.insert(Arc::as_ptr(frame) as usize) {bytes+=*charge;}
        }
        for (identity,frame,charge) in self.current.values() {
            bytes+=identity.capacity()+96;
            if seen.insert(Arc::as_ptr(frame) as usize) {bytes+=*charge;}
        }
        bytes
    }
    /// Resolved ancestor memoization is needed during a generation, but its
    /// unbounded inventory must not survive publication and evict the frontend.
    pub(super) fn release_generation(&mut self) {
        self.current.clear();self.current.shrink_to_fit();self.current_bytes=0;
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
        charge:usize,
    ) {
        // A generation must memoize every resolved owner. Capping this map
        // repeats ancestry resolution for every procedure after saturation.

        if !self.current.contains_key(&owner)
        {
            self.current_bytes += charge;
            self.current
                .insert(owner, (identity.to_owned(), Arc::clone(frame),charge));
        }
    }
    /// A frame depends only on its local field inventory/type annotations and
    /// its parent's resolved frame. Values/defaults and physical table IDs are
    /// deliberately excluded, so unrelated structural edits preserve the query.
    pub(super) fn resolve(
        &mut self,
        owner: u32,
        dmb: &impl dm_output::assembly::AssemblyImage,
        shared: &SharedLowerBindings,
    ) -> Result<Arc<dm_codegen_byond::OwnerLowerBindings>,String> {
        self.resolve_inner(owner, dmb, shared, &mut HashSet::new()).map(|(_,frame)|frame)
    }
    fn resolve_inner(
        &mut self,
        owner: u32,
        dmb: &impl dm_output::assembly::AssemblyImage,
        shared: &SharedLowerBindings,
        visited: &mut HashSet<u32>,
    ) -> Result<(String, Arc<dm_codegen_byond::OwnerLowerBindings>),String> {
        if let Some(value) = self.current.get(&owner) {
            return Ok((value.0.clone(),Arc::clone(&value.1)));
        }
        if !visited.insert(owner) {
            return Ok((String::new(), Arc::new(Default::default())));
        }
        let class = dmb.classes().get(owner as usize).ok_or_else(||format!("owner class out of range: {owner}"))?;
        let path = String::from_utf8_lossy(dmb.string(class.path_string_id()).unwrap_or_default())
            .into_owned();
        let parent = class.parent_class_id();
        let inherited = if parent != 0xffff {
            Some(self.resolve_inner(parent, dmb, shared, visited)?)
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
        if let Some(fields)=shared.known_member_fields.get(&path) {
            local.fields.extend(fields.iter().cloned());
        } else if let Some(declarations) = dmb.class_variable_declarations(owner as usize).map_err(|error|error.to_string())? {
            for (id, _) in declarations {
                if let Some(name) = dmb.string(dmb.variables().get(id as usize).ok_or_else(||format!("owner variable out of range: {id}"))?.name) {
                    local
                        .fields
                        .insert(String::from_utf8_lossy(name).into_owned());
                }
            }
        }
        // Physical class declarations can repeat inherited inventories. Keep
        // only semantic additions/overrides, so descendant roots share the
        // parent allocation rather than replacing it with identical strings.
        if let Some((_,parent))=&inherited {
            local.fields.retain(|name|!parent.fields.contains(name));
            local.field_types.retain(|name,ty|parent.field_types.get(name)!=Some(ty));
        }
        let mut ordered_types: Vec<_> = local.field_types.iter().collect();
        ordered_types.sort_by(|a, b| a.0.cmp(b.0));
        let identity = crate::lower_cache::shared_binding_fingerprint(&(
            &path,
            &local.fields,
            &ordered_types,
            inherited.as_ref().map(|(digest, _)| digest),
        ));
        // Local rows and inherited identity are already derived and validated.
        // A per-owner disk read only repeats these inputs and costs a redb open;
        // persistent root composition is cheaper than restoring a recipe here.
        if let Some((stored, frame, charge)) = self.records.get(&path) {
            if stored == &identity {
                let charge=*charge;
                let frame = Arc::clone(frame);
                self.retain_current(owner, &identity, &frame,charge);
                visited.remove(&owner);
                return Ok((identity, frame));
            }
        }
        let local=dm_codegen_byond::OwnerLowerBindings {
            fields:local.fields.into_iter().collect(),field_types:local.field_types.into_iter().collect(),
        };
        let charge=Self::charge(&path,&identity,&local);
        let frame=Self::compose(inherited.as_ref().map(|(_,frame)|frame),&local);
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
                parent_identity: inherited.as_ref().map(|(identity,_)|identity.clone()),
                local,
            }) {
                if bytes.len() <= Self::LIMIT / 4 {
                    self.pending_bytes = self.pending_bytes.saturating_add(bytes.len());
                    if let Some(old) = self.pending.insert(identity.clone(), bytes) {
                        self.pending_bytes = self.pending_bytes.saturating_sub(old.len());
                    }
                }
                if self.pending_bytes > 4 * 1024 * 1024 {
                    self.flush();
                }
            }
            self.bytes += charge;
            self.records
                .insert(path, (identity.clone(), Arc::clone(&frame), charge));
        }
        self.retain_current(owner, &identity, &frame,charge);
        visited.remove(&owner);
        Ok((identity, frame))
    }
}

pub(super) struct FrozenSkeleton {
    pub image: Dmb,
    pub metadata: SkeletonMetadata,
    resident_charge: AtomicUsize,
}

impl FrozenSkeleton {
    pub(super) fn new(image: Dmb, mut metadata: SkeletonMetadata) -> Self {
        // Invocation-local overlays are often identical for every procedure on
        // an owner. Hash by value while retaining one immutable allocation.
        let mut overlays=HashMap::<Arc<InvocationOverlay>,Arc<InvocationOverlay>>::new();
        for plan in &mut metadata.invocations {
            plan.bindings=Arc::clone(overlays.entry(Arc::clone(&plan.bindings)).or_insert_with(||Arc::clone(&plan.bindings)));
        }
        let charge = skeleton_heap(&image, &metadata);
        Self {
            image,
            metadata,
            resident_charge: AtomicUsize::new(charge),
        }
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
    fn nested_map(items: &im::OrdMap<String, im::OrdMap<String, String>>) -> usize {
        items.len()*96
            + items
                .iter()
                .map(|(name, members)| name.capacity() + members.len()*96 + members.iter().map(|(key,value)|key.capacity()+value.capacity()).sum::<usize>())
                .sum::<usize>()
    }
    fn nested_set(items: &im::OrdMap<String, im::OrdSet<String>>) -> usize {
        items.len()*96
            + items
                .iter()
                .map(|(name, members)| name.capacity() + members.iter().map(|value|value.capacity()+64).sum::<usize>())
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
    bytes += image.lists.iter().map(|words| words.capacity() * std::mem::size_of::<u32>()).sum::<usize>();
    bytes += metadata.strings.resident_bytes();
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
    for recipes in [&metadata.initializers,&metadata.modified_initializers] {
        bytes+=vec_heap(recipes)+recipes.iter().map(|recipe|recipe.key.path.capacity()+recipe.descriptor.body_digest.capacity()+recipe.descriptor.frame_digest.capacity()+recipe.source.len()+64).sum::<usize>();
    }
    bytes += vec_heap(&metadata.invocations);
    let mut overlay_seen=HashSet::new();
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
        if !overlay_seen.insert(Arc::as_ptr(overlay) as usize) {continue;}
        bytes += std::mem::size_of::<InvocationOverlay>()+overlay
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
        &shared.field_types,
        &shared.global_types,
        &shared.string_constants,
    ] {
        bytes += text_map(map);
    }
    for set in [&shared.fields, &shared.globals, &shared.global_procs] {
        bytes += text_set(set);
    }
    bytes += shared.parent_types.iter().map(|(key,value)|key.capacity()+value.capacity()+96).sum::<usize>();
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
    pub(super) emission_plans: super::emission_plans::EmissionPlans,
    pub(super) procedure_fragments: super::procedure_fragments::ProcedureFragments,
    pub(super) invocation_fragments: InvocationFragments,
    pub(super) owner_bindings:OwnerBindingQueries,
    pub(super) owner_frames: Arc<Mutex<OwnerFrameQueries>>,
    pub maps: crate::maps::MapInitializerSession,
    pub active_keys: BTreeSet<crate::ProcKey>,
    project: Option<std::path::PathBuf>,
    configuration: Option<String>,
    skeleton: Option<(String, Arc<FrozenSkeleton>)>,
    declaration_base: Option<(String, Arc<Vec<u8>>)>,
    pub(super) declaration_inputs: Option<DeclarationInputs>,
    pub(super) semantic_declarations: Option<Arc<semantic_declarations::SemanticDeclarations>>,
    pub(super) semantic_base_revision: Option<String>,
    pub skeleton_revision: String,
    pub skeleton_hits: usize,
    pub skeleton_misses: usize,
    pub emission_stats: ArtifactReuseStats,
}

impl CanonicalSession {
    pub(super) fn declaration_base(&mut self,key:&str,root:Option<&Path>)->Option<DeclarationBase> {
        let bytes=if let Some((cached,bytes))=&self.declaration_base { if cached==key {Some(Arc::clone(bytes))} else {None} } else {None};
        let bytes=bytes.or_else(||declaration_base::load(root?,key).map(Arc::new))?;
        let base=declaration_base::decode(&bytes)?;
        self.declaration_base=Some((key.to_owned(),bytes));Some(base)
    }
    pub(super) fn store_declaration_base(&mut self,key:String,base:&DeclarationBase,root:Option<&Path>) {
        if let Some(bytes)=declaration_base::encode(base) {
            if let Some(root)=root {declaration_base::store(root,&key,&bytes);}
            self.declaration_base=Some((key,Arc::new(bytes)));
        }
    }
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
        self.declaration_inputs = None;
        self.semantic_declarations = None;
        self.semantic_base_revision = None;
        self.maps = crate::maps::MapInitializerSession::open(&root, &project_identity);
        self.skeleton = None;
        self.declaration_base = None;
        self.output_validation = Default::default();
        self.emission_plans = super::emission_plans::EmissionPlans::open(&root, &project_identity);
        self.procedure_fragments = super::procedure_fragments::ProcedureFragments::open(&root, &project_identity);
        self.output_projections =
            Arc::new(dm_codegen_byond::relocatable::OutputProjectionCache::open(
                &root,
                env!("DM_EMISSION_FINGERPRINT"),
            ));
        self.invocation_fragments = InvocationFragments::open(&root);
        self.owner_bindings.bind(&root);
        self.owner_frames = Arc::new(Mutex::new(OwnerFrameQueries::open(&root)));
        const_eval::bind_cache(&root);
        semantic_declarations::bind_cache(&root);
        default_plans::bind_cache(&root);
        declaration_operations::bind(&root);
        self.project = Some(identity);
        self.configuration = Some(configuration.to_owned());
    }

    pub(crate) fn resident_bytes(&self) -> usize {
        // Prefixes with equal content identities share one immutable allocation
        // across sessions. Divide its conservative charge among live Arc owners.
        self.graph
            .resident_bytes()
            .saturating_add(self.declaration_base.as_ref().map_or(0,|(_,bytes)|bytes.capacity()))
            .saturating_add(self.maps.resident_bytes())
            .saturating_add(self.declaration_inputs.as_ref().map_or(0,DeclarationInputs::resident_bytes))
            .saturating_add(self.semantic_declarations.as_ref().map_or(0,|model|model.resident_bytes().div_ceil(Arc::strong_count(model).max(1))))
            .saturating_add(self.output_validation.resident_bytes())
            .saturating_add(self.output_projections.resident_bytes())
            .saturating_add(self.emission_plans.resident_bytes())
            .saturating_add(self.procedure_fragments.resident_bytes())
            .saturating_add(self.invocation_fragments.resident_bytes())
            .saturating_add(self.owner_bindings.resident_bytes())
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
        self.emission_plans.flush();
        self.procedure_fragments.flush();
        self.invocation_fragments.flush();
        self.invocation_fragments.release_requested();
        {
            let mut owners = self.owner_frames.lock().unwrap_or_else(|e| e.into_inner());
            owners.flush();
            owners.release_generation();
        }
        const_eval::flush_cache();
        semantic_declarations::flush_cache();
        default_plans::flush_cache();
        declaration_operations::flush();
        if std::env::var_os("DM_BUILD_TRACE").is_some() {
            eprintln!("DM_BUILD_TRACE canonical retained: frozen={} invocation={} owner={} semantic={} declarations={} maps={}",
                self.skeleton.as_ref().map_or(0,|(_,skeleton)|skeleton.resident_charge.load(Ordering::Relaxed)),
                self.invocation_fragments.resident_bytes(),
                self.owner_frames.lock().unwrap_or_else(|error|error.into_inner()).resident_bytes(),
                self.semantic_declarations.as_ref().map_or(0,|model|model.resident_bytes()),
                self.declaration_inputs.as_ref().map_or(0,DeclarationInputs::resident_bytes),self.maps.resident_bytes());
        }
    }
    /// Release duplicated encoding buffers before compact reuse handles and
    /// admitted procedure recipes. The pool can apply stronger pressure later.
    pub(crate) fn release_transient_output_buffers(&mut self) -> usize {
        let before = self.resident_bytes();
        let _ = self.output_projections.flush();
        self.output_projections.clear();
        self.output_validation.clear();
        self.emission_plans.clear();
        self.invocation_fragments.release_decoded();
        self.procedure_fragments.trim_transient();
        before.saturating_sub(self.resident_bytes())
    }
    /// This compressed replay image is also durable on disk. It is needed only
    /// when declarations change, while admitted procedure rows serve every edit.
    pub(crate) fn release_declaration_replay_buffer(&mut self) -> usize {
        self.declaration_base.take().map_or(0, |(_, bytes)| bytes.capacity())
    }
    pub(crate) fn trim_output_recipe_bytes(&mut self, bytes: usize) -> usize {
        let target = self.procedure_fragments.decoded_bytes().saturating_sub(bytes);
        self.procedure_fragments.trim_to(target)
    }
    /// Output projections are expendable accelerators. Retain compact semantic
    /// owner/invocation fragments when releasing output buffers under pressure.
    pub(crate) fn release_auxiliary_caches(&mut self) -> usize {
        let before = self.resident_bytes();
        let _ = self.output_projections.flush();
        self.output_projections.clear();
        self.output_validation.clear();
        self.declaration_base = None;
        self.emission_plans.clear();
        self.procedure_fragments.clear_decoded();
        // These are optional duplicate decoded declaration fragments; frozen
        // plans and addressed disk handles retain the authoritative inputs.
        self.invocation_fragments.release_decoded();
        // Compact handles are optional candidate selectors too. Release them
        // under pressure before sacrificing the frontend dependency graph.
        self.invocation_fragments.handles.clear();
        self.owner_bindings.clear();
        before.saturating_sub(self.resident_bytes())
    }
    /// Final pool-pressure fallback drops only the immutable prefix. Procedure
    /// identities, facts and prepared inputs survive its later reconstruction.
    pub(crate) fn release_skeleton(&mut self) -> usize {
        let before = self.resident_bytes();
        self.skeleton = None;
        self.declaration_base = None;
        before.saturating_sub(self.resident_bytes())
    }
    pub(crate) fn bind_project(&mut self, project: &Path, cache_root: &Path) {
        let identity = std::fs::canonicalize(project).unwrap_or_else(|_| project.to_owned());
        if self.project.as_ref() == Some(&identity) {
            return;
        }
        self.graph = crate::ProjectProcedureGraph::open(cache_root, &identity.to_string_lossy());
        self.declaration_inputs = None;
        self.semantic_declarations = None;
        self.semantic_base_revision = None;
        self.maps =
            crate::maps::MapInitializerSession::open(cache_root, &identity.to_string_lossy());
        self.skeleton = None;
        self.declaration_base = None;
        self.output_validation = Default::default();
        self.emission_plans = super::emission_plans::EmissionPlans::open(cache_root, &identity.to_string_lossy());
        self.procedure_fragments = super::procedure_fragments::ProcedureFragments::open(cache_root, &identity.to_string_lossy());
        self.output_projections =
            Arc::new(dm_codegen_byond::relocatable::OutputProjectionCache::open(
                cache_root,
                env!("DM_EMISSION_FINGERPRINT"),
            ));
        self.invocation_fragments = InvocationFragments::open(cache_root);
        self.owner_bindings.bind(cache_root);
        self.owner_frames = Arc::new(Mutex::new(OwnerFrameQueries::open(cache_root)));
        const_eval::bind_cache(cache_root);
        semantic_declarations::bind_cache(cache_root);
        default_plans::bind_cache(cache_root);
        declaration_operations::bind(cache_root);
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
        // Keep semantic map roots/dependency indexes, but release the obsolete
        // physical image before composing a structural generation. Otherwise
        // old and new declaration table buffers coexist until store() replaces it.
        self.skeleton = None;
        self.declaration_base = None;
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
        let value = skeleton_fragments::load(root?, key)?;
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
        semantic_declarations::flush_cache();
        default_plans::flush_cache();
        declaration_operations::flush();
        if let Some(root) = root { let _ = skeleton_fragments::store(root, &key, &value); }
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
    ast: &dm_syntax::AstFile, modified: &ModifiedTypes, builtins: &[u8], world: &str,
    resource_ids: &HashMap<String,u32>, debug: bool,
) -> String {
    skeleton_key_roots(&[&ast.items],modified,builtins,world,resource_ids,debug,false)
}

pub(super) fn skeleton_key_fragments(
    fragments: &[(usize,Arc<dm_syntax::AstFile>)], modified: &ModifiedTypes,
    builtins: &[u8], world: &str, resource_ids: &HashMap<String,u32>, debug: bool,
) -> String {
    let roots: Vec<&[Item]> = fragments.iter().map(|(_,ast)|ast.items.as_slice()).collect();
    skeleton_key_roots(&roots,modified,builtins,world,resource_ids,debug,true)
}

fn skeleton_key_roots(
    roots: &[&[Item]], modified: &ModifiedTypes, builtins: &[u8], world: &str,
    resource_ids: &HashMap<String,u32>, debug: bool, virtual_aliases: bool,
) -> String {
    fn node_hash(hash: &mut Sha256,node: &Item,modified: Option<&ModifiedTypes>) {
        let mut header = std::borrow::Cow::Borrowed(node.header.as_str());
        if let Some(modified) = modified.filter(|modified|!modified.aliases.is_empty()) {
            let mut edits=Vec::new();
            for span in modified_spans(&node.header) {
                if let Some(path)=modified.aliases.get(&modified_key(&node.header[span.range()])) { edits.push((span,path)); }
            }
            if !edits.is_empty() { for (span,path) in edits.into_iter().rev() { header.to_mut().replace_range(span.range(),path); } }
        }
        hash.update([node.kind as u8]);
        hash.update((header.len() as u64).to_le_bytes());
        hash.update(header.as_bytes());
        items(hash,&node.children,modified);
    }
    fn items(hash: &mut Sha256,nodes: &[Item],modified: Option<&ModifiedTypes>) {
        hash.update((nodes.len() as u64).to_le_bytes());
        for node in nodes { node_hash(hash,node,modified); }
    }
    let mut hash = Sha256::new();
    hash.update(b"canonical-skeleton-v3\0");
    hash.update(env!("DM_EMISSION_FINGERPRINT").as_bytes());
    hash.update(Sha256::digest(builtins));
    hash.update(world.as_bytes());
    hash.update([u8::from(debug)]);
    let count: usize = roots.iter().map(|nodes| nodes.len()).sum();
    hash.update((count as u64).to_le_bytes());
    for nodes in roots { for node in *nodes { node_hash(&mut hash,node,virtual_aliases.then_some(modified)); } }
    items(&mut hash, &modified.declarations, None);
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
