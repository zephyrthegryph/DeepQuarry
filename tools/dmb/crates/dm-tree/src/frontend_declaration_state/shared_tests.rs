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
