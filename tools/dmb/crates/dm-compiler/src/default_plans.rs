//! Authored declaration/default fragments independent of allocation history.
//! Resolution of names uses the constant observation query; paths/resources and
//! dynamic list constructors remain symbolic until current-generation encoding.
use super::*;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::sync::{Mutex, OnceLock};

const LIMIT: usize = 8 * 1024 * 1024;
#[derive(Clone, Serialize, Deserialize)]
pub(super) enum DefaultShape {
    Missing,
    Null,
    Number(u32),
    Text(String),
    Resource(String),
    Path(String),
    Runtime(String),
}
/// Literal list layout preserves source order and associative keys. Each
/// value remains a symbolic expression whose observed semantic dependencies
/// are recorded by constant/lowering queries when resolved in its owner scope.
#[derive(Clone, Serialize, Deserialize)]
pub(super) enum ListEntryPlan {
    Value(String),
    Association { key: String, value: String },
}
#[derive(Clone, Serialize, Deserialize)]
pub(super) struct DeclarationDefaultPlan {
    pub name: String,
    pub parts: Vec<String>,
    pub initial: Option<String>,
    pub is_tmp: bool,
    pub is_const: bool,
    pub is_static: bool,
    pub dynamic: Result<String, String>,
    pub shape: DefaultShape,
    #[serde(default)]
    pub list_entries: Option<Vec<ListEntryPlan>>,
}
#[derive(Default)]
struct Cache {
    entries: BTreeMap<String, Arc<DeclarationDefaultPlan>>,
    bytes: usize,
    store: Option<dm_store::Store>,
    root: Option<std::path::PathBuf>,
    pending: BTreeMap<String, Vec<u8>>,
    pending_bytes: usize,
    disk_ready: bool,
    missing: HashSet<String>,
}
fn cache() -> &'static Mutex<Cache> {
    static CACHE: OnceLock<Mutex<Cache>> = OnceLock::new();
    CACHE.get_or_init(|| Mutex::new(Cache::default()))
}
fn namespace() -> String {
    format!("default-plans-v1-{}", env!("DM_EMISSION_FINGERPRINT"))
}
fn charge(key: &str, plan: &DeclarationDefaultPlan) -> usize {
    key.len()
        + 192
        + plan.name.capacity()
        + plan.parts.capacity() * std::mem::size_of::<String>()
        + plan.parts.iter().map(String::capacity).sum::<usize>()
        + plan.initial.as_ref().map_or(0, String::capacity)
        + match &plan.dynamic {
            Ok(s) | Err(s) => s.capacity(),
        }
        + plan.list_entries.as_ref().map_or(0, |entries| {
            entries.capacity() * std::mem::size_of::<ListEntryPlan>()
                + entries
                    .iter()
                    .map(|entry| match entry {
                        ListEntryPlan::Value(value) => value.capacity(),
                        ListEntryPlan::Association { key, value } => {
                            key.capacity() + value.capacity()
                        }
                    })
                    .sum::<usize>()
        })
        + match &plan.shape {
            DefaultShape::Text(s)
            | DefaultShape::Resource(s)
            | DefaultShape::Path(s)
            | DefaultShape::Runtime(s) => s.capacity(),
            _ => 0,
        }
}
pub(super) fn bind_cache(root: &std::path::Path) {
    bind_owner_cache(root);
    let mut cache = cache().lock().unwrap_or_else(|e| e.into_inner());
    if cache.root.as_deref() == Some(root) {
        return;
    }
    let mut next = Cache {
        root: Some(root.to_owned()),
        store: dm_store::Store::open(root.join("declaration-fragments.redb")).ok(),
        ..Default::default()
    };
    next.disk_ready=next.store.as_ref().and_then(|store|store.read_many(&[dm_store::Key::new("declaration-fragment-ready",namespace())],None).ok())
        .is_some_and(|read|read.values.first().is_some_and(Option::is_some));
    *cache = next;
}
pub(super) fn flush_cache() {
    flush_owner_cache();
    let mut cache = cache().lock().unwrap_or_else(|e| e.into_inner());
    let Some(store) = &cache.store else {
        cache.pending.clear();cache.pending_bytes=0;
        return;
    };
    let mut changes: Vec<_> = cache
        .pending
        .iter()
        .map(|(key, bytes)| {
            dm_store::Change::Put(dm_store::Key::new(namespace(), key), bytes.clone())
        })
        .collect();
    changes.push(dm_store::Change::Put(dm_store::Key::new("declaration-fragment-ready",namespace()),vec![1]));
    if store.commit(&[], &changes, None).is_ok() {
        cache.pending.clear();cache.pending_bytes=0;
    }
}
/// Warm pure authored fragments using the workspace's one bounded scheduler.
/// Wire allocation and dependent constant resolution retain deterministic order.
pub(super) fn prefetch(items: &[Item], workers: usize) {
    fn collect<'a>(items: &'a [Item], output: &mut BTreeSet<&'a str>) {
        for item in items {
            if item.kind == ItemKind::Var {
                output.insert(item.header.trim());
            }
            collect(&item.children, output);
        }
    }
    let mut unique = BTreeSet::new();
    collect(items, &mut unique);
    let inputs: Vec<_> = unique
        .into_iter()
        .filter(|source| source.len().saturating_mul(8) + 512 <= 8 * 1024 * 1024)
        .collect();
    hydrate_defaults(&inputs);
    let limits = dm_work::WorkLimits {
        workers: workers.clamp(1, 4),
        max_active_bytes: 8 * 1024 * 1024,
    };
    let _ = dm_work::map_ordered(
        &inputs,
        limits,
        |source| source.len().saturating_mul(8) + 512,
        |source| {
            // Invalid authored syntax is diagnosed by the ordered allocation pass.
            // Prefetch owns neither diagnostics nor external semantic bindings.
            let _ = declaration(source);
        },
    );
}
pub(super) fn declaration(source: &str) -> Result<Arc<DeclarationDefaultPlan>, String> {
    let key = format!("{:x}", Sha256::digest(source.as_bytes()));
    if let Some(value) = cache()
        .lock()
        .unwrap_or_else(|e| e.into_inner())
        .entries
        .get(&key)
        .cloned()
    {
        return Ok(value);
    }
    if let Some(plan)=restore_default(&key) {return Ok(plan);}
    let raw = source
        .strip_prefix("/var/")
        .or_else(|| source.strip_prefix("var/"))
        .ok_or_else(|| format!("unsupported variable declaration: {source}"))?;
    let (raw_name, initial) = raw
        .split_once('=')
        .map_or((raw.trim(), None), |(name, value)| {
            (name.trim(), Some(value.trim().to_owned()))
        });
    let mut parts: Vec<String> = raw_name.split('/').map(str::to_owned).collect();
    let name = parts.pop().unwrap_or_default();
    if name.is_empty() {
        return Err(format!("unsupported variable declaration: {source}"));
    }
    let borrowed: Vec<_> = parts.iter().map(String::as_str).collect();
    let dynamic = initial.as_deref().map_or_else(
        || Ok(String::new()),
        |value| normalize_dynamic_expression(value, &borrowed, source),
    );
    let shape = match initial.as_deref() {
        None => DefaultShape::Missing,
        Some("null") => DefaultShape::Null,
        Some(value) if value.parse::<f32>().is_ok() => {
            DefaultShape::Number(value.parse::<f32>().unwrap().to_bits())
        }
        Some(value) if value.starts_with('"') && value.ends_with('"') && value.len() >= 2 => {
            DefaultShape::Text(value[1..value.len() - 1].to_owned())
        }
        Some(value) if value.starts_with('\'') && value.ends_with('\'') && value.len() >= 2 => {
            DefaultShape::Resource(value[1..value.len() - 1].replace('\\', "/"))
        }
        Some(value) if value.starts_with('/') => DefaultShape::Path(value.to_owned()),
        Some(value) => DefaultShape::Runtime(value.to_owned()),
    };
    let list_entries = initial.as_deref().and_then(|source| {
        let parsed = const_eval::parsed_expression(source)?;
        let dm_syntax::ExprKind::Call { callee, args } = &parsed.kind else {
            return None;
        };
        if !matches!(&callee.kind,dm_syntax::ExprKind::Ident(name) if name=="list") {
            return None;
        }
        let text = |expr: &dm_syntax::Expr| {
            source
                .get(expr.span.start..expr.span.end)
                .unwrap_or(source)
                .to_owned()
        };
        Some(
            args.iter()
                .map(|arg| {
                    if let dm_syntax::ExprKind::Binary { op, lhs, rhs } = &arg.kind {
                        if op == "=" {
                            return ListEntryPlan::Association {
                                key: text(lhs),
                                value: text(rhs),
                            };
                        }
                    }
                    ListEntryPlan::Value(text(arg))
                })
                .collect(),
        )
    });
    let plan = Arc::new(DeclarationDefaultPlan {
        name,
        is_tmp: parts.iter().any(|p| p == "tmp"),
        is_const: parts.iter().any(|p| p == "const"),
        is_static: parts.iter().any(|p| p == "static" || p == "global"),
        parts,
        initial,
        dynamic,
        shape,
        list_entries,
    });
    let size = charge(&key, &plan);
    let mut cache = cache().lock().unwrap_or_else(|e| e.into_inner());
    if size <= LIMIT {
        while cache.bytes.saturating_add(size) > LIMIT {
            let Some(old) = cache.entries.keys().next().cloned() else {
                break;
            };
            if let Some(value) = cache.entries.remove(&old) {
                cache.bytes = cache.bytes.saturating_sub(charge(&old, &value));
            }
        }
        if let Ok(bytes) = serde_json::to_vec(plan.as_ref()) {
            cache.pending_bytes+=bytes.len();
            if let Some(old)=cache.pending.insert(key.clone(), bytes) {cache.pending_bytes=cache.pending_bytes.saturating_sub(old.len());}
        }
        if let Some(old) = cache.entries.remove(&key) {
            cache.bytes = cache.bytes.saturating_sub(charge(&key, &old));
        }
        cache.bytes += size;
        cache.entries.insert(key, Arc::clone(&plan));
    }
    let flush = cache.pending_bytes > 1024 * 1024;
    drop(cache);
    if flush {
        flush_cache();
    }
    Ok(plan)
}

