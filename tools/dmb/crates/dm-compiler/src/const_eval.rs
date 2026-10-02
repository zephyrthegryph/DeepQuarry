//! Pure evaluation of declaration expressions. Runtime operations remain unfurled.
use dm_syntax::{parse_expression, Expr, ExprKind};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::{
    cell::RefCell,
    collections::BTreeMap,
    sync::{Arc, Mutex, OnceLock},
};

const CONSTANT_CACHE_BYTES: usize = 16 * 1024 * 1024;
struct ConstantMemo {
    parsed: Option<Arc<Expr>>,
    result: Option<Constant>,
    observations: BTreeMap<String, Option<Constant>>,
    charge: usize,
}
#[derive(Default)]
struct ConstantCache {
    values: BTreeMap<String, (u64, Arc<ConstantMemo>)>,
    clock: u64,
    bytes: usize,
    store: Option<dm_store::Store>,
    root: Option<std::path::PathBuf>,
    pending: BTreeMap<String, Vec<u8>>,
    pending_bytes: usize,
}
#[derive(Serialize, Deserialize)]
struct ConstantRecord {
    source: String,
    result: Option<Constant>,
    observations: BTreeMap<String, Option<Constant>>,
}
fn constant_namespace() -> String {
    format!("constant-query-v1-{}", env!("DM_EMISSION_FINGERPRINT"))
}
pub(super) fn bind_cache(root: &std::path::Path) {
    let mut cache = constant_cache().lock().unwrap_or_else(|e| e.into_inner());
    if cache.root.as_deref() == Some(root) {
        return;
    }
    flush_locked(&mut cache);
    cache.root = Some(root.to_owned());
    cache.store = dm_store::Store::open(root.join("constant-queries.redb")).ok();
    let snapshot = cache.store.as_ref().and_then(|store| {
        store
            .snapshot_namespace(
                &constant_namespace(),
                128_000,
                CONSTANT_CACHE_BYTES / 2,
                None,
            )
            .ok()
    });
    if let Some(snapshot) = snapshot {
        for (_, bytes) in snapshot.records {
            let Ok(record) = serde_json::from_slice::<ConstantRecord>(&bytes) else {
                continue;
            };
            let charge = 192
                + record.source.capacity()
                + constant_bytes(&record.result)
                + record
                    .observations
                    .iter()
                    .map(|(name, value)| 96 + name.capacity() + constant_bytes(value))
                    .sum::<usize>();
            if cache.bytes.saturating_add(charge) > CONSTANT_CACHE_BYTES {
                break;
            }
            if cache.values.contains_key(&record.source) {
                continue;
            }
            let memo = ConstantMemo {
                parsed: None,
                result: record.result,
                observations: record.observations,
                charge,
            };
            cache.bytes += charge;
            let clock = cache.clock;
            cache.values.insert(record.source, (clock, Arc::new(memo)));
        }
    }
}
fn flush_locked(cache: &mut ConstantCache) {
    if let Some(store) = &cache.store {
        let namespace = constant_namespace();
        let changes: Vec<_> = cache
            .pending
            .iter()
            .map(|(key, bytes)| {
                dm_store::Change::Put(dm_store::Key::new(&namespace, key), bytes.clone())
            })
            .collect();
        let _ = store.commit(&[], &changes, None);
    }
    cache.pending.clear();
    cache.pending_bytes = 0;
}
pub(super) fn flush_cache() {
    flush_locked(&mut constant_cache().lock().unwrap_or_else(|e| e.into_inner()));
}
fn constant_cache() -> &'static Mutex<ConstantCache> {
    static CACHE: OnceLock<Mutex<ConstantCache>> = OnceLock::new();
    CACHE.get_or_init(|| Mutex::new(ConstantCache::default()))
}
fn constant_bytes(value: &Option<Constant>) -> usize {
    std::mem::size_of::<Option<Constant>>()
        + match value {
            Some(Constant::Text(text) | Constant::TypePath(text)) => text.capacity(),
            Some(Constant::EncodedText(bytes)) => bytes.capacity(),
            _ => 0,
        }
}
fn expression_bytes(expr: &Expr) -> usize {
    use ExprKind::*;
    std::mem::size_of::<Expr>()
        + match &expr.kind {
            Ident(s) | Literal(s) | TypePath(s) => s.capacity(),
            Unary { op, value } => op.capacity() + expression_bytes(value),
            Binary { op, lhs, rhs } => {
                op.capacity() + expression_bytes(lhs) + expression_bytes(rhs)
            }
            Conditional {
                condition,
                then_value,
                else_value,
            } => {
                expression_bytes(condition)
                    + expression_bytes(then_value)
                    + expression_bytes(else_value)
            }
            Call { callee, args } => {
                expression_bytes(callee)
                    + args.capacity() * std::mem::size_of::<Expr>()
                    + args.iter().map(expression_bytes).sum::<usize>()
            }
            Member {
                object, selector, ..
            }
            | StaticMember { object, selector }
            | SafeMember { object, selector } => expression_bytes(object) + selector.capacity(),
            TypeFilter { value, types } => {
                expression_bytes(value)
                    + types.capacity() * std::mem::size_of::<String>()
                    + types.iter().map(String::capacity).sum::<usize>()
            }
            ObjectInitializer { object, fields } => {
                expression_bytes(object)
                    + fields.capacity() * std::mem::size_of::<(String, Expr)>()
                    + fields
                        .iter()
                        .map(|(name, value)| name.capacity() + expression_bytes(value))
                        .sum::<usize>()
            }
            Index { object, index } | SafeIndex { object, index } => {
                expression_bytes(object) + expression_bytes(index)
            }
            Group(value) => expression_bytes(value),
        }
}

