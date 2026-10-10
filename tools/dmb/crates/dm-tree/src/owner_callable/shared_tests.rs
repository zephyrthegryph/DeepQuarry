use super::*;
use crate::frontend::{
    build_with_executor_and_semantic_state, FrontendConfig, RetainedSemanticTree,
};
use std::path::Path;
struct Source(&'static str);
impl dm_preprocess::SourceProvider for Source {
    fn read(&self, _: &Path) -> Result<String, String> {
        Ok(self.0.into())
    }
}
fn anchor(state: &RetainedSemanticTree) -> Arc<CallableOwner> {
    let mut result = None;
    state.visit_callable_owner_storage(|view| {
        if let ObservedArtifactStorageView::Entry { value, .. } = view {
            if value
                .anchors
                .iter()
                .any(|(name, _)| *name == SymbolId::of("probe"))
            {
                result = Some(Arc::clone(value));
            }
        }
    });
    result.expect("probe callable owner")
}
#[test]
fn two_frontends_share_exact_callable_owner_and_keep_changed_variants_independent() {
    let shared = Arc::new(crate::SharedNormalizedDeclarations::default());
    let mut a = RetainedSemanticTree::with_shared_normalized(Arc::clone(&shared));
    let mut b = RetainedSemanticTree::with_shared_normalized(Arc::clone(&shared));
    let mut c = RetainedSemanticTree::with_shared_normalized(shared);
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
    let first = build(&mut a, "a.dme", "/obj/base/proc/probe()\n    return 1\n");
    let original = anchor(&a);
    let shifted = build(
        &mut b,
        "b.dme",
        "// shifted\n/obj/base/proc/probe()\n    return 2\n",
    );
    assert!(Arc::ptr_eq(&original, &anchor(&b)));
    assert!(!Arc::ptr_eq(
        &first.snapshot.occurrences,
        &shifted.snapshot.occurrences
    ));
    let _changed = build(
        &mut c,
        "c.dme",
        "/obj/base/proc/probe()\n    return 1\n/obj/base/proc/other()\n    return 3\n",
    );
    // The visitor exposes the whole shared core, so locate the changed exact roster.
    let mut changed = None;
    c.visit_callable_owner_storage(|view| {
        if let ObservedArtifactStorageView::Entry { value, .. } = view {
            if value
                .anchors
                .iter()
                .any(|(name, _)| *name == SymbolId::of("other"))
            {
                changed = Some(Arc::clone(value));
            }
        }
    });
    let changed = changed.unwrap();
    assert!(!Arc::ptr_eq(&original, &changed));
    let weak = Arc::downgrade(&changed);
    drop(changed);
    drop(c);
    assert!(weak.upgrade().is_none());
    a.clear();
    let _again = build(
        &mut a,
        "again.dme",
        "/obj/base/proc/probe()\n    return 9\n",
    );
    assert!(Arc::ptr_eq(&original, &anchor(&a)));
}
