//! Rays: a symmetric DDA line through the grid.
//!
//! A ray from `a` to `b` visits `n + 1` cells, where `n` is the largest
//! per-axis distance; step `k` is at `round(k * d / n)` on each axis from
//! the ray's canonical start, rounding halves up. The canonical start is
//! the endpoint with the smaller index, so a ray and its reverse visit the
//! same cells in opposite order (plain Bresenham does not guarantee that).
//! Consecutive cells differ by at most one on every axis. Everything is
//! integer arithmetic computed per step, so a ray needs no scratch at all.
//!
//! Rays may change z-level; the path is the same formula on the z axis.

use crate::grid::{BlockKind, Dir, Face, Grid, GridDims};

/// The cells from one grid cell to another, inclusive, as an iterator.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Ray {
    dims: GridDims,
    /// Canonical start (the endpoint with the smaller index).
    origin: [i64; 3],
    delta: [i64; 3],
    n: i64,
    /// Walk from the canonical end back to its start.
    reversed: bool,
    /// Next step to yield (in the ray's own direction) and one past the last.
    front: i64,
    back: i64,
}

fn axis_offset(k: i64, d: i64, n: i64) -> i64 {
    // round(k * d / n) with halves rounded toward +inf.
    (2 * k * d + n).div_euclid(2 * n)
}

impl Ray {
    /// The ray from `from` to `to`, or `None` if either is outside the grid.
    #[must_use]
    pub fn new(dims: GridDims, from: u32, to: u32) -> Option<Ray> {
        let a = dims.coords(from)?;
        let b = dims.coords(to)?;
        let (start, end, reversed) = if from <= to {
            (a, b, false)
        } else {
            (b, a, true)
        };
        let origin = [i64::from(start.0), i64::from(start.1), i64::from(start.2)];
        let delta = [
            i64::from(end.0) - origin[0],
            i64::from(end.1) - origin[1],
            i64::from(end.2) - origin[2],
        ];
        let n = delta.iter().map(|d| d.abs()).max().unwrap_or(0);
        Some(Ray {
            dims,
            origin,
            delta,
            n,
            reversed,
            front: 0,
            back: n + 1,
        })
    }

    /// Steps between the endpoints (cells visited minus one).
    #[must_use]
    pub const fn steps(&self) -> u32 {
        self.n as u32
    }

    /// The cell at step `k` (0 = `from`, [`steps`](Self::steps) = `to`).
    #[must_use]
    pub fn cell_at(&self, k: u32) -> Option<u32> {
        let k = i64::from(k);
        if k > self.n {
            return None;
        }
        let c = if self.reversed { self.n - k } else { k };
        let at = |axis: usize| {
            let off = if self.n == 0 {
                0
            } else {
                axis_offset(c, self.delta[axis], self.n)
            };
            (self.origin[axis] + off) as u32
        };
        self.dims.index(at(0), at(1), at(2))
    }

    /// Multiplies `intensity` by `factor(cell)` for every cell strictly
    /// between the endpoints, in ray order, stopping early once it drops
    /// below `cutoff`. The endpoints are excluded so a source is not shielded
    /// by its own cell and the result is the same in both directions (up to
    /// float rounding of the reversed product).
    pub fn attenuate<F>(self, intensity: f32, cutoff: f32, mut factor: F) -> RayHit
    where
        F: FnMut(u32) -> f32,
    {
        let mut remaining = intensity;
        let mut cells = 0;
        for k in 1..self.steps() {
            let cell = self.cell_at(k).expect("ray cells are in the grid");
            remaining *= factor(cell);
            cells += 1;
            if remaining < cutoff {
                return RayHit {
                    remaining,
                    cells,
                    stopped_at: Some(cell),
                };
            }
        }
        RayHit {
            remaining,
            cells,
            stopped_at: None,
        }
    }
}

impl Iterator for Ray {
    type Item = u32;

    fn next(&mut self) -> Option<u32> {
        if self.front >= self.back {
            return None;
        }
        let cell = self.cell_at(self.front as u32);
        self.front += 1;
        cell
    }

    fn size_hint(&self) -> (usize, Option<usize>) {
        let len = (self.back - self.front).max(0) as usize;
        (len, Some(len))
    }
}

impl DoubleEndedIterator for Ray {
    fn next_back(&mut self) -> Option<u32> {
        if self.front >= self.back {
            return None;
        }
        self.back -= 1;
        self.cell_at(self.back as u32)
    }
}

