use super::*;
#[path = "../examples/support/reference_hierarchy.rs"]
mod reference_hierarchy;
use std::path::Path;
use std::sync::Arc;
struct Source(dm_preprocess::AcquiredSource);
impl dm_preprocess::SourceProvider for Source {
    fn read(&self, _: &Path) -> Result<String, String> {
        Err("test requires actual original bytes".into())
    }
    fn acquired_source(&self, _: &Path) -> Result<Option<dm_preprocess::AcquiredSource>, String> {
        Ok(Some(self.0.clone()))
    }
    fn source_acquisition(
        &self,
        _: &Path,
        text: &dm_preprocess::SourceText,
    ) -> Option<dm_preprocess::AcquiredSource> {
        self.0
            .lease()
            .source_text()
            .same_view(text)
            .then(|| self.0.clone())
    }
}
fn input(source: &'static str, certified: bool) -> (std::path::PathBuf, PolicyInputs) {
    input_with_primary(source, certified, false)
}
fn input_with_primary(
    source: &'static str,
    certified: bool,
    primary: bool,
) -> (std::path::PathBuf, PolicyInputs) {
    use crate::policy_inputs::{HostCapture, PolicyRole};
    let root = std::env::current_dir()
        .unwrap()
        .join("member-native-fixture");
    let seed = reference_hierarchy::seed();
    let provider = Source(dm_preprocess::AcquiredSource::from_original_bytes(
        source.as_bytes().to_vec(),
        (),
    ));
    let executor = dm_exec::BuildExecutor::new(1).unwrap();
    let frontend = dm_tree::frontend::build_with_executor_and_semantic_state_for_policy(
        &root.join("code/probe.dm"),
        &provider,
        &Default::default(),
        dm_tree::frontend::FrontendConfig {
            workers: 1,
            engine: certified.then_some(&seed),
            observer: None,
        },
        None,
        &executor,
        None,
        primary,
    )
    .unwrap();
    let raw = frontend
        .files
        .iter()
        .filter(|f| f.captured)
        .map(|f| {
            HostCapture::analyze_raw(Arc::clone(&f.path), PolicyRole::DmSource, {
                let raw = f.text.replace("\r\n", "\n").replace('\r', "\n");
                if raw == f.text.as_str() {
                    f.text.clone()
                } else {
                    raw.into()
                }
            })
        })
        .collect::<Vec<_>>();
    (root, PolicyInputs::capture(&frontend, raw).unwrap())
}
#[test]
fn declared_receivers_are_typed_but_returns_and_indexes_remain_untyped() {
    let(root,input)=input("/datum/static_owner\n    var/static/danger\n/datum/typed\n    var/danger\n/proc/make()\n    return new /datum/typed\n/proc/check(holder, datum/typed/typed, list/items)\n    holder.danger\n    typed.danger\n    make().danger\n    items[1].danger\n    (new /datum/typed).danger\n",true);
    let rows = findings(&input, &root, |_| false, || Ok(())).unwrap();
    assert_eq!(rows.iter().map(|r| r.line).collect::<Vec<_>>(), [8, 10, 11]);
}
#[test]
fn unknown_builtin_ancestry_refuses_instead_of_certifying_empty_static_universe() {
    let (root, input) = input("/proc/check(holder)\n    holder.danger\n", false);
    assert!(findings(&input, &root, |_| false, || Ok(())).is_err());
}
#[test]
fn else_if_header_uses_the_legacy_first_if_statement_origin() {
    let(root,input)=input("/datum/static_owner\n    var/static/danger\n/proc/check(holder)\n    if(holder.danger)\n        return\n    else if(holder.danger)\n        return\n",true);
    let rows = findings(&input, &root, |_| false, || Ok(())).unwrap();
    assert_eq!(rows.iter().map(|r| r.line).collect::<Vec<_>>(), [4]);
}
#[test]
fn cancellation_drops_the_complete_policy_result() {
    let (root, input) = input(
        "/datum/static_owner\n    var/static/danger\n/proc/check(holder)\n    holder.danger\n",
        true,
    );
    assert!(findings(&input, &root, |_| false, || Err("cancelled".into())).is_err());
}

#[test]
fn constructor_target_member_is_not_a_read_but_argument_member_is() {
    let(root,input)=input("/datum/static_owner\n    var/static/danger\n/proc/check(holder)\n    new holder.danger()\n    new holder.danger(\n        holder.danger)\n",true);
    let rows = findings(&input, &root, |_| false, || Ok(())).unwrap();
    assert_eq!(rows.iter().map(|r| r.line).collect::<Vec<_>>(), [5]);
}

