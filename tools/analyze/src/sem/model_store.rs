//! The parsed model, kept between runs: a one-file edit re-parses one file instead of the tree.
//!
//! The full parse of `deepquarry.dme` is 10-12 s; reading the model back is about 2 s. After a full parse the object tree is written to
//! `data/analyze-cache/sem-model.bin` with the file table it was parsed with (every file the preprocessor registered, in order, and a
//! content key for each). The next run that builds the model reads it back and compares the keys:
//!
//! * nothing changed: the stored tree is the model;
//! * a few `.dm` files changed, none of them under `code/__defines/` and none holding a `#define`, `#undef` or `#include` before or
//!   after: each is parsed again on its own, after the files whose preprocessor state it can see (the `.dme` itself and every earlier
//!   file holding such a directive), with the file table pre-registered so its locations name the same file ids, and
//!   [`ObjectTree::splice_file`](dreammaker::objtree::ObjectTree::splice_file) puts its new proc bodies and locations in place. A
//!   change of structure (a definition added, removed or re-declared, a var value expression changed) is refused there;
//! * anything else (the `.dme`, the file set, the analyzer build, a define): the full parse.
//!
//! So the stored tree plus the splices is the tree a full parse would give; `DQ_MODEL_VERIFY=1` proves it on every splice by parsing the
//! whole tree too and comparing the two byte for byte (and uses the full parse when they differ). `DQ_MODEL_STORE=off` disables the store.
//! The new tree is written back on a side thread while the run goes on; [`finish`] waits for it before the process exits.

use std::path::{Path, PathBuf};
use std::sync::Mutex;

use dreammaker::objtree::ObjectTree;
use serde::{Deserialize, Serialize};

use crate::tree::{Hash, Tree};

const FILE: &str = "sem-model.bin";
/// More changed files than this and the full parse is cheaper than the partial ones.
const MAX_SPLICED: usize = 12;

pub struct Parsed {
    pub objtree: ObjectTree,
    pub files: dreammaker::FileList,
    pub errors: Vec<String>,
}

#[derive(Serialize)]
struct StoredRef<'a> {
    engine: &'a str,
    dme: Hash,
    paths: &'a [PathBuf],
    keys: &'a [Hash],
    directive: &'a [bool],
    errors: &'a [String],
    objtree: &'a ObjectTree,
}

#[derive(Deserialize)]
struct Stored {
    engine: String,
    dme: Hash,
    paths: Vec<PathBuf>,
    keys: Vec<Hash>,
    directive: Vec<bool>,
    errors: Vec<String>,
    objtree: ObjectTree,
}

/// What [`save_later`] writes: the table of the model just built.
struct Meta {
    path: PathBuf,
    dme: Hash,
    paths: Vec<PathBuf>,
    keys: Vec<Hash>,
    directive: Vec<bool>,
    errors: Vec<String>,
}

static PENDING_META: Mutex<Option<Meta>> = Mutex::new(None);
static WRITER: Mutex<Option<std::thread::JoinHandle<()>>> = Mutex::new(None);

fn trace() -> bool {
    std::env::var_os("DQ_ANALYZE_TRACE").is_some()
}

fn enabled() -> bool {
    !matches!(std::env::var("DQ_MODEL_STORE").as_deref(), Ok("off") | Ok("0")) && crate::incr::stamp().is_some()
}

fn engine() -> String {
    format!("{}|model-v1", crate::cache::ENGINE_HASH)
}

fn h128(bytes: &[u8]) -> Hash {
    u128::from_le_bytes(blake3::hash(bytes).as_bytes()[..16].try_into().unwrap())
}

/// The content key of a registered file: the tree's hash for a file the tree holds, else a digest of its bytes on disk.
fn key_of(tree: &Tree, root: &Path, path: &Path) -> Hash {
    let rel = crate::util::rel_slash(path, root);
    if let Some(f) = tree.get(&rel) {
        return f.hash;
    }
    std::fs::read(path).map(|b| h128(&b)).unwrap_or(0)
}

/// A preprocessor directive that changes the macro state later files see.
fn mutates_macros(text: &str) -> bool {
    text.lines().any(|l| {
        let t = l.trim_start();
        if !t.starts_with('#') {
            return false;
        }
        let d = t[1..].trim_start();
        d.starts_with("define") || d.starts_with("undef") || d.starts_with("include")
    })
}

