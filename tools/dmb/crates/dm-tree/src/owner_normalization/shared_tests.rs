use crate::frontend::{
    build_with_executor_and_semantic_state, BodyArena, FrontendConfig, RetainedSemanticTree,
};
use crate::*;
use std::{collections::BTreeMap, path::Path};
struct Source(&'static str);
impl dm_preprocess::SourceProvider for Source {
    fn read(&self, _: &Path) -> Result<String, String> {
        Ok(self.0.into())
    }
}
#[test]
fn shared_normalization_rebinds_two_current_frontends_and_keeps_read_variants_separate() {
    let shared = Arc::new(SharedNormalizedDeclarations::default());
    let mut a = RetainedSemanticTree::with_shared_normalized(Arc::clone(&shared));
    let mut b = RetainedSemanticTree::with_shared_normalized(Arc::clone(&shared));
    let mut c = RetainedSemanticTree::with_shared_normalized(shared);
    let executor = dm_exec::BuildExecutor::new(1).unwrap();
    let build = |state: &mut RetainedSemanticTree, path: &str, source| {
        build_with_executor_and_semantic_state(
            Path::new(path),
            &Source(source),
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
    let first = build(&mut a, "first.dme", original);
    let shifted = build(&mut b, "second.dme", "// shift\n/obj/unrelated\n    var/extra = 0\n/obj/base\n    var/count = 1\n/proc/probe()\n    return 7\n");
    let member = |tree: &SemanticTree| {
        tree.resolve(
            tree.lookup_type(dm_ir::SymbolId::of("/obj/base")).unwrap(),
            dm_ir::SymbolId::of("count"),
            MemberKind::Var,
        )
        .unwrap()
    };
    let left = member(&first.snapshot.tree);
    let right = member(&shifted.snapshot.tree);
    assert_ne!(
        left, right,
        "shared rows must bind to fresh dense member IDs"
    );
    assert!(Arc::ptr_eq(
        &first.snapshot.tree.members[left.index()].metadata,
        &shifted.snapshot.tree.members[right.index()].metadata
    ));
    assert!(b.normalization_hits() > 0);
    assert!(!Arc::ptr_eq(
        &first.snapshot.occurrences,
        &shifted.snapshot.occurrences
    ));
    let arena = BodyArena::new(&shifted);
    assert!(arena.with_parsed(&first.bodies[0], |_| ()).is_err());
    assert!(arena.with_parsed(&shifted.bodies[0], |_| ()).is_ok());
    let changed = build(
        &mut c,
        "changed.dme",
        "/obj/base\n    var/count = 2\n/proc/probe()\n    return 7\n",
    );
    let changed_id = member(&changed.snapshot.tree);
    assert!(!Arc::ptr_eq(
        &first.snapshot.tree.members[left.index()].metadata,
        &changed.snapshot.tree.members[changed_id.index()].metadata
    ));
    drop(c);
    a.clear();
    let again = build(&mut a, "third.dme", original);
    assert!(
        a.normalization_hits() > 0,
        "other host lease preserves original exact variant"
    );
    assert!(Arc::ptr_eq(
        &again.snapshot.tree.members[member(&again.snapshot.tree).index()].metadata,
        &first.snapshot.tree.members[left.index()].metadata
    ));
}
