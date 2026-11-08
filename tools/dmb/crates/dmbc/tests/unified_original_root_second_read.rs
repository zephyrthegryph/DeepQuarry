//! Real provider marker/second-read controls over the same private issuer.
//! No alternate parser, fabricated acquisition/model, daemon or GUI.
#[path="../../../shared/test_scratch.rs"]mod scratch;
use dmbc::{input_snapshot::{RecordingInputs,SnapshotProvider,FileSystemInputs,Stamp,FolderListing,PolicyDirectoryListing,CapturedInputRead,OriginalOpenedRead},policy_request::{PolicyInputRequest,AnalysisContext,WorkspacePolicyRequest,WorkspaceAuxiliaryQuestion as Q},runner_host::BuildHost};
use dm_preprocess::{SourceProvider,OriginalRawReadOutcome as Outcome,OriginalRawOpenDecision as Decision,source_arena_credit::{SourceArenaWork,read_original_source_open_using}};
use std::{io,path::{Path,PathBuf},sync::atomic::{AtomicUsize,Ordering},collections::BTreeMap};
struct Observe{mode:usize,marker:AtomicUsize,original:AtomicUsize}
impl SnapshotProvider for Observe{
 fn source_alias(&self,p:&Path,c:&dmbc::input_snapshot::SourceAliasChallenge)->io::Result<Option<dmbc::input_snapshot::SourceAliasProof>>{FileSystemInputs.source_alias(p,c)}
 fn stamp(&self,p:&Path)->io::Result<Stamp>{FileSystemInputs.stamp(p)}fn read(&self,p:&Path)->io::Result<(Stamp,Vec<u8>)>{FileSystemInputs.read(p)}fn list(&self,p:&Path)->io::Result<FolderListing>{FileSystemInputs.list(p)}
 fn read_policy_bounded(&self,p:&Path,n:usize)->io::Result<Option<CapturedInputRead>>{if p.file_name().is_some_and(|s|s=="deepquarry.dme"){self.marker.fetch_add(1,Ordering::AcqRel);}FileSystemInputs.read_policy_bounded(p,n)}
 fn read_policy_bounded_admitted(&self,p:&Path,n:usize,before:&mut dyn FnMut(usize)->io::Result<()>)->io::Result<Option<CapturedInputRead>>{if p.file_name().is_some_and(|s|s=="deepquarry.dme"){self.marker.fetch_add(1,Ordering::AcqRel);}FileSystemInputs.read_policy_bounded_admitted(p,n,before)}
 fn policy_directory(&self,p:&Path,follow:bool,n:usize)->io::Result<Option<PolicyDirectoryListing>>{FileSystemInputs.policy_directory(p,follow,n)}
 fn read_original_open_admitted(&self,p:&Path,n:usize,work:&dyn SourceArenaWork,opened:&mut dyn FnMut()->io::Result<Decision>,before:&mut dyn FnMut(usize)->io::Result<()>)->io::Result<OriginalOpenedRead>{self.original.fetch_add(1,Ordering::AcqRel);if self.mode==1{std::fs::remove_file(p)?}else if self.mode==2{std::fs::write(p,b"#include \"code/second.dm\"\n")?}FileSystemInputs.read_original_open_admitted(p,n,work,opened,before)}
}
fn fixture(label:&str)->PathBuf{let root=scratch::dir(label);std::fs::create_dir_all(root.join("code")).unwrap();std::fs::write(root.join("code/first.dm"),"/datum/first\n").unwrap();std::fs::write(root.join("code/second.dm"),"/datum/second\n").unwrap();std::fs::write(root.join("deepquarry.dme"),b"#include \"code/first.dm\"\n").unwrap();root}
fn intent(root:&Path)->PolicyInputRequest{PolicyInputRequest{analysis_context:Some(AnalysisContext::OriginalAnalyze0290),workspace:Some(WorkspacePolicyRequest{root:root.to_owned(),recursive_roots:vec![root.join("code")],configuration:root.join("tools/ci/lint_scopes.toml")}),workspace_auxiliary:vec![Q::DerivedReads],..Default::default()}}
#[derive(serde::Deserialize)]struct Facts{files:BTreeMap<PathBuf,serde::de::IgnoredAny>,#[serde(default)]opened_reads:BTreeMap<PathBuf,serde_json::Value>,#[serde(default)]original_payloads:BTreeMap<PathBuf,serde::de::IgnoredAny>}
fn has_root<T>(rows:&BTreeMap<PathBuf,T>)->bool{rows.keys().any(|p|p.file_name().is_some_and(|name|name=="deepquarry.dme"))}
#[test]fn actual_marker_read_is_followed_by_separate_exact_physical_read_and_new_bytes_are_delivered(){for mode in [0,2]{let root=fixture("public-physical-root-second-read");let provider=Observe{mode,marker:0.into(),original:0.into()};let mut inputs=RecordingInputs::new(&provider,0).with_initial_environment(dm_preprocess::InitialEnvironment::OriginalChecker0290);let project=inputs.prepare_original_analysis_entry(intent(&root)).unwrap();assert_eq!(provider.marker.load(Ordering::Acquire),1);assert_eq!(provider.original.load(Ordering::Acquire),0);let host=BuildHost::default();let mut opened=0;let result=read_original_source_open_using(&inputs,&project,1<<20,host.source_arena_work(),&mut||{opened+=1;Ok(Decision::Read)}).unwrap();let Outcome::Acquired(lease)=result else{panic!("genuine second physical reader must return its real lease")};assert_eq!(provider.original.load(Ordering::Acquire),1);assert_eq!(opened,1);let expected=if mode==0{b"#include \"code/first.dm\"\n" as &[u8]}else{b"#include \"code/second.dm\"\n" as &[u8]};assert_eq!(inputs.original_source_bytes(&lease).unwrap().unwrap(),expected,"marker bytes cannot stand in for the actual second reader payload");let snapshot=inputs.snapshot().unwrap();let json=serde_json::to_string(&snapshot).unwrap();let facts:Facts=serde_json::from_str(&json).unwrap();assert!(has_root(&facts.files));assert!(has_root(&facts.opened_reads));assert!(has_root(&facts.original_payloads));if mode==2{assert!(!snapshot.restat(&FileSystemInputs).unwrap().unchanged(),"independent first marker fact must not be rewritten to conceal a changed second read");}}}
#[test]fn deleted_after_marker_root_preserves_actual_source_open_failure_and_no_payload_or_suppression(){let root=fixture("public-root-deleted-after-marker");let provider=Observe{mode:1,marker:0.into(),original:0.into()};let mut inputs=RecordingInputs::new(&provider,0).with_initial_environment(dm_preprocess::InitialEnvironment::OriginalChecker0290);let project=inputs.prepare_original_analysis_entry(intent(&root)).unwrap();let host=BuildHost::default();let result=read_original_source_open_using(&inputs,&project,1<<20,host.source_arena_work(),&mut||panic!("failed root open must precede suppression/read decision")).unwrap();let Outcome::SourceOpenFailed(error)=result else{panic!("cached marker cannot conceal a real failed second open")};assert_eq!(error.kind(),io::ErrorKind::NotFound);assert_eq!(provider.original.load(Ordering::Acquire),1);let facts:Facts=serde_json::from_str(&serde_json::to_string(&inputs.snapshot().unwrap()).unwrap()).unwrap();assert!(has_root(&facts.files));assert!(has_root(&facts.opened_reads));assert!(!has_root(&facts.original_payloads));}
#[test]fn borrowed_native_source_lenders_keep_same_domain_and_refuse_foreign_growth(){let own=BuildHost::default();let foreign=BuildHost::default();let mut credit=own.source_arena_work().reserve(4096).unwrap();assert_eq!(foreign.source_arena_work().grow(&mut credit,1).unwrap_err().kind(),io::ErrorKind::InvalidInput);own.source_arena_work().grow(&mut credit,1).unwrap();own.source_arena_work().shrink(&mut credit,4097).unwrap();}

