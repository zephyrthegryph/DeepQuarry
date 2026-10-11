//! Request-local exact-byte string interning for staged output writers.
use super::*;
use std::sync::Arc;

#[derive(Default)]
struct BaseIndex {
    buckets: HashMap<u128, u32>,
    collisions: HashMap<u128, Vec<u32>>,
}
#[derive(Clone)]
pub(super) struct StringSeed {
    len: usize,
    base: Arc<BaseIndex>,
}
impl StringSeed {
    pub(super) fn admit(&self, current: &Dmb, previous: &Dmb) -> Option<StringIndex> {
        if current.strings.len() != self.len
            || previous.strings.get(..self.len)? != current.strings.as_slice()
        {
            return None;
        }
        Some(StringIndex {
            base: Some(self.base.clone()),
            buckets: HashMap::new(),
            collisions: HashMap::new(),
        })
    }
    pub(crate) fn census(&self, census: &mut crate::heap_census::HeapCensus) {
        if census.arc_object("retained.generation.string_index", &self.base) {
            for rows in self.base.collisions.values() {
                census.vec_payload("retained.generation.string_collisions", rows);
            }
            census.unknown("retained.generation.string_index", "HashMap backing and Arc control bytes are private; no string payload copy is retained");
        }
    }
}
pub(crate) struct StringIndex {
    base: Option<Arc<BaseIndex>>,
    pub(super) buckets: HashMap<u128, u32>,
    collisions: HashMap<u128, Vec<u32>>,
}
impl StringIndex {
    pub(crate) fn build(dmb: &Dmb) -> Result<Self, CompositionError> {
        let mut result = Self {
            base: None,
            buckets: HashMap::with_capacity(dmb.strings.len()),
            collisions: HashMap::new(),
        };
        for (index, string) in dmb.strings.iter().enumerate() {
            let id = u32::try_from(index).map_err(|_| unsupported("string count overflow"))?;
            if dm_link::is_reserved_string_index(id) {
                continue;
            }
            let hash = xxhash_rust::xxh3::xxh3_128(&string.data);
            if result.find(dmb, hash, &string.data).is_none() {
                result.remember(hash, id);
            }
        }
        Ok(result)
    }
    pub(super) fn seed(&mut self, len: usize) -> StringSeed {
        let base = self
            .base
            .get_or_insert_with(|| {
                Arc::new(BaseIndex {
                    buckets: std::mem::take(&mut self.buckets),
                    collisions: std::mem::take(&mut self.collisions),
                })
            })
            .clone();
        StringSeed { len, base }
    }
    pub(super) fn lookup(&self, dmb: &Dmb, data: &[u8]) -> Option<u32> {
        self.find(dmb, xxhash_rust::xxh3::xxh3_128(data), data)
    }
    pub(crate) fn intern(&mut self, dmb: &mut Dmb, data: &[u8]) -> Result<u32, CompositionError> {
        self.intern_hashed(dmb, data, xxhash_rust::xxh3::xxh3_128(data))
    }
    fn find(&self, dmb: &Dmb, hash: u128, data: &[u8]) -> Option<u32> {
        fn in_map(
            dmb: &Dmb,
            buckets: &HashMap<u128, u32>,
            collisions: &HashMap<u128, Vec<u32>>,
            hash: u128,
            data: &[u8],
        ) -> Option<u32> {
            let first = *buckets.get(&hash)?;
            if dmb.string(first) == Some(data) {
                return Some(first);
            }
            collisions
                .get(&hash)?
                .iter()
                .copied()
                .find(|&id| dmb.string(id) == Some(data))
        }
        self.base
            .as_ref()
            .and_then(|base| in_map(dmb, &base.buckets, &base.collisions, hash, data))
            .or_else(|| in_map(dmb, &self.buckets, &self.collisions, hash, data))
    }

