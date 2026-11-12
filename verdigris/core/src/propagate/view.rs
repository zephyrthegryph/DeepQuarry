//! Sight over a blocking layer of the [`Grid`](crate::grid::Grid): which cells
//! of one z-level a viewer at `center` sees within a square `range`, through
//! cells that block [`BlockKind::Opacity`] (or any kind).
//!
//! A cell blocks sight when any of its faces is blocked: an opaque atom makes
//! its whole turf opaque, border ones included. Light, line of sight for AI and
//! the like read this one layer; DM feeds it from turf `directional_opacity`
//! (`code/domains/verdigris/sight/`).
//!
//! The walk is symmetric shadowcasting, chosen for how it looks rather than to
//! copy BYOND's `view()`:
//! - The square around the viewer is cast as four quadrants (north, east,
//!   south, west), row by row outwards. Each row keeps the open interval of
//!   slopes still lit; a blocking cell narrows it for the rows behind.
//! - A clear cell is seen only when its centre lies inside the lit interval,
//!   so sight is symmetric: if a floor sees another floor, that floor sees it
//!   back. Nothing pops in or out at the edge of a shadow as the viewer moves.
//! - A blocking cell is seen when any part of it is lit, so a wall shows its
//!   whole face; then every blocking cell next to (by side) a seen clear cell
//!   is seen too, so a lit room never has a dark notch in its wall.
//! - Two blocking cells that touch only at a corner close the gap between
//!   them: a clear cell whose two neighbours toward the viewer both block is
//!   dark and passes nothing on, so no light squeezes through a wall seam.
//! - The viewer's own cell is clear for the walk (a viewer inside a wall still
//!   looks out) and is always seen.
//!
//! Slopes are exact rationals, so the result depends only on the layer and
//! the inputs.
use crate::grid::{BlockKind, Grid};

/// A slope `num / den` (`den > 0`), compared exactly.
#[derive(Clone, Copy)]
struct Slope {
    num: i64,
    den: i64,
}

impl Slope {
    fn le(self, other: Slope) -> bool {
        self.num * other.den <= other.num * self.den
    }
}

/// The window around the viewer: cells by offset, `None` off the map.
struct Window {
    r: i64,
    side: i64,
    cells: Vec<Option<(u32, bool)>>,
    seen: Vec<bool>,
}

impl Window {
    fn idx(&self, dx: i64, dy: i64) -> Option<usize> {
        (dx.abs() <= self.r && dy.abs() <= self.r)
            .then(|| ((dy + self.r) * self.side + (dx + self.r)) as usize)
    }

    fn cell(&self, dx: i64, dy: i64) -> Option<(u32, bool)> {
        self.idx(dx, dy).and_then(|i| self.cells[i])
    }

    /// Off the map counts as blocking: nothing is seen through the edge.
    fn blocks(&self, dx: i64, dy: i64) -> bool {
        if (dx, dy) == (0, 0) {
            return false;
        }
        self.cell(dx, dy).is_none_or(|c| c.1)
    }

    fn reveal(&mut self, dx: i64, dy: i64) {
        if let Some(i) = self.idx(dx, dy) {
            if self.cells[i].is_some() {
                self.seen[i] = true;
            }
        }
    }
}

/// Quadrant `q` maps (depth, column) to an offset from the viewer.
fn offset(q: u8, depth: i64, col: i64) -> (i64, i64) {
    match q {
        0 => (col, depth),   // north
        1 => (depth, -col),  // east
        2 => (-col, -depth), // south
        _ => (-depth, col),  // west
    }
}

/// floor(n + 1/2) and ceil(n - 1/2) of `depth * slope`.
fn round_ties_up(depth: i64, s: Slope) -> i64 {
    (2 * depth * s.num + s.den).div_euclid(2 * s.den)
}

fn round_ties_down(depth: i64, s: Slope) -> i64 {
    -((-2 * depth * s.num + s.den).div_euclid(2 * s.den))
}

fn cast(win: &mut Window, q: u8, depth: i64, mut start: Slope, end: Slope) {
    if depth > win.r || !start.le(end) {
        return;
    }
    let lo = round_ties_up(depth, start);
    let hi = round_ties_down(depth, end);
    let mut prev_blocks: Option<bool> = None;
    for col in lo..=hi {
        let (dx, dy) = offset(q, depth, col);
        let wall = win.blocks(dx, dy);
        // A clear cell behind a diagonal seam (both its neighbours toward the
        // viewer block) is shut off: it stays dark and passes no light on.
        let seam = !wall && col != 0 && {
            let (vx, vy) = offset(q, depth - 1, col);
            let (hx, hy) = offset(q, depth, col - col.signum());
            win.blocks(vx, vy) && win.blocks(hx, hy)
        };
        let blocks = wall || seam;
        // A clear cell counts only when its centre is inside the lit interval.
        let centre = Slope {
            num: col,
            den: depth,
        };
        if wall || (!seam && start.le(centre) && centre.le(end)) {
            win.reveal(dx, dy);
        }
        match prev_blocks {
            Some(true) if !blocks => {
                start = Slope {
                    num: 2 * col - 1,
                    den: 2 * depth,
                }
            }
            Some(false) if blocks => {
                cast(
                    win,
                    q,
                    depth + 1,
                    start,
                    Slope {
                        num: 2 * col - 1,
                        den: 2 * depth,
                    },
                );
            }
            _ => {}
        }
        prev_blocks = Some(blocks);
    }
    if prev_blocks == Some(false) {
        cast(win, q, depth + 1, start, end);
    }
}

