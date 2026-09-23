//! EMP falloff (`simulation.md` §8): severity bands by distance from the
//! epicentre, measured along rays from the centre (Chebyshev steps, the same
//! as DM's `get_dist`). DM's `emp_act` ladder decides what each band does.

use super::Ray;
use crate::grid::GridDims;

/// The clipped square an EMP covers and a severity per cell in it, row by
/// row (x fastest), which is the order of DM's `block()`.
///
/// A severity is `EMP_HEAVY` (1) .. `EMP_HARMLESS` (4). A value ending in
/// `.5` is a coin flip between the two neighbouring severities (the ring
/// exactly at a band's radius).
#[derive(Clone, Debug, PartialEq)]
pub struct EmpFalloff {
    /// Zero-based inclusive bounds on the epicentre's z-level.
    pub min: (u32, u32),
    pub max: (u32, u32),
    pub severity: Vec<f32>,
}

/// Severity at `distance` for band radii `ranges` (each at least the one
/// before; DM normalises them). Mirrors the ladder `empulse()` used.
#[must_use]
pub fn severity_at(distance: u32, ranges: [u32; 4]) -> Option<f32> {
    let [first, second, third, fourth] = ranges;
    Some(if distance < first {
        1.0
    } else if distance == first {
        1.5
    } else if distance < second {
        2.0
    } else if distance == second {
        2.5
    } else if distance < third {
        3.0
    } else if distance == third {
        2.5
    } else if distance <= fourth {
        4.0
    } else {
        return None;
    })
}

/// Falloff around the zero-based `centre`; `None` if it is off the grid.
#[must_use]
pub fn falloff(dims: GridDims, centre: (u32, u32, u32), ranges: [u32; 4]) -> Option<EmpFalloff> {
    let from = dims.index(centre.0, centre.1, centre.2)?;
    let reach = ranges[3];
    let min = (
        centre.0.saturating_sub(reach),
        centre.1.saturating_sub(reach),
    );
    let max = (
        centre.0.saturating_add(reach).min(dims.max_x() - 1),
        centre.1.saturating_add(reach).min(dims.max_y() - 1),
    );
    let mut severity = Vec::with_capacity(((max.0 - min.0 + 1) * (max.1 - min.1 + 1)) as usize);
    for y in min.1..=max.1 {
        for x in min.0..=max.0 {
            let to = dims.index(x, y, centre.2)?;
            let steps = Ray::new(dims, from, to).map_or(u32::MAX, |r| r.steps());
            severity.push(severity_at(steps, ranges).unwrap_or(0.0));
        }
    }
    Some(EmpFalloff { min, max, severity })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rings_by_distance() {
        let dims = GridDims::new(32, 32, 1).unwrap();
        let f = falloff(dims, (10, 10, 0), [1, 2, 3, 4]).unwrap();
        assert_eq!((f.min, f.max), ((6, 6), (14, 14)));
        let sev = |x: u32, y: u32| f.severity[((y - 6) * 9 + (x - 6)) as usize];
        assert_eq!(sev(10, 10), 1.0);
        assert_eq!(sev(11, 11), 1.5);
        assert_eq!(sev(12, 10), 2.5);
        assert_eq!(sev(13, 7), 2.5);
        assert_eq!(sev(14, 14), 4.0);
    }

    #[test]
    fn clipped_at_map_edges() {
        let dims = GridDims::new(8, 8, 1).unwrap();
        let f = falloff(dims, (0, 7, 0), [1, 2, 3, 4]).unwrap();
        assert_eq!((f.min, f.max), ((0, 3), (4, 7)));
        assert_eq!(f.severity.len(), 25);
        assert!(f.severity.iter().all(|&s| s >= 1.0));
    }
}
