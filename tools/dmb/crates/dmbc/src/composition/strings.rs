//! Request-local exact-byte string interning for staged output writers.
use super::*;

pub(crate) struct StringIndex {
    pub(super) buckets: HashMap<u128, Vec<u32>>,
}
impl StringIndex {
    pub(crate) fn build(dmb: &Dmb) -> Result<Self, CompositionError> {
        let mut result = Self {
            buckets: HashMap::new(),
        };
        for (index, string) in dmb.strings.iter().enumerate() {
            let id = u32::try_from(index).map_err(|_| unsupported("string count overflow"))?;
            if dm_link::is_reserved_string_index(id) {
                continue;
            }
            result
                .buckets
                .entry(xxhash_rust::xxh3::xxh3_128(&string.data))
                .or_default()
                .push(id);
        }
        Ok(result)
    }
    pub(crate) fn intern(&mut self, dmb: &mut Dmb, data: &[u8]) -> Result<u32, CompositionError> {
        let hash = xxhash_rust::xxh3::xxh3_128(data);
        if let Some(ids) = self.buckets.get(&hash) {
            for &id in ids {
                if dmb.string(id) == Some(data) {
                    return Ok(id);
                }
            }
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
        self.buckets.entry(hash).or_default().push(id);
        Ok(id)
    }
}
