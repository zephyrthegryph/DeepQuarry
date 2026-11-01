use super::*;
use crate::input_snapshot::{FolderListing, RecordingInputs, SnapshotProvider, Stamp};
use crate::policy_request::{
    AdmittedPolicyRequest, PolicyInputFile, PolicyInputRequest, PolicyInputRole,
};
use crate::runner_host::policy_capture::{self, RequestedPolicyFile};
use dm_analysis::policy_inputs::PolicyRole;
use std::{io, path::Path};
struct Source;
impl Source {
    fn bytes(path: &Path) -> io::Result<&'static [u8]> {
        match path.file_name().and_then(|name| name.to_str()) {
            Some("p.dme") => Ok(b"/datum/test\n    var/saved\n"),
            Some("marker.dm") => Ok(b"SCHEMA(/datum/test, saved, schema_msg())\r\n"),
            _ => Err(io::ErrorKind::NotFound.into()),
        }
    }
}
impl SnapshotProvider for Source {
    fn stamp(&self, path: &Path) -> io::Result<Stamp> {
        Ok(Stamp {
            size: Self::bytes(path)?.len() as u64,
            modified_ns: 1,
            file_id: Some(1),
        })
    }
    fn read(&self, path: &Path) -> io::Result<(Stamp, Vec<u8>)> {
        Ok((self.stamp(path)?, Self::bytes(path)?.to_vec()))
    }
    fn list(&self, path: &Path) -> io::Result<FolderListing> {
        Ok(if path.ends_with("search") {
            FolderListing::Missing
        } else {
            FolderListing::Present(vec!["marker.dm".into(), "p.dme".into()])
        })
    }
}
fn root() -> PathBuf {
    // Synthetic absolute provider paths; no directory is created on disk.
    std::env::current_dir()
        .unwrap()
        .join("policy-capture-fixture")
}
fn intent(files: &[RequestedPolicyFile], folders: &[PathBuf]) -> AdmittedPolicyRequest {
    PolicyInputRequest {workspace_auxiliary:Vec::new(),workspace_generators:Vec::new(),
        workspace: None,
        files: files
            .iter()
            .map(|file| PolicyInputFile {
                path: file.path.clone(),
                required: file.required,
                role: match file.role {
                    PolicyRole::DmSource => PolicyInputRole::DmSource,
                    PolicyRole::Configuration => PolicyInputRole::Configuration,
                },
            })
            .collect(),
        search_folders: folders.to_vec(),
    }
    .admit()
    .unwrap()
}
fn frontend(inputs: &RecordingInputs<Source>, db: &Arc<crate::query_db::QueryDb>) -> ColdFrontend {
    dm_tree::frontend::build(&root().join("p.dme"), inputs, &Default::default(), 1)
        .unwrap()
        .with_body_queries(db.clone())
}
#[test]
fn source_snapshot_binds_single_policy_archive_and_rejects_foreign_frontend() {
    let db = Arc::new(crate::query_db::QueryDb::default());
    let inputs = RecordingInputs::new(Source, 1);
    let frontend = frontend(&inputs, &db);
    let captured = Arc::new(
        policy_capture::capture(&frontend, &inputs, &[], &[])
            .unwrap()
            .bind_request(&intent(&[], &[]))
            .unwrap(),
    );
    let state = Arc::new(Mutex::new(QueryState::default()));
    let mut attempt = QueryAttempt::new(Arc::clone(&state), true);
    attempt
        .capture_with_queries(&frontend, db.clone(), Some(Arc::clone(&captured)))
        .unwrap();
    {
        let state = state.lock().unwrap();
        let snapshot = state.snapshot.as_ref().unwrap();
        assert!(Arc::ptr_eq(
            snapshot.body_archive.as_ref().unwrap(),
            captured.policy().archive()
        ));
        assert!(Arc::ptr_eq(
            snapshot.native_value_input.as_ref().unwrap().archive(),
            captured.policy().archive()
        ));
        assert_eq!(snapshot.policy_revision, captured.policy_revision());
        assert!(snapshot
            .native_policy_inputs
            .as_ref()
            .unwrap()
            .facts()
            .same_recorded_facts(&inputs.snapshot().unwrap()));
    }
    let foreign = dm_tree::frontend::build(&root().join("p.dme"), &inputs, &Default::default(), 1)
        .unwrap()
        .with_body_queries(db.clone());
    assert!(attempt
        .capture_with_queries(&foreign, db, Some(captured))
        .is_err());
}
#[test]
fn source_snapshot_reads_noncompiled_markers_through_analyze_raw_view() {
    use dm_analysis::policy_inputs::TextView;
    let db = Arc::new(crate::query_db::QueryDb::default());
    let inputs = RecordingInputs::new(Source, 1);
    let frontend = frontend(&inputs, &db);
    let files = [RequestedPolicyFile {
        path: root().join("marker.dm"),
        role: PolicyRole::DmSource,
        required: true,
    }];
    let captured = Arc::new(
        policy_capture::capture(&frontend, &inputs, &files, &[])
            .unwrap()
            .bind_request(&intent(&files, &[]))
            .unwrap(),
    );
    let marker = captured.policy().file(&root().join("marker.dm")).unwrap();
    assert!(!marker.is_compiled());
    assert_eq!(
        marker.view(TextView::AnalyzeRaw).unwrap().as_str(),
        "SCHEMA(/datum/test, saved, schema_msg())\n"
    );
    let state = Arc::new(Mutex::new(QueryState::default()));
    let mut attempt = QueryAttempt::new(Arc::clone(&state), true);
    attempt
        .capture_with_queries(&frontend, db, Some(captured))
        .unwrap();
    let state = state.lock().unwrap();
    let schemas = state
        .snapshot
        .as_ref()
        .unwrap()
        .native_schema_markers
        .as_ref()
        .unwrap();
    assert_eq!(
        schemas.find(
            &frontend.snapshot.tree,
            dm_ir::SymbolId::of("/datum/test"),
            dm_ir::SymbolId::of("saved")
        ),
        Some(&dm_analysis::value_schemas::Kind::Msg)
    );
}
#[test]
fn publication_replay_refuses_omitted_policy_absence_or_folder_facts() {
    let db = Arc::new(crate::query_db::QueryDb::default());
    let inputs = RecordingInputs::new(Source, 1);
    let frontend = frontend(&inputs, &db);
    let files = [RequestedPolicyFile {
        path: root().join("optional.toml"),
        role: PolicyRole::Configuration,
        required: false,
    }];
    let folders = [root().join("search")];
    let admitted = intent(&files, &folders);
    let captured = Arc::new(
        policy_capture::capture(&frontend, &inputs, &files, &folders)
            .unwrap()
            .bind_request(&admitted)
            .unwrap(),
    );
    let state = Arc::new(Mutex::new(QueryState::default()));
    let mut attempt = QueryAttempt::new(Arc::clone(&state), true);
    attempt
        .capture_with_queries(&frontend, db, Some(Arc::clone(&captured)))
        .unwrap();
    attempt.configure(
        crate::session::Configuration::new(
            &root(),
            &root().join("p.dme"),
            Default::default(),
            1,
            2,
            3,
        )
        .unwrap()
        .with_policy_inputs(Some(&admitted)),
    );
    let engine: Arc<[u8]> = Arc::from(&b"engine"[..]);
    attempt.bind_publication_proof(captured.facts(), &engine);
    assert!(state
        .lock()
        .unwrap()
        .snapshot
        .as_ref()
        .unwrap()
        .replay_proof
        .is_some());
    for omit_folder in [false, true] {
        let mut incomplete = crate::input_snapshot::InputSnapshot::new(1);
        for file in captured.facts().files() {
            incomplete
                .record_file(
                    &file.path,
                    file.stamp.clone(),
                    Source::bytes(&file.path).unwrap(),
                )
                .unwrap();
        }
        for (path, listing) in captured.facts().folders() {
            if !omit_folder || !path.ends_with("search") {
                incomplete.record_folder(path, listing.clone()).unwrap();
            }
        }
        if omit_folder {
            captured
                .facts()
                .visit_recorded_storage(|_, _, negative, _| {
                    for path in negative {
                        incomplete.record_negative(path).unwrap();
                    }
                });
        }
        assert!(!incomplete.same_recorded_facts(captured.facts()));
        attempt.bind_publication_proof(&incomplete, &engine);
        assert!(state
            .lock()
            .unwrap()
            .snapshot
            .as_ref()
            .unwrap()
            .replay_proof
            .is_none());
    }
}
#[test]
fn source_snapshot_rejects_unbound_policy_capture_before_retaining_anything() {
    let db = Arc::new(crate::query_db::QueryDb::default());
    let inputs = RecordingInputs::new(Source, 1);
    let frontend = frontend(&inputs, &db);
    let unbound = Arc::new(policy_capture::capture(&frontend, &inputs, &[], &[]).unwrap());
    let state = Arc::new(Mutex::new(QueryState::default()));
    let mut attempt = QueryAttempt::new(Arc::clone(&state), true);
    let error = attempt
        .capture_with_queries(&frontend, db, Some(unbound))
        .unwrap_err();
    assert!(error.to_string().contains("admitted request binding"));
    assert!(state.lock().unwrap().snapshot.is_none());
}

