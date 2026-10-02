//! Immutable declaration templates and exact inherited metadata queries.
//! Physical allocation is deliberately outside this semantic database.
use super::*;
use std::collections::VecDeque;

type Named = (String, String, bool);
#[derive(Clone, PartialEq, Eq, PartialOrd, Ord, Hash, Serialize, Deserialize)]
enum MetadataRead { Parent(String), Declaration(Named), Native(Named), Resolved(Named) }
#[derive(Clone, Serialize, Deserialize)]
struct MetadataRecord {
    reads: Vec<(MetadataRead, String)>,
    parent_identity: String,
    value: Option<Arc<ProcMetadata>>,
    identity: String,
    semantic_identity:String,
}
struct Declaration<'a> { item: &'a Item, identity: String }
/// Source-order publication overlays the frozen declaration index. A previously
/// published override has the same precedence as the original ordered resolver.
pub(crate) struct MetadataContext<'a,'debug> {
    source_debug:Option<&'debug crate::source_debug::SourceDebugIndex<'debug>>,
    parents: HashMap<String, Option<String>>,
    declarations: HashMap<Named, Declaration<'a>>,
    descriptors: HashMap<usize,(String,String)>,
    native: HashMap<Named, Arc<ProcMetadata>>,
    observations: HashMap<MetadataRead, String>,
    current: HashMap<Named, Arc<MetadataRecord>>,
    published: HashMap<Named, Arc<MetadataRecord>>,
    dependents: HashMap<Named, HashSet<Named>>,
    generation:u64,
    default_metadata:Arc<ProcMetadata>,
    default_identity:String,
    default_semantic_identity:String,
    absent_identity:String,
}
impl<'a,'debug> MetadataContext<'a,'debug> {
    pub(crate) fn new(dmb:&Dmb,pending:&[PendingProc<'a>],source_debug:Option<&'debug crate::source_debug::SourceDebugIndex<'debug>>)->Result<Self,String> {
        let mut parents=HashMap::new();let mut native=HashMap::new();
        for class in &dmb.classes {
            let Some(owner)=dmb.string(class.path_string_id()).and_then(|s|std::str::from_utf8(s).ok())else{continue;};
            let parent=dmb.classes.get(class.parent_class_id() as usize).and_then(|p|dmb.string(p.path_string_id())).and_then(|s|std::str::from_utf8(s).ok()).map(str::to_owned);
            parents.insert(owner.to_owned(),parent);
            for (slot,verb) in [(0,true),(1,false)] {
                if let Some(ids)=dmb.lists.get(class.lists_and_procs[slot] as usize) {
                    // Reverse lookup selects the last native same-name row.
                    for id in ids {if let Some(proc)=dmb.procs.get(*id as usize) {
                        if let Some(path)=dmb.string(proc.strings[0]).and_then(|s|std::str::from_utf8(s).ok()) {
                            native.insert((owner.to_owned(),path.rsplit('/').next().unwrap_or("").to_owned(),verb),Arc::new(proc_metadata(&[],Some((dmb,proc)))?.0));
                        }
                    }}
                }
            }
        }
        let mut declarations=HashMap::new();let mut descriptors=HashMap::new();
        for proc in pending {
            let path=InvocationFragments::declaration_path(proc.item,&proc.owner_path,proc.verb)
                .map_err(|reason|source_error(source_debug,proc.span().start,&proc.item.header,&reason))?;
            let identity=InvocationFragments::declaration_key(proc.item,&path);
            descriptors.insert(proc.item as *const Item as usize,(path.clone(),identity.clone()));
            if proc.owner.is_none(){continue;}
            declarations.insert((proc.owner_path.clone(),path.rsplit('/').next().unwrap_or("").to_owned(),proc.verb),Declaration {item:proc.item,identity});
        }
        let default_metadata=Arc::new(proc_metadata(&[],None)?.0);
        let default_identity=crate::lower_cache::shared_binding_fingerprint(default_metadata.as_ref());
        let default_semantic_identity=crate::lower_cache::shared_binding_fingerprint(&Some(default_metadata.as_ref()));
        let absent_identity=crate::lower_cache::shared_binding_fingerprint(&Option::<&ProcMetadata>::None);
        static NEXT_MODEL:std::sync::atomic::AtomicU64=std::sync::atomic::AtomicU64::new(1);
        let generation=NEXT_MODEL.fetch_add(1,std::sync::atomic::Ordering::Relaxed);
        Ok(Self {source_debug,parents,declarations,descriptors,native,observations:HashMap::new(),current:HashMap::new(),published:HashMap::new(),dependents:HashMap::new(),generation,default_metadata,default_identity,default_semantic_identity,absent_identity})
    }
    fn observation_epoch(&self,key:&MetadataRead)->(u64,Option<[u8;32]>) {
        // The already authenticated semantic digest versions named outputs.
        // No duplicate project-sized publication/version inventory is needed.
        let version=if let MetadataRead::Resolved(name)=key {
            self.published.get(name).or_else(||self.current.get(name)).and_then(|record|InvocationFragments::digest_bytes(&record.semantic_identity))
        }else{None};
        (self.generation,version)
    }
    pub(crate) fn descriptor(&self,item:&Item)->&(String,String) { &self.descriptors[&(item as *const Item as usize)] }
    fn read(&mut self,key:&MetadataRead)->String {
        if !matches!(key,MetadataRead::Resolved(_)) {if let Some(value)=self.observations.get(key){return value.clone();}}
        let value=match key {
            MetadataRead::Parent(owner)=>crate::lower_cache::shared_binding_fingerprint(&self.parents.get(owner)),
            MetadataRead::Declaration(key)=>self.declarations.get(key).map(|d|d.identity.clone()).unwrap_or_else(||self.absent_identity.clone()),
            MetadataRead::Native(key)=>self.native.get(key).map_or_else(||self.absent_identity.clone(),|value|crate::lower_cache::shared_binding_fingerprint(&Some(value))),
            MetadataRead::Resolved(key)=>self.published.get(key).or_else(||self.current.get(key)).map(|record|record.semantic_identity.clone()).unwrap_or_default(),
        };
        if !matches!(key,MetadataRead::Resolved(_)){self.observations.insert(key.clone(),value.clone());}value
    }
    pub(crate) fn publish(&mut self,owner:&str,name:&str,verb:bool,metadata:&ProcMetadata,identity:&str) {
        let key=(owner.to_owned(),name.to_owned(),verb);
        let record=Arc::new(MetadataRecord {reads:Vec::new(),parent_identity:String::new(),value:Some(Arc::new(metadata.clone())),identity:identity.to_owned(),semantic_identity:crate::lower_cache::shared_binding_fingerprint(&Some(metadata))});
        let changed=self.current.get(&key).is_some_and(|old|old.semantic_identity!=record.semantic_identity);
        self.published.insert(key.clone(),record);
        if changed {
            let mut queue=vec![key];let mut seen=HashSet::new();
            while let Some(key)=queue.pop(){if !seen.insert(key.clone()){continue;}
                if let Some(children)=self.dependents.get(&key){queue.extend(children.iter().cloned());}
                if !self.published.contains_key(&key){self.current.remove(&key);}
            }
        }
    }
}
#[derive(Default)]
pub(crate) struct InvocationQueries {
    templates: HashMap<String, (Arc<InvocationTemplate>,usize)>,
    handles: HashMap<[u8;32], std::sync::Weak<InvocationTemplate>>,
    order: VecDeque<String>, bytes:usize,
    metadata: HashMap<Named, (Arc<MetadataRecord>,usize)>,
    metadata_bytes:usize,
    requested_metadata:HashMap<Named,Arc<MetadataRecord>>,requested_metadata_bytes:usize,
    metadata_negative:HashSet<[u8;32]>,template_negative:HashSet<[u8;32]>,
    validity: ValidityArena,
    store:Option<Store>,
    packed_metadata:Option<dm_store::PackedRecords>,
    pending_metadata:Vec<(String,Vec<u8>)>, pending:Vec<Change>, pending_bytes:usize,
    pub hits:usize,pub misses:usize,
    pub metadata_restored:usize,pub metadata_reused:usize,pub metadata_derived:usize,
    pub persistence_batches:usize,pub persistence_seconds:f64,
}
impl InvocationQueries {
    const LIMIT:usize=16*1024*1024;
    const WRITE_BATCH:usize=8*1024*1024;
    fn namespace()->String {format!("invocation-templates-v1-{}",env!("DM_EMISSION_FINGERPRINT"))}
    pub(crate) fn open(root:&Path)->Self {
        let store=Store::open(root.join("declaration-fragments.redb")).ok();
        let packed_metadata=store.clone().and_then(|store|dm_store::PackedRecords::new(store,format!("invocation-metadata-packed-v1-{}",env!("DM_EMISSION_FINGERPRINT"))).ok());
        Self {store,packed_metadata,..Default::default()}
    }
    pub(crate) fn reset_counters(&mut self){self.hits=0;self.misses=0;self.metadata_restored=0;self.metadata_reused=0;self.metadata_derived=0;self.persistence_batches=0;self.persistence_seconds=0.0;}
    pub(crate) fn clear(&mut self){if let Some(packed)=&self.packed_metadata{packed.clear_index_cache();}self.templates.clear();self.handles.clear();self.order.clear();self.bytes=0;self.metadata.clear();self.metadata_bytes=0;self.requested_metadata.clear();self.requested_metadata_bytes=0;self.metadata_negative.clear();self.template_negative.clear();self.validity.clear();}
    pub(crate) fn release_decoded(&mut self) {
        self.flush();if let Some(packed)=&self.packed_metadata{packed.clear_index_cache();}self.templates.clear();self.order.clear();self.bytes=0;
        self.metadata.clear();self.metadata_bytes=0;self.requested_metadata.clear();self.requested_metadata_bytes=0;self.validity.clear();
        // Weak handles continue selecting templates retained by frozen plans.
    }
    pub(crate) fn resident_bytes(&self)->usize {self.bytes+self.metadata_bytes+self.pending_bytes+self.packed_metadata.as_ref().map_or(0,dm_store::PackedRecords::retained_index_bytes)+self.handles.len()*96+self.validity.bytes+self.requested_metadata_bytes+(self.metadata_negative.len()+self.template_negative.len())*48}
    pub(crate) fn flush(&mut self){
        if self.pending.is_empty()&&self.pending_metadata.is_empty(){return;}
        let started=std::time::Instant::now();
        if let Some(packed)=&self.packed_metadata {
            let mut records=std::mem::take(&mut self.pending_metadata);
            for change in std::mem::take(&mut self.pending) {
                if let Change::Put(key,bytes)=change {records.push((format!("template:{}",key.name),bytes));}
            }
            if !records.is_empty(){let _=packed.write_many(&records,None);}
        }else if !self.pending.is_empty(){if let Some(store)=&self.store{let _=store.commit(&[],&self.pending,None);}}
        self.persistence_seconds+=started.elapsed().as_secs_f64();self.persistence_batches+=1;
        self.pending.clear();self.pending_metadata.clear();self.pending_bytes=0;
    }
    pub(crate) fn prefetch(&mut self,keys:&[String]) {
        // Old weak pointers are selectors, never a permanently growing history.
        if self.handles.len()>=72_000 {self.handles.retain(|_,template|template.strong_count()>0);}
        let Some(store)=self.store.clone()else{return;};
        let mut keys:Vec<_>=keys.iter().filter(|key|self.authored_candidate(key).is_none()&&!InvocationFragments::digest_bytes(key).is_some_and(|key|self.template_negative.contains(&key))).map(|key|Key::new(Self::namespace(),key)).collect();
        if let Some(packed)=self.packed_metadata.clone() {
            let mut restored=HashSet::new();
            for chunk in keys.chunks(1024) {
                let names:Vec<_>=chunk.iter().map(|key|format!("template:{}",key.name)).collect();
                read_packed_requested(&packed,&names,&mut |name,bytes| {
                    let key=name.strip_prefix("template:").unwrap_or(name);
                    if let Some(bytes)=bytes {if let Ok(template)=rmp_serde::from_slice::<InvocationTemplate>(&bytes) {if template.declaration_identity==key {self.admit(Arc::new(template),bytes.len());restored.insert(key.to_owned());}}}
                });
            }
            keys.retain(|key|!restored.contains(&key.name));
        }
        default_plans::read_stage_batch(&store,&keys,1024*1024,8*1024*1024,&mut |key,bytes| {
            if let Some(bytes)=bytes {if let Ok(template)=rmp_serde::from_slice::<InvocationTemplate>(&bytes) {if template.declaration_identity==key.name {self.admit(Arc::new(template),bytes.len());}}}
            else if self.template_negative.len()<72_000 {if let Some(digest)=InvocationFragments::digest_bytes(&key.name){self.template_negative.insert(digest);}}
        });
    }

