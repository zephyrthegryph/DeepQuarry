//! Cable geometry: positions, BYOND directions and the connection rule of
//! DM's `/obj/structure/cable/proc/get_connections()`, so Rust derives the
//! graph from what DM already knows about each cable (turf, `d1`, `d2`).

/// BYOND direction bits.
pub const NORTH: u8 = 1;
pub const SOUTH: u8 = 2;
pub const EAST: u8 = 4;
pub const WEST: u8 = 8;
pub const UP: u8 = 16;
pub const DOWN: u8 = 32;

const XY_BITS: u32 = 10;
const XY_MASK: u32 = (1 << XY_BITS) - 1;
/// Largest z the position encoding holds.
pub const MAX_Z: u32 = (1 << (32 - 2 * XY_BITS)) - 1;

/// A turf, packed `z << 20 | y << 10 | x` (x, y below 1024).
#[must_use]
pub const fn pos(x: u32, y: u32, z: u32) -> u32 {
    (z << (2 * XY_BITS)) | ((y & XY_MASK) << XY_BITS) | (x & XY_MASK)
}

#[must_use]
pub const fn unpack(p: u32) -> (u32, u32, u32) {
    (p & XY_MASK, (p >> XY_BITS) & XY_MASK, p >> (2 * XY_BITS))
}

/// `GLOB.reverse_dir`.
#[must_use]
pub const fn reverse(dir: u8) -> u8 {
    let mut r = 0;
    if dir & NORTH != 0 {
        r |= SOUTH;
    }
    if dir & SOUTH != 0 {
        r |= NORTH;
    }
    if dir & EAST != 0 {
        r |= WEST;
    }
    if dir & WEST != 0 {
        r |= EAST;
    }
    if dir & UP != 0 {
        r |= DOWN;
    }
    if dir & DOWN != 0 {
        r |= UP;
    }
    r
}

/// A planar diagonal (two of N/S/E/W set).
#[must_use]
pub const fn is_diagonal(dir: u8) -> bool {
    let planar = dir & 15;
    planar != 0 && planar & (planar - 1) != 0
}

/// `get_zstep(p, dir)`. `up`/`down` are the z-levels above and below `p`'s
/// z (0 when there is none), as DM's `GetAbove`/`GetBelow` report them.
#[must_use]
pub fn step(p: u32, dir: u8, up: u32, down: u32) -> Option<u32> {
    let (x, y, z) = unpack(p);
    let (mut x, mut y, mut z) = (i64::from(x), i64::from(y), i64::from(z));
    if dir & NORTH != 0 {
        y += 1;
    }
    if dir & SOUTH != 0 {
        y -= 1;
    }
    if dir & EAST != 0 {
        x += 1;
    }
    if dir & WEST != 0 {
        x -= 1;
    }
    if dir & UP != 0 {
        if up == 0 {
            return None;
        }
        z = i64::from(up);
    }
    if dir & DOWN != 0 {
        if down == 0 {
            return None;
        }
        z = i64::from(down);
    }
    let max = i64::from(XY_MASK);
    if x < 1 || y < 1 || x > max || y > max || z < 1 || z > i64::from(MAX_Z) {
        return None;
    }
    Some(pos(x as u32, y as u32, z as u32))
}

/// One cable piece's shape.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct CableShape {
    pub d1: u8,
    pub d2: u8,
    /// z above / below this cable's z (0 = none); only read for UP/DOWN.
    pub up: u32,
    pub down: u32,
    /// Ender cables with the same non-zero id are joined wherever they are.
    pub link: u32,
}

impl CableShape {
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

    /// The turfs this cable reaches off its own turf, each with the
    /// direction a cable there must have to connect back:
    /// `(turf, required dir)`.
    #[must_use]
    pub fn reaches(&self, p: u32) -> Vec<(u32, u8)> {
        let mut out = Vec::with_capacity(4);
        for dir in [self.d1, self.d2] {
            if dir == 0 {
                continue;
            }
            if let Some(t) = step(p, dir, self.up, self.down) {
                out.push((t, reverse(dir)));
            }
            if is_diagonal(dir) {
                for pair in [NORTH | SOUTH, EAST | WEST] {
                    if let Some(t) = step(p, dir & pair, 0, 0) {
                        out.push((t, dir ^ pair));
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

    #[test]
    fn diagonal_rule_is_symmetric() {
        // A NE half at (5,5) and a SE half at (5,6) join (the /\ pattern).
        let a = CableShape { d1: 0, d2: NORTH | EAST, ..Default::default() };
        let pa = pos(5, 5, 1);
        let b = CableShape { d1: 0, d2: SOUTH | EAST, ..Default::default() };
        let pb = pos(5, 6, 1);
        assert!(a.reaches(pa).iter().any(|&(t, d)| t == pb && b.has(d)));
        assert!(b.reaches(pb).iter().any(|&(t, d)| t == pa && a.has(d)));
    }

    #[test]
    fn vertical_needs_a_link() {
        let c = CableShape { d1: 0, d2: UP, up: 0, ..Default::default() };
        assert!(c.reaches(pos(3, 3, 2)).is_empty());
        let c = CableShape { d1: 0, d2: UP, up: 3, ..Default::default() };
        assert_eq!(c.reaches(pos(3, 3, 2)), vec![(pos(3, 3, 3), DOWN)]);
    }
}
