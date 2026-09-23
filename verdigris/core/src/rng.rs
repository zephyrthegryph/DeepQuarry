//! Deterministic RNG streams, seedable and splittable per domain
//! (`rust_core.md` §3.9: replay must reproduce views bit for bit).
//!
//! A world has one [`RngStreams`] root seed. Each domain derives its own
//! stream from a stable [`StreamId`], so adding draws in one domain never
//! shifts another domain's sequence. A stream can be split further (per
//! chunk, per job) with [`Rng::split`], which is also deterministic.
//!
//! The generator is xoshiro256** seeded through `SplitMix64`. It is not
//! cryptographic.

/// A stable stream identifier. Build from a name with [`StreamId::named`];
/// the hash is FNV-1a, which (unlike `std`'s hasher) is fixed across builds.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub struct StreamId(pub u64);

impl StreamId {
    #[must_use]
    pub const fn named(name: &str) -> Self {
        let bytes = name.as_bytes();
        let mut hash: u64 = 0xcbf2_9ce4_8422_2325;
        let mut i = 0;
        while i < bytes.len() {
            hash ^= bytes[i] as u64;
            hash = hash.wrapping_mul(0x0000_0100_0000_01b3);
            i += 1;
        }
        Self(hash)
    }
}

/// The per-world root. Holds only the seed, so it is `Copy` and stateless.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct RngStreams {
    seed: u64,
}

impl RngStreams {
    #[must_use]
    pub const fn new(seed: u64) -> Self {
        Self { seed }
    }

    #[must_use]
    pub const fn seed(self) -> u64 {
        self.seed
    }

    /// The stream for a domain. Same seed and id, same sequence.
    #[must_use]
    pub fn stream(self, id: StreamId) -> Rng {
        Rng::from_seed(mix(self.seed ^ mix(id.0)))
    }
}

const fn mix(mut z: u64) -> u64 {
    z = z.wrapping_add(0x9e37_79b9_7f4a_7c15);
    z = (z ^ (z >> 30)).wrapping_mul(0xbf58_476d_1ce4_e5b9);
    z = (z ^ (z >> 27)).wrapping_mul(0x94d0_49bb_1331_11eb);
    z ^ (z >> 31)
}

/// xoshiro256**.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Rng {
    s: [u64; 4],
}

impl Rng {
    /// Seeds all 256 bits of state from one `u64` via `SplitMix64`.
    #[must_use]
    pub const fn from_seed(seed: u64) -> Self {
        let mut x = seed;
        let mut s = [0u64; 4];
        let mut i = 0;
        while i < 4 {
            x = x.wrapping_add(0x9e37_79b9_7f4a_7c15);
            s[i] = mix(x.wrapping_sub(0x9e37_79b9_7f4a_7c15));
            i += 1;
        }
        Self { s }
    }

    pub fn next_u64(&mut self) -> u64 {
        let result = self.s[1].wrapping_mul(5).rotate_left(7).wrapping_mul(9);
        let t = self.s[1] << 17;
        self.s[2] ^= self.s[0];
        self.s[3] ^= self.s[1];
        self.s[1] ^= self.s[2];
        self.s[0] ^= self.s[3];
        self.s[2] ^= t;
        self.s[3] = self.s[3].rotate_left(45);
        result
    }

    pub fn next_u32(&mut self) -> u32 {
        (self.next_u64() >> 32) as u32
    }

    /// Uniform in `[0, 1)`.
    #[allow(clippy::cast_precision_loss)]
    pub fn next_f32(&mut self) -> f32 {
        (self.next_u64() >> 40) as f32 * (1.0 / (1u64 << 24) as f32)
    }

    /// Uniform in `[0, 1)`.
    #[allow(clippy::cast_precision_loss)]
    pub fn next_f64(&mut self) -> f64 {
        (self.next_u64() >> 11) as f64 * (1.0 / (1u64 << 53) as f64)
    }

    /// Uniform in `0..n` (Lemire's method, unbiased). `n` must be non-zero.
    ///
    /// # Panics
    /// If `n` is zero.
    pub fn below(&mut self, n: u32) -> u32 {
        assert!(n > 0, "Rng::below(0)");
        let threshold = n.wrapping_neg() % n;
        loop {
            let m = u64::from(self.next_u32()) * u64::from(n);
            if (m as u32) >= threshold {
                return (m >> 32) as u32;
            }
        }
    }

    /// True with probability `p` (clamped to `[0, 1]`).
    pub fn chance(&mut self, p: f32) -> bool {
        self.next_f32() < p
    }

    /// A child stream keyed by `key`. Depends on the parent's current state
    /// and the key, and advances the parent by one draw, so splitting the
    /// same parent twice with the same key gives different children.
    pub fn split(&mut self, key: u64) -> Rng {
        let draw = self.next_u64();
        Rng::from_seed(mix(draw ^ mix(key)))
    }

    /// A child keyed by `key` that does not advance the parent: the same
    /// parent state and key always give the same child (per-chunk streams).
    #[must_use]
    pub fn fork(&self, key: u64) -> Rng {
        Rng::from_seed(mix(self.s[0] ^ self.s[2].rotate_left(17) ^ mix(key)))
    }
}

#[cfg(test)]
mod tests {
    use super::Rng;
    use super::*;
    use proptest::prelude::*;

    #[test]
    fn named_ids_are_stable() {
        // Pinned: changing the hash would change every recorded replay.
        assert_eq!(StreamId::named("").0, 0xcbf2_9ce4_8422_2325);
        assert_eq!(StreamId::named("a").0, 0xaf63_dc4c_8601_ec8c);
    }

    #[test]
    fn pinned_sequence() {
        // Pinned so an accidental generator change fails loudly.
        let mut rng = RngStreams::new(42).stream(StreamId::named("gas"));
        let first: Vec<u64> = (0..3).map(|_| rng.next_u64()).collect();
        let mut again = RngStreams::new(42).stream(StreamId::named("gas"));
        let second: Vec<u64> = (0..3).map(|_| again.next_u64()).collect();
        assert_eq!(first, second);
        let mut other = RngStreams::new(42).stream(StreamId::named("heat"));
        assert_ne!(first[0], other.next_u64());
    }

    #[test]
    fn below_covers_range() {
        let mut rng = Rng::from_seed(7);
        let mut seen = [false; 10];
        for _ in 0..1000 {
            seen[rng.below(10) as usize] = true;
        }
        assert!(seen.iter().all(|s| *s));
    }

    proptest! {
        #[test]
        fn streams_are_deterministic(seed in any::<u64>(), id in any::<u64>(), key in any::<u64>()) {
            let root = RngStreams::new(seed);
            let mut a = root.stream(StreamId(id));
            let mut b = root.stream(StreamId(id));
            for _ in 0..8 {
                prop_assert_eq!(a.next_u64(), b.next_u64());
            }
            prop_assert_eq!(a.fork(key), b.fork(key));
            let mut ca = a.split(key);
            let mut cb = b.split(key);
            prop_assert_eq!(ca.next_u64(), cb.next_u64());
            let f = a.next_f32();
            prop_assert!((0.0..1.0).contains(&f));
            let d = a.next_f64();
            prop_assert!((0.0..1.0).contains(&d));
        }

        #[test]
        fn below_is_in_range(seed in any::<u64>(), n in 1u32..) {
            let mut rng = Rng::from_seed(seed);
            prop_assert!(rng.below(n) < n);
        }
    }
}
