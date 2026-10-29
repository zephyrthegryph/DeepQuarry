use super::*;
use dm_analysis::policy_inputs::{HostCapture, PolicyRole};
use std::{collections::BTreeSet, path::PathBuf, sync::Arc};
struct Source(&'static str);
impl dm_preprocess::SourceProvider for Source {
    fn read(&self, _: &Path) -> Result<String, String> {
        Ok(self.0.into())
    }
}
fn fixture() -> (PathBuf, PolicyInputs) {
    let root = std::env::current_dir()
        .unwrap()
        .join("base-vars-composition-unit");
    let source="/atom\n    var/plain\n    var/list/items = list()\n    var/kept // ALLOW(base_vars): fixture keeps this base field deliberately for its owner\n    var/list/list_kept = list() // ALLOW(instance_list): fixture keeps this list allocation deliberately for its owner\n/datum/record/probe/proc/business()\n    return\n/datum/record/probe/proc/set_value()\n    return\n";
    let frontend = dm_tree::frontend::build(
        &root.join("code/probe.dm"),
        &Source(source),
        &Default::default(),
        1,
    )
    .unwrap();
    let extra = frontend
        .files
        .iter()
        .filter(|file| file.captured)
        .map(|file| {
            HostCapture::analyze_raw(
                Arc::clone(&file.path),
                PolicyRole::DmSource,
                file.text.clone(),
            )
        })
        .collect::<Vec<_>>();
    (root, PolicyInputs::capture(&frontend, extra).unwrap())
}
const CONFIG:&[u8]=b"[lint.base_vars.lists]\nrecord_accessor_prefixes=['set_','get_']\n[lint.base_vars.tables.base_var_home_hot]\n'/atom/plain'='short'\n";
#[test]
fn all_four_rules_compose_in_legacy_order_with_one_annotation_phase() {
    let (root, inputs) = fixture();
    let policy =
        CapturedBaseVarsPolicy::capture(&root, &inputs, Configuration::Captured(CONFIG)).unwrap();
    let candidates = BorrowedBaseVarCandidates::capture(&policy.raw, &inputs)
        .unwrap()
        .scan(|| Ok(()))
        .unwrap();
    let full = policy.scan(|| Ok(())).unwrap();
    assert_eq!(
        full.run
            .sites
            .iter()
            .map(|site| site.rule.as_str())
            .collect::<BTreeSet<_>>(),
        BTreeSet::from(["base_var", "list_init", "hot_home", "records_data_only"])
    );
    assert_eq!(full.allow_used, candidates.allow_used);
    assert_eq!(full.allow_used.len(), 2);
    assert_eq!(full.run.notes, candidates.run.notes);
    assert_eq!(full.run.notes.len(), 1);
    assert_eq!(full.run.sites.last().unwrap().rule, "records_data_only");
    let hot = full
        .run
        .sites
        .iter()
        .position(|site| site.rule == "hot_home")
        .unwrap();
    assert!(full.run.sites[..hot]
        .iter()
        .all(|site| matches!(site.rule.as_str(), "base_var" | "list_init")));
    assert_eq!(
        full.run
            .sites
            .iter()
            .filter(|site| site.rule == "records_data_only")
            .count(),
        1
    );
}
#[test]
fn borrowed_composition_reuses_the_raw_source_owner() {
    let (root, inputs) = fixture();
    let raw = CapturedRawPolicy::capture(&root, &inputs, Configuration::Captured(CONFIG)).unwrap();
    let borrowed = BorrowedBaseVarsPolicy::capture(&raw, &inputs).unwrap();
    let first = borrowed.scan(|| Ok(())).unwrap();
    let marker = raw.tree.get("code/probe.dm").unwrap().marker().clone();
    let second = borrowed.scan(|| Ok(())).unwrap();
    assert_eq!(first.run.sites, second.run.sites);
    assert_eq!(first.allow_used, second.allow_used);
    assert!(marker.same_view(raw.tree.get("code/probe.dm").unwrap().marker()));
}
#[test]
fn missing_analyze_raw_is_an_error_before_any_findings() {
    let root = std::env::current_dir()
        .unwrap()
        .join("base-vars-no-raw-unit");
    let frontend = dm_tree::frontend::build(
        &root.join("code/probe.dm"),
        &Source("/atom\n    var/one\n"),
        &Default::default(),
        1,
    )
    .unwrap();
    let inputs = PolicyInputs::capture(&frontend, Vec::new()).unwrap();
    assert!(CapturedBaseVarsPolicy::capture(&root, &inputs, Configuration::ProvenMissing).is_err());
}
#[test]
fn cancellation_after_candidate_work_does_not_issue_partial_results() {
    let (root, inputs) = fixture();
    let policy =
        CapturedBaseVarsPolicy::capture(&root, &inputs, Configuration::Captured(CONFIG)).unwrap();
    let mut candidate_checks = 0usize;
    BorrowedBaseVarCandidates::capture(&policy.raw, &inputs)
        .unwrap()
        .scan(|| {
            candidate_checks += 1;
            Ok(())
        })
        .unwrap();
    let mut checks = 0usize;
    let result = policy.scan(|| {
        checks += 1;
        if checks > candidate_checks {
            Err("after candidates".into())
        } else {
            Ok(())
        }
    });
    assert_eq!(result.err().as_deref(), Some("after candidates"));
    assert!(crate::dm::sys::take_recorded().is_empty());
}