#[test]
fn physical_statement_origin_is_not_a_nested_member_expression_line() {
    let(root,input)=input("/datum/static_owner\r\n    var/static/danger\r\n/proc/check(holder)\r\n    for(var/i=0;\r\n        holder.danger;\r\n        i++)\r\n        return\r\n",true);
    let rows = findings(&input, &root, |_| false, || Ok(())).unwrap();
    assert_eq!(rows.iter().map(|row| row.line).collect::<Vec<_>>(), [4]);
}
#[test]
fn macro_statement_needs_producer_line_receipt() {
    let(root,input)=input("#define READ(x) x.danger\n/datum/static_owner\n    var/static/danger\n/proc/check(holder)\n    READ(holder)\n",true);
    let rows = findings(&input, &root, |_| false, || Ok(())).unwrap();
    assert_eq!(rows.iter().map(|row| row.line).collect::<Vec<_>>(), [5]);
}

#[test]
fn scoped_values_have_no_declared_receiver_and_proc_reference_arguments_are_not_evaluated() {
    let(root,input)=input("/datum/static_owner\n    var/static/danger\n    var/static/ignored_danger\n    var/static/payload\n    proc/method()\n        return\n/proc/check(holder)\n    (/datum/static_owner::payload).danger\n    (/datum/static_owner::method(holder.ignored_danger))\n",true);
    let rows = findings(&input, &root, |_| false, || Ok(())).unwrap();
    assert_eq!(
        rows.iter()
            .map(|row| (row.line, row.name.as_str()))
            .collect::<Vec<_>>(),
        [(8, "danger")]
    );
}

#[test]
fn static_universe_uses_pinned_dsl_not_empty_runtime_seed_and_explicit_modifiers_only() {
    let(_,inputs)=input("var/implicit_root\nvar/global/explicit_global\nvar/static/explicit_static\nvar/const/constant = 1\nvar/tmp/temporary\n/datum/holder\n    var/global/member_global\n    var/static/member_static\n    var/ordinary\n/proc/check(holder)\n    holder.explicit_global\n",true);
    let tree = inputs.archive().tree();
    let profile = tree.checker_builtin_profile().unwrap();
    let names = static_names(tree, profile).unwrap();
    for name in [
        "world",
        "explicit_global",
        "explicit_static",
        "member_global",
        "member_static",
    ] {
        assert!(
            names.contains(name),
            "pinned checker/static declaration absent: {name}"
        );
    }
    for name in ["implicit_root", "constant", "temporary", "ordinary"] {
        assert!(
            !names.contains(name),
            "global storage is not an explicit STATIC flag: {name}"
        );
    }
    assert!(!reference_hierarchy::MEMBER_INVENTORY_COMPLETE);
    assert!(reference_hierarchy::seed().fields.is_empty());
    let catalog = dm_tree::checker_builtins::pinned_catalog().unwrap();
    assert_eq!(catalog.declarations.len(), 822);
    assert_eq!(
        catalog
            .declarations
            .iter()
            .filter(|row| row.kind == MemberKind::Var)
            .count(),
        444
    );
}
#[test]
fn authored_formal_replaces_builtin_flag_but_value_override_preserves_formal() {
    let(_,inputs)=input("var/world\nworld = null\n/datum/base\n    var/static/kept = 1\n    var/ordinary = 1\n/datum/base\n    kept = 2\n    ordinary = 2\n/datum/base/child\n    kept = 3\n/proc/check(holder)\n    holder.kept\n",true);
    let tree = inputs.archive().tree();
    let names = static_names(tree, tree.checker_builtin_profile().unwrap()).unwrap();
    assert!(
        !names.contains("world"),
        "same-owner source formal replaces pinned builtin declaration"
    );
    assert!(
        names.contains("kept"),
        "same-owner and subtype defaults do not erase formal static flags"
    );
    assert!(!names.contains("ordinary"));
}

#[test]
fn qualifier_only_field_and_local_receivers_refuse_not_false_clean() {
    for source in [
        "/datum/static_owner\n    var/static/danger\n/datum/holder\n    var/SpacemanDMM_private/untyped\n    proc/check()\n        untyped.danger\n",
        "/datum/static_owner\n    var/static/danger\n/proc/check()\n    var/SpacemanDMM_private/untyped\n    untyped.danger\n",
        "/datum/static_owner\n    var/static/danger\n/proc/check(SpacemanDMM_protected/untyped)\n    untyped.danger\n",
    ]{
        let(root,inputs)=input(source,true);
        assert!(findings(&inputs,&root,|_|false,||Ok(())).is_err());
    }
}

