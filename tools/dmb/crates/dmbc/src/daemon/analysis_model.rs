//! The converted model a hosted analysis request gets from dmbc's front end, kept per `.dme` (and define set) between requests.
//!
//! Building dq-analyze's model (`analysis_tree::parse_for_analysis`) is the front end (from the retained session,
//! `service::hosted_frontend`) plus converting it to the dreammaker-shaped `ObjectTree`, and the conversion is most of the time.
//! A request whose every source file the last conversion read is byte for byte the same gets that conversion back (decoded from
//! its encoded copy) instead of converting again: the model is a function of those files (the `.dme` among them; the macro
//! environment and every include come from them, a newly included file is named by a changed one) and of the define set, which
//! dmbc's parse fixes. One `check` asks twice (the analysis model and DreamChecker's), so the second is served from the first.
//!
//! Only inside the daemon (`register_hosted_provider`); the client and CI parse as before. `DQ_ANALYZE_MODEL_MEMO=0` turns it off.
use dreammaker::{Location, Severity};
use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::Mutex;
use std::time::Instant;

type Hash = u128;

/// One diagnostic, as the model reports it.
#[derive(Clone)]
struct Diagnostic {
    location: Location,
    severity: Severity,
    component: dreammaker::Component,
    description: String,
    errortype: Option<&'static str>,
    notes: Vec<(Location, String)>,
}
impl Diagnostic {
    fn of(e: &dreammaker::DMError) -> Self {
        Self {
            location: e.location(),
            severity: e.severity(),
            component: e.component(),
            description: e.description().to_string(),
            errortype: e.errortype(),
            notes: e.notes().iter().map(|n| (n.location(), n.description().to_string())).collect(),
        }
    }
    fn make(&self) -> dreammaker::DMError {
        let mut e = dreammaker::DMError::new(self.location, self.description.clone())
            .set_severity(self.severity)
            .with_component(self.component);
        if let Some(t) = self.errortype {
            e = e.with_errortype(t);
        }
        for (l, d) in &self.notes {
            e.add_note(*l, d.clone());
        }
        e
    }
}

struct Memo {
    /// Every file the model registered (relative to the root, or absolute) and its bytes' digest.
    inputs: Vec<(PathBuf, Hash)>,
    tree: Vec<u8>,
    errors: Vec<String>,
    fatal: bool,
    /// DreamChecker's diagnostics (`Parsed::raw`): its stream, summary line and what finishing the tree registered.
    stream: Vec<Diagnostic>,
    summary: Option<String>,
    finish: Vec<Diagnostic>,
}

static MEMO: Mutex<Option<HashMap<PathBuf, Memo>>> = Mutex::new(None);

fn enabled() -> bool {
    !matches!(dq_hostio::var("DQ_ANALYZE_MODEL_MEMO").as_deref(), Ok("0") | Ok("off"))
}

fn digest(path: &Path) -> Hash {
    std::fs::read(path).map(|b| xxhash_rust::xxh3::xxh3_128(&b)).unwrap_or(0)
}

fn root_of(dme: &Path) -> PathBuf {
    let abs = if dme.is_absolute() {
        dme.to_path_buf()
    } else {
        dq_hostio::current_dir().map(|cwd| cwd.join(dme)).unwrap_or_else(|_| dme.to_path_buf())
    };
    let abs: PathBuf = abs.components().filter(|c| !matches!(c, std::path::Component::CurDir)).collect();
    abs
}

fn inputs_of(root: &Path, files: &dreammaker::FileList) -> Vec<(PathBuf, Hash)> {
    let mut paths = Vec::new();
    files.for_each(|p| paths.push(p.to_path_buf()));
    let dir = root.parent().map(Path::to_path_buf).unwrap_or_default();
    // Hashing ~6000 files: on the executor threads would contend with a compile; a scoped fan-out of 8 is enough.
    let chunk = paths.len().div_ceil(8).max(1);
    let mut out = Vec::with_capacity(paths.len());
    std::thread::scope(|s| {
        let parts: Vec<_> = paths
            .chunks(chunk)
            .map(|part| {
                let dir = &dir;
                s.spawn(move || part.iter().map(|p| (p.clone(), digest(&if p.is_absolute() { p.clone() } else { dir.join(p) }))).collect::<Vec<_>>())
            })
            .collect();
        for part in parts {
            out.extend(part.join().unwrap_or_default());
        }
    });
    out
}

