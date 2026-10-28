use super::*;
#[derive(Serialize)]
struct Legacy<'a> {
    key: u128,
    #[serde(with = "source_wire")]
    source: crate::SourceText,
    control: u128,
    #[serde(with = "source_wire")]
    text: crate::SourceText,
    reads: &'a Vec<MacroRead>,
    locations: &'a Vec<(usize, bool, String)>,
    lines: &'a Vec<LegacyLine>,
    diagnostics: &'a Vec<Error>,
    fragments: &'a Vec<ParseFragment>,
}
#[derive(Serialize)]
struct LegacyTrace {
    name: String,
    #[serde(with = "span_wire")]
    invocation_span: Span,
    replacement_chain: Vec<String>,
}
#[derive(Serialize)]
struct LegacyLine {
    #[serde(with = "span_wire")]
    output: Span,
    input: usize,
    traces: Vec<LegacyTrace>,
}
#[test]
fn parser_enrichment_shares_expansion_receipts_and_preserves_legacy_wire() {
    let source: crate::SourceText = "X".to_owned().into();
    let control: u128 = 7;
    let value = ExpansionRecord {
        key: framed_key(&source, control),
        source,
        control,
        text: "Ω".to_owned().into(),
        reads: Arc::new(vec![MacroRead {
            segment: 0,
            name: Arc::from("X"),
            definition: None,
        }]),
        locations: Arc::new(vec![(0, false, "12".into())]),
        lines: Arc::new(vec![Line {
            output_start: 0,
            output_end: 2,
            input: 0,
            traces: Box::new([Trace {
                name: 0,
                chain: 0,
                start: 0,
                end: 1,
            }]),
        }]),
        trace_tables: TraceTables {
            names: Box::new([Arc::from("X")]),
            chains: Box::new([Arc::from([Arc::from("X")])]),
        },
        diagnostics: Arc::new(vec![Error {
            input: 0,
            kind: DiagnosticKind::UserError,
            message: "fixture".into(),
        }]),
        fragments: vec![],
        rows: Default::default(),
    };
    let legacy_lines = value
        .lines
        .iter()
        .map(|line| LegacyLine {
            output: line.output(),
            input: line.input(),
            traces: line
                .traces
                .iter()
                .map(|trace| LegacyTrace {
                    name: value.trace_tables.name(trace).to_string(),
                    invocation_span: TraceTables::span(trace),
                    replacement_chain: value
                        .trace_tables
                        .chain(trace)
                        .iter()
                        .map(ToString::to_string)
                        .collect(),
                })
                .collect(),
        })
        .collect();
    let legacy = Legacy {
        key: value.key,
        source: value.source.clone(),
        control: value.control,
        text: value.text.clone(),
        reads: &value.reads,
        locations: &value.locations,
        lines: &legacy_lines,
        diagnostics: &value.diagnostics,
        fragments: &value.fragments,
    };
    let bytes = value.to_bytes().unwrap();
    assert_eq!(bytes, dm_wire::encode(EXPANSION_VERSION, &legacy).unwrap());
    assert_eq!(ExpansionRecord::from_bytes(&bytes).unwrap(), value);
    let enriched = value
        .with_fragment(9, Span::new(0, 2), Arc::from([1u8, 2]))
        .unwrap();
    assert!(Arc::ptr_eq(&value.reads, &enriched.reads));
    assert!(Arc::ptr_eq(&value.locations, &enriched.locations));
    assert!(Arc::ptr_eq(&value.lines, &enriched.lines));
    assert!(Arc::ptr_eq(&value.diagnostics, &enriched.diagnostics));
    assert!(value.fragments.is_empty());
    assert_eq!(
        enriched.fragment(9, Span::new(0, 2)),
        Some([1u8, 2].as_slice())
    );
    assert!(value.same_expansion(&enriched));
    // The existing storage visitor reports the same immutable nested allocations.
    let backing = value.trace_tables.chains[0][0].as_ptr() as usize;
    let mut seen = 0;
    for record in [&value, &enriched] {
        record.visit_storage(|view| {
        if matches!(view,super::storage::ExpansionStorageView::Text(text) if text.as_ptr() as usize==backing) {seen+=1;}
    });
    }
    assert_eq!(seen, 2);
}

