//! Recipe placement selected only after the ordinary assembler succeeds.
//! The assembler remains the authority for descriptor collisions and unions.
use std::collections::BTreeMap;

/// Keep the first recipe for each reference, as the ordinary assembler does.
/// A missing recipe on that first encounter declines the handoff; a later
/// duplicate cannot substitute its root or debug ordinal.
pub(super) fn first_placements<K: Ord, T>(
    fragments: impl IntoIterator<Item = (usize, Vec<(K, Option<T>)>)>,
    final_references: impl IntoIterator<Item = K>,
) -> Option<Vec<(K, usize, T)>> {
    let mut selected = BTreeMap::new();
    for (root, recipes) in fragments {
        for (reference, recipe) in recipes {
            selected.entry(reference).or_insert((root, recipe));
        }
    }
    let expected: Vec<_> = final_references.into_iter().collect();
    if selected.keys().ne(expected.iter()) {
        return None;
    }
    selected
        .into_iter()
        .map(|(reference, (root, recipe))| Some((reference, root, recipe?)))
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn duplicate_uses_first_root_even_when_reference_order_differs() {
        assert_eq!(
            first_placements(
                [
                    (0, vec![(7, Some("first")), (2, Some("second"))]),
                    (1, vec![(7, Some("duplicate")), (9, Some("last"))])
                ],
                [2, 7, 9]
            ),
            Some(vec![(2, 0, "second"), (7, 0, "first"), (9, 1, "last")])
        );
    }
    #[test]
    fn missing_first_recipe_or_final_roster_mismatch_declines() {
        assert!(
            first_placements([(0, vec![(7, None)]), (1, vec![(7, Some("later"))])], [7]).is_none()
        );
        assert!(first_placements([(0, vec![(7, Some("first"))])], [8]).is_none());
    }
}
