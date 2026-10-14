//! Stable numeric emission order without sorting the full declaration roster.
use crate::OccurrenceId;

pub(super) fn ordered_occurrences(regions: &[usize], ranks: &[usize]) -> Vec<OccurrenceId> {
    if regions.is_empty() {
        return Vec::new();
    }
    let max_rank = regions.iter().map(|region| ranks[*region]).max().unwrap();
    // Sparse ranks use the existing comparison order rather than allocating a
    // large mostly empty bucket array. A bucket is never output authority.
    let buckets = max_rank.saturating_add(1);
    if buckets > regions.len().saturating_mul(2) {
        let mut result: Vec<_> = (0..regions.len())
            .map(|index| OccurrenceId(index as u32))
            .collect();
        result.sort_by_key(|id| (ranks[regions[id.0 as usize]], id.0));
        return result;
    }
    let mut offsets = vec![0usize; buckets];
    for region in regions {
        offsets[ranks[*region]] += 1;
    }
    let mut prefix = 0;
    for offset in &mut offsets {
        let count = *offset;
        *offset = prefix;
        prefix += count;
    }
    let mut result = vec![OccurrenceId(0); regions.len()];
    // Authored occurrence IDs arrive in ascending order, preserving the second
    // component of the old (emission rank, occurrence ID) comparison exactly.
    for (index, region) in regions.iter().enumerate() {
        let offset = &mut offsets[ranks[*region]];
        result[*offset] = OccurrenceId(index as u32);
        *offset += 1;
    }
    result
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn dense_sparse_and_equal_ranks_match_canonical_comparison_order() {
        for ranks in [vec![0, 1, 2], vec![2, 0, 1], vec![0, 0, 0], vec![91, 2, 7]] {
            for regions in [vec![], vec![0], vec![2, 0, 1, 0, 2, 1], vec![2; 17]] {
                let mut expected: Vec<_> = (0..regions.len())
                    .map(|index| OccurrenceId(index as u32))
                    .collect();
                expected.sort_by_key(|id| (ranks[regions[id.0 as usize]], id.0));
                assert_eq!(ordered_occurrences(&regions, &ranks), expected);
            }
        }
    }
}
