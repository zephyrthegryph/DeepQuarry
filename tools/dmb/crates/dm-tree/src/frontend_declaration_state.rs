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
    pub grammar_roster_hits: usize,
}
pub(super) struct RetainedDeclarations {
    pub(super) grammar: super::grammar_roster::RetainedGrammar,
    values: ArtifactStore<Contribution>,
    keys: AtomicUsize,
    hits: AtomicUsize,
    symbols: std::sync::Mutex<ActiveSymbols>,
}
impl Default for RetainedDeclarations {
    fn default() -> Self {
        Self {
            grammar: super::grammar_roster::RetainedGrammar::default(),
            values: ArtifactStore::current_revision(),
            keys: AtomicUsize::new(0),
            hits: AtomicUsize::new(0),
            symbols: std::sync::Mutex::new(ActiveSymbols::default()),
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
    facts: crate::AdaptedDeclarations,
    syntax: Arc<RelativeSyntax>,
    skeletons: Arc<Vec<crate::Skeleton>>,
    ledger: AllocationLedger,
    event_leaf: crate::allocation_ledger::ValidatedEventLeaf,
}
/// Complete public borrowed payload; no old source authority is reconstructed.
pub struct DeclarationContributionView<'a> {
    pub allocation_address: usize,
    pub allocation_size: usize,
    pub syntax: &'a Arc<RelativeSyntax>,
    pub skeletons: &'a Arc<Vec<crate::Skeleton>>,
    pub facts: &'a crate::AdaptedDeclarations,
    pub ledger: &'a AllocationLedger,
    event_leaf: &'a crate::allocation_ledger::ValidatedEventLeaf,
}
impl DeclarationContributionView<'_> {
    pub fn visit_allocation_storage(&self, mut visit: impl FnMut(usize, usize, usize)) {
        self.event_leaf.visit_storage(&mut visit);
    }
}
pub enum DeclarationStorageView<'a> {
    SymbolCatalog {
        symbols: &'a SymbolTable,
        counts: usize,
        contributions: usize,
    },
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
        let symbols = self
            .symbols
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        visit(DeclarationStorageView::SymbolCatalog {
            symbols: &symbols.symbols,
            counts: symbols.counts.len(),
            contributions: symbols.contributions.len(),
        });
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
                    syntax: &value.syntax,
                    skeletons: &value.skeletons,
                    facts: &value.facts,
                    ledger: &value.ledger,
                    event_leaf: &value.event_leaf,
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
    pub(super) fn clear(&self) {
        self.retain(&[]);
        self.grammar.clear();
        *self
            .symbols
            .lock()
            .unwrap_or_else(|error| error.into_inner()) = ActiveSymbols::default();
    }
    pub(super) fn get_shared(
        &self,
        key: &[u8],
        text: &str,
        offset: usize,
    ) -> Option<CurrentContribution> {
        let value = self.values.lookup(key, &NoReads)?;
        let bound = CurrentContribution::bind(value, text, offset)?;
        self.hits.fetch_add(1, Ordering::Relaxed);
        Some(bound)
    }
    pub(super) fn capture(
        &self,
        key: &[u8],
        text: &str,
        offset: usize,
        items: Vec<Item>,
        facts: crate::AdaptedDeclarations,
        ledger: AllocationLedger,
    ) -> Option<CurrentContribution> {
        let value = Contribution::capture_owned(text, offset, items, facts, ledger)?;
        self.values
            .insert_with(Arc::from(key), Vec::new(), Vec::new(), 0, || value);
        CurrentContribution::bind(self.values.lookup(key, &NoReads)?, text, offset)
    }
    #[cfg(test)]
    fn get(
        &self,
        key: &[u8],
        text: &str,
        offset: usize,
    ) -> Option<(Vec<Item>, crate::AdaptedDeclarations, AllocationLedger)> {
        let current = self.get_shared(key, text, offset)?;
        current.value.rebind(text, offset)
    }
    #[cfg(test)]
    fn insert(
        &self,
        key: &[u8],
        text: &str,
        offset: usize,
        items: &[Item],
        facts: &crate::AdaptedDeclarations,
        ledger: &AllocationLedger,
    ) {
        self.capture(
            key,
            text,
            offset,
            items.to_vec(),
            facts.clone(),
            ledger.clone(),
        );
    }
    pub(super) fn current_symbols(
        &self,
        current: &[Arc<Contribution>],
    ) -> Result<SymbolTable, dm_ir::SymbolCollision> {
        self.symbols
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .update(current)
    }
    pub(super) fn stats(&self) -> DeclarationRetentionStats {
        DeclarationRetentionStats {
            current_keys: self.keys.load(Ordering::Relaxed),
            unknown_retained_record_upper_bound: self.keys.load(Ordering::Relaxed),
            hits: self.hits.load(Ordering::Relaxed),
            grammar_roster_hits: self.grammar.hits(),
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
    fn current_bindings_share_relative_payload_and_catalog_removes_old_names() {
        let text = "/obj/probe\n    var/unique_name=1\n";
        let parsed = dm_syntax::parse_declaration_skeleton(text);
        let ast = AstFile {
            items: parsed.items,
            diagnostics: parsed.diagnostics,
            tokens: Vec::new(),
        };
        let mut facts = crate::from_ast(&ast, SymbolTable::default(), FileId(0), 0, 0).unwrap();
        let ledger =
            crate::allocation_ledger::capture(&ast.items, "/", &mut facts.symbols).unwrap();
        let name = facts.symbols.intern("unique_name").unwrap();
        let store = RetainedDeclarations::default();
        let key = RetainedDeclarations::key(text);
        store.retain(&[key.clone()]);
        let first = store
            .capture(&key, text, 0, ast.items, facts, ledger)
            .unwrap();
        let shifted = store.get_shared(&key, text, 80).unwrap();
        assert!(Arc::ptr_eq(&first.value, &shifted.value));
        assert!(Arc::ptr_eq(
            first.syntax.shared_relative(),
            shifted.syntax.shared_relative()
        ));
        assert!(Arc::ptr_eq(&first.skeletons(), &shifted.skeletons()));
        let a = first.syntax.items().next().unwrap();
        let b = shifted.syntax.items().next().unwrap();
        assert!(std::ptr::eq(a.relative_item(), b.relative_item()));
        assert_eq!(b.span().start, a.span().start + 80);
        let symbols = store.current_symbols(&[Arc::clone(&first.value)]).unwrap();
        assert_eq!(symbols.text(name), Some("unique_name"));
        let symbols = store
            .current_symbols(&[Arc::clone(&shifted.value)])
            .unwrap();
        assert_eq!(symbols.text(name), Some("unique_name"));
        assert!(store.current_symbols(&[]).unwrap().text(name).is_none());
        // Previously issued bindings remain immutable after current-roster pruning.
        store.retain(&[]);
        assert_eq!(b.header(), "/obj/probe");
    }
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
        assert_eq!(restored.skeletons.as_ref(), &facts.skeletons);
        assert_eq!(
            restored.syntax.relative_items().as_ref(),
            ast.items.as_slice()
        );
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
pub(super) struct CurrentContribution {
    pub(super) value: Arc<Contribution>,
    pub(super) syntax: CurrentSyntaxChunk,
    offset: usize,
}
impl CurrentContribution {
    fn bind(value: Arc<Contribution>, text: &str, offset: usize) -> Option<Self> {
        let syntax = value.syntax.bind(text.len(), offset).ok()?;
        // Origin and allocation spans were validated against the same relative source.
        offset
            .checked_add(text.len())
            .filter(|end| *end <= u32::MAX as usize)?;
        Some(Self {
            value,
            syntax,
            offset,
        })
    }
    pub(super) fn fresh(
        text: &str,
        offset: usize,
        items: Vec<Item>,
        facts: crate::AdaptedDeclarations,
        ledger: AllocationLedger,
    ) -> Option<Self> {
        Self::bind(
            Arc::new(Contribution::capture_owned(
                text, offset, items, facts, ledger,
            )?),
            text,
            offset,
        )
    }
    pub(super) fn symbols(&self) -> &SymbolTable {
        &self.value.facts.symbols
    }
    pub(super) fn skeletons(&self) -> Arc<Vec<crate::Skeleton>> {
        Arc::clone(&self.value.skeletons)
    }
    pub(super) fn origins(&self) -> impl Iterator<Item = crate::Provenance> + '_ {
        self.value.facts.origins.iter().cloned().map(|mut origin| {
            origin.span.start += self.offset as u32;
            origin.span.end += self.offset as u32;
            origin
        })
    }
    pub(super) fn event_leaf(&self) -> (crate::allocation_ledger::ValidatedEventLeaf, usize) {
        (self.value.event_leaf.clone(), self.offset)
    }
}
impl Contribution {
    fn capture_owned(
        text: &str,
        offset: usize,
        mut items: Vec<Item>,
        mut facts: crate::AdaptedDeclarations,
        ledger: AllocationLedger,
    ) -> Option<Self> {
        items_spans(&mut items, text, offset, 0)?;
        let ledger = rebase(&mut facts, &ledger, text, offset, 0)?;
        let syntax = Arc::new(RelativeSyntax::capture(items, text).ok()?);
        let skeletons = Arc::new(std::mem::take(&mut facts.skeletons));
        let event_leaf = crate::allocation_ledger::ValidatedEventLeaf::new(ledger.events.clone());
        Some(Self {
            facts,
            ledger,
            event_leaf,
            syntax,
            skeletons,
        })
    }
    #[cfg(test)]
    fn capture(
        text: &str,
        offset: usize,
        items: &[Item],
        facts: &crate::AdaptedDeclarations,
        ledger: &AllocationLedger,
    ) -> Option<Self> {
        Self::capture_owned(text, offset, items.to_vec(), facts.clone(), ledger.clone())
    }
    #[cfg(test)]
    fn rebind(
        &self,
        text: &str,
        offset: usize,
    ) -> Option<(Vec<Item>, crate::AdaptedDeclarations, AllocationLedger)> {
        let mut items = self.syntax.relative_items().to_vec();
        let mut facts = self.facts.clone();
        facts.skeletons = self.skeletons.as_ref().clone();
        items_spans(&mut items, text, 0, offset)?;
        let ledger = rebase(&mut facts, &self.ledger, text, 0, offset)?;
        Some((items, facts, ledger))
    }
}

#[derive(Default)]
struct ActiveSymbols {
    contributions: std::collections::BTreeMap<usize, Arc<Contribution>>,
    counts: std::collections::BTreeMap<dm_ir::SymbolId, usize>,
    symbols: SymbolTable,
}
impl ActiveSymbols {
    fn update(
        &mut self,
        current: &[Arc<Contribution>],
    ) -> Result<SymbolTable, dm_ir::SymbolCollision> {
        let next: std::collections::BTreeMap<_, _> = current
            .iter()
            .map(|value| (Arc::as_ptr(value) as usize, Arc::clone(value)))
            .collect();
        if next.len() == self.contributions.len() && next.keys().eq(self.contributions.keys()) {
            // Retained Arcs prevent address reuse: exact immutable leaf roster.
            return Ok(self.symbols.clone());
        }
        // Precheck every added leaf against a shallow transaction before committing.
        let mut symbols = self.symbols.clone();
        let mut counts = self.counts.clone();
        for (address, value) in &self.contributions {
            if !next.contains_key(address) {
                for (id, _) in value.facts.symbols.ordered() {
                    if let Some(count) = counts.get_mut(&id) {
                        *count -= 1;
                    }
                }
            }
        }
        counts.retain(|_, count| *count != 0);
        // Historical-only spellings cannot conflict with the new active roster.
        symbols.retain_local(|id| counts.contains_key(&id));
        for (address, value) in &next {
            if !self.contributions.contains_key(address) {
                for (id, _) in value.facts.symbols.ordered() {
                    *counts.entry(id).or_default() += 1;
                }
            }
        }
        counts.retain(|_, count| *count != 0);
        for (address, value) in &next {
            if !self.contributions.contains_key(address) {
                symbols.merge_from(&value.facts.symbols)?;
            }
        }
        self.counts = counts;
        self.symbols = symbols;
        self.contributions = next;
        Ok(self.symbols.clone())
    }
}
