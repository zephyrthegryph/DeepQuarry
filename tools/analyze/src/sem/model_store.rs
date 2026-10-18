//! The parsed model, kept between runs: a one-file edit re-parses one file instead of the tree.
//!
//! The full parse of `deepquarry.dme` is 10-12 s; reading the model back is about 1.5 s. After a full parse the object tree is written to
//! `data/analyze-cache/sem-model.bin` (the **base**) with the file table it was parsed with (every file the preprocessor registered, in
//! order, a content key for each and whether it holds a preprocessor directive). The next run that builds the model reads it back and
//! compares the keys:
//!
//! * nothing changed: the stored tree is the model;
//! * a few `.dm` files changed, none of them under `code/__defines/` and none holding a `#define`, `#undef` or `#include` before or
//!   after: each is parsed again on its own, after the files whose preprocessor state it can see (the `.dme` itself and every earlier
//!   file holding such a directive), with the file table pre-registered so its locations name the same file ids. What the file now
//!   contributes ([`FilePatch`](dreammaker::objtree::FilePatch)) replaces what it contributed
//!   ([`ObjectTree::splice_patch`](dreammaker::objtree::ObjectTree::splice_patch)); a change of structure (a definition added, removed or
//!   re-declared, a var value expression changed) is refused there;
//! * anything else (the `.dme`, the file set, the analyzer build, a define): the full parse.
//!
//! The patches of the files that differ from the base are kept in `sem-model-delta.bin` with the content they were made from, so the next
//! run applies them without parsing; the base is rewritten (on a side thread, [`finish`] waits for it) only after a full parse or when
//! the delta holds more than [`REBASE_AT`] files. `DQ_MODEL_VERIFY=1` proves every update by parsing the whole tree too and comparing the
//! two byte for byte (and uses the full parse when they differ). `DQ_MODEL_STORE=off` disables the store.

use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::Mutex;

use dreammaker::objtree::{FilePatch, ObjectTree};
use serde::{Deserialize, Serialize};

use crate::tree::{Hash, Tree};

const FILE: &str = "sem-model.bin";
const DELTA: &str = "sem-model-delta.bin";
/// More files to parse than this and the full parse is cheaper than the partial ones.
const MAX_SPLICED: usize = 12;
/// A delta of more files than this is folded into a new base.
const REBASE_AT: usize = 48;

pub struct Parsed {
    pub objtree: ObjectTree,
    pub files: dreammaker::FileList,
    pub errors: Vec<String>,
    /// The macro environment ([`environment`]), when the store already knows it.
    pub env: Option<Hash>,
    /// The structure digest (`Sem::structure_digest`), when the store already knows it: patches never change the structure.
    pub structure: Option<u128>,
    /// A full parse's macro history: the macro state at the start of every file, so a later run parses one file alone.
    pub defines: Option<dreammaker::preprocessor::StoredDefineHistory>,
}

#[derive(Serialize)]
struct StoredRef<'a> {
    engine: &'a str,
    dme: Hash,
    paths: &'a [PathBuf],
    keys: &'a [Hash],
    directive: &'a [bool],
    env: Hash,
    structure: u128,
    errors: &'a [String],
    /// How many slice files (`sem-model.<generation>.<n>.bin`) hold the type graph: each is read and decoded on its own core. A new
    /// base writes a new generation, so a reader of the old header never meets the new slices.
    slices: usize,
    generation: u128,
    types: &'a std::collections::BTreeMap<String, dreammaker::objtree::NodeIndex>,
}

#[derive(Deserialize)]
struct Stored {
    engine: String,
    dme: Hash,
    paths: Vec<PathBuf>,
    keys: Vec<Hash>,
    directive: Vec<bool>,
    env: Hash,
    structure: u128,
    errors: Vec<String>,
    slices: usize,
    generation: u128,
    types: std::collections::BTreeMap<String, dreammaker::objtree::NodeIndex>,
}

/// [`Stored`] with its tree decoded.
struct Base {
    engine: String,
    dme: Hash,
    paths: Vec<PathBuf>,
    keys: Vec<Hash>,
    directive: Vec<bool>,
    env: Hash,
    structure: u128,
    errors: Vec<String>,
    generation: u128,
    objtree: ObjectTree,
}

