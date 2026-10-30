use super::*;
use crate::policy_inputs::{HostCapture, PolicyRole};
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
        .join("rel-write-native-fixture");
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

fn scan(source: &str, decls: &[(&str, &str)]) -> Vec<Finding> {
    let (root, inputs) = input(source, true);
    let mut rels = HashMap::new();
    for (var, owner) in decls {
        rels.entry((*var).to_owned())
            .or_insert_with(Vec::new)
            .push((*owner).to_owned());
    }
    findings(
        &inputs,
        &root,
        &rels,
        |_| false,
        &mut (64 * 1024 * 1024),
        || Ok(()),
    )
    .unwrap()
}
#[test]
fn rel_writes_preserve_receiver_precedence_untyped_fallback_and_debug_formal_metadata() {
    let source="/datum/holder\n    var/list/items\n    var/datum/ref\n    proc/test(datum/holder/H, unknown)\n        rel_set(H, nameof(ref), null)\n        rel_add(H, nameof(items), null, 1)\n        rel_clear(unknown, nameof(H.ref))\n        rel_clear(H, nameof(unknown.ref))\n";
    let rows = scan(source, &[]);
    assert_eq!(
        rows.iter().map(|r| r.line).collect::<Vec<_>>(),
        [5, 6, 7, 8]
    );
    assert_eq!(rows[0].message,"rel_set writes `ref` of /datum/holder, which no relation declares [decl /datum/holder::ref many=0 keyed=0 at=code/probe.dm]");
    assert!(rows[1].message.contains("many=1 keyed=1"));
    assert!(rows[2].message.contains("of /datum/holder"));
    assert!(rows[3].message.contains("of an untyped holder"));
}
#[test]
fn relation_declaration_counts_parent_subtype_and_any_type_for_untyped_only() {
    let source="/datum/holder\n/datum/holder/child\n/datum/other\n/proc/check(datum/holder/H, datum/other/O, unknown)\n    rel_clear(H, nameof(v))\n    rel_clear(O, nameof(v))\n    rel_clear(unknown, nameof(v))\n    rel_clear(unknown, nameof(absent))\n";
    let rows = scan(source, &[("v", "/datum/holder/child")]);
    assert_eq!(rows.iter().map(|r| r.line).collect::<Vec<_>>(), [6, 8]);
}
#[test]
fn followed_calls_are_not_bare_calls_but_nested_arguments_and_parentheses_are_observed() {
    let source="/datum/holder/proc/check(datum/holder/H)\n    rel_clear(H, nameof(a)).field\n    rel_clear(H, nameof(b))[1]\n    rel_clear(H, nameof(c), rel_clear(H, nameof(d)))\n    (rel_clear(H, nameof(e)))\n    rel_move(H, nameof(f), H, nameof(g))\n    rel_private(H, nameof(h))\n    rel_is_private(H, nameof(i))\n";
    let rows = scan(source, &[]);
    assert_eq!(
        rows.iter().map(|r| r.var.as_str()).collect::<Vec<_>>(),
        ["c", "d", "e", "f", "g", "h", "i"]
    );
}
#[test]
fn first_same_line_observation_selects_debug_verb_and_keyed_flag() {
    let source="/datum/holder/proc/check(datum/holder/H)\n    rel_clear(H, nameof(v)); rel_add(H, nameof(v), null, 1)\n";
    let rows = scan(source, &[]);
    assert_eq!(rows.len(), 1);
    assert!(rows[0].message.starts_with("rel_clear "));
    assert!(rows[0].message.contains("keyed=0"));
}
#[test]
fn no_profile_cancel_and_tiny_headroom_cannot_return_clean_results() {
    let source = "/datum/holder/proc/check(datum/holder/H)\n    rel_clear(H, nameof(v))\n";
    let (root, inputs) = input(source, false);
    assert!(findings(
        &inputs,
        &root,
        &HashMap::new(),
        |_| false,
        &mut 4096,
        || Ok(())
    )
    .is_err());
    let (root, inputs) = input(source, true);
    assert!(findings(
        &inputs,
        &root,
        &HashMap::new(),
        |_| false,
        &mut 0,
        || Ok(())
    )
    .is_err());
    assert!(findings(
        &inputs,
        &root,
        &HashMap::new(),
        |_| false,
        &mut 4096,
        || Err("cancelled".into())
    )
    .is_err());
    assert!(
        findings(&inputs, &root, &HashMap::new(), |_| true, &mut 0, || Ok(()))
            .unwrap()
            .is_empty()
    );
}

#[test]
fn empty_local_member_return_uses_existing_root_declaration_contract() {
    let source="/proc/holder_result() as /datum/holder\n    return null\n/datum/holder\n/proc/check(unknown)\n    rel_clear(unknown.holder_result(), nameof(v))\n";
    let rows = scan(source, &[]);
    assert_eq!(rows.len(), 1);
    assert!(rows[0].message.contains("of /datum/holder"));
}

#[test]
fn unknown_declared_type_remains_a_static_spelling_without_borrowing_native_runtime_members() {
    let rows = scan(
        "/proc/check(datum/no_such_holder/H)\n    rel_clear(H, nameof(v))\n",
        &[],
    );
    assert_eq!(rows.len(), 1);
    assert_eq!(rows[0].message,"rel_clear writes `v` of /datum/no_such_holder, which no relation declares [decl ::v many=0 keyed=0 at=]");
}
