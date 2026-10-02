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
    let mut cache = cache().lock().unwrap_or_else(|e| e.into_inner());
    if cache.root.as_deref() == Some(root) {
        return;
    }
    let mut next = Cache {
        root: Some(root.to_owned()),
        store: dm_store::Store::open(root.join("declaration-fragments.redb")).ok(),
        ..Default::default()
    };
    let snapshot = next.store.as_ref().and_then(|store| {
        store
            .snapshot_namespace(&namespace(), 128_000, LIMIT / 2, None)
            .ok()
    });
    if let Some(snapshot) = snapshot {
        for (key, bytes) in snapshot.records {
            if let Ok(plan) = serde_json::from_slice::<DeclarationDefaultPlan>(&bytes) {
                let size = charge(&key.name, &plan);
                if next.bytes.saturating_add(size) <= LIMIT {
                    next.bytes += size;
                    next.entries.insert(key.name, Arc::new(plan));
                }
            }
        }
    }
    *cache = next;
}
pub(super) fn flush_cache() {
    let mut cache = cache().lock().unwrap_or_else(|e| e.into_inner());
    let Some(store) = &cache.store else {
        cache.pending.clear();
        return;
    };
    let changes: Vec<_> = cache
        .pending
        .iter()
        .map(|(key, bytes)| {
            dm_store::Change::Put(dm_store::Key::new(namespace(), key), bytes.clone())
        })
        .collect();
    if store.commit(&[], &changes, None).is_ok() {
        cache.pending.clear();
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
            cache.pending.insert(key.clone(), bytes);
        }
        if let Some(old) = cache.entries.remove(&key) {
            cache.bytes = cache.bytes.saturating_sub(charge(&key, &old));
        }
        cache.bytes += size;
        cache.entries.insert(key, Arc::clone(&plan));
    }
    let flush = cache.pending.values().map(Vec::len).sum::<usize>() > 1024 * 1024;
    drop(cache);
    if flush {
        flush_cache();
    }
    Ok(plan)
}
