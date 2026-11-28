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
//!
//! A process that serves many runs (the dmbc daemon) keeps the model of the last run decoded ([`Resident`]): the next run of the same store
//! starts from it and splices only the files that changed since that run (a patch the delta already holds for a file's content, else a
//! parse of the file alone), while the delta it writes stays relative to the base on disk, so a new process reads a consistent store. A run
//! that parsed the whole tree or folded the delta into a new base keeps nothing (the next run reads the new base).

use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::Mutex;

use dreammaker::objtree::{FilePatch, ObjectTree};
use serde::{Deserialize, Serialize};

use crate::tree::{Hash, Tree};

const FILE: &str = "sem-model.bin";
const DELTA: &str = "sem-model-delta.bin";
/// More files to parse than this and the full parse is cheaper than the partial ones (each is about 55 ms on one core, spread over all of them; the
/// full parse is 8-12 s, and loaded it is several times that: a merge batch of dozens of files must not cost it).
const MAX_SPLICED: usize = 128;
/// A delta of more files than this is folded into a new base.
const REBASE_AT: usize = 48;
/// ... or when the patches are about this large (an estimate: 2 KB a proc).
const REBASE_BYTES: usize = 12 << 20;

/// A checker parse's diagnostics (`super::parse_source`'s `checker`), in the order the standalone checker prints them.
pub struct CheckerDiagnostics {
    /// Preprocessor and parser, in stream order.
    pub stream: Vec<dreammaker::DMError>,
    /// The parser's "parsed N/M proc bodies" line, printed after `stream`.
    pub summary: Option<String>,
    /// What finishing the object tree registered.
    pub finish: Vec<dreammaker::DMError>,
}

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
    /// A checker parse's diagnostics, every severity, in source order (`parse_source`'s `checker`); never stored.
    pub raw: Option<CheckerDiagnostics>,
    /// The parser stopped on a fatal error.
    pub fatal: bool,
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

/// The last run's model, kept decoded for the next run of the same store (hosted only): the model as that run used it, the content
/// key of every file it reflects, and the base on disk the delta is relative to (its id, its keys, the patch of every file that differs
/// from it).
struct Resident {
    store: PathBuf,
    base: Base,
    disk_id: Hash,
    disk_keys: Vec<Hash>,
    disk_patches: HashMap<u32, (Hash, FilePatch)>,
}

/// What a run's `update` leaves for [`keep_resident`]: the model's table (its objtree is the run's, taken back at the end).
struct ResidentMeta {
    store: PathBuf,
    engine: String,
    dme: Hash,
    paths: Vec<PathBuf>,
    keys: Vec<Hash>,
    directive: Vec<bool>,
    env: Hash,
    structure: u128,
    errors: Vec<String>,
    generation: u128,
    disk_id: Hash,
    disk_keys: Vec<Hash>,
    disk_patches: HashMap<u32, (Hash, FilePatch)>,
}

static RESIDENT: Mutex<Option<Resident>> = Mutex::new(None);
static PENDING_RESIDENT: Mutex<Option<ResidentMeta>> = Mutex::new(None);
/// The run's model, for [`keep_resident`] (set by [`save_later`]).
static RUN_MODEL: Mutex<Option<std::sync::Arc<super::SemBox>>> = Mutex::new(None);
/// The base and delta a warm worker read before its request (`prewarm`), for `obtain` to use instead of reading them.
static PREWARMED: Mutex<Option<(PathBuf, Option<Base>, Option<Delta>)>> = Mutex::new(None);
static WRITER: Mutex<Option<std::thread::JoinHandle<()>>> = Mutex::new(None);

pub(crate) fn trace() -> bool {
    dq_hostio::var_os("DQ_ANALYZE_TRACE").is_some()
}

