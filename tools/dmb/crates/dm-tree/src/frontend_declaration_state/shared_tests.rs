use super::*;
use std::{collections::BTreeMap, path::Path};
fn capture(state: &RetainedDeclarations, text: &str, offset: usize) -> CurrentContribution {
    let parsed = dm_syntax::parse_declaration_skeleton(text);
    let mut ast = AstFile {
        items: parsed.items,
        diagnostics: parsed.diagnostics,
        tokens: Vec::new(),
    };
    for item in &mut ast.items {
        super::super::items_spans(std::slice::from_mut(item), text, 0, offset).unwrap();
    }
    let mut facts = crate::from_ast(&ast, SymbolTable::default(), FileId(0), 0, 0).unwrap();
    let ledger = crate::allocation_ledger::capture(&ast.items, "/", &mut facts.symbols).unwrap();
    let key = RetainedDeclarations::key(text);
    let mut current = state
        .capture(&key, text, offset, ast.items, facts, ledger)
        .unwrap();
    state.adopt_authored(std::iter::once(&mut current)).unwrap();
    current
}
#[test]
fn shared_contribution_replays_exact_bytes_rebinds_offsets_and_releases_independent_claims() {
    let engine = Arc::new(crate::SharedNormalizedDeclarations::default());
    let a = RetainedDeclarations::with_shared_authored(Arc::clone(&engine));
    let b = RetainedDeclarations::with_shared_authored(engine);
    let text = "/obj/base\n    var/count = 1\n";
    let first = capture(&a, text, 0);
    let key = RetainedDeclarations::key(text);
    let shifted = b.get_shared(&key, text, 80).unwrap();
    assert!(Arc::ptr_eq(&first.value, &shifted.value));
    assert!(Arc::ptr_eq(&first.value.syntax, &shifted.value.syntax));
    assert!(Arc::ptr_eq(&first.value.facts, &shifted.value.facts));
    assert!(Arc::ptr_eq(
        &first.value.skeletons,
        &shifted.value.skeletons
    ));
    assert_ne!(first.offset, shifted.offset);
    assert!(b.get_shared(&key, &text.replace("1", "2"), 80).is_none());
    assert!(b.get_shared(&key, text, usize::MAX).is_none());
    // Failed current binding cannot leak the prior callback's accepted owner.
    let rebound = b.get_shared(&key, text, 91).unwrap();
    assert!(Arc::ptr_eq(&rebound.value, &first.value));
    assert_eq!(rebound.offset, 91);
    drop(rebound);

    let weak = Arc::downgrade(&first.value);
    a.clear();
    assert!(b.get_shared(&key, text, 90).is_some());
    drop(first);
    drop(shifted);
    b.clear();
    assert!(weak.upgrade().is_none());
}
struct Source(&'static str);
impl dm_preprocess::SourceProvider for Source {
    fn read(&self, _: &Path) -> Result<String, String> {
        Ok(self.0.into())
    }
}
#[test]
fn real_frontend_declaration_chunks_share_only_containing_region_sources() {
    struct CapturedSource(String);
    impl dm_preprocess::SourceProvider for CapturedSource {
        fn read(&self, _: &Path) -> Result<String, String> {
            Ok(self.0.clone())
        }
    }
    struct Memo;
    impl dm_preprocess::regions::ExpansionMemo for Memo {
        fn candidates(&self, _: u128) -> Vec<Arc<dm_preprocess::regions::ExpansionRecord>> {
            Vec::new()
        }
        fn insert(&self, _: Arc<dm_preprocess::regions::ExpansionRecord>) {}
    }
    let source = CapturedSource(
        (0..70)
            .map(|index| format!("/proc/probe_{index}()\n    return \"café {index}\"\n"))
            .collect(),
    );
    let executor = dm_exec::BuildExecutor::new(1).unwrap();
    let mut state = RetainedSemanticTree::new();
    let build = |state: &mut RetainedSemanticTree| {
        build_with_executor_and_semantic_state(
            Path::new("views.dme"),
            &source,
            &BTreeMap::new(),
            FrontendConfig {
                workers: 1,
                engine: None,
                observer: None,
            },
            Some(&Memo),
            &executor,
            Some(state),
        )
        .unwrap()
    };
    let current = build(&mut state);
    let regions: Vec<_> = current
        .expanded
        .receipts
        .iter()
        .map(|receipt| receipt.record().shared_output_text())
        .collect();
    assert!(!regions.is_empty());
    let mut shared = std::collections::HashSet::new();
    state.visit_declaration_storage(|view| {
        if let DeclarationStorageView::SharedEntry { contribution, .. } = view {
            if !shared.insert(contribution.allocation_address) {
                return;
            }
            assert!(
                regions.iter().any(|region| {
                    region
                        .find(contribution.source.as_ref())
                        .and_then(|start| {
                            region.checked_view(start..start + contribution.source.len())
                        })
                        .is_some_and(|view| view.same_view(contribution.source))
                }),
                "declaration bytes must share the containing region, not joined output"
            );
            assert!(!current.expanded.text.same_view(contribution.source));
        }
    });
    assert!(shared.len() > 1, "fixture must exercise region subranges");
    let fresh = build(&mut RetainedSemanticTree::new());
    assert_eq!(
        current.snapshot.tree.identity(),
        fresh.snapshot.tree.identity()
    );
    assert_eq!(
        current.snapshot.tree.declarations(),
        fresh.snapshot.tree.declarations()
    );
    assert_eq!(current.bodies.len(), fresh.bodies.len());
    for (a, b) in current.bodies.iter().zip(fresh.bodies.iter()) {
        assert_eq!(a.expanded_span, b.expanded_span);
        assert_eq!(a.source, b.source);
    }
}
#[test]
fn two_real_frontends_share_relative_payloads_and_issue_fresh_bodies() {
    let engine = Arc::new(crate::SharedNormalizedDeclarations::default());
    let mut a = RetainedSemanticTree::with_shared_normalized(Arc::clone(&engine));
    let mut b = RetainedSemanticTree::with_shared_normalized(engine);
    let executor = dm_exec::BuildExecutor::new(1).unwrap();
    let build = |state: &mut RetainedSemanticTree, path| {
        build_with_executor_and_semantic_state(
            Path::new(path),
            &Source("/obj/base\n    var/count = 1\n/proc/probe()\n    return 7\n"),
            &BTreeMap::new(),
            FrontendConfig {
                workers: 1,
                engine: None,
                observer: None,
            },
            None,
            &executor,
            Some(state),
        )
        .unwrap()
    };
    let first = build(&mut a, "a.dme");
    let second = build(&mut b, "b.dme");
    assert!(b.declaration_retention_stats().hits > 0);
    assert!(!Arc::ptr_eq(
        &first.snapshot.occurrences,
        &second.snapshot.occurrences
    ));
    assert!(BodyArena::new(&second)
        .with_parsed(&first.bodies[0], |_| ())
        .is_err());
    let views = |state: &RetainedSemanticTree| {
        let mut result = Vec::new();
        state.visit_declaration_storage(|view| {
            if let DeclarationStorageView::SharedEntry { contribution, .. } = view {
                result.push((
                    contribution.allocation_address,
                    Arc::as_ptr(contribution.syntax) as usize,
                    Arc::as_ptr(contribution.facts_owner) as usize,
                    Arc::as_ptr(contribution.skeletons) as usize,
                ));
            }
        });
        result.sort_unstable();
        result
    };
    assert!(!views(&a).is_empty());
    assert_eq!(views(&a), views(&b));
}

#[test]
fn failed_and_analysis_frontends_preserve_published_claims_and_rebind_fresh_origins() {
    let source = "/obj/base\n    var/count = 1\n/proc/probe()\n    return 7\n";
    let engine = Arc::new(crate::SharedNormalizedDeclarations::default());
    let mut state = RetainedSemanticTree::with_shared_normalized(engine);
    let executor = dm_exec::BuildExecutor::new(1).unwrap();
    let build = |state: &mut RetainedSemanticTree, path: &str, text: &'static str| {
        build_with_executor_and_semantic_state(
            Path::new(path),
            &Source(text),
            &BTreeMap::new(),
            FrontendConfig {
                workers: 1,
                engine: None,
                observer: None,
            },
            None,
            &executor,
            Some(state),
        )
    };
    let first_request = state.begin_declaration_request(true);
    let first = build(&mut state, "previous.dme", source).unwrap();
    assert!(first_request.publish_successful());
    drop(first_request);
    let failed = state.begin_declaration_request(true);
    assert!(build(
        &mut state,
        "failed.dme",
        "/obj/partial\n    var/other = 2\n#error deliberate frontend failure\n"
    )
    .is_err());
    drop(failed);
    let analysis = state.begin_declaration_request(false);
    build(
        &mut state,
        "analysis.dme",
        "/obj/analysis\n    var/temporary = 3\n",
    )
    .unwrap();
    assert!(!analysis.publish_successful());
    drop(analysis);
    let current_request = state.begin_declaration_request(true);
    let current = build(&mut state, "current.dme", source).unwrap();
    assert!(state.declaration_retention_stats().hits > 0);
    let fresh = build(&mut RetainedSemanticTree::new(), "current.dme", source).unwrap();
    assert_eq!(
        current.snapshot.tree.identity(),
        fresh.snapshot.tree.identity()
    );
    assert_eq!(
        current.snapshot.tree.declarations(),
        fresh.snapshot.tree.declarations()
    );
    assert_eq!(current.bodies.len(), fresh.bodies.len());
    for (actual, expected) in current.bodies.iter().zip(fresh.bodies.iter()) {
        assert_eq!(actual.expanded_span, expected.expanded_span);
        assert_eq!(actual.source, expected.source);
        assert_eq!(
            actual.setting_context_origins,
            expected.setting_context_origins
        );
        assert_eq!(actual.member, expected.member);
    }
    assert_eq!(
        current.bodies[0].source.path.file_name().unwrap(),
        "current.dme"
    );
    assert_eq!(
        first.bodies[0].source.path.file_name().unwrap(),
        "previous.dme"
    );
    assert!(BodyArena::new(&current)
        .with_parsed(&first.bodies[0], |_| ())
        .is_err());
    assert!(BodyArena::new(&current)
        .with_parsed(&current.bodies[0], |_| ())
        .is_ok());
    assert!(current_request.publish_successful());
}