fn text_of(tree: &Tree, root: &Path, path: &Path) -> Option<String> {
    let rel = crate::util::rel_slash(path, root);
    match tree.get(&rel) {
        Some(f) => Some(f.code().text.clone()),
        None => std::fs::read_to_string(path).ok(),
    }
}

/// A registered path (relative to the .dme's directory, or absolute) in one comparable form.
fn norm_in(root: &Path, p: &Path) -> String {
    let abs = if p.is_absolute() { p.to_path_buf() } else { root.join(p) };
    abs.to_string_lossy().replace('\\', "/").to_ascii_lowercase()
}

/// The model of the real `.dme`: the stored one brought up to date, or a full parse.
pub fn obtain(root: &Path, tree: &Tree, dme_path: &Path) -> Result<Parsed, String> {
    if !enabled() {
        return super::parse_dme(dme_path, &[], None);
    }
    let Some(dir) = crate::incr::dir() else { return super::parse_dme(dme_path, &[], None) };
    let store = dir.join(FILE);
    let dme_hash = std::fs::read(dme_path).map(|b| h128(&b)).unwrap_or(0);
    let t0 = std::time::Instant::now();
    let reused = match load(&store) {
        Some(s) if s.engine == engine() && s.dme == dme_hash => update(root, tree, dme_path, s),
        Some(_) => Err("the analyzer or the .dme changed".to_string()),
        None => Err("no stored model".to_string()),
    };
    let parsed = match reused {
        Ok((p, spliced)) => {
            if trace() {
                eprintln!("analyze: model store: reused the stored model, {} file(s) re-parsed, in {:.1?}", spliced, t0.elapsed());
            }
            if spliced == 0 {
                // Unchanged: nothing to write back.
                return Ok(p);
            }
            p
        }
        Err(why) => {
            if trace() {
                eprintln!("analyze: model store: full parse ({})", why);
            }
            super::parse_dme(dme_path, &[], None)?
        }
    };
    let mut paths = Vec::new();
    parsed.files.for_each(|p| paths.push(p.to_path_buf()));
    let keys = paths.iter().map(|p| key_of(tree, root, p)).collect();
    let directive = paths.iter().map(|p| text_of(tree, root, p).map(|t| mutates_macros(&t)).unwrap_or(true)).collect();
    *PENDING_META.lock().unwrap() = Some(Meta { path: store, dme: dme_hash, paths, keys, directive, errors: parsed.errors.clone() });
    Ok(parsed)
}

fn load(path: &Path) -> Option<Stored> {
    let bytes = std::fs::read(path).ok()?;
    bincode::deserialize(&bytes).ok()
}

fn file_list(paths: &[PathBuf]) -> dreammaker::FileList {
    let fl = dreammaker::FileList::default();
    for p in paths {
        fl.register(p);
    }
    fl
}

