use super::*;

#[test]
fn issued_parser_fragments_replay_compact_settings_ranges_and_cross_include_grammar() {
    use dm_preprocess::regions::{
        expand_regions_text_with_memo, plan_regions, ExpansionMemo, ExpansionRecord,
    };
    use std::sync::{Arc, Mutex};
    #[derive(Default)]
    struct Memo(
        Mutex<BTreeMap<u128, Vec<Arc<ExpansionRecord>>>>,
        Mutex<BTreeMap<u128, Vec<Arc<dm_preprocess::regions::FragmentRecord>>>>,
    );
    impl ExpansionMemo for Memo {
        fn fragment_candidates(
            &self,
            key: u128,
        ) -> Vec<Arc<dm_preprocess::regions::FragmentRecord>> {
            self.1
                .lock()
                .unwrap()
                .get(&key)
                .cloned()
                .unwrap_or_default()
        }
        fn insert_fragment(&self, record: Arc<dm_preprocess::regions::FragmentRecord>) {
            self.1
                .lock()
                .unwrap()
                .entry(record.key())
                .or_default()
                .push(record);
        }
        fn candidates(&self, key: u128) -> Vec<Arc<ExpansionRecord>> {
            self.0
                .lock()
                .unwrap()
                .get(&key)
                .cloned()
                .unwrap_or_default()
        }
        fn insert(&self, record: Arc<ExpansionRecord>) {
            self.0
                .lock()
                .unwrap()
                .entry(record.key())
                .or_default()
                .push(record);
        }
    }
    let memo = Memo::default();
    let source=Memory(BTreeMap::from([(PathBuf::from("project.dme"),"/datum/probe\n    var/value = 3\n    proc/read(a)\n        if(1)\n            set waitfor = 0\n        return value + a\n".into())]));
    let plan = plan_regions(Path::new("project.dme"), &source, &BTreeMap::new());
    let expanded = expand_regions_text_with_memo(&plan, 2, &memo);
    let config = FrontendConfig {
        workers: 2,
        engine: None,
        observer: None,
    };
    let first = parse_declarations(&expanded, config, Some(&memo)).unwrap();
    assert!(!memo.1.lock().unwrap().is_empty());
    // A fresh expansion with no matching region memo still consumes the exact
    // chunk's independent facts. Its current global offset/provenance are fresh.
    memo.0.lock().unwrap().clear();
    let independent_expanded = expand_regions_text_with_memo(&plan, 1, &memo);
    let independent = parse_declarations(&independent_expanded, config, Some(&memo)).unwrap();
    assert_eq!(independent.reuse_stats.region_hits, 0);
    assert_eq!(independent.reuse_stats.independent_hits, 1);
    assert_eq!(independent.reuse_stats.facts_hits, 1);
    assert_eq!(independent.reuse_stats.parsed_chunks, 0);
    assert_eq!(independent.items, first.items);
    assert!(independent.adapted.skeletons == first.adapted.skeletons);
    assert_eq!(
        independent.allocation_ledger.events,
        first.allocation_ledger.events
    );
    // Independent hits do not enrich exact-region records: no reserialization.
    assert!(memo
        .0
        .lock()
        .unwrap()
        .values()
        .flatten()
        .all(|record| record
            .fragment(
                parserwire::VERSION,
                dm_syntax::Span::new(0, record.text().len())
            )
            .is_none()));
    // Restore exact-region enrichment for the remainder of this fixture.
    memo.1.lock().unwrap().clear();
    parse_declarations(&independent_expanded, config, Some(&memo)).unwrap();
    let reused = expand_regions_text_with_memo(&plan, 1, &memo);
    let receipt = &reused.receipts[0];
    assert!(receipt
        .record()
        .fragment(
            parserwire::VERSION,
            dm_syntax::Span::new(0, reused.text.len())
        )
        .is_some());
    let hit = parse_declarations(&reused, config, Some(&memo)).unwrap();
    assert_eq!(hit.reuse_stats.region_hits, 1);
    assert_eq!(hit.reuse_stats.facts_hits, 1);
    assert_eq!(hit.items, first.items);
    assert!(hit.adapted.skeletons == first.adapted.skeletons);
    assert_eq!(hit.adapted.origins, first.adapted.origins);
    assert_eq!(hit.allocation_ledger.events, first.allocation_ledger.events);
    assert_eq!(hit.diagnostics, first.diagnostics);
    assert_eq!(hit.items[0].children[1].children[0].header, "if(1)");
    // Invalid typed parser payload is a parse miss, without changing diagnostics.
    let poisoned = receipt
        .record()
        .with_fragment(
            parserwire::VERSION,
            dm_syntax::Span::new(0, reused.text.len()),
            Arc::from(b"{}".as_slice()),
        )
        .unwrap();
    memo.insert(Arc::new(poisoned));
    let repaired = expand_regions_text_with_memo(&plan, 2, &memo);
    let parsed = parse_declarations(&repaired, config, Some(&memo)).unwrap();
    assert_eq!(parsed.items, first.items);
    // The type block crosses the include boundary: only the joined grammar-safe
    // descriptor is parsed, never the included indented member as a root program.
    let cross = Memory(BTreeMap::from([
        (
            PathBuf::from("project.dme"),
            "/datum/probe\n#include \"member.dm\"\n".into(),
        ),
        (PathBuf::from("member.dm"), "    var/value = 7\n".into()),
    ]));
    let crossplan = plan_regions(Path::new("project.dme"), &cross, &BTreeMap::new());
    let expanded = expand_regions_text_with_memo(&crossplan, 2, &memo);
    let parsed = parse_declarations(&expanded, config, Some(&memo)).unwrap();
    assert_eq!(parsed.items.len(), 1);
    assert_eq!(parsed.items[0].children[0].header, "var/value = 7");
    for receipt in &expanded.receipts {
        assert!(receipt
            .record()
            .fragment(
                parserwire::VERSION,
                dm_syntax::Span::new(0, receipt.record().text().len())
            )
            .is_none());
    }
}

