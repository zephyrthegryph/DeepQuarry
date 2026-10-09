//! Request-local exact-byte string interning for staged output writers.
use super::*;

pub(crate) struct StringIndex {
    pub(super) buckets: HashMap<u128, u32>,
    collisions: HashMap<u128, Vec<u32>>,
}
impl StringIndex {
    pub(crate) fn build(dmb: &Dmb) -> Result<Self, CompositionError> {
        let mut result = Self {
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
    pub(crate) fn intern(&mut self, dmb: &mut Dmb, data: &[u8]) -> Result<u32, CompositionError> {
        self.intern_hashed(dmb, data, xxhash_rust::xxh3::xxh3_128(data))
    }
    fn find(&self, dmb: &Dmb, hash: u128, data: &[u8]) -> Option<u32> {
        let first = *self.buckets.get(&hash)?;
        if dmb.string(first) == Some(data) {
            return Some(first);
        }
        self.collisions
            .get(&hash)?
            .iter()
            .copied()
            .find(|&id| dmb.string(id) == Some(data))
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
