//! Cell indexing for BYOND's turf grid.
//!
//! A turf index is BYOND's zero-based turf ref number:
//! `(x - 1) + (y - 1) * max_x + (z - 1) * max_x * max_y`.

/// One of the six grid faces. The discriminant is the bit position of the same
/// direction in BYOND's `NORTH`/`SOUTH`/`EAST`/`WEST`/`UP`/`DOWN` flags.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
#[repr(u8)]
pub enum Face {
    North = 0,
    South = 1,
    East = 2,
    West = 3,
    Up = 4,
    Down = 5,
}

impl Face {
    pub const ALL: [Face; 6] = [
        Face::North,
        Face::South,
        Face::East,
        Face::West,
        Face::Up,
        Face::Down,
    ];

    /// The face for a BYOND direction bit position (0..6).
    #[must_use]
    pub const fn from_bit_index(bit: u8) -> Option<Face> {
        match bit {
            0 => Some(Face::North),
            1 => Some(Face::South),
            2 => Some(Face::East),
            3 => Some(Face::West),
            4 => Some(Face::Up),
            5 => Some(Face::Down),
            _ => None,
        }
    }
}

/// World dimensions. Every neighbour lookup is bounds-checked: a cell on the
/// east edge has no east neighbour (it does not wrap to the next row), and a
/// cell on the top row has no north neighbour (it does not step into the next
/// z-level).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct GridDims {
    max_x: u32,
    max_y: u32,
    max_z: u32,
}

impl GridDims {
    /// `None` if any dimension is zero or the grid does not fit a `u32` index.
    #[must_use]
    pub fn new(max_x: u32, max_y: u32, max_z: u32) -> Option<Self> {
        if max_x == 0 || max_y == 0 || max_z == 0 {
            return None;
        }
        max_x.checked_mul(max_y)?.checked_mul(max_z)?;
        Some(Self {
            max_x,
            max_y,
            max_z,
        })
    }

    /// Dimensions when only the plane size is known. The z range is as deep as
    /// a `u32` index allows, so `Up` is bounded only by the index space.
    #[must_use]
    pub fn planar(max_x: u32, max_y: u32) -> Option<Self> {
        let layer = max_x.checked_mul(max_y)?;
        if layer == 0 {
            return None;
        }
        Self::new(max_x, max_y, u32::MAX / layer)
    }

    #[must_use]
    pub const fn layer_len(self) -> u32 {
        self.max_x * self.max_y
    }

    /// Zero-based (x, y, z) of an index, or `None` if it is outside the grid.
    #[must_use]
    pub const fn coords(self, index: u32) -> Option<(u32, u32, u32)> {
        let layer = self.layer_len();
        let z = index / layer;
        if z >= self.max_z {
            return None;
        }
        let in_layer = index % layer;
        Some((in_layer % self.max_x, in_layer / self.max_x, z))
    }

    /// The index of the cell across `face`, or `None` at the grid edge.
    #[must_use]
    pub const fn neighbor(self, index: u32, face: Face) -> Option<u32> {
        let Some((x, y, z)) = self.coords(index) else {
            return None;
        };
        match face {
            Face::North if y + 1 < self.max_y => Some(index + self.max_x),
            Face::South if y > 0 => Some(index - self.max_x),
            Face::East if x + 1 < self.max_x => Some(index + 1),
            Face::West if x > 0 => Some(index - 1),
            Face::Up if z + 1 < self.max_z => Some(index + self.layer_len()),
            Face::Down if z > 0 => Some(index - self.layer_len()),
            _ => None,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn dims() -> GridDims {
        GridDims::new(4, 3, 2).unwrap()
    }

    fn index(x: u32, y: u32, z: u32) -> u32 {
        x + y * 4 + z * 12
    }

    #[test]
    fn rejects_empty_and_overflowing_grids() {
        assert!(GridDims::new(0, 3, 1).is_none());
        assert!(GridDims::new(u32::MAX, 2, 1).is_none());
        assert!(GridDims::planar(0, 5).is_none());
    }

    #[test]
    fn interior_cell_has_all_six_neighbours() {
        let dims = GridDims::new(4, 3, 3).unwrap();
        let centre = 1 + 4 + 12;
        let found = Face::ALL.map(|face| dims.neighbor(centre, face));
        assert_eq!(
            found,
            [
                Some(centre + 4),
                Some(centre - 4),
                Some(centre + 1),
                Some(centre - 1),
                Some(centre + 12),
                Some(centre - 12),
            ]
        );
    }

    /// Regression for B1: heat conducted from the east edge into the next row's
    /// west edge, and from the top row into the next z-level.
    #[test]
    fn edges_do_not_wrap() {
        let d = dims();
        for z in 0..2 {
            for y in 0..3 {
                assert_eq!(d.neighbor(index(3, y, z), Face::East), None);
                assert_eq!(d.neighbor(index(0, y, z), Face::West), None);
            }
            for x in 0..4 {
                assert_eq!(d.neighbor(index(x, 2, z), Face::North), None);
                assert_eq!(d.neighbor(index(x, 0, z), Face::South), None);
            }
        }
        assert_eq!(d.neighbor(index(1, 1, 1), Face::Up), None);
        assert_eq!(d.neighbor(index(1, 1, 0), Face::Down), None);
        assert_eq!(d.neighbor(24, Face::West), None, "index outside the grid");
    }

    #[test]
    fn neighbour_relation_is_symmetric() {
        let d = dims();
        let opposite = |face| match face {
            Face::North => Face::South,
            Face::South => Face::North,
            Face::East => Face::West,
            Face::West => Face::East,
            Face::Up => Face::Down,
            Face::Down => Face::Up,
        };
        for cell in 0..24 {
            for face in Face::ALL {
                if let Some(other) = d.neighbor(cell, face) {
                    assert_eq!(d.neighbor(other, opposite(face)), Some(cell));
                }
            }
        }
    }

    #[test]
    fn planar_dims_bound_the_plane() {
        let d = GridDims::planar(255, 255).unwrap();
        assert_eq!(d.neighbor(254, Face::East), None);
        assert_eq!(d.neighbor(254, Face::Up), Some(254 + 255 * 255));
        assert_eq!(d.neighbor(0, Face::Down), None);
    }
}