fn enabled() -> bool {
    !matches!(dq_hostio::var("DQ_MODEL_STORE").as_deref(), Ok("off") | Ok("0")) && crate::incr::stamp().is_some()
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

/// Whether a stored model exists for this worktree (a warm run: most of the tree is known).
pub fn stored(_root: &Path) -> bool {
    enabled() && crate::incr::dir().map(|d| d.join(FILE).exists()).unwrap_or(false)
}

/// The tree stores proc bodies encoded and decodes one when something reads it (`dreammaker::objtree::LazyCode`): bincode both ways.
pub fn ensure_codec() {
    fn enc(c: &Option<dreammaker::ast::Block>) -> Vec<u8> {
        bincode::serialize(c).unwrap_or_default()
    }
    fn dec(b: &[u8]) -> Option<dreammaker::ast::Block> {
        bincode::deserialize(b).expect("a stored proc body decodes (the store is stamped with the analyzer build)")
    }
    dreammaker::objtree::set_code_codec(enc, dec);
}

/// The model of the real `.dme`: the stored one brought up to date, or a full parse.
/// Reads the stored model and delta now and decodes every proc body (a warm worker does this before its request: `crate::warm`).
pub fn prewarm() {
    ensure_codec();
    if !enabled() {
        return;
    }
    let Some(dir) = crate::incr::dir() else { return };
    if resident_for(&dir) {
        return;
    }
    let store = dir.join(FILE);
    let (loaded, delta) = std::thread::scope(|s| {
        let d = s.spawn(|| std::fs::read(dir.join(DELTA)).ok().and_then(|b| bincode::deserialize::<Delta>(&b).ok()));
        let l = load(&store);
        (l, d.join().ok().flatten())
    });
    if let Some(base) = &loaded {
        let mut bodies: Vec<&dreammaker::objtree::ProcValue> = Vec::new();
        for ty in base.objtree.iter_types() {
            for (_, tp) in ty.get().procs.iter() {
                bodies.extend(tp.value.iter());
            }
        }
        super::par_map(&bodies, |v| {
            let _ = v.code.as_ref();
        });
    }
    *PREWARMED.lock().unwrap() = Some((store, loaded, delta));
}

pub fn obtain(root: &Path, tree: &Tree, dme_path: &Path) -> Result<Parsed, String> {
    ensure_codec();
    // A model from another front end (`DQ_ANALYZE_PARSE=dmbc`) is built whole each run: the store splices dreammaker parses.
    if let Some(parsed) = super::provided_parse(dme_path, false) {
        return parsed;
    }
    if !enabled() {
        return super::parse_dme(dme_path, &[], None);
    }
    let Some(dir) = crate::incr::dir() else { return super::parse_dme(dme_path, &[], None) };
    let store = dir.join(FILE);
    let dme_hash = std::fs::read(dme_path).map(|b| h128(&b)).unwrap_or(0);
    let t0 = std::time::Instant::now();
    // The last run's model, kept in this process: brought up to date by the files that changed since that run.
    let resident = RESIDENT.lock().unwrap_or_else(|e| e.into_inner()).take().filter(|r| r.store == store && r.base.engine == engine() && r.base.dme == dme_hash);
    if let Some(r) = resident {
        let disk = Disk { id: r.disk_id, keys: r.disk_keys, known: r.disk_patches };
        match update(root, tree, dme_path, r.base, disk) {
            Ok((p, parsed, patched)) => {
                if trace() {
                    eprintln!("analyze: model store: brought the model kept in memory up to date, {} patch(es) applied, {} file(s) re-parsed, in {:.1?}", patched, parsed, t0.elapsed());
                }
                return Ok(p);
            }
            Err(why) => {
                if trace() {
                    eprintln!("analyze: model store: the model kept in memory cannot be updated ({}); reading the store", why);
                }
            }
        }
    }
    let prewarmed = PREWARMED.lock().unwrap().take().filter(|(p, _, _)| *p == store);
    let (loaded, delta) = match prewarmed {
        Some((_, l, d)) => (l, d),
        None => std::thread::scope(|s| {
            let d = s.spawn(|| std::fs::read(dir.join(DELTA)).ok().and_then(|b| bincode::deserialize::<Delta>(&b).ok()));
            let l = load(&store);
            (l, d.join().ok().flatten())
        }),
    };
    if trace() {
        eprintln!("analyze: model store: read the stored model in {:.1?}", t0.elapsed());
    }
    let reused = match loaded {
        Some(s) if s.engine == engine() && s.dme == dme_hash => {
            let id = base_id(&s);
            let known = delta.filter(|d| d.engine == engine() && d.base == id).map(|d| d.patches.into_iter().map(|(i, k, p)| (i, (k, p))).collect()).unwrap_or_default();
            let disk = Disk { id, keys: s.keys.clone(), known };
            update(root, tree, dme_path, s, disk)
        }
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
            let mut parsed = super::parse_source(dme_path, &[], super::Source::Dme(None), true, None)?;
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
        dq_hostio::discard(b);
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

/// The first `.dm` file the `.dme` includes that exists on disk but is not in `paths` (the files the stored model was parsed from).
fn appeared_include(root: &Path, dme_path: &Path, paths: &[PathBuf]) -> Option<String> {
    let text = std::fs::read_to_string(dme_path).ok()?;
    let known: std::collections::HashSet<String> = paths.iter().map(|p| norm_in(root, p)).collect();
    let base = dme_path.parent().unwrap_or(root);
    for line in text.lines() {
        let Some(rest) = line.trim_start().strip_prefix("#include") else { continue };
        let Some(name) = rest.trim().strip_prefix('"').and_then(|r| r.split('"').next()) else { continue };
        if !name.to_ascii_lowercase().ends_with(".dm") {
            continue;
        }
        let rel = PathBuf::from(name.replace('\\', "/"));
        if known.contains(&norm_in(root, &rel)) || known.contains(&norm_in(root, &base.join(&rel))) {
            continue;
        }
        if abs_in(base, &rel).is_file() {
            return Some(name.replace('\\', "/"));
        }
    }
    None
}

/// The base on disk a model's delta is relative to: its id, the content key of each file in it, and the patch of each file that differs
/// from it (as the delta on disk holds them).
struct Disk {
    id: Hash,
    keys: Vec<Hash>,
    known: HashMap<u32, (Hash, FilePatch)>,
}

/// A model brought up to this tree. `s` is the model to start from (the base on disk, or the last run's model kept in memory) with the
/// content key of every file it reflects; `disk` is the base on disk. A file whose content differs from what `s` reflects gets the
/// delta's patch for its content, else a fresh patch of the file parsed alone. The delta written stays relative to `disk`. Returns the
/// model and how many files were parsed and patched.
fn update(root: &Path, tree: &Tree, dme_path: &Path, mut s: Base, disk: Disk) -> Result<(Parsed, usize, usize), String> {
    // The stored file table lists only the files the preprocessor registered. A `.dm` the `.dme` includes that was missing when the model
    // was parsed (a generated file `analyze gen` had not written yet) is in no table, so comparing keys cannot see it appear: the model
    // would be reused without it. Any included `.dm` that exists now and is not in the table is a full parse.
    if let Some(appeared) = appeared_include(root, dme_path, &s.paths) {
        return Err(format!("{} appeared", appeared));
    }
    let now: Vec<Hash> = super::par_map(&s.paths, |p| key_of(tree, root, p));
    if disk.keys.len() != s.paths.len() {
        return Err("the base on disk has another file table".to_string());
    }
    // What the model must change (its content differs from what `s` reflects) and what the delta must hold (it differs from the base).
    let changed: Vec<usize> = (0..s.paths.len()).filter(|&i| now[i] != s.keys[i]).collect();
    let off_base: Vec<usize> = (0..s.paths.len()).filter(|&i| now[i] != disk.keys[i]).collect();
    let files = file_list(&s.paths);
    let id = disk.id;
    let mut known = disk.known;
    let before: std::collections::BTreeSet<(u32, Hash)> = known.iter().map(|(i, (k, _))| (*i, *k)).collect();
    let mut to_parse: Vec<usize> = Vec::new();
    // Patches to splice onto `s`, and the delta's patches of the files that differ from the base but not from `s` (kept as they are).
    let mut patches: Vec<(u32, Hash, FilePatch)> = Vec::new();
    let mut kept: Vec<(u32, Hash, FilePatch)> = Vec::new();
    let changed_set: std::collections::HashSet<usize> = changed.iter().copied().collect();
    for &i in &changed {
        match known.remove(&(i as u32)) {
            Some((k, p)) if k == now[i] => patches.push((i as u32, k, p)),
            _ => to_parse.push(i),
        }
    }
    for &i in &off_base {
        if changed_set.contains(&i) {
            continue;
        }
        match known.remove(&(i as u32)) {
            Some((k, p)) if k == now[i] => kept.push((i as u32, k, p)),
            _ => return Err(format!("no patch for {} in the delta", crate::util::rel_slash(&abs_in(root, &s.paths[i]), root))),
        }
    }
    if to_parse.len() > MAX_SPLICED {
        return Err(format!("{} files changed", to_parse.len()));
    }
    let dme_norm = norm_in(root, dme_path);
    for &i in &to_parse {
        let p = &s.paths[i];
        let rel = crate::util::rel_slash(&abs_in(root, p), root);
        if norm_in(root, p) == dme_norm || !rel.ends_with(".dm") || crate::scopes::is_defines(&rel) {
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
            let partial = super::parse_source(dme_path, &s.paths, super::Source::Alone(hist.clone(), read), false, None)?;
            if partial.files.get_id(target) != Some(fid) {
                return Err("the partial parse named the file differently".to_string());
            }
            if trace() {
                eprintln!("analyze: model store: parsed {} alone in {:.1?} ({} error(s) of the partial parse)", crate::util::rel_slash(&abs_in(root, target), root), tp.elapsed(), partial.errors.len());
                for e in partial.errors.iter().take(3) {
                    eprintln!("analyze: model store:   {}", e);
                }
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
    // The delta relative to the base: what this run spliced for files that differ from the base, and what it kept.
    let mut patches: Vec<(u32, Hash, FilePatch)> = patches.into_iter().filter(|(i, k, _)| disk.keys[*i as usize] != *k).collect();
    patches.extend(kept);
    patches.sort_by_key(|(i, _, _)| *i);
    if dq_hostio::var_os("DQ_MODEL_VERIFY").is_some() && patched > 0 {
        let full = super::parse_dme(dme_path, &[], None)?;
        let a = bincode::serialize(&s.objtree).map_err(|e| e.to_string())?;
        let b = bincode::serialize(&full.objtree).map_err(|e| e.to_string())?;
        if a != b {
            if let Some(d) = dq_hostio::var_os("DQ_MODEL_VERIFY_DUMP") {
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
    // Fold into a new base past REBASE_AT files or REBASE_BYTES of patches (a big file's patch is most of a delta's read time).
    let delta_bytes: usize = patches.iter().map(|(_, _, p)| p.types.iter().map(|t| t.procs.len() * 2048 + t.vals.len() * 256).sum::<usize>()).sum();
    let rebase = patches.len() > REBASE_AT || delta_bytes > REBASE_BYTES;
    let delta_changed = before != patches.iter().map(|(i, k, _)| (*i, *k)).collect::<std::collections::BTreeSet<_>>();
    if !rebase && crate::incr::hosted() {
        let disk_patches: HashMap<u32, (Hash, FilePatch)> = patches.iter().map(|(i, k, p)| (*i, (*k, p.clone()))).collect();
        *PENDING_RESIDENT.lock().unwrap_or_else(|e| e.into_inner()) = Some(ResidentMeta {
            store: crate::incr::dir().map(|d| d.join(FILE)).unwrap_or_default(),
            engine: s.engine.clone(),
            dme: s.dme,
            paths: s.paths.clone(),
            keys: now.clone(),
            directive: s.directive.clone(),
            env,
            structure: s.structure,
            errors: s.errors.clone(),
            generation: s.generation,
            disk_id: id,
            disk_keys: disk.keys.clone(),
            disk_patches,
        });
    }
    if rebase {
        // Fold the patches into a new base (written on a side thread once the model is in the memo).
        let (keys, directive) = (now, s.directive.clone());
        let dir = crate::incr::dir().ok_or("no cache dir")?;
        let _ = std::fs::remove_file(dir.join(DELTA));
        let defines = load_defines(&dir.join(FILE), s.generation).map(|d| (*d).clone());
        *PENDING_META.lock().unwrap() = Some(Meta { path: dir.join(FILE), defines, dme: s.dme, paths: s.paths.clone(), keys, directive, env, errors: s.errors.clone() });
    } else if delta_changed {
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
            dq_hostio::discard(d);
        }
    } else {
        dq_hostio::discard(patches);
    }
    let structure = s.structure;
    Ok((Parsed { objtree: s.objtree, files, errors: s.errors, env: Some(env), structure: Some(structure), defines: None, raw: None, fatal: false }, parsed, patched))
}

/// Called once the model is in the memo: writes a new base on a side thread when this run parsed the tree or folded the delta, and
/// remembers the model for [`keep_resident`].
pub fn save_later(handle: std::sync::Arc<super::SemBox>) {
    if PENDING_RESIDENT.lock().unwrap_or_else(|e| e.into_inner()).is_some() {
        *RUN_MODEL.lock().unwrap_or_else(|e| e.into_inner()) = Some(handle.clone());
    }
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
            dq_hostio::discard(b);
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
        dq_hostio::discard(bytes);
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

/// The end of a hosted run: keeps the run's model decoded for the next run of the same store, when this run brought a stored model up to
/// date (nothing else may still hold the model then: the run is over).
pub fn keep_resident() {
    let meta = PENDING_RESIDENT.lock().unwrap_or_else(|e| e.into_inner()).take();
    let handle = RUN_MODEL.lock().unwrap_or_else(|e| e.into_inner()).take();
    let (Some(meta), Some(handle)) = (meta, handle) else { return };
    let t0 = std::time::Instant::now();
    let Some(objtree) = super::SemBox::into_objtree(handle) else {
        if trace() {
            eprintln!("analyze: model store: the run's model is still shared; not kept in memory");
        }
        return;
    };
    let base = Base {
        engine: meta.engine,
        dme: meta.dme,
        paths: meta.paths,
        keys: meta.keys,
        directive: meta.directive,
        env: meta.env,
        structure: meta.structure,
        errors: meta.errors,
        generation: meta.generation,
        objtree,
    };
    *RESIDENT.lock().unwrap_or_else(|e| e.into_inner()) =
        Some(Resident { store: meta.store, base, disk_id: meta.disk_id, disk_keys: meta.disk_keys, disk_patches: meta.disk_patches });
    if trace() {
        eprintln!("analyze: model store: kept the model in memory in {:.1?}", t0.elapsed());
    }
}

/// Whether a model is kept in memory for the store at `dir`: the read-ahead then has nothing to read.
pub fn resident_for(dir: &Path) -> bool {
    RESIDENT.lock().unwrap_or_else(|e| e.into_inner()).as_ref().is_some_and(|r| r.store == dir.join(FILE))
}

/// Drops the prewarmed model and the one kept in memory (a hosting process sheds them when idle or short of memory).
pub fn shed() {
    *PREWARMED.lock().unwrap_or_else(|e| e.into_inner()) = None;
    *RESIDENT.lock().unwrap_or_else(|e| e.into_inner()) = None;
}

/// Run state for `crate::host::reset_run_state`: the store writer joined (it holds the run's model) and the pending meta. The
/// prewarmed model stays.
pub(crate) fn reset() {
    if let Some(t) = WRITER.lock().unwrap_or_else(|e| e.into_inner()).take() {
        let _ = t.join();
    }
    *PENDING_META.lock().unwrap_or_else(|e| e.into_inner()) = None;
    *PENDING_RESIDENT.lock().unwrap_or_else(|e| e.into_inner()) = None;
    *RUN_MODEL.lock().unwrap_or_else(|e| e.into_inner()) = None;
}
