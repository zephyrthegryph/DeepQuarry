use crate::panic_safe;
use meowtonin::{ByondError, ByondResult, value::ByondValue};
use rand_distr::{Bernoulli, Distribution};
use rayon::iter::{
    IndexedParallelIterator, IntoParallelRefIterator, IntoParallelRefMutIterator, ParallelIterator,
};

const CELL_THRESHOLD: usize = 5;

/// Upper bound on a single map dimension. The cave generator is meant for small
/// procedural rooms (the live map uses ~8x8); a few thousand cells per side is
/// already far beyond any legitimate caller and keeps the allocation bounded.
const MAX_DIMENSION: usize = 1024;
/// Upper bound on smoothing passes. Each pass is O(cells); the automaton
/// converges well before this, so anything larger is a caller bug.
const MAX_ITERATIONS: usize = 1024;

/// Validate a BYOND number that must be a finite, non-negative integer within
/// `ceiling`, returning it as a `usize`.
fn validate_count(raw: f64, name: &str, ceiling: usize) -> ByondResult<usize> {
    if !raw.is_finite() {
        return Err(ByondError::boxed(VerdigrisMapError(format!(
            "{name} must be a finite number, got {raw}"
        ))));
    }
    if raw < 0.0 {
        return Err(ByondError::boxed(VerdigrisMapError(format!(
            "{name} must be non-negative, got {raw}"
        ))));
    }
    let value = raw as usize;
    if value > ceiling {
        return Err(ByondError::boxed(VerdigrisMapError(format!(
            "{name} must be <= {ceiling}, got {value}"
        ))));
    }
    Ok(value)
}

#[derive(Debug)]
struct VerdigrisMapError(String);

impl std::fmt::Display for VerdigrisMapError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "verdigris map error: {}", self.0)
    }
}

impl std::error::Error for VerdigrisMapError {}

#[byond_fn]
pub fn generate_automata(
    limit_x: ByondValue,
    limit_y: ByondValue,
    iterations: ByondValue,
    initial_wall_cell: ByondValue,
) -> ByondResult<Vec<ByondValue>> {
    panic_safe!({
        // meowtonin's ByondValue::get_number() yields f32; widen to f64 so the
        // validation/ceiling math has integer headroom.
        let limit_x = validate_count(f64::from(limit_x.get_number()?), "limit_x", MAX_DIMENSION)?;
        let limit_y = validate_count(f64::from(limit_y.get_number()?), "limit_y", MAX_DIMENSION)?;
        let iterations = validate_count(
            f64::from(iterations.get_number()?),
            "iterations",
            MAX_ITERATIONS,
        )?;
        let initial_wall_cell = validate_count(
            f64::from(initial_wall_cell.get_number()?),
            "initial_wall_cell",
            100,
        )?;

        let map = smooth_map(
            seed_map(limit_x, limit_y, initial_wall_cell)?,
            limit_x,
            limit_y,
            iterations,
        );

        let byond_list: Vec<ByondValue> = map
            .iter()
            .map(|&b| ByondValue::new_num(if b { 1. } else { 0. }))
            .collect();

        Ok(byond_list)
    })
}

/// Run `iterations` smoothing passes of the cellular automaton over `map`.
///
/// Uses a double buffer: two `Vec`s are allocated once, each pass writes into
/// the back buffer in parallel and the two are swapped, so the whole run costs
/// two allocations regardless of `iterations`.
fn smooth_map(
    mut front: Vec<bool>,
    limit_x: usize,
    limit_y: usize,
    iterations: usize,
) -> Vec<bool> {
    if iterations == 0 || front.is_empty() {
        return front;
    }
    let mut back = vec![false; front.len()];
    for _ in 0..iterations {
        back.par_iter_mut().enumerate().for_each(|(i, out)| {
            *out = wall_count(&front, i, limit_x, limit_y) >= CELL_THRESHOLD;
        });
        std::mem::swap(&mut front, &mut back);
    }
    front
}

/// Count live (wall) cells in the 3x3 neighbourhood centred on index `i`,
/// including the centre. Bounds are checked against the *centre* coordinates so
/// off-grid neighbours are skipped and the linear index can never wrap.
fn wall_count(map: &[bool], i: usize, limit_x: usize, limit_y: usize) -> usize {
    let cx = (i % limit_x) as isize;
    let cy = (i / limit_x) as isize;
    let mut count = 0;
    for x in [-1, 0, 1] {
        for y in [-1, 0, 1] {
            let nx = cx + x;
            let ny = cy + y;
            if nx < 0 || nx >= limit_x as isize || ny < 0 || ny >= limit_y as isize {
                continue;
            }
            let idx = (ny as usize) * limit_x + (nx as usize);
            if map[idx] {
                count += 1;
            }
        }
    }
    count
}

