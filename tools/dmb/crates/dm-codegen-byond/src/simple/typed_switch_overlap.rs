//! Common interval preflight for finite, ordered ranges.
//! Inputs are only folded numeric values, never semantic authority or emitted order.
pub(super) fn overlaps(exact: &[f32], ranges: &[(f32, f32)]) -> bool {
    let mut points: Vec<_> = exact
        .iter()
        .copied()
        .filter(|value| !value.is_nan())
        .collect();
    points.sort_by(f32::total_cmp);
    let mut intervals = ranges.to_vec();
    intervals.sort_by(|a, b| a.0.total_cmp(&b.0));
    for (index, &(low, high)) in intervals.iter().enumerate() {
        if index > 0 && low <= intervals[index - 1].1 {
            return true;
        }
        let point = points.partition_point(|value| *value < low);
        if points.get(point).is_some_and(|value| *value <= high) {
            return true;
        }
    }
    false
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn ordered_guard_matches_pairwise_guard_without_reordering_producer_inputs() {
        let points = [
            -f32::INFINITY,
            -2.0,
            -0.0,
            0.0,
            1.0,
            2.0,
            f32::INFINITY,
            f32::NAN,
        ];
        let ranges = [
            (-2.0, -1.0),
            (-1.0, 0.0),
            (0.0, 0.0),
            (1.0, 2.0),
            (3.0, 4.0),
        ];
        for first in ranges {
            for second in ranges {
                let intervals = [first, second];
                for point in points {
                    let naive = intervals.iter().enumerate().any(|(index, &(low, high))| {
                        (point >= low && point <= high)
                            || intervals[..index]
                                .iter()
                                .any(|&(a, b)| low <= b && a <= high)
                    });
                    assert_eq!(overlaps(&[point], &intervals), naive);
                }
            }
        }
        assert!(!overlaps(&[], &[]));
    }
}
