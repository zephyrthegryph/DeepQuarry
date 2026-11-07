use super::*;
use std::sync::Mutex;
struct P {
    value: Mutex<PolicyDirectoryListing>,
}
impl SnapshotProvider for P {
    fn stamp(&self, _: &Path) -> io::Result<Stamp> {
        unreachable!()
    }
    fn read(&self, _: &Path) -> io::Result<(Stamp, Vec<u8>)> {
        unreachable!()
    }
    fn list(&self, _: &Path) -> io::Result<FolderListing> {
        Ok(FolderListing::Present(vec![]))
    }
    fn policy_directory(
        &self,
        _: &Path,
        _: bool,
        _: usize,
    ) -> io::Result<Option<PolicyDirectoryListing>> {
        Ok(Some(self.value.lock().unwrap().clone()))
    }
}
fn listing(kind: PolicyEntryKind) -> PolicyDirectoryListing {
    PolicyDirectoryListing::Present(
        vec![PolicyDirectoryEntry {
            name: "x.dm".into(),
            kind,
        }]
        .into(),
    )
}
#[test]
fn unchanged_names_changed_kind_invalidates_same_recorded_ledger() {
    let provider = P {
        value: Mutex::new(listing(PolicyEntryKind::File)),
    };
    let path = std::env::current_dir().unwrap().join("typed-kind-fixture");
    let inputs = RecordingInputs::new(&provider, 1);
    inputs.capture_policy_directory(&path, false).unwrap();
    let snapshot = inputs.snapshot().unwrap();
    *provider.value.lock().unwrap() = listing(PolicyEntryKind::Directory);
    let (report, next) = snapshot.validate(&provider, true, 2).unwrap();
    assert_eq!(report.changed, vec![path]);
    assert!(!snapshot.same_recorded_facts(&next));
}
#[test]
fn missing_and_empty_present_are_not_the_same_discovery_fact() {
    let provider = P {
        value: Mutex::new(PolicyDirectoryListing::Missing),
    };
    let path = std::env::current_dir()
        .unwrap()
        .join("typed-missing-fixture");
    let inputs = RecordingInputs::new(&provider, 1);
    inputs.capture_policy_directory(&path, true).unwrap();
    let snapshot = inputs.snapshot().unwrap();
    *provider.value.lock().unwrap() = PolicyDirectoryListing::Present(vec![].into());
    assert!(!snapshot.validate(&provider, true, 2).unwrap().0.unchanged());
}
#[test]
fn root_follow_mode_cannot_be_reinterpreted_under_existing_capture() {
    let provider = P {
        value: Mutex::new(listing(PolicyEntryKind::File)),
    };
    let path = std::env::current_dir().unwrap().join("typed-mode-fixture");
    let inputs = RecordingInputs::new(provider, 1);
    inputs.capture_policy_directory(&path, true).unwrap();
    assert!(inputs.capture_policy_directory(&path, false).is_err());
    assert_eq!(inputs.snapshot().unwrap().shape().1, 1);
}
#[test]
fn snapshots_share_metadata_owners_but_equal_deserialized_payload_is_a_new_owner() {
    let mut snapshot = InputSnapshot::new(1);
    let path = std::env::current_dir().unwrap().join("typed-owner-fixture");
    snapshot
        .record_policy_directory(&path, true, listing(PolicyEntryKind::File))
        .unwrap();
    let clone = snapshot.clone();
    let decoded: InputSnapshot =
        serde_json::from_slice(&serde_json::to_vec(&snapshot).unwrap()).unwrap();
    decoded.check_structure().unwrap();
    let one = &snapshot.policy_directories[&path].listing;
    let alias = &clone.policy_directories[&path].listing;
    let independent = &decoded.policy_directories[&path].listing;
    let mut seen = BTreeSet::new();
    assert!(one.storage(&mut seen).unwrap() > 0);
    assert_eq!(alias.storage(&mut seen).unwrap(), 0);
    assert!(independent.storage(&mut seen).unwrap() > 0);
}
#[test]
fn malformed_leaf_cannot_escape_recursive_root_or_form_a_prefix() {
    for name in ["..", ".", "a/b", r"a\b", ""] {
        let value = PolicyDirectoryListing::Present(
            vec![PolicyDirectoryEntry {
                name: name.into(),
                kind: PolicyEntryKind::Directory,
            }]
            .into(),
        );
        assert!(value.check().is_err(), "{name:?}");
    }
}
#[test]
fn actual_directory_capacity_is_bounded_before_full_roster_collection() {
    let root = crate::test_scratch::dir("typed-directory-bound");
    std::fs::write(root.join("x.dm"), b"x").unwrap();
    assert!(filesystem_policy_directory(&root, true, 1).is_err());
}
#[cfg(unix)]
#[test]
fn declared_root_symlink_follows_but_child_link_kind_remains_symlink() {
    let root = crate::test_scratch::dir("typed-root-symlink");
    let target = root.join("target");
    std::fs::create_dir(&target).unwrap();
    std::fs::write(target.join("x.dm"), b"x").unwrap();
    std::os::unix::fs::symlink(&target, root.join("link")).unwrap();
    assert!(matches!(
        filesystem_policy_directory(&root.join("link"), false, 4096).unwrap(),
        PolicyDirectoryListing::NotDirectory
    ));
    assert!(matches!(
        filesystem_policy_directory(&root.join("link"), true, 4096).unwrap(),
        PolicyDirectoryListing::Present(_)
    ));
    let PolicyDirectoryListing::Present(entries) =
        filesystem_policy_directory(&root, true, 4096).unwrap()
    else {
        panic!()
    };
    assert_eq!(
        entries
            .iter()
            .find(|entry| entry.name == "link")
            .unwrap()
            .kind,
        PolicyEntryKind::Symlink
    );
}