#[test]fn missing_and_non_utf8_initial_markers_choose_real_issued_synthetic_entry_not_unavailable(){for malformed in [false,true]{let root=fixture("public-root-marker-synthetic");if malformed{std::fs::write(root.join("deepquarry.dme"),b"\xff#include \"code/first.dm\"\n").unwrap()}else{std::fs::remove_file(root.join("deepquarry.dme")).unwrap()}let provider=Observe{mode:0,marker:0.into(),original:0.into()};let mut inputs=RecordingInputs::new(&provider,0).with_initial_environment(dm_preprocess::InitialEnvironment::OriginalChecker0290);let project=inputs.prepare_original_analysis_entry(intent(&root)).unwrap();assert_eq!(project.file_name().unwrap(),"synth.dme","actual old marker predicate chooses synthetic source");let host=BuildHost::default();let result=read_original_source_open_using(&inputs,&project,1<<20,host.source_arena_work(),&mut||Ok(Decision::Read)).unwrap();let Outcome::Acquired(lease)=result else{panic!("missing/invalid-UTF8 marker must issue its private header")};let bytes=inputs.original_source_bytes(&lease).unwrap().unwrap();assert!(std::ptr::eq(bytes,lease.source_text().as_bytes()),"same actual synthetic backing survives ordinary-first dispatch");let mut foreign=RecordingInputs::new(&provider,0).with_initial_environment(dm_preprocess::InitialEnvironment::OriginalChecker0290);assert_eq!(foreign.prepare_original_analysis_entry(intent(&root)).unwrap(),project);let refused=foreign.original_source_bytes(&lease).unwrap_err();assert_eq!(refused.kind(),io::ErrorKind::InvalidData);assert_eq!(refused.to_string(),"Original bytes lack a genuine recorded read receipt");assert_eq!(provider.original.load(Ordering::Acquire),0,"private issued header is genuine nonphysical input, not a skipped physical second read");}}

