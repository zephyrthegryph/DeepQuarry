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
fn captured_player_link_preserves_exact_sites_message_dedup_and_exemptions() {
    let root = std::env::current_dir()
        .unwrap()
        .join("captured-player-link-fixture");
    let source = Source(AcquiredSource::from_original_bytes(
        b"/mob/proc/test()\n    key = 1; ckey = 2\n".to_vec(),
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
            engine: Some(&seed),
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
    let inputs = PolicyInputs::capture(&frontend, extra).unwrap();
    let run = CapturedPlayerLink::capture(&root, &inputs, Configuration::ProvenMissing)
        .unwrap()
        .scan(|| Ok(()))
        .unwrap();
    assert_eq!(run.run.sites.len(), 1);
    let site = &run.run.sites[0];
    assert_eq!(
        (
            site.rule.as_str(),
            site.rel.as_str(),
            site.line,
            site.msg.as_str(),
            site.ident.as_str(),
            site.key.as_str()
        ),
        (
            "raw_key",
            "code/probe.dm",
            2,
            crate::player_link_policy::MESSAGE,
            "",
            ""
        )
    );
    assert!(run.allow_used.is_empty() && run.run.notes.is_empty());
    let config = b"[lint.player_link]\nexempt_prefixes=['code/']\n";
    assert!(
        CapturedPlayerLink::capture(&root, &inputs, Configuration::Captured(config))
            .unwrap()
            .scan(|| Ok(()))
            .unwrap()
            .run
            .sites
            .is_empty()
    );
}