#[test]
fn workspace_child_keeps_compiler_schema_order_and_has_no_published_subset_revision(){
 struct Ordered;
 impl Ordered {fn bytes(path:&Path)->io::Result<&'static [u8]>{match path.file_name().and_then(|s|s.to_str()){
  Some("deepquarry.dme")=>Ok(b"#define SCHEMA(T,v,k)\n/datum/test\n    var/saved\n#include \"z.dm\"\n#include \"a.dm\"\n"),
  Some("z.dm")=>Ok(b"SCHEMA(/datum/test, saved, schema_msg())\n"),
  Some("a.dm")=>Ok(b"SCHEMA(/datum/test, saved, schema_any())\n"),
  _=>Err(io::ErrorKind::NotFound.into()),
 }}}
 impl SnapshotProvider for Ordered {
  fn stamp(&self,p:&Path)->io::Result<Stamp>{Ok(Stamp{size:Self::bytes(p)?.len()as u64,modified_ns:1,file_id:None})}
  fn read(&self,p:&Path)->io::Result<(Stamp,Vec<u8>)>{Ok((self.stamp(p)?,Self::bytes(p)?.to_vec()))}
  fn list(&self,_:&Path)->io::Result<FolderListing>{Ok(FolderListing::Present(vec!["a.dm".into(),"deepquarry.dme".into(),"z.dm".into()]))}
 }
 let inputs=RecordingInputs::new(Ordered,1);let db=Arc::new(crate::query_db::QueryDb::default());
 let front=dm_tree::frontend::build(&root().join("deepquarry.dme"),&inputs,&Default::default(),1).unwrap().with_body_queries(db.clone());
 let child=Arc::new(policy_capture::capture_workspace_generator(&front,&inputs,&root().join("missing.toml")).unwrap());
 assert!(child.policy_revision().is_some());
 let mut snapshot=SourceSnapshot::capture_policy_role(&front,Some(Arc::clone(&child)),SnapshotPolicyRole::WorkspaceGeneratorChild);
 // Hostile name data alone must not create a published workspace role.
 let mut names=[None;13];names[0]=Some(crate::GeneratorName::Deps);snapshot.workspace_generator_selection=Some(WorkspaceGeneratorSelection{names});
 assert!(snapshot.policy_revision.is_none());assert_eq!(snapshot.workspace_generator_inputs(crate::GeneratorName::Deps).err().unwrap().kind(),io::ErrorKind::Other,"selected name data cannot grant unpublished workspace authority");
 assert!(Arc::ptr_eq(snapshot.body_archive.as_ref().unwrap(),child.policy().archive()));
 assert!(Arc::ptr_eq(snapshot.native_value_input.as_ref().unwrap().archive(),child.policy().archive()));
 let expected=native_policy::capture_schemas(&front).unwrap();
 assert_eq!(snapshot.native_schema_markers.as_ref().unwrap().find(&front.snapshot.tree,dm_ir::SymbolId::of("/datum/test"),dm_ir::SymbolId::of("saved")),expected.find(&front.snapshot.tree,dm_ir::SymbolId::of("/datum/test"),dm_ir::SymbolId::of("saved")));
 let z=front.files.iter().position(|file|file.path.file_name().is_some_and(|name|name=="z.dm")).unwrap();
 let a=front.files.iter().position(|file|file.path.file_name().is_some_and(|name|name=="a.dm")).unwrap();assert!(z<a,"fixture exercises compiler include order opposite raw BTree order");
 assert_eq!(expected.find(&front.snapshot.tree,dm_ir::SymbolId::of("/datum/test"),dm_ir::SymbolId::of("saved")),Some(&dm_analysis::value_schemas::Kind::Any));
}

