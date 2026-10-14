//! Owned root-context declaration contributions; all stored coordinates are relative.
use super::*;
#[path = "frontend_declaration_state/authored.rs"]
mod authored;
#[path = "frontend_declaration_state/shared.rs"]
pub(crate) mod shared;
use crate::allocation_ledger::{AllocationKind, AllocationLedger, EventBuilder};

pub use shared::ChunkSourceAnswer;
use shared::DeclarationValues;
use std::sync::atomic::{AtomicUsize, Ordering};

#[derive(Default)]
pub struct DeclarationRetentionStats {
    pub current_keys: usize,
    /// Borrowed storage visits the engine-wide core; counts here remain host-local.
    pub shared_census_scope: bool,
    /// Full metadata/index capacities have not yet been traversed by the census.
    pub unknown_retained_record_upper_bound: usize,
    pub hits: usize,
    pub grammar_roster_hits: usize,
}
#[path = "frontend_declaration_state/publication.rs"]
mod publication;
pub use publication::DeclarationRequest;
pub(super) use publication::RetainedDeclarations;
struct DeclarationClaims {
    pub(super) grammar: super::grammar_roster::RetainedGrammar,
    values: DeclarationValues,
    authored: Option<crate::declaration_contributions::authored::AuthoredLease>,
    authored_current: Arc<std::sync::Mutex<Option<Arc<authored::AdmittedAuthored>>>>,
    keys: AtomicUsize,
    hits: AtomicUsize,
    symbols: std::sync::Mutex<Arc<ActiveSymbols>>,
}
impl Default for DeclarationClaims {
    fn default() -> Self {
        Self {
            grammar: super::grammar_roster::RetainedGrammar::default(),
            values: DeclarationValues::default(),
            authored: None,
            authored_current: Arc::new(std::sync::Mutex::new(None)),
            keys: AtomicUsize::new(0),
            hits: AtomicUsize::new(0),
            symbols: std::sync::Mutex::new(Arc::new(ActiveSymbols::default())),
        }
    }
}
#[derive(Clone)]
pub(crate) struct Contribution {
    // A locator is not source authority. Every current binding checks these bytes.
    source: dm_preprocess::SourceText,
    facts: Arc<crate::AdaptedDeclarations>,
    syntax: Arc<RelativeSyntax>,
    skeletons: Arc<Vec<crate::Skeleton>>,
    ledger: AllocationLedger,
    event_leaf: crate::allocation_ledger::ValidatedEventLeaf,
    origin_max: u32,
}
/// Complete public borrowed payload; no old source authority is reconstructed.
pub struct DeclarationContributionView<'a> {
    pub allocation_address: usize,
    pub allocation_size: usize,
    pub syntax: &'a Arc<RelativeSyntax>,
    pub source: &'a dm_preprocess::SourceText,
    pub skeletons: &'a Arc<Vec<crate::Skeleton>>,
    pub facts: &'a crate::AdaptedDeclarations,
    pub facts_owner: &'a Arc<crate::AdaptedDeclarations>,
    pub ledger: &'a AllocationLedger,
    event_leaf: &'a crate::allocation_ledger::ValidatedEventLeaf,
}
impl DeclarationContributionView<'_> {
    pub fn visit_allocation_storage(&self, mut visit: impl FnMut(usize, usize, usize)) {
        self.event_leaf.visit_storage(&mut visit);
    }
}
pub enum DeclarationStorageView<'a> {
    /// Host-local descriptor backing; payload leaves may also belong to shared entries.
    AuthoredLeafRoster {
        leaves: &'a Vec<Arc<Vec<crate::Skeleton>>>,
    },
    SharedEntry {
        key: &'a Arc<[u8]>,
        reads: &'a dm_session::Receipt<(), ChunkSourceAnswer, ()>,
        versions: &'a Arc<[((), u128)]>,
        contribution: DeclarationContributionView<'a>,
    },
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
        reads:
            &'a dm_session::Receipt<dm_ir::ResolveQuery, dm_ir::ResolvedMeaning, dm_ir::ReadDomain>,
        versions: &'a Arc<[(dm_ir::ReadDomain, u128)]>,
        contribution: DeclarationContributionView<'a>,
    },
}
impl DeclarationClaims {
    pub(super) fn visit_bookkeeping(&self, mut visit: impl FnMut(DeclarationStorageView<'_>)) {
        {
            let authored = self
                .authored_current
                .lock()
                .unwrap_or_else(|error| error.into_inner());
            if let Some(authored) = authored.as_ref() {
                visit(DeclarationStorageView::AuthoredLeafRoster {
                    leaves: &authored.leaves,
                });
            }
        }
        let symbols = self
            .symbols
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        visit(DeclarationStorageView::SymbolCatalog {
            symbols: &symbols.symbols,
            counts: symbols.counts.len(),
            contributions: symbols.contributions.len(),
        });
        if let Some(catalog) = &symbols.catalog {
            visit(DeclarationStorageView::SymbolCatalog {
                symbols: &catalog.symbols,
                counts: 0,
                contributions: 0,
            });
            if let Some(engine) = &catalog.engine {
                visit(DeclarationStorageView::SymbolCatalog {
                    symbols: engine,
                    counts: 0,
                    contributions: 0,
                });
            }
        }
    }

    pub(super) fn key(text: &str) -> Vec<u8> {
        let mut key = b"owned-root-declarations-locator-v2".to_vec();
        key.extend_from_slice(&parserwire::VERSION.to_le_bytes());
        key.extend_from_slice(&(text.len() as u64).to_le_bytes());
        key.extend_from_slice(&xxhash_rust::xxh3::xxh3_128(text.as_bytes()).to_le_bytes());
        key
    }
    pub(super) fn retain(&self, keys: &[Vec<u8>]) {
        self.values.retain(keys);
        self.keys.store(keys.len(), Ordering::Relaxed);
    }
    pub(super) fn get_shared(
        &self,
        key: &[u8],
        text: &str,
        offset: usize,
    ) -> Option<CurrentContribution> {
        let bound = self.values.get(key, text, offset)?;
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
        self.capture_source(key, text.into(), offset, items, facts, ledger)
    }
    pub(super) fn capture_source(
        &self,
        key: &[u8],
        source: dm_preprocess::SourceText,
        offset: usize,
        items: Vec<Item>,
        facts: crate::AdaptedDeclarations,
        ledger: AllocationLedger,
    ) -> Option<CurrentContribution> {
        let value = Contribution::capture_source(source, offset, items, facts, ledger)?;
        let text = value.source.clone();
        let mut current = CurrentContribution::bind(Arc::new(value), &text, offset)?;
        if !self.values.is_shared() {
            self.values.publish(key, &mut current)?;
        }
        Some(current)
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
    pub(super) fn current_catalog(
        &self,
        current: &[Arc<Contribution>],
        engine: Option<&SymbolTable>,
    ) -> Result<Arc<super::symbol_catalog::SymbolCatalog>, dm_ir::SymbolCollision> {
        let mut active = self
            .symbols
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        let source = if active.matches(current) {
            Arc::clone(&active.symbols)
        } else {
            Arc::make_mut(&mut active).update(current)?
        };
        let catalog =
            super::symbol_catalog::SymbolCatalog::capture(active.catalog.as_ref(), source, engine)?;
        if !active
            .catalog
            .as_ref()
            .is_some_and(|old| Arc::ptr_eq(old, &catalog))
        {
            Arc::make_mut(&mut active).catalog = Some(Arc::clone(&catalog));
        }
        Ok(catalog)
    }
    #[cfg(test)]
    pub(super) fn current_symbols(
        &self,
        current: &[Arc<Contribution>],
    ) -> Result<SymbolTable, dm_ir::SymbolCollision> {
        let mut active = self
            .symbols
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        Arc::make_mut(&mut active)
            .update(current)
            .map(|symbols| symbols.as_ref().clone())
    }
    pub(super) fn stats(&self) -> DeclarationRetentionStats {
        DeclarationRetentionStats {
            current_keys: self.keys.load(Ordering::Relaxed),
            shared_census_scope: self.values.is_shared(),
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
    fn declaration_capture_shares_checked_region_view_and_rebinds_current_origins() {
        let text = "/obj/probe\n    var/display = \"café\"\n";
        let arena = dm_preprocess::SourceText::from(format!("prefix\n{text}suffix\n"));
        let view = arena.checked_view(7..7 + text.len()).unwrap();
        let parsed = dm_syntax::parse_declaration_skeleton(text);
        let ast = AstFile {
            items: parsed.items,
            diagnostics: parsed.diagnostics,
            tokens: Vec::new(),
        };
        let mut facts = crate::from_ast(&ast, SymbolTable::default(), FileId(0), 0, 0).unwrap();
        let ledger =
            crate::allocation_ledger::capture(&ast.items, "/", &mut facts.symbols).unwrap();
        let fallback =
            CurrentContribution::fresh(text, 0, ast.items.clone(), facts.clone(), ledger.clone())
                .unwrap();
        let store = RetainedDeclarations::default();
        let key = RetainedDeclarations::key(text);
        store.retain(&[key.clone()]);
        let current = store
            .capture_source(&key, view.clone(), 0, ast.items, facts, ledger)
            .unwrap();
        assert!(current.value.source.same_view(&view));
        assert!(current
            .syntax
            .shared_relative()
            .shared_source()
            .unwrap()
            .same_view(&view));
        assert_eq!(current.value.source.as_str().as_ptr(), arena[7..].as_ptr());
        assert!(!fallback.value.source.same_view(&view));
        assert_eq!(current.value.skeletons, fallback.value.skeletons);
        let shifted = store.get_shared(&key, text, 81).unwrap();
        assert!(shifted.value.source.same_view(&view));
        let (_, shifted_facts, _) = shifted.value.rebind(text, 81).unwrap();
        for (old, new) in current
            .value
            .relative_origins()
            .iter()
            .zip(shifted_facts.origins)
        {
            assert_eq!(new.span.start, old.span.start + 81);
            assert_eq!(new.span.end, old.span.end + 81);
        }
        let changed = text.replace("café", "cafe");
        assert_eq!(changed.len() + 1, text.len());
        assert!(store.get_shared(&key, &changed, 81).is_none());
        assert!(store.get_shared(&key, text, usize::MAX).is_none());
    }
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
        let fragment = dm_preprocess::regions::FragmentRecord::new_shared_source(
            super::super::parserwire::VERSION,
            first.shared_source(),
            Arc::from([1u8, 2]),
        )
        .unwrap();
        assert!(Arc::ptr_eq(
            fragment.shared_source(),
            first.value.source.full_original_owner().unwrap()
        ));
        assert!(Arc::ptr_eq(
            fragment.shared_source(),
            &shifted.shared_source()
        ));
        assert!(Arc::ptr_eq(
            fragment.shared_source(),
            first
                .syntax
                .shared_relative()
                .shared_source()
                .unwrap()
                .full_original_owner()
                .unwrap()
        ));
        assert!(fragment.matches(super::super::parserwire::VERSION, text));

        // Force the same locator for different equal-length source. A collision
        // must decline before any old syntax or semantic facts are issued.
        let foreign = text.replace("=1", "=2");
        assert_eq!(foreign.len(), text.len());
        assert!(store.get_shared(&key, &foreign, 80).is_none());
        assert!(first.value.rebind(&foreign, 80).is_none());
        assert_eq!(
            key.len(),
            RetainedDeclarations::key(&"x".repeat(4096)).len()
        );
        assert!(Arc::ptr_eq(&first.value, &shifted.value));
        assert!(Arc::ptr_eq(
            first.syntax.shared_relative(),
            shifted.syntax.shared_relative()
        ));
        assert!(Arc::ptr_eq(&first.skeletons(), &shifted.skeletons()));
        let mut origins = crate::relative_origins::RelativeOriginRoster::default();
        origins.push(Arc::clone(&first.value), 0).unwrap();
        origins.push(Arc::clone(&shifted.value), 80).unwrap();
        assert!(origins.push(Arc::clone(&first.value), usize::MAX).is_none());
        let bound = crate::relative_origins::OriginRoster::Bound(origins);
        let expected: Vec<_> = first
            .value
            .relative_origins()
            .iter()
            .cloned()
            .chain(
                first
                    .value
                    .relative_origins()
                    .iter()
                    .cloned()
                    .map(|mut origin| {
                        origin.span.start += 80;
                        origin.span.end += 80;
                        origin
                    }),
            )
            .collect();
        assert_eq!(bound, expected);
        let values = bound.into_owned();
        assert_eq!(values, expected);
        assert_eq!(
            first.value.relative_origins()[0].span.start,
            expected[0].span.start
        );
        let a = first.syntax.items().next().unwrap();
        let b = shifted.syntax.items().next().unwrap();
        assert!(a.same_relative_node(b));
        assert_eq!(b.span().start, a.span().start + 80);
        let catalog = store
            .current_catalog(&[Arc::clone(&first.value)], None)
            .unwrap();
        let shifted_catalog = store
            .current_catalog(&[Arc::clone(&shifted.value)], None)
            .unwrap();
        assert!(Arc::ptr_eq(&catalog, &shifted_catalog));
        let empty_catalog = store.current_catalog(&[], None).unwrap();
        assert!(!Arc::ptr_eq(&catalog, &empty_catalog));
        assert!(empty_catalog.symbols.text(name).is_none());
        assert_eq!(catalog.symbols.text(name), Some("unique_name"));
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
            restored.syntax.materialize_relative_items().as_slice(),
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
    pub(super) fn shared_source(&self) -> Arc<str> {
        self.value
            .source
            .full_original_owner()
            .map_or_else(|| Arc::from(self.value.source.as_ref()), Arc::clone)
    }
    fn bind(value: Arc<Contribution>, text: &str, offset: usize) -> Option<Self> {
        if value.source.as_ref() != text {
            return None;
        }
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
        Self::fresh_source(text.into(), offset, items, facts, ledger)
    }
    pub(super) fn fresh_source(
        source: dm_preprocess::SourceText,
        offset: usize,
        items: Vec<Item>,
        facts: crate::AdaptedDeclarations,
        ledger: AllocationLedger,
    ) -> Option<Self> {
        let text = source.clone();
        Self::bind(
            Arc::new(Contribution::capture_source(
                source, offset, items, facts, ledger,
            )?),
            &text,
            offset,
        )
    }
    pub(super) fn symbols(&self) -> &SymbolTable {
        &self.value.facts.symbols
    }
    pub(super) fn skeletons(&self) -> Arc<Vec<crate::Skeleton>> {
        Arc::clone(&self.value.skeletons)
    }
    pub(super) fn origin_leaf(&self) -> (Arc<Contribution>, usize) {
        (Arc::clone(&self.value), self.offset)
    }
    pub(super) fn event_leaf(&self) -> (crate::allocation_ledger::ValidatedEventLeaf, usize) {
        (self.value.event_leaf.clone(), self.offset)
    }
}
impl Contribution {
    pub(crate) fn relative_origins(&self) -> &[crate::Provenance] {
        &self.facts.origins
    }
    pub(crate) fn relative_origin_max(&self) -> u32 {
        self.origin_max
    }

    fn capture_source(
        source: dm_preprocess::SourceText,
        offset: usize,
        mut items: Vec<Item>,
        mut facts: crate::AdaptedDeclarations,
        ledger: AllocationLedger,
    ) -> Option<Self> {
        let text = source.as_ref();
        items_spans(&mut items, text, offset, 0)?;
        let ledger = rebase(&mut facts, &ledger, text, offset, 0)?;
        let settings = facts
            .skeletons
            .iter()
            .zip(&facts.origins)
            .filter_map(|(row, origin)| {
                let crate::Skeleton::Member { metadata, .. } = row else {
                    return None;
                };
                metadata
                    .procedure
                    .as_ref()
                    .map(|owner| (origin.span.start as usize, Arc::clone(owner)))
            })
            .collect();
        let syntax =
            Arc::new(RelativeSyntax::capture_with_settings(items, source.clone(), &settings).ok()?);
        let skeletons = Arc::new(std::mem::take(&mut facts.skeletons));
        let event_leaf = crate::allocation_ledger::ValidatedEventLeaf::new(ledger.events.clone());
        let origin_max = facts
            .origins
            .iter()
            .map(|origin| origin.span.start.max(origin.span.end))
            .max()
            .unwrap_or(0);
        Some(Self {
            source,
            facts: Arc::new(facts),
            ledger,
            event_leaf,
            origin_max,
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
        Self::capture_source(
            text.into(),
            offset,
            items.to_vec(),
            facts.clone(),
            ledger.clone(),
        )
    }
    #[cfg(test)]
    fn rebind(
        &self,
        text: &str,
        offset: usize,
    ) -> Option<(Vec<Item>, crate::AdaptedDeclarations, AllocationLedger)> {
        if self.source.as_ref() != text {
            return None;
        }
        let mut items = self.syntax.materialize_relative_items();
        let mut facts = self.facts.as_ref().clone();
        facts.skeletons = self.skeletons.as_ref().clone();
        items_spans(&mut items, text, 0, offset)?;
        let ledger = rebase(&mut facts, &self.ledger, text, 0, offset)?;
        Some((items, facts, ledger))
    }
}

#[derive(Default, Clone)]
struct ActiveSymbols {
    contributions: std::collections::BTreeMap<usize, Arc<Contribution>>,
    counts: std::collections::BTreeMap<dm_ir::SymbolId, usize>,
    symbols: Arc<SymbolTable>,
    catalog: Option<Arc<super::symbol_catalog::SymbolCatalog>>,
}
impl ActiveSymbols {
    fn matches(&self, current: &[Arc<Contribution>]) -> bool {
        current.len() == self.contributions.len()
            && current.iter().all(|value| {
                self.contributions
                    .get(&(Arc::as_ptr(value) as usize))
                    .is_some_and(|old| Arc::ptr_eq(old, value))
            })
    }
    fn update(
        &mut self,
        current: &[Arc<Contribution>],
    ) -> Result<Arc<SymbolTable>, dm_ir::SymbolCollision> {
        let next: std::collections::BTreeMap<_, _> = current
            .iter()
            .map(|value| (Arc::as_ptr(value) as usize, Arc::clone(value)))
            .collect();
        if next.len() == self.contributions.len() && next.keys().eq(self.contributions.keys()) {
            // Retained Arcs prevent address reuse: exact immutable leaf roster.
            return Ok(self.symbols.clone());
        }
        // Precheck every added leaf against a shallow transaction before committing.
        let mut symbols = self.symbols.as_ref().clone();
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
        if self.symbols.ordered() != symbols.ordered() {
            self.symbols = Arc::new(symbols);
        }
        self.contributions = next;
        Ok(self.symbols.clone())
    }
}
