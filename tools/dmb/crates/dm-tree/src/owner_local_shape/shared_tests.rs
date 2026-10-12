use super::*;
use crate::frontend::{
    build_with_executor_and_semantic_state, BodyArena, FrontendConfig, RetainedSemanticTree,
};
use std::path::Path;

fn member(owner: SymbolId, name: SymbolId) -> Skeleton {
    Skeleton::Member {
        owner,
        name,
        kind: MemberKind::Var,
        mode: DefinitionMode::Declare,
        metadata: Arc::new(MemberMetadata::default()),
        content: 0,
    }
}

#[test]
fn two_frontends_share_exact_local_shapes_and_bind_fresh_dense_members() {
    struct Source(&'static str);
    impl dm_preprocess::SourceProvider for Source {
        fn read(&self, _: &Path) -> Result<String, String> {
            Ok(self.0.into())
        }
    }
    let shared = Arc::new(crate::SharedNormalizedDeclarations::default());
    let mut a = RetainedSemanticTree::with_shared_normalized(Arc::clone(&shared));
    let mut b = RetainedSemanticTree::with_shared_normalized(shared);
    let executor = dm_exec::BuildExecutor::new(1).unwrap();
    let build = |state: &mut RetainedSemanticTree, path: &str, text| {
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
        .unwrap()
    };
    let original = "/obj/base\n    var/count = 1\n/proc/probe()\n    return 7\n";
    let shifted = "// shifted root\n/obj/unrelated\n    var/extra = 0\n/obj/base\n    var/count = 1\n/proc/probe()\n    return 7\n";
    let first = build(&mut a, "first.dme", original);
    let owner = SymbolId::of("/obj/base");
    let rows = |state: &RetainedSemanticTree| {
        let mut payloads = Vec::new();
        state.visit_local_shape_storage(|view| {
            if let LocalShapeStorageView::Payload { rows, .. } = view {
                if rows.iter().flatten().any(|row| row.key.owner == owner) {
                    payloads.push(Arc::clone(rows));
                }
            }
        });
        assert_eq!(payloads.len(), 1, "one exact shared source-shape variant");
        payloads.pop().unwrap()
    };
    let original_rows = rows(&a);
    let second = build(&mut b, "second.dme", shifted);
    assert!(b.local_shape_hits() > 0);
    assert!(Arc::ptr_eq(&original_rows, &rows(&b)));
    let selected = |tree: &SemanticTree| {
        tree.resolve(
            tree.lookup_type(owner).unwrap(),
            SymbolId::of("count"),
            MemberKind::Var,
        )
        .unwrap()
    };
    assert_ne!(
        selected(&first.snapshot.tree),
        selected(&second.snapshot.tree)
    );
    assert!(!Arc::ptr_eq(
        &first.snapshot.occurrences,
        &second.snapshot.occurrences
    ));
    assert!(BodyArena::new(&second)
        .with_parsed(&first.bodies[0], |_| ())
        .is_err());
    assert!(BodyArena::new(&second)
        .with_parsed(&second.bodies[0], |_| ())
        .is_ok());
    a.clear();
    let again = build(&mut a, "third.dme", original);
    assert!(
        a.local_shape_hits() > 0,
        "fresh host keeps its engine-scoped shape lease"
    );
    assert!(Arc::ptr_eq(&original_rows, &rows(&a)));
    let fresh = build(&mut RetainedSemanticTree::new(), "third.dme", original);
    assert_eq!(
        again.snapshot.tree.identity(),
        fresh.snapshot.tree.identity()
    );
    assert_eq!(
        again.snapshot.tree.declarations(),
        fresh.snapshot.tree.declarations()
    );
}

#[test]
fn asymmetric_shape_edits_keep_sibling_variant_and_release_last_lease() {
    let shared = Arc::new(crate::SharedNormalizedDeclarations::default());
    let a = RetainedOwnerShapes::with_shared(Arc::clone(&shared));
    let b = RetainedOwnerShapes::with_shared(Arc::clone(&shared));
    let mut symbols = SymbolTable::default();
    let owner = symbols.intern("/obj").unwrap();
    let count = symbols.intern("count").unwrap();
    let extra = symbols.intern("extra").unwrap();
    let tree = crate::build(symbols, &[]).unwrap();
    let kinds = callable_namespace::CallableKinds::default();
    let original = vec![member(owner, count)];
    let (declarations, _) = KeyedDeclarations::capture(None, &original).unwrap();
    let first = a.prepare(&tree, &declarations, &kinds);
    let sibling = b.prepare(&tree, &declarations, &kinds);
    assert!(Arc::ptr_eq(&first[&owner], &sibling[&owner]));
    let previous = Arc::downgrade(&first[&owner]);
    let changed = vec![original[0].clone(), member(owner, extra)];
    let (edited, _) = KeyedDeclarations::capture(Some(&declarations), &changed).unwrap();
    let current = b.prepare(&tree, &edited, &kinds);
    assert!(!Arc::ptr_eq(&first[&owner], &current[&owner]));
    assert_eq!(current[&owner].rows.len(), 2);
    let unchanged = a.prepare(&tree, &declarations, &kinds);
    assert!(Arc::ptr_eq(&first[&owner], &unchanged[&owner]));
    let latest = Arc::downgrade(&current[&owner]);
    drop(first);
    drop(sibling);
    drop(unchanged);
    assert!(
        previous.upgrade().is_some(),
        "sibling lease retains exact old variant"
    );
    drop(a);
    assert!(
        previous.upgrade().is_none(),
        "last old claim releases old backing"
    );
    drop(current);
    assert!(latest.upgrade().is_some());
    drop(b);
    assert!(
        latest.upgrade().is_none(),
        "engine registry cannot pin unclaimed shapes"
    );
    drop(shared);
}

#[test]
fn shared_shape_negative_name_reads_replay_each_current_catalog() {
    let shared = Arc::new(crate::SharedNormalizedDeclarations::default());
    let a = RetainedOwnerShapes::with_shared(Arc::clone(&shared));
    let b = RetainedOwnerShapes::with_shared(shared);
    let mut symbols = SymbolTable::default();
    let owner = symbols.intern("/obj").unwrap();
    let absent = SymbolId::of("missing");
    let (declarations, _) = KeyedDeclarations::capture(None, &[member(owner, absent)]).unwrap();
    let before = crate::build(symbols.clone(), &[]).unwrap();
    let kinds = callable_namespace::CallableKinds::default();
    let first = a.prepare(&before, &declarations, &kinds);
    let sibling = b.prepare(&before, &declarations, &kinds);
    assert!(Arc::ptr_eq(&first[&owner], &sibling[&owner]));
    assert!(matches!(first[&owner].first_failure,
        Some((_, LocalValidationFailure::UnknownSymbol(name))) if name == absent));
    symbols.intern("missing").unwrap();
    let changed = crate::build(symbols, &[]).unwrap();
    let repaired = b.prepare(&changed, &declarations, &kinds);
    assert!(repaired[&owner].first_failure.is_none());
    assert!(!Arc::ptr_eq(&first[&owner], &repaired[&owner]));
    let untouched = a.prepare(&before, &declarations, &kinds);
    assert!(Arc::ptr_eq(&first[&owner], &untouched[&owner]));
    assert!(matches!(untouched[&owner].first_failure,
        Some((_, LocalValidationFailure::UnknownSymbol(name))) if name == absent));
}
