//! Declaration expression resolution over an allocation-independent owner model.
//! Wire tables are consulted only once to import the immutable builtin schema.
#[path = "analysis_model.rs"]
pub(super) mod analysis_model;
#[path="semantic_default_queries.rs"]
mod default_queries;
use super::*;
use std::cell::RefCell;
use std::sync::{Mutex, OnceLock};
use serde::{Serialize, Deserialize};
use std::sync::atomic::{AtomicU64,Ordering};
use sha2::{Digest, Sha256};

fn next_model_generation()->u64 {
    static GENERATION:AtomicU64=AtomicU64::new(1);
    GENERATION.fetch_add(1,Ordering::Relaxed)
}

#[derive(Clone,Serialize,Deserialize)]
struct Field {
    expression: Option<String>,
    constant: bool,
    override_only: bool,
    imported: Option<const_eval::Constant>,
}
#[derive(Clone, Default,Serialize,Deserialize)]
struct Owner {
    parent: Option<String>,
    fields: BTreeMap<String, Field>,
}
#[derive(Default)]
pub(super) struct SemanticDeclarations {
    generation:u64,
    owners: im::HashMap<String, Arc<Owner>>,
    globals: im::HashMap<String, Field>,
    recipes: im::HashMap<String, String>,
    builtin_identity: String,
    builtins: Arc<BuiltinModel>,
}
#[path = "semantic_owner_dag.rs"]
mod owner_dag;
#[derive(Clone,Default,Serialize,Deserialize)]
struct BuiltinModel { owners:im::HashMap<String,Arc<Owner>>, globals:im::HashMap<String,Field> }
static QUERIES:AtomicU64=AtomicU64::new(0);
static HITS:AtomicU64=AtomicU64::new(0);
static MISSES:AtomicU64=AtomicU64::new(0);
pub(super) fn stats()->(u64,u64,u64) {(QUERIES.load(Ordering::Relaxed),HITS.load(Ordering::Relaxed),MISSES.load(Ordering::Relaxed))}
thread_local! {
    static ACTIVE: RefCell<Option<Arc<SemanticDeclarations>>> = const { RefCell::new(None) };
}
pub(super) struct ActiveModel(Option<Arc<SemanticDeclarations>>);
impl Drop for ActiveModel {
    fn drop(&mut self) { ACTIVE.with(|active| *active.borrow_mut() = self.0.take()); }
}
pub(super) fn activate(model: Arc<SemanticDeclarations>) -> ActiveModel {
    ActiveModel(ACTIVE.with(|active| active.replace(Some(model))))
}
pub(super) fn capture_active() -> Option<Arc<SemanticDeclarations>> {
    ACTIVE.with(|active| active.borrow().clone())
}
pub(super) fn activate_optional(model: Option<Arc<SemanticDeclarations>>) -> ActiveModel {
    ActiveModel(ACTIVE.with(|active| active.replace(model)))
}
/// None means no semantic model is installed (legacy isolated helper callers).
/// Some(None) is a witnessed missing/dynamic binding and never consults wire IDs.
pub(super) fn evaluate(source: &str, owner: Option<&str>, blocked: &HashSet<String>) -> Option<Option<const_eval::Constant>> {
    let model = ACTIVE.with(|active| active.borrow().clone())?;
    QUERIES.fetch_add(1,Ordering::Relaxed);
    let owner = owner.unwrap_or("");
    // Literal recipes are scope independent. Avoid polluting syntax/default
    // query caches with hundreds of thousands of repeated wire projections.
    if source=="null" {return Some(Some(const_eval::Constant::Null));}
    if let Some(number)=literal_number(source) {return Some(Some(const_eval::Constant::Number(number)));}
    if source.starts_with('/') && source.bytes().all(|byte|byte.is_ascii_alphanumeric()||matches!(byte,b'/'|b'_')) {
        return Some(Some(const_eval::Constant::TypePath(source.to_owned())));
    }
    if source.starts_with('\'')&&source.ends_with('\'') {return Some(None);}
    if source.starts_with('"')&&source.ends_with('"')&&source.len()>=2 {
        let text=&source[1..source.len()-1];
        if !text.bytes().any(|byte|matches!(byte,b'\\'|b'['|b'"')) {return Some(Some(const_eval::Constant::Text(text.to_owned())));}
    }
    let name=expression_key(source,blocked);
    let key=(owner.to_owned(),name.clone());
    let candidate=value_cache().lock().unwrap_or_else(|error|error.into_inner()).entries.get(&key).map(|(record,_)|Arc::clone(record));
    if let Some(record)=candidate {
        if default_queries::validate(&model,&record) {
            HITS.fetch_add(1,Ordering::Relaxed);
            return Some(record.value.clone());
        }
    }
    MISSES.fetch_add(1,Ordering::Relaxed);
    let reads=RefCell::new(BTreeMap::new());
    let result=const_eval::evaluate(source, |name|model.resolve(owner,name,blocked,&mut HashSet::new(),&reads));
    retain_value(key,Arc::new(ResolvedValue {owner:owner.to_owned(),name,value:result.clone(),reads:reads.into_inner().into_iter().collect()}));
    Some(result)
}
// Rust accepts identifier spellings such as NaN/inf; DM must resolve those
// through the symbol model. Only authored numeric syntax bypasses dependencies.
fn literal_number(source:&str)->Option<f32> {
    if !source.bytes().any(|byte|byte.is_ascii_digit()) || !source.bytes().all(|byte|
        byte.is_ascii_digit() || matches!(byte,b'.'|b'+'|b'-'|b'e'|b'E')) { return None; }
    source.parse().ok()
}
/// Plan only the next physical allocation window. Workers share immutable
/// declaration roots and publish portable witnessed values; no wire IDs or
/// mutable DMB state enter this stage.
pub(super) fn prefetch_owner_defaults(items:&[&Item],plans:&[Arc<default_plans::OwnerDeclarationPlan>],workers:usize) {
    let Some(model)=capture_active() else {return;};
    let empty_set=HashSet::new();
    let empty=&empty_set;
    let jobs:Vec<_>=items.iter().zip(plans).flat_map(|(item,plan)| {
        plan.expressions.iter().filter_map(move |field|field.expression.as_deref()
            .filter(|source|!dependency_free_literal(source))
            .map(move |source|(item.header.trim(),source,if field.override_only {empty} else {&plan.mutable_names})))
    }).collect();
    let configured=dm_work::WorkLimits::configured();
    let limits=dm_work::WorkLimits {workers:workers.min(configured.workers).clamp(1,4),max_active_bytes:configured.max_active_bytes.min(8*1024*1024)};
    // A resident candidate is validated by the consuming query. Prefetch only
    // genuine candidate misses; do not replay every cached readset twice.
    let cache=value_cache().lock().unwrap_or_else(|error|error.into_inner());
    let jobs:Vec<_>=jobs.into_iter().filter(|(owner,source,blocked)|!cache.entries.contains_key(&(owner.to_string(),expression_key(source,blocked)))).collect();
    drop(cache);
    if jobs.is_empty() {return;}
    let _=dm_work::map_ordered(&jobs,limits,|(_,source,blocked)|source.len()+blocked.len()*64+256,|(owner,source,blocked)| {
        let _active=activate(Arc::clone(&model));
        let _=evaluate(source,Some(owner),blocked);
    });
}