#[test]
fn cached_parser_errors_rebind_current_include_path_and_source_origin() {
    use dm_preprocess::regions::{ExpansionMemo, ExpansionRecord};
    use std::sync::{Arc, Mutex};
    #[derive(Default)]
    struct Memo(Mutex<BTreeMap<u128, Vec<Arc<ExpansionRecord>>>>);
    impl ExpansionMemo for Memo {
        fn candidates(&self, key: u128) -> Vec<Arc<ExpansionRecord>> {
            self.0
                .lock()
                .unwrap()
                .get(&key)
                .cloned()
                .unwrap_or_default()
        }
        fn insert(&self, record: Arc<ExpansionRecord>) {
            let mut records = self.0.lock().unwrap();
            let bucket = records.entry(record.key()).or_default();
            bucket.retain(|previous| !previous.same_expansion(&record));
            bucket.push(record);
        }
    }
    let memo = Memo::default();
    let config = FrontendConfig {
        workers: 2,
        engine: None,
        observer: None,
    };
    let old = Memory(BTreeMap::from([
        (PathBuf::from("project.dme"), "#include \"old.dm\"\n".into()),
        (PathBuf::from("old.dm"), "    datum/probe\n".into()),
    ]));
    let first = match build_with_expansion_memo(
        Path::new("project.dme"),
        &old,
        &BTreeMap::new(),
        config,
        Some(&memo),
    ) {
        Err(errors) => errors,
        Ok(_) => panic!("unexpected indentation must remain a source error"),
    };
    assert!(first
        .iter()
        .any(|error| error.stage == DiagnosticStage::Syntax
            && error.message == "unexpected indentation"));
    // Persist/reload the issued compact payload before moving its source path.
    {
        let mut records = memo.0.lock().unwrap();
        assert!(records.values().flatten().any(|record| record
            .fragment(
                parserwire::VERSION,
                dm_syntax::Span::new(0, record.text().len())
            )
            .is_some()));
        for bucket in records.values_mut() {
            for record in bucket {
                *record =
                    Arc::new(ExpansionRecord::from_bytes(&record.to_bytes().unwrap()).unwrap());
            }
        }
    }
    let moved = Memory(BTreeMap::from([
        (PathBuf::from("project.dme"), "#include \"new.dm\"\n".into()),
        (PathBuf::from("new.dm"), "    datum/probe\n".into()),
    ]));
    let reused = match build_with_expansion_memo(
        Path::new("project.dme"),
        &moved,
        &BTreeMap::new(),
        config,
        Some(&memo),
    ) {
        Err(errors) => errors,
        Ok(_) => panic!("cached diagnostics cannot admit malformed source"),
    };
    let cold = match build_with_config(Path::new("project.dme"), &moved, &BTreeMap::new(), config) {
        Err(errors) => errors,
        Ok(_) => panic!("cold diagnostics cannot admit malformed source"),
    };
    let projection = |errors: &[Diagnostic]| {
        errors
            .iter()
            .map(|error| {
                let origin = error
                    .location
                    .as_ref()
                    .expect("current syntax error origin");
                (
                    error.kind,
                    error.stage,
                    error.message.clone(),
                    origin.path.clone(),
                    origin.semantic_path.clone(),
                    origin.line,
                    origin.span.start,
                    origin.span.end,
                    origin.include_occurrence,
                    origin.include_chain.clone(),
                    format!("{:?}", origin.macro_expansions),
                )
            })
            .collect::<Vec<_>>()
    };
    assert_eq!(projection(&reused), projection(&cold));
    let origin = reused
        .iter()
        .find(|error| error.message == "unexpected indentation")
        .unwrap()
        .location
        .as_ref()
        .unwrap();
    assert_eq!(origin.path.as_path(), Path::new("new.dm"));
    assert_eq!(origin.line, 1);
    assert_ne!(origin.path.as_path(), Path::new("old.dm"));
}
