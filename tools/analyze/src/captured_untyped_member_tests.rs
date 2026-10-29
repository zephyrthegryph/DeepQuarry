use super::*;
use std::sync::Arc;
#[path = "../../dmb/crates/dm-analysis/examples/support/reference_hierarchy.rs"]
mod reference_hierarchy;
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
#[test]
fn full_member_facade_preserves_exact_finding_fields_and_path_exemption() {
    use dm_analysis::policy_inputs::{HostCapture, PolicyRole};
    let root = std::env::current_dir()
        .unwrap()
        .join("captured-member-fixture");
    let seed = reference_hierarchy::seed();
    let provider = Source(dm_preprocess::AcquiredSource::from_original_bytes(
        b"/datum/static_owner\n    var/static/danger\n/proc/check(holder)\n    holder.danger\n"
            .to_vec(),
        (),
    ));
    let frontend = dm_tree::frontend::build_with_config(
        &root.join("code/probe.dm"),
        &provider,
        &Default::default(),
        dm_tree::frontend::FrontendConfig {
            workers: 1,
            engine: Some(&seed),
            observer: None,
        },
    )
    .unwrap();
    let raw = frontend
        .files
        .iter()
        .filter(|f| f.captured)
        .map(|f| {
            HostCapture::analyze_raw(Arc::clone(&f.path), PolicyRole::DmSource, f.text.clone())
        })
        .collect::<Vec<_>>();
    let inputs = PolicyInputs::capture(&frontend, raw).unwrap();
    let run = CapturedUntypedMember::capture(&root, &inputs, Configuration::ProvenMissing)
        .unwrap()
        .scan(|| Ok(()))
        .unwrap();
    assert_eq!(run.run.sites.len(), 1);
    let site = &run.run.sites[0];
    assert_eq!(
        (site.rule.as_str(), site.rel.as_str(), site.line),
        ("static_member", "code/probe.dm", 4)
    );
    assert_eq!(site.msg,"`.danger` is read through a receiver with no static type, and `danger` is declared static on some type");
    assert!(site.ident.is_empty() && site.key.is_empty());
    assert!(run.allow_used.is_empty() && run.run.notes.is_empty());
    let config = b"[lint.untyped_member]\nexempt_prefixes=['code/']\n";
    let run = CapturedUntypedMember::capture(&root, &inputs, Configuration::Captured(config))
        .unwrap()
        .scan(|| Ok(()))
        .unwrap();
    assert!(run.run.sites.is_empty());
}
