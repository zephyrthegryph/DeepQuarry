//! A `u128` stored as two `u64` words: 8-byte alignment, so an enum that carries one is not padded to 16. Equality,
//! ordering, hashing, `Debug` and the serde form are exactly those of the `u128` it holds, so replacing a `u128` field
//! with it changes no persisted byte, no query id and no sort order.
#[derive(Clone, Copy, Default, PartialEq, Eq)]
pub struct PackedU128([u64; 2]);
impl PackedU128 {
    #[inline]
    pub const fn new(value: u128) -> Self {
        Self([(value >> 64) as u64, value as u64])
    }
    #[inline]
    pub const fn to_le_bytes(self) -> [u8; 16] {
        self.get().to_le_bytes()
    }
    #[inline]
    pub const fn get(self) -> u128 {
        ((self.0[0] as u128) << 64) | self.0[1] as u128
    }
}
impl From<u128> for PackedU128 {
    #[inline]
    fn from(value: u128) -> Self {
        Self::new(value)
    }
}
impl From<PackedU128> for u128 {
    #[inline]
    fn from(value: PackedU128) -> Self {
        value.get()
    }
}
impl PartialEq<u128> for PackedU128 {
    fn eq(&self, other: &u128) -> bool {
        self.get() == *other
    }
}
impl PartialOrd for PackedU128 {
    fn partial_cmp(&self, other: &Self) -> Option<std::cmp::Ordering> {
        Some(self.cmp(other))
    }
}
impl Ord for PackedU128 {
    fn cmp(&self, other: &Self) -> std::cmp::Ordering {
        self.get().cmp(&other.get())
    }
}
impl std::hash::Hash for PackedU128 {
    fn hash<H: std::hash::Hasher>(&self, state: &mut H) {
        self.get().hash(state)
    }
}
impl std::fmt::Debug for PackedU128 {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        std::fmt::Debug::fmt(&self.get(), f)
    }
}
impl std::fmt::Display for PackedU128 {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        std::fmt::Display::fmt(&self.get(), f)
    }
}
impl std::fmt::LowerHex for PackedU128 {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        std::fmt::LowerHex::fmt(&self.get(), f)
    }
}
impl serde::Serialize for PackedU128 {
    fn serialize<S: serde::Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        self.get().serialize(serializer)
    }
}
impl<'de> serde::Deserialize<'de> for PackedU128 {
    fn deserialize<D: serde::Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
        u128::deserialize(deserializer).map(Self::new)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn packed_value_behaves_as_the_u128_it_holds() {
        use std::hash::{Hash, Hasher};
        let values = [0u128, 1, u64::MAX as u128, (u64::MAX as u128) + 1, u128::MAX - 5, u128::MAX];
        for a in values {
            assert_eq!(PackedU128::new(a).get(), a);
            let hash = |value: &dyn Fn(&mut std::collections::hash_map::DefaultHasher)| {
                let mut hasher = std::collections::hash_map::DefaultHasher::new();
                value(&mut hasher);
                hasher.finish()
            };
            assert_eq!(hash(&|h| PackedU128::new(a).hash(h)), hash(&|h| a.hash(h)));
            assert_eq!(format!("{:?}", PackedU128::new(a)), format!("{a:?}"));
            for b in values {
                assert_eq!(PackedU128::new(a).cmp(&PackedU128::new(b)), a.cmp(&b));
            }
        }
        assert_eq!(std::mem::align_of::<PackedU128>(), 8);
        assert_eq!(std::mem::size_of::<PackedU128>(), 16);
    }
}

#[cfg(test)]
mod size_guard {
    /// The packed words are why these stay at 8-byte alignment; a `u128` field would raise them to 48 and 80.
    #[test]
    fn query_and_meaning_stay_packed() {
        assert!(std::mem::size_of::<crate::ResolveQuery>() <= 32);
        assert!(std::mem::size_of::<crate::ResolvedMeaning>() <= 48);
    }
}