impl ExactSizeIterator for Ray {}

/// The result of [`Ray::attenuate`].
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct RayHit {
    /// Intensity left after the cells passed.
    pub remaining: f32,
    /// Cells whose factor was applied.
    pub cells: u32,
    /// The cell that pushed the intensity under the cutoff, if one did.
    pub stopped_at: Option<u32>,
}

/// Face of `grid` for moving one cell along `axis` (0 x, 1 y, 2 z) by `sign`.
fn face_for(axis: usize, sign: i64) -> Face {
    match (axis, sign > 0) {
        (0, true) => Face::East,
        (0, false) => Face::West,
        (1, true) => Face::North,
        (1, false) => Face::South,
        (_, true) => Face::Up,
        (_, false) => Face::Down,
    }
}

/// One single-axis move, checking the near side's face unless `skip_near`
/// and the far side's unless `skip_far`.
fn sub_step(
    grid: &Grid,
    kind: BlockKind,
    cell: u32,
    face: Face,
    skip_near: bool,
    skip_far: bool,
) -> Option<u32> {
    let next = grid.neighbor(cell, face)?;
    let near: Dir = grid.blocked(kind, cell);
    let far: Dir = grid.blocked(kind, next);
    let blocked =
        (!skip_near && near.contains(face)) || (!skip_far && far.contains(face.opposite()));
    (!blocked).then_some(next)
}

/// Whether a ray from `from` to `to` gets through `kind`'s blocked faces.
///
/// Each ray step moves up to one cell on each axis; a step that changes
/// several axes passes if any order of single-axis moves does (so a
/// diagonal squeezes past one wall corner but not between two). The
/// viewer's own faces and the target's own faces are not checked, so a wall
/// cell can be seen and the answer is symmetric in `from` and `to`. `false`
/// if either cell is outside the grid.
#[must_use]
pub fn line_of_sight(grid: &Grid, kind: BlockKind, from: u32, to: u32) -> bool {
    let Some(ray) = Ray::new(grid.dims(), from, to) else {
        return false;
    };
    let dims = grid.dims();
    let steps = ray.steps();
    let mut prev = from;
    for k in 1..=steps {
        let next = ray.cell_at(k).expect("ray cells are in the grid");
        let (px, py, pz) = dims.coords(prev).expect("in grid");
        let (nx, ny, nz) = dims.coords(next).expect("in grid");
        let d = [
            i64::from(nx) - i64::from(px),
            i64::from(ny) - i64::from(py),
            i64::from(nz) - i64::from(pz),
        ];
        let mut faces = [Face::North; 3];
        let mut count = 0;
        for (axis, &s) in d.iter().enumerate() {
            if s != 0 {
                faces[count] = face_for(axis, s);
                count += 1;
            }
        }
        if !step_passes(grid, kind, prev, &faces[..count], k == 1, k == steps) {
            return false;
        }
        prev = next;
    }
    true
}

/// Whether some order of the single-axis `faces` moves gets from `cell`
/// through. `first`/`last` mark the ray's first and last steps.
fn step_passes(
    grid: &Grid,
    kind: BlockKind,
    cell: u32,
    faces: &[Face],
    first: bool,
    last: bool,
) -> bool {
    const ORDERS: [[usize; 3]; 6] = [
        [0, 1, 2],
        [0, 2, 1],
        [1, 0, 2],
        [1, 2, 0],
        [2, 0, 1],
        [2, 1, 0],
    ];
    let len = faces.len();
    ORDERS
        .iter()
        .filter(|order| order[..len].iter().all(|&i| i < len))
        .any(|order| {
            let mut at = cell;
            for (j, &i) in order[..len].iter().enumerate() {
                let skip_near = first && j == 0;
                let skip_far = last && j + 1 == len;
                match sub_step(grid, kind, at, faces[i], skip_near, skip_far) {
                    Some(n) => at = n,
                    None => return false,
                }
            }
            true
        })
}

#[cfg(test)]
mod tests {
    use super::*;
    use proptest::prelude::*;