fn same_inputs(root: &Path, inputs: &[(PathBuf, Hash)]) -> bool {
    let dir = root.parent().map(Path::to_path_buf).unwrap_or_default();
    let chunk = inputs.len().div_ceil(8).max(1);
    std::thread::scope(|s| {
        let parts: Vec<_> = inputs
            .chunks(chunk)
            .map(|part| {
                let dir = &dir;
                s.spawn(move || part.iter().all(|(p, h)| digest(&if p.is_absolute() { p.clone() } else { dir.join(p) }) == *h))
            })
            .collect();
        parts.into_iter().all(|p| p.join().unwrap_or(false))
    })
}

/// The provider registered inside the daemon: the remembered model when its inputs are unchanged, else a conversion (remembered).
pub(crate) fn parse(dme: &Path, checker: bool) -> Result<dq_analyze::sem::model_store::Parsed, String> {
    if !enabled() {
        return crate::analysis_tree::parse_for_analysis(dme, checker);
    }
    let started = Instant::now();
    let root = root_of(dme);
    let mut guard = MEMO.lock().unwrap_or_else(|e| e.into_inner());
    let memos = guard.get_or_insert_with(HashMap::new);
    if let Some(memo) = memos.get(&root) {
        if same_inputs(&root, &memo.inputs) {
            let compared = started.elapsed();
            if let Ok(objtree) = dq_analyze::incr::de::<dreammaker::objtree::ObjectTree>(&memo.tree) {
                let files_ctx = dreammaker::Context::default();
                for (p, _) in &memo.inputs {
                    files_ctx.register_file(p);
                }
                let raw = checker.then(|| dq_analyze::sem::model_store::CheckerDiagnostics {
                    stream: memo.stream.iter().map(Diagnostic::make).collect(),
                    summary: memo.summary.clone(),
                    finish: memo.finish.iter().map(Diagnostic::make).collect(),
                });
                super::emit_stderr(format_args!(
                    "dmbd analyze: model of {} unchanged ({} files compared in {compared:.1?}), decoded in {:.1?}",
                    root.display(),
                    memo.inputs.len(),
                    started.elapsed() - compared
                ));
                return Ok(dq_analyze::sem::model_store::Parsed {
                    objtree,
                    files: files_ctx.clone_file_list(),
                    errors: memo.errors.clone(),
                    env: None,
                    structure: None,
                    defines: None,
                    raw,
                    fatal: memo.fatal,
                });
            }
        }
        memos.remove(&root);
    }
    drop(guard);
    // A checker parse keeps DreamChecker's diagnostics; remembering one serves both kinds of request.
    let parsed = crate::analysis_tree::parse_for_analysis(dme, true)?;
    let converted = started.elapsed();
    let t = Instant::now();
    let inputs = inputs_of(&root, &parsed.files);
    let raw = parsed.raw.as_ref();
    let memo = dq_analyze::incr::ser(&parsed.objtree).ok().map(|tree| Memo {
        inputs,
        tree,
        errors: parsed.errors.clone(),
        fatal: parsed.fatal,
        stream: raw.map(|r| r.stream.iter().map(Diagnostic::of).collect()).unwrap_or_default(),
        summary: raw.and_then(|r| r.summary.clone()),
        finish: raw.map(|r| r.finish.iter().map(Diagnostic::of).collect()).unwrap_or_default(),
    });
    if let Some(memo) = memo {
        super::emit_stderr(format_args!(
            "dmbd analyze: model of {} converted in {converted:.1?}, remembered ({} files, {} MB encoded) in {:.1?}",
            root.display(),
            memo.inputs.len(),
            memo.tree.len() >> 20,
            t.elapsed()
        ));
        MEMO.lock().unwrap_or_else(|e| e.into_inner()).get_or_insert_with(HashMap::new).insert(root, memo);
    }
    let mut parsed = parsed;
    if !checker {
        parsed.raw = None;
    }
    Ok(parsed)
}

/// Drops every remembered model (memory pressure, idle shedding). Returns how many encoded bytes were freed.
pub(crate) fn shed() -> usize {
    MEMO.lock().unwrap_or_else(|e| e.into_inner()).take().map_or(0, |m| m.values().map(|v| v.tree.len()).sum())
}
