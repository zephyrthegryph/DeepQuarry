use super::*;
#[derive(Serialize)]
struct Legacy<'a> {
    key: u128,
    #[serde(with = "source_wire")]
    source: crate::SourceText,
    control: Arc<[u8]>,
    #[serde(with = "source_wire")]
    text: crate::SourceText,
    reads: &'a Vec<MacroRead>,
    locations: &'a Vec<(usize, bool, String)>,
    lines: &'a Vec<Line>,
    diagnostics: &'a Vec<Error>,
    fragments: &'a Vec<ParseFragment>,
}
#[test]
fn parser_enrichment_shares_expansion_receipts_and_preserves_legacy_wire() {
    let source: crate::SourceText = "X".to_owned().into();
    let control: Arc<[u8]> = Arc::from(EXPANSION_VERSION.to_le_bytes());
    let value = ExpansionRecord {
        key: framed_key(&source, &control),
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
            output: Span::new(0, 2),
            input: 0,
            traces: vec![Trace {
                name: "X".into(),
                invocation_span: Span::new(0, 1),
                replacement_chain: vec!["X".into()],
            }],
        }]),
        diagnostics: Arc::new(vec![Error {
            input: 0,
            kind: DiagnosticKind::UserError,
            message: "fixture".into(),
        }]),
        fragments: vec![],
    };
    let legacy = Legacy {
        key: value.key,
        source: value.source.clone(),
        control: value.control.clone(),
        text: value.text.clone(),
        reads: &value.reads,
        locations: &value.locations,
        lines: &value.lines,
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
    let backing = value.lines[0].traces[0].replacement_chain[0].as_ptr() as usize;
    let mut seen = 0;
    for record in [&value, &enriched] {
        record.visit_storage(|view| {
        if matches!(view,super::storage::ExpansionStorageView::Buffer {address,..} if address==backing) {seen+=1;}
    });
    }
    assert_eq!(seen, 2);
}
