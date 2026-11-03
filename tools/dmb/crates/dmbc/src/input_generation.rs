//! Read-only generation bootstrap. This is never a SourceSnapshot, compiled
//! PolicyInputs, semantic tree, body/read provider or full workspace receipt.
use super::*;
use dm_resources::capture::CaptureProvider;

#[derive(Debug)]
pub(crate) enum GenerationBootstrapFailure {
    Operational(io::Error),
    Declarations(dm_tree::frontend::GenerationPreparationFailure),
}
pub(crate) enum GenerationBootstrapPreparation {
    /// Exact registered outputs all exist. Caller must use the existing retained
    /// full frontend; no second declaration parse runs in this branch.
    NotNeeded,
    MissingOutputs(GenerationBootstrap),
}
pub(crate) struct GenerationBootstrap {
    declarations: dm_tree::frontend::GenerationDeclarationFrame,
    inputs: InputSnapshot,
}
impl GenerationBootstrap {
    pub(crate) fn declarations(&self)->&dm_tree::frontend::GenerationDeclarationFrame {&self.declarations}
    pub(crate) fn require_current(&self,provider:&impl SnapshotProvider)->io::Result<()> {
        if !self.inputs.restat(provider)?.unchanged(){return Err(io::Error::new(io::ErrorKind::InvalidData,"generation bootstrap inputs changed; prepare a new generation frame"));}
        Ok(())
    }
}
impl<P:SnapshotProvider> RecordingInputs<P> {
    pub(crate) fn prepare_generation_bootstrap(
        &self, project:&Path, defines:&BTreeMap<String,String>,
        config:dm_tree::frontend::FrontendConfig<'_>, executor:&dm_exec::BuildExecutor,
        host:&std::sync::Arc<dyn dm_tree::frontend::SettingExpressionQueries>,
        admit:&mut dyn FnMut(usize)->io::Result<()>,
    )->Result<GenerationBootstrapPreparation,GenerationBootstrapFailure>{
        self.prepare_generation_bootstrap_inner(project,defines,config,executor,host,admit,false)
    }
    pub(crate) fn prepare_generation_question_bootstrap(
        &self, project:&Path, defines:&BTreeMap<String,String>,
        config:dm_tree::frontend::FrontendConfig<'_>, executor:&dm_exec::BuildExecutor,
        host:&std::sync::Arc<dyn dm_tree::frontend::SettingExpressionQueries>,
        admit:&mut dyn FnMut(usize)->io::Result<()>,
    )->Result<GenerationBootstrapPreparation,GenerationBootstrapFailure>{
        self.prepare_generation_bootstrap_inner(project,defines,config,executor,host,admit,true)
    }
    pub(crate) fn prepare_generation_bootstrap_inner(
        &self, project:&Path, defines:&BTreeMap<String,String>,
        config:dm_tree::frontend::FrontendConfig<'_>, executor:&dm_exec::BuildExecutor,
        host:&std::sync::Arc<dyn dm_tree::frontend::SettingExpressionQueries>,
        admit:&mut dyn FnMut(usize)->io::Result<()>,
        questions:bool,
    )->Result<GenerationBootstrapPreparation,GenerationBootstrapFailure>{
        let mut run=||->Result<GenerationBootstrapPreparation,GenerationBootstrapFailure>{
            crate::daemon::control::checkpoint().map_err(GenerationBootstrapFailure::Operational)?;
            if !project.is_absolute(){return Err(GenerationBootstrapFailure::Operational(io::Error::new(io::ErrorKind::InvalidInput,"generation manifest must be caller absolute")));}
            let root=if let Some(subject)=self.original_analysis_subject(){let source=subject.source_for(project).ok_or_else(||GenerationBootstrapFailure::Operational(invalid("generation subject root unavailable")))?;subject.generation_root(project,source.lease()).map_err(GenerationBootstrapFailure::Operational)?}else{project.parent().ok_or_else(||GenerationBootstrapFailure::Operational(io::Error::new(io::ErrorKind::InvalidInput,"generation manifest has no parent")))?};
            // The iterator's owned PathBuf exists before probe receives it.
            // Precharge every actual join from known registry widths first.
            for relative in crate::query_db::QueryDb::generation_dm_outputs(){
                let bytes=root.as_os_str().len().checked_add(relative.len()).and_then(|n|n.checked_mul(8)).and_then(|n|n.checked_add(1024)).ok_or_else(||GenerationBootstrapFailure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,"generation output join capacity overflow")))?;
                admit(bytes).map_err(GenerationBootstrapFailure::Operational)?;
            }
            let paths=crate::query_db::QueryDb::generation_dm_outputs().map(|relative|root.join(relative));
            let omissions=dm_preprocess::regions::GenerationOmissions::probe(paths,&mut |path| {
                crate::daemon::control::checkpoint()?;
                // This existing exact read path records BOTH actual NotFound
                // and parent membership. Any other IO is returned intact.
                self.read_candidate(path).map(|value|value.is_none())
            },admit).map_err(GenerationBootstrapFailure::Operational)?;
            if omissions.paths().next().is_none(){return Ok(GenerationBootstrapPreparation::NotNeeded)}
            let read=|path:&Path|{
                crate::daemon::control::checkpoint()?;
                if let Some(source)=self.original_analysis_subject().and_then(|subject|subject.source_for(path)){return Ok(Some(std::sync::Arc::clone(source.prepared())))}
                let parent=path.parent().ok_or_else(||io::Error::new(io::ErrorKind::InvalidInput,"generation source has no parent"))?;
                self.record_search_folder(parent)?;
                match self.read_recorded(path){
                    Ok(bytes)=>self.acquire_recorded_source(path,bytes).map(|source|Some(std::sync::Arc::clone(source.prepared()))),
                    Err(actual) if actual.kind()==io::ErrorKind::NotFound=>{
                        // The actual read provider can classify an existing
                        // nonregular candidate as NotFound. Only independently
                        // observed absence may become a negative source input;
                        // otherwise preserve the FIRST read error intact.
                        let parent_absent={
                            let snapshot=self.snapshot.lock().map_err(|_|invalid("input capture mutex poisoned"));
                            match (snapshot.as_ref(),path.file_name().and_then(|name|name.to_str())){
                                (Ok(snapshot),Some(name))=>match snapshot.folders.get(parent){
                                    Some(FolderListing::Missing)=>true,
                                    Some(FolderListing::Present(names))=>{
                                        // Exact names include files, directories and nonregulars.
                                        // A possible case alias is not proof of absence.
                                        let exact=names.binary_search_by(|entry|entry.as_str().cmp(name)).is_ok();
                                        let ambiguous=cfg!(windows)&&(!name.is_ascii()||names.iter().any(|entry|!entry.is_ascii()||entry.eq_ignore_ascii_case(name)));
                                        !exact&&!ambiguous
                                    },
                                    None=>false,
                                },
                                _=>false,
                            }
                        };
                        let stamp_missing=matches!(self.provider.stamp(path),Err(ref missing)if missing.kind()==io::ErrorKind::NotFound);
                        // Typed Missing distinguishes an absent path from the
                        // regular-file stamp API's existing nonregular refusal.
                        // No directory roster is requested or retained here.
                        let typed_missing=parent_absent&&stamp_missing&&matches!(self.provider.policy_directory(path,false,0),Ok(Some(PolicyDirectoryListing::Missing)));
                        if typed_missing{self.snapshot.lock().map_err(|_|invalid("input capture mutex poisoned"))?.record_negative(path)?;Ok(None)}else{Err(actual)}
                    },
                    Err(actual)=>Err(actual),
                }
            };
            let plan=dm_tree::frontend::prepare_generation_declaration_plan(project,self,defines,omissions,host,&read).map_err(|failure|match failure {dm_tree::frontend::GenerationPreparationFailure::Frontend(dm_tree::frontend::FrontendBuildFailure::Operational(actual))=>GenerationBootstrapFailure::Operational(actual),other=>GenerationBootstrapFailure::Declarations(other)})?;
            // A missing unused registry output is not a missing source include.
            // Decide BEFORE any declaration expansion/parse, preserving the
            // ordinary retained frontend path without a second declaration parse.
            // The genuine full Analyze synthetic subject has no physical include
            // references to absent generated outputs. Actual registered negative
            // output probes still justify its restricted source phase; no complete
            // source/body receipt is minted by this owner.
            if plan.encountered_omissions().next().is_none()&&!self.original_analysis_subject().is_some_and(|subject|subject.synthetic()){return Ok(GenerationBootstrapPreparation::NotNeeded)}
            let declarations=dm_tree::frontend::prepare_generation_declarations_from_plan(plan,config,executor,host,questions).map_err(|failure|match failure {dm_tree::frontend::GenerationPreparationFailure::Frontend(dm_tree::frontend::FrontendBuildFailure::Operational(actual))=>GenerationBootstrapFailure::Operational(actual),other=>GenerationBootstrapFailure::Declarations(other)})?;
            let inputs=self.snapshot().map_err(GenerationBootstrapFailure::Operational)?;
            let result=GenerationBootstrap{declarations,inputs};
            result.require_current(&self.provider).map_err(GenerationBootstrapFailure::Operational)?;
            Ok(GenerationBootstrapPreparation::MissingOutputs(result))
        };
        let result=run();
        if matches!(&result,Err(GenerationBootstrapFailure::Operational(_))){return result}
        crate::daemon::control::checkpoint().map_err(GenerationBootstrapFailure::Operational)?;
        result
    }
}


