//! The tracked neighbour index behind DM's `adjacency(KIND, dirs =, ...)`
//! declaration (`doc/rewrite/final_api.html` section 6, "Lifecycle forms",
//! form 4).
//!
//! An adjacency member is a handle (DM's small integer for an atom) placed on
//! a cell `(x, y, z)` under a *kind* (walls, tables, cables, ...): members of
//! one kind see each other. The index answers "who of kind K is on the cells
//! around this one" and, on every change, *which members' neighbour sets
//! changed*: placing a member changes its own set and the set of every
//! neighbour that now sees it; removing one changes the sets of the
//! neighbours that saw it. DM recomputes exactly those members (their
//! `connects =` check and `into =` var), so a wall built in a corridor updates
//! the walls around it and nothing else.
//!
//! Directions are BYOND's: `NORTH = 1`, `SOUTH = 2`, `EAST = 4`, `WEST = 8`,
//! the diagonals their ORs, `UP = 16`, `DOWN = 32`. A member's `dirs` mask
//! says which faces it looks on: [`DIRS_CARDINAL`], plus [`DIR_DIAGONALS`]
//! for the four corners, plus the vertical bits. The result for one member
//! is a *junction mask*: the cardinal and vertical bits as BYOND writes them,
//! and the corners at [`JUNCTION_NE`] .. [`JUNCTION_SW`] (a BYOND corner is
//! two cardinal bits, so it cannot be a bit of its own).
//!
//! No globals: an [`AdjacencyIndex`] is owned by its caller (the FFI keeps one
//! per world, reset with it).

use std::collections::HashMap;

/// A member handle: DM's index for the atom.
pub type Handle = u32;

pub const NORTH: u8 = 1;
pub const SOUTH: u8 = 2;
pub const EAST: u8 = 4;
pub const WEST: u8 = 8;
pub const UP: u8 = 16;
pub const DOWN: u8 = 32;
/// The four cardinal faces.
pub const DIRS_CARDINAL: u32 = 0x0F;
/// `dirs` bit asking for the four corners as well.
pub const DIR_DIAGONALS: u32 = 0x40;

/// Junction bits of the four corners (the cardinal and vertical faces use
/// their BYOND bits).
pub const JUNCTION_NE: u32 = 1 << 6;
pub const JUNCTION_NW: u32 = 1 << 7;
pub const JUNCTION_SE: u32 = 1 << 8;
pub const JUNCTION_SW: u32 = 1 << 9;

/// One looked-at neighbour position: the offset and its junction bit.
#[derive(Clone, Copy, Debug)]
struct Step {
    dx: i32,
    dy: i32,
    dz: i32,
    bit: u32,
}

const CARDINAL_STEPS: [Step; 4] = [
    Step { dx: 0, dy: 1, dz: 0, bit: NORTH as u32 },
    Step { dx: 0, dy: -1, dz: 0, bit: SOUTH as u32 },
    Step { dx: 1, dy: 0, dz: 0, bit: EAST as u32 },
    Step { dx: -1, dy: 0, dz: 0, bit: WEST as u32 },
];
const DIAGONAL_STEPS: [Step; 4] = [
    Step { dx: 1, dy: 1, dz: 0, bit: JUNCTION_NE },
    Step { dx: -1, dy: 1, dz: 0, bit: JUNCTION_NW },
    Step { dx: 1, dy: -1, dz: 0, bit: JUNCTION_SE },
    Step { dx: -1, dy: -1, dz: 0, bit: JUNCTION_SW },
];
const VERTICAL_STEPS: [Step; 2] = [
    Step { dx: 0, dy: 0, dz: 1, bit: UP as u32 },
    Step { dx: 0, dy: 0, dz: -1, bit: DOWN as u32 },
];

/// The opposite junction bit (what a neighbour at `bit` sees this member as).
#[must_use]
pub const fn opposite(bit: u32) -> u32 {
    match bit {
        1 => 2,
        2 => 1,
        4 => 8,
        8 => 4,
        16 => 32,
        32 => 16,
        JUNCTION_NE => JUNCTION_SW,
        JUNCTION_SW => JUNCTION_NE,
        JUNCTION_NW => JUNCTION_SE,
        JUNCTION_SE => JUNCTION_NW,
        _ => 0,
    }
}

fn steps(dirs: u32) -> impl Iterator<Item = Step> {
    let cardinal = CARDINAL_STEPS.into_iter().filter(move |s| dirs & s.bit != 0);
    let diagonal = DIAGONAL_STEPS.into_iter().filter(move |_| dirs & DIR_DIAGONALS != 0);
    let vertical = VERTICAL_STEPS.into_iter().filter(move |s| dirs & s.bit != 0);
    cardinal.chain(diagonal).chain(vertical)
}

