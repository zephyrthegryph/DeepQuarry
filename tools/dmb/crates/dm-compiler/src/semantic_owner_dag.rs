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
pub(super) fn build(items:&[Item],modified:&[Item],builtin:&Dmb,builtin_image:&[u8],previous:Option<&Arc<SemanticDeclarations>>,workers:usize)->Arc<SemanticDeclarations> {
    build_roots(&[items],modified,builtin,builtin_image,previous,workers)
}
pub(super) fn build_fragments(fragments:&[dm_analysis::FrontendFragment],modified:&[Item],builtin:&Dmb,builtin_image:&[u8],previous:Option<&Arc<SemanticDeclarations>>,workers:usize)->Arc<SemanticDeclarations> {
    let roots:Vec<_>=fragments.iter().map(|fragment|fragment.ast.items.as_slice()).collect();
    build_roots(&roots,modified,builtin,builtin_image,previous,workers)
}
fn build_roots(roots:&[&[Item]],modified:&[Item],builtin:&Dmb,builtin_image:&[u8],previous:Option<&Arc<SemanticDeclarations>>,workers:usize)->Arc<SemanticDeclarations> {
    let started=std::time::Instant::now();let identity=format!("{:x}",Sha256::digest(builtin_image));
    let previous=previous.filter(|model|model.builtin_identity==identity);
    let builtins=previous.map(|model|Arc::clone(&model.builtins)).unwrap_or_else(||builtin_model(builtin,&identity));
    let mut owners=previous.map(|model|model.owners.clone()).unwrap_or_else(||builtins.owners.clone());
    let mut globals=previous.map(|model|model.globals.clone()).unwrap_or_else(||builtins.globals.clone());
    let mut recipes=previous.map(|model|model.recipes.clone()).unwrap_or_default();
    let mut types=Vec::new();for items in roots {collect_type_items(items,&mut types);}types.extend(modified.iter());
    // Semantic owner identity contains local declarations only. Procedure
    // headers and child offsets affect physical plans, never this database.
    // Derive syntax plans only for owners whose declaration rows changed.
    let mut source_groups=BTreeMap::<String,Vec<&Item>>::new();
    for item in types {source_groups.entry(item.header.trim().to_owned()).or_default().push(item);}
    let next:BTreeMap<_,_>=source_groups.iter().map(|(path,items)| {
        let mut hash=Sha256::new();hash.update(b"symbolic-owner-input-v2\0");
        hash.update(identity.as_bytes());hash.update((path.len() as u64).to_le_bytes());hash.update(path.as_bytes());
        for item in items {
            for child in &item.children {
                if matches!(child.kind,ItemKind::Var|ItemKind::Unknown|ItemKind::Statement) {
                    hash.update([child.kind as u8]);hash.update((child.header.len() as u64).to_le_bytes());hash.update(child.header.as_bytes());
                }
            }
        }
        (path.clone(),format!("{:x}",hash.finalize()))
    }).collect();
    let changed:Vec<_>=next.iter().filter(|(path,identity)|recipes.get(*path)!=Some(*identity)).map(|(_,identity)|identity.clone()).collect();
    hydrate(&changed);
    let changed_types:Vec<_>=source_groups.iter().filter(|(path,_)|recipes.get(*path)!=next.get(*path))
        .flat_map(|(_,items)|items.iter().copied()).collect();
    let owner_plans=default_plans::owner_batch(&changed_types,workers);
    let mut groups=BTreeMap::<String,Vec<Arc<default_plans::OwnerDeclarationPlan>>>::new();
    for (item,plan) in changed_types.into_iter().zip(owner_plans) {groups.entry(item.header.trim().to_owned()).or_default().push(plan);}
    let removed:Vec<_>=recipes.keys().filter(|path|!path.is_empty()&&!next.contains_key(*path)).cloned().collect();
    let changed_paths:BTreeSet<_>=next.iter().filter(|(path,identity)|recipes.get(*path)!=Some(*identity)).map(|(path,_)|path.clone()).chain(removed.iter().cloned()).collect();
    let owners_changed=!changed.is_empty()||!removed.is_empty();
    for path in removed {
        recipes.remove(&path);if let Some(base)=builtins.owners.get(&path) {owners.insert(path,Arc::clone(base));} else {owners.remove(&path);}
    }
    let mut reused=0;let mut rebuilt=0;
    for (path,recipe) in next {
        if recipes.get(&path)==Some(&recipe) {reused+=1;continue;}
        let owner=owner_fragment(&recipe,builtins.owners.get(&path),&path,&groups[&path]);
        owners.insert(path.clone(),owner);recipes.insert(path,recipe);rebuilt+=1;
    }
    // Globals have one lexical owner. Replace only changed field rows while
    // preserving the persistent map root for unaffected declarations.
    let mut authored=BTreeMap::new();
    for item in roots.iter().flat_map(|items|items.iter()).filter(|item|item.kind==ItemKind::Var) {
        if let Ok(plan)=default_plans::declaration(item.header.trim()) {
            let name=plan.name.split('[').next().unwrap_or(&plan.name).to_owned();
            let expression=if plan.name.contains('[') {"list()".to_owned()} else {plan.initial.clone().unwrap_or_else(||"null".to_owned())};
            authored.insert(name,Field {expression:Some(expression),constant:plan.is_const,override_only:false,imported:None});
        }
    }
    let removed:Vec<_>=globals.keys().filter(|name|!authored.contains_key(*name)&&!builtins.globals.contains_key(*name)).cloned().collect();
    let mut globals_changed=!removed.is_empty();
    for name in removed {globals.remove(&name);}
    for (name,field) in &builtins.globals {
        if !authored.contains_key(name)&&field_identity(globals.get(name))!=field_identity(Some(field)) {globals_changed=true;globals.insert(name.clone(),field.clone());}
    }
    for (name,field) in authored {
        if field_identity(globals.get(&name))!=field_identity(Some(&field)) {globals_changed=true;globals.insert(name,field);}
    }
    if !owners_changed&&!globals_changed {
        if let Some(previous)=previous {
            if std::env::var_os("DM_BUILD_TRACE").is_some() {eprintln!("DM_BUILD_TRACE symbolic owner DAG: unchanged semantic model reused in {:.3}s",started.elapsed().as_secs_f64());}
            return Arc::clone(previous);
        }
    }
    let model=Arc::new(SemanticDeclarations {generation:next_model_generation(),owners,globals,recipes,builtin_identity:identity,builtins});
    hydrate_values(&model,previous.map(|_|&changed_paths),globals_changed||previous.is_none());
    if std::env::var_os("DM_BUILD_TRACE").is_some() {eprintln!("DM_BUILD_TRACE symbolic owner DAG: {reused} unchanged, {rebuilt} changed/imported recipes in {:.3}s",started.elapsed().as_secs_f64());}
    model
}
pub(super) fn resident_bytes()->usize {
    let cache=artifacts().lock().unwrap_or_else(|error|error.into_inner());
    cache.pending_bytes+cache.owners.iter().map(|(key,(owner,size))|key.capacity()+96+size.div_ceil(Arc::strong_count(owner).max(1))).sum::<usize>()
        +cache.seeds.values().map(|(model,size)|size.div_ceil(Arc::strong_count(model).max(1))).sum::<usize>()+cache.missing.len()*96
}
pub(super) fn trim_to(max_bytes:usize) {
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