/// Purpose-specific actual native questions; metadata InputSnapshot remains the
/// same recorded closure. It has no SourceSnapshot/PolicyInputs conversion.
pub(crate) struct GenerationQuestionBootstrap {
    questions:dm_tree::frontend::GenerationNativeQuestions,
    inputs:InputSnapshot,
}
impl GenerationBootstrap {
    pub(crate) fn into_native_questions<P:SnapshotProvider>(self,recording:&RecordingInputs<P>,config:dm_tree::frontend::FrontendConfig<'_>,executor:&dm_exec::BuildExecutor,db:&std::sync::Arc<crate::query_db::QueryDb>)->Result<GenerationQuestionBootstrap,GenerationBootstrapFailure>{
        self.require_recording(recording).map_err(GenerationBootstrapFailure::Operational)?;
        let control:std::sync::Arc<dyn dm_tree::frontend::SettingExpressionQueries>=db.clone();
        let bodies:std::sync::Arc<dyn dm_tree::frontend::BodySyntaxQueries>=db.clone();
        let Self{declarations,inputs}=self;
        let questions=declarations.into_native_questions(config,executor,bodies,&control).map_err(|failure|match failure{dm_tree::frontend::GenerationPreparationFailure::Frontend(dm_tree::frontend::FrontendBuildFailure::Operational(actual))=>GenerationBootstrapFailure::Operational(actual),other=>GenerationBootstrapFailure::Declarations(other)})?;
        let frame=GenerationQuestionBootstrap{questions,inputs};frame.require_recording(recording).map_err(GenerationBootstrapFailure::Operational)?;Ok(frame)
    }
}
impl GenerationQuestionBootstrap {
    fn require_recording<P:SnapshotProvider>(&self,recording:&RecordingInputs<P>)->io::Result<()>{
        crate::daemon::control::checkpoint()?;
        for(path,lease)in self.questions.original_sources(){let lease=lease.ok_or_else(||invalid("generation question original acquisition absent"))?;if !recording.validate_source_lease(path,lease)&&!recording.validate_analysis_subject_lease(path,lease){return Err(io::Error::new(io::ErrorKind::InvalidData,"generation question frame belongs to another original recorder"))}}
        if !self.inputs.restat(&recording.provider)?.unchanged(){return Err(io::Error::new(io::ErrorKind::InvalidData,"generation question inputs changed; reissue actual generation frame"))}
        crate::daemon::control::checkpoint()
    }
    pub(crate) fn with_questions<P:SnapshotProvider,R,S>(&self,recording:&RecordingInputs<P>,consume:impl for<'frame>FnOnce(&'frame dm_tree::frontend::GenerationNativeQuestions)->io::Result<Result<R,S>>)->io::Result<Result<R,S>>{
        self.require_recording(recording)?;
        let result=consume(&self.questions)?; // actual first IO remains unchanged
        self.require_recording(recording)?; // semantic/success both final-check
        Ok(result)
    }
}

