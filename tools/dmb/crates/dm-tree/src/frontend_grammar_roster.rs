//! Exact output-piece observations for the existing joined grammar scanner.
use super::ExpandedRegions;
use dm_preprocess::regions::ExpansionRecord;
use dm_session::{ObservationHost, ObservationLedger, ObservedArtifactStore};
use std::sync::{
    atomic::{AtomicUsize, Ordering},
    Arc,
};
#[derive(Clone, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub enum GrammarQuery {
    OrderedPieces,
}
#[derive(Clone, Debug)]
pub struct GrammarAnswer(Option<Arc<[Arc<ExpansionRecord>]>>);
impl PartialEq for GrammarAnswer {
    fn eq(&self, other: &Self) -> bool {
        match (&self.0, &other.0) {
            (None, None) => true,
            (Some(a), Some(b)) => {
                a.len() == b.len()
                    && a.iter()
                        .zip(b.iter())
                        .all(|(a, b)| Arc::ptr_eq(a, b) || a.text() == b.text())
            }
            _ => false,
        }
    }
}
impl Eq for GrammarAnswer {}
struct CurrentPieces {
    answer: GrammarAnswer,
    length: usize,
}
impl CurrentPieces {
    fn capture(expanded: &ExpandedRegions) -> Option<Self> {
        let mut cursor = 0usize;
        let mut records = Vec::with_capacity(expanded.receipts.len());
        for receipt in &expanded.receipts {
            let span = receipt.output_span();
            if span.start != cursor || expanded.text.get(span.range())? != receipt.record().text() {
                return None;
            }
            cursor = span.end;
            records.push(Arc::clone(receipt.record()));
        }
        if cursor != expanded.text.len() {
            return None;
        }
        Some(Self {
            answer: GrammarAnswer(Some(records.into())),
            length: cursor,
        })
    }
}
impl ObservationHost<GrammarQuery, GrammarAnswer, ()> for CurrentPieces {
    fn answer(&self, _: &GrammarQuery) -> GrammarAnswer {
        self.answer.clone()
    }
}
pub struct GrammarDescriptors {
    pub(crate) spans: Vec<(usize, usize)>,
    pub(crate) source_len: usize,
}
impl GrammarDescriptors {
    pub fn spans(&self) -> &Vec<(usize, usize)> {
        &self.spans
    }
}
pub(super) struct RetainedGrammar {
    values: ObservedArtifactStore<GrammarDescriptors, GrammarQuery, GrammarAnswer, ()>,
    hits: AtomicUsize,
}
impl Default for RetainedGrammar {
    fn default() -> Self {
        Self {
            values: ObservedArtifactStore::current_revision(),
            hits: AtomicUsize::new(0),
        }
    }
}
impl RetainedGrammar {
    fn key() -> Vec<u8> {
        let mut key = b"joined-grammar-descriptors-v1".to_vec();
        key.extend_from_slice(&super::parserwire::VERSION.to_le_bytes());
        key.extend_from_slice(&32u64.to_le_bytes());
        key
    }
    pub(super) fn lookup(&self, expanded: &ExpandedRegions) -> Option<Arc<GrammarDescriptors>> {
        let host = CurrentPieces::capture(expanded)?;
        let descriptors = self.values.lookup(&Self::key(), &host)?;
        if descriptors.source_len != host.length
            || descriptors.spans.iter().any(|&(offset, len)| {
                offset.checked_add(len).is_none_or(|end| end > host.length)
                    || !expanded.text.is_char_boundary(offset)
                    || !expanded.text.is_char_boundary(offset + len)
            })
        {
            return None;
        }
        self.hits.fetch_add(1, Ordering::Relaxed);
        Some(descriptors)
    }
    pub(super) fn insert(&self, expanded: &ExpandedRegions, spans: Vec<(usize, usize)>) {
        let Some(host) = CurrentPieces::capture(expanded) else {
            return;
        };
        let ledger = ObservationLedger::default();
        ledger.record(
            GrammarQuery::OrderedPieces,
            host.answer(&GrammarQuery::OrderedPieces),
            (),
            None,
        );
        let key = Self::key();
        self.values.retain_current_keys([key.as_slice()]);
        self.values.insert_with(
            key.into(),
            ledger.reads(),
            ledger.domain_receipts(),
            0,
            || GrammarDescriptors {
                spans,
                source_len: host.length,
            },
        );
    }
    pub(super) fn clear(&self) {
        self.values.retain_current_keys(std::iter::empty::<&[u8]>());
    }
    pub(super) fn hits(&self) -> usize {
        self.hits.load(Ordering::Relaxed)
    }
    pub(super) fn visit_storage(
        &self,
        visit: impl FnMut(
            dm_session::ObservedArtifactStorageView<
                '_,
                GrammarDescriptors,
                GrammarQuery,
                GrammarAnswer,
                (),
            >,
        ),
    ) {
        self.values.visit_storage(visit);
    }
}
impl GrammarAnswer {
    pub fn records(&self) -> Option<&Arc<[Arc<ExpansionRecord>]>> {
        self.0.as_ref()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::{
        collections::BTreeMap,
        path::{Path, PathBuf},
    };
    struct Source(BTreeMap<PathBuf, String>);
    impl dm_preprocess::SourceProvider for Source {
        fn read(&self, path: &Path) -> Result<String, String> {
            self.0
                .get(path)
                .cloned()
                .ok_or_else(|| "missing fixture".into())
        }
    }
    struct Memo;
    impl dm_preprocess::regions::ExpansionMemo for Memo {
        fn candidates(&self, _: u128) -> Vec<Arc<ExpansionRecord>> {
            Vec::new()
        }
        fn insert(&self, _: Arc<ExpansionRecord>) {}
    }
    fn expand(value: u32) -> ExpandedRegions {
        let source = Source(BTreeMap::from([
            (
                PathBuf::from("project.dme"),
                "/datum/probe\n#include \"member.dm\"\n/proc/after()\n    return 4\n".into(),
            ),
            (
                PathBuf::from("member.dm"),
                format!("    var/count = {value}\n    proc/get()\n        return count\n"),
            ),
        ]));
        let plan = dm_preprocess::regions::plan_regions(
            Path::new("project.dme"),
            &source,
            &BTreeMap::new(),
        );
        assert!(plan.diagnostics.is_empty());
        dm_preprocess::regions::expand_regions_text_with_memo(&plan, 1, &Memo)
    }
    fn scan(expanded: &ExpandedRegions) -> Vec<(usize, usize)> {
        let mut spans = Vec::new();
        let report = dm_syntax::for_each_stable_source_chunk(
            &expanded.text,
            expanded.text.len().max(1),
            32,
            |text, offset| spans.push((offset, text.len())),
        );
        assert_eq!(report.skipped_declarations, 0);
        spans
    }
    #[test]
    fn exact_piece_replay_preserves_cross_include_grammar_and_declines_changes() {
        let first = expand(1);
        assert!(first.receipts.len() > 1);
        let store = RetainedGrammar::default();
        let spans = scan(&first);
        assert!(store.lookup(&first).is_none());
        store.insert(&first, spans.clone());
        let again = expand(1);
        let hit = store.lookup(&again).unwrap();
        assert_eq!(hit.spans, scan(&again));
        assert_eq!(hit.spans, spans);
        assert_eq!(store.hits(), 1);
        for &(offset, len) in &hit.spans {
            assert!(
                dm_syntax::parse_declaration_skeleton(&again.text[offset..offset + len])
                    .diagnostics
                    .is_empty()
            );
        }
        let changed = expand(2);
        assert_eq!(changed.text.len(), first.text.len());
        assert!(store.lookup(&changed).is_none());
        let mut tampered = again.clone();
        tampered.text = Arc::from(again.text.replace("count = 1", "count = 9"));
        assert!(store.lookup(&tampered).is_none());
        let mut incomplete = again.clone();
        incomplete.receipts.pop();
        assert!(store.lookup(&incomplete).is_none());
    }
    #[test]
    fn production_parser_uses_shared_descriptor_roster_without_changing_results() {
        let state = super::super::declaration_state::RetainedDeclarations::default();
        let executor = dm_exec::BuildExecutor::new(1).unwrap();
        let config = super::super::FrontendConfig {
            workers: 1,
            engine: None,
            observer: None,
        };
        let first = expand(1);
        let parsed = super::super::declaration_parse::parse_declarations_with_state(
            &first,
            config,
            None,
            &executor,
            Some(&state),
        )
        .unwrap();
        let again = expand(1);
        let replay = super::super::declaration_parse::parse_declarations_with_state(
            &again,
            config,
            None,
            &executor,
            Some(&state),
        )
        .unwrap();
        assert_eq!(state.stats().grammar_roster_hits, 1);
        assert_eq!(replay.reuse_stats.parsed_chunks, 0);
        assert_eq!(parsed.adapted.skeletons, replay.adapted.skeletons);
        assert_eq!(
            parsed.adapted.symbols.ordered(),
            replay.adapted.symbols.ordered()
        );
        let old = parsed.syntax.items().next().unwrap();
        let new = replay.syntax.items().next().unwrap();
        assert!(std::ptr::eq(old.relative_item(), new.relative_item()));
        let changed = expand(2);
        let updated = super::super::declaration_parse::parse_declarations_with_state(
            &changed,
            config,
            None,
            &executor,
            Some(&state),
        )
        .unwrap();
        assert_eq!(state.stats().grammar_roster_hits, 1);
        let fresh = super::super::declaration_parse::parse_declarations_with_state(
            &changed, config, None, &executor, None,
        )
        .unwrap();
        assert_eq!(updated.adapted.skeletons, fresh.adapted.skeletons);
        assert_eq!(
            updated.adapted.symbols.ordered(),
            fresh.adapted.symbols.ordered()
        );
    }
    #[test]
    fn parser_fragments_are_not_grammar_inputs() {
        let expanded = expand(1);
        let record = Arc::clone(expanded.receipts[0].record());
        let altered = record
            .with_fragment(
                13,
                dm_syntax::Span::new(0, record.text().len()),
                Arc::from(b"different parser payload".as_slice()),
            )
            .unwrap();
        assert_eq!(
            GrammarAnswer(Some(vec![record].into())),
            GrammarAnswer(Some(vec![Arc::new(altered)].into()))
        );
    }
}
