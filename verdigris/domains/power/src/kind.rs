//! [`Cables`]: the R7 network kind for power (`simulation.md` §3, §6).

use vg_core::network::NetworkKind;

/// An APC power channel. Replaces the magic `0`/`1`/`2` indices DM's
/// `POWERCHAN_*` used: everywhere a channel is threaded through Rust it is
/// this type, not a bare `usize`.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum Channel {
    Equip,
    Light,
    Environ,
}

impl Channel {
    /// Every channel, in the order DM's `EQUIP`/`LIGHT`/`ENVIRON` (minus
    /// one) expects for its `[f64; 3]`/`[u8; 3]` arrays.
    pub const ALL: [Channel; 3] = [Channel::Equip, Channel::Light, Channel::Environ];

    /// This channel's index into a per-channel `[T; 3]` array.
    #[must_use]
    pub const fn idx(self) -> usize {
        match self {
            Channel::Equip => 0,
            Channel::Light => 1,
            Channel::Environ => 2,
        }
    }
}

/// Index of each [`Summary`] component.
pub mod sum {
    use super::Channel;

    /// Registered generator supply (W).
    pub const SUPPLY: usize = 0;
    /// Demand by APC channel (W): equipment, lighting, environment. One
    /// past [`SUPPLY`], in [`Channel::idx`] order.
    #[must_use]
    pub const fn channel(c: Channel) -> usize {
        1 + c.idx()
    }
    pub const EQUIP: usize = channel(Channel::Equip);
    pub const LIGHT: usize = channel(Channel::Light);
    pub const ENVIRON: usize = channel(Channel::Environ);
    /// Storage capacity attached to the region (SMES and APC cell units).
    pub const CAPACITY: usize = 4;
}

/// A region's additive aggregate: supply, demand per channel and storage
/// capacity (see [`sum`]).
pub type Summary = [f64; 5];

/// What one node contributes: a cable contributes nothing; a machine node
/// carries its registered supply, the static channel demand it serves (an
/// APC terminal) and the storage it attaches (a SMES, an APC cell).
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct Load {
    pub supply: f64,
    pub demand: [f64; 3],
    pub capacity: f64,
}

impl Load {
    #[must_use]
    pub fn summary(&self) -> Summary {
        [
            self.supply,
            self.demand[0],
            self.demand[1],
            self.demand[2],
            self.capacity,
        ]
    }
}

/// Cables: node data is a [`Load`]; the region payload is pooled storage
/// energy, split by capacity share and pooled on merge (so it conserves
/// across any edit). Commands add (or with a negative value, take) pooled
/// energy.
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct Cables;

impl NetworkKind for Cables {
    const NAME: &'static str = "cables";
    type Node = Load;
    type Summary = Summary;
    type Payload = f64;
    type Device = ();
    type Command = f64;

    fn summarize(node: &Load) -> Summary {
        node.summary()
    }

    fn split(pool: &mut f64, whole: &Summary, part: &Summary) -> f64 {
        let cap = whole[sum::CAPACITY];
        let frac = if cap > 0.0 {
            (part[sum::CAPACITY] / cap).clamp(0.0, 1.0)
        } else {
            0.0
        };
        let out = *pool * frac;
        *pool -= out;
        out
    }

    fn merge(into: &mut f64, other: f64) {
        *into += other;
    }

    fn apply(pool: &mut f64, _: &Summary, cmd: &f64) {
        *pool = (*pool + cmd).max(0.0);
    }
}
