//! Method membership is an issued encounter roster, not procedure-table sorting.
use super::*;

pub(super) fn procedure_membership(
    projection: &ClassProjection,
    tables: &dm_link::LinkTables,
) -> Result<BTreeMap<(SymbolId, bool), Vec<u32>>, ProjectionError> {
    let mut bindings = BTreeMap::new();
    // Preserve the old source-chain binding validation and first-error order.
    for chain in projection.chains.iter() {
        for &key in chain.entries.iter() {
            let id = tables.index(key).ok_or_else(|| {
                ProjectionError::Unsupported("missing procedure chain binding".into())
            })?;
            if bindings.insert(key, id).is_some() {
                return Err(ProjectionError::Unsupported(
                    "duplicate procedure membership".into(),
                ));
            }
        }
    }
    let mut lists: BTreeMap<(SymbolId, bool), Vec<u32>> = BTreeMap::new();
    for &key in projection.procedure_membership.iter() {
        let id = bindings.remove(&key).ok_or_else(|| {
            ProjectionError::Unsupported("unissued or duplicate procedure membership order".into())
        })?;
        let (owner, verb) = match key {
            Key::Proc { owner, .. } => (owner, false),
            Key::Verb { owner, .. } => (owner, true),
            _ => {
                return Err(ProjectionError::Unsupported(
                    "nonmethod in procedure membership order".into(),
                ))
            }
        };
        if owner != SymbolId::of("/") {
            lists.entry((owner, verb)).or_default().push(id);
        }
    }
    if !bindings.is_empty() {
        return Err(ProjectionError::Unsupported(
            "incomplete procedure membership order".into(),
        ));
    }
    Ok(lists)
}

#[cfg(test)]
#[path = "methods_tests.rs"]
mod tests;