#[cfg(test)] mod tests {
    use super::*;
    use std::sync::Arc;
    #[test]
    fn actual_generation_bootstrap_records_missing_registered_includes_and_reissues_after_output_writes(){
        let root=crate::test_scratch::dir("generation-bootstrap-negative");
        std::fs::create_dir_all(&root).unwrap();
        let project=root.join("main.dme");
        std::fs::write(&project,"#include \"code/engine/_generated/tracked_lists.dm\"\n#include \"code/engine/_generated/reads.dm\"\n/datum/probe\n    var/value=7\n").unwrap();
        let host=Arc::new(crate::query_db::QueryDb::default()) as Arc<dyn dm_tree::frontend::SettingExpressionQueries>;
        let executor=dm_exec::BuildExecutor::new(1).unwrap();
        let config=dm_tree::frontend::FrontendConfig{workers:1,engine:None,observer:None};
        let first=RecordingInputs::new(FileSystemInputs,0);
        let frame=match first.prepare_generation_bootstrap(&project,&BTreeMap::new(),config,&executor,&host,&mut |_|Ok(())).unwrap(){GenerationBootstrapPreparation::MissingOutputs(frame)=>frame,GenerationBootstrapPreparation::NotNeeded=>panic!("actual missing generated directories require bootstrap")};
        assert!(!root.join("code/engine/_generated").exists());
        assert!(first.snapshot().unwrap().proof_folders().any(|folder|folder==canonical_path(&root.join("code/engine/_generated"))));
        assert!(frame.declarations().omissions().any(|path|path==root.join("code/engine/_generated/reads.dm")));
        let count=frame.declarations().declarations().count();
        frame.require_current(&FileSystemInputs).unwrap();
        std::fs::create_dir_all(root.join("code/engine/_generated")).unwrap();
        std::fs::write(root.join("code/engine/_generated/reads.dm"),"/datum/generated_reads\n    var/new_value=2\n").unwrap();
        std::fs::write(root.join("code/engine/_generated/tracked_lists.dm"),"/datum/generated_setters\n    var/new_value=3\n").unwrap();
        assert_eq!(frame.require_current(&FileSystemInputs).unwrap_err().kind(),io::ErrorKind::InvalidData);
        let next=RecordingInputs::new(FileSystemInputs,0);
        let next=match next.prepare_generation_bootstrap(&project,&BTreeMap::new(),config,&executor,&host,&mut |_|Ok(())).unwrap(){GenerationBootstrapPreparation::MissingOutputs(frame)=>frame,GenerationBootstrapPreparation::NotNeeded=>panic!("other registered outputs remain absent")};
        assert!(next.declarations().declarations().count()>count);
        assert!(!next.declarations().omissions().any(|path|path==root.join("code/engine/_generated/reads.dm")));
        next.require_current(&FileSystemInputs).unwrap();
        // Once every registered output exists, the typed selection declines
        // this cold bootstrap before declaration parsing. The actual retained
        // full frontend is the caller's required next role.
        for relative in crate::query_db::QueryDb::generation_dm_outputs(){let path=root.join(relative);if !path.exists(){std::fs::create_dir_all(path.parent().unwrap()).unwrap();std::fs::write(path,"// real on-disk generated fixture\n").unwrap();}}
        assert!(matches!(RecordingInputs::new(FileSystemInputs,0).prepare_generation_bootstrap(&project,&BTreeMap::new(),config,&executor,&host,&mut |_|Ok(())).unwrap(),GenerationBootstrapPreparation::NotNeeded));
        // Arbitrary missing input is not a registered output and remains an
        // actual native preprocessing failure, rather than an omitted file.
        std::fs::write(&project,"#include \"not_registered.dm\"\n/datum/probe\n").unwrap();
        std::fs::remove_file(root.join("code/engine/_generated/reads.dm")).unwrap();
        let bad=RecordingInputs::new(FileSystemInputs,0);
        assert!(matches!(bad.prepare_generation_bootstrap(&project,&BTreeMap::new(),config,&executor,&host,&mut |_|Ok(())),Err(GenerationBootstrapFailure::Declarations(dm_tree::frontend::GenerationPreparationFailure::Preprocess(_)))));
    }
    #[test]
    fn actual_generation_bootstrap_refuses_operational_probe_and_quota_without_frame(){
        struct Failure;
        impl SnapshotProvider for Failure {
            fn stamp(&self,_:&Path)->io::Result<Stamp>{Err(io::Error::from_raw_os_error(1450))}
            fn read(&self,_:&Path)->io::Result<(Stamp,Vec<u8>)>{Err(io::Error::from_raw_os_error(1450))}
            fn list(&self,_:&Path)->io::Result<FolderListing>{Ok(FolderListing::Present(Vec::new()))}
        }
        let root=crate::test_scratch::dir("generation-bootstrap-errors");
        let project=root.join("main.dme");
        let host=Arc::new(crate::query_db::QueryDb::default()) as Arc<dyn dm_tree::frontend::SettingExpressionQueries>;
        let executor=dm_exec::BuildExecutor::new(1).unwrap();let config=dm_tree::frontend::FrontendConfig{workers:1,engine:None,observer:None};
        match RecordingInputs::new(Failure,0).prepare_generation_bootstrap(&project,&BTreeMap::new(),config,&executor,&host,&mut |_|Ok(())){Err(GenerationBootstrapFailure::Operational(actual))=>assert_eq!(actual.raw_os_error(),Some(1450)),_=>panic!("actual probe IO must remain operational")}
        struct LateFailure(PathBuf);
        impl SnapshotProvider for LateFailure {
            fn stamp(&self,path:&Path)->io::Result<Stamp>{SnapshotProvider::stamp(&FileSystemInputs,path)}
            fn read(&self,path:&Path)->io::Result<(Stamp,Vec<u8>)>{if path==self.0{Err(io::Error::from_raw_os_error(1450))}else{SnapshotProvider::read(&FileSystemInputs,path)}}
            fn list(&self,path:&Path)->io::Result<FolderListing>{SnapshotProvider::list(&FileSystemInputs,path)}
        }
        std::fs::create_dir_all(&root).unwrap();
        std::fs::write(&project,"#include \"late.dm\"\n/datum/probe\n").unwrap();
        match RecordingInputs::new(LateFailure(root.join("late.dm")),0).prepare_generation_bootstrap(&project,&BTreeMap::new(),config,&executor,&host,&mut |_|Ok(())){Err(GenerationBootstrapFailure::Operational(actual))=>assert_eq!(actual.raw_os_error(),Some(1450)),_=>panic!("late non-generated source IO must not become a preprocessing diagnostic")}
        match RecordingInputs::new(FileSystemInputs,0).prepare_generation_bootstrap(&project,&BTreeMap::new(),config,&executor,&host,&mut |_|Err(io::ErrorKind::OutOfMemory.into())){Err(GenerationBootstrapFailure::Operational(actual))=>assert_eq!(actual.kind(),io::ErrorKind::OutOfMemory),_=>panic!("quota must not issue a generation frame")}
    }
}

