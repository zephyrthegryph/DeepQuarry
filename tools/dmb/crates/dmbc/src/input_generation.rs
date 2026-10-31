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
        let mut run=||->Result<GenerationBootstrapPreparation,GenerationBootstrapFailure>{
            crate::daemon::control::checkpoint().map_err(GenerationBootstrapFailure::Operational)?;
            if !project.is_absolute(){return Err(GenerationBootstrapFailure::Operational(io::Error::new(io::ErrorKind::InvalidInput,"generation manifest must be caller absolute")));}
            let root=project.parent().ok_or_else(||GenerationBootstrapFailure::Operational(io::Error::new(io::ErrorKind::InvalidInput,"generation manifest has no parent")))?;
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
            let declarations=dm_tree::frontend::prepare_generation_declarations(project,self,defines,omissions,config,executor,host,&|path|{
                crate::daemon::control::checkpoint()?;
                let parent=path.parent().ok_or_else(||io::Error::new(io::ErrorKind::InvalidInput,"generation source has no parent"))?;
                self.record_search_folder(parent)?;
                match self.read_recorded(path){
                    Ok(bytes)=>self.acquire_recorded_source(path,bytes).map(|source|Some(std::sync::Arc::clone(source.prepared()))),
                    Err(actual) if actual.kind()==io::ErrorKind::NotFound=>{self.snapshot.lock().map_err(|_|invalid("input capture mutex poisoned"))?.record_negative(path)?;Ok(None)},
                    Err(actual)=>Err(actual),
                }
            }).map_err(|failure|match failure {dm_tree::frontend::GenerationPreparationFailure::Frontend(dm_tree::frontend::FrontendBuildFailure::Operational(actual))=>GenerationBootstrapFailure::Operational(actual),other=>GenerationBootstrapFailure::Declarations(other)})?;
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
