use super::*;
use crate::input_snapshot::{FolderListing, Stamp};
use dm_analysis::policy_inputs::{Coverage, TextView};
use std::sync::Mutex;

#[derive(Clone, Default)]
struct Memory(Arc<Mutex<BTreeMap<PathBuf, Vec<u8>>>>);
impl Memory {
    fn put(&self, path: &str, bytes: &[u8]) {
        self.0
            .lock()
            .unwrap()
            .insert(canonical_path(Path::new(path)), bytes.to_vec());
    }
    fn stamp_bytes(bytes: &[u8]) -> Stamp {
        Stamp {
            size: bytes.len() as u64,
            modified_ns: 1,
            file_id: Some(1),
        }
    }
}
impl SnapshotProvider for Memory {
    fn stamp(&self, path: &Path) -> io::Result<Stamp> {
        self.0
            .lock()
            .unwrap()
            .get(&canonical_path(path))
            .map(|b| Self::stamp_bytes(b))
            .ok_or_else(|| io::Error::from(io::ErrorKind::NotFound))
    }
    fn read(&self, path: &Path) -> io::Result<(Stamp, Vec<u8>)> {
        self.0
            .lock()
            .unwrap()
            .get(&canonical_path(path))
            .map(|bytes| (Self::stamp_bytes(bytes), bytes.clone()))
            .ok_or_else(|| io::Error::from(io::ErrorKind::NotFound))
    }
    fn list(&self, folder: &Path) -> io::Result<FolderListing> {
        let folder = canonical_path(folder);
        let files = self.0.lock().unwrap();
        let mut names = std::collections::BTreeSet::new();
        for path in files.keys() {
            if let Ok(relative) = path.strip_prefix(&folder) {
                if let Some(name) = relative.components().next() {
                    names.insert(name.as_os_str().to_string_lossy().into_owned());
                }
            }
        }
        Ok(if names.is_empty() {
            FolderListing::Missing
        } else {
            FolderListing::Present(names.into_iter().collect())
        })
    }
}
fn setup() -> (Memory, RecordingInputs<Memory>, ColdFrontend) {
    let memory = Memory::default();
    memory.put("policy-root/project.dme", b"/datum/test\n");
    let inputs = RecordingInputs::new(memory.clone(), 1);
    let frontend = dm_tree::frontend::build(
        Path::new("policy-root/project.dme"),
        &inputs,
        &Default::default(),
        1,
    )
    .unwrap();
    (memory, inputs, frontend)
}
fn request(path: &str, role: PolicyRole, required: bool) -> RequestedPolicyFile {
    RequestedPolicyFile {
        path: path.into(),
        role,
        required,
    }
}

#[test]
fn explicit_policy_files_share_compiled_text_without_changing_membership() {
    let (memory, inputs, frontend) = setup();
    memory.put("policy-root/unused.dm", b"/datum/not_compiled\n");
    memory.put("policy-root/analysis.toml", b"disabled = false\r\n");
    let revision = frontend.source_export_revision();
    let captured = capture(
        &frontend,
        &inputs,
        &[
            request("policy-root/unused.dm", PolicyRole::DmSource, true),
            request("policy-root/analysis.toml", PolicyRole::Configuration, true),
        ],
        &[],
    )
    .unwrap();
    assert_eq!(captured.policy().coverage(), Coverage::CapturedFilesOnly);
    assert_eq!(captured.policy().revision().compiler_source, revision);
    assert!(frontend
        .snapshot
        .tree
        .lookup_type(dm_ir::SymbolId::of("/datum/not_compiled"))
        .is_none());
    let unused = captured
        .policy()
        .file(Path::new("policy-root/unused.dm"))
        .unwrap();
    assert!(!unused.is_compiled());
    assert_eq!(
        unused.view(TextView::AnalyzeRaw).unwrap().as_str(),
        "/datum/not_compiled\n"
    );
    let compiled = frontend.files.iter().find(|file| file.captured).unwrap();
    let policy = captured.policy().file(&compiled.path).unwrap();
    assert!(policy.is_compiled());
    assert!(policy
        .view(TextView::AnalyzeRaw)
        .unwrap()
        .same_view(&compiled.text));
    assert_eq!(
        captured
            .policy()
            .file(Path::new("policy-root/analysis.toml"))
            .unwrap()
            .view(TextView::AnalyzeRaw)
            .unwrap()
            .as_str(),
        "disabled = false\n"
    );
    assert_eq!(captured.facts().files().count(), 3);
    assert!(captured
        .facts()
        .same_recorded_facts(&inputs.snapshot().unwrap()));
}