    /// Reference line: float DDA from the smaller-index endpoint, rounding
    /// halves up, then reversed if the ray runs the other way.
    fn reference(dims: GridDims, from: u32, to: u32) -> Vec<u32> {
        let (s, e) = if from <= to { (from, to) } else { (to, from) };
        let a = dims.coords(s).unwrap();
        let b = dims.coords(e).unwrap();
        let a = [f64::from(a.0), f64::from(a.1), f64::from(a.2)];
        let b = [f64::from(b.0), f64::from(b.1), f64::from(b.2)];
        let n = (0..3).map(|i| (b[i] - a[i]).abs()).fold(0.0, f64::max);
        let mut out: Vec<u32> = (0..=n as u32)
            .map(|k| {
                let t = if n == 0.0 { 0.0 } else { f64::from(k) / n };
                let p: Vec<u32> = (0..3)
                    .map(|i| (a[i] + (b[i] - a[i]) * t + 0.5).floor() as u32)
                    .collect();
                dims.index(p[0], p[1], p[2]).unwrap()
            })
            .collect();
        if from > to {
            out.reverse();
        }
        out
    }

    fn arb_ray() -> impl Strategy<Value = (GridDims, u32, u32)> {
        (1u32..60, 1u32..60, 1u32..4).prop_flat_map(|(x, y, z)| {
            let n = x * y * z;
            (Just(GridDims::new(x, y, z).unwrap()), 0..n, 0..n)
        })
    }

    proptest! {
        #[test]
        fn matches_reference_line((dims, a, b) in arb_ray()) {
            let cells: Vec<u32> = Ray::new(dims, a, b).unwrap().collect();
            prop_assert_eq!(&cells, &reference(dims, a, b));
        }

        #[test]
        fn symmetric_contiguous_and_exact_size((dims, a, b) in arb_ray()) {
            let ray = Ray::new(dims, a, b).unwrap();
            prop_assert_eq!(ray.len(), ray.steps() as usize + 1);
            let fwd: Vec<u32> = ray.collect();
            let mut back: Vec<u32> = Ray::new(dims, b, a).unwrap().collect();
            back.reverse();
            prop_assert_eq!(&fwd, &back);
            prop_assert_eq!(fwd.first(), Some(&a));
            prop_assert_eq!(fwd.last(), Some(&b));
            let rev: Vec<u32> = ray.rev().collect();
            prop_assert_eq!(rev.iter().rev().copied().collect::<Vec<_>>(), fwd.clone());
            for w in fwd.windows(2) {
                let p = dims.coords(w[0]).unwrap();
                let q = dims.coords(w[1]).unwrap();
                prop_assert!(p.0.abs_diff(q.0) <= 1 && p.1.abs_diff(q.1) <= 1 && p.2.abs_diff(q.2) <= 1);
                prop_assert_ne!(w[0], w[1]);
            }
        }

        #[test]
        fn line_of_sight_is_symmetric(
            (dims, a, b) in arb_ray(),
            walls in prop::collection::vec((any::<u32>(), 1u8..64), 0..60),
        ) {
            let mut grid = Grid::new(dims);
            let len = dims.layer_len() * dims.max_z();
            for (i, m) in walls {
                grid.set_blocked(BlockKind::Opacity, i % len, Dir(m));
            }
            prop_assert_eq!(
                line_of_sight(&grid, BlockKind::Opacity, a, b),
                line_of_sight(&grid, BlockKind::Opacity, b, a)
            );
            // Unblocked for another kind.
            prop_assert!(line_of_sight(&grid, BlockKind::Radiation, a, b));
        }

        #[test]
        fn attenuation_matches_manual_product((dims, a, b) in arb_ray(), f in prop::collection::vec(0.5f32..1.0, 64)) {
            let factor = |c: u32| f[c as usize % f.len()];
            let hit = Ray::new(dims, a, b).unwrap().attenuate(100.0, 0.0, factor);
            let cells: Vec<u32> = Ray::new(dims, a, b).unwrap().collect();
            let inner = &cells[1..cells.len().saturating_sub(1).max(1)];
            let expected = inner.iter().fold(100.0f32, |acc, &c| acc * factor(c));
            prop_assert_eq!(hit.remaining, expected);
            prop_assert_eq!(hit.cells as usize, inner.len());
            prop_assert_eq!(hit.stopped_at, None);
            let back = Ray::new(dims, b, a).unwrap().attenuate(100.0, 0.0, factor);
            prop_assert!((back.remaining - hit.remaining).abs() <= 1e-3 * hit.remaining.max(1.0));
        }
    }

