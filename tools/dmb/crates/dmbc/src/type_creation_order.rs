//! Bounded wire creation order from the shared pre-normalization grammar ledger.
//! This follows captured declaration allocation and lexical-parent construction;
//! it does not certify BYOND's runtime `typesof()` enumeration rule.
use dm_ir::{SymbolId, SymbolTable};
use dm_link::{Key, LinkInventory};
use dm_tree::allocation_ledger::{AllocationKind, AllocationLedger};
use std::collections::BTreeSet;
use std::sync::Arc;
#[path = "type_creation_order/retained.rs"]
pub(crate) mod retained;
pub use retained::{collect_retained, AllocationArtifacts, AllocationRoster};

pub fn collect(
    ledger: &AllocationLedger,
    expanded_source: &str,
    symbols: &SymbolTable,
    retained: &LinkInventory,
) -> Result<Vec<SymbolId>, String> {
    collect_recorded(ledger, expanded_source, symbols, retained, None)
}
fn collect_recorded(
    ledger: &AllocationLedger,
    expanded_source: &str,
    symbols: &SymbolTable,
    retained: &LinkInventory,
    mut reads: Option<&mut Vec<dm_session::Observation<SymbolId, Option<String>, ()>>>,
) -> Result<Vec<SymbolId>, String> {
    let mut seen: BTreeSet<_> = retained
        .fixed
        .iter()
        .filter_map(|(key, _)| match key {
            Key::Type(path) => Some(*path),
            _ => None,
        })
        .collect();
    seen.insert(SymbolId::of("/"));
    seen.insert(SymbolId::of("/world"));
    let mut order = Vec::new();
    let mut last = None;
    for event in ledger.events.iter() {
        if last.is_some_and(|previous| previous >= event.encounter_order) {
            return Err("allocation ledger is not in unique encounter order".into());
        }
        last = Some(event.encounter_order);
        let owner = match event.kind {
            AllocationKind::Type { path, .. } => path,
            AllocationKind::Namespace { owner, .. }
            | AllocationKind::Field { owner, .. }
            | AllocationKind::Procedure { owner, .. }
            | AllocationKind::Parent { owner, .. } => owner,
        };
        allocate(owner, symbols, &mut seen, &mut order, reads.as_deref_mut())?;
        if let AllocationKind::Parent { value, .. } = event.kind {
            let source = expanded_source
                .get(value.start..value.end)
                .ok_or("parent allocation source span invalid")?;
            let parsed = dm_syntax::parse_expression(source);
            if !parsed.diagnostics.is_empty() {
                return Err(format!(
                    "parent allocation expression: {:?}",
                    parsed.diagnostics
                ));
            }
            let expression = parsed.expr.ok_or("parent allocation expression absent")?;
            match expression.kind {
                dm_syntax::ExprKind::TypePath(path) => {
                    let symbol = SymbolId::of(&path);
                    observe(symbol, symbols, reads.as_deref_mut());
                    if symbols.text(symbol) != Some(path.as_str()) {
                        return Err(
                            "parent path not captured in collision-checked symbol table".into()
                        );
                    }
                    allocate(symbol, symbols, &mut seen, &mut order, reads.as_deref_mut())?;
                }
                dm_syntax::ExprKind::Literal(value) if value == "null" => (),
                _ => {
                    return Err(
                        "parent allocation expression lacks certified ordinary type meaning".into(),
                    )
                }
            }
        }
    }
    Ok(order)
}
fn allocate(
    path: SymbolId,
    symbols: &SymbolTable,
    seen: &mut BTreeSet<SymbolId>,
    order: &mut Vec<SymbolId>,
    mut reads: Option<&mut Vec<dm_session::Observation<SymbolId, Option<String>, ()>>>,
) -> Result<(), String> {
    if seen.contains(&path) {
        return Ok(());
    }
    observe(path, symbols, reads.as_deref_mut());
    let text = symbols
        .text(path)
        .ok_or("allocation type spelling missing")?;
    if !text.starts_with('/') || text.ends_with('/') {
        return Err("allocation path is not an absolute class path".into());
    }
    let slash = text.rfind('/').ok_or("allocation lexical parent absent")?;
    let parent = if slash == 0 { "/" } else { &text[..slash] };
    let parent_symbol = SymbolId::of(parent);
    if !seen.contains(&parent_symbol) {
        observe(parent_symbol, symbols, reads.as_deref_mut());
    }
    if !seen.contains(&parent_symbol) && symbols.text(parent_symbol) != Some(parent) {
        return Err("allocation lexical parent is not a captured declaration".into());
    }
    allocate(parent_symbol, symbols, seen, order, reads)?;
    if seen.insert(path) {
        order.push(path);
    }
    Ok(())
}
fn observe(
    path: SymbolId,
    symbols: &SymbolTable,
    reads: Option<&mut Vec<dm_session::Observation<SymbolId, Option<String>, ()>>>,
) {
    if let Some(reads) = reads {
        reads.push(dm_session::Observation {
            domain: (),
            query: path,
            answer: symbols.text(path).map(str::to_owned),
        });
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    fn source_order(source: &str) -> Vec<SymbolId> {
        let parsed = dm_syntax::parse(source);
        assert!(parsed.diagnostics.is_empty());
        let mut symbols = SymbolTable::default();
        let ledger = dm_tree::allocation_ledger::capture(&parsed.items, "/", &mut symbols).unwrap();
        let mut inventory = LinkInventory::default();
        inventory.fixed.push((Key::Type(SymbolId::of("/datum")), 2));
        collect(&ledger, source, &symbols, &inventory).unwrap()
    }
    #[test]
    fn creation_order_follows_encounter_and_lexical_parents_not_hash_sort() {
        let order =
            source_order("/datum/z/child\n/datum/a\n/datum/z/child/proc/p()\n    return 1\n");
        assert_eq!(
            order,
            [
                SymbolId::of("/datum/z"),
                SymbolId::of("/datum/z/child"),
                SymbolId::of("/datum/a")
            ]
        );
    }
    #[test]
    fn explicit_forward_parent_allocates_when_its_authored_assignment_is_encountered() {
        let order = source_order("/datum/child\n    parent_type = /datum/later\n/datum/later\n");
        assert_eq!(
            order,
            [SymbolId::of("/datum/child"), SymbolId::of("/datum/later")]
        );
    }
}