#[test]
fn optional_absence_and_requested_search_folders_remain_validation_facts() {
    let (memory, inputs, frontend) = setup();
    let captured = capture(
        &frontend,
        &inputs,
        &[request(
            "policy-root/optional.toml",
            PolicyRole::Configuration,
            false,
        )],
        &["policy-root/search".into()],
    )
    .unwrap();
    assert_eq!(
        captured.missing_paths(),
        &[canonical_path(Path::new("policy-root/optional.toml"))]
    );
    assert!(captured
        .facts()
        .folders()
        .contains_key(&canonical_path(Path::new("policy-root/search"))));
    assert!(captured
        .facts()
        .validate(&memory, true, 2)
        .unwrap()
        .0
        .unchanged());
    memory.put("policy-root/optional.toml", b"enabled = true");
    memory.put("policy-root/search/new.dm", b"/datum/new");
    assert!(!captured
        .facts()
        .validate(&memory, true, 3)
        .unwrap()
        .0
        .unchanged());
}

#[test]
fn compiler_and_analyze_decoding_keep_distinct_raw_contracts() {
    assert_eq!(
        analyze_raw(b"\xef\xbb\xbfA\x80\r\nB\rC").as_str(),
        "\u{feff}A\u{fffd}\nB\nC"
    );
    let (memory, inputs, frontend) = setup();
    memory.put("policy-root/unused.dm", b"// \x80\r\n/datum/unused\r");
    let captured = capture(
        &frontend,
        &inputs,
        &[request("policy-root/unused.dm", PolicyRole::DmSource, true)],
        &[],
    )
    .unwrap();
    let file = captured
        .policy()
        .file(Path::new("policy-root/unused.dm"))
        .unwrap();
    assert_eq!(
        file.view(TextView::CompilerDecoded).unwrap().as_str(),
        "// \u{20ac}\r\n/datum/unused\r"
    );
    assert_eq!(
        file.view(TextView::AnalyzeRaw).unwrap().as_str(),
        "// \u{fffd}\n/datum/unused\n"
    );
}

#[test]
fn proven_source_capture_is_historical_and_final_validation_detects_later_mutation() {
    let (memory, inputs, frontend) = setup();
    memory.put("policy-root/project.dme", b"/datum/else\n");
    let captured = capture(&frontend, &inputs, &[], &[]).unwrap();
    let file = captured
        .policy()
        .file(Path::new("policy-root/project.dme"))
        .unwrap();
    assert_eq!(
        file.view(TextView::AnalyzeRaw).unwrap().as_str(),
        "/datum/test\n"
    );
    assert!(!captured
        .facts()
        .validate(&memory, true, 2)
        .unwrap()
        .0
        .unchanged());
    assert!(
        inputs
            .read_candidate(Path::new("policy-root/project.dme"))
            .is_err(),
        "contradictory explicit reread still fails"
    );
    let foreign = RecordingInputs::new(memory, 2);
    assert!(capture(&frontend, &foreign, &[], &[]).is_err());
}

#[test]
fn policy_retention_admission_is_explicit_and_saturating() {
    assert!(admit_capture_charge(MAX_POLICY_CAPTURE_CHARGE).is_ok());
    assert!(admit_capture_charge(MAX_POLICY_CAPTURE_CHARGE + 1).is_err());
    assert!(admit_capture_charge(usize::MAX).is_err());
    let (_, inputs, frontend) = setup();
    assert!(
        capture(&frontend, &inputs, &[], &[])
            .unwrap()
            .budget_charge()
            >= 4096
    );
}