#[test]fn staged_source_frame_keeps_explicit_subset_revision_and_rejects_role_transplant(){
 let db=Arc::new(crate::query_db::QueryDb::default());let inputs=RecordingInputs::new(Source,1);let front=frontend(&inputs,&db);let policy=Arc::new(policy_capture::capture(&front,&inputs,&[],&[]).unwrap().bind_request(&intent(&[],&[])).unwrap());
 let mut snapshot=SourceSnapshot::capture_policy(&front,Some(Arc::clone(&policy)));snapshot.native_raw_queries=Some(Arc::clone(&db));let state=Arc::new(Mutex::new(QueryState::default()));let mut attempt=QueryAttempt::new(state,true);attempt.stage_source_snapshot(snapshot,inputs.snapshot().unwrap()).unwrap();
 let(snapshot,frame)=attempt.pending_source.as_mut().unwrap();frame.require_snapshot(snapshot).unwrap();snapshot.policy_role=SnapshotPolicyRole::WorkspaceGeneratorChild;snapshot.policy_revision=None;assert!(frame.require_snapshot(snapshot).is_err(),"equal original owners cannot transplant a source role");
 snapshot.policy_role=SnapshotPolicyRole::ExplicitSubset;assert!(frame.require_snapshot(snapshot).is_err(),"explicit subset still requires its exact bound revision");snapshot.policy_revision=policy.policy_revision();frame.require_snapshot(snapshot).unwrap();let mut names=[None;13];names[0]=Some(crate::GeneratorName::Deps);snapshot.workspace_generator_selection=Some(WorkspaceGeneratorSelection{names});assert!(frame.require_snapshot(snapshot).is_err(),"a request-name mutation cannot change the exact staged role");snapshot.workspace_generator_selection=None;frame.require_snapshot(snapshot).unwrap();
}
