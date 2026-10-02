//! Persistent owner recipes and immutable declaration-map roots. Body syntax,
//! offsets and physical allocation IDs never enter these nodes.
use super::*;
use dm_store::{Store,Key,Change};
const LIMIT:usize=32*1024*1024;
#[derive(Default)]
struct Artifacts {
    root:Option<std::path::PathBuf>,store:Option<Store>,
    owners:BTreeMap<String,(Arc<Owner>,usize)>,seeds:BTreeMap<String,(Arc<BuiltinModel>,usize)>,
    missing:BTreeSet<String>,bytes:usize,pending:BTreeMap<Key,Vec<u8>>,pending_bytes:usize,
}
fn artifacts()->&'static Mutex<Artifacts> {
    static CACHE:OnceLock<Mutex<Artifacts>>=OnceLock::new();
    CACHE.get_or_init(||Mutex::new(Artifacts::default()))
}
fn namespace()->String {format!("symbolic-owner-recipes-v2-{}",env!("DM_EMISSION_FINGERPRINT"))}
fn seeds_namespace()->String {format!("symbolic-builtin-schema-v1-{}",env!("DM_EMISSION_FINGERPRINT"))}
pub(super) fn bind(root:&std::path::Path) {
    let mut cache=artifacts().lock().unwrap_or_else(|error|error.into_inner());
    if cache.root.as_deref()==Some(root) {return;}
    flush_locked(&mut cache);
    *cache=Artifacts {root:Some(root.to_owned()),store:Store::open(root.join("resolved-declarations.redb")).ok(),..Default::default()};
}
fn flush_locked(cache:&mut Artifacts) {
    let Some(store)=&cache.store else {cache.pending.clear();cache.pending_bytes=0;return;};
    let changes:Vec<_>=cache.pending.iter().map(|(key,bytes)|Change::Put(key.clone(),bytes.clone())).collect();
    if store.commit(&[],&changes,None).is_ok() {cache.pending.clear();cache.pending_bytes=0;}
}
pub(super) fn flush() {flush_locked(&mut artifacts().lock().unwrap_or_else(|error|error.into_inner()));}
fn queue(cache:&mut Artifacts,key:Key,bytes:Vec<u8>) {
    if cache.pending_bytes.saturating_add(bytes.len())>4*1024*1024 {flush_locked(cache);}
    cache.pending_bytes+=bytes.len();
    if let Some(old)=cache.pending.insert(key,bytes) {cache.pending_bytes=cache.pending_bytes.saturating_sub(old.len());}
}
fn charge(owner:&Owner)->usize {
    128+owner.parent.as_ref().map_or(0,String::capacity)+owner.fields.iter().map(|(name,field)|
        128+name.capacity()+field.expression.as_ref().map_or(0,String::capacity)+match &field.imported {
            Some(const_eval::Constant::Text(text))|Some(const_eval::Constant::TypePath(text))=>text.capacity(),
            Some(const_eval::Constant::EncodedText(text))=>text.capacity(),_=>0,
        }).sum::<usize>()
}
fn retain(cache:&mut Artifacts,key:String,owner:Arc<Owner>) {
    let size=charge(&owner);
    if size>LIMIT {return;}
    if let Some((_,old))=cache.owners.remove(&key) {cache.bytes=cache.bytes.saturating_sub(old);}
    while cache.bytes.saturating_add(size)>LIMIT {
        let Some(key)=cache.owners.keys().next().cloned() else {break;};
        if let Some((_,old))=cache.owners.remove(&key) {cache.bytes=cache.bytes.saturating_sub(old);}
    }
    cache.bytes+=size;cache.owners.insert(key, (owner,size));
}
fn hydrate(identities:&[String]) {
    let mut cache=artifacts().lock().unwrap_or_else(|error|error.into_inner());
    let Some(store)=cache.store.clone() else {return;};
    let keys:Vec<_>=identities.iter().filter(|identity|!cache.owners.contains_key(*identity)&&!cache.missing.contains(*identity)).map(|identity|Key::new(namespace(),identity)).collect();
    for keys in keys.chunks(4096) {
        default_plans::read_stage_batch(&store,keys,2*1024*1024,8*1024*1024,&mut |key,bytes| {
            if let Some(bytes)=bytes {
                if let Ok(owner)=rmp_serde::from_slice::<Owner>(&bytes) {retain(&mut cache,key.name.clone(),Arc::new(owner));}
            } else if cache.missing.len()<128_000 {cache.missing.insert(key.name.clone());}
        });
    }
}
fn owner_fragment(identity:&str,base:Option<&Arc<Owner>>,path:&str,plans:&[Arc<default_plans::OwnerDeclarationPlan>])->Arc<Owner> {
    if let Some(owner)=artifacts().lock().unwrap_or_else(|error|error.into_inner()).owners.get(identity).map(|(owner,_)|Arc::clone(owner)) {return owner;}
    let lexical=lexical_parent(path).map(str::to_owned);
    let mut owner=base.map(|owner|owner.as_ref().clone()).unwrap_or_else(||Owner {parent:lexical,fields:BTreeMap::new()});
    for plan in plans {
        if let Some(parent)=&plan.explicit_parent {owner.parent=Some(parent.clone());}
        for expression in &plan.expressions {
            if expression.override_only {
                let field=owner.fields.entry(expression.name.clone()).or_insert(Field {expression:None,constant:false,override_only:true,imported:None});
                field.expression=expression.expression.clone();field.imported=None;field.override_only=true;
            } else {
                owner.fields.insert(expression.name.clone(),Field {expression:expression.expression.clone(),constant:expression.constant,override_only:false,imported:None});
            }
        }
    }
    let owner=Arc::new(owner);
    let mut cache=artifacts().lock().unwrap_or_else(|error|error.into_inner());
    if let Ok(bytes)=rmp_serde::to_vec_named(owner.as_ref()) {
        if bytes.len()<=2*1024*1024 {queue(&mut cache,Key::new(namespace(),identity),bytes);}
    }
    retain(&mut cache,identity.to_owned(),Arc::clone(&owner));owner
}
fn builtin_model(image:&Dmb,identity:&str)->Arc<BuiltinModel> {
    {
        let cache=artifacts().lock().unwrap_or_else(|error|error.into_inner());
        if let Some((model,_))=cache.seeds.get(identity) {return Arc::clone(model);}
        if let Some(store)=&cache.store {
            if let Ok(read)=store.read_many_bounded(&[Key::new(seeds_namespace(),identity)],16*1024*1024,16*1024*1024,None) {
                if let Some(bytes)=read.values.first().and_then(Option::as_deref) {
                    if let Ok(model)=rmp_serde::from_slice::<BuiltinModel>(bytes) {return Arc::new(model);}
                }
            }
        }
    }
    let mut model=BuiltinModel::default();let strings=StringIndex::new(image);
    for (class_id,class) in image.classes.iter().enumerate() {
        let Some(path)=image.string(class.path_string_id()).and_then(|path|std::str::from_utf8(path).ok()) else {continue;};
        let parent=image.classes.get(class.parent_class_id() as usize).and_then(|class|image.string(class.path_string_id())).and_then(|path|std::str::from_utf8(path).ok()).map(str::to_owned);
        let mut owner=Owner {parent,fields:BTreeMap::new()};
        for (id,flags) in image.class_variable_declarations(class_id).unwrap_or_default() {
            let variable=&image.variables[id as usize];
            let Some(name)=image.string(variable.name).and_then(|name|std::str::from_utf8(name).ok()) else {continue;};
            owner.fields.insert(name.to_owned(),Field {expression:None,constant:flags&2!=0,override_only:false,imported:constant_from_variable(image,id,&strings)});
        }
        for value in image.class_initial_values(class_id).unwrap_or_default() {
            let Some(name)=image.string(image.variables[value.variable_id as usize].name).and_then(|name|std::str::from_utf8(name).ok()) else {continue;};
            let imported=constant_from_value(image,&Variable {name:0,kind:value.value.tag(),value:value.value.number_bits().unwrap_or_else(||value.value.id())},&strings);
            owner.fields.entry(name.to_owned()).or_insert(Field {expression:None,constant:false,override_only:false,imported:None}).imported=imported;
        }
        model.owners.insert(path.to_owned(),Arc::new(owner));
    }
    for (name,id) in &strings.1 {model.globals.insert(name.clone(),Field {expression:None,constant:true,override_only:false,imported:constant_from_variable(image,*id,&strings)});}
    let size=model.owners.values().map(|owner|charge(owner)).sum::<usize>()+model.globals.len()*128;
    let model=Arc::new(model);let mut cache=artifacts().lock().unwrap_or_else(|error|error.into_inner());
    if let Ok(bytes)=rmp_serde::to_vec_named(model.as_ref()) {if bytes.len()<=16*1024*1024 {queue(&mut cache,Key::new(seeds_namespace(),identity),bytes);}}
    // Two native versions suffice for ordinary version-policy transitions.
    if size<=16*1024*1024 {
        while cache.seeds.len()>=2 {if let Some(key)=cache.seeds.keys().next().cloned() {cache.seeds.remove(&key);} else {break;}}
        cache.seeds.insert(identity.to_owned(),(Arc::clone(&model),size));
    }
    model
}
/// Immutable source declaration outputs. Procedure bodies, offsets and physical
/// IDs are absent; source order is preserved by the caller's shard sequence.
#[derive(Clone,Serialize,Deserialize)]
struct SourceShard {
    identity:String,
    owners:Vec<(String,Arc<default_plans::OwnerDeclarationPlan>)>,
    globals:Vec<(String,Field)>,
    owner_slots:BTreeMap<String,Vec<usize>>,
    #[serde(skip)]
    retained_bytes:usize,
}
struct SourceShardEntry { source:std::sync::Weak<dm_syntax::AstFile>, shard:std::sync::Weak<SourceShard>, bytes:usize }
#[derive(Default)]
struct SourceShards { entries:BTreeMap<usize,SourceShardEntry>,bytes:usize }
fn source_shards()->&'static Mutex<SourceShards> {
    static SHARDS:OnceLock<Mutex<SourceShards>>=OnceLock::new();
    SHARDS.get_or_init(||Mutex::new(SourceShards::default()))
}
fn shard_namespace()->String {format!("semantic-source-declarations-v3-{}",env!("DM_EMISSION_FINGERPRINT"))}
fn shard_identity(items:&[Item])->String {
    fn rows(hash:&mut Sha256,items:&[Item]) {
        for (index,item) in items.iter().enumerate() {
            if matches!(item.kind,ItemKind::Proc|ItemKind::Verb) {continue;}
            // Authored owner plans carry child indexes for ordered allocation.
            // A new procedure can shift those indexes even when default values
            // remain equal; semantic owner identity still hashes plan outputs.
            hash.update((index as u64).to_le_bytes());hash.update([item.kind as u8]);hash.update((item.header.len() as u64).to_le_bytes());hash.update(item.header.as_bytes());
            rows(hash,&item.children);hash.update([255]);
        }
    }
    let mut hash=Sha256::new();hash.update(b"semantic-source-declarations-v3\0");rows(&mut hash,items);format!("{:x}",hash.finalize())
}
fn derive_shard(items:&[Item],identity:String,workers:usize)->Arc<SourceShard> {derive_prepared_shard(items,identity,workers,None)}
fn derive_prepared_shard(items:&[Item],identity:String,workers:usize,prepared:Option<Vec<Arc<default_plans::OwnerDeclarationPlan>>>)->Arc<SourceShard> {
    let mut types=Vec::new();collect_type_items(items,&mut types);
    let plans=if let Some(plans)=prepared {plans} else {default_plans::prefetch(items,workers);default_plans::owner_batch(&types,workers)};
    let owners:Vec<_>=types.into_iter().zip(plans).map(|(item,plan)|(item.header.trim().to_owned(),plan)).collect();
    let mut owner_slots=BTreeMap::<String,Vec<usize>>::new();
    for (index,(path,_)) in owners.iter().enumerate() {owner_slots.entry(path.clone()).or_default().push(index);}
    let mut globals=Vec::new();
    for item in items.iter().filter(|item|item.kind==ItemKind::Var) {
        if let Ok(plan)=default_plans::declaration(item.header.trim()) {
            let name=plan.name.split('[').next().unwrap_or(&plan.name).to_owned();
            let expression=if plan.name.contains('[') {"list()".to_owned()} else {plan.initial.clone().unwrap_or_else(||"null".to_owned())};
            globals.push((name,Field {expression:Some(expression),constant:plan.is_const,override_only:false,imported:None}));
        }
    }
    let mut shard=SourceShard {identity,owners,globals,owner_slots,retained_bytes:0};
    shard.retained_bytes=shard_charge(&shard);
    let shard=Arc::new(shard);
    if let Ok(bytes)=rmp_serde::to_vec_named(shard.as_ref()) {
        if bytes.len()<=8*1024*1024 {queue(&mut artifacts().lock().unwrap_or_else(|e|e.into_inner()),Key::new(shard_namespace(),&shard.identity),bytes);}
    }
    shard
}
fn shard_charge(shard:&SourceShard)->usize {
    fn plan_charge(plan:&default_plans::OwnerDeclarationPlan)->usize {
        256+plan.identity.capacity()+plan.semantic_identity.capacity()+plan.explicit_parent.as_ref().map_or(0,String::capacity)
            +plan.expressions.capacity()*std::mem::size_of::<default_plans::OwnerFieldExpression>()
            +plan.expressions.iter().map(|field|field.name.capacity()+field.expression.as_ref().map_or(0,String::capacity)).sum::<usize>()
            +plan.const_indexes.capacity()*std::mem::size_of::<usize>()
            +plan.mutable_names.iter().map(|name|name.capacity()+64).sum::<usize>()
            +plan.field_types.iter().map(|(name,kind)|name.capacity()+kind.capacity()+96).sum::<usize>()
    }
    256+shard.identity.capacity()+shard.owners.capacity()*std::mem::size_of::<(String,Arc<default_plans::OwnerDeclarationPlan>)>()
        +shard.owners.iter().map(|(path,plan)|path.capacity()+plan_charge(plan)).sum::<usize>()
        +shard.owner_slots.iter().map(|(path,slots)|path.capacity()+slots.capacity()*std::mem::size_of::<usize>()+96).sum::<usize>()
        +shard.globals.capacity()*std::mem::size_of::<(String,Field)>()
        +shard.globals.iter().map(|(name,field)|name.capacity()+field.expression.as_ref().map_or(0,String::capacity)+128).sum::<usize>()
}
fn cached_shard(ast:&Arc<dm_syntax::AstFile>)->Option<Arc<SourceShard>> {
    let cache=source_shards().lock().unwrap_or_else(|e|e.into_inner());
    let entry=cache.entries.get(&(Arc::as_ptr(ast) as usize))?;
    entry.source.upgrade().filter(|source|Arc::ptr_eq(source,ast)).and_then(|_|entry.shard.upgrade())
}
fn retain_shard(ast:&Arc<dm_syntax::AstFile>,shard:&Arc<SourceShard>) {
    let pointer=Arc::as_ptr(ast) as usize;
    let bytes=192;
    let mut cache=source_shards().lock().unwrap_or_else(|e|e.into_inner());
    if let Some(old)=cache.entries.remove(&pointer) {cache.bytes=cache.bytes.saturating_sub(old.bytes);}
    while cache.bytes.saturating_add(bytes)>16*1024*1024||cache.entries.len()>=8192 {
        let Some(key)=cache.entries.keys().next().copied() else {break;};
        if let Some(old)=cache.entries.remove(&key) {cache.bytes=cache.bytes.saturating_sub(old.bytes);}
    }
    if bytes<=16*1024*1024 {cache.bytes+=bytes;cache.entries.insert(pointer,SourceShardEntry {source:Arc::downgrade(ast),shard:Arc::downgrade(shard),bytes});}
}
fn shards_for(asts:&[&Arc<dm_syntax::AstFile>],workers:usize,previous:Option<&Arc<SemanticDeclarations>>)->Vec<Arc<SourceShard>> {
    let store=artifacts().lock().unwrap_or_else(|e|e.into_inner()).store.clone();
    let previous_shards:BTreeMap<_,_>=previous.and_then(|model|model.source_index.as_ref()).into_iter().flat_map(|index|index.shards.iter()).map(|shard|(shard.identity.as_str(),shard)).collect();
    let mut result=Vec::with_capacity(asts.len());
    // Address only changed source fragments. Hydration has one shared bounded
    // read path; no namespace inventories or per-fragment database sessions.
    for window in asts.chunks(128) {
        let mut candidates:Vec<_>=window.iter().map(|ast|cached_shard(ast)).collect();
        let identities:Vec<_>=window.iter().zip(&candidates).map(|(ast,candidate)|candidate.is_none().then(||shard_identity(&ast.items))).collect();
        for ((ast,candidate),identity) in window.iter().zip(candidates.iter_mut()).zip(&identities) {if candidate.is_none() {if let Some(shard)=identity.as_ref().and_then(|identity|previous_shards.get(identity.as_str())) {retain_shard(ast,shard);*candidate=Some(Arc::clone(shard));}}}
        let keys:Vec<_>=identities.iter().zip(&candidates).filter_map(|(identity,candidate)|candidate.is_none().then(||identity.as_ref()).flatten()).map(|identity|Key::new(shard_namespace(),identity)).collect();
        let mut restored=BTreeMap::new();
        if let Some(store)=&store {default_plans::read_stage_batch(store,&keys,8*1024*1024,8*1024*1024,&mut |key,bytes| {
            if let Some(mut shard)=bytes.as_deref().and_then(|bytes|rmp_serde::from_slice::<SourceShard>(bytes).ok()).filter(|shard|shard.identity==key.name) {shard.retained_bytes=shard_charge(&shard);restored.insert(key.name.clone(),Arc::new(shard));}
        });}
        // Batch pure syntax derivation for all missing shards in this window.
        // This uses the configured scheduler once, rather than starting a pool
        // and opening authored-plan sessions for every individual source file.
        let roots:Vec<_>=window.iter().zip(&candidates).zip(&identities)
            .filter(|((_,candidate),identity)|candidate.is_none()&&identity.as_ref().is_some_and(|identity|!restored.contains_key(identity)))
            .map(|((ast,_),_)|ast.items.as_slice()).collect();
        default_plans::prefetch_roots(&roots,workers);
        let mut owner_items=Vec::new();for items in &roots {collect_type_items(items,&mut owner_items);}
        let mut plans=default_plans::owner_batch(&owner_items,workers).into_iter();
        for ((ast,candidate),identity) in window.iter().zip(candidates.iter_mut()).zip(identities) {
            let shard=if let Some(shard)=candidate.take() {shard} else {
                let identity=identity.expect("missing source shard identity");
                let shard=if let Some(shard)=restored.get(&identity) {Arc::clone(shard)} else {
                    let mut types=Vec::new();collect_type_items(&ast.items,&mut types);
                    let prepared=plans.by_ref().take(types.len()).collect();
                    derive_prepared_shard(&ast.items,identity,workers,Some(prepared))
                };
                retain_shard(ast,&shard);shard
            };
            result.push(shard);
        }
    }
    result
}
pub(super) fn build(items:&[Item],modified:&[Item],builtin:&Dmb,builtin_image:&[u8],previous:Option<&Arc<SemanticDeclarations>>,workers:usize)->Arc<SemanticDeclarations> {
    let shard=derive_shard(items,shard_identity(items),workers);
    compose_shards(&[shard],modified,builtin,builtin_image,previous,workers)
}
pub(super) fn build_fragments(fragments:&[dm_analysis::FrontendFragment],modified:&[Item],builtin:&Dmb,builtin_image:&[u8],previous:Option<&Arc<SemanticDeclarations>>,workers:usize)->Arc<SemanticDeclarations> {
    let asts:Vec<_>=fragments.iter().map(|fragment|&fragment.ast).collect();
    let shards=shards_for(&asts,workers,previous);
    compose_shards(&shards,modified,builtin,builtin_image,previous,workers)
}
pub(super) fn build_local_fragments(fragments:&[(usize,Arc<dm_syntax::AstFile>)],modified:&[Item],builtin:&Dmb,builtin_image:&[u8],previous:Option<&Arc<SemanticDeclarations>>,workers:usize)->Arc<SemanticDeclarations> {
    let asts:Vec<_>=fragments.iter().map(|(_,ast)|ast).collect();
    let shards=shards_for(&asts,workers,previous);
    compose_shards(&shards,modified,builtin,builtin_image,previous,workers)
}
pub(super) struct SourceDeclarationIndex {
    shards:Vec<Arc<SourceShard>>,
    owners:im::HashMap<String,Arc<Vec<Arc<default_plans::OwnerDeclarationPlan>>>>,
    authored_globals:im::HashMap<String,Field>,
}
impl SourceDeclarationIndex {
    pub(super) fn owner_plan(&self,item:&Item)->Option<Arc<default_plans::OwnerDeclarationPlan>> {
        let key=default_plans::owner_key(item);
        self.owners.get(item.header.trim())?.iter().find(|plan|plan.identity==key).map(Arc::clone)
    }
    pub(super) fn resident_bytes(&self)->usize {
        let mut seen=HashSet::new();
        self.owners.len()*128+self.authored_globals.len()*160+self.shards.capacity()*std::mem::size_of::<Arc<SourceShard>>()
            +self.shards.iter().map(|shard| {
                if !seen.insert(Arc::as_ptr(shard) as usize) {return 0;}
                // Shared immutable plans are charged by ownership. The index
                // payload and its distinct source-order contribution arrays
                // remain charged even when the source AST has been discarded.
                shard.retained_bytes/Arc::strong_count(shard).max(1)
            }).sum::<usize>()
            +self.owners.values().map(|plans|plans.capacity()*std::mem::size_of::<Arc<default_plans::OwnerDeclarationPlan>>()+64).sum::<usize>()
    }
}
fn compose_shards(shards:&[Arc<SourceShard>],modified:&[Item],builtin:&Dmb,builtin_image:&[u8],previous:Option<&Arc<SemanticDeclarations>>,workers:usize)->Arc<SemanticDeclarations> {
    let started=std::time::Instant::now();let identity=format!("{:x}",Sha256::digest(builtin_image));
    let previous=previous.filter(|model|model.builtin_identity==identity);
    let builtins=previous.map(|model|Arc::clone(&model.builtins)).unwrap_or_else(||builtin_model(builtin,&identity));
    let mut owners=previous.map(|model|model.owners.clone()).unwrap_or_else(||builtins.owners.clone());
    let mut globals=previous.map(|model|model.globals.clone()).unwrap_or_else(||builtins.globals.clone());
    let mut recipes=previous.map(|model|model.recipes.clone()).unwrap_or_default();
    let modified_shard=derive_shard(modified,shard_identity(modified),workers);
    let current:Vec<_>=shards.iter().cloned().chain(std::iter::once(modified_shard)).collect();
    let old_index=previous.and_then(|model|model.source_index.as_ref());
    // Occurrence keys preserve repeated includes and source-order overrides.
    fn occurrences(shards:&[Arc<SourceShard>])->Vec<(String,usize)> {
        let mut counts=BTreeMap::<&str,usize>::new();
        shards.iter().map(|shard| {let count=counts.entry(&shard.identity).or_default();let key=(shard.identity.clone(),*count);*count+=1;key}).collect()
    }
    let new_order=occurrences(&current);
    let old_order=old_index.map(|index|occurrences(&index.shards)).unwrap_or_default();
    if old_order==new_order {if let Some(previous)=previous {return Arc::clone(previous);}}
    let old_keys:BTreeSet<_>=old_order.iter().cloned().collect();let new_keys:BTreeSet<_>=new_order.iter().cloned().collect();
    let common_old:Vec<_>=old_order.iter().filter(|key|new_keys.contains(*key)).collect();
    let common_new:Vec<_>=new_order.iter().filter(|key|old_keys.contains(*key)).collect();
    let reordered=common_old!=common_new;
    let mut affected=BTreeSet::new();let mut affected_globals=BTreeSet::new();
    let old_shards=old_index.map(|index|index.shards.as_slice()).unwrap_or(&[]);
    for (shard,key) in old_shards.iter().zip(&old_order).chain(current.iter().zip(&new_order)) {
        if reordered||!old_keys.contains(key)||!new_keys.contains(key) {
            affected.extend(shard.owner_slots.keys().cloned());affected_globals.extend(shard.globals.iter().map(|(name,_)|name.clone()));
        }
    }
    let mut groups=old_index.map(|index|index.owners.clone()).unwrap_or_default();
    let mut authored=old_index.map(|index|index.authored_globals.clone()).unwrap_or_default();
    let mut requested=BTreeMap::<String,Vec<Arc<default_plans::OwnerDeclarationPlan>>>::new();
    let mut selected_globals=BTreeMap::new();
    for shard in &current {
        for (path,plan) in &shard.owners {if affected.contains(path) {requested.entry(path.clone()).or_default().push(Arc::clone(plan));}}
    }
    for shard in shards {for (name,field) in &shard.globals {if affected_globals.contains(name) {selected_globals.insert(name.clone(),field.clone());}}}
    let mut next=BTreeMap::new();
    for path in &affected {
        let Some(plans)=requested.remove(path) else {groups.remove(path);continue;};
        let mut hash=Sha256::new();hash.update(b"symbolic-owner-input-v3\0");hash.update(identity.as_bytes());hash.update((path.len() as u64).to_le_bytes());hash.update(path.as_bytes());
        for plan in &plans {hash.update(plan.semantic_identity.as_bytes());}
        next.insert(path.clone(),format!("{:x}",hash.finalize()));groups.insert(path.clone(),Arc::new(plans));
    }
    for name in &affected_globals {
        if let Some(field)=selected_globals.remove(name) {authored.insert(name.clone(),field);} else {authored.remove(name);}
    }
    let source_index=Arc::new(SourceDeclarationIndex {shards:current,owners:groups.clone(),authored_globals:authored.clone()});
    let changed:Vec<_>=next.iter().filter(|(path,identity)|recipes.get(*path)!=Some(*identity)).map(|(_,identity)|identity.clone()).collect();hydrate(&changed);
    let removed:Vec<_>=affected.iter().filter(|path|!groups.contains_key(*path)&&recipes.contains_key(*path)).cloned().collect();
    let changed_paths:BTreeSet<_>=next.iter().filter(|(path,identity)|recipes.get(*path)!=Some(*identity)).map(|(path,_)|path.clone()).chain(removed.iter().cloned()).collect();
    let _owners_changed=!changed.is_empty()||!removed.is_empty();
    for path in removed {recipes.remove(&path);if let Some(base)=builtins.owners.get(&path) {owners.insert(path,Arc::clone(base));} else {owners.remove(&path);}}
    let mut reused=0;let mut rebuilt=0;
    for (path,recipe) in next {
        if recipes.get(&path)==Some(&recipe) {reused+=1;continue;}
        let owner=owner_fragment(&recipe,builtins.owners.get(&path),&path,&groups[&path]);owners.insert(path.clone(),owner);recipes.insert(path,recipe);rebuilt+=1;
    }
    let mut globals_changed=false;let mut changed_globals=BTreeSet::new();
    for name in &affected_globals {
        let selected=authored.get(name).or_else(||builtins.globals.get(name));
        if field_identity(globals.get(name))!=field_identity(selected) {
            globals_changed=true;changed_globals.insert(name.clone());
            if let Some(field)=selected {globals.insert(name.clone(),field.clone());} else {globals.remove(name);}
        }
    }
    let model=Arc::new(SemanticDeclarations {generation:next_model_generation(),owners,globals,recipes,builtin_identity:identity,builtins,source_index:Some(source_index),previous_generation:previous.map(|model|model.generation),changes:DeclarationChanges {owners:changed_paths.clone(),globals:changed_globals}});
    hydrate_values(&model,previous.map(|_|&changed_paths),globals_changed||previous.is_none());
    if std::env::var_os("DM_BUILD_TRACE").is_some() {eprintln!("DM_BUILD_TRACE symbolic owner DAG: {reused} unchanged, {rebuilt} changed/imported cached shard recipes in {:.3}s",started.elapsed().as_secs_f64());}
    model
}
pub(super) fn resident_bytes()->usize {
    let cache=artifacts().lock().unwrap_or_else(|error|error.into_inner());
    source_shards().lock().unwrap_or_else(|e|e.into_inner()).bytes+cache.pending_bytes+cache.owners.iter().map(|(key,(owner,size))|key.capacity()+96+size.div_ceil(Arc::strong_count(owner).max(1))).sum::<usize>()
        +cache.seeds.values().map(|(model,size)|size.div_ceil(Arc::strong_count(model).max(1))).sum::<usize>()+cache.missing.len()*96
}
pub(super) fn trim_to(max_bytes:usize) {
    {let mut shards=source_shards().lock().unwrap_or_else(|e|e.into_inner());
        shards.entries.retain(|_,entry|entry.source.strong_count()!=0&&entry.shard.strong_count()!=0);
        shards.bytes=shards.entries.values().map(|entry|entry.bytes).sum();
        while shards.bytes>max_bytes/4 {
            let Some(key)=shards.entries.keys().next().copied() else {break;};
            if let Some(entry)=shards.entries.remove(&key) {shards.bytes=shards.bytes.saturating_sub(entry.bytes);}
        }
    }
    let mut cache=artifacts().lock().unwrap_or_else(|error|error.into_inner());flush_locked(&mut cache);
    // Decoded lookup ownership is expendable; immutable models keep their Arc
    // fragments. Negative inventories and native seeds also count toward the
    // same requested budget, rather than escaping a trim of owner rows alone.
    cache.missing.clear();
    while cache.bytes+cache.seeds.values().map(|(_,size)|*size).sum::<usize>()>max_bytes {
        if let Some(key)=cache.seeds.keys().next().cloned() {cache.seeds.remove(&key);continue;}
        let Some(key)=cache.owners.keys().next().cloned() else {break;};
        if let Some((_,size))=cache.owners.remove(&key) {cache.bytes=cache.bytes.saturating_sub(size);}
    }
}
