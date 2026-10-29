//! Reference checker report traversal over the issued compiler roster.
//!
//! SpacemanDMM 0290db5c752fa292f9824521515b603a2afd11dc (GPL-3.0)
//! dreamchecker::run_inner walks lexical child paths in BTreeMap preorder,
//! then first-name proc groups and each group's normalized value order.
//! This does not change runtime dispatch, inheritance, or compiler body order.

use dm_tree::{
    frontend::{BodyOccurrence, ColdFrontend},
    DefinitionMode, MemberKind, SemanticTree, Target,
};
use std::collections::BTreeMap;

/// Return borrowed bodies with their original archive ordinals. Authenticate
/// issuance before consulting the publicly visible compatibility fields.
pub fn bodies(frontend: &ColdFrontend) -> Result<Vec<(usize, &BodyOccurrence)>, String> {
    frontend.callable_roster()?;
    order(&frontend.snapshot.tree, &frontend.bodies)
}

/// Same lexical checker order projected over the ORIGINAL archive roster.
pub fn archived_bodies(
    archive: &dm_tree::frontend::BodyArchive,
) -> Result<Vec<(usize, &BodyOccurrence)>, String> {
    order(archive.tree(), archive.occurrences())
}
fn components(path: &str) -> Vec<&str> {
    path.split('/').filter(|part| !part.is_empty()).collect()
}

fn order<'a>(
    tree: &'a SemanticTree,
    bodies: &'a [BodyOccurrence],
) -> Result<Vec<(usize, &'a BodyOccurrence)>, String> {
    let mut first_name = BTreeMap::new();
    // Include bodyless declarations: an earlier declaration can establish a
    // group's position even when its first executable override comes later.
    for (index, target) in tree.declarations().iter().enumerate() {
        if let Target::Member(id) = target {
            let member = tree
                .member(*id)
                .ok_or("checker declaration member absent")?;
            if matches!(member.kind, MemberKind::Proc | MemberKind::Verb) {
                first_name
                    .entry((member.owner, member.name))
                    .or_insert(index);
            }
        }
    }
    let mut ordered = Vec::with_capacity(bodies.len());
    for (ordinal, body) in bodies.iter().enumerate() {
        let member = tree
            .member(body.member)
            .ok_or("checker body member absent")?;
        let owner = tree
            .type_node(member.owner)
            .ok_or("checker body owner absent")?;
        let path = tree
            .symbols()
            .text(owner.path)
            .ok_or("checker owner path absent")?;
        let first = first_name
            .get(&(member.owner, member.name))
            .copied()
            .ok_or("checker callable encounter absent")?;
        let occurrence = tree
            .member_occurrence(body.member)
            .ok_or("checker callable occurrence absent")?;
        ordered.push((
            (
                components(path),
                first,
                member.definition != DefinitionMode::Declare,
                occurrence,
                ordinal,
            ),
            body,
        ));
    }
    ordered.sort_by(|(left, _), (right, _)| left.cmp(right));
    Ok(ordered
        .into_iter()
        .map(|(key, body)| (key.4, body))
        .collect())
}

#[cfg(test)]
#[path = "checker_order_tests.rs"]
mod tests;
