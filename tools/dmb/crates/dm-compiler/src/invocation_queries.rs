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
}
struct Declaration<'a> { item: &'a Item, identity: String }
/// Source-order publication overlays the frozen declaration index. A previously
/// published override has the same precedence as the original ordered resolver.
pub(crate) struct MetadataContext<'a> {
    parents: HashMap<String, Option<String>>,
    declarations: HashMap<Named, Declaration<'a>>,
    descriptors: HashMap<usize,(String,String)>,
    native: HashMap<Named, Arc<ProcMetadata>>,
    observations: HashMap<MetadataRead, String>,
    current: HashMap<Named, Arc<MetadataRecord>>,
    published: HashMap<Named, Arc<MetadataRecord>>,
    dependents: HashMap<Named, HashSet<Named>>,
}
impl<'a> MetadataContext<'a> {
    pub(crate) fn new(dmb:&Dmb,pending:&[PendingProc<'a>])->Result<Self,String> {
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
            let path=InvocationFragments::declaration_path(proc.item,&proc.owner_path,proc.verb)?;
            let identity=InvocationFragments::declaration_key(proc.item,&path);
            descriptors.insert(proc.item as *const Item as usize,(path.clone(),identity.clone()));
            if proc.owner.is_none(){continue;}
            declarations.insert((proc.owner_path.clone(),path.rsplit('/').next().unwrap_or("").to_owned(),proc.verb),Declaration {item:proc.item,identity});
        }
        Ok(Self {parents,declarations,descriptors,native,observations:HashMap::new(),current:HashMap::new(),published:HashMap::new(),dependents:HashMap::new()})
    }
    pub(crate) fn descriptor(&self,item:&Item)->&(String,String) { &self.descriptors[&(item as *const Item as usize)] }
    fn read(&mut self,key:&MetadataRead)->String {
        if !matches!(key,MetadataRead::Resolved(_)) {if let Some(value)=self.observations.get(key){return value.clone();}}
        let value=match key {
            MetadataRead::Parent(owner)=>crate::lower_cache::shared_binding_fingerprint(&self.parents.get(owner)),
            MetadataRead::Declaration(key)=>self.declarations.get(key).map(|d|d.identity.clone()).unwrap_or_else(||crate::lower_cache::shared_binding_fingerprint(&Option::<u8>::None)),
            MetadataRead::Native(key)=>crate::lower_cache::shared_binding_fingerprint(&self.native.get(key)),
            MetadataRead::Resolved(key)=>self.published.get(key).or_else(||self.current.get(key)).map(|record|record.identity.clone()).unwrap_or_default(),
        };
        if !matches!(key,MetadataRead::Resolved(_)){self.observations.insert(key.clone(),value.clone());}value
    }
    pub(crate) fn publish(&mut self,owner:&str,name:&str,verb:bool,metadata:&ProcMetadata,identity:&str) {
        let key=(owner.to_owned(),name.to_owned(),verb);
        let record=Arc::new(MetadataRecord {reads:Vec::new(),parent_identity:String::new(),value:Some(Arc::new(metadata.clone())),identity:identity.to_owned()});
        let changed=self.current.get(&key).is_some_and(|old|crate::lower_cache::shared_binding_fingerprint(&old.value)!=crate::lower_cache::shared_binding_fingerprint(&Some(metadata)));
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
    validity: ValidityArena,
    store:Option<Store>, pending:Vec<Change>, pending_bytes:usize,
    pub hits:usize,pub misses:usize,
}
impl InvocationQueries {
    const LIMIT:usize=16*1024*1024;
    fn namespace()->String {format!("invocation-templates-v1-{}",env!("DM_EMISSION_FINGERPRINT"))}
    pub(crate) fn open(root:&Path)->Self {Self {store:Store::open(root.join("declaration-fragments.redb")).ok(),..Default::default()}}
    pub(crate) fn clear(&mut self){self.templates.clear();self.handles.clear();self.order.clear();self.bytes=0;self.metadata.clear();self.metadata_bytes=0;self.validity.clear();}
    pub(crate) fn release_decoded(&mut self) {
        self.flush();self.templates.clear();self.order.clear();self.bytes=0;
        self.metadata.clear();self.metadata_bytes=0;self.validity.clear();
        // Weak handles continue selecting templates retained by frozen plans.
    }
    pub(crate) fn resident_bytes(&self)->usize {self.bytes+self.metadata_bytes+self.pending_bytes+self.handles.len()*96+self.validity.bytes}
    pub(crate) fn flush(&mut self){if self.pending.is_empty(){return;}if let Some(store)=&self.store{let _=store.commit(&[],&self.pending,None);}self.pending.clear();self.pending_bytes=0;}
    pub(crate) fn prefetch(&mut self,keys:&[String]) {
        let Some(store)=self.store.clone()else{return;};
        let keys:Vec<_>=keys.iter().filter(|key|self.authored_candidate(key).is_none()).map(|key|Key::new(Self::namespace(),key)).collect();
        default_plans::read_stage_batch(&store,&keys,1024*1024,8*1024*1024,&mut |key,bytes| {
            if let Some(bytes)=bytes {if let Ok(template)=rmp_serde::from_slice::<InvocationTemplate>(&bytes) {if template.declaration_identity==key.name {self.admit(Arc::new(template),bytes.len());}}}
        });
    }
    fn admit(&mut self,template:Arc<InvocationTemplate>,wire:usize) {
        let key=template.declaration_identity.clone();
        if let Some(digest)=InvocationFragments::digest_bytes(&key) {if self.handles.len()<72_000||self.handles.contains_key(&digest){self.handles.insert(digest,Arc::downgrade(&template));}}
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
        if self.pending_bytes+bytes.len()>1024*1024{self.flush();}
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
        let Some(owner)=owner else {let value=proc_metadata(&[],None)?.0;return Ok((value.clone(),crate::lower_cache::shared_binding_fingerprint(&value)));};
        let parent=context.parents.get(owner).cloned().flatten();
        let parent_record=if let Some(parent)=parent {Some(self.resolve(context,(parent,name.to_owned(),verb),&mut HashSet::new())?)}else{None};
        // A declared ancestor resolves against the default metadata; absent
        // ancestors can still leave an intrinsic native row on the current owner.
        let value=parent_record.as_ref().and_then(|r|r.value.as_ref().map(Arc::clone)).or_else(||context.native.get(&(owner.to_owned(),name.to_owned(),verb)).cloned()).unwrap_or(Arc::new(proc_metadata(&[],None)?.0));
        let mut reads=BTreeMap::new();
        let key=MetadataRead::Parent(owner.to_owned());let observation=context.read(&key);crate::observed_dependencies::record(&mut reads,key,observation);
        if parent_record.as_ref().is_none_or(|record|record.value.is_none()) {
            let key=MetadataRead::Native((owner.to_owned(),name.to_owned(),verb));let value=context.read(&key);crate::observed_dependencies::record(&mut reads,key,value);
        }
        let identity=crate::lower_cache::shared_binding_fingerprint(&(reads,parent_record.as_ref().map(|r|&r.identity),value.as_ref()));
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
                crate::observed_dependencies::record(&mut reads,MetadataRead::Resolved(parent_key),parent.identity.clone());
                Some(parent)
            }else{None}
        }else{None};
        let parent_identity=parent.as_ref().map(|p|p.identity.clone()).unwrap_or_default();
        let old=self.metadata.get(&key).map(|(record,_)|Arc::clone(record));
        let old=old.filter(|old|old.parent_identity==parent_identity&&self.validity.validate(old,context));
        let record=if let Some(record)=old{record}else {
            let base=parent.as_ref().and_then(|p|p.value.as_ref().map(Arc::clone));
            let value=if let Some(item)=declaration {
                let base=base.unwrap_or(Arc::new(proc_metadata(&[],None)?.0));
                let declarations=invocation_declaration_projection(&item.children);
                Some(Arc::new(proc_metadata_from_base(&declarations,base.as_ref().clone())?.0))
            }else {native.or(base)};
            let reads:Vec<_>=reads.into_iter().collect();
            let identity=crate::lower_cache::shared_binding_fingerprint(&(&reads,&parent_identity,value.as_ref()));
            let record=Arc::new(MetadataRecord {reads,parent_identity,value,identity});
            let charge=rmp_serde::to_vec_named(record.as_ref()).map_or(0,|bytes|bytes.len()*3+192);
            if self.metadata_bytes+charge>Self::LIMIT {self.metadata.clear();self.metadata_bytes=0;}
            if let Some((_,old_charge))=self.metadata.remove(&key){self.metadata_bytes=self.metadata_bytes.saturating_sub(old_charge);}
            self.metadata_bytes+=charge;self.metadata.insert(key.clone(),(Arc::clone(&record),charge));
            if let Ok(bytes)=rmp_serde::to_vec_named(record.as_ref()) {
                if bytes.len()<=1024*1024 {
                    if self.pending_bytes+bytes.len()>1024*1024 {self.flush();}
                    self.pending_bytes+=bytes.len();self.pending.push(Change::Put(Key::new(format!("invocation-metadata-v1-{}",env!("DM_EMISSION_FINGERPRINT")),&record.identity),bytes));
                }
            }
            record
        };
        active.remove(&key);context.current.insert(key,Arc::clone(&record));Ok(record)
    }
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
    db:Database, observations:BTreeMap<MetadataRead,ObservationInput>,
    candidates:HashMap<String,ValidityInput>,bytes:usize,
}
impl ValidityArena {
    fn clear(&mut self){*self=Self::default();}
    fn validate(&mut self,record:&MetadataRecord,context:&mut MetadataContext)->bool {
        if self.bytes>8*1024*1024 {self.clear();}
        let mut inputs=Vec::with_capacity(record.reads.len());
        for (key,_) in &record.reads {
            let current=context.read(key);
            let input=if let Some(input)=self.observations.get(key).copied() {
                if input.value(&self.db)!=&current {input.set_value(&mut self.db).to(current);}input
            }else {
                self.bytes+=rmp_serde::to_vec_named(key).map_or(128,|bytes|bytes.len()+128)+current.len();
                let input=ObservationInput::new(&self.db,current);self.observations.insert(key.clone(),input);input
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
