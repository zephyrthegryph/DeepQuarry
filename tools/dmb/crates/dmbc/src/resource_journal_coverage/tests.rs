use super::*;
use std::path::PathBuf;
use crate::{frozen_inputs::Inputs, input_snapshot::{RecordingInputs, SnapshotProvider}};
use dm_resources::capture::{CapturePolicy, discover_demand, capture_discovered};
use dm_preprocess::regions::{DirectivePlan, ExpandedRegions};
struct Root(PathBuf);
impl Root {
    fn new() -> Self {
        let base = if cfg!(windows) { PathBuf::from("E:/dq-cache/dmb-protocol-checks") } else { std::env::temp_dir() };
        let stamp = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap().as_nanos();
        let root = base.join(format!("resource-journal-{}-{stamp}", std::process::id()));
        std::fs::create_dir_all(root.join("late")).unwrap(); Self(root)
    }
}
impl Drop for Root { fn drop(&mut self) { let _ = std::fs::remove_dir_all(&self.0); } }
fn demand(root: &Path, text: &str) -> ResourceDemand {
    discover_demand(&DirectivePlan { project_dir: root.into(), file_dirs: vec!["late".into()], ..Default::default() },
        &ExpandedRegions { text: format!("/proc/p()\n    return '{text}'\n").into(), ..Default::default() }, &[], &[]).unwrap()
}
fn limits() -> CoverageLimits { CoverageLimits { candidate_reads: 32, source_payload_bytes: 1024 } }
fn raw_policy() -> CapturePolicy { CapturePolicy { certified_raw_extensions: BTreeSet::from(["txt".into()]) } }
#[test]
fn observed_resource_coverage_authenticates_winner_and_preceding_absence() {
    let root = Root::new();
    std::fs::write(root.0.join("late/asset.txt"), b"winner").unwrap();
    let journal = Inputs::record(&root.0.join("journal")).unwrap();
    let policy = raw_policy();
    let config = CaptureConfig { policy: &policy, encoded: &[], additional: &[] };
    let current = demand(&root.0, "asset.txt");
    let captured = capture_discovered(current.clone(), config, &RecordingInputs::new(&journal, 1)).unwrap();
    journal.with_access_view(|view| {
        let coverage = validate_observed_demand(current.clone(), &captured, config, &view, limits())?;
        assert_eq!(coverage.candidate_reads, 2);
        assert_eq!(coverage.source_payload_bytes, 6);
        assert_eq!(coverage.resource_aliases, 1);
        assert!(validate_observed_demand(current.clone(), &captured, config, &view,
            CoverageLimits { candidate_reads: 1, source_payload_bytes: 1024 }).is_err());
        Ok(())
    }).unwrap();
    // A journal missing the earlier negative cannot manufacture search coverage.
    let incomplete = Inputs::record(&root.0.join("incomplete")).unwrap();
    incomplete.read(&root.0.join("late/asset.txt")).unwrap();
    incomplete.list(&root.0).unwrap(); incomplete.list(&root.0.join("late")).unwrap();
    incomplete.with_access_view(|view| {
        assert!(validate_observed_demand(current.clone(), &captured, config, &view, limits()).is_err()); Ok(())
    }).unwrap();
    // Newly present earlier candidates must decline the old selected output.
    std::fs::write(root.0.join("asset.txt"), b"earlier").unwrap();
    let changed = Inputs::record(&root.0.join("changed")).unwrap();
    capture_discovered(current.clone(), config, &RecordingInputs::new(&changed, 2)).unwrap();
    changed.with_access_view(|view| {
        assert!(validate_observed_demand(current.clone(), &captured, config, &view, limits()).is_err()); Ok(())
    }).unwrap();
}