fn dependency_free_literal(source:&str)->bool {
    source=="null" || literal_number(source).is_some()
        || (source.starts_with('/')&&source.bytes().all(|byte|byte.is_ascii_alphanumeric()||matches!(byte,b'/'|b'_')))
        || (source.starts_with('\'')&&source.ends_with('\''))
        || (source.starts_with('"')&&source.ends_with('"')&&source.len()>=2&&!source[1..source.len()-1].bytes().any(|byte|matches!(byte,b'\\'|b'['|b'"')))
}
fn expression_key(source:&str,blocked:&HashSet<String>)->String {
    let mut hash=Sha256::new();
    hash.update(b"default-expression-v1\0");
    hash.update((source.len() as u64).to_le_bytes());hash.update(source.as_bytes());
    let mut blocked:Vec<_>=blocked.iter().collect();blocked.sort();
    for name in blocked {hash.update((name.len() as u64).to_le_bytes());hash.update(name.as_bytes());}
    format!("\0expression:{:x}",hash.finalize())
}
impl SemanticDeclarations {
    pub(super) fn build(items:&[Item],modified:&[Item],builtin:&Dmb,builtin_image:&[u8],previous:Option<&Arc<Self>>,workers:usize)->Arc<Self> {
        owner_dag::build(items,modified,builtin,builtin_image,previous,workers)
    }
    pub(super) fn resident_bytes(&self)->usize {
        let map_charge=self.owners.len()*96+self.globals.len()*96+self.recipes.len()*160+self.builtin_identity.capacity();
        let owners=self.owners.values().map(|owner|owner.fields.iter().map(|(name,field)|
            name.capacity()+field.expression.as_ref().map_or(0,String::capacity)+128).sum::<usize>() / Arc::strong_count(owner).max(1)).sum::<usize>();
        map_charge+owners
    }
    fn resolve(&self,owner:&str,name:&str,blocked:&HashSet<String>,active:&mut HashSet<(String,String)>,reads:&RefCell<BTreeMap<SemanticRead,String>>) -> Option<const_eval::Constant> {
        if let Some((path,field))=name.split_once("::") {return self.field(path,field,true,active,reads);}
        if blocked.contains(name) {return None;}
        let mut path=owner;
        let mut visited=HashSet::new();
        while !path.is_empty() && visited.insert(path.to_owned()) {
            self.observe(SemanticRead::Field(path.to_owned(),name.to_owned()),reads);
            self.observe(SemanticRead::Parent(path.to_owned()),reads);
            let Some(scope)=self.owners.get(path) else {
                path = lexical_parent(path)?;
                continue;
            };
            if let Some(field)=scope.fields.get(name) {
                let constant = field.constant || (field.override_only && self.inherited_constant(scope.parent.as_deref(), name, reads));
                return if constant {self.value(path,name,field,active,reads)} else {None};
            }
            path=scope.parent.as_deref().unwrap_or("");
        }
        self.observe(SemanticRead::Global(name.to_owned()),reads);
        if let Some(field)=self.globals.get(name) {
            return if field.constant {self.value("",name,field,active,reads)} else {None};
        }
        self.observe(SemanticRead::Builtin(name.to_owned()),reads);
        builtin_constant(name)
    }
    fn field(&self,path:&str,name:&str,allow_mutable:bool,active:&mut HashSet<(String,String)>,reads:&RefCell<BTreeMap<SemanticRead,String>>) -> Option<const_eval::Constant> {
        let mut path=path;
        let mut visited=HashSet::new();
        while visited.insert(path.to_owned()) {
            self.observe(SemanticRead::Field(path.to_owned(),name.to_owned()),reads);
            self.observe(SemanticRead::Parent(path.to_owned()),reads);
            let Some(scope)=self.owners.get(path) else {
                path=lexical_parent(path)?;
                continue;
            };
            if let Some(field)=scope.fields.get(name) {
                return if allow_mutable||field.constant {self.value(path,name,field,active,reads)} else {None};
            }
            path=scope.parent.as_deref()?;
        }
        None
    }
    fn inherited_constant<'a>(&'a self, mut path: Option<&'a str>, name: &str, reads:&RefCell<BTreeMap<SemanticRead,String>>) -> bool {
        let mut visited = HashSet::new();
        while let Some(current) = path {
            if !visited.insert(current) { return false; }
            self.observe(SemanticRead::Field(current.to_owned(),name.to_owned()),reads);
            self.observe(SemanticRead::Parent(current.to_owned()),reads);
            let Some(owner) = self.owners.get(current) else { path = lexical_parent(current); continue; };
            if let Some(field) = owner.fields.get(name) {
                if field.constant { return true; }
                if !field.override_only { return false; }
            }
            path = owner.parent.as_deref();
        }
        false
    }
    fn observe(&self, key:SemanticRead, reads:&RefCell<BTreeMap<SemanticRead,String>>) {
        let identity=self.read_identity(&key);crate::observed_dependencies::record(&mut reads.borrow_mut(),key,identity);
    }
    fn read_identity(&self,key:&SemanticRead)->String {
        match key {
            SemanticRead::Field(path,name)=>field_identity(self.owners.get(path).and_then(|owner|owner.fields.get(name))),
            SemanticRead::Global(name)=>field_identity(self.globals.get(name)),
            SemanticRead::Parent(path)=>self.owners.get(path).map(|owner|format!("owner:{}",owner.parent.as_deref().unwrap_or(""))).unwrap_or_else(||"missing".to_owned()),
            SemanticRead::Builtin(name)=>field_identity(Some(&Field {expression:None,constant:true,override_only:false,imported:builtin_constant(name)})),
        }
    }
    fn value(&self,owner:&str,name:&str,field:&Field,active:&mut HashSet<(String,String)>,reads:&RefCell<BTreeMap<SemanticRead,String>>) -> Option<const_eval::Constant> {
        let key=(owner.to_owned(),name.to_owned());
        if !active.insert(key.clone()) {return None;}
        let candidate=value_cache().lock().unwrap_or_else(|error|error.into_inner()).entries.get(&key).map(|(record,_)|Arc::clone(record));
        if let Some(record)=candidate {
            if default_queries::validate(self,&record) {
                HITS.fetch_add(1,Ordering::Relaxed);
                reads.borrow_mut().extend(record.reads.iter().cloned());
                active.remove(&key);return record.value.clone();
            }
        }
        MISSES.fetch_add(1,Ordering::Relaxed);
        let local=RefCell::new(BTreeMap::new());
        self.observe(if owner.is_empty() {SemanticRead::Global(name.to_owned())} else {SemanticRead::Field(owner.to_owned(),name.to_owned())},&local);
        let result = match &field.expression {
            Some(expression)=>{
                let active=RefCell::new(&mut *active);
                const_eval::evaluate(expression,|name|self.resolve(owner,name,&HashSet::new(),&mut **active.borrow_mut(),&local))
            },
            None=>field.imported.clone(),
        };
        active.remove(&key);
        let observations:Vec<_>=local.into_inner().into_iter().collect();
        reads.borrow_mut().extend(observations.iter().cloned());
        let record=Arc::new(ResolvedValue {owner:owner.to_owned(),name:name.to_owned(),value:result.clone(),reads:observations});
        retain_value(key,Arc::clone(&record));
        result
    }

}