/// `(kind, x, y, z)`: one cell of one kind.
type CellKey = (u16, i32, i32, i32);

/// Where a member is: its kind, cell and the faces it looks on.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
struct Placed {
    kind: u16,
    x: i32,
    y: i32,
    z: i32,
    dirs: u32,
}

/// One neighbour seen from a member: the neighbour and the junction bit it is
/// on.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Seen {
    pub handle: Handle,
    pub bit: u32,
}

/// The index: per kind and cell, the members there.
#[derive(Default, Debug)]
pub struct AdjacencyIndex {
    cells: HashMap<CellKey, Vec<Handle>>,
    /// `(kind, handle)` -> where it is. A handle may be a member of several kinds.
    placed: HashMap<(u16, Handle), Placed>,
}

impl AdjacencyIndex {
    #[must_use]
    pub fn new() -> Self {
        Self::default()
    }

    /// Members placed (all kinds).
    #[must_use]
    pub fn len(&self) -> usize {
        self.placed.len()
    }

    #[must_use]
    pub fn is_empty(&self) -> bool {
        self.placed.is_empty()
    }

    /// Drops everything (a new round).
    pub fn clear(&mut self) {
        self.cells.clear();
        self.placed.clear();
    }

    /// The members of `kind` around `(x, y, z)` on the faces `dirs` asks for,
    /// excluding `except`.
    #[must_use]
    pub fn neighbours(&self, kind: u16, x: i32, y: i32, z: i32, dirs: u32, except: Option<Handle>) -> Vec<Seen> {
        let mut out = Vec::new();
        for s in steps(dirs) {
            if let Some(list) = self.cells.get(&(kind, x + s.dx, y + s.dy, z + s.dz)) {
                for &h in list {
                    if Some(h) != except {
                        out.push(Seen { handle: h, bit: s.bit });
                    }
                }
            }
        }
        out
    }

    /// Places `handle` (moving it if it was placed elsewhere). Returns every
    /// member whose neighbour set changed: the member itself first, then the
    /// neighbours at the old and the new place, each once.
    pub fn place(&mut self, kind: u16, handle: Handle, x: i32, y: i32, z: i32, dirs: u32) -> Vec<Handle> {
        let mut changed = vec![handle];
        if let Some(old) = self.placed.get(&(kind, handle)).copied() {
            if old.x == x && old.y == y && old.z == z && old.dirs == dirs {
                return Vec::new();
            }
            self.unlink(kind, handle, old, &mut changed);
        }
        let at = Placed { kind, x, y, z, dirs };
        self.cells.entry((kind, x, y, z)).or_default().push(handle);
        self.placed.insert((kind, handle), at);
        for seen in self.watchers(kind, at, handle) {
            if !changed.contains(&seen) {
                changed.push(seen);
            }
        }
        changed
    }

    /// Removes `handle` from `kind`. Returns the neighbours whose set changed
    /// (not the member itself).
    pub fn remove(&mut self, kind: u16, handle: Handle) -> Vec<Handle> {
        let mut changed = Vec::new();
        if let Some(old) = self.placed.get(&(kind, handle)).copied() {
            self.unlink(kind, handle, old, &mut changed);
        }
        changed
    }

    /// The junction mask of `handle` in `kind` now (its neighbours on its own
    /// faces), and who they are.
    #[must_use]
    pub fn junction(&self, kind: u16, handle: Handle) -> (u32, Vec<Seen>) {
        let Some(at) = self.placed.get(&(kind, handle)).copied() else {
            return (0, Vec::new());
        };
        let seen = self.neighbours(kind, at.x, at.y, at.z, at.dirs, Some(handle));
        let mask = seen.iter().fold(0, |m, s| m | s.bit);
        (mask, seen)
    }

    fn unlink(&mut self, kind: u16, handle: Handle, old: Placed, changed: &mut Vec<Handle>) {
        if let Some(list) = self.cells.get_mut(&(kind, old.x, old.y, old.z)) {
            list.retain(|&h| h != handle);
            if list.is_empty() {
                self.cells.remove(&(kind, old.x, old.y, old.z));
            }
        }
        self.placed.remove(&(kind, handle));
        for seen in self.watchers(kind, old, handle) {
            if !changed.contains(&seen) {
                changed.push(seen);
            }
        }
    }

