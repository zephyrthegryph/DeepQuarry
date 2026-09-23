//! [`Cables`]: the R7 network kind for power (`simulation.md` §3, §6).

use vg_core::network::NetworkKind;

/// Index of each [`Summary`] component.
pub mod sum {
    /// Registered generator supply (W).
    pub const SUPPLY: usize = 0;
    /// Demand by APC channel (W): equipment, lighting, environment.
    pub const EQUIP: usize = 1;
    pub const LIGHT: usize = 2;
    pub const ENVIRON: usize = 3;
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