    #[test]
    fn known_lines_and_bounds() {
        let dims = GridDims::new(10, 10, 2).unwrap();
        let i = |x, y, z| dims.index(x, y, z).unwrap();
        let cells: Vec<u32> = Ray::new(dims, i(0, 0, 0), i(4, 2, 0)).unwrap().collect();
        assert_eq!(
            cells,
            vec![i(0, 0, 0), i(1, 1, 0), i(2, 1, 0), i(3, 2, 0), i(4, 2, 0)]
        );
        assert_eq!(Ray::new(dims, 5, 5).unwrap().collect::<Vec<_>>(), vec![5]);
        assert_eq!(Ray::new(dims, 0, 200), None);
        assert!(!line_of_sight(&Grid::new(dims), BlockKind::Opacity, 0, 200));
        // Z transition: straight up one level.
        let up: Vec<u32> = Ray::new(dims, i(3, 3, 0), i(5, 3, 1)).unwrap().collect();
        assert_eq!(up, vec![i(3, 3, 0), i(4, 3, 1), i(5, 3, 1)]);
        // Along the east edge a ray never wraps.
        let edge: Vec<u32> = Ray::new(dims, i(9, 0, 0), i(9, 9, 0)).unwrap().collect();
        assert!(edge.iter().all(|&c| dims.coords(c).unwrap().0 == 9));
    }

    #[test]
    fn walls_block_sight_and_attenuate() {
        let dims = GridDims::new(9, 9, 2).unwrap();
        let i = |x, y, z| dims.index(x, y, z).unwrap();
        let mut grid = Grid::new(dims);
        assert!(line_of_sight(
            &grid,
            BlockKind::Opacity,
            i(0, 4, 0),
            i(8, 4, 0)
        ));
        grid.set_blocked(BlockKind::Opacity, i(4, 4, 0), Dir::ALL);
        assert!(!line_of_sight(
            &grid,
            BlockKind::Opacity,
            i(0, 4, 0),
            i(8, 4, 0)
        ));
        // The wall itself is visible, and you can see out of it.
        assert!(line_of_sight(
            &grid,
            BlockKind::Opacity,
            i(0, 4, 0),
            i(4, 4, 0)
        ));
        assert!(line_of_sight(
            &grid,
            BlockKind::Opacity,
            i(4, 4, 0),
            i(0, 4, 0)
        ));
        // A diagonal slips past one corner wall but not between two.
        let mut g2 = Grid::new(dims);
        g2.set_blocked(BlockKind::Opacity, i(1, 0, 0), Dir::ALL);
        g2.set_blocked(BlockKind::Opacity, i(0, 1, 0), Dir::ALL);
        assert!(!line_of_sight(
            &g2,
            BlockKind::Opacity,
            i(0, 0, 0),
            i(2, 2, 0)
        ));
        g2.set_blocked(BlockKind::Opacity, i(0, 1, 0), Dir::NONE);
        assert!(line_of_sight(
            &g2,
            BlockKind::Opacity,
            i(0, 0, 0),
            i(2, 2, 0)
        ));
        // A sealed floor blocks sight between z-levels.
        let mut g3 = Grid::new(dims);
        assert!(line_of_sight(
            &g3,
            BlockKind::Opacity,
            i(2, 2, 0),
            i(2, 2, 1)
        ));
        g3.set_blocked(BlockKind::Opacity, i(2, 3, 0), Dir::NONE.with(Face::Up));
        assert!(line_of_sight(
            &g3,
            BlockKind::Opacity,
            i(2, 2, 0),
            i(2, 4, 1)
        ));
        g3.set_blocked(BlockKind::Opacity, i(2, 2, 0), Dir::NONE.with(Face::Up));
        g3.set_blocked(BlockKind::Opacity, i(2, 3, 0), Dir::ALL);
        assert!(!line_of_sight(
            &g3,
            BlockKind::Opacity,
            i(2, 1, 0),
            i(2, 5, 1)
        ));

        // Attenuation stops at the first cell under the cutoff.
        let ray = Ray::new(dims, i(0, 0, 0), i(8, 0, 0)).unwrap();
        let hit = ray.attenuate(1.0, 0.3, |c| if c == i(3, 0, 0) { 0.1 } else { 0.9 });
        assert_eq!(hit.stopped_at, Some(i(3, 0, 0)));
        assert_eq!(hit.cells, 3);
        // A fully blocked insulation cell zeroes the ray.
        let hit = ray.attenuate(1.0, 0.0, |c| if c == i(5, 0, 0) { 0.0 } else { 1.0 });
        assert_eq!(hit.remaining, 0.0);
        assert_eq!(hit.cells, 7);
    }
}