#[test]
fn replay_requires_all_policy_facts_but_allows_later_resource_facts() {
    let (_, inputs, frontend) = setup();
    let captured = capture(
        &frontend,
        &inputs,
        &[request(
            "policy-root/optional.toml",
            PolicyRole::Configuration,
            false,
        )],
        &[],
    )
    .unwrap();
    assert!(captured.is_recorded_in(&inputs.snapshot().unwrap()));
    let mut extended = inputs.snapshot().unwrap();
    extended
        .record_file(
            Path::new("policy-root/icon.dmi"),
            Memory::stamp_bytes(b"icon"),
            b"icon",
        )
        .unwrap();
    assert!(captured.is_recorded_in(&extended));
    assert!(!captured.is_recorded_in(&InputSnapshot::new(2)));
}

#[derive(Clone)]
struct Counted {
    memory: Memory,
    reads: Arc<std::sync::atomic::AtomicUsize>,
    config_pointer: Arc<std::sync::atomic::AtomicUsize>,
}
impl SnapshotProvider for Counted {
    fn stamp(&self, path: &Path) -> io::Result<Stamp> {
        self.memory.stamp(path)
    }
    fn list(&self, path: &Path) -> io::Result<FolderListing> {
        self.memory.list(path)
    }
    fn read(&self, path: &Path) -> io::Result<(Stamp, Vec<u8>)> {
        use std::sync::atomic::Ordering;
        self.reads.fetch_add(1, Ordering::Relaxed);
        let value = self.memory.read(path)?;
        if path.extension().is_some_and(|ext| ext == "toml") {
            self.config_pointer
                .store(value.1.as_ptr() as usize, Ordering::Relaxed);
        }
        Ok(value)
    }
}
fn counted(source: &[u8]) -> (Counted, RecordingInputs<Counted>, ColdFrontend) {
    let provider = Counted {
        memory: Memory::default(),
        reads: Arc::new(Default::default()),
        config_pointer: Arc::new(Default::default()),
    };
    provider.memory.put("policy-root/project.dme", source);
    let inputs = RecordingInputs::new(provider.clone(), 1);
    let frontend = dm_tree::frontend::build(
        Path::new("policy-root/project.dme"),
        &inputs,
        &Default::default(),
        1,
    )
    .unwrap();
    (provider, inputs, frontend)
}
#[test]
fn normal_compiled_utf8_source_is_read_once_and_raw_owner_is_shared() {
    use std::sync::atomic::Ordering;
    let (provider, inputs, frontend) = counted(b"/datum/test\n");
    assert_eq!(provider.reads.load(Ordering::Relaxed), 1);
    let captured = capture(&frontend, &inputs, &[], &[]).unwrap();
    assert_eq!(
        provider.reads.load(Ordering::Relaxed),
        1,
        "no second physical source read"
    );
    let source = frontend.files.iter().find(|file| file.captured).unwrap();
    assert!(captured
        .policy()
        .file(&source.path)
        .unwrap()
        .view(TextView::AnalyzeRaw)
        .unwrap()
        .same_view(&source.text));
    assert!(captured
        .facts()
        .folders()
        .contains_key(&canonical_path(Path::new("policy-root"))));
}
#[test]
fn crlf_and_bom_raw_views_use_their_single_authenticated_acquisition() {
    use std::sync::atomic::Ordering;
    let (provider, inputs, frontend) = counted(b"/datum/test\r\n");
    let captured = capture(&frontend, &inputs, &[], &[]).unwrap();
    assert_eq!(provider.reads.load(Ordering::Relaxed), 1);
    let file = captured
        .policy()
        .file(Path::new("policy-root/project.dme"))
        .unwrap();
    assert_eq!(
        file.view(TextView::CompilerDecoded).unwrap().as_str(),
        "/datum/test\r\n"
    );
    assert_eq!(
        file.view(TextView::AnalyzeRaw).unwrap().as_str(),
        "/datum/test\n"
    );
    let (provider, inputs, frontend) = counted(b"\xef\xbb\xbf/datum/test\n");
    capture(&frontend, &inputs, &[], &[]).unwrap();
    assert_eq!(
        provider.reads.load(Ordering::Relaxed),
        1,
        "BOM raw view must use the retained authenticated original, not reread"
    );
    provider
        .memory
        .put("policy-root/project.dme", b"\xef\xbb\xbf/datum/else\n");
    let historical = capture(&frontend, &inputs, &[], &[]).unwrap();
    assert_eq!(provider.reads.load(Ordering::Relaxed), 1);
    assert_eq!(
        historical
            .policy()
            .file(Path::new("policy-root/project.dme"))
            .unwrap()
            .view(TextView::AnalyzeRaw)
            .unwrap()
            .as_str(),
        "\u{feff}/datum/test\n"
    );
    // Historical capture stays immutable; publication freshness rejects the
    // now-different live file instead of silently recapturing a newer revision.
    assert!(!historical
        .facts()
        .validate(&provider, true, 2)
        .unwrap()
        .0
        .unchanged());
}
#[test]
fn strict_configuration_bytes_keep_same_authenticated_allocation_and_invalid_utf8() {
    use std::sync::atomic::Ordering;
    let (provider, inputs, frontend) = counted(b"/datum/test\n");
    let bytes = b"key = \xff\r\n";
    provider.memory.put("policy-root/checker.toml", bytes);
    let captured = capture(
        &frontend,
        &inputs,
        &[
            request("policy-root/checker.toml", PolicyRole::Configuration, true),
            request(
                "policy-root/optional.toml",
                PolicyRole::Configuration,
                false,
            ),
        ],
        &[],
    )
    .unwrap();
    let raw = captured
        .configuration_bytes(Path::new("policy-root/checker.toml"))
        .unwrap()
        .unwrap();
    assert_eq!(raw, bytes);
    assert_eq!(
        raw.as_ptr() as usize,
        provider.config_pointer.load(Ordering::Relaxed),
        "raw configuration moved without copying"
    );
    assert!(
        std::str::from_utf8(raw).is_err(),
        "strict config readers must reject these bytes"
    );
    assert_eq!(
        captured
            .policy()
            .file(Path::new("policy-root/checker.toml"))
            .unwrap()
            .view(TextView::AnalyzeRaw)
            .unwrap()
            .as_str(),
        "key = \u{fffd}\n"
    );
    assert!(captured
        .configuration_bytes(Path::new("policy-root/project.dme"))
        .is_err());
    assert!(captured
        .configuration_bytes(Path::new("policy-root/missing.toml"))
        .is_err());
    assert!(captured
        .configuration_bytes(Path::new("policy-root/optional.toml"))
        .unwrap()
        .is_none());
}