/// Owner-local declaration derivation, independent of output allocation. Child
/// indexes preserve author order without retaining procedure bodies or offsets.
/// Parent identity is symbolic; inherited constant observations are recorded by
/// the existing constant query when the allocator resolves each initializer.
#[derive(Clone, Serialize, Deserialize)]
pub(super) struct OwnerFieldExpression {
    pub name: String,
    pub expression: Option<String>,
    pub constant: bool,
    pub override_only: bool,
}
#[derive(Clone, Serialize, Deserialize)]
pub(super) struct OwnerDeclarationPlan {
    pub identity: String,
    pub semantic_identity: String,
    pub expressions: Vec<OwnerFieldExpression>,
    pub explicit_parent: Option<String>,
    pub const_indexes: Vec<usize>,
    pub mutable_names: HashSet<String>,
    pub field_types: HashMap<String, String>,
}
#[derive(Default)]
struct OwnerCache {
    entries: BTreeMap<String, Arc<OwnerDeclarationPlan>>,
    bytes: usize,
    root: Option<std::path::PathBuf>,
    store: Option<dm_store::Store>,
    pending: BTreeMap<String, Vec<u8>>,
    pending_bytes:usize,
    disk_ready:bool,
    missing:HashSet<String>,
}
fn owner_cache() -> &'static Mutex<OwnerCache> {
    static CACHE: OnceLock<Mutex<OwnerCache>> = OnceLock::new();
    CACHE.get_or_init(|| Mutex::new(OwnerCache::default()))
}
fn owner_namespace() -> String {
    format!("owner-declarations-v2-{}", env!("DM_EMISSION_FINGERPRINT"))
}
fn owner_key(item:&Item)->String {
    let mut hash = Sha256::new();
    hash.update(item.header.as_bytes());
    // Index is part of the fragment: edits which move declarations must update
    // the allocation projection, even if their symbolic meaning is unchanged.
    for (index, child) in item.children.iter().enumerate() {
        if matches!(child.kind, ItemKind::Var | ItemKind::Unknown | ItemKind::Statement) {
            hash.update((index as u64).to_le_bytes());
            hash.update([child.kind as u8]);
            hash.update((child.header.len() as u64).to_le_bytes());
            hash.update(child.header.as_bytes());
        }
    }
    format!("{:x}", hash.finalize())

}
pub(super) fn owner(item: &Item) -> Arc<OwnerDeclarationPlan> {
    let key=owner_key(item);
    if let Some(plan) = owner_cache().lock().unwrap_or_else(|e|e.into_inner()).entries.get(&key).cloned() { return plan; }
    if let Some(plan)=restore_owner(&key) {return plan;}
    let mut plan = OwnerDeclarationPlan { identity:key.clone(), semantic_identity:String::new(), expressions:Vec::new(), explicit_parent: None, const_indexes: Vec::new(), mutable_names: HashSet::new(), field_types: HashMap::new() };
    for (index, child) in item.children.iter().enumerate() {
        if plan.explicit_parent.is_none() {
            plan.explicit_parent = child.header.trim().strip_prefix("parent_type")
                .and_then(|tail|tail.trim().strip_prefix('=').map(|value|value.trim().to_owned()));
        }
        if child.kind != ItemKind::Var {
            if matches!(child.kind, ItemKind::Statement | ItemKind::Unknown) {
                if let Some((name, value)) = child.header.split_once('=') {
                    if name.trim() != "parent_type" {
                        plan.expressions.push(OwnerFieldExpression { name:name.trim().to_owned(), expression:Some(value.trim().to_owned()), constant:false, override_only:true });
                    }
                }
            }
            continue;
        }
        if let Ok(declaration) = declaration(child.header.trim()) {
            let name = declaration.name.split('[').next().unwrap_or(&declaration.name).to_owned();
            let expression = if declaration.name.contains('[') { "list()".to_owned() }
                else { declaration.initial.clone().unwrap_or_else(||"null".to_owned()) };
            plan.expressions.push(OwnerFieldExpression {name, expression:Some(expression), constant:declaration.is_const, override_only:false});
        }
        if let Some((name, ty)) = declared_variable_type(&child.header) { plan.field_types.insert(name, ty); }
        let is_const = child.header.split('=').next().is_some_and(|header|header.split('/').any(|part|part.trim()=="const"));
        if is_const { plan.const_indexes.push(index); }
        else if let Some(name) = child.header.split('=').next().and_then(|header|header.trim().rsplit('/').next()) { plan.mutable_names.insert(name.to_owned()); }
    }
    let mut semantic=Sha256::new();
    semantic.update(serde_json::to_vec(&(&plan.explicit_parent,&plan.expressions)).unwrap_or_default());
    plan.semantic_identity=format!("{:x}",semantic.finalize());
    let plan = Arc::new(plan);
    if let Ok(bytes) = serde_json::to_vec(plan.as_ref()) {
        let charge = bytes.len().saturating_mul(3) + key.len() + 128;
        let mut cache = owner_cache().lock().unwrap_or_else(|e|e.into_inner());
        if charge <= 16*1024*1024 {
            while cache.bytes.saturating_add(charge) > 16*1024*1024 {
                let Some(old) = cache.entries.keys().next().cloned() else {break};
                if let Some(value) = cache.entries.remove(&old) {
                    cache.bytes = cache.bytes.saturating_sub(serde_json::to_vec(value.as_ref()).map_or(0,|b|b.len()*3)+old.len()+128);
                }
            }
            if cache.entries.insert(key.clone(), Arc::clone(&plan)).is_none() {cache.bytes+=charge;}
            cache.pending_bytes+=bytes.len();
            if let Some(old)=cache.pending.insert(key, bytes) {cache.pending_bytes=cache.pending_bytes.saturating_sub(old.len());}
        }
        let flush = cache.pending_bytes > 1024 * 1024;
        drop(cache);
        if flush { flush_owner_cache(); }
    }
    plan
}
pub(super) fn bind_owner_cache(root: &std::path::Path) {
    let mut cache = owner_cache().lock().unwrap_or_else(|e|e.into_inner());
    if cache.root.as_deref()==Some(root) {return;}
    let mut next = OwnerCache { root:Some(root.to_owned()), store:dm_store::Store::open(root.join("declaration-fragments.redb")).ok(), ..Default::default() };
    next.disk_ready=next.store.as_ref().and_then(|store|store.read_many(&[dm_store::Key::new("declaration-fragment-ready",owner_namespace())],None).ok())
        .is_some_and(|read|read.values.first().is_some_and(Option::is_some));
    *cache=next;
}
pub(super) fn flush_owner_cache() {
    let mut cache=owner_cache().lock().unwrap_or_else(|e|e.into_inner());
    let Some(store)=cache.store.as_ref() else {cache.pending.clear();cache.pending_bytes=0;return};
    let mut changes:Vec<_>=cache.pending.iter().map(|(key,bytes)|dm_store::Change::Put(dm_store::Key::new(owner_namespace(),key),bytes.clone())).collect();
    changes.push(dm_store::Change::Put(dm_store::Key::new("declaration-fragment-ready",owner_namespace()),vec![1]));
    if store.commit(&[],&changes,None).is_ok() {cache.pending.clear();cache.pending_bytes=0;}
}
/// Consume the ordered results directly instead of warming a bounded cache and
/// looking up/rebuilding all owners again after that cache has evicted them.
pub(super) fn owner_batch(items: &[&Item], workers:usize) -> Vec<Arc<OwnerDeclarationPlan>> {
    let limits=dm_work::WorkLimits {workers:workers.clamp(1,4),max_active_bytes:8*1024*1024};
    let mut output=Vec::with_capacity(items.len());
    for chunk in items.chunks(4096) {
        hydrate_owners(chunk);
        let plans=dm_work::map_ordered(chunk,limits,|item|item.header.len()+item.children.iter().map(|child|child.header.len()+128).sum::<usize>(),|item|owner(item))
            .unwrap_or_else(|_|chunk.iter().map(|item|owner(item)).collect());
        output.extend(plans);
    }
    output
}

