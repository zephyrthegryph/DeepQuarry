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
        .join("player-link-native-fixture");
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
fn player_link_judges_mobs_and_preserves_local_shadow_and_named_argument_boundaries() {
    let source="/datum/holder\n    var/mob/passenger\n    proc/use(mob/P, datum/U, list/mob/L)\n        P.key = 1\n        passenger.ckey = 2\n        usr.key = 3\n        U.key = 4\n        L[1].ckey = 5\n        use(key = 6)\n        use(P.key = 7)\n        P.key += 8\n        (P.key) = 9\n/mob/proc/direct()\n    key = 10\n    src.ckey = 11\n/mob/proc/shadow()\n    key = 12\n    var/key\n";
    let (root, inputs) = input(source, true);
    let got = findings(&inputs, &root, |_| false, || Ok(())).unwrap();
    assert_eq!(
        got.iter().map(|f| f.line).collect::<Vec<_>>(),
        [4, 5, 6, 8, 14, 15]
    );
    assert!(got.iter().all(|f| f.rel == "code/probe.dm"));
    assert!(
        findings(&inputs, &root, |f| f == "code/probe.dm", || Ok(()))
            .unwrap()
            .is_empty()
    );
}
#[test]
fn player_link_preserves_declared_returns_lists_and_reference_first_ternary_policy() {
    let source="/proc/mob_result() as /mob\n    return null\n/proc/no_hint() as /mob\n    return null\n/datum/holder/proc/no_hint()\n    return null\n/datum/holder/proc/method() as /mob\n    return null\n/datum/holder/proc/check(datum/holder/H, mob/P, obj/O, turf/T)\n    mob_result().key = 1\n    H.method().key = 2\n    H.mob_result().key = 3\n    no_hint().key = 4\n    (P ? O : P).key = 5\n    (P ? T : P).key = 6\n    (new /mob()).key = 7\n";
    let (root, inputs) = input(source, true);
    let rows = findings(&inputs, &root, |_| false, || Ok(())).unwrap();
    assert_eq!(
        rows.iter().map(|f| f.line).collect::<Vec<_>>(),
        [10, 11, 12, 13, 15, 16]
    );
}
#[test]
fn player_link_deduplicates_statement_lines_and_counts_control_header_roots_only() {
    let source="/mob/proc/test(mob/P)\n    key = 1; ckey = 2\n    if(P.key = 3)\n        P.ckey = 4\n    if((P.key = 5))\n        return\n    for(P.key = 6; P.ckey = 7; P.key = 8)\n        P.key = 9\n";
    let (root, inputs) = input(source, true);
    let rows = findings(&inputs, &root, |_| false, || Ok(())).unwrap();
    assert_eq!(
        rows.iter().map(|f| f.line).collect::<Vec<_>>(),
        [2, 3, 4, 7, 8]
    );
}
#[test]
fn player_link_does_not_turn_unproved_hierarchy_or_cancellation_into_clean_results() {
    let (root, inputs) = input("/mob/proc/test()\n    key = 1\n", false);
    assert!(findings(&inputs, &root, |_| false, || Ok(())).is_err());
    let (root, inputs) = input("/mob/proc/test()\n    key = 1\n", true);
    assert_eq!(
        findings(&inputs, &root, |_| false, || Err("cancelled".into()))
            .err()
            .unwrap()
            .0,
        "cancelled"
    );
}

#[test]
fn member_return_fallback_needs_existing_type_and_absent_method_not_missing_hint() {
    let source="/proc/mob_result() as /mob\n    return null\n/proc/no_hint() as /mob\n    return null\n/datum/holder/proc/no_hint()\n    return null\n/datum/holder/proc/check(datum/holder/H, unknown)\n    H.mob_result().key = 1\n    H.no_hint().key = 2\n    unknown.mob_result().key = 3\n";
    let (root, inputs) = input(source, true);
    let rows = findings(&inputs, &root, |_| false, || Ok(())).unwrap();
    assert_eq!(rows.iter().map(|r| r.line).collect::<Vec<_>>(), [8, 10]);
}

#[test]
fn an_undeclared_receiver_type_cannot_borrow_a_global_return_annotation() {
    let source="/proc/mob_result() as /mob\n    return null\n/proc/check(datum/no_such_holder/H)\n    H.mob_result().key = 1\n";
    let (root, inputs) = input(source, true);
    assert!(findings(&inputs, &root, |_| false, || Ok(()))
        .unwrap()
        .is_empty());
}

#[test]
fn untyped_locals_use_original_root_proc_lookup_but_not_root_field_lookup() {
    let source = "/proc/mob_result() as /mob\n    return null\n/proc/check(unknown)\n    var/local\n    unknown.mob_result().key = 1\n    local.mob_result().key = 2\n    unknown.key = 3\n    local.key = 4\n";
    let (root, inputs) = input(source, true);
    let rows = findings(&inputs, &root, |_| false, || Ok(())).unwrap();
    assert_eq!(rows.iter().map(|r| r.line).collect::<Vec<_>>(), [5, 6]);
}