fn binding_setup() -> (Memory, RecordingInputs<Memory>, ColdFrontend, PathBuf) {
    // Absolute synthetic provider paths only; this creates no filesystem tree.
    let root = std::env::current_dir()
        .unwrap()
        .join("policy-binding-fixture");
    let memory = Memory::default();
    memory.put(root.join("p.dme").to_str().unwrap(), b"/datum/test\n");
    memory.put(
        root.join("extra.dm").to_str().unwrap(),
        b"SCHEMA(/datum/test, value, schema_msg())\n",
    );
    let inputs = RecordingInputs::new(memory.clone(), 1);
    let frontend =
        dm_tree::frontend::build(&root.join("p.dme"), &inputs, &Default::default(), 1).unwrap();
    (memory, inputs, frontend, root)
}
fn bind_intent(
    files: Vec<crate::policy_request::PolicyInputFile>,
) -> crate::policy_request::AdmittedPolicyRequest {
    crate::policy_request::PolicyInputRequest {analysis_context:None,workspace_auxiliary:Vec::new(),workspace_generators:Vec::new(),
        workspace: None,
        files,
        search_folders: vec![],
    }
    .admit()
    .unwrap()
}
#[test]
fn binding_rejects_unrequested_noncompiled_files_and_missing_paths() {
    let (_, inputs, frontend, root) = binding_setup();
    let empty = bind_intent(vec![]);
    let extra = RequestedPolicyFile {
        path: root.join("extra.dm"),
        role: PolicyRole::DmSource,
        required: true,
    };
    assert!(capture(&frontend, &inputs, &[extra], &[])
        .unwrap()
        .bind_request(&empty)
        .is_err());
    let absent = RequestedPolicyFile {
        path: root.join("optional.toml"),
        role: PolicyRole::Configuration,
        required: false,
    };
    assert!(capture(&frontend, &inputs, &[absent], &[])
        .unwrap()
        .bind_request(&empty)
        .is_err());
}
#[test]
fn binding_checks_missing_roles_and_allows_implicit_compiler_and_parent_facts() {
    use crate::policy_request::{PolicyInputFile, PolicyInputRole};
    let (_, inputs, frontend, root) = binding_setup();
    let missing_dm = RequestedPolicyFile {
        path: root.join("optional.dm"),
        role: PolicyRole::DmSource,
        required: false,
    };
    let wrong = bind_intent(vec![PolicyInputFile {
        path: missing_dm.path.clone(),
        role: PolicyInputRole::Configuration,
        required: false,
    }]);
    assert!(capture(&frontend, &inputs, &[missing_dm], &[])
        .unwrap()
        .bind_request(&wrong)
        .is_err());
    let missing_config = RequestedPolicyFile {
        path: root.join("optional.toml"),
        role: PolicyRole::Configuration,
        required: false,
    };
    let wrong = bind_intent(vec![PolicyInputFile {
        path: missing_config.path.clone(),
        role: PolicyInputRole::DmSource,
        required: false,
    }]);
    assert!(capture(
        &frontend,
        &inputs,
        std::slice::from_ref(&missing_config),
        &[]
    )
    .unwrap()
    .bind_request(&wrong)
    .is_err());
    let extra = RequestedPolicyFile {
        path: root.join("extra.dm"),
        role: PolicyRole::DmSource,
        required: true,
    };
    let right = bind_intent(vec![
        PolicyInputFile {
            path: extra.path.clone(),
            role: PolicyInputRole::DmSource,
            required: true,
        },
        PolicyInputFile {
            path: missing_config.path.clone(),
            role: PolicyInputRole::Configuration,
            required: false,
        },
    ]);
    let captured = capture(&frontend, &inputs, &[extra, missing_config], &[])
        .unwrap()
        .bind_request(&right)
        .unwrap();
    assert!(captured.policy_revision().is_some());
    assert!(
        captured
            .facts()
            .folders()
            .contains_key(&canonical_path(&root)),
        "parent-directory proof extras are permitted"
    );
}

