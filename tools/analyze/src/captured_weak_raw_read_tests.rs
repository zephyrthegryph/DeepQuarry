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

#[test]
fn weak_capture_uses_original_declaration_matcher_and_exact_messages() {
    let root = std::env::current_dir()
        .unwrap()
        .join("weak-captured-fixture");
    let code=b"#define CAPABILITIES(T) T/proc/capabilities()\n#define TRUE 1\n/datum/owner\n    var/datum/target\nCAPABILITIES(/datum/owner)\n    ref_one(nameof(target), weak = TRUE)\n/datum/owner/proc/read()\n    target\n    nameof(target)\n    target()\n";
    let source = Source(AcquiredSource::from_original_bytes(code.to_vec(), ()));
    let seed = reference_hierarchy::seed();
    let executor = dm_exec::BuildExecutor::new(1).unwrap();
    let frontend = dm_tree::frontend::build_with_executor_and_semantic_state_for_policy(
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
    let captures = frontend
        .files
        .iter()
        .filter(|f| f.captured)
        .map(|f| {
            HostCapture::analyze_raw(Arc::clone(&f.path), PolicyRole::DmSource, f.text.clone())
        })
        .collect::<Vec<_>>();
    let inputs = PolicyInputs::capture(&frontend, captures).unwrap();
    let run = CapturedWeakRawRead::capture(&root, &inputs, Configuration::ProvenMissing)
        .unwrap()
        .scan(|| Ok(()))
        .unwrap();
    assert_eq!(run.run.sites.len(), 1);
    let site = &run.run.sites[0];
    assert_eq!(
        (
            &*site.rule,
            &*site.rel,
            site.line,
            &*site.msg,
            &*site.ident,
            &*site.key
        ),
        (
            "raw",
            "code/probe.dm",
            8,
            "`target` of /datum/owner is a weak relation read raw; use target()",
            "",
            ""
        )
    );
    assert!(run.allow_used.is_empty() && run.run.notes.is_empty());
    let config = b"[lint.weak_raw_read]\nexempt_files=['code/probe.dm']\n";
    assert!(
        CapturedWeakRawRead::capture(&root, &inputs, Configuration::Captured(config))
            .unwrap()
            .scan(|| Ok(()))
            .unwrap()
            .run
            .sites
            .is_empty()
    );
}