#[test]
fn retained_trace_owners_share_capture_and_rebind_current_definition_origin() {
    use crate::regions::{
        expand_regions_text, expand_regions_text_with_memo, plan_regions, ExpansionMemo,
    };
    use std::{collections::BTreeMap, path::Path, sync::Mutex};
    struct Source(BTreeMap<std::path::PathBuf, String>);
    impl crate::SourceProvider for Source {
        fn read(&self, path: &Path) -> Result<String, String> {
            self.0
                .get(path)
                .cloned()
                .ok_or_else(|| format!("missing {path:?}"))
        }
    }
    #[derive(Default)]
    struct Memo(Mutex<Vec<Arc<ExpansionRecord>>>);
    impl ExpansionMemo for Memo {
        fn candidates(&self, _: u128) -> Vec<Arc<ExpansionRecord>> {
            self.0.lock().unwrap().clone()
        }
        fn insert(&self, record: Arc<ExpansionRecord>) {
            self.0.lock().unwrap().push(record);
        }
    }
    let sources = |prefix: &str| {
        Source(BTreeMap::from([
            (
                "probe.dme".into(),
                "#include \"defs.dm\"\n#include \"body.dm\"\n".into(),
            ),
            (
                "defs.dm".into(),
                format!("{prefix}#define OUTER INNER\n#define INNER 7\n"),
            ),
            (
                "body.dm".into(),
                "/proc/probe()\n    return OUTER + OUTER\n".into(),
            ),
        ]))
    };
    let first = plan_regions(Path::new("probe.dme"), &sources(""), &BTreeMap::new());
    let memo = Memo::default();
    let fresh = expand_regions_text_with_memo(&first, 1, &memo);
    let recorded = memo.0.lock().unwrap().clone();
    let traces = fresh
        .origins
        .iter()
        .find(|line| !line.macro_expansions.is_empty())
        .unwrap()
        .macro_expansions;
    let (stored_record, stored) = recorded
        .iter()
        .flat_map(|record| record.lines.iter().map(move |line| (record, line)))
        .find(|(_, line)| !line.traces.is_empty())
        .unwrap();
    let stored_name = stored_record.trace_tables.name(&stored.traces[0]);
    let stored_chain = stored_record.trace_tables.chain(&stored.traces[0]);
    assert!(Arc::ptr_eq(&traces[0].name, stored_name));
    assert!(Arc::ptr_eq(&traces[0].replacement_chain, stored_chain));
    // The observed definitions move; the reused body region's exact bytes do not.
    let current = plan_regions(Path::new("probe.dme"), &sources("\n\n"), &BTreeMap::new());
    let reused = expand_regions_text_with_memo(&current, 1, &memo);
    let expected = expand_regions_text(&current, 1);
    assert_eq!(expected.text, reused.text);
    assert_eq!(expected.diagnostics, reused.diagnostics);
    assert_eq!(
        format!("{:?}", expected.origins),
        format!("{:?}", reused.origins)
    );
    let hydrated = reused
        .origins
        .iter()
        .find(|line| !line.macro_expansions.is_empty())
        .unwrap()
        .macro_expansions;
    assert!(Arc::ptr_eq(stored_name, &hydrated[0].name));
    assert!(Arc::ptr_eq(stored_chain, &hydrated[0].replacement_chain));
    // Origin path is issued by the current segment definition, never by Trace.
    assert_eq!(
        hydrated[0].definition.as_ref().unwrap().path.as_ref(),
        Path::new("defs.dm")
    );
    assert_eq!(
        hydrated[0].definition.as_ref().unwrap().source_line,
        traces[0].definition.as_ref().unwrap().source_line + 2
    );
}