#[test]
fn discovery_own_metadata_is_reserved_before_requesting_another_directory() {
    use std::sync::atomic::{AtomicUsize, Ordering};
    struct Probe(AtomicUsize);
    impl SnapshotProvider for Probe {
        fn stamp(&self, _: &Path) -> io::Result<Stamp> {
            unreachable!()
        }
        fn read(&self, _: &Path) -> io::Result<(Stamp, Vec<u8>)> {
            unreachable!()
        }
        fn list(&self, _: &Path) -> io::Result<FolderListing> {
            unreachable!()
        }
        fn policy_directory(
            &self,
            _: &Path,
            _: bool,
            limit: usize,
        ) -> io::Result<Option<PolicyDirectoryListing>> {
            self.0.store(limit, Ordering::SeqCst);
            Ok(Some(PolicyDirectoryListing::Present(Vec::new().into())))
        }
    }
    let inputs = RecordingInputs::new(Probe(AtomicUsize::new(0)), 1);
    let root = std::env::current_dir().unwrap().join("metadata-probe");
    assert!(inputs
        .capture_policy_directory_bounded(&root, true, METADATA_BOUND)
        .is_err());
    assert_eq!(
        inputs.provider.0.load(Ordering::SeqCst),
        0,
        "no provider allocation before admission"
    );
    inputs
        .capture_policy_directory_bounded(&root, true, 1024)
        .unwrap();
    assert!(inputs.provider.0.load(Ordering::SeqCst) < METADATA_BOUND - 1024);
}

#[test]
fn policy_file_observation_distinguishes_actual_content_absence_and_unobserved() {
    let root = crate::test_scratch::dir("policy-file-observation");
    let config = root.join("lint_scopes.toml");
    let absent = root.join("missing.toml");
    let input = RecordingInputs::new(FileSystemInputs, 0);
    assert!(input.recorded_policy_file_observation(&absent).is_err());
    assert!(input.read_policy_candidate(&absent, 4096).unwrap().is_none());
    assert_eq!(input.recorded_policy_file_observation(&absent).unwrap(), None);

    std::fs::write(&config, "[lint.one]\n").unwrap();
    input.read_policy_candidate(&config, 4096).unwrap().unwrap();
    let first = input.recorded_policy_file_observation(&config).unwrap().unwrap();
    std::fs::write(&config, "[lint.two]\n").unwrap();
    let later = RecordingInputs::new(FileSystemInputs, 0);
    later.read_policy_candidate(&config, 4096).unwrap().unwrap();
    let second = later.recorded_policy_file_observation(&config).unwrap().unwrap();
    assert_eq!(first.0.size, second.0.size);
    assert_ne!(first.1, second.1);
}
