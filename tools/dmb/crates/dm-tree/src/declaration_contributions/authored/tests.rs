use crate::frontend::{
    build_with_executor_and_semantic_state, BodyArena, FrontendConfig, RetainedSemanticTree,
};
use crate::*;
use std::{collections::BTreeMap, path::Path, sync::Arc};
struct Source(&'static str);
impl dm_preprocess::SourceProvider for Source {
    fn read(&self, _: &Path) -> Result<String, String> {
        Ok(self.0.into())
    }
}
fn meanings(state: &RetainedSemanticTree) -> Vec<Arc<dm_ir::DeclarationMeaning>> {
    let mut values = Vec::new();
    state.visit_declaration_storage(|view| {
        if let frontend::DeclarationStorageView::Entry { contribution, .. }
        | frontend::DeclarationStorageView::SharedEntry { contribution, .. } = view
        {
            for skeleton in contribution.skeletons.iter() {
                if let Skeleton::Member { metadata, .. } = skeleton {
                    values.push(Arc::clone(metadata));
                }
            }
        }
    });
    values
}
#[test]
fn shared_authored_rows_adopt_retained_skeletons_without_reusing_current_issuance() {
    let shared = Arc::new(SharedNormalizedDeclarations::default());
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
    let text = "/obj/base\n    var/count = 1\n/proc/probe()\n    return 7\n";
    let first = build(&mut a, "first.dme", text);
    let second = build(
        &mut b,
        "second.dme",
        "// shift\n/obj/base\n    var/count = 1\n/proc/probe()\n    return 9\n",
    );
    let left = meanings(&a);
    let right = meanings(&b);
    assert!(!left.is_empty());
    for value in &left {
        assert!(
            right
                .iter()
                .any(|other| value.as_ref() == other.as_ref() && Arc::ptr_eq(value, other)),
            "retained contribution must adopt exact metadata owner"
        );
    }
    let owner = dm_ir::SymbolId::of("/obj/base");
    assert!(Arc::ptr_eq(
        a.retained_declaration_index()
            .unwrap()
            .owner(owner)
            .unwrap(),
        b.retained_declaration_index()
            .unwrap()
            .owner(owner)
            .unwrap()
    ));
    assert!(!Arc::ptr_eq(
        &first.snapshot.occurrences,
        &second.snapshot.occurrences
    ));
    assert!(BodyArena::new(&second)
        .with_parsed(&first.bodies[0], |_| ())
        .is_err());
    let _changed = build(
        &mut c,
        "changed.dme",
        "/obj/base\n    var/count = 2\n/proc/probe()\n    return 7\n",
    );
    assert!(!Arc::ptr_eq(
        a.retained_declaration_index()
            .unwrap()
            .owner(owner)
            .unwrap(),
        c.retained_declaration_index()
            .unwrap()
            .owner(owner)
            .unwrap()
    ));
    drop(c);
    a.clear();
    let _again = build(&mut a, "again.dme", text);
    assert!(Arc::ptr_eq(
        a.retained_declaration_index()
            .unwrap()
            .owner(owner)
            .unwrap(),
        b.retained_declaration_index()
            .unwrap()
            .owner(owner)
            .unwrap()
    ));
}
