//! [`Cables`]: the R7 network kind for power (`rust_architecture.md` §6).
//! All region state lives in [`PowerLedger`], the payload -- there is no
//! side ledger map (`rust_architecture.md` §4.5's rule). A node's role is
//! topology only (`rust_architecture.md` step 3): a machine node (an APC's
//! own terminal, a producer, a SMES terminal) carries no power data of its
//! own any more -- that lives on components, reached through the entity a
//! node's row law is already iterating (`Apc`) or through
//! [`vg_core::query::Foreign`] (`Smes`, via its terminals).

use vg_core::grid::{CellId, Dir};
use vg_core::network::NetworkKind;

use crate::components::Cable;
use crate::geom;

/// What one node contributes to its region: a cable's shape, or nothing (a
/// machine node is topology only; its power data is a component).
#[derive(Clone, Debug, Default, PartialEq)]
pub enum PowerNode {
    Cable(Cable),
    #[default]
    Machine,
}

impl PowerNode {
    #[must_use]
    pub const fn as_cable(&self) -> Option<&Cable> {
        match self {
            Self::Cable(c) => Some(c),
            Self::Machine => None,
        }
    }
}

/// A region's live state: what [`crate::laws::PowerPlan`]/
/// [`crate::laws::PowerSettle`] compute and what the brownout event tracks,
/// plus the pro-rata totals [`crate::laws::SmesOutputApply`]/
/// [`crate::laws::SmesInputApply`] need and can only be summed once per
/// region (`rust_architecture.md` §8.5). The only region state there is
/// (`rust_architecture.md` §4.5) -- no side ledger, no display smoothing
/// (a DM read-time concern now, not simulated here).
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct PowerLedger {
    /// Registered supply plus storage offers, planned for this step, W.
    pub avail: f64,
    /// Delivered this step, W.
    pub load: f64,
    pub brown: bool,
    /// Sum of every member SMES output terminal's offer this step, W.
    pub smes_offer_total: f64,
    /// Sum of every member SMES input terminal's ask this step, W.
    pub smes_ask_total: f64,
    /// `load` beyond non-storage `avail`: what storage output actually had
    /// to cover this step, W.
    pub storage_used: f64,
    /// `avail - load`: this step's leftover supply, shared pro-rata among
    /// asking SMES input terminals, W.
    pub region_excess: f64,
}

impl PowerLedger {
    #[must_use]
    pub fn netexcess(&self) -> f64 {
        self.avail - self.load
    }
}

/// Cables: node data is a [`PowerNode`] (topology only), the region payload
/// is [`PowerLedger`].
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct Cables;

impl NetworkKind for Cables {
    const NAME: &'static str = "cables";
    type Node = PowerNode;
    type Summary = ();
    type Payload = PowerLedger;
    type Device = ();
    type Command = ();

    fn summarize(_node: &PowerNode) {}

    fn split(payload: &mut PowerLedger, (): &(), (): &()) -> PowerLedger {
        // avail/load are re-planned every step (they are not a stock), so
        // a split child starts fresh; brown carries over until the next
        // step's law recomputes it, so a mid-step split never flashes a
        // brief false "restored".
        PowerLedger {
            brown: payload.brown,
            ..PowerLedger::default()
        }
    }

    fn merge(into: &mut PowerLedger, other: PowerLedger) {
        into.load += other.load;
        into.brown = into.brown || other.brown;
    }

    /// Two nodes connect when a cable reaches the other's cell with a
    /// direction the other has (or, for same-cell cables, a shared end),
    /// or a machine sits on a knot cable at its own cell
    /// ([`crate::geom`]'s `get_connections()` port).
    fn connects((a, ca): (&PowerNode, CellId), (b, cb): (&PowerNode, CellId)) -> bool {
        match (a, b) {
            (PowerNode::Cable(a), PowerNode::Cable(b)) => {
                if ca == cb {
                    return a.shares_end(b);
                }
                a.reaches(ca).into_iter().any(|(t, need)| t == cb && b.has(need))
            }
            (PowerNode::Cable(c), PowerNode::Machine) | (PowerNode::Machine, PowerNode::Cable(c)) => {
                ca == cb && c.is_knot()
            }
            (PowerNode::Machine, PowerNode::Machine) => false,
        }
    }

