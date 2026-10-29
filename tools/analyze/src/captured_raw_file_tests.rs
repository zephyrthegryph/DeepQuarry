use super::*;
use dm_analysis::policy_inputs::{HostCapture, PolicyInputs, PolicyRole, TextView};
use std::{path::PathBuf, sync::Arc};
fn root() -> PathBuf {
    std::env::current_dir().unwrap().join("raw-file-fixture")
}
struct Sources;
impl dm_preprocess::SourceProvider for Sources {
    fn read(&self, path: &Path) -> Result<String, String> {
        Ok(match path.file_name().and_then(|p|p.to_str()){
    Some("p.dme")=>"#include \"code/a.dm\"\n#include \"code/b.dm\"\n",
    Some("a.dm")=>"/proc/a()\n    sleep(1)\n    sleep(2) // ALLOW(scheduler): intentionally retained raw policy annotation fixture\n",
    Some("b.dm")=>"/proc/b()\n    sleep(3)\n",_=>return Err("missing fixture".into()),
}.into())
    }
}
fn inputs() -> PolicyInputs {
    let frontend =
        dm_tree::frontend::build(&root().join("p.dme"), &Sources, &Default::default(), 1).unwrap();
    let extra: Vec<_> = frontend
        .files
        .iter()
        .filter(|f| f.captured)
        .map(|f| {
            HostCapture::analyze_raw(Arc::clone(&f.path), PolicyRole::DmSource, f.text.clone())
        })
        .collect();
    PolicyInputs::capture(&frontend, extra).unwrap()
}
#[test]
fn per_file_results_preserve_exact_old_sites_allow_consumption_and_notes() {
    let inputs = inputs();
    let config = Config::capture(Configuration::ProvenMissing).unwrap();
    let scope = config.scope("scheduler").unwrap();
    let mut sites = Vec::new();
    let mut allows = Vec::new();
    let mut notes = Vec::new();
    for file in inputs.files().filter(|f| f.role() == PolicyRole::DmSource) {
        let scanned = File::capture(
            &root(),
            file.path(),
            file.view(TextView::AnalyzeRaw).unwrap().clone(),
        )
        .unwrap()
        .scan(&scope)
        .unwrap();
        sites.extend(scanned.run.sites);
        allows.extend(scanned.allow_used);
        notes.extend(scanned.run.notes);
    }
    let previous = captured_raw_policy::CapturedRawPolicy::capture(
        &root(),
        &inputs,
        Configuration::ProvenMissing,
    )
    .unwrap()
    .scan(&["scheduler".into()], || Ok(()))
    .unwrap();
    assert_eq!(sites, previous[0].run.sites);
    assert_eq!(allows, previous[0].allow_used);
    assert_eq!(notes, previous[0].run.notes);
    assert_eq!(sites.len(), 2);
    assert_eq!(allows.len(), 1);
}
#[test]
fn interpreted_scope_only_changes_for_affected_configuration() {
    let a = Config::capture(Configuration::Captured(
        b"[lint.scheduler]\nexempt_files=['code/a.dm']\n",
    ))
    .unwrap();
    let b=Config::capture(Configuration::Captured(b"[lint.scheduler]\nexempt_files=['code/a.dm']\n[lint.breakpoint]\nexempt_files=['code/b.dm']\n")).unwrap();
    let c = Config::capture(Configuration::Captured(
        b"[lint.scheduler]\nexempt_files=['code/b.dm']\n",
    ))
    .unwrap();
    assert_eq!(
        a.scope("scheduler").unwrap().fingerprint(),
        b.scope("scheduler").unwrap().fingerprint()
    );
    assert_ne!(
        a.scope("scheduler").unwrap().fingerprint(),
        c.scope("scheduler").unwrap().fingerprint()
    );
    let invalid = Config::capture(Configuration::Captured(b"# bad \xff")).unwrap();
    let absent = Config::capture(Configuration::ProvenMissing).unwrap();
    assert_eq!(
        invalid.scope("scheduler").unwrap().fingerprint(),
        absent.scope("scheduler").unwrap().fingerprint()
    );
}
#[test]
fn per_file_boundary_rejects_foreign_root_and_unadmitted_policy() {
    let text: dm_preprocess::SourceText = "/proc/a()\n    sleep(1)\n".into();
    assert!(File::capture(
        &root(),
        &root().parent().unwrap().join("outside.dm"),
        text.clone()
    )
    .is_err());
    assert!(Config::capture(Configuration::ProvenMissing)
        .unwrap()
        .scope("tracked")
        .is_err());
    assert!(ordered_names(&["tracked".into()]).is_err());
}

#[test]
fn all_admitted_raw_policies_equal_whole_captured_file_order_and_allow_results() {
    let inputs = inputs();
    let config = Config::capture(Configuration::ProvenMissing).unwrap();
    let mut files: Vec<_> = inputs
        .files()
        .filter(|f| f.role() == PolicyRole::DmSource)
        .map(|f| {
            File::capture(
                &root(),
                f.path(),
                f.view(TextView::AnalyzeRaw).unwrap().clone(),
            )
            .unwrap()
        })
        .collect();
    files.sort_by_key(|f| crate::util::rel_slash(f.path(), &root()));
    let names: Vec<String> = captured_raw_policy::RAW_FILE_LINTS
        .iter()
        .map(|n| (*n).into())
        .collect();
    let old = captured_raw_policy::CapturedRawPolicy::capture(
        &root(),
        &inputs,
        Configuration::ProvenMissing,
    )
    .unwrap()
    .scan(&names, || Ok(()))
    .unwrap();
    for previous in old {
        let scope = config.scope(&previous.name).unwrap();
        let mut sites = Vec::new();
        let mut allows = Vec::new();
        let mut notes = Vec::new();
        for file in &files {
            let rows = file.scan(&scope).unwrap();
            sites.extend(rows.run.sites);
            allows.extend(rows.allow_used);
            notes.extend(rows.run.notes);
        }
        assert_eq!(sites, previous.run.sites, "{} sites", previous.name);
        assert_eq!(allows, previous.allow_used, "{} allows", previous.name);
        assert_eq!(notes, previous.run.notes, "{} notes", previous.name);
    }
}

#[cfg(windows)]
#[test]
fn per_file_report_accepts_safe_drive_alias_without_rewriting_provider_key() {
    let root = Path::new(r"E:\raw-file-fixture");
    let issued = Path::new(r"\\?\E:\raw-file-fixture\code\sample.dm");
    let file = File::capture(root, issued, "/proc/run()\n    sleep(1)\n".into()).unwrap();
    assert_eq!(file.path(), issued);
    let rows = file
        .scan(
            &Config::capture(Configuration::ProvenMissing)
                .unwrap()
                .scope("scheduler")
                .unwrap(),
        )
        .unwrap();
    assert_eq!(rows.run.sites.len(), 1);
    assert_eq!(rows.run.sites[0].rel, "code/sample.dm");
    assert!(File::capture(
        root,
        Path::new(r"\\.\E:\raw-file-fixture\code\sample.dm"),
        "/proc/run()\n    return\n".into()
    )
    .is_err());
    assert!(File::capture(
        root,
        Path::new(r"\\?\UNC\server\share\code\sample.dm"),
        "/proc/run()\n    return\n".into()
    )
    .is_err());
}