fn lexical_parent(path:&str)->Option<&str> {
    if path == "/datum" { return None; }
    Some(path.rsplit_once('/').map(|(parent,_)|parent).filter(|parent|!parent.is_empty()).unwrap_or("/datum"))
}

pub(super) fn resident_bytes()->usize {
    let values = value_cache().lock().unwrap_or_else(|error|error.into_inner());
    values.bytes + values.pending_bytes + owner_dag::resident_bytes() + default_queries::resident_bytes()
}
/// Auxiliary process cache trimming drops indexes only; active requests retain
/// their immutable owner Arcs until completion.
pub(super) fn trim_to(max_bytes:usize) {
    owner_dag::trim_to(max_bytes/3);
    if max_bytes==0 { default_queries::reset(); }
    let mut values=value_cache().lock().unwrap_or_else(|error|error.into_inner());
    flush_values(&mut values);
    while values.bytes>max_bytes/2 {
        let Some(key)=values.entries.keys().next().cloned() else {break};
        if let Some((_,old))=values.entries.remove(&key) {values.bytes=values.bytes.saturating_sub(old);}
    }
}

#[derive(Clone, Ord, PartialOrd, Eq, PartialEq, Serialize, Deserialize)]
enum SemanticRead { Field(String,String), Parent(String), Global(String), Builtin(String) }
#[derive(Serialize, Deserialize)]
struct ResolvedValue { owner:String, name:String, value:Option<const_eval::Constant>, reads:Vec<(SemanticRead,String)> }
#[derive(Default)]
struct ValueArtifacts {
    root:Option<std::path::PathBuf>,store:Option<dm_store::Store>,
    entries:BTreeMap<(String,String),(Arc<ResolvedValue>,usize)>,bytes:usize,
    pending:BTreeMap<String,Vec<u8>>,pending_bytes:usize,
}
fn value_cache()->&'static Mutex<ValueArtifacts> {
    static VALUES:OnceLock<Mutex<ValueArtifacts>>=OnceLock::new();
    VALUES.get_or_init(||Mutex::new(ValueArtifacts::default()))
}
fn value_namespace()->String {format!("resolved-owner-defaults-v1-{}",env!("DM_EMISSION_FINGERPRINT"))}
fn field_identity(field:Option<&Field>)->String {
    let Some(field)=field else {return "missing".to_owned()};
    let mut hash=Sha256::new();
    hash.update([field.constant as u8,field.override_only as u8,field.expression.is_some() as u8]);
    let expression=field.expression.as_deref().unwrap_or("");hash.update((expression.len() as u64).to_le_bytes());hash.update(expression);
    match &field.imported {
        None=>hash.update([0]),Some(const_eval::Constant::Null)=>hash.update([1]),
        Some(const_eval::Constant::Number(number))=>{hash.update([2]);hash.update(number.to_bits().to_le_bytes());},
        Some(const_eval::Constant::Text(text))=>{hash.update([3]);hash.update(text);},
        Some(const_eval::Constant::EncodedText(text))=>{hash.update([4]);hash.update(text);},
        Some(const_eval::Constant::TypePath(path))=>{hash.update([5]);hash.update(path);},
    }
    format!("{:x}",hash.finalize())
}
fn flush_values(cache:&mut ValueArtifacts) {
    let Some(store)=&cache.store else {cache.pending.clear();cache.pending_bytes=0;return;};
    let changes:Vec<_>=cache.pending.iter().map(|(key,bytes)|dm_store::Change::Put(dm_store::Key::new(value_namespace(),key),bytes.clone())).collect();
    if store.commit(&[],&changes,None).is_ok() {cache.pending.clear();cache.pending_bytes=0;}
}
pub(super) fn bind_cache(root:&std::path::Path) {
    owner_dag::bind(root);
    let mut cache=value_cache().lock().unwrap_or_else(|error|error.into_inner());
    if cache.root.as_deref()==Some(root) {return;}
    default_queries::reset();
    flush_values(&mut cache);
    let next=ValueArtifacts {root:Some(root.to_owned()),store:dm_store::Store::open(root.join("resolved-declarations.redb")).ok(),..Default::default()};
    *cache=next;
}
pub(super) fn flush_cache() {owner_dag::flush();flush_values(&mut value_cache().lock().unwrap_or_else(|error|error.into_inner()));}
fn retain_value(key:(String,String),record:Arc<ResolvedValue>) {
    let Ok(bytes)=serde_json::to_vec(record.as_ref()) else {return;};
    if bytes.len()>1024*1024 {return;}
    let size=bytes.len()*3+128;
    let mut cache=value_cache().lock().unwrap_or_else(|error|error.into_inner());
    if let Some((_,old))=cache.entries.remove(&key) {cache.bytes=cache.bytes.saturating_sub(old);}
    while cache.bytes.saturating_add(size)>32*1024*1024 {
        let Some(key)=cache.entries.keys().next().cloned() else {break;};
        if let Some((_,old))=cache.entries.remove(&key) {cache.bytes=cache.bytes.saturating_sub(old);}
    }
    cache.bytes+=size;cache.entries.insert(key.clone(),(record,size));
    if cache.store.is_some() {
        if cache.pending_bytes.saturating_add(bytes.len())>4*1024*1024 {flush_values(&mut cache);}
        let identity=format!("{:x}",Sha256::digest(serde_json::to_vec(&key).unwrap_or_default()));
        if let Some(old)=cache.pending.insert(identity,bytes.clone()) {cache.pending_bytes=cache.pending_bytes.saturating_sub(old.len());}
        cache.pending_bytes+=bytes.len();
    }
}