    /// The members of `kind` whose faces include the cell of `at`: they see a
    /// member there. A member looks on its own `dirs`, so the reverse look is
    /// done over every face and filtered by the neighbour's mask.
    fn watchers(&self, kind: u16, at: Placed, except: Handle) -> Vec<Handle> {
        let all = DIRS_CARDINAL | DIR_DIAGONALS | u32::from(UP) | u32::from(DOWN);
        let mut out = Vec::new();
        for s in steps(all) {
            let Some(list) = self.cells.get(&(kind, at.x + s.dx, at.y + s.dy, at.z + s.dz)) else { continue };
            let back = opposite(s.bit);
            for &h in list {
                if h == except {
                    continue;
                }
                let Some(n) = self.placed.get(&(kind, h)) else { continue };
                let looks = if back >= JUNCTION_NE { n.dirs & DIR_DIAGONALS != 0 } else { n.dirs & back != 0 };
                if looks && !out.contains(&h) {
                    out.push(h);
                }
            }
        }
        out
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_row_of_three_connects_east_west() {
        let mut idx = AdjacencyIndex::new();
        assert_eq!(idx.place(1, 10, 5, 5, 1, DIRS_CARDINAL), vec![10]);
        assert_eq!(idx.place(1, 11, 6, 5, 1, DIRS_CARDINAL), vec![11, 10]);
        assert_eq!(idx.place(1, 12, 7, 5, 1, DIRS_CARDINAL), vec![12, 11]);
        assert_eq!(idx.junction(1, 11).0, u32::from(EAST | WEST));
        assert_eq!(idx.junction(1, 10).0, u32::from(EAST));
        assert_eq!(idx.junction(1, 12).0, u32::from(WEST));
    }

    #[test]
    fn removing_updates_only_the_neighbours() {
        let mut idx = AdjacencyIndex::new();
        idx.place(1, 1, 0, 0, 1, DIRS_CARDINAL);
        idx.place(1, 2, 1, 0, 1, DIRS_CARDINAL);
        idx.place(1, 3, 5, 5, 1, DIRS_CARDINAL);
        assert_eq!(idx.remove(1, 2), vec![1]);
        assert_eq!(idx.junction(1, 1).0, 0);
        assert!(idx.remove(1, 2).is_empty(), "a second remove changes nothing");
    }

    #[test]
    fn kinds_do_not_see_each_other() {
        let mut idx = AdjacencyIndex::new();
        idx.place(1, 1, 0, 0, 1, DIRS_CARDINAL);
        idx.place(2, 2, 1, 0, 1, DIRS_CARDINAL);
        assert_eq!(idx.junction(1, 1).0, 0);
        assert_eq!(idx.junction(2, 2).0, 0);
    }

    #[test]
    fn a_move_updates_old_and_new_neighbours() {
        let mut idx = AdjacencyIndex::new();
        idx.place(1, 1, 0, 0, 1, DIRS_CARDINAL);
        idx.place(1, 2, 1, 0, 1, DIRS_CARDINAL);
        idx.place(1, 3, 3, 0, 1, DIRS_CARDINAL);
        let changed = idx.place(1, 2, 2, 0, 1, DIRS_CARDINAL);
        assert_eq!(changed, vec![2, 1, 3]);
        assert_eq!(idx.junction(1, 1).0, 0);
        assert_eq!(idx.junction(1, 3).0, u32::from(WEST));
        assert!(idx.place(1, 2, 2, 0, 1, DIRS_CARDINAL).is_empty(), "placing where it is changes nothing");
    }

    #[test]
    fn diagonals_and_vertical_use_their_own_bits() {
        let mut idx = AdjacencyIndex::new();
        let all = DIRS_CARDINAL | DIR_DIAGONALS | u32::from(UP) | u32::from(DOWN);
        idx.place(1, 1, 0, 0, 1, all);
        idx.place(1, 2, 1, 1, 1, all);
        idx.place(1, 3, 0, 0, 2, all);
        let (mask, _) = idx.junction(1, 1);
        assert_eq!(mask, JUNCTION_NE | u32::from(UP));
        assert_eq!(idx.junction(1, 2).0, JUNCTION_SW);
        assert_eq!(idx.junction(1, 3).0, u32::from(DOWN));
    }

    #[test]
    fn a_member_that_does_not_look_on_a_face_is_not_told() {
        let mut idx = AdjacencyIndex::new();
        idx.place(1, 1, 0, 0, 1, u32::from(NORTH));
        assert_eq!(idx.place(1, 2, 1, 0, 1, DIRS_CARDINAL), vec![2], "1 looks only north");
        assert_eq!(idx.junction(1, 2).0, u32::from(WEST));
        assert_eq!(idx.junction(1, 1).0, 0);
    }
}
