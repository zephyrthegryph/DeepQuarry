//! Source-neutral allocation proof issued by the ordinary checked allocator.
use super::*;
use dm_session::{ObservationHost, ObservedArtifactStore};
/// This owner certifies ordered allocation only, never current source positions.
#[derive(PartialEq, Eq)]
pub struct AllocationRoster {
    order: Arc<[SymbolId]>,
}
impl AllocationRoster {
    pub fn order(&self) -> &[SymbolId] {
        &self.order
    }
    pub(crate) fn shared_order(&self) -> &Arc<[SymbolId]> {
        &self.order
    }
}
pub struct AllocationArtifacts {
    values: ObservedArtifactStore<AllocationRoster, SymbolId, Option<String>, ()>,
}
impl Default for AllocationArtifacts {
    fn default() -> Self {
        Self {
            values: ObservedArtifactStore::current_revision(),
        }
    }
}
struct Spellings<'a>(&'a SymbolTable);
impl ObservationHost<SymbolId, Option<String>, ()> for Spellings<'_> {
    fn answer(&self, path: &SymbolId) -> Option<String> {
        self.0.text(*path).map(str::to_owned)
    }
}
impl AllocationArtifacts {
    pub fn clear(&self) {
        self.values.retain_current_keys(std::iter::empty::<&[u8]>());
    }
    pub(crate) fn visit_storage(
        &self,
        visitor: impl FnMut(
            dm_session::ObservedArtifactStorageView<
                '_,
                AllocationRoster,
                SymbolId,
                Option<String>,
                (),
            >,
        ),
    ) {
        self.values.visit_storage(visitor);
    }
}
fn key(ledger: &AllocationLedger, source: &str, inventory: &LinkInventory) -> Option<Vec<u8>> {
    let mut key = b"dmbc-source-allocation-roster-v1\0".to_vec();
    let fixed: Vec<_> = inventory
        .fixed
        .iter()
        .filter_map(|(key, _)| match key {
            Key::Type(path) => Some(*path),
            _ => None,
        })
        .collect();
    key.extend_from_slice(&(fixed.len() as u64).to_le_bytes());
    for path in fixed {
        key.extend_from_slice(&path.bits().to_le_bytes());
    }
    key.extend_from_slice(&(ledger.events.len() as u64).to_le_bytes());
    let mut last = None;
    for event in ledger.events.iter() {
        if last.is_some_and(|previous| previous >= event.encounter_order) {
            return None;
        }
        last = Some(event.encounter_order);
        let owner = match event.kind {
            AllocationKind::Type { path, .. } => path,
            AllocationKind::Namespace { owner, .. }
            | AllocationKind::Field { owner, .. }
            | AllocationKind::Procedure { owner, .. }
            | AllocationKind::Parent { owner, .. } => owner,
        };
        key.extend_from_slice(&owner.bits().to_le_bytes());
        if let AllocationKind::Parent { value, .. } = event.kind {
            let text = source.get(value.start..value.end)?;
            key.push(1);
            key.extend_from_slice(&(text.len() as u64).to_le_bytes());
            key.extend_from_slice(text.as_bytes());
        } else {
            key.push(0);
        }
    }
    Some(key)
}
pub fn collect_retained(
    ledger: &AllocationLedger,
    expanded_source: &str,
    symbols: &SymbolTable,
    inventory: &LinkInventory,
    artifacts: Option<&AllocationArtifacts>,
) -> Result<Arc<AllocationRoster>, String> {
    let Some(artifacts) = artifacts else {
        return super::collect(ledger, expanded_source, symbols, inventory).map(|order| {
            Arc::new(AllocationRoster {
                order: order.into(),
            })
        });
    };
    let Some(key) = key(ledger, expanded_source, inventory) else {
        return super::collect(ledger, expanded_source, symbols, inventory).map(|order| {
            Arc::new(AllocationRoster {
                order: order.into(),
            })
        });
    };
    artifacts
        .values
        .retain_current_keys(std::iter::once(key.as_slice()));
    if let Some(value) = artifacts.values.lookup(&key, &Spellings(symbols)) {
        return Ok(value);
    }
    let mut reads = Vec::new();
    // Only this ordinary producer issues a receipt. Preliminary key extraction
    // never emits errors, so invalid input preserves original diagnostic order.
    let order = super::collect_recorded(
        ledger,
        expanded_source,
        symbols,
        inventory,
        Some(&mut reads),
    )?;
    Ok(artifacts
        .values
        .insert_with_owned(key.into(), reads, Vec::new(), 0, || AllocationRoster {
            order: order.into(),
        })
        .expect("current-revision allocation store admits issued roster"))
}

#[cfg(test)]
mod tests {
    use super::*;
    fn capture(source: &str) -> (AllocationLedger, SymbolTable) {
        let parsed = dm_syntax::parse(source);
        assert!(parsed.diagnostics.is_empty());
        let mut symbols = SymbolTable::default();
        let ledger = dm_tree::allocation_ledger::capture(&parsed.items, "/", &mut symbols).unwrap();
        (ledger, symbols)
    }
    #[test]
    fn admitted_allocation_receipt_survives_body_edit_and_current_span_shift() {
        let store = AllocationArtifacts::default();
        let mut inventory = LinkInventory::default();
        inventory.fixed.push((Key::Type(SymbolId::of("/datum")), 2));
        let source = "/datum/a\n/datum/a/proc/run()\n    return 1\n/datum/a/child\n";
        let (ledger, symbols) = capture(source);
        let first = collect_retained(&ledger, source, &symbols, &inventory, Some(&store)).unwrap();
        let shifted = "// shifted\n/datum/a\n/datum/a/proc/run()\n    return 22\n/datum/a/child\n";
        let (ledger, symbols) = capture(shifted);
        let second =
            collect_retained(&ledger, shifted, &symbols, &inventory, Some(&store)).unwrap();
        assert!(Arc::ptr_eq(&first, &second));
        assert_eq!(
            second.order(),
            super::super::collect(&ledger, shifted, &symbols, &inventory).unwrap()
        );
        inventory
            .fixed
            .push((Key::Type(SymbolId::of("/datum/a")), 3));
        let changed =
            collect_retained(&ledger, shifted, &symbols, &inventory, Some(&store)).unwrap();
        assert!(!Arc::ptr_eq(&first, &changed));
        assert_eq!(changed.order(), &[SymbolId::of("/datum/a/child")]);
    }
    #[test]
    fn parent_source_change_and_current_symbol_loss_match_original_failures() {
        let store = AllocationArtifacts::default();
        let inventory = LinkInventory::default();
        let source = "/datum/a\n    parent_type = /datum/b\n/datum/b\n";
        let (ledger, symbols) = capture(source);
        let first = collect_retained(&ledger, source, &symbols, &inventory, Some(&store)).unwrap();
        let missing = SymbolTable::default();
        assert_eq!(
            collect_retained(&ledger, source, &missing, &inventory, Some(&store)).err(),
            super::super::collect(&ledger, source, &missing, &inventory).err(),
        );
        let invalid = "/datum/a\n    parent_type = 7\n/datum/b\n";
        let (ledger, symbols) = capture(invalid);
        assert_eq!(
            collect_retained(&ledger, invalid, &symbols, &inventory, Some(&store)).err(),
            super::super::collect(&ledger, invalid, &symbols, &inventory).err(),
        );
        let (ledger, symbols) = capture(source);
        let repaired =
            collect_retained(&ledger, source, &symbols, &inventory, Some(&store)).unwrap();
        assert_eq!(first.order(), repaired.order());
    }
}