fn seed_map(limit_x: usize, limit_y: usize, percent_chance: usize) -> ByondResult<Vec<bool>> {
    let len = limit_x.checked_mul(limit_y).ok_or_else(|| {
        ByondError::boxed(VerdigrisMapError(format!(
            "map size overflow: {limit_x} * {limit_y}"
        )))
    })?;

    // percent_chance is validated to be <= 100 by the caller, so Bernoulli::new
    // cannot fail; clamp defensively anyway.
    let probability = (percent_chance.min(100) as f64) / 100.0;
    let d = Bernoulli::new(probability).expect("probability in [0.0, 1.0]");

    let mut rng = rand::rng();
    let map = (0..len).map(|_| d.sample(&mut rng)).collect();

    Ok(map)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn seed_map_zero_percent_all_false() {
        let map = seed_map(8, 8, 0).expect("seed should succeed");
        assert_eq!(map.len(), 64);
        assert!(map.iter().all(|&b| !b));
    }

    #[test]
    fn seed_map_full_percent_all_true() {
        let map = seed_map(8, 8, 100).expect("seed should succeed");
        assert_eq!(map.len(), 64);
        assert!(map.iter().all(|&b| b));
    }

    #[test]
    fn seed_map_dimensions_respected() {
        let map = seed_map(13, 7, 50).expect("seed should succeed");
        assert_eq!(map.len(), 91);
    }

    #[test]
    fn seed_map_percent_over_100_clamped_all_true() {
        // percent_chance is clamped to <= 100, so an over-range value behaves
        // like 100% rather than erroring out.
        let map = seed_map(8, 8, 250).expect("seed should succeed");
        assert_eq!(map.len(), 64);
        assert!(map.iter().all(|&b| b));
    }

    #[test]
    fn seed_map_overflow_errors() {
        assert!(seed_map(usize::MAX, 2, 50).is_err());
    }

    #[test]
    fn validate_count_rejects_negative_nan_and_over_ceiling() {
        assert!(validate_count(-1.0, "x", 100).is_err());
        assert!(validate_count(f64::NAN, "x", 100).is_err());
        assert!(validate_count(f64::INFINITY, "x", 100).is_err());
        assert!(validate_count(101.0, "x", 100).is_err());
        assert_eq!(validate_count(64.0, "x", 100).expect("in range"), 64);
    }

    /// 3x3 grid, indices:
    ///   0 1 2
    ///   3 4 5
    ///   6 7 8
    /// All cells live. The neighbour count (centre included) must match the
    /// number of in-grid cells in the 3x3 stencil: 4 at corners, 6 on edges,
    /// 9 at the centre.
    #[test]
    fn wall_count_edges_and_corners() {
        let map = vec![true; 9];
        let (lx, ly) = (3, 3);
        // corners -> 2x2 = 4
        assert_eq!(wall_count(&map, 0, lx, ly), 4);
        assert_eq!(wall_count(&map, 2, lx, ly), 4);
        assert_eq!(wall_count(&map, 6, lx, ly), 4);
        assert_eq!(wall_count(&map, 8, lx, ly), 4);
        // edges -> 2x3 = 6
        assert_eq!(wall_count(&map, 1, lx, ly), 6);
        assert_eq!(wall_count(&map, 3, lx, ly), 6);
        assert_eq!(wall_count(&map, 5, lx, ly), 6);
        assert_eq!(wall_count(&map, 7, lx, ly), 6);
        // centre -> full 3x3 = 9
        assert_eq!(wall_count(&map, 4, lx, ly), 9);
    }

    /// A cell on the left edge must not see the right edge of the row above as a
    /// neighbour. The old index-wrap bug would have leaked across the seam.
    #[test]
    fn wall_count_no_horizontal_wraparound() {
        // 3x3, only the right column is live: indices 2, 5, 8.
        let mut map = vec![false; 9];
        map[2] = true;
        map[5] = true;
        map[8] = true;
        // Cell 3 is on the left edge of the middle row; its real neighbours are
        // {0,1,3,4,6,7}, none of which are live -> count 0 (no wrap to col 2).
        assert_eq!(wall_count(&map, 3, 3, 3), 0);
    }

    #[test]
    fn smooth_map_zero_iterations_is_identity() {
        let seed = vec![true, false, true, false];
        let out = smooth_map(seed.clone(), 2, 2, 0);
        assert_eq!(out, seed);
    }

    #[test]
    fn smooth_map_runs_exactly_n_passes() {
        // An all-live 5x5 interior cell stays live (9 >= threshold); a lone live
        // cell dies after one pass. One iteration must mean exactly one pass.
        let mut map = vec![false; 25];
        map[12] = true; // centre of 5x5
        let out = smooth_map(map, 5, 5, 1);
        assert!(out.iter().all(|&b| !b), "lone cell should die in one pass");
    }
}