#[test]
fn generated_source_reads_and_warm_preparations_keep_current_file_receipts() {
    use crate::input_snapshot::{GeneratedOutputInputs, PreparedInputArtifacts};
    let memory = Memory::default();
    memory.put(
        "policy-root/project.dme",
        b"#include \"parent.dm\"\n#include \"map.dmm\"\n#include \"skin.dmf\"\n",
    );
    memory.put(
        "policy-root/parent.dm",
        b"#include \"code/_generated/child.dm\"\n",
    );
    memory.put(
        "policy-root/code/_generated/child.dm",
        b"/datum/generated\n",
    );
    memory.put(
        "policy-root/map.dmm",
        b"map source is deliberately not parsed as DM\n",
    );
    memory.put(
        "policy-root/skin.dmf",
        b"skin source is deliberately not parsed as DM\n",
    );
    let prepared = Arc::new(PreparedInputArtifacts::default());
    for scan in [1, 2] {
        let outputs = GeneratedOutputInputs::new(
            memory.clone(),
            [PathBuf::from("policy-root/code/_generated")],
        );
        let ledger =
            RecordingInputs::new(outputs, scan).with_prepared_sources(Some(prepared.clone()));
        let inputs = crate::native_inputs::NativeInputs::prepare(
            Path::new("policy-root/project.dme"),
            &ledger,
            1,
        )
        .unwrap();
        let provider = inputs.provider(&ledger);
        let frontend = dm_tree::frontend::build(
            Path::new("policy-root/project.dme"),
            &provider,
            &Default::default(),
            1,
        )
        .unwrap();
        let generated = canonical_path(Path::new("policy-root/code/_generated/child.dm"));
        assert!(ledger.snapshot().unwrap().contains_file(&generated));
        assert!(frontend
            .files
            .iter()
            .any(|file| file.path.as_ref() == &generated && file.captured));
        for name in ["map.dmm", "skin.dmf"] {
            assert!(frontend
                .files
                .iter()
                .any(|file| file.path.ends_with(name) && !file.captured));
            assert!(!ledger
                .snapshot()
                .unwrap()
                .contains_file(&canonical_path(&Path::new("policy-root").join(name))));
        }
        let captured = capture(&frontend, &ledger, &[], &[]).unwrap();
        assert!(captured.policy().file(&generated).unwrap().is_compiled());
        for name in ["map.dmm", "skin.dmf"] {
            assert!(captured
                .policy()
                .file(&Path::new("policy-root").join(name))
                .is_none());
        }
        assert!(captured.facts().contains_file(&generated));
        ledger.finish_prepared().unwrap();
    }
}

