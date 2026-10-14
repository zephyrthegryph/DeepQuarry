use super::*;
use dm_ir::{FileId, SymbolId, SymbolTable};

fn adapted(source: &str) -> crate::SharedAdaptedDeclarations {
    crate::adapter::from_ast(
        &dm_syntax::parse(source),
        SymbolTable::default(),
        FileId(0),
        0,
        0,
    )
    .unwrap()
    .into()
}

#[test]
fn standalone_symbol_admission_shares_text_and_rejects_changed_same_size_catalog() {
    let executor = dm_exec::BuildExecutor::new(1).unwrap();
    let mut state = RetainedSemanticTree::new();
    let input = adapted("/datum/base\n    var/count = 1\n");
    let mut spellings = std::collections::BTreeMap::new();
    input.symbols.visit_storage(|id, text| {
        spellings.insert(id, Arc::clone(text));
    });
    let first = state.resolve(input, None, |_, _, _| {}, &executor).unwrap();
    let retained = state.retained_symbol_owner().unwrap();
    retained.visit_storage(|id, text| {
        assert!(
            Arc::ptr_eq(text, &spellings[&id]),
            "fallback must share spelling allocations"
        );
    });
    let second = state
        .resolve(
            adapted("/datum/base\n    var/count = 1\n"),
            None,
            |_, _, _| {},
            &executor,
        )
        .unwrap();
    assert!(Arc::ptr_eq(&first.tree, &second.tree));
    assert_eq!(state.hits(), 1);
    let third = state
        .resolve(
            adapted("/datum/base\n    var/count = 2\n"),
            None,
            |_, _, _| {},
            &executor,
        )
        .unwrap();
    assert!(!Arc::ptr_eq(&second.tree, &third.tree));
    assert!(state
        .retained_symbol_owner()
        .unwrap()
        .text(SymbolId::of("2"))
        .is_some());
    let mut fresh = RetainedSemanticTree::new();
    let expected = fresh
        .resolve(
            adapted("/datum/base\n    var/count = 2\n"),
            None,
            |_, _, _| {},
            &executor,
        )
        .unwrap();
    assert_eq!(third.tree.identity(), expected.tree.identity());
}

#[test]
fn production_catalog_admission_retains_existing_owner() {
    struct Source;
    impl dm_preprocess::SourceProvider for Source {
        fn read(&self, _: &std::path::Path) -> Result<String, String> {
            Ok("/datum/base\n    var/count = 1\n".into())
        }
    }
    let executor = dm_exec::BuildExecutor::new(1).unwrap();
    let mut state = RetainedSemanticTree::new();
    crate::frontend::build_with_executor_and_semantic_state(
        std::path::Path::new("symbols.dme"),
        &Source,
        &Default::default(),
        crate::frontend::FrontendConfig {
            workers: 1,
            engine: None,
            observer: None,
        },
        None,
        &executor,
        Some(&mut state),
    )
    .unwrap();
    let entry = state.entry.as_ref().unwrap();
    let catalog = entry
        .symbol_catalog
        .as_ref()
        .expect("production must issue a symbol catalog");
    assert!(Arc::ptr_eq(&entry.symbols, &catalog.symbols));
}
