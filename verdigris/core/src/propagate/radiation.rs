//! Radiation shielding (`simulation.md` §8): a per-cell transmission layer
//! and pulses that attenuate a ray from the source to each target.
//!
//! DM owns what shields: it sends a cell's combined transmission (the turf's
//! `rad_insulation` times every movable's on it) whenever that changes, so
//! a pulse reads the layer and never walks turf contents.

use super::Ray;
use crate::grid::{ChunkedLayer, GridDims};

/// Per-cell radiation transmission, 1.0 (transparent) by default.
#[derive(Clone, Debug)]
pub struct RadiationField {
    /// `1 - transmission`, so an untouched chunk (all zero) is transparent.
    absorbed: ChunkedLayer<f32>,
}

/// A pulse target's result when it is out of range, on another z-level or
/// outside the grid.
pub const OUT_OF_RANGE: f32 = -1.0;

impl RadiationField {
    #[must_use]
    pub fn new(dims: GridDims) -> Self {
        Self {
            absorbed: ChunkedLayer::new(dims),
        }
    }

    #[must_use]
    pub const fn dims(&self) -> GridDims {
        self.absorbed.dims()
    }

    /// Sets a cell's transmission (clamped to 0..=1). `false` outside the grid.
    pub fn set_transmission(&mut self, cell: u32, transmission: f32) -> bool {
        let t = if transmission.is_finite() {
            transmission.clamp(0.0, 1.0)
        } else {
            1.0
        };
        self.absorbed.set(cell, 1.0 - t)
    }

    /// A cell's transmission; 1.0 outside the grid.
    #[must_use]
    pub fn transmission(&self, cell: u32) -> f32 {
        1.0 - self.absorbed.get(cell).unwrap_or(0.0)
    }

    /// Fraction of a pulse from `from` that reaches `to`: the product of the
    /// transmission of every cell after the source, the target's own cell
    /// included (a mob inside a locker is shielded by the locker). Stops
    /// once the product is below `cutoff`. 1.0 when `from == to`.
    #[must_use]
    pub fn path_transmission(&self, from: u32, to: u32, cutoff: f32) -> f32 {
        if from == to {
            return 1.0;
        }
        let Some(ray) = Ray::new(self.dims(), from, to) else {
            return 0.0;
        };
        let hit = ray.attenuate(1.0, cutoff, |cell| self.transmission(cell));
        if hit.stopped_at.is_some() {
            return hit.remaining;
        }
        hit.remaining * self.transmission(to)
    }

    /// One pulse: the path transmission from the zero-based `source` to each
    /// zero-based target, or [`OUT_OF_RANGE`] for targets on another z-level,
    /// farther than `range` (Chebyshev, like DM's `get_dist`) or off the grid.
    #[must_use]
    pub fn pulse(
        &self,
        source: (u32, u32, u32),
        range: u32,
        cutoff: f32,
        targets: &[(u32, u32, u32)],
    ) -> Vec<f32> {
        let dims = self.dims();
        let Some(from) = dims.index(source.0, source.1, source.2) else {
            return vec![OUT_OF_RANGE; targets.len()];
        };
        targets
            .iter()
            .map(|&(x, y, z)| {
                if z != source.2 || x.abs_diff(source.0).max(y.abs_diff(source.1)) > range {
                    return OUT_OF_RANGE;
                }
                dims.index(x, y, z)
                    .map_or(OUT_OF_RANGE, |to| self.path_transmission(from, to, cutoff))
            })
            .collect()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn field() -> RadiationField {
        RadiationField::new(GridDims::new(16, 16, 2).unwrap())
    }

    fn at(f: &RadiationField, x: u32, y: u32) -> u32 {
        f.dims().index(x, y, 0).unwrap()
    }

    #[test]
    fn open_space_is_transparent() {
        let f = field();
        assert_eq!(
            f.pulse((2, 2, 0), 10, 0.1, &[(8, 2, 0), (2, 2, 0)]),
            vec![1.0, 1.0]
        );
    }

    #[test]
    fn a_wall_shields() {
        let mut f = field();
        f.set_transmission(at(&f, 5, 2), 0.6);
        let r = f.pulse((2, 2, 0), 10, 0.0, &[(8, 2, 0), (8, 8, 0)]);
        assert!((r[0] - 0.6).abs() < 1e-6);
        assert_eq!(r[1], 1.0, "a target off the wall's line is unshielded");
    }

    #[test]
    fn the_source_cell_does_not_shield_but_the_target_cell_does() {
        let mut f = field();
        f.set_transmission(at(&f, 2, 2), 0.5);
        f.set_transmission(at(&f, 6, 2), 0.5);
        let r = f.pulse((2, 2, 0), 10, 0.0, &[(6, 2, 0)]);
        assert!((r[0] - 0.5).abs() < 1e-6);
    }

    #[test]
    fn full_insulation_blocks_and_cuts_off() {
        let mut f = field();
        f.set_transmission(at(&f, 4, 4), 0.0);
        assert_eq!(f.pulse((1, 1, 0), 10, 0.05, &[(7, 7, 0)]), vec![0.0]);
    }

    #[test]
    fn range_z_and_edges() {
        let f = field();
        let r = f.pulse(
            (0, 0, 0),
            3,
            0.0,
            &[(4, 0, 0), (3, 3, 0), (0, 0, 1), (16, 0, 0)],
        );
        assert_eq!(r, vec![OUT_OF_RANGE, 1.0, OUT_OF_RANGE, OUT_OF_RANGE]);
    }

    #[test]
    fn clearing_a_cell_restores_transmission() {
        let mut f = field();
        let c = at(&f, 3, 3);
        f.set_transmission(c, 0.2);
        f.set_transmission(c, 1.0);
        assert_eq!(f.transmission(c), 1.0);
    }
}