/// The cells `center` sees within `range` on its own z-level, the centre
/// first, then in window order. Empty if `center` is outside the grid.
#[must_use]
pub fn view(grid: &Grid, kind: BlockKind, center: u32, range: u32) -> Vec<u32> {
    let dims = grid.dims();
    let Some((cx, cy, cz)) = dims.coords(center) else {
        return Vec::new();
    };
    let r = i64::from(range);
    let side = 2 * r + 1;
    let (max_x, max_y) = (i64::from(dims.max_x()), i64::from(dims.max_y()));
    let mut cells = vec![None; (side * side) as usize];
    for dy in -r..=r {
        for dx in -r..=r {
            let (x, y) = (i64::from(cx) + dx, i64::from(cy) + dy);
            if x < 0 || y < 0 || x >= max_x || y >= max_y {
                continue;
            }
            if let Some(cell) = dims.index(x as u32, y as u32, cz) {
                let i = ((dy + r) * side + (dx + r)) as usize;
                cells[i] = Some((cell, !grid.blocked(kind, cell).is_empty()));
            }
        }
    }
    let mut win = Window {
        r,
        side,
        cells,
        seen: vec![false; (side * side) as usize],
    };
    win.reveal(0, 0);
    for q in 0..4 {
        cast(
            &mut win,
            q,
            1,
            Slope { num: -1, den: 1 },
            Slope { num: 1, den: 1 },
        );
    }
    // Wall faces: a blocking cell beside a seen clear cell is seen.
    let mut faces = Vec::new();
    for dy in -r..=r {
        for dx in -r..=r {
            let Some(i) = win.idx(dx, dy) else { continue };
            if win.seen[i] || !win.cell(dx, dy).is_some_and(|c| c.1) {
                continue;
            }
            let beside_seen_floor =
                [(1, 0), (-1, 0), (0, 1), (0, -1)]
                    .into_iter()
                    .any(|(ax, ay)| {
                        let (nx, ny) = (dx + ax, dy + ay);
                        win.idx(nx, ny).is_some_and(|j| win.seen[j]) && !win.blocks(nx, ny)
                    });
            if beside_seen_floor {
                faces.push(i);
            }
        }
    }
    for i in faces {
        win.seen[i] = true;
    }
    let mut out = Vec::with_capacity(win.seen.iter().filter(|s| **s).count());
    out.push(center);
    for (i, seen) in win.seen.iter().enumerate() {
        if *seen {
            if let Some((cell, _)) = win.cells[i] {
                if cell != center {
                    out.push(cell);
                }
            }
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::grid::{Dir, GridDims};
    use std::collections::HashSet;

    fn grid(n: u32) -> Grid {
        Grid::new(GridDims::planar(n, n).expect("dims"))
    }

    fn at(g: &Grid, x: u32, y: u32) -> u32 {
        g.dims().index(x, y, 0).unwrap()
    }

    fn wall(g: &mut Grid, x: u32, y: u32) {
        let c = at(g, x, y);
        g.set_blocked(BlockKind::Opacity, c, Dir::ALL);
    }

    fn seen(g: &Grid, x: u32, y: u32, r: u32) -> HashSet<u32> {
        view(g, BlockKind::Opacity, at(g, x, y), r)
            .into_iter()
            .collect()
    }

    fn blocks(g: &Grid, c: u32) -> bool {
        !g.blocked(BlockKind::Opacity, c).is_empty()
    }

    /// A deterministic scatter of walls (xorshift, no external crates).
    fn scattered(n: u32, seed: u64, per_mille: u64) -> Grid {
        let mut g = grid(n);
        let mut s = seed | 1;
        for y in 0..n {
            for x in 0..n {
                s ^= s << 13;
                s ^= s >> 7;
                s ^= s << 17;
                if s % 1000 < per_mille {
                    wall(&mut g, x, y);
                }
            }
        }
        g
    }

    #[test]
    fn open_room_sees_the_whole_square() {
        let g = grid(11);
        assert_eq!(seen(&g, 5, 5, 3).len(), 49);
    }

    #[test]
    fn a_wall_is_seen_and_hides_what_is_behind_it() {
        let mut g = grid(11);
        wall(&mut g, 7, 5);
        let v = seen(&g, 5, 5, 4);
        assert!(v.contains(&at(&g, 7, 5)));
        assert!(!v.contains(&at(&g, 9, 5)));
    }

    #[test]
    fn the_map_edge_clips_the_square() {
        let g = grid(5);
        assert_eq!(seen(&g, 0, 0, 2).len(), 9);
    }

    #[test]
    fn a_viewer_inside_a_wall_still_sees_out() {
        let mut g = grid(7);
        wall(&mut g, 3, 3);
        assert_eq!(seen(&g, 3, 3, 1).len(), 9);
    }

    #[test]
    fn sight_between_floors_is_symmetric() {
        for seed in 1..=12u64 {
            let g = scattered(17, seed * 7919, 220);
            let n = 17;
            for r in [2u32, 4, 6] {
                let views: Vec<Option<HashSet<u32>>> = (0..n * n)
                    .map(|c| {
                        (!blocks(&g, c))
                            .then(|| view(&g, BlockKind::Opacity, c, r).into_iter().collect())
                    })
                    .collect();
                for a in 0..n * n {
                    let Some(va) = &views[a as usize] else {
                        continue;
                    };
                    for &b in va {
                        if let Some(vb) = &views[b as usize] {
                            assert!(
                                vb.contains(&a),
                                "seed {seed} r {r}: {a} sees {b} but not back"
                            );
                        }
                    }
                }
            }
        }
    }

    #[test]
    fn every_wall_beside_a_seen_floor_is_seen() {
        for seed in 1..=12u64 {
            let g = scattered(17, seed * 104_729, 250);
            let dims = g.dims();
            for c in 0..17 * 17 {
                if blocks(&g, c) {
                    continue;
                }
                let v: HashSet<u32> = view(&g, BlockKind::Opacity, c, 5).into_iter().collect();
                let (cx, cy, _) = dims.coords(c).unwrap();
                for &f in &v {
                    if blocks(&g, f) {
                        continue;
                    }
                    let (fx, fy, _) = dims.coords(f).unwrap();
                    for (ax, ay) in [(1i64, 0i64), (-1, 0), (0, 1), (0, -1)] {
                        let (wx, wy) = (i64::from(fx) + ax, i64::from(fy) + ay);
                        if wx < 0 || wy < 0 || wx >= 17 || wy >= 17 {
                            continue;
                        }
                        if (wx - i64::from(cx)).abs() > 5 || (wy - i64::from(cy)).abs() > 5 {
                            continue;
                        }
                        let w = dims.index(wx as u32, wy as u32, 0).unwrap();
                        if blocks(&g, w) {
                            assert!(
                                v.contains(&w),
                                "seed {seed}: wall {w} beside seen floor {f} is dark"
                            );
                        }
                    }
                }
            }
        }
    }

    #[test]
    fn no_light_through_a_diagonal_wall_seam() {
        // Walls east of and north of the viewer at (1, 1) meet at a corner: (2, 2) and beyond stay dark.
        let mut g = grid(7);
        wall(&mut g, 2, 1);
        wall(&mut g, 1, 2);
        let v = seen(&g, 1, 1, 4);
        assert!(
            !v.contains(&at(&g, 2, 2)),
            "the cell beyond the seam is dark"
        );
        assert!(
            !v.contains(&at(&g, 3, 3)),
            "light does not run on along the diagonal"
        );
    }

    #[test]
    fn moving_one_tile_in_the_open_changes_nothing_near() {
        // An open room with one pillar: a step changes visibility only behind the pillar.
        let mut g = grid(21);
        wall(&mut g, 12, 10);
        for x in 5..15u32 {
            let a = seen(&g, x, 6, 6);
            let b = seen(&g, x + 1, 6, 6);
            for c in a.symmetric_difference(&b) {
                let (px, py, _) = g.dims().coords(*c).unwrap();
                let in_both = (i64::from(px) - i64::from(x)).abs() <= 6
                    && (i64::from(px) - i64::from(x + 1)).abs() <= 6
                    && (i64::from(py) - 6).abs() <= 6;
                if in_both {
                    assert!(
                        py > 10,
                        "cell ({px},{py}) flickered stepping from {x} (only cells behind the pillar may change)"
                    );
                }
            }
        }
    }

    #[test]
    fn same_inputs_same_answer() {
        let g = scattered(17, 42, 300);
        for c in 0..17 * 17 {
            assert_eq!(
                view(&g, BlockKind::Opacity, c, 6),
                view(&g, BlockKind::Opacity, c, 6)
            );
        }
    }
}