/// Amortize database ownership over many small records while keeping the same
/// strict byte bound. Large records split the requested window, never omit rows.
pub(super) fn read_stage_batch(store:&dm_store::Store,keys:&[dm_store::Key],max_record:usize,max_bytes:usize,visit:&mut impl FnMut(&dm_store::Key,Option<Vec<u8>>)) {
    if keys.is_empty() {return;}
    match store.read_grouped_bounded(keys,128,max_record,max_bytes,max_bytes.saturating_mul(8).min(64*1024*1024),None) {
        Ok(read)=>for (key,bytes) in keys.iter().zip(read.values) {visit(key,bytes);},
        Err(error) if error.kind()==std::io::ErrorKind::InvalidInput && keys.len()>1=>{
            let middle=keys.len()/2;
            read_stage_batch(store,&keys[..middle],max_record,max_bytes,visit);
            read_stage_batch(store,&keys[middle..],max_record,max_bytes,visit);
        }
        _=>{}
    }
}

/// Semantic defaults contain no generation-local IDs. Constant query witnesses
/// cover inherited/global names (including failed lookups); resource identity
/// is encoded by the current generation only after semantic planning finishes.
#[derive(Clone, Serialize, Deserialize)]
pub(super) enum SymbolicDefaultValue {
    Constant(const_eval::Constant),
    Resource(String),
}
pub(super) fn resolve_value(
    initial: Option<&str>,
    declaration: &str,
    dmb: &Dmb,
    strings: &StringIndex,
    owner: Option<u32>,
    blocked: &HashSet<String>,
) -> Result<SymbolicDefaultValue, String> {
    // Literal recipes carry no semantic dependencies and never enter the
    // scoped resolver or Salsa. Their physical payload is allocated later.
    match initial {
        None|Some("null")=>return Ok(SymbolicDefaultValue::Constant(const_eval::Constant::Null)),
        Some(source) if source.parse::<f32>().is_ok()=>return Ok(SymbolicDefaultValue::Constant(const_eval::Constant::Number(source.parse().unwrap()))),
        Some(source) if source.starts_with('\'')&&source.ends_with('\'')&&source.len()>=2=>return Ok(SymbolicDefaultValue::Resource(source[1..source.len()-1].replace('\\',"/"))),
        _=>{}
    }
    if let Some(value) = initial.and_then(|source|fold_constant_scoped(source,dmb,owner,blocked,strings)) {
        return Ok(SymbolicDefaultValue::Constant(value));
    }
    let shape = if declaration.starts_with("var/") || declaration.starts_with("/var/") {
        declaration_plan_shape(initial, declaration)
    } else { None };
    if let Some(value)=shape {
        return Ok(value);
    }
    match initial {
        None | Some("null") => Ok(SymbolicDefaultValue::Constant(const_eval::Constant::Null)),
        Some(number) if number.parse::<f32>().is_ok() => Ok(SymbolicDefaultValue::Constant(const_eval::Constant::Number(number.parse().unwrap()))),
        Some(text) if text.starts_with('"') && text.ends_with('"') && text.len()>=2 => Ok(SymbolicDefaultValue::Constant(const_eval::Constant::Text(text[1..text.len()-1].to_owned()))),
        Some(text) if text.starts_with('\'') && text.ends_with('\'') && text.len()>=2 => Ok(SymbolicDefaultValue::Resource(text[1..text.len()-1].replace('\\',"/"))),
        _ => Err(format!("unsupported initial value: {declaration}")),
    }
}
fn declaration_plan_shape(initial: Option<&str>, source: &str) -> Option<SymbolicDefaultValue> {
    let plan=declaration(source).ok()?;
    if plan.initial.as_deref()!=initial {return None;}
    Some(match &plan.shape {
        DefaultShape::Missing | DefaultShape::Null => SymbolicDefaultValue::Constant(const_eval::Constant::Null),
        DefaultShape::Number(bits) => SymbolicDefaultValue::Constant(const_eval::Constant::Number(f32::from_bits(*bits))),
        DefaultShape::Text(text) => SymbolicDefaultValue::Constant(const_eval::Constant::Text(text.clone())),
        DefaultShape::Resource(name) => SymbolicDefaultValue::Resource(name.clone()),
        DefaultShape::Path(_) | DefaultShape::Runtime(_) => return None,
    })
}

