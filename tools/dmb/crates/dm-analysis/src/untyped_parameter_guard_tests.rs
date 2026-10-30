use super::*;
use crate::policy_inputs::{HostCapture, PolicyInputs, PolicyRole};
use dm_preprocess::{AcquiredSource, SourceProvider, SourceText};
use std::path::Path;
use std::{path::PathBuf, sync::Arc};
#[path = "../examples/support/reference_hierarchy.rs"]
mod reference_hierarchy;
struct Source(AcquiredSource);
impl SourceProvider for Source {
    fn read(&self, _: &Path) -> Result<String, String> {
        Err("acquisition required".into())
    }
    fn acquired_source(&self, _: &Path) -> Result<Option<AcquiredSource>, String> {
        Ok(Some(self.0.clone()))
    }
    fn source_acquisition(&self, _: &Path, text: &SourceText) -> Option<AcquiredSource> {
        self.0
            .lease()
            .source_text()
            .same_view(text)
            .then(|| self.0.clone())
    }
}
fn input(source: &str, certified: bool) -> (PathBuf, PolicyInputs) {
    let root = std::env::current_dir()
        .unwrap()
        .join("qualified-parameter-guard-fixture");
    let source = Source(AcquiredSource::from_original_bytes(
        source.as_bytes().to_vec(),
        (),
    ));
    let seed = reference_hierarchy::seed();
    let executor = dm_exec::BuildExecutor::new(1).unwrap();
    let frontend = dm_tree::frontend::build_with_executor_and_semantic_state_for_policy(
        &root.join("code/probe.dm"),
        &source,
        &Default::default(),
        dm_tree::frontend::FrontendConfig {
            workers: 1,
            engine: certified.then_some(&seed),
            observer: None,
        },
        None,
        &executor,
        None,
        true,
    )
    .unwrap();
    let extra = frontend
        .files
        .iter()
        .filter(|f| f.captured)
        .map(|f| {
            HostCapture::analyze_raw(Arc::clone(&f.path), PolicyRole::DmSource, f.text.clone())
        })
        .collect::<Vec<_>>();
    (root, PolicyInputs::capture(&frontend, extra).unwrap())
}
#[test]
fn original_parameter_receipts_preserve_leading_embedded_repeated_namespace_and_suffix_types() {
    for (parameter, wanted) in [
        ("static/datum/D", "/datum"),
        ("const/datum/D", "/datum"),
        ("tmp/datum/D", "/datum"),
        ("global/datum/D", "/datum"),
        ("datum/static/D", "/datum/static"),
        ("datum/var/D", "/datum/var"),
        ("obj/var/item/D", "/obj/var/item"),
        ("var/var/datum/D", "/var/datum"),
        ("datum/D[][]", "/list/datum"),
        ("list/datum/D[]", "/list/list/datum"),
    ] {
        let source = format!("/proc/probe({parameter})\n    return\n");
        let (_, inputs) = input(&source, true);
        let body = inputs.archive().parse(0).unwrap();
        let scope = archived_scope(&body, inputs.archive().tree(), &[]).unwrap();
        assert_eq!(
            scope.locals.get("D").map(String::as_str),
            Some(wanted),
            "{parameter}"
        );
    }
}
#[test]
fn ordinary_zero_flag_parameters_keep_existing_scope_behavior() {
    let (_, inputs) = input(
        "/proc/probe(datum/D, list/datum/L, untyped)\n    return\n",
        true,
    );
    let body = inputs.archive().parse(0).unwrap();
    let scope = archived_scope(&body, inputs.archive().tree(), &[]).unwrap();
    assert_eq!(scope.locals.get("D").map(String::as_str), Some("/datum"));
    assert_eq!(
        scope.locals.get("L").map(String::as_str),
        Some("/list/datum")
    );
    assert_eq!(scope.locals.get("untyped").map(String::as_str), Some(""));
}
#[test]
fn unissued_internal_scope_cannot_claim_zero_runtime_flags_are_original_source_proof() {
    for parameter in ["datum/D", "var/var/datum/D"] {
        let (_, inputs) = input(&format!("/proc/probe({parameter})\n    return\n"), true);
        let body = inputs.archive().parse(0).unwrap();
        let member = inputs
            .archive()
            .tree()
            .member(body.occurrence().member)
            .unwrap();
        assert_eq!(
            member
                .metadata
                .procedure
                .as_ref()
                .unwrap()
                .signature
                .parameters[0]
                .flags,
            0
        );
        let error = scope_from(
            inputs.archive().tree(),
            body.occurrence(),
            body.statement_body(),
            inputs.archive().tree(),
            &[],
        )
        .err()
        .unwrap();
        assert!(error.0.contains("zero runtime flags are not source proof"));
    }
}
#[test]
fn shared_policies_use_original_alias_path_instead_of_a_runtime_normalized_receiver() {
    let source="/holder_alias\n    parent_type=/datum\n    var/link\n/player_alias\n    parent_type=/mob\n/datum/probe\n    var/field\n    proc/early(mob/P, holder_alias/H, datum/D)\n        P.key=1\n        H.link\n        rel_clear(H, nameof(undeclared))\n        field=D\n    proc/late(holder_alias/static/H, player_alias/static/P)\n        P.key=2\n        H.link\n        rel_clear(H, nameof(link))\n        field=H\n";
    let (root, inputs) = input(source, true);
    let relations = HashMap::from([("link".to_owned(), vec!["/holder_alias".to_owned()])]);
    let p = crate::player_link_native::findings(&inputs, &root, |_| false, || Ok(())).unwrap();
    assert_eq!(p.iter().map(|r| r.line).collect::<Vec<_>>(), [9]);
    let w = crate::weak_raw_read_native::findings(&inputs, &root, &relations, |_| false, || Ok(()))
        .unwrap();
    assert_eq!(w.iter().map(|r| r.line).collect::<Vec<_>>(), [10]);
    let r = crate::rel_write_native::findings(
        &inputs,
        &root,
        &relations,
        |_| false,
        &mut (64 * 1024 * 1024),
        || Ok(()),
    )
    .unwrap();
    assert_eq!(r.iter().map(|r| r.line).collect::<Vec<_>>(), [11, 16]);
    let values =
        crate::value_program::Values::build_archive(inputs.archive(), inputs.archive().tree(), &[])
            .unwrap();
    let schemas = crate::value_schemas::Schemas::default();
    let rows = crate::untyped_native::archived_findings(
        inputs.archive(),
        &values,
        &schemas,
        &root,
        &[],
        |_| false,
    )
    .unwrap();
    assert!(
        !rows.is_empty(),
        "ordinary datum witness must survive original type projection"
    );
}

// Pinned old executable evidence: parameter-type-original-oracles/receipt.json
// array_obj_rank2/array_list_obj/parameter_args. A suffix adds ONE list
// wrapper, even when the explicit element starts with list. Explicit arguments
// named args replace the built-in list args, rather than merging its type.
#[test]
fn original_nested_list_suffix_depth_and_explicit_args_shadowing_are_preserved() {
    for (parameter, name, expected) in [
        ("obj/item/args", "args", "/obj/item"),
        ("obj/item/P[][]", "P", "/list/obj/item"),
        ("list/obj/item/P[]", "P", "/list/list/obj/item"),
        ("list/obj/item/P[][]", "P", "/list/list/obj/item"),
    ] {
        let source = format!("/obj/item\n    var/member\n/proc/probe({parameter})\n    return\n");
        let (_, inputs) = input(&source, true);
        let body = inputs.archive().parse(0).unwrap();
        let scope = archived_scope(&body, inputs.archive().tree(), &[]).unwrap();
        assert_eq!(
            scope.locals.get(name).map(String::as_str),
            Some(expected),
            "{parameter}"
        );
    }
}
