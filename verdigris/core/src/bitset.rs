//! Dense bitsets for dirty and active flags (`rust_core.md` §5).

/// A fixed-length set of `u32` indices backed by 64-bit words.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct DenseBitSet {
    words: Vec<u64>,
    len: u32,
}

impl DenseBitSet {
    /// An empty set that can hold indices `0..len`.
    #[must_use]
    pub fn new(len: u32) -> Self {
        Self {
            words: vec![0; (len as usize).div_ceil(64)],
            len,
        }
    }

    /// Capacity in indices.
    #[must_use]
    pub const fn capacity(&self) -> u32 {
        self.len
    }

    /// Grows (never shrinks) to hold `0..len`.
    pub fn grow(&mut self, len: u32) {
        if len > self.len {
            self.words.resize((len as usize).div_ceil(64), 0);
            self.len = len;
        }
    }

    /// Sets `index`; returns whether it was newly set. Out-of-range indices
    /// return `false` and are ignored.
    pub fn insert(&mut self, index: u32) -> bool {
        if index >= self.len {
            return false;
        }
        let (word, bit) = split(index);
        let was = self.words[word] & bit != 0;
        self.words[word] |= bit;
        !was
    }

    /// Clears `index`; returns whether it was set.
    pub fn remove(&mut self, index: u32) -> bool {
        if index >= self.len {
            return false;
        }
        let (word, bit) = split(index);
        let was = self.words[word] & bit != 0;
        self.words[word] &= !bit;
        was
    }

    #[must_use]
    pub fn contains(&self, index: u32) -> bool {
        if index >= self.len {
            return false;
        }
        let (word, bit) = split(index);
        self.words[word] & bit != 0
    }

    pub fn clear(&mut self) {
        self.words.fill(0);
    }

    #[must_use]
    pub fn count(&self) -> u32 {
        self.words.iter().map(|w| w.count_ones()).sum()
    }

    #[must_use]
    pub fn is_empty(&self) -> bool {
        self.words.iter().all(|w| *w == 0)
    }

    /// `self |= other` over the shared prefix.
    pub fn union_with(&mut self, other: &Self) {
        for (a, b) in self.words.iter_mut().zip(&other.words) {
            *a |= *b;
        }
        self.mask_tail();
    }

    /// `self &= other`; indices beyond `other` are cleared.
    pub fn intersect_with(&mut self, other: &Self) {
        for (i, a) in self.words.iter_mut().enumerate() {
            *a &= other.words.get(i).copied().unwrap_or(0);
        }
    }

    fn mask_tail(&mut self) {
        let rem = self.len % 64;
        if rem != 0 {
            if let Some(last) = self.words.last_mut() {
                *last &= (1u64 << rem) - 1;
            }
        }
    }

    /// Set indices in ascending order.
    pub fn iter(&self) -> impl Iterator<Item = u32> + '_ {
        self.words.iter().enumerate().flat_map(|(w, &word)| {
            let base = u32::try_from(w * 64).expect("index fits u32");
            BitIter(word).map(move |bit| base + bit)
        })
    }

    /// Yields and clears every set index (a dirty-flag drain).
    pub fn drain(&mut self) -> impl Iterator<Item = u32> + '_ {
        self.words.iter_mut().enumerate().flat_map(|(w, word)| {
            let base = u32::try_from(w * 64).expect("index fits u32");
            BitIter(std::mem::take(word)).map(move |bit| base + bit)
        })
    }
}

const fn split(index: u32) -> (usize, u64) {
    ((index / 64) as usize, 1u64 << (index % 64))
}

struct BitIter(u64);

impl Iterator for BitIter {
    type Item = u32;
    fn next(&mut self) -> Option<u32> {
        if self.0 == 0 {
            return None;
        }
        let bit = self.0.trailing_zeros();
        self.0 &= self.0 - 1;
        Some(bit)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use proptest::prelude::*;
    use std::collections::BTreeSet;

    #[test]
    fn out_of_range_is_ignored() {
        let mut set = DenseBitSet::new(70);
        assert!(!set.insert(70));
        assert!(set.insert(69));
        assert!(!set.insert(69));
        assert!(set.contains(69));
        assert!(!set.contains(1000));
    }

    proptest! {
        #[test]
        fn matches_btreeset(len in 0u32..500, ops in prop::collection::vec((any::<bool>(), 0u32..600), 0..300)) {
            let mut set = DenseBitSet::new(len);
            let mut model = BTreeSet::new();
            for (insert, i) in ops {
                if insert {
                    prop_assert_eq!(set.insert(i), i < len && model.insert(i));
                } else {
                    prop_assert_eq!(set.remove(i), model.remove(&i));
                }
            }
            prop_assert_eq!(set.count() as usize, model.len());
            prop_assert_eq!(set.iter().collect::<Vec<_>>(), model.iter().copied().collect::<Vec<_>>());
            let drained: Vec<_> = set.drain().collect();
            prop_assert_eq!(drained, model.into_iter().collect::<Vec<_>>());
            prop_assert!(set.is_empty());
        }
    }
}