#[test]
fn binding_requires_exact_explicit_search_scope_not_incidental_folder_proofs() {
    use crate::policy_request::PolicyInputRequest;
    let (_, inputs, frontend) = setup();
    let folder = std::env::current_dir().unwrap().join("policy-search-scope");
    let empty = PolicyInputRequest::default().admit().unwrap();
    let expected = PolicyInputRequest {analysis_context:None,workspace_auxiliary:Vec::new(),workspace_generators:Vec::new(),
        workspace: None,
        files: vec![],
        search_folders: vec![folder.clone()],
    }
    .admit()
    .unwrap();
    assert!(capture(&frontend, &inputs, &[], &[folder.clone()])
        .unwrap()
        .bind_request(&empty)
        .is_err());
    // A prior incidental folder proof does not authorize an explicit search.
    assert!(inputs
        .snapshot()
        .unwrap()
        .folders()
        .contains_key(&canonical_path(&folder)));
    assert!(capture(&frontend, &inputs, &[], &[])
        .unwrap()
        .bind_request(&expected)
        .is_err());
    let aliases = [folder.clone(), folder.join("child/.."), folder.clone()];
    let captured = capture(&frontend, &inputs, &[], &aliases)
        .unwrap()
        .bind_request(&expected)
        .unwrap();
    assert_eq!(
        captured.explicit_search_folders(),
        expected.search_folders()
    );
}
#[test]
fn unique_owner_capture_counts_shared_views_and_independent_noncompiled_equal_files() {
    let (memory, inputs, frontend) = setup();
    let extra = "/datum/extra\n".to_owned() + &"// retained source bytes\n".repeat(1024);
    memory.put("policy-root/extra1.dm", extra.as_bytes());
    memory.put("policy-root/extra2.dm", extra.as_bytes());
    let captured = Arc::new(
        capture(
            &frontend,
            &inputs,
            &[
                request("policy-root/extra1.dm", PolicyRole::DmSource, true),
                request("policy-root/extra2.dm", PolicyRole::DmSource, true),
            ],
            &[],
        )
        .unwrap(),
    );
    let mut owners = owner_charge::Owners::default();
    for file in captured.policy().files() {
        assert!(file
            .view(TextView::CompilerDecoded)
            .unwrap()
            .same_view(file.view(TextView::AnalyzeRaw).unwrap()));
        for (_, text) in file.views() {
            owners.text(text).unwrap();
        }
    }
    assert_eq!(owners.totals().text_backings, 3);
    assert_eq!(owners.totals().text_payloads, 3);
    assert!(owners.totals().payload_capacity >= 2 * extra.len());
    assert!(captured.budget_charge() < MAX_POLICY_CAPTURE_CHARGE);
}
#[test]
fn capture_census_deduplicates_owner_aliases_and_does_not_retain_extra_source() {
    let (memory, inputs, frontend) = setup();
    memory.put("policy-root/extra.dm", b"/datum/extra\n");
    let captured = Arc::new(
        capture(
            &frontend,
            &inputs,
            &[request("policy-root/extra.dm", PolicyRole::DmSource, true)],
            &[],
        )
        .unwrap(),
    );
    let weak = captured
        .policy()
        .file(Path::new("policy-root/extra.dm"))
        .unwrap()
        .view(TextView::AnalyzeRaw)
        .unwrap()
        .downgrade();
    let mut once = crate::heap_census::HeapCensus::new("once");
    once.policy_capture(&captured);
    let once = once.finish();
    let mut twice = crate::heap_census::HeapCensus::new("twice");
    twice.policy_capture(&captured);
    twice.policy_capture(&captured);
    let twice = twice.finish();
    assert_eq!(
        once.unique_known_capacity_bytes,
        twice.unique_known_capacity_bytes
    );
    drop(captured);
    assert!(weak.upgrade().is_none());
}