    fn reach(node: &PowerNode, cell: CellId) -> Vec<CellId> {
        let PowerNode::Cable(cable) = node else {
            return vec![cell];
        };
        let mut cells = vec![cell];
        cells.extend(cable.reaches(cell).into_iter().map(|(t, _)| t));
        cells
    }

    fn link_group(node: &PowerNode) -> Option<u32> {
        match node {
            PowerNode::Cable(c) if c.link != 0 => Some(c.link),
            _ => None,
        }
    }
}

impl Cable {
    #[must_use]
    pub const fn is_knot(&self) -> bool {
        self.d1 == 0
    }

    #[must_use]
    pub const fn has(&self, dir: u8) -> bool {
        self.d1 == dir || self.d2 == dir
    }

    /// Two cables on the same turf connect when they share a direction
    /// value (two knots share 0).
    #[must_use]
    pub const fn shares_end(&self, other: &Self) -> bool {
        other.has(self.d1) || other.has(self.d2)
    }

    /// The turfs this cable reaches off `p`, each with the direction a
    /// cable there must have to connect back: `(turf, required dir)`.
    #[must_use]
    pub fn reaches(&self, p: CellId) -> Vec<(CellId, u8)> {
        let mut out = Vec::with_capacity(4);
        for dir in [self.d1, self.d2] {
            if dir == 0 {
                continue;
            }
            if let Some(t) = geom::step(p, dir, self.up, self.down) {
                out.push((t, Dir(dir).reverse().0));
            }
            if Dir(dir).is_diagonal() {
                for pair in [Dir::NORTH.union(Dir::SOUTH), Dir::EAST.union(Dir::WEST)] {
                    if let Some(t) = geom::step(p, dir & pair.0, 0, 0) {
                        out.push((t, dir ^ pair.0));
                    }
                }
            }
        }
        out
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::geom::pos;

    fn wire(d1: u8, d2: u8) -> Cable {
        Cable { d1, d2, up: 0, down: 0, link: 0 }
    }

    #[test]
    fn a_straight_run_connects_end_to_end() {
        let a = PowerNode::Cable(wire(0, Dir::EAST.0));
        let b = PowerNode::Cable(wire(Dir::EAST.0, Dir::WEST.0));
        let c = PowerNode::Cable(wire(Dir::WEST.0, 0));
        let (pa, pb, pc) = (pos(1, 1, 1), pos(2, 1, 1), pos(3, 1, 1));
        assert!(Cables::connects((&a, pa), (&b, pb)));
        assert!(Cables::connects((&b, pb), (&c, pc)));
        assert!(!Cables::connects((&a, pa), (&c, pc)), "not directly adjacent");
    }

    #[test]
    fn a_knot_and_a_machine_on_it_connect_but_not_off_it() {
        let knot = PowerNode::Cable(wire(0, 0));
        let machine = PowerNode::Machine;
        let p = pos(4, 4, 1);
        assert!(Cables::connects((&knot, p), (&machine, p)));
        assert!(!Cables::connects((&knot, p), (&machine, pos(5, 4, 1))));
    }

    #[test]
    fn two_machines_never_connect_directly() {
        let p = pos(1, 1, 1);
        assert!(!Cables::connects((&PowerNode::Machine, p), (&PowerNode::Machine, p)));
    }

    #[test]
    fn split_zeroes_the_flow_but_keeps_brown() {
        let mut payload = PowerLedger { avail: 500.0, load: 300.0, brown: true, ..PowerLedger::default() };
        let child = Cables::split(&mut payload, &(), &());
        assert_eq!(child, PowerLedger { avail: 0.0, load: 0.0, brown: true, ..PowerLedger::default() });
    }

    #[test]
    fn merge_adds_load_and_ors_brown() {
        let mut into = PowerLedger { avail: 100.0, load: 40.0, brown: false, ..PowerLedger::default() };
        let other = PowerLedger { avail: 50.0, load: 10.0, brown: true, ..PowerLedger::default() };
        Cables::merge(&mut into, other);
        assert_eq!(into.load, 50.0);
        assert!(into.brown);
    }
}
