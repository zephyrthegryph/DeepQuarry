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
        .join("captured-rel-write-fixture");
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
    CapturedRelWrite::capture(&root, &inputs, config)
        .unwrap()
        .scan(|| Ok(()))
        .unwrap()
}
#[test]
fn whole_relation_decl_projection_sees_inactive_capabilities_links_and_legacy_final_annotation() {
    let source="/datum/holder/proc/check(datum/holder/H)\n    rel_clear(H, nameof(kept))\n    rel_clear(H, nameof(linked))\n    rel_clear(H, nameof(legacy))\n    rel_clear(H, nameof(annotated))\n";
    let raw="#if 0\nCAPABILITIES(/datum/holder)\n    ref_one(nameof(kept))\n    links(/datum/holder::linked, /datum/other::back)\n/datum/holder/relations()\n    . += rel_one(nameof(legacy))\n    . += owns(nameof(annotated))\n    . += owns(nameof(annotated), policy = OWN_NONE)\n#endif\n";
    let run = captured(
        source,
        &[("code/inactive.dm", raw)],
        Configuration::ProvenMissing,
    );
    assert_eq!(run.run.sites.len(), 1);
    assert!(run.run.sites[0].msg.contains("`annotated`"));
}
#[test]
fn path_form_scans_inactive_uncompiled_lines_without_inventing_second_move_pair() {
    let source = "/datum/holder\n";
    let raw="#if 0\nrel_set(H, nameof(/datum/holder::absent), null)\nrel_move(H, nameof(/datum/holder::first), H, nameof(/datum/holder::second))\nrel_private(H, nameof(/datum/holder::private))\n#endif\n";
    let run = captured(
        source,
        &[("code/raw.dm", raw)],
        Configuration::ProvenMissing,
    );
    assert_eq!(run.run.sites.len(), 2);
    assert!(run.run.sites.iter().all(|s| !s.msg.contains("`second`")));
}
#[test]
fn real_scope_exemptions_apply_to_body_and_raw_pass_but_not_declaration_visibility() {
    let source = "/datum/holder/proc/check(datum/holder/H)\n    rel_clear(H, nameof(v))\n";
    let run = captured(
        source,
        &[("code/raw.dm", "rel_clear(H, nameof(/datum/holder::v))\n")],
        Configuration::Captured(
            b"[lint.rel_write_undeclared]\nexempt_files = [\"code/probe.dm\",\"code/raw.dm\"]\n",
        ),
    );
    assert!(run.run.sites.is_empty());
}