fn manifest_intent(
    path: PathBuf,
    role: crate::policy_request::PolicyInputRole,
) -> crate::policy_request::AdmittedPolicyRequest {
    bind_intent(vec![crate::policy_request::PolicyInputFile {
        path,
        role,
        required: false,
    }])
}
#[test]
fn untyped_manifest_requires_exact_requested_role_and_recorded_absence() {
    use crate::policy_request::PolicyInputRole;
    use dq_analyze::captured_untyped::ManifestRead;
    let (_, inputs, frontend, root) = binding_setup();
    let unrequested = capture(&frontend, &inputs, &[], &[])
        .unwrap()
        .bind_request(&bind_intent(vec![]))
        .unwrap();
    assert!(unrequested.untyped_manifest(&root).is_err());
    let manifest = root.join("deepquarry.dme");
    let intent = manifest_intent(manifest.clone(), PolicyInputRole::DmSource);
    let captured = capture(&frontend, &inputs, &intent.capture_files(), &[])
        .unwrap()
        .bind_request(&intent)
        .unwrap();
    assert!(matches!(
        captured.untyped_manifest(&root).unwrap(),
        ManifestRead::ProvenUnavailable
    ));
    assert!(captured.untyped_manifest(&root.join("foreign")).is_err());
    let wrong = manifest_intent(manifest, PolicyInputRole::Configuration);
    let captured = capture(&frontend, &inputs, &wrong.capture_files(), &[])
        .unwrap()
        .bind_request(&wrong)
        .unwrap();
    assert!(captured.untyped_manifest(&root).is_err());
}
#[test]
fn untyped_uncompiled_manifest_preserves_exact_bom_crlf_and_policy_revision() {
    use crate::policy_request::PolicyInputRole;
    use dq_analyze::captured_untyped::ManifestRead;
    let (memory, inputs, frontend, root) = binding_setup();
    let path = root.join("deepquarry.dme");
    let bytes =
        b"\xef\xbb\xbf#include \"code/a.dm\"\r\n#if 0\r\n#include \"code/b.dm\"\r\n#endif\r\n";
    memory.put(path.to_str().unwrap(), bytes);
    let intent = manifest_intent(path.clone(), PolicyInputRole::DmSource);
    let captured = capture(&frontend, &inputs, &intent.capture_files(), &[])
        .unwrap()
        .bind_request(&intent)
        .unwrap();
    match captured.untyped_manifest(&root).unwrap() {
        ManifestRead::OriginalBytes(original) => assert_eq!(original, bytes),
        _ => panic!("uncompiled original bytes were not retained"),
    }
    let pin = captured.policy_revision();
    // Query is a prepared-frame read, not IO. Provider mutation cannot mix bytes.
    memory.put(path.to_str().unwrap(), b"// changed manifest\n");
    match captured.untyped_manifest(&root).unwrap() {
        ManifestRead::OriginalBytes(original) => assert_eq!(original, bytes),
        _ => panic!("manifest authority changed without prepare"),
    }
    let next_inputs = RecordingInputs::new(memory, 2);
    let next_front =
        dm_tree::frontend::build(&root.join("p.dme"), &next_inputs, &Default::default(), 1)
            .unwrap();
    let next = capture(&next_front, &next_inputs, &intent.capture_files(), &[])
        .unwrap()
        .bind_request(&intent)
        .unwrap();
    assert_eq!(
        frontend.source_export_revision(),
        next_front.source_export_revision()
    );
    assert_ne!(pin, next.policy_revision());
    assert_ne!(
        captured.policy().revision().policy_inputs,
        next.policy().revision().policy_inputs
    );
}
#[test]
fn untyped_compiled_manifest_uses_private_original_receipt_with_bom() {
    use dq_analyze::captured_untyped::ManifestRead;
    let root = std::env::current_dir()
        .unwrap()
        .join("compiled-manifest-receipt");
    let path = root.join("deepquarry.dme");
    let bytes = b"\xef\xbb\xbf/datum/probe\r\n";
    let memory = Memory::default();
    memory.put(path.to_str().unwrap(), bytes);
    let inputs = RecordingInputs::new(memory, 1);
    let frontend = dm_tree::frontend::build(&path, &inputs, &Default::default(), 1).unwrap();
    let captured = capture(&frontend, &inputs, &[], &[])
        .unwrap()
        .bind_request(&bind_intent(vec![]))
        .unwrap();
    match captured.untyped_manifest(&root).unwrap() {
        ManifestRead::CompiledOriginalBytes(original) => assert_eq!(original, bytes),
        _ => panic!("compiled BOM original was reconstructed or discarded"),
    }
}
#[test]
fn untyped_input_registry_is_canonical_exact_archive_and_bounded_metadata_only() {
    let (_, inputs, frontend, _) = binding_setup();
    let capture = capture(&frontend, &inputs, &[], &[])
        .unwrap()
        .bind_request(&bind_intent(vec![]))
        .unwrap();
    let before = capture.budget_charge();
    let a = capture
        .untyped_input(&["/datum/b".into(), "/datum/a".into(), "/datum/a".into()])
        .unwrap();
    let b = capture
        .untyped_input(&["/datum/a".into(), "/datum/b".into()])
        .unwrap();
    assert!(Arc::ptr_eq(&a, &b));
    assert!(Arc::ptr_eq(a.archive(), capture.policy().archive()));
    assert_eq!(a.exempt_types(), &["/datum/a", "/datum/b"]);
    assert!(capture.budget_charge() > before);
    assert!(capture.untyped_input(&["x".repeat(65537)]).is_err());
    for n in 0..15 {
        capture.untyped_input(&[format!("/datum/p{n}")]).unwrap();
    }
    assert!(capture.untyped_input(&["/datum/overflow".into()]).is_err());
    assert!(Arc::ptr_eq(
        &a,
        &capture
            .untyped_input(&["/datum/b".into(), "/datum/a".into()])
            .unwrap()
    ));
}