// The real record/replay issuer must retain marker and later actual opened
// payload/status independently, even when those observations disagree.
#[test]fn actual_record_replay_keeps_marker_and_second_reader_as_separate_observations(){
 for deleted in [false,true]{
  let root=fixture("public-root-second-read-replay");let journal=scratch::dir("public-root-second-journal").join("capture");let host=BuildHost::default();
  let recorded=dmbc::frozen_inputs::Inputs::record(&journal).unwrap();
  let mut inputs=RecordingInputs::new(&recorded,0).with_initial_environment(dm_preprocess::InitialEnvironment::OriginalChecker0290);
  let project=inputs.prepare_original_analysis_entry(intent(&root)).unwrap();
  if deleted{std::fs::remove_file(root.join("deepquarry.dme")).unwrap()}else{std::fs::write(root.join("deepquarry.dme"),b"#include \"code/second.dm\"\n").unwrap()}
  let observed=read_original_source_open_using(&inputs,&project,1<<20,host.source_arena_work(),&mut||Ok(Decision::Read)).unwrap();
  let first=match observed{Outcome::Acquired(lease)=>{assert!(!deleted);Ok(inputs.original_source_bytes(&lease).unwrap().unwrap().to_vec())},Outcome::SourceOpenFailed(error)=>{assert!(deleted);Err((error.kind(),error.raw_os_error()))},_=>panic!("real recorded second open cannot be absent/suppressed")};
  recorded.finish().unwrap();drop(inputs);drop(recorded);
  std::fs::write(root.join("deepquarry.dme"),b"not the marker or the second payload\n").unwrap();
  let replay=dmbc::frozen_inputs::Inputs::replay(&journal).unwrap();let mut replayed=RecordingInputs::new(&replay,0).with_initial_environment(dm_preprocess::InitialEnvironment::OriginalChecker0290);
  let project=replayed.prepare_original_analysis_entry(intent(&root)).unwrap();
  let result=read_original_source_open_using(&replayed,&project,1<<20,host.source_arena_work(),&mut||Ok(Decision::Read)).unwrap();
  let second=match result{Outcome::Acquired(lease)=>Ok(replayed.original_source_bytes(&lease).unwrap().unwrap().to_vec()),Outcome::SourceOpenFailed(error)=>Err((error.kind(),error.raw_os_error())),_=>panic!("replay changed actual second-open disposition")};assert_eq!(first,second,"journal must not substitute marker payload or live filesystem for actual second reader");
  let facts:Facts=serde_json::from_str(&serde_json::to_string(&replayed.snapshot().unwrap()).unwrap()).unwrap();assert!(has_root(&facts.files));assert!(has_root(&facts.opened_reads));assert_eq!(has_root(&facts.original_payloads),!deleted);
 }
}

