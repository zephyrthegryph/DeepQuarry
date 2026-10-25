//! Process-wide sharing of the strings and macro definitions that memo records repeat.
//!
//! A decoded record owns fresh allocations for every macro name, macro definition and replacement chain it
//! names, so the same `TRUE` or `SECONDS` definition read by thousands of regions was held thousands of
//! times, once per record (hundreds of megabytes for the production tree). A freshly expanded record shares
//! the plan's `Arc`s; decoding through these pools gives a decoded record the same sharing. Only the
//! allocation identity changes: every value compares and encodes exactly as before, so the wire format and
//! every reuse decision are untouched.
//!
//! A pool holds strong references, so an entry stays only while a record or plan still shares it: a shard
//! drops its otherwise-unreferenced entries whenever it has doubled since its last sweep.
use crate::Macro;
use serde::{de, Deserialize, Deserializer};
use std::{
    borrow::Borrow,
    collections::{hash_map::RandomState, HashSet},
    hash::{BuildHasher, Hash},
    sync::{Arc, Mutex, OnceLock},
};

const SHARDS: usize = 64;
const SWEEP_FLOOR: usize = 1 << 12;

struct Shard<T: ?Sized + Eq + Hash> {
    entries: HashSet<Arc<T>>,
    sweep_at: usize,
}
struct Pool<T: ?Sized + Eq + Hash> {
    hasher: RandomState,
    shards: Vec<Mutex<Shard<T>>>,
}
impl<T: ?Sized + Eq + Hash> Pool<T> {
    fn new() -> Self {
        Self {
            hasher: RandomState::new(),
            shards: (0..SHARDS)
                .map(|_| {
                    Mutex::new(Shard {
                        entries: HashSet::new(),
                        sweep_at: SWEEP_FLOOR,
                    })
                })
                .collect(),
        }
    }
    fn share<Q>(&self, key: &Q, make: impl FnOnce() -> Arc<T>) -> Arc<T>
    where
        Arc<T>: Borrow<Q>,
        Q: ?Sized + Eq + Hash,
    {
        let shard = &self.shards[self.hasher.hash_one(key) as usize % SHARDS];
        let mut shard = shard.lock().unwrap_or_else(|error| error.into_inner());
        if let Some(found) = shard.entries.get(key) {
            return Arc::clone(found);
        }
        if shard.entries.len() >= shard.sweep_at {
            shard.entries.retain(|entry| Arc::strong_count(entry) > 1);
            shard.sweep_at = (shard.entries.len() * 2).max(SWEEP_FLOOR);
        }
        let made = make();
        shard.entries.insert(Arc::clone(&made));
        made
    }
}

fn names() -> &'static Pool<str> {
    static POOL: OnceLock<Pool<str>> = OnceLock::new();
    POOL.get_or_init(Pool::new)
}
fn definitions() -> &'static Pool<Macro> {
    static POOL: OnceLock<Pool<Macro>> = OnceLock::new();
    POOL.get_or_init(Pool::new)
}
fn chains() -> &'static Pool<[Arc<str>]> {
    static POOL: OnceLock<Pool<[Arc<str>]>> = OnceLock::new();
    POOL.get_or_init(Pool::new)
}

/// The shared allocation for this text.
pub(crate) fn name(text: &str) -> Arc<str> {
    names().share(text, || Arc::from(text))
}