#[derive(Clone)]
struct DeniedManifest(Memory);
impl SnapshotProvider for DeniedManifest {
    fn stamp(&self, path: &Path) -> io::Result<Stamp> {
        if path.file_name().is_some_and(|p| p == "deepquarry.dme") {
            return Err(io::ErrorKind::PermissionDenied.into());
        }
        self.0.stamp(path)
    }
    fn read(&self, path: &Path) -> io::Result<(Stamp, Vec<u8>)> {
        if path.file_name().is_some_and(|p| p == "deepquarry.dme") {
            return Err(io::ErrorKind::PermissionDenied.into());
        }
        self.0.read(path)
    }
    fn list(&self, path: &Path) -> io::Result<FolderListing> {
        self.0.list(path)
    }
}
#[test]
fn untyped_manifest_optional_read_error_never_becomes_absence() {
    let root = std::env::current_dir().unwrap().join("denied-manifest");
    let memory = Memory::default();
    memory.put(root.join("p.dme").to_str().unwrap(), b"/datum/probe\n");
    let inputs = RecordingInputs::new(DeniedManifest(memory), 1);
    let frontend =
        dm_tree::frontend::build(&root.join("p.dme"), &inputs, &Default::default(), 1).unwrap();
    let intent = manifest_intent(
        root.join("deepquarry.dme"),
        crate::policy_request::PolicyInputRole::DmSource,
    );
    assert!(capture(&frontend, &inputs, &intent.capture_files(), &[]).is_err());
}
#[test]
fn untyped_manifest_mutated_private_negative_map_cannot_override_positive_fact() {
    let (memory, inputs, frontend, root) = binding_setup();
    let path = root.join("deepquarry.dme");
    memory.put(path.to_str().unwrap(), b"// present\n");
    let intent = manifest_intent(
        path.clone(),
        crate::policy_request::PolicyInputRole::DmSource,
    );
    let mut c = capture(&frontend, &inputs, &intent.capture_files(), &[])
        .unwrap()
        .bind_request(&intent)
        .unwrap();
    c.manifest_originals.insert(path.clone(), None);
    c.missing.push(path);
    assert!(c.untyped_manifest(&root).is_err());
}