/// The files that differ from the base: index into the base's file table, the content key the patch was made from, the patch.
#[derive(Serialize, Deserialize, Default)]
struct Delta {
    engine: String,
    base: Hash,
    patches: Vec<(u32, Hash, FilePatch)>,
}

/// What [`save_later`] writes: the table of the model just built.
struct Meta {
    path: PathBuf,
    defines: Option<dreammaker::preprocessor::StoredDefineHistory>,
    dme: Hash,
    paths: Vec<PathBuf>,
    keys: Vec<Hash>,
    directive: Vec<bool>,
    env: Hash,
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
    format!("{}|model-v2", crate::cache::ENGINE_HASH)
}

fn h128(bytes: &[u8]) -> Hash {
    u128::from_le_bytes(blake3::hash(bytes).as_bytes()[..16].try_into().unwrap())
}

fn abs_in(root: &Path, p: &Path) -> PathBuf {
    if p.is_absolute() {
        p.to_path_buf()
    } else {
        root.join(p)
    }
}

/// The content key of a registered file: the tree's hash for a file the tree holds, else a digest of its bytes on disk.
fn key_of(tree: &Tree, root: &Path, path: &Path) -> Hash {
    let rel = crate::util::rel_slash(&abs_in(root, path), root);
    if let Some(f) = tree.get(&rel) {
        return f.hash;
    }
    std::fs::read(abs_in(root, path)).map(|b| h128(&b)).unwrap_or(0)
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
    let rel = crate::util::rel_slash(&abs_in(root, path), root);
    match tree.get(&rel) {
        Some(f) => Some(f.code().text.clone()),
        None => std::fs::read_to_string(abs_in(root, path)).ok(),
    }
}

/// A registered path (relative to the .dme's directory, or absolute) in one comparable form.
fn norm_in(root: &Path, p: &Path) -> String {
    abs_in(root, p).to_string_lossy().replace('\\', "/").to_ascii_lowercase()
}

/// The macro environment of a full model: the `.dme` and every registered file holding a `#define`, `#undef` or `#include`. Two models
/// of one environment parse a file's text the same way, so a proc body is a function of its file's content (`walk_cache`).
fn environment_of(root: &Path, dme: Hash, paths: &[PathBuf], keys: &[Hash], directive: &[bool]) -> Hash {
    let mut h = blake3::Hasher::new();
    h.update(&dme.to_le_bytes());
    for ((p, k), d) in paths.iter().zip(keys).zip(directive) {
        if *d {
            h.update(norm_in(root, p).as_bytes());
            h.update(&k.to_le_bytes());
        }
    }
    u128::from_le_bytes(h.finalize().as_bytes()[..16].try_into().unwrap())
}

/// [`environment_of`] for a model the store does not describe.
pub fn environment(tree: &Tree, root: &Path, dme_path: &Path, files: &dreammaker::FileList) -> Hash {
    let mut paths = Vec::new();
    files.for_each(|p| paths.push(p.to_path_buf()));
    let (keys, directive) = table(tree, root, &paths);
    environment_of(root, std::fs::read(dme_path).map(|b| h128(&b)).unwrap_or(0), &paths, &keys, &directive)
}

/// Each file's content key and directive flag, on all cores.
fn table(tree: &Tree, root: &Path, paths: &[PathBuf]) -> (Vec<Hash>, Vec<bool>) {
    let rows: Vec<(Hash, bool)> = super::par_map(paths, |p| (key_of(tree, root, p), text_of(tree, root, p).map(|t| mutates_macros(&t)).unwrap_or(true)));
    rows.into_iter().unzip()
}

