//! Pure greatest-fixpoint computation for native value-proof summaries.
//!
//! This is not a second cache or semantic model. Issued body facts must first
//! supply ALL equations (returns, writes, arguments, dispatch and external-call
//! barriers). The query host can schedule each returned SCC as one query, never
//! recursively block on another member of that SCC. An incomplete equation set
//! is an error, not evidence that an unknown call returns a scalar.
use std::collections::{BTreeMap, BTreeSet, VecDeque};

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct Equation<K> {
    pub admissible: bool,
    /// Every prerequisite must remain a value proof. A return with multiple
    /// possible callees requires every dynamically reachable definition.
    pub requires: BTreeSet<K>,
}

#[derive(Debug, Eq, PartialEq)]
pub struct Missing<K> {
    pub owner: K,
    pub dependency: K,
}

#[derive(Debug, Eq, PartialEq)]
pub struct Solution<K> {
    pub values: BTreeMap<K, bool>,
    /// Members and groups are deterministic. Recompute membership from current
    /// contributions after an edit/deletion; an old SCC is not an authority.
    pub components: Vec<Vec<K>>,
}

pub fn solve<K: Clone + Ord>(
    equations: &BTreeMap<K, Equation<K>>,
) -> Result<Solution<K>, Missing<K>> {
    let mut dependants: BTreeMap<K, Vec<K>> = equations
        .keys()
        .cloned()
        .map(|key| (key, Vec::new()))
        .collect();
    for (owner, equation) in equations {
        for dependency in &equation.requires {
            let incoming = dependants.get_mut(dependency).ok_or_else(|| Missing {
                owner: owner.clone(),
                dependency: dependency.clone(),
            })?;
            incoming.push(owner.clone());
        }
    }

    // Kosaraju with explicit stacks: generated code can have very deep chains;
    // neither Rust recursion nor cyclic dm-query fetches are required here.
    let mut seen = BTreeSet::new();
    let mut finish = Vec::new();
    for root in equations.keys() {
        if seen.contains(root) {
            continue;
        }
        let mut stack = vec![(root.clone(), false)];
        while let Some((node, visited)) = stack.pop() {
            if visited {
                finish.push(node);
                continue;
            }
            if !seen.insert(node.clone()) {
                continue;
            }
            stack.push((node.clone(), true));
            for next in equations[&node].requires.iter().rev() {
                if !seen.contains(next) {
                    stack.push((next.clone(), false));
                }
            }
        }
    }
    seen.clear();
    let mut components = Vec::new();
    for root in finish.into_iter().rev() {
        if !seen.insert(root.clone()) {
            continue;
        }
        let mut stack = vec![root];
        let mut group = Vec::new();
        while let Some(node) = stack.pop() {
            for next in dependants[&node].iter().rev() {
                if seen.insert(next.clone()) {
                    stack.push(next.clone());
                }
            }
            group.push(node);
        }
        group.sort();
        components.push(group);
    }
    components.sort();

    // Greatest, not least, fixpoint: a mutually recursive group with no
    // non-value exit stays proven. Each negative edge is propagated once.
    let mut values: BTreeMap<K, bool> = equations
        .iter()
        .map(|(key, equation)| (key.clone(), equation.admissible))
        .collect();
    let mut rejected: VecDeque<K> = values
        .iter()
        .filter(|(_, value)| !**value)
        .map(|(key, _)| key.clone())
        .collect();
    while let Some(node) = rejected.pop_front() {
        for dependant in &dependants[&node] {
            if values[dependant] {
                values.insert(dependant.clone(), false);
                rejected.push_back(dependant.clone());
            }
        }
    }
    Ok(Solution { values, components })
}

#[cfg(test)]
mod tests {
    use super::*;
    fn eq(admissible: bool, requires: &[u32]) -> Equation<u32> {
        Equation {
            admissible,
            requires: requires.iter().copied().collect(),
        }
    }
    #[test]
    fn recursive_groups_keep_the_reference_greatest_fixpoint() {
        let equations = BTreeMap::from([
            (0, eq(true, &[1])),
            (1, eq(true, &[0])),
            (2, eq(false, &[])),
            (3, eq(true, &[2])),
        ]);
        let solution = solve(&equations).unwrap();
        assert_eq!(
            solution.values,
            BTreeMap::from([(0, true), (1, true), (2, false), (3, false)])
        );
        assert_eq!(solution.components, vec![vec![0, 1], vec![2], vec![3]]);
    }
    #[test]
    fn sibling_edges_do_not_manufacture_a_recursive_group() {
        let equations = BTreeMap::from([
            (0, eq(true, &[1, 2])),
            (1, eq(true, &[2])),
            (2, eq(true, &[])),
        ]);
        assert_eq!(
            solve(&equations).unwrap().components,
            vec![vec![0], vec![1], vec![2]]
        );
    }
    #[test]
    fn editing_a_recursive_exit_can_shrink_and_then_restore_summaries() {
        let mut equations = BTreeMap::from([(0, eq(true, &[1])), (1, eq(true, &[0]))]);
        assert!(solve(&equations)
            .unwrap()
            .values
            .values()
            .all(|value| *value));
        equations.get_mut(&1).unwrap().admissible = false;
        assert!(solve(&equations)
            .unwrap()
            .values
            .values()
            .all(|value| !*value));
        equations.insert(1, eq(true, &[]));
        let repaired = solve(&equations).unwrap();
        assert!(repaired.values.values().all(|value| *value));
        assert_eq!(repaired.components, vec![vec![0], vec![1]]);
        equations.remove(&1);
        assert_eq!(
            solve(&equations).unwrap_err(),
            Missing {
                owner: 0,
                dependency: 1
            }
        );
    }
    #[test]
    fn long_generated_chains_do_not_use_the_native_stack() {
        let mut equations = BTreeMap::new();
        equations.insert(0, eq(false, &[]));
        for key in 1..20_000 {
            equations.insert(key, eq(true, &[key - 1]));
        }
        let solution = solve(&equations).unwrap();
        assert_eq!(solution.components.len(), 20_000);
        assert!(solution.values.values().all(|value| !*value));
    }
}