    fn remember(&mut self, hash: u128, id: u32) {
        match self.buckets.entry(hash) {
            std::collections::hash_map::Entry::Vacant(entry) => {
                entry.insert(id);
            }
            std::collections::hash_map::Entry::Occupied(_) => {
                self.collisions.entry(hash).or_default().push(id);
            }
        }
    }
    fn intern_hashed(
        &mut self,
        dmb: &mut Dmb,
        data: &[u8],
        hash: u128,
    ) -> Result<u32, CompositionError> {
        if let Some(id) = self.find(dmb, hash, data) {
            return Ok(id);
        }
        while dm_link::is_reserved_string_index(
            u32::try_from(dmb.strings.len()).map_err(|_| unsupported("string count overflow"))?,
        ) {
            dmb.strings.push(DmString {
                data: Vec::new(),
                long_chunks: 0,
            });
        }
        let id =
            u32::try_from(dmb.strings.len()).map_err(|_| unsupported("string count overflow"))?;
        let chunks =
            u16::try_from(data.len() / 65535).map_err(|_| unsupported("string too large"))?;
        dmb.strings.push(DmString {
            data: data.to_vec(),
            long_chunks: chunks,
        });
        self.remember(hash, id);
        Ok(id)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn issued_prefix_reuses_base_and_declines_changed_order_or_chunks() {
        let mut original =
            Dmb::from_bytes(include_bytes!("../../../../fixtures/native_template.bin")).unwrap();
        original.strings.push(DmString {
            data: vec![b'x'; 65535],
            long_chunks: 1,
        });
        let mut index = StringIndex::build(&original).unwrap();
        let seed = index.seed(original.strings.len());
        let mut previous = original.clone();
        index
            .intern(&mut previous, b"late generation string")
            .unwrap();
        let mut current = original.clone();
        let mut reused = seed.admit(&current, &previous).unwrap();
        assert!(Arc::ptr_eq(reused.base.as_ref().unwrap(), &seed.base));
        let mut fresh = StringIndex::build(&current).unwrap();
        let mut fresh_model = current.clone();
        for text in [
            b"late generation string".as_slice(),
            b"new metadata",
            b"new metadata",
        ] {
            assert_eq!(
                reused.intern(&mut current, text).unwrap(),
                fresh.intern(&mut fresh_model, text).unwrap()
            );
        }
        let hash = 91234;
        for text in [
            b"first collision".as_slice(),
            b"second collision",
            b"first collision",
        ] {
            assert_eq!(
                reused.intern_hashed(&mut current, text, hash).unwrap(),
                fresh.intern_hashed(&mut fresh_model, text, hash).unwrap()
            );
        }
        assert_eq!(
            current.encode().unwrap().bytes(),
            fresh_model.encode().unwrap().bytes()
        );
        let mut changed = original.clone();
        changed.strings.last_mut().unwrap().long_chunks = 2;
        assert!(seed.admit(&changed, &previous).is_none());
        changed = original.clone();
        changed.strings.swap(0, 1);
        assert!(seed.admit(&changed, &previous).is_none());
        changed = original;
        changed.strings.push(DmString {
            data: b"new initial binding".to_vec(),
            long_chunks: 0,
        });
        assert!(seed.admit(&changed, &previous).is_none());
    }
    #[test]
    fn forced_collision_retains_exact_bytes_and_first_index() {
        let mut dmb =
            Dmb::from_bytes(include_bytes!("../../../../fixtures/native_template.bin")).unwrap();
        let mut pool = StringIndex::build(&dmb).unwrap();
        let hash = 123;
        let first = pool
            .intern_hashed(&mut dmb, b"collision first", hash)
            .unwrap();
        let second = pool
            .intern_hashed(&mut dmb, b"collision second", hash)
            .unwrap();
        assert_ne!(first, second);
        assert_eq!(
            pool.intern_hashed(&mut dmb, b"collision first", hash)
                .unwrap(),
            first
        );
        assert_eq!(
            pool.intern_hashed(&mut dmb, b"collision second", hash)
                .unwrap(),
            second
        );
        assert_eq!(pool.collisions[&hash], [second]);
    }
    #[test]
    fn duplicate_bytes_build_keeps_first_without_overflow_allocation() {
        let mut dmb =
            Dmb::from_bytes(include_bytes!("../../../../fixtures/native_template.bin")).unwrap();
        let first = dmb.strings.len() as u32;
        for _ in 0..2 {
            dmb.strings.push(DmString {
                data: b"duplicate build probe".to_vec(),
                long_chunks: 0,
            });
        }
        let mut pool = StringIndex::build(&dmb).unwrap();
        assert_eq!(
            pool.intern(&mut dmb, b"duplicate build probe").unwrap(),
            first
        );
        assert!(!pool
            .collisions
            .contains_key(&xxhash_rust::xxh3::xxh3_128(b"duplicate build probe")));
    }
}