fn base_id(s: &Base) -> Hash {
    let mut h = blake3::Hasher::new();
    h.update(&s.dme.to_le_bytes());
    for k in &s.keys {
        h.update(&k.to_le_bytes());
    }
    u128::from_le_bytes(h.finalize().as_bytes()[..16].try_into().unwrap())
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
    let (loaded, delta) = std::thread::scope(|s| {
        let d = s.spawn(|| std::fs::read(dir.join(DELTA)).ok().and_then(|b| bincode::deserialize::<Delta>(&b).ok()));
        let l = load(&store);
        (l, d.join().ok().flatten())
    });
    if trace() {
        eprintln!("analyze: model store: read the stored model in {:.1?}", t0.elapsed());
    }
    let reused = match loaded {
        Some(s) if s.engine == engine() && s.dme == dme_hash => update(root, tree, dme_path, s, delta.filter(|d| d.engine == engine())),
        Some(_) => Err("the analyzer or the .dme changed".to_string()),
        None => Err("no stored model".to_string()),
    };
    match reused {
        Ok((p, parsed, patched)) => {
            if trace() {
                eprintln!("analyze: model store: reused the stored model, {} patch(es) applied, {} file(s) re-parsed, in {:.1?}", patched, parsed, t0.elapsed());
            }
            Ok(p)
        }
        Err(why) => {
            if trace() {
                eprintln!("analyze: model store: full parse ({})", why);
            }
            let _ = std::fs::remove_file(dir.join(DELTA));
            let mut parsed = super::parse_source(dme_path, &[], super::Source::Dme(None), true)?;
            let mut paths = Vec::new();
            parsed.files.for_each(|p| paths.push(p.to_path_buf()));
            let (keys, directive) = table(tree, root, &paths);
            let env = environment_of(root, dme_hash, &paths, &keys, &directive);
            parsed.env = Some(env);
            let defines = parsed.defines.take();
            *PENDING_META.lock().unwrap() = Some(Meta { path: store, defines, dme: dme_hash, paths, keys, directive, env, errors: parsed.errors.clone() });
            Ok(parsed)
        }
    }
}

/// The file of slice `i` of the base at `path`.
fn slice_path(path: &Path, generation: u128, i: usize) -> PathBuf {
    path.with_extension(format!("{:032x}.{}.bin", generation, i))
}

/// The macro history file of the base generation `generation`.
fn defines_path(path: &Path, generation: u128) -> PathBuf {
    path.with_extension(format!("{:032x}.defines.bin", generation))
}

fn load_defines(path: &Path, generation: u128) -> Option<std::sync::Arc<dreammaker::preprocessor::StoredDefineHistory>> {
    let b = std::fs::read(defines_path(path, generation)).ok()?;
    bincode::deserialize(&b).ok().map(std::sync::Arc::new)
}

fn load(path: &Path) -> Option<Base> {
    let bytes = std::fs::read(path).ok()?;
    let s: Stored = bincode::deserialize(&bytes).ok()?;
    let names: Vec<PathBuf> = (0..s.slices).map(|i| slice_path(path, s.generation, i)).collect();
    let slices: Vec<Option<Vec<dreammaker::objtree::Type>>> = super::par_map(&names, |p| {
        let b = std::fs::read(p).ok()?;
        let v = bincode::deserialize(&b).ok();
        std::mem::forget(b);
        v
    });
    let slices: Option<Vec<_>> = slices.into_iter().collect();
    Some(Base { engine: s.engine, dme: s.dme, paths: s.paths, keys: s.keys, directive: s.directive, env: s.env, structure: s.structure, errors: s.errors, generation: s.generation, objtree: ObjectTree::from_parts(slices?, s.types) })
}

fn file_list(paths: &[PathBuf]) -> dreammaker::FileList {
    let fl = dreammaker::FileList::default();
    for p in paths {
        fl.register(p);
    }
    fl
}