#[test]
fn owned_primary_field_qualifiers_admit_untyped_and_preserve_unknown_nonempty_hints() {
    let source="/datum/static_owner\n    var/static/danger\n/datum/holder\n    var/SpacemanDMM_private/untyped\n    var/SpacemanDMM_private/datum/typed\n    var/SpacemanDMM_private/missing_type/unknown\n    proc/check()\n        untyped.danger\n        typed.danger\n        unknown.danger\n";
    let (root, ordinary) = input_with_primary(source, true, false);
    assert!(
        findings(&ordinary, &root, |_| false, || Ok(())).is_err(),
        "no primary receipt means Unknown, not stripped metadata"
    );
    let (root, inputs) = input_with_primary(source, true, true);
    let rows = findings(&inputs, &root, |_| false, || Ok(())).unwrap();
    assert_eq!(
        rows.iter()
            .map(|row| (row.line, row.name.as_str()))
            .collect::<Vec<_>>(),
        [(8, "danger")]
    );
    let archive = inputs.archive();
    let tree = archive.tree();
    let profile = tree.checker_builtin_profile().unwrap();
    let formal = tree
        .source_formal_variable_member(SymbolId::of("/datum/holder"), SymbolId::of("unknown"))
        .unwrap()
        .unwrap();
    let view = archive
        .checker_variable_properties(formal, profile)
        .unwrap();
    assert_eq!(view.declared_hint(), Some("/missing_type"));
    assert!(
        tree.lookup_type(SymbolId::of("/missing_type")).is_none(),
        "receiver typing must not depend on type existence"
    );
    assert!(
        tree.symbols()
            .text(view.metadata.declared_type.unwrap())
            .unwrap()
            .contains("SpacemanDMM_private"),
        "runtime metadata unchanged"
    );
}
#[test]
fn public_property_view_uses_actual_profile_formal_and_source_issuance() {
    let source="/datum/base\n    var/SpacemanDMM_private/value\n/datum/base/child\n    value = null\n    proc/check()\n        return\n";
    let (_, inputs) = input_with_primary(source, true, true);
    let archive = inputs.archive();
    let tree = archive.tree();
    let profile = tree.checker_builtin_profile().unwrap();
    let base = tree
        .source_formal_variable_member(SymbolId::of("/datum/base"), SymbolId::of("value"))
        .unwrap()
        .unwrap();
    let inherited = tree
        .source_formal_variable_member(SymbolId::of("/datum/base/child"), SymbolId::of("value"))
        .unwrap()
        .unwrap();
    assert_eq!(
        base, inherited,
        "value-only override does not manufacture another formal"
    );
    let view = archive
        .checker_variable_properties(inherited, profile)
        .unwrap();
    assert_eq!(view.owner, SymbolId::of("/datum/base"));
    assert_eq!(view.qualifiers, dm_syntax::CHECKER_VAR_PRIVATE);
    assert_eq!(view.declared_hint(), None);
    assert!(
        std::ptr::eq(view.metadata, tree.member(base).unwrap().metadata.as_ref()),
        "borrow SAME original metadata, no reified declaration"
    );
    assert_eq!(
        tree.symbols().text(view.metadata.declared_type.unwrap()),
        Some("/SpacemanDMM_private")
    );
    assert!(archive
        .checker_variable_properties(base, PackedU128::new(profile.get() ^ 1))
        .is_err());
    let (_, ordinary) = input_with_primary(source, true, false);
    let ordinary = ordinary.archive();
    let p = ordinary.tree().checker_builtin_profile().unwrap();
    let id = ordinary
        .tree()
        .source_formal_variable_member(SymbolId::of("/datum/base"), SymbolId::of("value"))
        .unwrap()
        .unwrap();
    assert!(
        ordinary.checker_variable_properties(id, p).is_err(),
        "valid builtin profile alone is not primary qualifier issuance"
    );
}
#[test]
fn public_property_view_preserves_list_container_when_qualifier_is_the_only_element_segment() {
    let source="/datum/holder\n    var/list/SpacemanDMM_private/list_only\n    var/list/SpacemanDMM_private/missing_type/typed_list\n";
    let (_, inputs) = input_with_primary(source, true, true);
    let archive = inputs.archive();
    let tree = archive.tree();
    let profile = tree.checker_builtin_profile().unwrap();
    for (name, hint) in [("list_only", "/list"), ("typed_list", "/list/missing_type")] {
        let formal = tree
            .source_formal_variable_member(SymbolId::of("/datum/holder"), SymbolId::of(name))
            .unwrap()
            .unwrap();
        let view = archive
            .checker_variable_properties(formal, profile)
            .unwrap();
        assert_eq!(view.qualifiers, dm_syntax::CHECKER_VAR_PRIVATE);
        assert_eq!(view.declared_hint(), Some(hint));
        assert_eq!(view.declared_type, Some(SymbolId::of("/list")));
        assert!(tree
            .symbols()
            .text(view.metadata.list_element_type.unwrap())
            .unwrap()
            .contains("SpacemanDMM_private"));
    }
}
