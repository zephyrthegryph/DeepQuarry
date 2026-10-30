use super::*;
use dm_analysis::policy_inputs::{HostCapture, PolicyRole};
use dm_preprocess::{AcquiredSource, SourceProvider, SourceText};
use std::sync::Arc;
#[path = "../../dmb/crates/dm-analysis/examples/support/reference_hierarchy.rs"]
mod reference_hierarchy;
struct Source(AcquiredSource);
impl SourceProvider for Source {
    fn read(&self, _: &Path) -> Result<String, String> {
        Err("acquisition required".into())
    }
    fn acquired_source(&self, _: &Path) -> Result<Option<AcquiredSource>, String> {
        Ok(Some(self.0.clone()))
    }
    fn source_acquisition(&self, _: &Path, t: &SourceText) -> Option<AcquiredSource> {
        self.0
            .lease()
            .source_text()
            .same_view(t)
            .then(|| self.0.clone())
    }
}

fn captured(source: &str, extra: &[(&str, &str)], config: Configuration<'_>) -> RawRun {
    let root = std::env::current_dir()
        .unwrap()
        .join("captured-stored-reference-fixture");
    let source = Source(AcquiredSource::from_original_bytes(
        source.as_bytes().to_vec(),
        (),
    ));
    let seed = reference_hierarchy::seed();
    let executor = dm_exec::BuildExecutor::new(1).unwrap();
    let front = dm_tree::frontend::build_with_executor_and_semantic_state_for_policy(
        &root.join("code/probe.dm"),
        &source,
        &Default::default(),
        dm_tree::frontend::FrontendConfig {
            workers: 1,
            engine: Some(&seed),
            observer: None,
        },
        None,
        &executor,
        None,
        true,
    )
    .unwrap();
    let mut raw = front
        .files
        .iter()
        .filter(|f| f.captured)
        .map(|f| {
            HostCapture::analyze_raw(Arc::clone(&f.path), PolicyRole::DmSource, f.text.clone())
        })
        .collect::<Vec<_>>();
    for (rel, text) in extra {
        raw.push(HostCapture::analyze_raw(
            Arc::new(root.join(rel)),
            PolicyRole::DmSource,
            (*text).into(),
        ));
    }
    let inputs = PolicyInputs::capture(&front, raw).unwrap();
    CapturedStoredRefs::capture(&root, &inputs, config)
        .unwrap()
        .scan(|| Ok(()))
        .unwrap()
}
#[test]
fn stored_raw_inactive_relations_keep_and_init_only_preserve_original_distinctions() {
    let source="/datum/holder\n    var/datum/kept\n    var/datum/init_only\n    var/datum/forever/F\n    var/datum/plain\n/datum/forever\n";
    let extra="#if 0\nCAPABILITIES(/datum/holder)\n    ref_one(nameof(kept))\n    param(nameof(init_only), keep = FALSE)\nLIFECYCLE_KEEP_ALWAYS(/datum/forever)\n#endif\n";
    let run = captured(
        source,
        &[("code/inactive.dm", extra)],
        Configuration::ProvenMissing,
    );
    assert_eq!(run.run.sites.len(), 1);
    assert_eq!(run.run.sites[0].ident, "/datum/holder::plain");
}
#[test]
fn stored_value_schema_suppresses_list_not_typed_var_and_raw_allow_is_consumed() {
    let source="/datum/holder\n    var/list/items\n    var/datum/loose\n    var/datum/allowed // ALLOW(stored_refs): fixture explicitly models reviewed relation-free storage\n    proc/check(datum/D)\n        items += D\n";
    let extra="SCHEMA(/datum/holder, items, list_of(schema_path(/datum)))\nSCHEMA(/datum/holder, loose, schema_path(/datum))\n";
    let run = captured(
        source,
        &[("code/schema.dm", extra)],
        Configuration::ProvenMissing,
    );
    assert_eq!(run.run.sites.len(), 1);
    assert_eq!(run.run.sites[0].ident, "/datum/holder::loose");
    assert_eq!(run.allow_used.len(), 1);
}
#[test]
fn stored_scope_lists_are_exact_for_reference_types_transients_and_work_queues() {
    let source="/datum/holder\n    var/datum/plain\n    var/list/items\n    proc/check(datum/D)\n        items += D\n/datum/transient\n    var/datum/not_stored\n";
    let config="[lint.stored_refs.lists]\ntransient_types = [\"/datum/transient\"]\nwork_queues = [\"/datum/holder::items\"]\nexempt_types = []\n";
    let run = captured(source, &[], Configuration::Captured(config.as_bytes()));
    assert_eq!(run.run.sites.len(), 1);
    assert_eq!(run.run.sites[0].ident, "/datum/holder::plain");
}