struct NameVisitor;
impl de::Visitor<'_> for NameVisitor {
    type Value = Arc<str>;
    fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter.write_str("a string")
    }
    fn visit_str<E: de::Error>(self, text: &str) -> Result<Arc<str>, E> {
        Ok(name(text))
    }
    fn visit_string<E: de::Error>(self, text: String) -> Result<Arc<str>, E> {
        Ok(name(&text))
    }
}
/// `Arc<str>` field, shared across records (same wire form as the default).
pub(crate) fn shared_name<'de, D: Deserializer<'de>>(
    deserializer: D,
) -> Result<Arc<str>, D::Error> {
    deserializer.deserialize_str(NameVisitor)
}
struct Name(Arc<str>);
impl<'de> Deserialize<'de> for Name {
    fn deserialize<D: Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
        shared_name(deserializer).map(Self)
    }
}
/// `Arc<[Arc<str>]>` field whose chain and elements are both shared.
pub(crate) fn shared_chain<'de, D: Deserializer<'de>>(
    deserializer: D,
) -> Result<Arc<[Arc<str>]>, D::Error> {
    let names: Vec<Name> = Vec::deserialize(deserializer)?;
    let names: Vec<Arc<str>> = names.into_iter().map(|name| name.0).collect();
    Ok(chains().share(names.as_slice(), || Arc::from(names.as_slice())))
}
/// `Option<Arc<Macro>>` field, definitions shared by value.
pub(crate) fn shared_definition<'de, D: Deserializer<'de>>(
    deserializer: D,
) -> Result<Option<Arc<Macro>>, D::Error> {
    let definition: Option<Macro> = Option::deserialize(deserializer)?;
    Ok(definition
        .map(|definition| definitions().share(&definition, || Arc::new(definition.clone()))))
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde::Serialize;

    #[derive(Serialize, Deserialize, PartialEq, Debug)]
    struct Plain {
        name: Arc<str>,
        chain: Arc<[Arc<str>]>,
        definition: Option<Arc<Macro>>,
    }
    #[derive(Serialize, Deserialize)]
    struct Shared {
        #[serde(deserialize_with = "shared_name")]
        name: Arc<str>,
        #[serde(deserialize_with = "shared_chain")]
        chain: Arc<[Arc<str>]>,
        #[serde(deserialize_with = "shared_definition")]
        definition: Option<Arc<Macro>>,
    }
    fn plain(name: &str) -> Plain {
        Plain {
            name: Arc::from(name),
            chain: Arc::from([Arc::from("A"), Arc::from(name)]),
            definition: Some(Arc::new(Macro {
                parameters: Some(vec!["x".into()]),
                variadic: false,
                replacement: format!("({name} + x)"),
            })),
        }
    }
    fn decode_shared(value: &Plain) -> Shared {
        let bytes = dm_wire::encode(1, value).unwrap();
        dm_wire::decode(1, &bytes, bytes.len()).unwrap()
    }
    #[test]
    fn decoding_shares_equal_values_without_changing_the_wire_form() {
        let value = plain("intern_wire_probe");
        let bytes = dm_wire::encode(1, &value).unwrap();
        let first = decode_shared(&value);
        let second = decode_shared(&value);
        assert!(Arc::ptr_eq(&first.name, &second.name));
        assert!(Arc::ptr_eq(&first.chain, &second.chain));
        assert!(Arc::ptr_eq(&first.chain[1], &first.name));
        assert!(Arc::ptr_eq(
            first.definition.as_ref().unwrap(),
            second.definition.as_ref().unwrap()
        ));
        // Encoding the decoded value reproduces the original bytes, and the default decoder agrees on value.
        assert_eq!(dm_wire::encode(1, &first).unwrap(), bytes);
        let reference: Plain = dm_wire::decode(1, &bytes, bytes.len()).unwrap();
        assert_eq!(reference, value);
        assert_eq!(*first.name, *reference.name);
        assert_eq!(first.chain, reference.chain);
        assert_eq!(first.definition, reference.definition);
    }
    #[test]
    fn distinct_values_stay_distinct_and_unreferenced_entries_are_swept() {
        let a = decode_shared(&plain("sweep_a"));
        let b = decode_shared(&plain("sweep_b"));
        assert!(!Arc::ptr_eq(&a.name, &b.name));
        assert_ne!(a.definition, b.definition);
        drop((a, b));
        let total = SWEEP_FLOOR * SHARDS * 3;
        for index in 0..total {
            name(&format!("sweep_filler_{index}"));
        }
        let held: usize = names()
            .shards
            .iter()
            .map(|shard| shard.lock().unwrap().entries.len())
            .sum();
        assert!(held < total, "{held} entries survived");
    }
}