/// The stored model brought up to this tree: the delta's patches of files whose content they still describe, a fresh patch of every other
/// changed file. Returns the model and how many files were parsed and patched.
fn update(root: &Path, tree: &Tree, dme_path: &Path, mut s: Base, delta: Option<Delta>) -> Result<(Parsed, usize, usize), String> {
    let now: Vec<Hash> = super::par_map(&s.paths, |p| key_of(tree, root, p));
    let changed: Vec<usize> = (0..s.paths.len()).filter(|&i| now[i] != s.keys[i]).collect();
    let files = file_list(&s.paths);
    let id = base_id(&s);
    let mut known: HashMap<u32, (Hash, FilePatch)> = delta.filter(|d| d.base == id).map(|d| d.patches.into_iter().map(|(i, k, p)| (i, (k, p))).collect()).unwrap_or_default();
    let mut to_parse: Vec<usize> = Vec::new();
    let mut patches: Vec<(u32, Hash, FilePatch)> = Vec::new();
    for &i in &changed {
        match known.remove(&(i as u32)) {
            Some((k, p)) if k == now[i] => patches.push((i as u32, k, p)),
            _ => to_parse.push(i),
        }
    }
    if to_parse.len() > MAX_SPLICED {
        return Err(format!("{} files changed", to_parse.len()));
    }
    let dme_norm = norm_in(root, dme_path);
    for &i in &to_parse {
        let p = &s.paths[i];
        let rel = crate::util::rel_slash(&abs_in(root, p), root);
        if norm_in(root, p) == dme_norm || !rel.ends_with(".dm") || rel.starts_with("code/__defines/") {
            return Err(format!("{} changed", rel));
        }
        let Some(text) = text_of(tree, root, p) else { return Err(format!("{} unreadable", rel)) };
        // One that held a directive before changed what later files saw; one that holds one now would.
        if mutates_macros(&text) || s.directive.get(i).copied().unwrap_or(true) {
            return Err(format!("{} holds a preprocessor directive", rel));
        }
    }
    // The patched files hold no directive either (checked when their patch was made), so the base's flags are the tree's.
    let parsed = to_parse.len();
    if !to_parse.is_empty() {
        let hist = load_defines(&crate::incr::dir().ok_or("no cache dir")?.join(FILE), s.generation).ok_or("no stored macro history")?;
        let jobs: Vec<(usize, Option<dreammaker::FileId>)> = to_parse.iter().map(|&i| (i, files.get_id(&s.paths[i]))).collect();
        let made: Vec<Result<(u32, Hash, FilePatch), String>> = super::par_map(&jobs, |&(i, fid)| {
            let target = &s.paths[i];
            let fid = fid.ok_or("no file id")?;
            // The file alone, from the macro state at its start, then the file after it (the parser places the end of the file's last
            // statement at the next token, which must be what follows it in the whole tree).
            let mut read: Vec<(PathBuf, PathBuf)> = vec![(target.clone(), abs_in(root, target))];
            if let Some(next) = s.paths.get(i + 1) {
                read.push((next.clone(), abs_in(root, next)));
            }
            let tp = std::time::Instant::now();
            let partial = super::parse_source(dme_path, &s.paths, super::Source::Alone(hist.clone(), read), false)?;
            if partial.files.get_id(target) != Some(fid) {
                return Err("the partial parse named the file differently".to_string());
            }
            if trace() {
                eprintln!("analyze: model store: parsed {} alone in {:.1?} ({} error(s) of the partial parse)", crate::util::rel_slash(&abs_in(root, target), root), tp.elapsed(), partial.errors.len());
            }
            Ok((i as u32, now[i], partial.objtree.file_patch(fid)))
        });
        for m in made {
            patches.push(m?);
        }
    }
    let patched = patches.len();
    for (i, _, p) in &patches {
        let target = &s.paths[*i as usize];
        let fid = files.get_id(target).ok_or("no file id")?;
        s.objtree.splice_patch(fid, p).map_err(|e| format!("{}: {}", crate::util::rel_slash(&abs_in(root, target), root), e))?;
    }
    if std::env::var_os("DQ_MODEL_VERIFY").is_some() && patched > 0 {
        let full = super::parse_dme(dme_path, &[], None)?;
        let a = bincode::serialize(&s.objtree).map_err(|e| e.to_string())?;
        let b = bincode::serialize(&full.objtree).map_err(|e| e.to_string())?;
        if a != b {
            if let Some(d) = std::env::var_os("DQ_MODEL_VERIFY_DUMP") {
                let d = PathBuf::from(d);
                let _ = std::fs::write(d.join("spliced.bin"), &a);
                let _ = std::fs::write(d.join("full.bin"), &b);
            }
            eprintln!("analyze: model store: VERIFY FAILED: the updated model differs from a full parse ({} vs {} bytes); using the full parse", a.len(), b.len());
            return Err("verify failed".to_string());
        }
        eprintln!("analyze: model store: verify ok");
    }
    let env = s.env;
    if patched > REBASE_AT {
        // Fold the patches into a new base (written on a side thread once the model is in the memo).
        let (keys, directive) = (now, s.directive.clone());
        let dir = crate::incr::dir().ok_or("no cache dir")?;
        let _ = std::fs::remove_file(dir.join(DELTA));
        let defines = load_defines(&dir.join(FILE), s.generation).map(|d| (*d).clone());
        *PENDING_META.lock().unwrap() = Some(Meta { path: dir.join(FILE), defines, dme: s.dme, paths: s.paths.clone(), keys, directive, env, errors: s.errors.clone() });
    } else if parsed > 0 || patched != changed.len() || !known.is_empty() {
        // The delta now describes exactly the files that differ from the base (a file back at its base content needs no patch).
        if let Some(dir) = crate::incr::dir() {
            let d = Delta { engine: engine(), base: id, patches };
            if let Ok(bytes) = bincode::serialize(&d) {
                let path = dir.join(DELTA);
                let tmp = path.with_extension(format!("tmp{}", std::process::id()));
                if std::fs::write(&tmp, &bytes).is_ok() && std::fs::rename(&tmp, &path).is_err() {
                    let _ = std::fs::remove_file(&tmp);
                }
                if trace() {
                    eprintln!("analyze: model store: wrote the delta ({} file(s), {} KB)", d.patches.len(), bytes.len() >> 10);
                }
            }
            std::mem::forget(d);
        }
    } else {
        std::mem::forget(patches);
    }
    let structure = s.structure;
    Ok((Parsed { objtree: s.objtree, files, errors: s.errors, env: Some(env), structure: Some(structure), defines: None }, parsed, patched))
}