fn hydrate_defaults(sources:&[&str]) {
    let mut cache=cache().lock().unwrap_or_else(|error|error.into_inner());
    let Some(store)=cache.store.clone() else {return;};
    let keys:Vec<_>=sources.iter().map(|source|format!("{:x}",Sha256::digest(source.as_bytes()))).filter(|key|!cache.entries.contains_key(key)&&!cache.missing.contains(key)).map(|key|dm_store::Key::new(namespace(),key)).collect();
    for keys in keys.chunks(4096) {
        read_stage_batch(&store,keys,1024*1024,8*1024*1024,&mut |key,bytes| {
            if let Some(plan)=bytes.as_deref().and_then(|bytes|serde_json::from_slice::<DeclarationDefaultPlan>(bytes).ok()) {
                retain_default(&mut cache,key.name.clone(),Arc::new(plan));
            } else if cache.missing.len()<128_000 {cache.missing.insert(key.name.clone());}
        });
    }
}
fn retain_default(cache:&mut Cache,key:String,plan:Arc<DeclarationDefaultPlan>) {
    let size=charge(&key,&plan);if size>LIMIT {return;}
    if let Some(old)=cache.entries.remove(&key) {cache.bytes=cache.bytes.saturating_sub(charge(&key,&old));}
    while cache.bytes.saturating_add(size)>LIMIT {
        let Some(key)=cache.entries.keys().next().cloned() else {break;};
        if let Some(old)=cache.entries.remove(&key) {cache.bytes=cache.bytes.saturating_sub(charge(&key,&old));}
    }
    cache.bytes+=size;cache.entries.insert(key,plan);
}
fn restore_default(key:&str)->Option<Arc<DeclarationDefaultPlan>> {
    let mut cache=cache().lock().unwrap_or_else(|error|error.into_inner());
    if !cache.disk_ready || cache.missing.contains(key) {return None;}
    let read=cache.store.as_ref()?.read_many_bounded(&[dm_store::Key::new(namespace(),key)],1024*1024,1024*1024,None).ok()?;
    let plan=Arc::new(serde_json::from_slice::<DeclarationDefaultPlan>(read.values.first()?.as_deref()?).ok()?);
    retain_default(&mut cache,key.to_owned(),Arc::clone(&plan));Some(plan)
}
fn retain_owner(cache:&mut OwnerCache,key:String,plan:Arc<OwnerDeclarationPlan>,wire_size:usize) {
    let size=wire_size*3+key.len()+128;if size>16*1024*1024 {return;}
    if let Some(old)=cache.entries.remove(&key) {cache.bytes=cache.bytes.saturating_sub(serde_json::to_vec(old.as_ref()).map_or(0,|bytes|bytes.len()*3)+key.len()+128);}
    while cache.bytes.saturating_add(size)>16*1024*1024 {
        let Some(key)=cache.entries.keys().next().cloned() else {break;};
        if let Some(old)=cache.entries.remove(&key) {cache.bytes=cache.bytes.saturating_sub(serde_json::to_vec(old.as_ref()).map_or(0,|bytes|bytes.len()*3)+key.len()+128);}
    }
    cache.bytes+=size;cache.entries.insert(key,plan);
}
fn hydrate_owners(items:&[&Item]) {
    let mut cache=owner_cache().lock().unwrap_or_else(|error|error.into_inner());
    let Some(store)=cache.store.clone() else {return;};
    let keys:Vec<_>=items.iter().map(|item|owner_key(item)).collect::<BTreeSet<_>>().into_iter().filter(|key|!cache.entries.contains_key(key)&&!cache.missing.contains(key)).map(|key|dm_store::Key::new(owner_namespace(),key)).collect();
    for keys in keys.chunks(4096) {
        read_stage_batch(&store,keys,1024*1024,8*1024*1024,&mut |key,bytes| {
            if let Some(bytes)=bytes {
                if let Ok(plan)=serde_json::from_slice::<OwnerDeclarationPlan>(&bytes) {retain_owner(&mut cache,key.name.clone(),Arc::new(plan),bytes.len());}
            } else if cache.missing.len()<128_000 {cache.missing.insert(key.name.clone());}
        });
    }
}
fn restore_owner(key:&str)->Option<Arc<OwnerDeclarationPlan>> {
    let mut cache=owner_cache().lock().unwrap_or_else(|error|error.into_inner());
    if !cache.disk_ready || cache.missing.contains(key) {return None;}
    let read=cache.store.as_ref()?.read_many_bounded(&[dm_store::Key::new(owner_namespace(),key)],1024*1024,1024*1024,None).ok()?;
    let bytes=read.values.first()?.as_deref()?;
    let plan=Arc::new(serde_json::from_slice::<OwnerDeclarationPlan>(bytes).ok()?);
    retain_owner(&mut cache,key.to_owned(),Arc::clone(&plan),bytes.len());Some(plan)
}
