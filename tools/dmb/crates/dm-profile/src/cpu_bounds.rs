//! Existing per-stage and process-union uncertainty aggregation.
use super::clock;

pub(super) fn sum_bounds(values: impl Iterator<Item = clock::CpuBounds>) -> clock::CpuBounds {
    values.fold(
        clock::CpuBounds {
            lower: 0.0,
            upper: 0.0,
        },
        clock::CpuBounds::add,
    )
}
// Union only observations from the same thread. Overlapping spans share clock
// uncertainty; charging it once per nested segment would multiply one error.
pub(super) fn union_interval_bounds(
    mut intervals: Vec<clock::CpuInterval>,
) -> Option<clock::CpuBounds> {
    intervals.sort_unstable_by_key(|i| (i.raw_begin, i.raw_end));
    let mut merged: Vec<clock::CpuInterval> = Vec::new();
    for interval in intervals {
        if let Some(last) = merged.last_mut() {
            if interval.raw_begin <= last.raw_end {
                // Paired coarse endpoints must remain monotonic. Equal raw
                // boundaries must have identical paired observations.
                if interval.coarse_begin < last.coarse_begin
                    || interval.coarse_begin > last.coarse_end
                    || (interval.raw_begin == last.raw_begin
                        && interval.coarse_begin != last.coarse_begin)
                    || (interval.raw_begin == last.raw_end
                        && interval.coarse_begin != last.coarse_end)
                {
                    return None;
                }
                if interval.raw_end > last.raw_end {
                    if interval.coarse_end < last.coarse_end {
                        return None;
                    }
                    last.raw_end = interval.raw_end;
                    last.coarse_end = interval.coarse_end;
                } else if interval.coarse_end > last.coarse_end
                    || (interval.raw_end == last.raw_end && interval.coarse_end != last.coarse_end)
                {
                    return None;
                }
                continue;
            }
        }
        merged.push(interval);
    }
    Some(sum_bounds(
        merged.into_iter().map(|i| i.bounds(cfg!(windows))),
    ))
}
pub(super) fn interval_bounds(intervals: &[clock::CpuInterval]) -> clock::CpuBounds {
    // Merge only exactly contiguous observations, never fill an unobserved gap.
    let mut merged: Vec<clock::CpuInterval> = Vec::new();
    for interval in intervals {
        if let Some(last) = merged.last_mut() {
            if last.raw_end == interval.raw_begin && last.coarse_end == interval.coarse_begin {
                last.raw_end = interval.raw_end;
                last.coarse_end = interval.coarse_end;
                continue;
            }
        }
        merged.push(*interval);
    }
    merged
        .into_iter()
        .map(|interval| interval.bounds(cfg!(windows)))
        .fold(
            clock::CpuBounds {
                lower: 0.0,
                upper: 0.0,
            },
            clock::CpuBounds::add,
        )
}