// Exercise the production recorder and QueryDb settlement, with an exact
// pre-scan allocation so backing reuse is eligible regardless of read_to_end
// spare capacity on this Rust standard library or filesystem.
struct PreparedRead {
    opens: AtomicUsize,
    extra_capacity: usize,
}
impl SnapshotProvider for PreparedRead {
    fn stamp(&self, path: &Path) -> io::Result<Stamp> { FileSystemInputs.stamp(path) }
    fn read(&self, path: &Path) -> io::Result<(Stamp, Vec<u8>)> {
        let (stamp, bytes) = FileSystemInputs.read(path)?;
        let bytes = bytes.into_boxed_slice().into_vec();
        if self.extra_capacity == 0 { return Ok((stamp, bytes)); }
        let mut spare = Vec::with_capacity(bytes.len() + self.extra_capacity);
        spare.extend_from_slice(&bytes);
        Ok((stamp, spare))
    }
    fn list(&self, path: &Path) -> io::Result<FolderListing> { FileSystemInputs.list(path) }
    fn read_original_open_admitted(
        &self, path: &Path, limit: usize, work: &dyn SourceArenaWork,
        opened: &mut dyn FnMut() -> io::Result<Decision>,
        before: &mut dyn FnMut(usize) -> io::Result<()>,
    ) -> io::Result<OriginalOpenedRead> {
        self.opens.fetch_add(1, Ordering::Relaxed);
        FileSystemInputs.read_original_open_admitted(path, limit, work, opened, before)
    }
}

fn prescanned(provider: &PreparedRead) -> RecordingInputs<&PreparedRead> {
    RecordingInputs::new(provider, 0)
        .with_initial_environment(dm_preprocess::InitialEnvironment::OriginalChecker0290)
        .with_prepared_sources(Some(std::sync::Arc::new(dmbc::input_snapshot::PreparedInputArtifacts::default())))
}

#[test]
fn exact_open_shares_only_equal_admitted_utf8_storage_and_keeps_a_new_receipt() {
    let root = scratch::dir("public-original-prepared-backing");
    for extra_capacity in [0, 4096] {
        let path = root.join(format!("probe-{extra_capacity}.dm"));
        let bytes = format!("/datum/exact_prepared_backing_{extra_capacity}\n");
        std::fs::write(&path, bytes.as_bytes()).unwrap();
        let path = dm_preprocess::regions::canonical_path(&path);
        let provider = PreparedRead { opens: AtomicUsize::new(0), extra_capacity };
        let input = prescanned(&provider);
        let prepared = input.prepared_source(&path).unwrap();
        let old = input.source_acquisition(&path, prepared.original()).unwrap();
        let host = BuildHost::default();
        let read = || {
            let Outcome::Acquired(lease) = read_original_source_open_using(
                &input, &path, 1<<20, host.source_arena_work(), &mut || Ok(Decision::Read),
            ).unwrap() else { panic!("actual exact read"); };
            lease
        };
        let lease = read();
        let again = read();
        assert_eq!(provider.opens.load(Ordering::Relaxed), 2);
        assert_eq!(input.original_source_bytes(&lease).unwrap().unwrap(), bytes.as_bytes());
        assert_eq!(lease.source_text().same_view(prepared.original()), extra_capacity == 0);
        assert_eq!(again.source_text().same_view(prepared.original()), extra_capacity == 0);
        assert!(!lease.same_binding(old.lease()));
        assert!(!lease.same_original_acquisition(old.lease()));
        assert!(!lease.same_binding(&again));
        assert!(!lease.same_original_acquisition(&again));
    }
}

