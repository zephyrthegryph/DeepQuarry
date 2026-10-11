//! Exact output-piece observations for the existing joined grammar scanner.
use super::ExpandedRegions;
#[path = "frontend_grammar_convergence.rs"]
mod convergence;
#[cfg(test)]
use dm_preprocess::regions::ExpansionRecord;
use dm_preprocess::SourceText;
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
pub struct GrammarAnswer(Option<Arc<[SourceText]>>);
impl PartialEq for GrammarAnswer {
    fn eq(&self, other: &Self) -> bool {
        match (&self.0, &other.0) {
            (None, None) => true,
            (Some(a), Some(b)) => a.len() == b.len() && a.iter().zip(b.iter()).all(|(a, b)| a == b),
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
            records.push(receipt.record().shared_output_text());
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
    starts: Vec<dm_syntax::BoundaryCheckpoint>,
    reused: usize,
    scanned_bytes: usize,
}
impl GrammarDescriptors {
    pub fn checkpoints(&self) -> &Vec<dm_syntax::BoundaryCheckpoint> {
        &self.starts
    }
    pub fn construction_reused_descriptors(&self) -> usize {
        self.reused
    }
    pub fn construction_scanned_bytes(&self) -> usize {
        self.scanned_bytes
    }
    pub fn spans(&self) -> &Vec<(usize, usize)> {
        &self.spans
    }
}
pub(super) struct RetainedGrammar {
    values: Arc<ObservedArtifactStore<GrammarDescriptors, GrammarQuery, GrammarAnswer, ()>>,
    lease: dm_session::ObservedArtifactLease<GrammarDescriptors, GrammarQuery, GrammarAnswer, ()>,
    hits: AtomicUsize,
}
impl Default for RetainedGrammar {
    fn default() -> Self {
        let values = ObservedArtifactStore::shared_current_rosters();
        Self {
            lease: values.lease(),
            values,
            hits: AtomicUsize::new(0),
        }
    }
}
impl RetainedGrammar {
    pub(super) fn fork(&self) -> Self {
        Self {
            values: Arc::clone(&self.values),
            lease: self.values.lease(),
            hits: AtomicUsize::new(0),
        }
    }
    fn key() -> Vec<u8> {
        let mut key = b"joined-grammar-descriptors-v2".to_vec();
        key.extend_from_slice(&super::parserwire::VERSION.to_le_bytes());
        key.extend_from_slice(&32u64.to_le_bytes());
        key
    }
    #[cfg(test)]
    pub(super) fn lookup(&self, expanded: &ExpandedRegions) -> Option<Arc<GrammarDescriptors>> {
        let host = CurrentPieces::capture(expanded)?;
        let descriptors = self
            .lease
            .visit_explained(&Self::key(), &host, &mut |_| true)
            .0?;
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
    pub(super) fn discover(
        &self,
        expanded: &ExpandedRegions,
    ) -> Result<Arc<GrammarDescriptors>, &'static str> {
        let host = CurrentPieces::capture(expanded);
        let key = Self::key();
        if let Some(host) = &host {
            if let Some(value) = self.lease.visit_explained(&key, host, &mut |_| true).0 {
                if value.source_len == host.length {
                    self.hits.fetch_add(1, Ordering::Relaxed);
                    return Ok(value);
                }
            }
        }
        let mut previous = None;
        if host.is_some() {
            self.values.visit_storage(|entry| {
                if let dm_session::ObservedArtifactStorageView::Entry {
                    key: stored,
                    reads,
                    value,
                    ..
                } = entry
                {
                    if stored.as_ref() == key.as_slice()
                        && reads.len() == 1
                        && reads[0].query == GrammarQuery::OrderedPieces
                    {
                        previous = Some((Arc::clone(value), reads[0].answer.clone()));
                    }
                }
            });
        }
        let built = convergence::build(
            &expanded.text,
            previous
                .as_ref()
                .map(|(value, answer)| (value.as_ref(), answer)),
        )?;
        let descriptors = GrammarDescriptors {
            reused: built.reused,
            scanned_bytes: built.scanned_bytes,
            ..built.descriptors
        };
        if let Some(host) = host {
            let ledger = ObservationLedger::default();
            ledger.record(
                GrammarQuery::OrderedPieces,
                host.answer(&GrammarQuery::OrderedPieces),
                (),
                None,
            );
            self.lease.retain_current_keys([key.as_slice()]);
            self.lease.insert_with(
                key.clone().into(),
                ledger.reads(),
                ledger.domain_receipts(),
                0,
                || descriptors,
            );
            self.lease
                .visit_explained(&key, &host, &mut |_| true)
                .0
                .ok_or("new grammar descriptor admission failed")
        } else {
            // Missing exact piece coverage cannot authorize history reuse.
            Ok(Arc::new(descriptors))
        }
    }
    #[cfg(test)]
    fn insert(&self, expanded: &ExpandedRegions, spans: Vec<(usize, usize)>) {
        let value = self.discover(expanded).unwrap();
        assert_eq!(value.spans, spans);
    }
    pub(super) fn clear(&self) {
        self.lease.retain_current_keys(std::iter::empty::<&[u8]>());
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
    pub fn pieces(&self) -> Option<&Arc<[SourceText]>> {
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
    #[test]
    fn grammar_keeps_output_bytes_without_retaining_expansion_records() {
        let first = expand(1);
        let records: Vec<_> = first
            .receipts
            .iter()
            .map(|receipt| Arc::downgrade(receipt.record()))
            .collect();
        let outputs: Vec<_> = first
            .receipts
            .iter()
            .map(|receipt| receipt.record().shared_output_text().downgrade())
            .collect();
        assert!(!records.is_empty());
        let grammar = RetainedGrammar::default();
        let expected = scan(&first);
        grammar.insert(&first, expected.clone());
        drop(first);
        assert!(records.iter().all(|record| record.upgrade().is_none()));
        assert!(outputs.iter().all(|output| output.upgrade().is_some()));
        let current = expand(1);
        assert_eq!(grammar.lookup(&current).unwrap().spans, expected);
        let changed = expand(2);
        assert_eq!(changed.text.len(), current.text.len());
        assert!(grammar.lookup(&changed).is_none());
        grammar.clear();
        assert!(outputs.iter().all(|output| output.upgrade().is_none()));
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
        tampered.text = again.text.replace("count = 1", "count = 9").into();
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
        assert!(old.same_relative_node(new));
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
    fn expand_text(text: &str) -> ExpandedRegions {
        let source = Source(BTreeMap::from([(
            PathBuf::from("project.dme"),
            text.to_owned(),
        )]));
        let plan = dm_preprocess::regions::plan_regions(
            Path::new("project.dme"),
            &source,
            &BTreeMap::new(),
        );
        assert!(plan.diagnostics.is_empty());
        dm_preprocess::regions::expand_regions_text_with_memo(&plan, 1, &Memo)
    }
    #[test]
    fn body_and_structural_edits_converge_to_exact_fresh_descriptor_suffix() {
        let source = format!(
            "/datum/container\n    var/value=1\n{}",
            (0..180)
                .map(|index| format!("/proc/p{index}(arg=1)\n    return {index}\n"))
                .collect::<String>()
        );
        for edited in [
            source.replace("    return 80\n", "    return list(80,81,82,83)\n"),
            source.replace(
                "/proc/p80(arg=1)",
                "/proc/inserted()\n    return 1\n/proc/p80(arg=1)",
            ),
            source.replace("    var/value=1\n", "    var/value=1\n    var/other=2\n"),
            source.replace("/proc/p80(arg=1)", "/proc/p80(arg=9)"),
            source.replace("/proc/p80(arg=1)\n    return 80\n", ""),
            source.replace("    return 80\n", "    return \"\u{3b1}\"\n"),
        ] {
            let store = RetainedGrammar::default();
            let base = expand_text(&source);
            let before = store.discover(&base).unwrap();
            assert_eq!(before.spans, scan(&base));
            let expanded = expand_text(&edited);
            let rebuilt = store.discover(&expanded).unwrap();
            assert_eq!(rebuilt.spans, scan(&expanded));
            assert_eq!(rebuilt.spans.len(), rebuilt.starts.len());
            assert!(
                rebuilt.construction_reused_descriptors() > 0,
                "edit must reuse an exact prefix or converged suffix"
            );
            assert!(
                rebuilt.construction_scanned_bytes() < expanded.text.len(),
                "edit must avoid whole joined grammar scan"
            );
            assert_eq!(store.discover(&expanded).unwrap().spans, rebuilt.spans);
            assert_eq!(store.hits(), 1);
        }
    }
    #[test]
    fn convergence_preserves_literals_delimiter_changes_and_cross_include_units() {
        let source = (0..180)
            .map(|index| format!("/proc/p{index}()\n    return {index}\n"))
            .collect::<String>();
        for replacement in [
            "    return {\"multiline\n/proc/not_a_declaration()\nend\"}\n",
            "    return list(80,\n        list(1,2))\n",
            "    /* nested /* block */ comment */ return 80\n",
            "    return (80\n", // Changes lexical depth through the suffix: convergence must decline.
        ] {
            let store = RetainedGrammar::default();
            store.discover(&expand_text(&source)).unwrap();
            let edited = source.replace("    return 80\n", replacement);
            let expanded = expand_text(&edited);
            assert_eq!(store.discover(&expanded).unwrap().spans, scan(&expanded));
        }
        let store = RetainedGrammar::default();
        let first = expand(1);
        store.discover(&first).unwrap();
        let changed = expand(2);
        assert_eq!(store.discover(&changed).unwrap().spans, scan(&changed));
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
            GrammarAnswer(Some(vec![record.shared_output_text()].into())),
            GrammarAnswer(Some(vec![altered.shared_output_text()].into()))
        );
    }
}