/// Shared syntax query for constant and symbolic declaration-default plans.
/// Its result has no resolver observations or physical output IDs.
pub(super) fn parsed_expression(source: &str) -> Option<Arc<Expr>> {
    type SyntaxEntries = (BTreeMap<String, (Option<Arc<Expr>>, usize)>, usize);
    static SYNTAX: OnceLock<Mutex<SyntaxEntries>> = OnceLock::new();
    let cache = SYNTAX.get_or_init(|| Mutex::new((BTreeMap::new(), 0)));
    if let Some((parsed, _)) = cache
        .lock()
        .unwrap_or_else(|e| e.into_inner())
        .0
        .get(source)
    {
        return parsed.clone();
    }
    let parsed = parse_expression(source);
    let parsed = parsed
        .diagnostics
        .is_empty()
        .then_some(parsed.expr)
        .flatten()
        .map(Arc::new);
    let charge = 128usize
        .saturating_add(source.len())
        .saturating_add(parsed.as_ref().map_or(0, |expr| expression_bytes(expr)));
    const LIMIT: usize = 8 * 1024 * 1024;
    if charge <= LIMIT {
        let mut cache = cache.lock().unwrap_or_else(|e| e.into_inner());
        if !cache.0.contains_key(source) {
            while cache.1.saturating_add(charge) > LIMIT {
                let Some(key) = cache.0.keys().next().cloned() else {
                    break;
                };
                if let Some((_, bytes)) = cache.0.remove(&key) {
                    cache.1 -= bytes;
                }
            }
            cache.0.insert(source.to_owned(), (parsed.clone(), charge));
            cache.1 += charge;
        }
    }
    parsed
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub(super) enum Constant {
    Null,
    Number(f32),
    Text(String),
    EncodedText(Vec<u8>),
    TypePath(String),
}
impl PartialEq for Constant {
    fn eq(&self, other: &Self) -> bool {
        match (self, other) {
            (Self::Null, Self::Null) => true,
            (Self::Number(a), Self::Number(b)) => a.to_bits() == b.to_bits(),
            (Self::Text(a), Self::Text(b)) | (Self::TypePath(a), Self::TypePath(b)) => a == b,
            (Self::EncodedText(a), Self::EncodedText(b)) => a == b,
            _ => false,
        }
    }
}
impl Constant {
    fn truth(&self) -> bool {
        match self {
            Self::Null => false,
            Self::Number(n) => *n != 0.0,
            Self::Text(s) => !s.is_empty(),
            Self::EncodedText(s) => !s.is_empty(),
            Self::TypePath(_) => true,
        }
    }
    fn number(&self) -> Option<f32> {
        match self {
            Self::Number(n) => Some(*n),
            _ => None,
        }
    }
}

pub(super) fn evaluate(
    source: &str,
    resolve: impl Fn(&str) -> Option<Constant>,
) -> Option<Constant> {
    // Queries are independent of output table allocation. Resolve precisely the
    // positive and negative names previously read, rather than invalidating all
    // declaration expressions when an unrelated declaration changes.
    let previous = {
        let mut cache = constant_cache().lock().unwrap_or_else(|e| e.into_inner());
        cache.clock = cache.clock.wrapping_add(1);
        let clock = cache.clock;
        cache.values.get_mut(source).map(|(used, memo)| {
            *used = clock;
            Arc::clone(memo)
        })
    };
    if let Some(memo) = &previous {
        if memo
            .observations
            .iter()
            .all(|(name, value)| resolve(name) == *value)
        {
            return memo.result.clone();
        }
    }
    let parsed = match &previous {
        Some(memo) if memo.parsed.is_some() => memo.parsed.clone(),
        _ => parsed_expression(source),
    };
    let observations = RefCell::new(BTreeMap::new());
    let result = parsed.as_ref().and_then(|expr| {
        eval(expr, &|name| {
            let value = resolve(name);
            observations
                .borrow_mut()
                .insert(name.to_owned(), value.clone());
            value
        })
    });
    let observations = observations.into_inner();
    let charge = 192usize
        .saturating_add(source.len())
        .saturating_add(parsed.as_ref().map_or(0, |expr| expression_bytes(expr)))
        .saturating_add(constant_bytes(&result))
        .saturating_add(
            observations
                .iter()
                .map(|(name, value)| 96 + name.capacity() + constant_bytes(value))
                .sum::<usize>(),
        );
    if charge <= CONSTANT_CACHE_BYTES {
        let encoded = serde_json::to_vec(&ConstantRecord {
            source: source.to_owned(),
            result: result.clone(),
            observations: observations.clone(),
        })
        .ok()
        .filter(|bytes| {
            // JSON cannot represent NaNs/infinities. An unroundtrippable record
            // is a persistence miss, never an alternative numeric encoding.
            serde_json::from_slice::<ConstantRecord>(bytes).is_ok()
        });
        let memo = Arc::new(ConstantMemo {
            parsed,
            result: result.clone(),
            observations,
            charge,
        });
        let mut cache = constant_cache().lock().unwrap_or_else(|e| e.into_inner());
        if let Some((_, old)) = cache.values.remove(source) {
            cache.bytes -= old.charge;
        }
        while cache.bytes.saturating_add(charge) > CONSTANT_CACHE_BYTES {
            let oldest = cache
                .values
                .iter()
                .min_by_key(|(_, (used, _))| *used)
                .map(|(source, _)| source.clone());
            let Some(oldest) = oldest else {
                break;
            };
            if let Some((_, old)) = cache.values.remove(&oldest) {
                cache.bytes -= old.charge;
            }
        }
        let clock = cache.clock;
        cache.values.insert(source.to_owned(), (clock, memo));
        cache.bytes += charge;
        if cache.store.is_some() {
            if let Some(bytes) = encoded.filter(|bytes| bytes.len() <= 1024 * 1024) {
                if cache.pending_bytes.saturating_add(bytes.len()) > 4 * 1024 * 1024 {
                    flush_locked(&mut cache);
                }
                let key = format!("{:x}", Sha256::digest(source.as_bytes()));
                if let Some(old) = cache.pending.insert(key, bytes.clone()) {
                    cache.pending_bytes -= old.len();
                }
                cache.pending_bytes += bytes.len();
            }
        }
    }
    result
}
fn eval(expr: &Expr, resolve: &impl Fn(&str) -> Option<Constant>) -> Option<Constant> {
    use Constant::*;
    let boolean = |value| Number(if value { 1.0 } else { 0.0 });
    let result = match &expr.kind {
        ExprKind::Ident(name) if name == "null" => Null,
        ExprKind::Ident(name) => resolve(name)?,
        ExprKind::TypePath(path) => TypePath(path.clone()),
        ExprKind::StaticMember { object, selector } => {
            let TypePath(path) = eval(object, resolve)? else {
                return None;
            };
            resolve(&format!("{path}::{selector}"))?
        }
        ExprKind::Call { callee, args } if matches!(&callee.kind, ExprKind::Ident(name) if name == "nameof") =>
        {
            let [argument] = args.as_slice() else {
                return None;
            };
            Text(dm_codegen_byond::nameof_reference(argument)?.to_owned())
        }
        ExprKind::Literal(raw) if raw == "null" => Null,
        ExprKind::Literal(raw) if raw == "1.#INF" => Number(f32::INFINITY),
        ExprKind::Literal(raw) => {
            if (raw.starts_with('"') && raw.ends_with('"'))
                || (raw.starts_with("{\"") && raw.ends_with("\"}"))
                || raw.starts_with('@')
            {
                let bytes = dm_codegen_byond::decode_constant_string_literal(raw).ok()??;
                match String::from_utf8(bytes) {
                    Ok(text) => Text(text),
                    Err(error) => EncodedText(error.into_bytes()),
                }
            } else {
                let n = if let Some(hex) = raw.strip_prefix("0x").or_else(|| raw.strip_prefix("0X"))
                {
                    u32::from_str_radix(hex, 16).ok()? as f32
                } else {
                    raw.parse::<f32>().ok()?
                };
                Number(n)
            }
        }
        ExprKind::Group(inner) => eval(inner, resolve)?,
        ExprKind::Unary { op, value } => {
            let value = eval(value, resolve)?;
            match op.as_str() {
                "!" => boolean(!value.truth()),
                "+" => Number(value.number()?),
                "-" => Number(-value.number()?),
                "~" => Number((!(value.number()? as i32) & 0xffffff) as f32),
                _ => return None,
            }
        }
        ExprKind::Binary { op, lhs, rhs } => {
            let left = eval(lhs, resolve)?;
            if op == "&&" {
                return if left.truth() {
                    eval(rhs, resolve)
                } else {
                    Some(left)
                };
            }
            if op == "||" {
                return if left.truth() {
                    Some(left)
                } else {
                    eval(rhs, resolve)
                };
            }
            let right = eval(rhs, resolve)?;
            if op == "+" {
                if let (Text(a), Text(b)) = (&left, &right) {
                    return Some(Text(format!("{a}{b}")));
                }
                let bytes = |value: &Constant| match value {
                    Text(text) => Some(text.as_bytes().to_vec()),
                    EncodedText(text) => Some(text.clone()),
                    _ => None,
                };
                if let (Some(mut a), Some(b)) = (bytes(&left), bytes(&right)) {
                    a.extend(b);
                    return Some(EncodedText(a));
                }
            }
            if op == "==" || op == "!=" {
                if std::mem::discriminant(&left) != std::mem::discriminant(&right) {
                    return None;
                }
                return Some(boolean(if op == "==" {
                    left == right
                } else {
                    left != right
                }));
            }
            let a = left.number()?;
            let b = right.number()?;
            match op.as_str() {
                "+" => Number(a + b),
                "-" => Number(a - b),
                "*" => Number(a * b),
                "/" if b != 0.0 => Number(a / b),
                "%" if b != 0.0 => Number((a as i32).checked_rem(b as i32)? as f32),
                "**" => Number(a.powf(b)),
                "<" => boolean(a < b),
                "<=" => boolean(a <= b),
                ">" => boolean(a > b),
                ">=" => boolean(a >= b),
                "&" => Number(((a as i32 & b as i32) & 0xffffff) as f32),
                "|" => Number(((a as i32 | b as i32) & 0xffffff) as f32),
                "^" => Number(((a as i32 ^ b as i32) & 0xffffff) as f32),
                "<<" => {
                    if !a.is_finite() || !b.is_finite() || a >= 2147483648.0 || b >= 4294967296.0 {
                        return None;
                    }
                    Number(
                        ((a.max(0.0) as u32).wrapping_shl((b.max(0.0) as u32) & 31) & 0xffffff)
                            as f32,
                    )
                }
                ">>" => Number(((a as i32 & 0xffffff) >> ((b.max(0.0) as u32) & 31)) as f32),
                _ => return None,
            }
        }
        ExprKind::Conditional {
            condition,
            then_value,
            else_value,
        } => eval(
            if eval(condition, resolve)?.truth() {
                then_value
            } else {
                else_value
            },
            resolve,
        )?,
        _ => return None,
    };
    if matches!(result, Number(n) if n.is_nan()) {
        None
    } else {
        Some(result)
    }
}