/// Bulk addressed restore in authored owner order. Entries absent from this
/// revision are neither fetched nor decoded. The cache remains optional.
fn hydrate_values(model:&SemanticDeclarations) {
    let mut cache=value_cache().lock().unwrap_or_else(|error|error.into_inner());
    let Some(store)=cache.store.clone() else {return;};
    let mut slots:Vec<_>=model.owners.iter().flat_map(|(owner,scope)|scope.fields.keys().map(move|name|(owner.clone(),name.clone())))
        .chain(model.globals.keys().map(|name|(String::new(),name.clone()))).filter(|key|!cache.entries.contains_key(key)).collect();
    for (owner,scope) in &model.owners {
        let blocked:HashSet<_>=scope.fields.iter().filter(|(_,field)|!field.constant).map(|(name,_)|name.clone()).collect();
        for field in scope.fields.values() {
            if let Some(source)=field.expression.as_deref().filter(|source|!dependency_free_literal(source)) {
                slots.push((owner.clone(),expression_key(source,&HashSet::new())));
                slots.push((owner.clone(),expression_key(source,&blocked)));
            }
        }
    }
    for field in model.globals.values() {
        if let Some(source)=field.expression.as_deref().filter(|source|!dependency_free_literal(source)) {slots.push((String::new(),expression_key(source,&HashSet::new())));}
    }
    slots.sort();slots.dedup();
    slots.retain(|key|!cache.entries.contains_key(key));
    for slots in slots.chunks(4096) {
        let keys:Vec<_>=slots.iter().map(|key|dm_store::Key::new(value_namespace(),format!("{:x}",Sha256::digest(serde_json::to_vec(key).unwrap_or_default())))).collect();
        let Ok(read)=store.read_grouped_bounded(&keys,128,1024*1024,8*1024*1024,64*1024*1024,None) else {continue;};
        for (key,bytes) in slots.iter().zip(read.values) {
            let Some(bytes)=bytes else {continue;};
            let Ok(record)=serde_json::from_slice::<ResolvedValue>(&bytes) else {continue;};
            if record.owner!=key.0||record.name!=key.1 {continue;}
            let size=bytes.len()*3+128;
            if size>32*1024*1024 {continue;}
            while cache.bytes.saturating_add(size)>32*1024*1024 {
                let Some(key)=cache.entries.keys().next().cloned() else {break;};
                if let Some((_,old))=cache.entries.remove(&key) {cache.bytes=cache.bytes.saturating_sub(old);}
            }
            if let Some((_,old))=cache.entries.remove(key) {cache.bytes=cache.bytes.saturating_sub(old);}
            cache.bytes+=size;cache.entries.insert(key.clone(),(Arc::new(record),size));
        }
    }
}