#[path="input_generation_sources.rs"]mod sources;
pub(crate) use sources::{GenerationSourceReader,GenerationSourceFrame,OwnedGenerationFrame,RetiredGenerationInputs};
impl GenerationBootstrap{
 pub(crate) fn require_recording<P:SnapshotProvider>(&self,inputs:&RecordingInputs<P>)->io::Result<()>{
  crate::daemon::control::checkpoint()?;
  for(path,lease)in self.declarations.original_sources(){
   let lease=lease.ok_or_else(||io::Error::new(io::ErrorKind::InvalidData,"generation original acquisition is absent"))?;
   if !inputs.validate_source_lease(path,lease)&&!inputs.validate_analysis_subject_lease(path,lease){return Err(io::Error::new(io::ErrorKind::InvalidData,"generation frame belongs to another original recorder"))}
  }
  self.require_current(&inputs.provider)?;crate::daemon::control::checkpoint()
 }
}

#[cfg(test)]mod generation_encountered_selection_tests{
 use super::*;use std::sync::{Arc,atomic::{AtomicUsize,Ordering}};
 #[test]fn unused_missing_registered_outputs_select_ordinary_before_declaration_parse(){
  let root=crate::test_scratch::dir("generation-unused-registered");let project=root.join("main.dme");std::fs::write(&project,"/datum/probe\n    var/value=7\n").unwrap();let recording=RecordingInputs::new(FileSystemInputs,0);let queries=Arc::new(crate::query_db::QueryDb::default());let host=queries.clone()as Arc<dyn dm_tree::frontend::SettingExpressionQueries>;let executor=dm_exec::BuildExecutor::new(1).unwrap();let parsed=AtomicUsize::new(0);let observer=|progress:dm_tree::frontend::FrontendProgress|{if progress.stage==dm_tree::frontend::FrontendStage::DeclarationParsing{parsed.fetch_add(1,Ordering::Relaxed);}};let config=dm_tree::frontend::FrontendConfig{workers:1,engine:None,observer:Some(&observer)};
  assert!(crate::query_db::QueryDb::generation_dm_outputs().all(|relative|!root.join(relative).exists()));
  assert!(matches!(recording.prepare_generation_bootstrap(&project,&Default::default(),config,&executor,&host,&mut |_|Ok(())).unwrap(),GenerationBootstrapPreparation::NotNeeded));
  assert!(matches!(recording.prepare_generation_question_bootstrap(&project,&Default::default(),config,&executor,&host,&mut |_|Ok(())).unwrap(),GenerationBootstrapPreparation::NotNeeded));assert_eq!(parsed.load(Ordering::Relaxed),0,"unused registry negatives never start a second declaration parse");
  std::fs::write(&project,"#include \"code/engine/_generated/deps.dm\"\n/datum/probe\n    var/value=7\n").unwrap();let current=RecordingInputs::new(FileSystemInputs,0);let GenerationBootstrapPreparation::MissingOutputs(frame)=current.prepare_generation_question_bootstrap(&project,&Default::default(),config,&executor,&host,&mut |_|Ok(())).unwrap()else{panic!("actual omitted include selects restricted preparation")};let expected=root.join("code/engine/_generated/deps.dm");assert_eq!(frame.declarations().encountered_omissions().collect::<Vec<_>>(),vec![expected.as_path()]);assert!(frame.declarations().omissions().count()>1,"permitted unused negatives stay distinct from encountered includes");assert!(parsed.load(Ordering::Relaxed)>0);
 }
 #[test]fn unrelated_missing_include_never_becomes_notneeded_or_omitted_generation_source(){
  let root=crate::test_scratch::dir("generation-unrelated-source");let project=root.join("main.dme");std::fs::write(&project,"#include \"code/unregistered_missing.dm\"\n/datum/probe\n").unwrap();let recording=RecordingInputs::new(FileSystemInputs,0);let queries=Arc::new(crate::query_db::QueryDb::default())as Arc<dyn dm_tree::frontend::SettingExpressionQueries>;let executor=dm_exec::BuildExecutor::new(1).unwrap();let result=recording.prepare_generation_bootstrap(&project,&Default::default(),dm_tree::frontend::FrontendConfig{workers:1,engine:None,observer:None},&executor,&queries,&mut |_|Ok(()));assert!(matches!(result,Err(GenerationBootstrapFailure::Declarations(dm_tree::frontend::GenerationPreparationFailure::Preprocess(ref errors)))if !errors.is_empty()),"actual unrelated source refusal must remain visible");
 }
}