    fn metadata_namespace()->String {format!("invocation-metadata-v2-{}",env!("DM_EMISSION_FINGERPRINT"))}
    fn metadata_addresses()->String {format!("invocation-metadata-addresses-v2-{}",env!("DM_EMISSION_FINGERPRINT"))}
    /// Hydrate only named parent queries requested by this ordered window. Both
    /// locator and immutable record reads are grouped; no namespace scans or
    /// per-ancestor database opens occur during semantic resolution.
    pub(crate) fn prefetch_metadata(&mut self,context:&MetadataContext,roots:&[(Option<&str>,&str,bool)]) {
        self.requested_metadata.clear();self.requested_metadata_bytes=0;
        let Some(store)=self.store.clone()else{return;};
        let mut requested=BTreeMap::new();
        for (owner,name,verb) in roots {
            let Some(owner)=owner else {continue;};
            let mut parent=context.parents.get(*owner).cloned().flatten();let mut visited=HashSet::new();
            while let Some(owner)=parent {
                if !visited.insert(owner.clone()){break;}
                let query=(owner.clone(),(*name).to_owned(),*verb);
                if context.current.contains_key(&query)||context.published.contains_key(&query){break;}
                let address=crate::lower_cache::shared_binding_fingerprint(&query);
                if !self.metadata.contains_key(&query)&&!InvocationFragments::digest_bytes(&address).is_some_and(|key|self.metadata_negative.contains(&key)) {
                    requested.insert(address,query.clone());
                }
                if !context.declarations.contains_key(&query)&&context.native.contains_key(&query){break;}
                parent=context.parents.get(&owner).cloned().flatten();
            }
        }
        if let Some(packed)=self.packed_metadata.clone() {
            let addresses:Vec<_>=requested.keys().cloned().collect();
            for chunk in addresses.chunks(1024) {
                read_packed_requested(&packed,chunk,&mut |address,bytes| {
                    if let Some(bytes)=bytes {
                        if let Some(query)=requested.get(address) {
                            if let Some(record)=decode_metadata_record(&bytes,query) {
                                let charge=bytes.len().saturating_mul(3)+192;
                                if self.requested_metadata_bytes+charge<=Self::LIMIT {
                                    self.requested_metadata_bytes+=charge;self.metadata_restored+=1;
                                    self.requested_metadata.insert(query.clone(),Arc::new(record));
                                    requested.remove(address);
                                }
                            }
                        }
                    }
                });
            }
        }
        let addresses:Vec<_>=requested.keys().map(|key|Key::new(Self::metadata_addresses(),key)).collect();
        let mut records=BTreeMap::new();
        default_plans::read_stage_batch(&store,&addresses,128,1024*1024,&mut |key,bytes| {
            if let Some(identity)=bytes.and_then(|bytes|String::from_utf8(bytes).ok()).filter(|identity|InvocationFragments::digest_bytes(identity).is_some()) {
                if let Some(query)=requested.get(&key.name){records.insert(identity,query.clone());}
            }else if self.metadata_negative.len()<128_000 {if let Some(digest)=InvocationFragments::digest_bytes(&key.name){self.metadata_negative.insert(digest);}}
        });
        let keys:Vec<_>=records.keys().map(|key|Key::new(Self::metadata_namespace(),key)).collect();
        default_plans::read_stage_batch(&store,&keys,1024*1024,8*1024*1024,&mut |key,bytes| {
            if let Some(bytes)=bytes {
                let charge=bytes.len().saturating_mul(3)+192;
                if self.requested_metadata_bytes+charge>Self::LIMIT{return;}
                if let Ok(record)=rmp_serde::from_slice::<MetadataRecord>(&bytes) {
                    // The portable witness/value checksum rejects damaged rows;
                    // consuming queries still validate every observed input.
                    let identity=crate::lower_cache::shared_binding_fingerprint(&(&record.reads,&record.parent_identity,record.value.as_ref()));
                    if record.identity==key.name&&identity==key.name&&record.semantic_identity==crate::lower_cache::shared_binding_fingerprint(&record.value) {
                        if let Some(query)=records.get(&key.name){self.requested_metadata_bytes+=charge;self.metadata_restored+=1;self.requested_metadata.insert(query.clone(),Arc::new(record));}
                    }
                }
            }
        });
    }
    fn admit(&mut self,template:Arc<InvocationTemplate>,wire:usize) {
        let key=template.declaration_identity.clone();
        if let Some(digest)=InvocationFragments::digest_bytes(&key) {self.template_negative.remove(&digest);if self.handles.len()<72_000||self.handles.contains_key(&digest){self.handles.insert(digest,Arc::downgrade(&template));}}
        if let Some((_,old_charge))=self.templates.remove(&key) {
            self.bytes=self.bytes.saturating_sub(old_charge);self.order.retain(|old|old!=&key);
        }
        let charge=wire.saturating_mul(3)+key.len()+128;
        if charge>Self::LIMIT{return;}
        while self.bytes.saturating_add(charge)>Self::LIMIT {
            let Some(old)=self.order.pop_front()else{break;};
            if let Some((_,charge))=self.templates.remove(&old){self.bytes=self.bytes.saturating_sub(charge);}
        }
        self.bytes+=charge;self.order.push_back(key.clone());self.templates.insert(key,(template,charge));
    }
    pub(crate) fn remember(&mut self,template:Arc<InvocationTemplate>) {
        let Ok(bytes)=rmp_serde::to_vec_named(template.as_ref())else{return;};
        self.admit(Arc::clone(&template),bytes.len());
        if bytes.len()>1024*1024{return;}
        if self.pending_bytes+bytes.len()>Self::WRITE_BATCH||self.pending.len()+self.pending_metadata.len()>=60_000{self.flush();}
        self.pending_bytes+=bytes.len();self.pending.push(Change::Put(Key::new(Self::namespace(),&template.declaration_identity),bytes));
    }
    pub(crate) fn authored_candidate(&self,key:&str)->Option<Arc<InvocationTemplate>> {
        self.templates.get(key).map(|(template,_)|Arc::clone(template)).or_else(||InvocationFragments::digest_bytes(key).and_then(|key|self.handles.get(&key)).and_then(std::sync::Weak::upgrade))
    }
    pub(crate) fn candidate(&mut self,key:&str,inherited:&str)->Option<Arc<InvocationTemplate>> {
        let value=self.authored_candidate(key).filter(|value|value.inherited_identity==inherited);
        if value.is_some(){self.hits+=1;}else{self.misses+=1;}value
    }
    pub(crate) fn base(&mut self,context:&mut MetadataContext,owner:Option<&str>,name:&str,verb:bool)->Result<(ProcMetadata,String),String> {
        let Some(owner)=owner else {return Ok((context.default_metadata.as_ref().clone(),context.default_identity.clone()));};
        let parent=context.parents.get(owner).cloned().flatten();
        let parent_record=if let Some(parent)=parent {Some(self.resolve(context,(parent,name.to_owned(),verb),&mut HashSet::new())?)}else{None};
        // A declared ancestor resolves against the default metadata; absent
        // ancestors can still leave an intrinsic native row on the current owner.
        let value=parent_record.as_ref().and_then(|r|r.value.as_ref().map(Arc::clone)).or_else(||context.native.get(&(owner.to_owned(),name.to_owned(),verb)).cloned()).unwrap_or_else(||Arc::clone(&context.default_metadata));
        let mut reads=BTreeMap::new();
        let key=MetadataRead::Parent(owner.to_owned());let observation=context.read(&key);crate::observed_dependencies::record(&mut reads,key,observation);
        if parent_record.as_ref().is_none_or(|record|record.value.is_none()) {
            let key=MetadataRead::Native((owner.to_owned(),name.to_owned(),verb));let value=context.read(&key);crate::observed_dependencies::record(&mut reads,key,value);
        }
        let observations:Vec<_>=reads.into_iter().collect();
        let identity=crate::lower_cache::shared_binding_fingerprint(&(observations,parent_record.as_ref().map(|r|&r.semantic_identity),value.as_ref()));
        Ok((value.as_ref().clone(),identity))
    }
    fn resolve(&mut self,context:&mut MetadataContext,key:Named,active:&mut HashSet<Named>)->Result<Arc<MetadataRecord>,String> {
        if let Some(record)=context.published.get(&key).or_else(||context.current.get(&key)){return Ok(Arc::clone(record));}
        if !active.insert(key.clone()){return Err("cyclic procedure metadata ancestry".into());}
        let mut reads=BTreeMap::new();
        let declaration=context.declarations.get(&key).map(|d|d.item);
        let read=MetadataRead::Declaration(key.clone());let value=context.read(&read);crate::observed_dependencies::record(&mut reads,read,value);
        let native=if declaration.is_none(){
            let read=MetadataRead::Native(key.clone());let value=context.read(&read);crate::observed_dependencies::record(&mut reads,read,value);
            context.native.get(&key).cloned()
        }else{None};
        let parent=if declaration.is_some()||native.is_none() {
            let read=MetadataRead::Parent(key.0.clone());let value=context.read(&read);crate::observed_dependencies::record(&mut reads,read,value);
            if let Some(owner)=context.parents.get(&key.0).cloned().flatten() {
                let parent_key=(owner,key.1.clone(),key.2);
                context.dependents.entry(parent_key.clone()).or_default().insert(key.clone());
                let parent=self.resolve(context,parent_key.clone(),active)?;
                crate::observed_dependencies::record(&mut reads,MetadataRead::Resolved(parent_key),parent.semantic_identity.clone());
                Some(parent)
            }else{None}
        }else{None};
        let parent_identity=parent.as_ref().map(|p|p.semantic_identity.clone()).unwrap_or_default();
        let old=self.metadata.get(&key).map(|(record,_)|Arc::clone(record)).or_else(||self.requested_metadata.get(&key).cloned());
        let old=old.filter(|old|old.parent_identity==parent_identity&&self.validity.validate(old,context));
        let record=if let Some(record)=old{self.metadata_reused+=1;record}else {
            self.metadata_derived+=1;
            let base=parent.as_ref().and_then(|p|p.value.as_ref().map(Arc::clone));
            let (value,semantic_identity)=if let Some(item)=declaration {
                let base=base.unwrap_or_else(||Arc::clone(&context.default_metadata));
                let declarations=invocation_declaration_projection(&item.children);
                if declarations.is_empty() {
                    // Empty projections forward immutable metadata unchanged.
                    let semantic=parent.as_ref().filter(|parent|parent.value.is_some()).map(|parent|parent.semantic_identity.clone()).unwrap_or_else(||context.default_semantic_identity.clone());
                    (Some(base),semantic)
                }else {
                    let value=Some(Arc::new(proc_metadata_from_base(&declarations,base.as_ref().clone())
                        .map_err(|reason|source_error(context.source_debug,item.header_span.start,&item.header,&reason))?.0));
                    let semantic=crate::lower_cache::shared_binding_fingerprint(&value);
                    (value,semantic)
                }
            }else if let Some(native)=native {
                let semantic=context.read(&MetadataRead::Native(key.clone()));
                (Some(native),semantic)
            }else {
                let semantic=parent.as_ref().map(|parent|parent.semantic_identity.clone()).unwrap_or_else(||context.absent_identity.clone());
                (base,semantic)
            };
            let reads:Vec<_>=reads.into_iter().collect();
            let identity=crate::lower_cache::shared_binding_fingerprint(&(&reads,&parent_identity,value.as_ref()));
            let record=Arc::new(MetadataRecord {reads,parent_identity,value,identity,semantic_identity});
            let encoded=rmp_serde::to_vec_named(record.as_ref()).ok();
            let charge=encoded.as_ref().map_or(192,|bytes|bytes.len()*3+192);
            if self.metadata_bytes+charge>Self::LIMIT {self.metadata.clear();self.metadata_bytes=0;}
            if let Some((_,old_charge))=self.metadata.remove(&key){self.metadata_bytes=self.metadata_bytes.saturating_sub(old_charge);}
            self.metadata_bytes+=charge;self.metadata.insert(key.clone(),(Arc::clone(&record),charge));
            if let Some(bytes)=encoded {
                if bytes.len()<=1024*1024 {
                    if self.pending_bytes+bytes.len()+record.identity.len()>Self::WRITE_BATCH||self.pending.len()+self.pending_metadata.len()>=60_000 {self.flush();}
                    let address=crate::lower_cache::shared_binding_fingerprint(&key);
                    if let Some(digest)=InvocationFragments::digest_bytes(&address){self.metadata_negative.remove(&digest);}
                    self.pending_bytes+=bytes.len()+address.len();
                    if self.packed_metadata.is_some() {
                        self.pending_metadata.push((address,bytes));
                    }else {
                        self.pending.push(Change::Put(Key::new(Self::metadata_namespace(),&record.identity),bytes));
                        self.pending.push(Change::Put(Key::new(Self::metadata_addresses(),address),record.identity.as_bytes().to_vec()));
                    }
                }
            }
            record
        };
        active.remove(&key);context.current.insert(key,Arc::clone(&record));Ok(record)
    }
}

fn read_packed_requested(packed:&dm_store::PackedRecords,keys:&[String],visit:&mut impl FnMut(&str,Option<Vec<u8>>)) {
    if keys.is_empty(){return;}
    match packed.read_many(keys,1024*1024,8*1024*1024,None) {
        Ok(rows)=>for (key,row) in keys.iter().zip(rows){visit(key,row);},
        Err(error) if error.kind()==std::io::ErrorKind::InvalidInput&&keys.len()>1=>{
            let middle=keys.len()/2;
            read_packed_requested(packed,&keys[..middle],visit);
            read_packed_requested(packed,&keys[middle..],visit);
        }
        Err(_)=>for key in keys {visit(key,None);},
    }
}

fn decode_metadata_record(bytes:&[u8],query:&Named)->Option<MetadataRecord> {
    let record=rmp_serde::from_slice::<MetadataRecord>(bytes).ok()?;
    let identity=crate::lower_cache::shared_binding_fingerprint(&(&record.reads,&record.parent_identity,record.value.as_ref()));
    if identity!=record.identity||record.semantic_identity!=crate::lower_cache::shared_binding_fingerprint(&record.value)||!record.reads.iter().any(|(read,_)|matches!(read,MetadataRead::Declaration(name) if name==query)){return None;}
    Some(record)
}

// The portable observations above are also the sole Salsa dependency inputs.
// Shared observed keys are interned once; the semantic context supplies values.
use salsa::Setter as _;
#[salsa::input]
struct ObservationInput { #[returns(ref)] value:String }
#[salsa::input]
struct ValidityInput {
    #[returns(ref)] expected:Vec<String>,
    #[returns(ref)] observations:Vec<ObservationInput>,
}
#[salsa::db]
trait MetadataDb:salsa::Database {}
#[salsa::db]
#[derive(Clone,Default)]
struct Database {storage:salsa::Storage<Self>}
#[salsa::db]
impl salsa::Database for Database {}
#[salsa::db]
impl MetadataDb for Database {}
#[salsa::tracked]
fn valid(db:&dyn MetadataDb,input:ValidityInput)->bool {
    crate::observed_dependencies::validate(input.observations(db).iter().zip(input.expected(db)),|input|input.value(db).clone())
}
#[derive(Default)]
struct ValidityArena {
    db:Database, observations:BTreeMap<MetadataRead,(ObservationInput,(u64,Option<[u8;32]>))>,
    candidates:HashMap<String,ValidityInput>,bytes:usize,
}
impl ValidityArena {
    fn clear(&mut self){*self=Self::default();}
    fn validate(&mut self,record:&MetadataRecord,context:&mut MetadataContext)->bool {
        if self.bytes>8*1024*1024 {self.clear();}
        let mut inputs=Vec::with_capacity(record.reads.len());
        for (key,_) in &record.reads {
            let epoch=context.observation_epoch(key);
            let input=if let Some((input,refreshed))=self.observations.get(key).copied() {
                // Each immutable input refreshes once per model. Named resolved
                // values carry their own source-order publication version.
                if refreshed!=epoch {
                    let current=context.read(key);
                    if input.value(&self.db)!=&current {input.set_value(&mut self.db).to(current);}
                    self.observations.insert(key.clone(),(input,epoch));
                }
                input
            }else {
                let current=context.read(key);
                self.bytes+=rmp_serde::to_vec_named(key).map_or(192,|bytes|bytes.len()+192)+current.len();
                let input=ObservationInput::new(&self.db,current);self.observations.insert(key.clone(),(input,epoch));input
            };
            inputs.push(input);
        }
        let input=if let Some(input)=self.candidates.get(&record.identity).copied(){input}else {
            let expected:Vec<_>=record.reads.iter().map(|(_,value)|value.clone()).collect();
            self.bytes+=expected.iter().map(|value|value.len()+64).sum::<usize>()+record.identity.len()+128;
            let input=ValidityInput::new(&self.db,expected,inputs);self.candidates.insert(record.identity.clone(),input);input
        };
        *valid(&self.db,input)
    }
}