/// Called once the model is in the memo: writes a new base on a side thread when this run parsed the tree or folded the delta.
pub fn save_later(handle: std::sync::Arc<super::SemBox>) {
    let Some(meta) = PENDING_META.lock().unwrap().take() else { return };
    let t = std::thread::Builder::new().name("model-store".into()).spawn(move || {
        let Some(sem) = handle.sem.as_ref() else { return };
        let t0 = std::time::Instant::now();
        let (slices, types) = sem.objtree.parts(16);
        // The slices first, then the header naming them: a reader that sees the new header finds its slices (a stale header with new
        // slices fails to decode or names a different engine and is a full parse).
        let generation = h128(format!("{}|{:?}", std::process::id(), std::time::SystemTime::now()).as_bytes());
        let idx: Vec<usize> = (0..slices.len()).collect();
        let ok: Vec<bool> = super::par_map(&idx, |&i| {
            let Ok(b) = bincode::serialize(slices[i]) else { return false };
            let p = slice_path(&meta.path, generation, i);
            let tmp = p.with_extension(format!("tmp{}", std::process::id()));
            let done = std::fs::write(&tmp, &b).is_ok() && std::fs::rename(&tmp, &p).is_ok();
            std::mem::forget(b);
            done
        });
        if ok.iter().any(|o| !o) {
            return;
        }
        if let Some(d) = &meta.defines {
            let p = defines_path(&meta.path, generation);
            let tmp = p.with_extension(format!("tmp{}", std::process::id()));
            let done = bincode::serialize(d).map(|b| std::fs::write(&tmp, &b).is_ok()).unwrap_or(false) && std::fs::rename(&tmp, &p).is_ok();
            if !done {
                return;
            }
        }
        let r = StoredRef { engine: &engine(), dme: meta.dme, paths: &meta.paths, keys: &meta.keys, directive: &meta.directive, env: meta.env, structure: sem.structure_digest(), errors: &meta.errors, slices: slices.len(), generation, types };
        let Ok(bytes) = bincode::serialize(&r) else { return };
        let tmp = meta.path.with_extension(format!("tmp{}", std::process::id()));
        if std::fs::write(&tmp, &bytes).is_ok() && std::fs::rename(&tmp, &meta.path).is_err() {
            let _ = std::fs::remove_file(&tmp);
        }
        // The slices of older generations (a reader still holding an older header already read them, or reads them as a miss).
        let keep = format!("{:032x}", generation);
        if let (Some(dir), Some(stem)) = (meta.path.parent(), meta.path.file_stem().and_then(|s| s.to_str())) {
            if let Ok(rd) = std::fs::read_dir(dir) {
                for e in rd.filter_map(|e| e.ok()) {
                    let name = e.file_name().to_string_lossy().to_string();
                    if name.starts_with(&format!("{}.", stem)) && name.ends_with(".bin") && name.len() > stem.len() + 33 && !name.contains(&keep) {
                        let _ = std::fs::remove_file(e.path());
                    }
                }
            }
        }
        if trace() {
            eprintln!("analyze: model store: wrote {} MB in {:.1?}", bytes.len() >> 20, t0.elapsed());
        }
        std::mem::forget(bytes);
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
