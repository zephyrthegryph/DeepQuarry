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

#[cfg(feature = "legacy-sem")]
#[path = "../../dmb/shared/test_scratch.rs"]
mod scratch;

#[test]
fn native_stored_work_queue_exempts_exact_scalar_and_typed_list_places() {
    const SOURCE: &str = concat!(
        "/datum/queues\n",
        "    var/datum/queued\n",
        "    var/datum/queued_suffix\n",
        "    var/list/datum/queued_list\n",
        "/datum/queues_other\n",
        "    var/datum/queued\n",
        "    var/list/datum/queued_list\n",
        // Give the legacy indenter a real following token so the preceding
        // declaration is located at its authored EOL, not at the DME EOF.
        "/datum/after_queue_declarations\n",
    );
    const CONFIG: &str = concat!(
        "[lint.stored_refs.lists]\n",
        "transient_types = []\n",
        "exempt_types = []\n",
        "work_queues = [\"/datum/queues::queued\", \"/datum/queues::queued_list\"]\n",
    );
    let native = captured(SOURCE, &[], Configuration::Captured(CONFIG.as_bytes()));
    let summary: Vec<_> = native.run.sites.iter().map(|site| (site.rule.as_str(), site.ident.as_str())).collect();
    assert_eq!(summary, [
        ("var", "/datum/queues::queued_suffix"),
        ("var", "/datum/queues_other::queued"),
        ("list", "/datum/queues_other::queued_list"),
    ]);
    assert!(native.allow_used.is_empty());

    #[cfg(feature = "legacy-sem")]
    {
        let root = scratch::dir("stored-work-queue-current-master");
        std::fs::create_dir_all(root.join("tools/ci")).unwrap();
        std::fs::create_dir_all(root.join("code")).unwrap();
        std::fs::write(root.join("tools/ci/lint_scopes.toml"), CONFIG).unwrap();
        std::fs::write(root.join("deepquarry.dme"), "#include \"code/probe.dm\"\n").unwrap();
        std::fs::write(root.join("code/probe.dm"), SOURCE).unwrap();
        let engine = crate::run::Engine::new(crate::run::registry(), crate::run::Options {
            root, lints: vec!["stored_refs".into()], no_cache: true, raw: true,
            ..Default::default()
        }).unwrap();
        let sem = crate::sem::sem_for(&engine.tree).unwrap();
        assert!(sem.errors.is_empty(), "master fixture errors: {:?}", sem.errors);
        for (owner, line) in [("/datum/queues", 4), ("/datum/queues_other", 7)] {
            let declaration = sem.var_decl(owner, "queued_list").expect("original typed list seed");
            assert_eq!(declaration.declared, "/list/datum");
            assert_eq!((declaration.file.as_str(), declaration.line), ("code/probe.dm", line));
        }
        let lint = engine.reg.lints.iter().find(|lint| lint.meta().name == "stored_refs").unwrap();
        let original = engine.run_one(lint.as_ref());
        assert!(original.internal_error.is_none());
        assert_eq!(native.run.sites, original.run.sites);
        assert_eq!(native.allow_used, original.allow_used);
    }
}
