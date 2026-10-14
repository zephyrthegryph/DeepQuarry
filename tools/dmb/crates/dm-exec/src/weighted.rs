//! Ordered disjoint job partitions shared by bulk compiler stages.
use std::ops::Range;

/// Split `len` items into at most `tasks` nonempty contiguous ranges, balancing
/// deterministic item weights. Zero tasks becomes one; zero weights become one.
/// The callback is a repeatable size lookup, evaluated at most twice per item.
/// u128 accumulation accommodates every usize weight on supported platforms.
pub fn weighted_ranges(
    len: usize,
    tasks: usize,
    weight: impl Fn(usize) -> usize,
) -> Vec<Range<usize>> {
    if len == 0 {
        return Vec::new();
    }
    let tasks = tasks.max(1).min(len);
    let weight = |index| weight(index).max(1) as u128;
    let mut remaining_weight: u128 = (0..len).map(&weight).sum();
    let mut ranges = Vec::with_capacity(tasks);
    let mut start = 0;
    for task in 0..tasks {
        let left = tasks - task;
        if left == 1 {
            ranges.push(start..len);
            break;
        }
        let target = remaining_weight.div_ceil(left as u128);
        let latest = len - (left - 1);
        let mut end = start;
        let mut assigned = 0;
        while end < latest && (end == start || assigned < target) {
            assigned += weight(end);
            end += 1;
        }
        ranges.push(start..end);
        remaining_weight -= assigned;
        start = end;
    }
    ranges
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn partitions_cover_once_for_empty_zero_and_excess_tasks() {
        for len in [0, 1, 2, 17, 259] {
            for tasks in [0, 1, 2, 8, usize::MAX] {
                let ranges = weighted_ranges(len, tasks, |_| 0);
                assert_eq!(ranges.len(), tasks.max(1).min(len));
                assert!(ranges.iter().all(|range| !range.is_empty()));
                assert_eq!(
                    ranges.into_iter().flatten().collect::<Vec<_>>(),
                    (0..len).collect::<Vec<_>>()
                );
            }
        }
    }
    #[test]
    fn maximal_weights_do_not_overflow_and_uniform_work_is_balanced() {
        assert_eq!(
            weighted_ranges(8, 4, |_| usize::MAX),
            [0..2, 2..4, 4..6, 6..8]
        );
        assert_eq!(weighted_ranges(8, 4, |_| 0), [0..2, 2..4, 4..6, 6..8]);
        assert_eq!(
            weighted_ranges(4, 2, |index| [9, 1, 1, 1][index]),
            [0..1, 1..4]
        );
    }
}
