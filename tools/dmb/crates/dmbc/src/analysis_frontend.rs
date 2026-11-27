//! The compiler front end dq-analyze's semantic model reads (doc/rewrite/proposals/lean_unified.md, "Workstream 2a LINTS"): the provider
//! dq-analyze calls for a `.dme` (`dq_analyze::sem::register_frontend_provider`). Inside the daemon the retained session of the root
//! supplies the revision (incrementally after an edit); elsewhere it is built cold. dq-analyze reads the tree as SpacemanDMM tools do:
//! `SPACEMAN_DMM` is defined, so code under `#if defined(SPACEMAN_DMM)` (the test fixtures among it) is part of the model.
use dm_tree::frontend::{ColdFrontend, FrontendRevision};
use std::collections::BTreeMap;
use std::path::Path;

/// The pinned target's predefines: what dmbc's preprocess starts with.
pub(crate) fn native_defines() -> BTreeMap<String, String> {
    let mut defines = BTreeMap::new();
    crate::pinned_target::admit_defines(&mut defines).expect("the pinned target admits its own defaults");
    defines
}

/// The predefines analysis builds the front end with: the pinned target's and `SPACEMAN_DMM`.
pub(crate) fn analysis_defines() -> BTreeMap<String, String> {
    let mut defines = native_defines();
    defines.insert("SPACEMAN_DMM".into(), "1".into());
    defines
}

/// A cold front end of `dme` under `defines`, against the engine's bootstrap catalog.
pub(crate) fn build_frontend_with(dme: &Path, defines: BTreeMap<String, String>) -> Result<ColdFrontend, Box<dyn std::error::Error>> {
    let workers = std::thread::available_parallelism().map(|n| n.get()).unwrap_or(4);
    let mut host = crate::runner_host::BuildHost::one_shot();
    let engine = host.engine(dme.to_path_buf(), defines.clone(), true, include_bytes!("../../../fixtures/native_template.bin").to_vec())?;
    let frontend = dm_tree::frontend::build_with_config(
        dme,
        &dm_preprocess::FileSystem,
        &defines,
        dm_tree::frontend::FrontendConfig { workers, engine: Some(engine.frontend_seed()), observer: None },
    )
    .map_err(|d| format!("front end failed: {} diagnostic(s), first: {:?}", d.len(), d.first().map(|x| &x.message)))?;
    Ok(frontend)
}

/// The analysis front end of `dme`: the daemon's retained session when it hosts this request, else a cold build.
pub fn frontend(dme: &Path) -> Result<FrontendRevision, String> {
    let defines = analysis_defines();
    let started = std::time::Instant::now();
    let revision = match crate::daemon::hosted_frontend(dme, &defines) {
        Some(revision) => revision?,
        None => FrontendRevision::new(build_frontend_with(dme, defines).map_err(|e| e.to_string())?),
    };
    if dq_hostio::var_os("DQ_ANALYZE_PARSE_TRACE").is_some() {
        dq_hostio::out(false, format_args!("analyze: dmbc front end {:.1?}", started.elapsed()), true);
    }
    Ok(revision)
}

/// Registers [`frontend`] as dq-analyze's front end.
pub fn register_analysis_provider() {
    dq_analyze::sem::register_frontend_provider(frontend);
}
