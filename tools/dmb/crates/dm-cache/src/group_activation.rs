//! Complete membership activates a single atomic superseding transaction.
use super::group_manifest::GroupManifest;
use std::collections::{BTreeMap, BTreeSet, VecDeque};
#[derive(Default)]
pub(super) struct GroupActivation {
    pub supersedes_segments: BTreeSet<u128>,
    pub supersedes_groups: BTreeSet<u128>,
    pub cyclic_groups: BTreeSet<u128>,
}
pub(super) fn activate<'a>(
    groups: impl IntoIterator<Item = &'a GroupManifest>,
    healthy_segments: &BTreeSet<u128>,
) -> GroupActivation {
    let eligible = groups
        .into_iter()
        .filter(|group| group.complete(healthy_segments))
        .map(|group| (group.id, group))
        .collect::<BTreeMap<_, _>>();
    // Kahn traversal has bounded stack use. Malformed cycles and their dependent
    // older nodes remain inactive rather than inferring a supersedes order.
    let mut incoming = eligible
        .keys()
        .map(|id| (*id, 0usize))
        .collect::<BTreeMap<_, _>>();
    for group in eligible.values() {
        for target in &group.supersedes_groups {
            if let Some(count) = incoming.get_mut(target) {
                *count += 1;
            }
        }
    }
    let mut pending = incoming
        .iter()
        .filter_map(|(id, count)| (*count == 0).then_some(*id))
        .collect::<VecDeque<_>>();
    let mut visited = BTreeSet::new();
    while let Some(id) = pending.pop_front() {
        visited.insert(id);
        for target in &eligible[&id].supersedes_groups {
            if let Some(count) = incoming.get_mut(target) {
                *count -= 1;
                if *count == 0 {
                    pending.push_back(*target);
                }
            }
        }
    }
    let mut result = GroupActivation::default();
    result
        .cyclic_groups
        .extend(eligible.keys().filter(|id| !visited.contains(id)).copied());
    for id in &visited {
        result
            .supersedes_groups
            .extend(eligible[id].supersedes_groups.iter().copied());
    }
    for id in visited {
        if !result.supersedes_groups.contains(&id) {
            result
                .supersedes_segments
                .extend(eligible[&id].supersedes_segments.iter().copied());
        }
    }
    result
}

#[cfg(test)]
mod tests {
    use super::*;
    fn group(id: u128, members: &[u128], segments: &[u128], groups: &[u128]) -> GroupManifest {
        GroupManifest {
            id,
            members: members.to_vec(),
            supersedes_segments: segments.to_vec(),
            supersedes_groups: groups.to_vec(),
        }
    }
    #[test]
    fn partial_publication_and_rejected_member_never_supersede_sources() {
        let groups = [group(100, &[10, 11], &[1, 2], &[])];
        assert!(activate(&groups, &[1, 2, 10].into_iter().collect())
            .supersedes_segments
            .is_empty());
        assert_eq!(
            activate(&groups, &[1, 2, 10, 11].into_iter().collect()).supersedes_segments,
            [1, 2].into_iter().collect()
        );
        // Rejection removes one leaf from the healthy set, reactivating original
        // physical leaves if they still exist; it cannot recreate deleted files.
        assert!(activate(&groups, &[1, 2, 11].into_iter().collect())
            .supersedes_segments
            .is_empty());
    }
    #[test]
    fn newer_complete_group_retires_old_tombstone_and_cycles_fail_closed() {
        let old = group(100, &[10], &[1], &[]);
        let new = group(200, &[20], &[10], &[100]);
        let activation = activate(&[old, new], &[1, 10, 20].into_iter().collect());
        assert_eq!(activation.supersedes_segments, [10].into_iter().collect());
        assert_eq!(activation.supersedes_groups, [100].into_iter().collect());
        let cycle = [group(1, &[10], &[20], &[2]), group(2, &[20], &[10], &[1])];
        let activation = activate(&cycle, &[10, 20].into_iter().collect());
        assert!(activation.supersedes_segments.is_empty());
        assert_eq!(activation.cyclic_groups, [1, 2].into_iter().collect());
    }
}