#[test]
fn observed_resource_coverage_declines_file_created_after_folder_observation() {
    let root = Root::new();
    let journal = Inputs::record(&root.0.join("journal")).unwrap();
    journal.list(&root.0).unwrap();
    let source = root.0.join("asset.txt");
    std::fs::write(&source, b"new asset").unwrap();
    journal.read(&source).unwrap();
    let policy = raw_policy();
    let config = CaptureConfig { policy: &policy, encoded: &[], additional: &[] };
    let current = demand(&root.0, "asset.txt");
    let captured = capture_discovered(current.clone(), config, &crate::input_snapshot::FileSystemInputs).unwrap();
    journal.with_access_view(|view| {
        let error = validate_observed_demand(current, &captured, config, &view, limits()).err().unwrap();
        assert!(error.to_string().contains("resource file contradicts search folder membership"));
        Ok(())
    }).unwrap();
}
#[test]
fn observed_resource_coverage_uses_real_encoder_source_receipt_and_declines_changed_source() {
    use sha2::{Digest, Sha256};
    use dm_resources::{ResourceInput, capture::EncodedResourceInput};
    let root = Root::new();
    let source = root.0.join("picture.png");
    std::fs::write(&source, b"source").unwrap();
    let named = byond_dmb::rsc::NamedResource::from_data(6, b"picture.png".to_vec(), b"encoded".to_vec(), 0, 0).unwrap();
    let encoded = [EncodedResourceInput { input: ResourceInput { archive_name: "picture.png".into(),
        disk_path: source.clone(), content_digest: Sha256::digest(b"encoded").into(), named: named.into() },
        source_digest: Sha256::digest(b"source").into() }];
    let policy = CapturePolicy::default();
    let config = CaptureConfig { policy: &policy, encoded: &encoded, additional: &[] };
    let current = demand(&root.0, "picture.png");
    let journal = Inputs::record(&root.0.join("journal")).unwrap();
    let captured = capture_discovered(current.clone(), config, &RecordingInputs::new(&journal, 1)).unwrap();
    journal.with_access_view(|view| validate_observed_demand(current.clone(), &captured, config, &view, limits())).unwrap().unwrap();
    std::fs::write(&source, b"changed source").unwrap();
    let changed = Inputs::record(&root.0.join("changed")).unwrap();
    changed.read(&source).unwrap(); changed.list(&root.0).unwrap();
    changed.with_access_view(|view| {
        assert!(validate_observed_demand(current.clone(), &captured, config, &view, limits()).is_err()); Ok(())
    }).unwrap();
}
#[test]
fn observed_resource_coverage_declines_external_search_roots() {
    let root = Root::new();
    let current = discover_demand(&DirectivePlan { project_dir: root.0.clone(), file_dirs: vec!["../outside".into()], ..Default::default() },
        &ExpandedRegions::default(), &[], &[]).unwrap();
    let policy = raw_policy();
    let config = CaptureConfig { policy: &policy, encoded: &[], additional: &[] };
    let journal = Inputs::record(&root.0.join("journal")).unwrap();
    let captured = capture_discovered(current.clone(), config, &RecordingInputs::new(&journal, 1)).unwrap();
    journal.with_access_view(|view| {
        assert_eq!(validate_observed_demand(current, &captured, config, &view, limits()).err().unwrap().kind(), io::ErrorKind::Unsupported); Ok(())
    }).unwrap();
}

#[test]
fn observed_resource_coverage_requires_additional_skin_input_and_declines_unknown_encoding() {
    let root = Root::new();
    std::fs::write(root.0.join("skin.txt"), b"skin source").unwrap();
    let additional = [dm_resources::ResourceRequest { archive_name: "skin.txt".into(), disk_path: root.0.join("skin.txt") }];
    let current = discover_demand(&DirectivePlan { project_dir: root.0.clone(), ..Default::default() },
        &ExpandedRegions::default(), &[], &additional).unwrap();
    let policy = raw_policy();
    let config = CaptureConfig { policy: &policy, encoded: &[], additional: &additional };
    let journal = Inputs::record(&root.0.join("journal")).unwrap();
    let captured = capture_discovered(current.clone(), config, &RecordingInputs::new(&journal, 1)).unwrap();
    journal.with_access_view(|view| {
        assert_eq!(validate_observed_demand(current.clone(), &captured, config, &view, limits())?.resource_aliases, 1);
        let unsupported = CapturePolicy::default();
        assert!(validate_observed_demand(current.clone(), &captured,
            CaptureConfig { policy: &unsupported, encoded: &[], additional: &additional }, &view, limits()).is_err());
        Ok(())
    }).unwrap();
    let incomplete = Inputs::record(&root.0.join("incomplete")).unwrap();
    incomplete.list(&root.0).unwrap();
    incomplete.with_access_view(|view| {
        assert!(validate_observed_demand(current, &captured, config, &view, limits()).is_err()); Ok(())
    }).unwrap();
}
