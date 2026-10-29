#![cfg(windows)]
use super::*;
struct Files {
    saved: Option<SourceAliasProof>,
}
impl SnapshotProvider for Files {
    fn stamp(&self, path: &Path) -> io::Result<Stamp> {
        FileSystemInputs.stamp(path)
    }
    fn read(&self, path: &Path) -> io::Result<(Stamp, Vec<u8>)> {
        FileSystemInputs.read(path)
    }
    fn list(&self, path: &Path) -> io::Result<FolderListing> {
        FileSystemInputs.list(path)
    }
    fn source_alias(
        &self,
        path: &Path,
        challenge: &SourceAliasChallenge,
    ) -> io::Result<Option<SourceAliasProof>> {
        match &self.saved {
            Some(proof) => Ok(Some(proof.clone())),
            None => FileSystemInputs.source_alias(path, challenge),
        }
    }
}
fn files(label: &str) -> (PathBuf, PathBuf) {
    let root = crate::test_scratch::dir(label);
    std::fs::create_dir_all(root.join("code")).unwrap();
    let source = root.join("code/alias.dm");
    std::fs::write(&source, b"/datum/acquired_alias\n    var/value\n").unwrap();
    let project = root.join("project.dme");
    std::fs::write(&project, b"#include \"code/alias.dm\"\n").unwrap();
    (std::fs::canonicalize(project).unwrap(), source)
}
fn primary(frontend: &dm_tree::frontend::ColdFrontend) -> &dm_tree::frontend::SourceFile {
    frontend
        .files
        .iter()
        .find(|file| file.path.file_name() == Some(std::ffi::OsStr::new("alias.dm")))
        .unwrap()
}
#[test]
fn foreign_same_facts_response_cannot_answer_new_acquisition_challenge() {
    let (project, source) = files("alias-foreign-challenge");
    let first = RecordingInputs::new(Files { saved: None }, 4_000_000_000);
    let frontend = dm_tree::frontend::build(&project, &first, &Default::default(), 1).unwrap();
    let old = primary(&frontend);
    let proof = first
        .acquire_source_alias(&source, &old.path, &old.text)
        .unwrap()
        .unwrap();
    let second = RecordingInputs::new(
        Files {
            saved: Some(proof.proof.clone()),
        },
        4_000_000_001,
    );
    let other = dm_tree::frontend::build(&project, &second, &Default::default(), 1).unwrap();
    let current = primary(&other);
    assert!(
        old.text.same_view(&current.text),
        "same interned payload is not a challenge authority"
    );
    let error = second
        .acquire_source_alias(&source, &current.path, &current.text)
        .err()
        .unwrap();
    assert!(error
        .to_string()
        .contains("foreign acquired-source alias proof"));
    assert!(!second.snapshot().unwrap().contains_file(&source));
}
#[test]
fn journal_replay_reissues_exact_recorded_alias_against_new_genuine_challenge() {
    let (project, source) = files("alias-record-replay");
    let journal = crate::test_scratch::dir("alias-journal").join("journal");
    let recorded = RecordingInputs::new(
        crate::frozen_inputs::Inputs::record(&journal).unwrap(),
        4_000_000_000,
    );
    let frontend = dm_tree::frontend::build(&project, &recorded, &Default::default(), 1).unwrap();
    let old = primary(&frontend);
    let original = recorded
        .acquire_source_alias(&source, &old.path, &old.text)
        .unwrap()
        .unwrap();
    recorded.provider.finish().unwrap();
    let replay = RecordingInputs::new(
        crate::frozen_inputs::Inputs::replay(&journal).unwrap(),
        4_000_000_001,
    );
    let other = dm_tree::frontend::build(&project, &replay, &Default::default(), 1).unwrap();
    let current = primary(&other);
    let proof = replay
        .acquire_source_alias(&source, &current.path, &current.text)
        .unwrap()
        .unwrap();
    assert!(!Arc::ptr_eq(
        &original.proof.challenge.0,
        &proof.proof.challenge.0
    ));
    assert!(current.text.same_view(proof.lease().source_text()));
    let facts = replay.snapshot().unwrap();
    assert!(facts.contains_file(&source));
    assert!(facts.contains_file(current.path.as_ref()));
    assert_eq!(original.proof.record(), proof.proof.record());
}
#[test]
fn old_journal_without_alias_record_declines_instead_of_inferring_from_equal_facts() {
    let (project, source) = files("alias-old-journal");
    let journal = crate::test_scratch::dir("alias-old-record").join("journal");
    let recorded = RecordingInputs::new(
        crate::frozen_inputs::Inputs::record(&journal).unwrap(),
        4_000_000_000,
    );
    dm_tree::frontend::build(&project, &recorded, &Default::default(), 1).unwrap();
    recorded.provider.finish().unwrap();
    let replay = RecordingInputs::new(
        crate::frozen_inputs::Inputs::replay(&journal).unwrap(),
        4_000_000_001,
    );
    let other = dm_tree::frontend::build(&project, &replay, &Default::default(), 1).unwrap();
    let current = primary(&other);
    assert!(replay
        .acquire_source_alias(&source, &current.path, &current.text)
        .unwrap()
        .is_none());
    assert!(!replay.snapshot().unwrap().contains_file(&source));
}

#[test]
fn journal_alias_record_cannot_change_path_identity_or_original_fact() {
    let (project, source) = files("alias-replay-record-binding");
    let inputs = RecordingInputs::new(Files { saved: None }, 4_000_000_000);
    let frontend = dm_tree::frontend::build(&project, &inputs, &Default::default(), 1).unwrap();
    let current = primary(&frontend);
    let acquired = inputs
        .acquire_source_alias(&source, &current.path, &current.text)
        .unwrap()
        .unwrap();
    let challenge = &acquired.proof.challenge;
    let mut record = acquired.proof.record();
    record.alias.path = source.with_file_name("foreign.dm");
    assert!(record.replay(&source, challenge).is_err());
    record = acquired.proof.record();
    record.primary.content ^= 1;
    assert!(record.replay(&source, challenge).is_err());
}
