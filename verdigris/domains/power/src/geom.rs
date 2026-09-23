//! Turf position packing and BYOND direction math: what the cable
//! connection rule ([`crate::laws::connects`]/[`crate::laws::reach`])
//! builds on, so Rust derives the graph from what DM already knows about
//! each cable (turf, `d1`, `d2`) without DM sending topology.

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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reverse_undoes_every_direction() {
        for dir in [NORTH, SOUTH, EAST, WEST, UP, DOWN] {
            assert_eq!(reverse(reverse(dir)), dir);
        }
        assert_eq!(reverse(NORTH | EAST), SOUTH | WEST);
    }

    #[test]
    fn step_respects_bounds_and_explicit_z_links() {
        assert_eq!(step(pos(5, 5, 1), NORTH, 0, 0), Some(pos(5, 6, 1)));
        assert_eq!(step(pos(5, 5, 1), UP, 0, 0), None, "no linked z above");
        assert_eq!(step(pos(5, 5, 1), UP, 3, 0), Some(pos(5, 5, 3)), "follows the explicit link, not z+1");
    }
}
