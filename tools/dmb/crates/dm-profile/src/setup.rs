use super::*;
use tracing_subscriber::prelude::*;

pub(super) fn initialize(path: &Path) -> Result<ProfileGuard, String> {
    let start = Instant::now();
    let process = clock::process();
    if let Some(parent) = path.parent().filter(|p| !p.as_os_str().is_empty()) {
        std::fs::create_dir_all(parent).map_err(|e| e.to_string())?;
    }
    let state = Arc::new(State {
        calibration: clock::calibrate(),
        io_wait: io_wait::Ledger::default(),
        entries: Mutex::new(BTreeMap::new()),
        folded: Mutex::new(BTreeMap::new()),
        wall_folded: Mutex::new(BTreeMap::new()),
        finished: AtomicBool::new(false),
        workers: AtomicUsize::new(0),
        bindings: AtomicUsize::new(0),
        dispatch: Mutex::new(None),
    });
    let lease = request::RequestLease::claim(Arc::clone(&state))?;
    request::initialize_tracing()?;
    let setup = internal_observer::InternalThreadObserver::new(Arc::clone(&state), "profile.setup");
    let mut trace_outputs = trace_output::Outputs::from_environment().map_err(|e| e.to_string())?;
    let writer = writer::ObservedWriter::new(
        trace_outputs
            .writer(path, "chrome-json")
            .map_err(|e| e.to_string())?,
        Arc::clone(&state),
    );
    let (chrome, chrome_guard) = chrome::layer(writer)?;
    let flame_writer = trace_outputs
        .writer(&artifact_path(path, ".tracing.folded"), "tracing-folded")
        .map_err(|e| e.to_string())?;
    let flame = tracing_flame::FlameLayer::new(std::io::BufWriter::new(flame_writer));
    let flame_guard = flame.flush_on_drop();
    let subscriber = tracing_subscriber::registry()
        .with(names::Names)
        .with(chrome)
        .with(flame);
    let dispatch = tracing::Dispatch::new(subscriber);
    *state.dispatch.lock().unwrap_or_else(|e| e.into_inner()) = Some(dispatch);
    let binding = RequestContext::from_state(&state)
        .expect("new profiler dispatch")
        .enter()?;
    let memory_sampler = memory::Sampler::start(Arc::clone(&state))?;
    drop(setup);
    Ok(ProfileGuard {
        state,
        start,
        process,
        path: path.into(),
        chrome: Some(chrome_guard),
        flame: Some(flame_guard),
        trace_outputs,
        memory_sampler,
        request_binding: Some(binding),
        request_lease: lease,
    })
}