#[test]
fn exact_open_rejects_prepared_backing_when_bytes_change_at_the_same_stamp() {
    use std::fs::{File, FileTimes};

    let root = scratch::dir("public-original-prepared-same-stamp");
    let path = root.join("changed.dm");
    let before = b"/datum/prepared_backing_before_a\n";
    let after = b"/datum/prepared_backing_before_b\n";
    std::fs::write(&path, before).unwrap();
    let path = dm_preprocess::regions::canonical_path(&path);
    let provider = PreparedRead { opens: AtomicUsize::new(0), extra_capacity: 0 };
    let input = prescanned(&provider);
    let prepared = input.prepared_source(&path).unwrap();
    let stamp = provider.stamp(&path).unwrap();
    let modified = std::fs::metadata(&path).unwrap().modified().unwrap();
    std::fs::write(&path, after).unwrap();
    File::options().write(true).open(&path).unwrap()
        .set_times(FileTimes::new().set_modified(modified)).unwrap();
    assert_eq!(provider.stamp(&path).unwrap(), stamp, "same actual file, size and timestamp");

    let host = BuildHost::default();
    let Outcome::Acquired(lease) = read_original_source_open_using(
        &input, &path, 1<<20, host.source_arena_work(), &mut || Ok(Decision::Read),
    ).unwrap() else { panic!("actual exact read"); };
    assert_eq!(provider.opens.load(Ordering::Relaxed), 1);
    assert_eq!(input.original_source_bytes(&lease).unwrap().unwrap(), after);
    assert_eq!(prepared.original().as_bytes(), before);
    assert!(!lease.source_text().same_view(prepared.original()));
}

#[test]
fn prepared_backing_cannot_replace_exceptional_raw_bytes_or_real_open_disposition() {
    let root = scratch::dir("public-original-prepared-exceptional");
    let provider = PreparedRead { opens: AtomicUsize::new(0), extra_capacity: 0 };
    let host = BuildHost::default();
    for (name, bytes, encoding) in [
        ("bom.dm", &b"\xef\xbb\xbf/datum/prepared_bom\n"[..], dm_preprocess::SourceEncoding::Utf8Bom),
        ("latin.dm", &b"/datum/prepared_latin // \xe9\n"[..], dm_preprocess::SourceEncoding::IncompatibleOriginal),
    ] {
        let path = root.join(name);
        std::fs::write(&path, bytes).unwrap();
        let path = dm_preprocess::regions::canonical_path(&path);
        let input = prescanned(&provider);
        let prepared = input.prepared_source(&path).unwrap();
        let Outcome::Acquired(lease) = read_original_source_open_using(
            &input, &path, 1<<20, host.source_arena_work(), &mut || Ok(Decision::Read),
        ).unwrap() else { panic!("actual exact read"); };
        assert_eq!(lease.encoding(), encoding);
        assert_eq!(input.original_source_bytes(&lease).unwrap().unwrap(), bytes);
        assert!(!lease.source_text().same_view(prepared.original()));
    }

    let path = root.join("suppressed.dm");
    std::fs::write(&path, b"/datum/prepared_suppressed_backing\n").unwrap();
    let path = dm_preprocess::regions::canonical_path(&path);
    let input = prescanned(&provider);
    let _prepared = input.prepared_source(&path).unwrap();
    let outcome = read_original_source_open_using(
        &input, &path, 1<<20, host.source_arena_work(), &mut || Ok(Decision::Suppress),
    ).unwrap();
    assert!(matches!(outcome, Outcome::Suppressed));
    let facts: Facts = serde_json::from_str(&serde_json::to_string(&input.snapshot().unwrap()).unwrap()).unwrap();
    assert!(facts.opened_reads.contains_key(&path));
    assert!(facts.original_payloads.is_empty());

    let missing = prescanned(&provider);
    // Repeat with a live prepared candidate on the same recorder that opens
    // the now missing path, without converting its prior ordinary fact.
    let alias = root.join("missing-after-prescan.dm");
    std::fs::write(&alias, b"/datum/prepared_disappeared_backing\n").unwrap();
    let alias = dm_preprocess::regions::canonical_path(&alias);
    let _old = missing.prepared_source(&alias).unwrap();
    std::fs::remove_file(&alias).unwrap();
    let outcome = read_original_source_open_using(
        &missing, &alias, 1<<20, host.source_arena_work(), &mut || panic!("failed actual open must precede suppression"),
    ).unwrap();
    let Outcome::SourceOpenFailed(error) = outcome else { panic!("prepared bytes cannot authorize a failed open"); };
    assert_eq!(error.kind(), io::ErrorKind::NotFound);
    let facts: Facts = serde_json::from_str(&serde_json::to_string(&missing.snapshot().unwrap()).unwrap()).unwrap();
    assert!(facts.files.contains_key(&alias));
    assert!(facts.opened_reads.contains_key(&alias));
    assert!(facts.original_payloads.is_empty());
    assert_eq!(provider.opens.load(Ordering::Relaxed), 4);
}
