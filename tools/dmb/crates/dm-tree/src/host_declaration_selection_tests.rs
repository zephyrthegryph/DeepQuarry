use super::*;
use crate::frontend::{
    build_with_executor_and_semantic_state, ColdFrontend, FrontendConfig, RetainedSemanticTree,
};
struct Source(&'static str);
impl dm_preprocess::SourceProvider for Source {
    fn read(&self, _: &std::path::Path) -> Result<String, String> {
        Ok(self.0.into())
    }
}
fn build(text: &'static str, state: Option<&mut RetainedSemanticTree>) -> ColdFrontend {
    let executor = dm_exec::BuildExecutor::new(1).unwrap();
    build_with_executor_and_semantic_state(
        std::path::Path::new("selection.dme"),
        &Source(text),
        &Default::default(),
        FrontendConfig {
            workers: 1,
            engine: None,
            observer: None,
        },
        None,
        &executor,
        state,
    )
    .unwrap()
}
fn check(tree: &SemanticTree) {
    let callables = tree
        .host_declaration_selections()
        .flat_map(|(_, row)| row.callable_names.iter().copied())
        .collect::<std::collections::BTreeSet<_>>();
    let variables = tree
        .host_declaration_selections()
        .flat_map(|(_, row)| row.declared_variable_names.iter().copied())
        .collect::<std::collections::BTreeSet<_>>();
    let scalars = tree
        .host_declaration_selections()
        .flat_map(|(_, row)| row.scalar_requests.iter().copied())
        .collect::<std::collections::BTreeSet<_>>();
    let old_callables: std::collections::BTreeSet<_> = tree
        .members()
        .iter()
        .filter(|member| matches!(member.kind, MemberKind::Proc | MemberKind::Verb))
        .map(|member| member.name)
        .collect();
    let old_variables: std::collections::BTreeSet<_> = tree
        .members()
        .iter()
        .filter(|member| {
            member.kind == MemberKind::Var && member.definition == DefinitionMode::Declare
        })
        .map(|member| member.name)
        .collect();
    let old_scalars: std::collections::BTreeSet<_> = tree
        .members()
        .iter()
        .filter(|member| member.kind == MemberKind::Var && member.metadata.flags & 2 != 0)
        .map(|member| constant_resolution::ScalarQuery::Const {
            owner: tree.type_node(member.owner).unwrap().path,
            name: member.name,
        })
        .collect();
    assert_eq!(callables, old_callables);
    assert_eq!(variables, old_variables);
    assert_eq!(scalars, old_scalars);
}
#[test]
fn final_host_selections_match_legacy_scans_for_flags_inheritance_and_shadowing() {
    let mut state = RetainedSemanticTree::new();
    for source in [
        "/datum/base\n    var/const/value = 1\n    proc/action()\n        return 1\n/datum/base/child\n    value = 2\n    action()\n        return 2\n",
        "/datum/base\n    var/value = 1\n    proc/action()\n        return 1\n/datum/base/child\n    value = 2\n    action()\n        return 2\n",
        "var/const/shadow = 1\n/datum/base\n    var/value = 1\n    proc/action()\n        return 1\n/datum/base/child\n    value = 2\n    var/shadow = 4\n    action()\n        return 2\n    proc/added()\n        return 3\n",
    ] {
        let current=build(source,Some(&mut state));let fresh=build(source,None);
        check(&current.snapshot.tree);check(&fresh.snapshot.tree);
        assert_eq!(current.snapshot.tree.host_declaration_selection_storage(),fresh.snapshot.tree.host_declaration_selection_storage());
        let child=current.snapshot.tree.host_declaration_selections().find(|(owner,_)|*owner==SymbolId::of("/datum/base/child")).unwrap().1;
        if source.contains("var/const/value") {assert!(child.scalar_requests.iter().any(|query|*query==constant_resolution::ScalarQuery::Const {owner:SymbolId::of("/datum/base/child"),name:SymbolId::of("value")}));}
        else {assert!(!child.scalar_requests.iter().any(|query|*query==constant_resolution::ScalarQuery::Const {owner:SymbolId::of("/datum/base/child"),name:SymbolId::of("value")}));}
    }
}
#[test]
fn untouched_owner_selection_shares_artifact_across_other_owner_structure_edits() {
    let mut state = RetainedSemanticTree::new();
    let before = build(
        "/datum/one\n    var/const/value = 1\n/datum/two\n    var/other = 2\n",
        Some(&mut state),
    );
    let after=build("/datum/one\n    var/const/value = 1\n/datum/two\n    var/other = 2\n    proc/added()\n        return 2\n",Some(&mut state));
    let owner = SymbolId::of("/datum/one");
    assert!(Arc::ptr_eq(
        &before.snapshot.tree.host_declaration_selection_storage()[&owner],
        &after.snapshot.tree.host_declaration_selection_storage()[&owner]
    ));
    assert!(!Arc::ptr_eq(
        &before.snapshot.occurrences,
        &after.snapshot.occurrences
    ));
    check(&after.snapshot.tree);
}