#[cfg(all(test,windows))]mod source_notfound_tests{
 use super::*;use std::sync::Arc;
 #[test]fn actual_generation_nonregular_source_read_keeps_original_notfound_io_instead_of_missing_include_diagnostic(){
  let root=crate::test_scratch::dir("generation-existing-directory-source");std::fs::create_dir_all(root.join("code")).unwrap();let source=root.join("code/nonregular.dm");std::fs::create_dir(&source).unwrap();let project=root.join("main.dme");std::fs::write(&project,"#include \"code/nonregular.dm\"\n#include \"code/engine/_generated/deps.dm\"\n").unwrap();
  let expected=FileSystemInputs.read_verified(&source).err().unwrap();assert_eq!(expected.kind(),io::ErrorKind::NotFound);assert_eq!(FileSystemInputs.stamp(&source).err().unwrap().kind(),io::ErrorKind::NotFound,"regular-file stamps also reject an actual directory; they are insufficient absence proof");
  let recording=RecordingInputs::new(FileSystemInputs,0);let db=Arc::new(crate::query_db::QueryDb::default())as Arc<dyn dm_tree::frontend::SettingExpressionQueries>;let executor=dm_exec::BuildExecutor::new(1).unwrap();let config=dm_tree::frontend::FrontendConfig{workers:1,engine:None,observer:None};
  let error=recording.prepare_generation_bootstrap(&project,&BTreeMap::new(),config,&executor,&db,&mut |_|Ok(())).err().unwrap();let GenerationBootstrapFailure::Operational(actual)=error else{panic!("existing nonregular source read must remain operational: {error:?}")};assert_eq!(actual.kind(),expected.kind());assert_eq!(actual.raw_os_error(),expected.raw_os_error());assert_eq!(actual.to_string(),expected.to_string());assert!(!root.join("code/engine/_generated").exists());
 }
}