/// The stored model with the changed files spliced in, and how many were.
fn update(root: &Path, tree: &Tree, dme_path: &Path, mut s: Stored) -> Result<(Parsed, usize), String> {
    let now: Vec<Hash> = s.paths.iter().map(|p| key_of(tree, root, p)).collect();
    // A file the tree has that the stored parse never registered may be newly included: the .dme is unchanged, so only through
    // another file's #include, which is a directive that changed that file.
    let changed: Vec<usize> = (0..s.paths.len()).filter(|&i| now[i] != s.keys[i]).collect();
    if changed.is_empty() {
        let files = file_list(&s.paths);
        return Ok((Parsed { objtree: s.objtree, files, errors: s.errors }, 0));
    }
    if changed.len() > MAX_SPLICED {
        return Err(format!("{} files changed", changed.len()));
    }
    let dme_norm = norm_in(root, dme_path);
    for &i in &changed {
        let p = &s.paths[i];
        let rel = crate::util::rel_slash(p, root);
        if norm_in(root, p) == dme_norm || !rel.ends_with(".dm") || rel.starts_with("code/__defines/") {
            return Err(format!("{} changed", rel));
        }
        let Some(text) = text_of(tree, root, p) else { return Err(format!("{} unreadable", rel)) };
        if mutates_macros(&text) || s.directive.get(i).copied().unwrap_or(true) {
            return Err(format!("{} holds a preprocessor directive", rel));
        }
    }
    // Which registered files change the macro state, judged on the current text (the changed ones hold none now; one that held one before
    // would have changed what later files saw, and its old text is gone, so refuse a changed file the stored flags mark).
    let mut directive: Vec<bool> = Vec::with_capacity(s.paths.len());
    for p in &s.paths {
        directive.push(text_of(tree, root, p).map(|t| mutates_macros(&t)).unwrap_or(true));
    }
    let dme_text = std::fs::read_to_string(dme_path).map_err(|e| e.to_string())?;
    let files = file_list(&s.paths);
    let mut spliced = 0;
    for &i in &changed {
        let target = &s.paths[i];
        let fid = files.get_id(target).ok_or("no file id")?;
        // The .dme with only the includes the file's macro state depends on, then the file itself.
        let keep: std::collections::HashSet<String> = s.paths[..i].iter().enumerate().filter(|(j, _)| directive[*j]).map(|(_, p)| norm_in(root, p)).chain(std::iter::once(norm_in(root, target))).collect();
        let mut synth = String::with_capacity(dme_text.len());
        let dme_dir = dme_path.parent().unwrap_or(root);
        for line in dme_text.lines() {
            let t = line.trim_start();
            if let Some(rest) = t.strip_prefix("#include") {
                let inc = rest.trim().trim_matches('"');
                let abs = dme_dir.join(inc.replace('\\', "/"));
                if keep.contains(&norm_in(root, &abs)) {
                    synth.push_str(line);
                    synth.push('\n');
                } else {
                    synth.push('\n');
                }
                continue;
            }
            synth.push_str(line);
            synth.push('\n');
        }
        let partial = super::parse_dme(dme_path, &s.paths, Some(synth))?;
        if partial.files.get_id(target) != Some(fid) {
            return Err("the partial parse named the file differently".to_string());
        }
        if trace() && !partial.errors.is_empty() {
            eprintln!("analyze: model store: the partial parse of {} logged {} error(s), first: {}", crate::util::rel_slash(target, root), partial.errors.len(), partial.errors[0]);
        }
        let n = s.objtree.splice_file(fid, &partial.objtree).map_err(|e| format!("{}: {}", crate::util::rel_slash(target, root), e))?;
        if trace() {
            eprintln!("analyze: model store: spliced {} ({} proc definitions changed)", crate::util::rel_slash(target, root), n);
        }
        spliced += 1;
    }
    if std::env::var_os("DQ_MODEL_VERIFY").is_some() {
        let full = super::parse_dme(dme_path, &[], None)?;
        let a = bincode::serialize(&s.objtree).map_err(|e| e.to_string())?;
        let b = bincode::serialize(&full.objtree).map_err(|e| e.to_string())?;
        if a != b {
            if let Some(d) = std::env::var_os("DQ_MODEL_VERIFY_DUMP") {
                let d = PathBuf::from(d);
                let _ = std::fs::write(d.join("spliced.bin"), &a);
                let _ = std::fs::write(d.join("full.bin"), &b);
            }
            eprintln!("analyze: model store: VERIFY FAILED: the spliced model differs from a full parse ({} vs {} bytes); using the full parse", a.len(), b.len());
            return Err("verify failed".to_string());
        }
        eprintln!("analyze: model store: verify ok");
    }
    Ok((Parsed { objtree: s.objtree, files, errors: s.errors }, spliced))
}

/// Called once the model is in the memo: writes it back on a side thread when this run parsed or changed it.
pub fn save_later(handle: std::sync::Arc<super::SemBox>) {
    let Some(meta) = PENDING_META.lock().unwrap().take() else { return };
    let t = std::thread::Builder::new().name("model-store".into()).spawn(move || {
        let Some(sem) = handle.sem.as_ref() else { return };
        let t0 = std::time::Instant::now();
        let r = StoredRef { engine: &engine(), dme: meta.dme, paths: &meta.paths, keys: &meta.keys, directive: &meta.directive, errors: &meta.errors, objtree: &sem.objtree };
        let Ok(bytes) = bincode::serialize(&r) else { return };
        let tmp = meta.path.with_extension(format!("tmp{}", std::process::id()));
        if std::fs::write(&tmp, &bytes).is_ok() && std::fs::rename(&tmp, &meta.path).is_err() {
            let _ = std::fs::remove_file(&tmp);
        }
        if trace() {
            eprintln!("analyze: model store: wrote {} MB in {:.1?}", bytes.len() >> 20, t0.elapsed());
        }
    });
    if let Ok(t) = t {
        *WRITER.lock().unwrap() = Some(t);
    }
}

/// Waits for the model write (called before the process exits).
pub fn finish() {
    if let Some(t) = WRITER.lock().unwrap().take() {
        let _ = t.join();
    }
}
