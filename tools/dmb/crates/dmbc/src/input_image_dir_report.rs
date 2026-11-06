//! The fixed physical ImageDir capture. The config and body archive borrow the
//! same recorder, and no generic semantic or checker capture can be obtained.
use super::*;
use dm_preprocess::source_arena_credit::{self, SourceArenaCredit, SourceArenaWork};
use dm_tree::frontend::{FrontendBuildFailure, OriginalImageDirFrontend, SettingExpressionQueries};
use dq_analyze::{captured_raw_file::Config, captured_raw_policy::Configuration, selected_exclusions_wire::{Frame, Hex128}};
use std::sync::Arc;

#[derive(Clone, Copy)]
pub(crate) enum NamedImageDirNoticeMode { Forbid, WarningsAndHints }

pub(crate) struct NamedImageDirCapture {
    pub(crate) frontend: OriginalImageDirFrontend,
    pub(crate) config: Config,
    facts: InputSnapshot,
    frame: Frame,
    // Actual interpreted configuration drops before its parse reservation.
    _config_credit: SourceArenaCredit,
    _path_credit: SourceArenaCredit,
}

enum RootFailure { Source(&'static str), Operational(io::Error) }
impl From<&'static str> for RootFailure {
    fn from(message:&'static str)->Self { Self::Source(message) }
}
impl From<RootFailure> for io::Error {
    fn from(failure:RootFailure)->Self { match failure {
        RootFailure::Source(message)=>invalid(message),
        RootFailure::Operational(actual)=>actual,
    } }
}

fn frontend_failure(failure:FrontendBuildFailure)->io::Error {
    match failure {
        FrontendBuildFailure::Operational(actual)=>actual,
        other=>io::Error::new(io::ErrorKind::Unsupported,format!("fixed ImageDir Original preparation: {other:?}")),
    }
}

fn quota()->io::Error { io::ErrorKind::OutOfMemory.into() }

impl NamedImageDirCapture {
    /// The already validated canonical fixed root is a request coordinate.
    /// Only the actual recorder acquires the physical DME and its includes.
    pub(crate) fn prepare(
        root:&Path, queries:&Arc<crate::query_db::QueryDb>, notices:NamedImageDirNoticeMode,
    )->io::Result<Self> {
        crate::daemon::control::checkpoint()?;
        let work: &dyn SourceArenaWork=queries.as_ref();
        let path_bytes=root.as_os_str().len().checked_mul(8).and_then(|n|n.checked_add(4096)).ok_or_else(quota)?;
        let path_credit=work.reserve(path_bytes)?;
        let project=root.join("deepquarry.dme");
        let configuration=root.join("tools/ci/lint_scopes.toml");
        if project.capacity().checked_add(configuration.capacity()).is_none_or(|n|n>path_bytes) {
            return Err(quota());
        }
        let recording=RecordingInputs::new(FileSystemInputs,0)
            .with_initial_environment(dm_preprocess::InitialEnvironment::OriginalChecker0290);
        let host:Arc<dyn SettingExpressionQueries>=queries.clone();
        let seed=dm_tree::checker_builtins::original_analysis_seed()
            .map_err(|_|invalid("ImageDir Original declaration seed unavailable"))?;
        let executor=dm_exec::BuildExecutor::new(1).map_err(io::Error::other)?;
        let frontend=dm_tree::frontend::build_for_original_image_dir_checked(
            &project,&recording.original_batch_view(None),&Default::default(),
            dm_tree::frontend::FrontendConfig{workers:1,engine:Some(seed.frontend_seed()),observer:None},
            &executor,&host,
        ).map_err(frontend_failure)?.with_body_queries(queries.clone()).map_err(io::Error::other)?;
        match notices {
            NamedImageDirNoticeMode::Forbid if !frontend.has_no_original_preprocess_notices() => {
                return Err(io::Error::new(io::ErrorKind::Unsupported,"named ImageDir notice output has not been admitted"));
            }
            NamedImageDirNoticeMode::Forbid => {},
            NamedImageDirNoticeMode::WarningsAndHints => frontend.with_original_preprocess_notices(|notices| {
                for notice in notices.iter() {
                    crate::daemon::control::checkpoint()?;
                    let notice=notice.map_err(invalid)?;
                    if matches!(notice.severity,dm_preprocess::regions::OriginalNoticeSeverity::Error) {
                        return Err(io::Error::new(io::ErrorKind::Unsupported,"named ImageDir preprocessing errors are not admitted by the warning/hint role"));
                    }
                }
                Ok(())
            })?,
        }
        let mapping=frontend.archive().source_mapping();
        let (_,entry,physical,root_lease)=mapping.original_root_acquisition_using(
            &mut||crate::daemon::control::checkpoint().map_err(RootFailure::Operational),
        )?;
        if entry!=project || physical!=project
            || !recording.validate_recorded_source_lease(physical,root_lease)
            || root_lease.encoding()==dm_preprocess::SourceEncoding::SyntheticUtf8 {
            return Err(invalid("named ImageDir requires its actual fixed physical DME"));
        }
        // This narrow role never selects the legacy synthesized-manifest path.
        let root_bytes=recording.original_bytes_checked(root_lease)?;
        if !std::str::from_utf8(root_bytes).is_ok_and(|text|text.contains("#include")){
            return Err(io::Error::new(io::ErrorKind::Unsupported,"fixed ImageDir manifest marker is absent"));
        }
        for (path, lease) in mapping.source_acquisitions() {
            crate::daemon::control::checkpoint()?;
            if path==configuration || lease.is_some_and(|lease|lease.encoding()==dm_preprocess::SourceEncoding::SyntheticUtf8) {
                return Err(invalid("named ImageDir configuration cannot occupy an archive occurrence"));
            }
        }
        for (path,lease) in frontend.original_text_sources() {
            crate::daemon::control::checkpoint()?;
            if !lease.is_some_and(|lease|recording.validate_recorded_source_lease(path,lease)){
                return Err(invalid("named ImageDir has an unissued Original textual acquisition"));
            }
        }

        // Config is read only AFTER the source roster is sealed. The existing
        // exact reader records its own physical payload, never a compiler
        // occurrence, and its borrowed bytes carry the genuine input credit.
        let config_lease=match source_arena_credit::read_original_source_open_using(
            &recording,&configuration,dq_analyze::captured_raw_policy::MAX_FIXTURE_FILE_BYTES,
            work,&mut||Ok(dm_preprocess::OriginalRawOpenDecision::Read),
        )? {
            dm_preprocess::OriginalRawReadOutcome::Acquired(lease)=>lease,
            dm_preprocess::OriginalRawReadOutcome::SourceOpenFailed(actual)=>return Err(actual),
            _=>return Err(invalid("named ImageDir config has no actual opened input")),
        };
        if !recording.validate_recorded_source_lease(&configuration,&config_lease){
            return Err(invalid("named ImageDir config differs from its exact recorder"));
        }
        let config_bytes=recording.original_bytes_checked(&config_lease)?;
        // Use the existing conservative policy interpretation grant.
        let bound=config_bytes.len().checked_mul(64).and_then(|n|n.checked_add(8192)).ok_or_else(quota)?;
        let config_credit=work.reserve(bound)?;
        let config=Config::capture(Configuration::Captured(config_bytes)).map_err(io::Error::other)?;
        if config.budget_charge()>bound{return Err(quota())}
        let source_revision=frontend.source_revision();
        let semantic_revision=frontend.archive().tree().identity();
        let mut policy=xxhash_rust::xxh3::Xxh3::new();
        policy.update(b"native-analyze-named-image-dir-v1");
        let root_bytes=root.as_os_str().as_encoded_bytes();
        policy.update(&(root_bytes.len() as u64).to_le_bytes());
        policy.update(root_bytes);
        policy.update(&semantic_revision.to_le_bytes());
        policy.update(&source_revision.to_le_bytes());
        policy.update(&xxhash_rust::xxh3::xxh3_128(config_bytes).to_le_bytes());
        let frame=Frame{semantic_revision:Hex128(semantic_revision),source_revision:Hex128(source_revision),policy_revision:Hex128(policy.digest128())};
        drop(config_lease);
        // Move, never clone, the immutable facts. Validation then has no
        // recorder lock or raw-family gate across filesystem calls.
        let facts=recording.into_snapshot()?;
        // The named proof understands only exact Original input families.
        // Keep positive/negative metadata and opened-reader observations
        // distinct. In particular, never overwrite an earlier FEXISTS
        // decision just because the later configuration open succeeded.
        if !facts.files.is_empty() || !facts.folders.is_empty() || !facts.policy_directories.is_empty()
            || !facts.generated_outputs.is_empty() || !facts.negative_files.is_empty(){
            return Err(invalid("named ImageDir recorder acquired unsupported input fact families"));
        }
        if facts.path_presence.get(&configuration)==Some(false){
            return Err(io::Error::new(io::ErrorKind::Interrupted,"named ImageDir configuration contradicts the earlier metadata observation"));
        }
        // Where the filesystem exposes stable physical identity, also reject
        // an authored alias/hardlink of the config in the compiled roster.
        let config_id=facts.original_payloads.get(&configuration).ok_or_else(||invalid("named ImageDir config exact payload fact absent"))?.stamp.file_id;
        if let Some(config_id)=config_id {
            for (path,_) in frontend.archive().source_mapping().source_acquisitions(){
                crate::daemon::control::checkpoint()?;
                if facts.original_payloads.get(path).is_some_and(|fact|fact.stamp.file_id==Some(config_id)){
                    return Err(invalid("named ImageDir config aliases a physical archive occurrence"));
                }
            }
        }
        Ok(Self{frontend,config,facts,frame,_config_credit:config_credit,_path_credit:path_credit})
    }

    /// Require the exact closure this producer actually creates. This is not
    /// a general InputSnapshot validator or an ordinary freshness stamp.
    pub(crate) fn require_current(&self,work:&dyn SourceArenaWork)->io::Result<Frame>{
        // Existing FileSystemInputs digest uses one 64 KiB stack block. The
        // small fixed allowance also covers the transient handles/hasher.
        let _stream_credit=work.reserve(64*1024+4096)?;
        let provider=&FileSystemInputs;
        let facts=&self.facts;
        let stale=||io::Error::new(io::ErrorKind::Interrupted,"named ImageDir actual recorded inputs changed");
        for (path,present) in facts.path_presence.iter(){
            crate::daemon::control::checkpoint()?;
            if provider.path_presence(path)?!=*present {return Err(stale())}
        }
        for (path,opened) in facts.opened_reads.iter(){
            crate::daemon::control::checkpoint()?;
            if !opened.is_readable(){
                return Err(io::Error::new(io::ErrorKind::Unsupported,"named ImageDir has an unadmitted Original failed-open notice"));
            }
            // The digest below itself opens every captured payload. A real
            // suppression has an open fact but no payload to hash.
            if facts.original_payloads.get(path).is_none(){
                drop(std::fs::File::open(path)?);
            }
        }
        for (path,prior) in facts.original_payloads.iter(){
            crate::daemon::control::checkpoint()?;
            if !facts.opened_reads.get(path).is_some_and(|opened|opened.is_readable()){
                return Err(invalid("named ImageDir payload lacks an exact readable open fact"));
            }
            // Filesystem digest is the existing bounded, fixed stack reader.
            // Equal bytes with a changed timestamp remain the same report input.
            let (_,actual)=provider.digest(path)?;
            if actual!=prior.content {return Err(stale())}
        }
        crate::daemon::control::checkpoint()?;
        Ok(self.frame)
    }
}

#[cfg(test)]
mod controls {
    use super::*;

    #[test]
    fn named_image_dir_rejects_same_size_config_edit_without_refreshing_revision(){
        let root=std::fs::canonicalize(crate::test_scratch::dir("image-dir-actual-config-revalidation")).unwrap();
        std::fs::create_dir_all(root.join("tools/ci")).unwrap();
        std::fs::create_dir_all(root.join("code")).unwrap();
        std::fs::write(root.join("deepquarry.dme"),b"#include \"code/probe.dm\"\n").unwrap();
        std::fs::write(root.join("code/probe.dm"),b"/proc/p()\n    return 0\n").unwrap();
        let path=root.join("tools/ci/lint_scopes.toml");
        let old=b"[lint.image_dir_after_build.lists]\nexempt_files=[]\n# a\n";
        let new=b"[lint.image_dir_after_build.lists]\nexempt_files=[]\n# b\n";
        assert_eq!(old.len(),new.len());
        std::fs::write(&path,old).unwrap();
        let queries=Arc::new(crate::query_db::QueryDb::default());
        let capture=NamedImageDirCapture::prepare(&root,&queries,NamedImageDirNoticeMode::Forbid).unwrap();
        let before=capture.require_current(queries.as_ref()).unwrap();
        std::fs::write(&path,new).unwrap();
        assert_eq!(capture.require_current(queries.as_ref()).unwrap_err().kind(),io::ErrorKind::Interrupted);
        std::fs::write(&path,old).unwrap();
        assert_eq!(capture.require_current(queries.as_ref()).unwrap(),before);
    }
}
