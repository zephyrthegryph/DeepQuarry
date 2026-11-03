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

struct ObservedFiles{reads:std::cell::Cell<usize>,saved:std::cell::RefCell<Option<SourceAliasProof>>}
impl SnapshotProvider for ObservedFiles{
 fn read_policy_bounded(&self,path:&Path,limit:usize)->io::Result<Option<CapturedInputRead>>{self.reads.set(self.reads.get()+1);FileSystemInputs.read_policy_bounded(path,limit)}
 fn stamp(&self,path:&Path)->io::Result<Stamp>{FileSystemInputs.stamp(path)}
 fn read(&self,path:&Path)->io::Result<(Stamp,Vec<u8>)>{self.reads.set(self.reads.get()+1);FileSystemInputs.read(path)}
 fn list(&self,path:&Path)->io::Result<FolderListing>{FileSystemInputs.list(path)}
 fn source_alias(&self,path:&Path,challenge:&SourceAliasChallenge)->io::Result<Option<SourceAliasProof>>{if let Some(saved)=self.saved.borrow().as_ref(){return Ok(Some(saved.clone()))}let proof=FileSystemInputs.source_alias(path,challenge)?;*self.saved.borrow_mut()=proof.clone();Ok(proof)}
}
#[test]fn observed_positive_file_alias_uses_actual_identity_without_payload_reread_or_source_lease(){
 let(_,ordinary)=files("observed-positive-alias");let canonical=std::fs::canonicalize(&ordinary).unwrap();assert_ne!(ordinary,canonical);let provider=ObservedFiles{reads:std::cell::Cell::new(0),saved:Default::default()};let inputs=RecordingInputs::new(provider,0);let bytes=inputs.read_policy_candidate(&canonical,1<<20).unwrap().unwrap();let before=inputs.provider.reads.get();inputs.record_observed_file_alias(&ordinary,&canonical).unwrap();assert_eq!(inputs.provider.reads.get(),before);let primary=inputs.recorded_file_fact(&canonical).unwrap();let alias=inputs.recorded_file_fact(&ordinary).unwrap();assert_eq!(alias.stamp,primary.stamp);assert_eq!(alias.content,xxhash_rust::xxh3::xxh3_128(bytes.as_slice()));assert!(inputs.source_acquisitions.lock().unwrap().is_empty(),"positive metadata alias does not mint a compiled source acquisition");
 let saved=inputs.provider.saved.borrow().clone();let foreign=RecordingInputs::new(ObservedFiles{reads:std::cell::Cell::new(0),saved:std::cell::RefCell::new(saved)},1);foreign.read_policy_candidate(&canonical,1<<20).unwrap();assert!(foreign.record_observed_file_alias(&ordinary,&canonical).is_err());assert!(!foreign.snapshot().unwrap().contains_file(&ordinary),"old equal-fact proof cannot answer the new actual challenge");
}
