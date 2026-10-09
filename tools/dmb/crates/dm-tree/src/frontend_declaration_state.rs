//! Owned root-context declaration contributions; all stored coordinates are relative.
use super::*;
use crate::allocation_ledger::{AllocationKind, AllocationLedger, EventBuilder};
use dm_session::{ArtifactStorageView, ArtifactStore};
use std::sync::atomic::{AtomicUsize, Ordering};

#[derive(Default)]
pub struct DeclarationRetentionStats {
    pub current_keys: usize,
    /// Full metadata/index capacities have not yet been traversed by the census.
    pub unknown_retained_record_upper_bound: usize,
    pub hits: usize,
}
pub(super) struct RetainedDeclarations {
    values: ArtifactStore<Contribution>,
    keys: AtomicUsize,
    hits: AtomicUsize,
}
impl Default for RetainedDeclarations {
    fn default() -> Self {
        Self {
            values: ArtifactStore::current_revision(),
            keys: AtomicUsize::new(0),
            hits: AtomicUsize::new(0),
        }
    }
}
struct NoReads;
impl dm_ir::Resolver for NoReads {
    fn resolve(&self, query: dm_ir::ResolveQuery) -> dm_ir::ResolvedMeaning {
        dm_ir::ResolvedMeaning::Unsupported(query)
    }
}
pub(super) struct Contribution {
    items: Vec<Item>,
    facts: crate::AdaptedDeclarations,
    ledger: AllocationLedger,
}
/// Complete public borrowed payload; no old source authority is reconstructed.
pub struct DeclarationContributionView<'a> {
    pub allocation_address: usize,
    pub allocation_size: usize,
    pub items: &'a Vec<Item>,
    pub facts: &'a crate::AdaptedDeclarations,
    pub ledger: &'a AllocationLedger,
}
pub enum DeclarationStorageView<'a> {
    Store {
        buckets: usize,
        entries: usize,
    },
    Bucket {
        address: usize,
        len: usize,
        capacity: usize,
        element_size: usize,
    },
    Entry {
        key: &'a Arc<[u8]>,
        reads: &'a Arc<[dm_session::ResolverRead]>,
        versions: &'a Arc<[(dm_ir::ReadDomain, u128)]>,
        contribution: DeclarationContributionView<'a>,
    },
}
impl RetainedDeclarations {
    pub(super) fn visit_storage(&self, mut visit: impl FnMut(DeclarationStorageView<'_>)) {
        self.values.visit_storage(|storage| match storage {
            ArtifactStorageView::Store { buckets, entries } => {
                visit(DeclarationStorageView::Store { buckets, entries })
            }
            ArtifactStorageView::Bucket {
                address,
                len,
                capacity,
                element_size,
            } => visit(DeclarationStorageView::Bucket {
                address,
                len,
                capacity,
                element_size,
            }),
            ArtifactStorageView::Entry {
                key,
                reads,
                versions,
                value,
            } => visit(DeclarationStorageView::Entry {
                key,
                reads,
                versions,
                contribution: DeclarationContributionView {
                    allocation_address: Arc::as_ptr(value) as usize,
                    allocation_size: std::mem::size_of::<Contribution>(),
                    items: &value.items,
                    facts: &value.facts,
                    ledger: &value.ledger,
                },
            }),
        });
    }
    pub(super) fn key(text: &str) -> Vec<u8> {
        let mut key = b"owned-root-declarations-v1".to_vec();
        key.extend_from_slice(&parserwire::VERSION.to_le_bytes());
        key.extend_from_slice(text.as_bytes());
        key
    }
    pub(super) fn retain(&self, keys: &[Vec<u8>]) {
        self.values
            .retain_current_keys(keys.iter().map(Vec::as_slice));
        self.keys.store(keys.len(), Ordering::Relaxed);
    }
    pub(super) fn get(
        &self,
        key: &[u8],
        text: &str,
        offset: usize,
    ) -> Option<(Vec<Item>, crate::AdaptedDeclarations, AllocationLedger)> {
        let mut rebound = None;
        self.values.visit_explained(key, &NoReads, &mut |value| {
            rebound = value.rebind(text, offset);
            rebound.is_some()
        });
        if rebound.is_some() {
            self.hits.fetch_add(1, Ordering::Relaxed);
        }
        rebound
    }
    pub(super) fn insert(
        &self,
        key: &[u8],
        text: &str,
        offset: usize,
        items: &[Item],
        facts: &crate::AdaptedDeclarations,
        ledger: &AllocationLedger,
    ) {
        let Some(value) = Contribution::capture(text, offset, items, facts, ledger) else {
            return;
        };
        // Zero is NOT a memory estimate: this full-current-roster mode has no
        // byte budget; public statistics explicitly mark every record unknown.
        self.values
            .insert_with(Arc::from(key), Vec::new(), Vec::new(), 0, || value);
    }
    pub(super) fn stats(&self) -> DeclarationRetentionStats {
        DeclarationRetentionStats {
            current_keys: self.keys.load(Ordering::Relaxed),
            unknown_retained_record_upper_bound: self.keys.load(Ordering::Relaxed),
            hits: self.hits.load(Ordering::Relaxed),
        }
    }
}
fn span(span: dm_syntax::Span, text: &str, from: usize, to: usize) -> Option<dm_syntax::Span> {
    let start = span.start.checked_sub(from)?;
    let end = span.end.checked_sub(from)?;
    text.get(start..end)?;
    Some(dm_syntax::Span::new(
        start.checked_add(to)?,
        end.checked_add(to)?,
    ))
}
fn items_spans(items: &mut [Item], text: &str, from: usize, to: usize) -> Option<()> {
    for item in items {
        item.span = span(item.span, text, from, to)?;
        item.header_span = span(item.header_span, text, from, to)?;
        items_spans(&mut item.children, text, from, to)?;
    }
    Some(())
}
fn rebase(
    facts: &mut crate::AdaptedDeclarations,
    ledger: &AllocationLedger,
    text: &str,
    from: usize,
    to: usize,
) -> Option<AllocationLedger> {
    for origin in &mut facts.origins {
        if origin.span.file != FileId(0)
            || origin.include_occurrence != 0
            || origin.region != 0
            || !origin.expansion_stack.is_empty()
        {
            return None;
        }
        let mapped = span(
            dm_syntax::Span::new(origin.span.start as usize, origin.span.end as usize),
            text,
            from,
            to,
        )?;
        origin.span.start = u32::try_from(mapped.start).ok()?;
        origin.span.end = u32::try_from(mapped.end).ok()?;
    }
    let mut events = EventBuilder::new();
    for mut event in ledger.events.iter() {
        event.span = span(event.span, text, from, to)?;
        event.header_span = span(event.header_span, text, from, to)?;
        match &mut event.kind {
            AllocationKind::Field { initializer, .. } => {
                *initializer = match *initializer {
                    Some(value) => Some(span(value, text, from, to)?),
                    None => None,
                };
            }
            AllocationKind::Procedure { body, .. } => *body = span(*body, text, from, to)?,
            AllocationKind::Parent { value, .. } => *value = span(*value, text, from, to)?,
            AllocationKind::Type { .. } | AllocationKind::Namespace { .. } => {}
        }
        events.push(event);
    }
    Some(AllocationLedger {
        events: events.finish(),
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn owned_chunk_rebinds_all_nested_coordinates_and_rejects_foreign_spans() {
        let text =
            "/obj/base\n    var/count=1\n/proc/p()\n    set name = \"Display\"\n    return 1\n";
        let mut ast = dm_syntax::parse_declaration_skeleton(text);
        ast.items = compact_declarations(ast.items, 0);
        let adapted_ast = dm_syntax::AstFile {
            items: ast.items.clone(),
            tokens: Vec::new(),
            diagnostics: ast.diagnostics.clone(),
        };
        let mut facts =
            crate::from_ast(&adapted_ast, SymbolTable::default(), FileId(0), 0, 0).unwrap();
        let ledger =
            crate::allocation_ledger::capture(&ast.items, "/", &mut facts.symbols).unwrap();
        let contribution = Contribution::capture(text, 0, &ast.items, &facts, &ledger).unwrap();
        let (shifted_items, shifted, shifted_ledger) = contribution.rebind(text, 113).unwrap();
        assert_eq!(shifted.skeletons, facts.skeletons);
        for (new, old) in shifted.origins.iter().zip(&facts.origins) {
            assert_eq!(new.span.start, old.span.start + 113);
            assert_eq!(new.span.end, old.span.end + 113);
        }
        let restored =
            Contribution::capture(text, 113, &shifted_items, &shifted, &shifted_ledger).unwrap();
        assert_eq!(restored.ledger.events, ledger.events);
        assert_eq!(restored.facts.origins, facts.origins);
        assert_eq!(restored.items, ast.items);
        assert!(contribution.rebind(text, usize::MAX).is_none());
        let mut foreign = facts.clone();
        foreign.origins[0].span.file = FileId(1);
        assert!(Contribution::capture(text, 0, &ast.items, &foreign, &ledger).is_none());
        let store = RetainedDeclarations::default();
        let key = RetainedDeclarations::key(text);
        store.retain(&[key.clone()]);
        store.insert(&key, text, 0, &ast.items, &facts, &ledger);
        assert!(store.get(&key, text, 113).is_some());
        assert!(store
            .get(&RetainedDeclarations::key("var/changed=2\n"), text, 0)
            .is_none());
        store.retain(&[]);
        assert!(store.get(&key, text, 0).is_none());
    }
}
impl Contribution {
    fn capture(
        text: &str,
        offset: usize,
        items: &[Item],
        facts: &crate::AdaptedDeclarations,
        ledger: &AllocationLedger,
    ) -> Option<Self> {
        let mut items = items.to_vec();
        let mut facts = facts.clone();
        items_spans(&mut items, text, offset, 0)?;
        let ledger = rebase(&mut facts, ledger, text, offset, 0)?;
        Some(Self {
            items,
            facts,
            ledger,
        })
    }
    fn rebind(
        &self,
        text: &str,
        offset: usize,
    ) -> Option<(Vec<Item>, crate::AdaptedDeclarations, AllocationLedger)> {
        let mut items = self.items.clone();
        let mut facts = self.facts.clone();
        items_spans(&mut items, text, 0, offset)?;
        let ledger = rebase(&mut facts, &self.ledger, text, 0, offset)?;
        Some((items, facts, ledger))
    }
}
