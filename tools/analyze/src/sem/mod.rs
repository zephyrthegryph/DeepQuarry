//! The semantic layer: type, proc and var resolution on the dreammaker backend, and the queries
//! built on it (generated reads, key resolution, handler checks, the generator API).
//!
//! `Sem` owns the parsed `ObjectTree` for one tree. It is built once per run (`Cx::sem()`,
//! memoized) and shared by every semantic lint and generator. The front end is the dreammaker
//! parser behind [`crate::frontend`]'s trait boundary: nothing outside this module (and
//! `frontend/`) names a dreammaker type, so the incremental compiler's analysis API can replace it
//! by implementing the same small surface (`ty`, `var_decl`, `proc_ref`, `proc_body`).
//!
//! Declarations that expand to nothing in DM (`CAPABILITIES(...)`, `STAT(...)`, `READS_AS(...)`,
//! `READS_FROM(...)`, ...) are read from source text by [`decls`]; everything that needs real
//! structure (what a proc body reads, what a type declares) comes from the AST here.

pub mod actor_tests;
pub mod ast;
pub mod checks;
pub mod closure;
pub mod ctor_args;
pub mod handlers;
pub mod hooks;
pub mod cli;
pub mod decls;
pub mod globals;
pub mod graph;
pub mod layering;
pub mod keys;
pub mod gen;
pub mod incremental;
pub mod model_store;
pub mod walk_cache;
pub mod body_facts;
pub mod oracle;
pub mod procs;
pub mod reads;

use std::collections::HashMap;
use std::path::{Path, PathBuf};

use dreammaker::objtree::{ObjectTree, ProcRef, TypeRef};
use dreammaker::ast::{Block, Parameter, VarTypeFlags};
use dreammaker::Location;

use crate::tree::{Tree, CODE_DM};

/// A var's declaration as the semantic layer reports it.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct VarSig {
    /// Declared type path (`/obj/item/cell`), `""` when untyped.
    pub declared: String,
    pub is_static: bool,
    pub is_const: bool,
    pub is_tmp: bool,
    pub file: String,
    pub line: u32,
}

impl VarSig {
    /// An object-typed var: a declared type that is not a builtin value type.
    pub fn is_object(&self) -> bool {
        is_object_type(&self.declared)
    }

    pub fn is_list(&self) -> bool {
        self.declared == "/list" || self.declared.starts_with("/list/")
    }
}

const VALUE_TYPES: &[&str] = &["/list", "/text", "/num", "/string", "/icon", "/sound", "/mutable_appearance", "/image", "/matrix", "/regex", "/savefile", "/client", "/world", "/exception", "/path", "/color", "/alist"];

/// True for a declared type that names a game object (anything but the value types above or
/// `""`). `/image` and the other appearance types are values for reads purposes.
pub fn is_object_type(declared: &str) -> bool {
    !declared.is_empty() && !VALUE_TYPES.iter().any(|v| declared == *v || declared.starts_with(&format!("{}/", v)))
}

/// A proc body with the facts the walkers need.
pub struct ProcBody<'a> {
    pub owner: String,
    pub name: String,
    pub params: &'a [Parameter],
    pub code: Option<&'a Block>,
    pub file: String,
    pub line: u32,
    pub builtin: bool,
}

pub struct Sem {
    pub objtree: ObjectTree,
    /// `FileId` -> repo-relative path (built from the locations the tree carries).
    files: HashMap<dreammaker::FileId, String>,
    pub root: PathBuf,
    /// Parse errors the dreammaker front end raised (not findings: informational).
    pub errors: Vec<String>,
    /// file -> sorted (line, owner type path) of every var/proc definition, for locating the owner
    /// of a text marker by its line.
    def_index: HashMap<String, Vec<(u32, String, String)>>,
    /// Files whose definitions (locations, bodies) the analysis consulted: the footprint a cached
    /// result depends on (see `sem::incremental`). Every file-attributed answer goes through
    /// [`Sem::rel`] or the def index, which record here.
    /// type path -> repo-relative file of the type's location.
    type_loc: HashMap<String, String>,
    pub(crate) layering_type_defs: HashMap<String, Vec<String>>,
    pub(crate) layering_owner_defs: HashMap<String, Vec<String>>,
    touched: std::sync::Mutex<std::collections::HashSet<dreammaker::FileId>>,
    touched_rel: std::sync::Mutex<std::collections::HashSet<String>>,
    /// Built from the real `.dme` (not a partial or fixture model): its walks may be kept between runs (`walk_cache`).
    full: bool,
    /// The macro environment ([`model_store::environment`]) and each file's content key: a proc body digests as its file's key.
    env_key: u128,
    file_keys: HashMap<dreammaker::FileId, u128>,
    structure: std::sync::OnceLock<u128>,
    globals: std::sync::OnceLock<globals::GlobalIndex>,
    writes: std::sync::OnceLock<reads::WriteIndex>,
}

impl Sem {
    /// Parses the environment. A tree with a non-empty `deepquarry.dme` uses it (include order
    /// matters for define visibility); anything else (a fixture) gets a synthesized `.dme` that
    /// includes every `code/**/*.dm` in path order.
    pub fn build(root: &Path, tree: &Tree) -> Result<Sem, String> {
        Sem::build_with(root, tree, None)
    }

    /// A model of only `files` (repo-relative) plus every `code/__defines/**` file for macros: the
    /// cheap model per-proc checks use when only a few files matter. Types the other files
    /// declare are absent.
    pub fn build_partial(root: &Path, tree: &Tree, files: &[String]) -> Result<Sem, String> {
        Sem::build_with(root, tree, Some(files))
    }

    fn build_with(root: &Path, tree: &Tree, only: Option<&[String]>) -> Result<Sem, String> {
        // The synthesized .dme lives in a temp dir, so every path it names must be absolute.
        let abs_root: PathBuf = if root.is_absolute() { root.to_path_buf() } else { std::env::current_dir().map_err(|e| e.to_string())?.join(root) };
        let root = abs_root.as_path();
        let dme = root.join("deepquarry.dme");
        let real = only.is_none() && std::fs::read_to_string(&dme).map(|t| t.contains("#include")).unwrap_or(false);
        let (dme_path, _keep) = if real {
            (dme, None)
        } else {
            let dir = tempfile_dir(root);
            let mut text = String::new();
            let mut list: Vec<String> = Vec::new();
            match only {
                None => list.extend(tree.select(&CODE_DM).iter().map(|f| f.rel.clone())),
                Some(files) => {
                    list.extend(tree.select(&CODE_DM).iter().filter(|f| f.rel.starts_with("code/__defines/")).map(|f| f.rel.clone()));
                    for f in files {
                        if !list.contains(f) {
                            list.push(f.clone());
                        }
                    }
                }
            }
            for rel in &list {
                let abs = root.join(rel);
                text.push_str(&format!("#include \"{}\"\n", abs.display().to_string().replace('\\', "/")));
            }
            let p = dir.join("synth.dme");
            std::fs::write(&p, text).map_err(|e| format!("synth dme: {}", e))?;
            (p, Some(dir))
        };
        let t_build = std::time::Instant::now();
        let parsed = if real { model_store::obtain(root, tree, &dme_path)? } else { parse_dme(&dme_path, &[], None)? };
        let model_store::Parsed { objtree, files: file_list, errors, env, structure, .. } = parsed;
        let env_key = if real { env.unwrap_or_else(|| model_store::environment(tree, root, &dme_path, &file_list)) } else { 0 };
        let t_parsed = t_build.elapsed();
        let mut files: HashMap<dreammaker::FileId, String> = HashMap::new();
        let mut def_index: HashMap<String, Vec<(u32, String, String)>> = HashMap::new();
        let rel_of = |loc: Location, files: &mut HashMap<dreammaker::FileId, String>| -> Option<String> {
            if loc.is_builtins() {
                return None;
            }
            let r = files
                .entry(loc.file)
                .or_insert_with(|| crate::util::rel_slash(&file_list.get_path(loc.file).to_path_buf(), root))
                .clone();
            Some(r)
        };
        let mut type_loc: HashMap<String, String> = HashMap::new();
        for ty in objtree.iter_types() {
            let t = ty.get();
            let path = if t.path.is_empty() { "/".to_string() } else { t.path.clone() };
            if let Some(r) = rel_of(t.location, &mut files) {
                type_loc.insert(path.clone(), r);
            }
            for (_n, v) in &t.vars {
                if let Some(d) = &v.declaration {
                    if let Some(r) = rel_of(d.location, &mut files) {
                        def_index.entry(r).or_default().push((d.location.line, path.clone(), _n.clone()));
                    }
                }
            }
            for (_n, p) in &t.procs {
                for value in &p.value {
                    if let Some(r) = rel_of(value.location, &mut files) {
                        def_index.entry(r).or_default().push((value.location.line, path.clone(), _n.clone()));
                    }
                }
            }
        }
        for v in def_index.values_mut() {
            v.sort();
        }
        if let Some(dir) = _keep {
            let _ = std::fs::remove_dir_all(dir);
        }
        let t_indexed = t_build.elapsed();
        let mut layering_type_defs: HashMap<String, Vec<String>> = HashMap::new();
        let mut layering_owner_defs: HashMap<String, Vec<String>> = HashMap::new();
        let capability_type = regex::Regex::new(r"^CAPABILITY_TYPE\s*\(\s*[^,]+,\s*[^,]+,\s*(/[A-Za-z_][\w/]*)").unwrap();
        let capability_def = regex::Regex::new(r"^CAPABILITY_DEF\s*\(\s*([A-Za-z_]\w*)\s*,").unwrap();
        // What a file's text says (cached by content, `incr::facts`), replayed against this model in file order (the lists keep the order a
        // sequential scan gave them): only an edited file is read and scanned again.
        let code_files = tree.select(&CODE_DM);
        let events: Vec<Vec<LayerEvent>> = crate::incr::facts("sem-layering", &code_files, |file| layering_events(file.code().text.as_str(), &capability_type, &capability_def));
        let scanned: Vec<(Vec<String>, Vec<String>)> = par_map(&events, |evs| {
            let mut owners: Vec<String> = Vec::new();
            let mut types: Vec<String> = Vec::new();
            let mut parents: Vec<(usize, String)> = Vec::new();
            for e in evs {
                match e {
                    LayerEvent::Owner(owner) => {
                        if objtree.find(owner).is_some() {
                            owners.push(owner.clone());
                        }
                    }
                    LayerEvent::Type(t) => types.push(t.clone()),
                    LayerEvent::Indent(indent) => {
                        while parents.last().is_some_and(|(n, _)| *n >= *indent as usize) { parents.pop(); }
                    }
                    LayerEvent::Header(indent, header) => {
                        let path = if header.starts_with('/') { header.clone() }
                            else if let Some((_, parent)) = parents.last() { format!("{}/{}", parent, header) }
                            else { continue; };
                        if path.split('/').any(|part| matches!(part, "var" | "proc" | "verb")) { continue; }
                        if objtree.find(&path).is_some() {
                            types.push(path.clone());
                            parents.push((*indent as usize, path));
                        }
                    }
                }
            }
            (owners, types)
        });
        for (file, (owners, types)) in code_files.iter().zip(scanned) {
            for o in owners {
                layering_owner_defs.entry(o).or_default().push(file.rel.clone());
            }
            for t in types {
                layering_type_defs.entry(t).or_default().push(file.rel.clone());
            }
        }
        for ty in objtree.iter_types() {
            for var in ty.get().vars.values() {
                let locations = std::iter::once(var.value.location)
                    .chain(var.declaration.as_ref().map(|declaration| declaration.location));
                for location in locations {
                    if let Some(file) = rel_of(location, &mut files).filter(|file| tree.get(file).is_some()) {
                        layering_owner_defs.entry(ty.get().path.clone()).or_default().push(file);
                    }
                }
            }
        }
        // Synthetic DME locations are parser scaffolding, never type definitions.
        for (file, definitions) in &def_index {
            if tree.get(file).is_none() { continue; }
            for (_, owner, _) in definitions {
                layering_owner_defs.entry(owner.clone()).or_default().push(file.clone());
            }
        }
        if std::env::var("DQ_ANALYZE_TRACE").is_ok() {
            eprintln!("analyze: sem build: parse {:.1?}, index {:.1?}, layering {:.1?}", t_parsed, t_indexed - t_parsed, t_build.elapsed() - t_indexed);
        }
        let file_keys: HashMap<dreammaker::FileId, u128> = files.iter().filter_map(|(id, rel)| tree.get(rel).map(|f| (*id, f.hash))).collect();
        Ok(Sem { objtree, files, layering_type_defs, layering_owner_defs, root: root.to_path_buf(), errors, def_index, type_loc, touched: Default::default(), touched_rel: Default::default(), full: real, env_key, file_keys, structure: structure.map(std::sync::OnceLock::from).unwrap_or_default(), globals: Default::default(), writes: Default::default() })
    }

    pub fn rel(&self, loc: Location) -> &str {
        if !loc.is_builtins() {
            self.touched.lock().unwrap().insert(loc.file);
        }
        self.files.get(&loc.file).map(|s| s.as_str()).unwrap_or("")
    }

    /// The file a location is in, without recording it in the footprint.
    pub(crate) fn file_of(&self, loc: Location) -> Option<&str> {
        if loc.is_builtins() {
            return None;
        }
        self.files.get(&loc.file).map(|s| s.as_str())
    }

    fn touch_rel(&self, file: &str) {
        self.touched_rel.lock().unwrap().insert(file.to_string());
    }

    /// Every file the analysis consulted so far (repo-relative, sorted).
    pub fn footprint(&self) -> Vec<String> {
        let mut out: std::collections::BTreeSet<String> = self.touched_rel.lock().unwrap().iter().cloned().collect();
        for id in self.touched.lock().unwrap().iter() {
            if let Some(r) = self.files.get(id) {
                out.insert(r.clone());
            }
        }
        out.into_iter().collect()
    }

    pub fn ty(&self, path: &str) -> Option<TypeRef<'_>> {
        if path == "/" || path.is_empty() {
            return Some(self.objtree.root());
        }
        self.objtree.find(path)
    }

    /// `child` is `parent` or one of its subtypes.
    pub fn is_subtype(&self, child: &str, parent: &str) -> bool {
        let Some(c) = self.ty(child) else { return false };
        let Some(p) = self.ty(parent) else { return false };
        c.is_subtype_of(p.get())
    }

    /// The parent type's path (the `parent_type` chain, not the path nesting).
    pub fn parent_of(&self, path: &str) -> Option<String> {
        let t = self.ty(path)?;
        let p = t.parent_type()?;
        let pp = &p.get().path;
        Some(if pp.is_empty() { "/".to_string() } else { pp.clone() })
    }

    /// A var visible on `ty` (declared on it or an ancestor), with its declared type.
    pub fn var_decl(&self, ty: &str, name: &str) -> Option<VarSig> {
        walk_cache::record(|| walk_cache::Dep::Var(ty.to_string(), name.to_string()));
        self.var_decl_unrecorded(ty, name)
    }

    /// Which global vars change after boot: a function of the model, built once for every engine.
    pub fn global_index(&self) -> &globals::GlobalIndex {
        self.globals.get_or_init(|| globals::GlobalIndex::build(self))
    }

    /// Which var names are written anywhere: a function of the model, built once for every engine.
    pub fn write_index(&self) -> &reads::WriteIndex {
        self.writes.get_or_init(|| reads::WriteIndex::build(self))
    }

    /// Whether this model's walks may be kept between runs.
    pub fn cacheable(&self) -> bool {
        self.full && self.env_key != 0
    }

    /// A digest of where `loc` is: its file's content in this macro environment (a location in an unchanged file is unchanged).
    pub(crate) fn location_key(&self, loc: Location) -> u128 {
        if loc.is_builtins() {
            return 1;
        }
        let k = self.file_keys.get(&loc.file).copied().unwrap_or(2);
        let mut h = blake3::Hasher::new();
        h.update(&self.env_key.to_le_bytes());
        h.update(&k.to_le_bytes());
        h.update(self.files.get(&loc.file).map(|s| s.as_str()).unwrap_or("").as_bytes());
        u128::from_le_bytes(h.finalize().as_bytes()[..16].try_into().unwrap())
    }

    /// A digest of the tree's structure without any location or body: types and parents, each var's declaration and initial constant,
    /// each proc's definitions (parameters, whether it has a body) and declaration. What a walk can see of the tree besides the bodies it
    /// enters and the var declarations it looks up.
    pub fn structure_digest(&self) -> u128 {
        *self.structure.get_or_init(|| {
            let mut h = blake3::Hasher::new();
            for t in self.objtree.iter_types() {
                let ty = t.get();
                h.update(ty.path.as_bytes());
                h.update(b"<");
                if let Some(p) = t.parent_type() {
                    h.update(p.get().path.as_bytes());
                }
                for (name, v) in &ty.vars {
                    h.update(b"|v");
                    h.update(name.as_bytes());
                    if let Some(d) = &v.declaration {
                        h.update(format!("{}:{}:{:?}", d.var_type.flags.bits(), d.var_type.type_path.join("/"), d.var_type.input_type).as_bytes());
                    }
                    h.update(format!("={:?}", v.value.constant).as_bytes());
                }
                for (name, p) in &ty.procs {
                    h.update(b"|p");
                    h.update(name.as_bytes());
                    for value in &p.value {
                        h.update(b"(");
                        for prm in value.parameters.iter() {
                            h.update(format!("{}:{}:{}:{:?},", prm.name, prm.var_type.flags.bits(), prm.var_type.type_path.join("/"), prm.input_type).as_bytes());
                        }
                        h.update(if value.code.has_body() { b")b" } else { b")n" });
                    }
                    if let Some(d) = &p.declaration {
                        h.update(format!("d{:?}{}{:?}", d.kind, d.flags.bits(), d.return_type).as_bytes());
                    }
                }
                h.update(b"\n");
            }
            u128::from_le_bytes(h.finalize().as_bytes()[..16].try_into().unwrap())
        })
    }

    /// [`var_decl`](Self::var_decl) without recording a walk dependency.
    pub fn var_decl_unrecorded(&self, ty: &str, name: &str) -> Option<VarSig> {
        let t = self.ty(ty)?;
        let d = t.get_var_declaration(name)?;
        let flags = d.var_type.flags;
        let declared = if d.var_type.type_path.is_empty() {
            String::new()
        } else {
            format!("/{}", d.var_type.type_path.join("/"))
        };
        Some(VarSig {
            declared,
            is_static: flags.contains(VarTypeFlags::STATIC),
            is_const: flags.contains(VarTypeFlags::CONST),
            is_tmp: flags.contains(VarTypeFlags::TMP),
            file: self.rel(d.location).to_string(),
            line: d.location.line,
        })
    }

    /// The type that declares `name` (walking parents), for classification by owner.
    pub fn var_owner(&self, ty: &str, name: &str) -> Option<String> {
        let mut cur = self.ty(ty)?;
        loop {
            if cur.get().vars.get(name).map(|v| v.declaration.is_some()).unwrap_or(false) {
                let p = &cur.get().path;
                return Some(if p.is_empty() { "/".to_string() } else { p.clone() });
            }
            cur = cur.parent_type()?;
        }
    }

    pub fn proc_ref(&self, ty: &str, name: &str) -> Option<ProcRef<'_>> {
        self.ty(ty)?.get_proc(name)
    }

    pub fn global_proc(&self, name: &str) -> Option<ProcRef<'_>> {
        self.objtree.root().get_proc(name)
    }

    pub fn proc_body<'a>(&'a self, p: ProcRef<'a>) -> ProcBody<'a> {
        let v = p.get();
        let owner = {
            let path = &p.ty().get().path;
            if path.is_empty() { "/".to_string() } else { path.clone() }
        };
        ProcBody {
            owner,
            name: p.name().to_string(),
            params: &v.parameters,
            code: v.code.as_ref(),
            file: self.rel(v.location).to_string(),
            line: v.location.line,
            builtin: p.is_builtin(),
        }
    }

    /// The type that owns the definition nearest `line` in `file`, looking back first and then
    /// forward: where a text marker (`READS_AS(...)`) sits is decided by the definitions around it.
    pub fn owner_candidates(&self, file: &str, line: u32) -> Vec<String> {
        self.touch_rel(file);
        let Some(defs) = self.def_index.get(file) else { return Vec::new() };
        let mut out = Vec::new();
        let idx = defs.partition_point(|(l, _, _)| *l <= line);
        if idx > 0 {
            out.push(defs[idx - 1].1.clone());
        }
        if idx < defs.len() && !out.contains(&defs[idx].1) {
            out.push(defs[idx].1.clone());
        }
        out
    }

    /// Every `(file, line, owner)` definition, for "which proc is this line in".
    pub fn defs_in(&self, file: &str) -> &[(u32, String, String)] {
        self.touch_rel(file);
        self.def_index.get(file).map(|v| v.as_slice()).unwrap_or(&[])
    }

    /// Paths of every type, sorted.
    pub fn type_paths(&self) -> Vec<String> {
        let mut v: Vec<String> = self.objtree.iter_types().map(|t| if t.get().path.is_empty() { "/".to_string() } else { t.get().path.clone() }).collect();
        v.sort();
        v
    }
}

/// Parses `dme_path` with dreammaker: the preprocessor (lexing, macro expansion, includes: about a third of the parse) runs on its own
/// thread and streams batches of tokens to the parser here. A `Context` is not shareable between threads, so each side has its own: the
/// preprocessor's registers the files (every `Location` names one of its file ids), and the errors of both are kept. `preregister` names
/// files to register first, in order, so they get the same ids as in the parse that produced that list (`model_store`).
pub(crate) fn parse_dme(dme_path: &Path, preregister: &[PathBuf], text: Option<String>) -> Result<model_store::Parsed, String> {
    parse_source(dme_path, preregister, Source::Dme(text), false)
}

/// What the preprocessor reads.
pub(crate) enum Source {
    /// The `.dme` (or text standing in for it: includes resolve against the real `.dme`'s directory).
    Dme(Option<String>),
    /// Files read one after the other, starting with the macro state the stored history had at the start of the first: (registered path,
    /// path on disk). See `model_store`.
    Alone(std::sync::Arc<dreammaker::preprocessor::StoredDefineHistory>, Vec<(PathBuf, PathBuf)>),
}

/// [`parse_dme`] with the source spelled out; `history` also returns the parse's macro history (`Parsed::defines`).
pub(crate) fn parse_source(dme_path: &Path, preregister: &[PathBuf], source: Source, history: bool) -> Result<model_store::Parsed, String> {
    const BATCH: usize = 8192;
    let (tx, rx) = std::sync::mpsc::sync_channel::<Vec<dreammaker::lexer::LocatedToken>>(64);
    let dme_for_pp = dme_path.to_path_buf();
    let pre: Vec<PathBuf> = preregister.to_vec();
    type Out = (dreammaker::Context, Option<dreammaker::preprocessor::StoredDefineHistory>);
    let pp_thread = std::thread::Builder::new()
        .name("dm-preprocess".into())
        .stack_size(64 * 1024 * 1024)
        .spawn(move || -> Result<Out, String> {
            let _acct = CpuGuard(std::panic::Location::caller(), if crate::util::cpu_accounting() { crate::util::thread_cpu_ms() } else { 0 });
            let ctx = dreammaker::Context::default();
            for p in &pre {
                ctx.register_file(p);
            }
            let stored = {
                let mut pp = match source {
                    Source::Dme(Some(t)) => dreammaker::preprocessor::Preprocessor::from_buffer(&ctx, dme_for_pp.clone(), t),
                    Source::Dme(None) => dreammaker::preprocessor::Preprocessor::new(&ctx, dme_for_pp.clone()).map_err(|e| format!("{}: {}", dme_for_pp.display(), e))?,
                    Source::Alone(hist, files) => {
                        let Some((first, _)) = files.first() else { return Err("nothing to parse".to_string()) };
                        let fid = ctx.get_file(first).ok_or("the first file is not registered")?;
                        let mut pp = dreammaker::preprocessor::DefineHistory::from_stored(&hist).branch_at_file(fid, &ctx);
                        // An include stack: the first file is read first.
                        // Registered under its relative path, `__FILE__` the path an include from the .dme resolves to (the .dme's directory
                        // joined with the include text), as in the full parse.
                        let env_dir = dme_for_pp.parent().map(|p| p.to_path_buf()).unwrap_or_default();
                        for (reg, abs) in files.iter().rev() {
                            let f = std::fs::File::open(abs).map_err(|e| format!("{}: {}", abs.display(), e))?;
                            let shown = if reg.is_absolute() { reg.clone() } else { env_dir.join(reg.to_string_lossy().replace('\\', "/")) };
                            pp.push_file_as(reg, shown, f).map_err(|e| e.to_string())?;
                        }
                        pp
                    }
                };
                let mut batch = Vec::with_capacity(BATCH);
                for tok in dreammaker::indents::IndentProcessor::new(&ctx, &mut pp) {
                    batch.push(tok);
                    if batch.len() == BATCH {
                        if tx.send(std::mem::replace(&mut batch, Vec::with_capacity(BATCH))).is_err() {
                            break;
                        }
                    }
                }
                if !batch.is_empty() {
                    let _ = tx.send(batch);
                }
                history.then(|| pp.finalize().to_stored())
            };
            Ok((ctx, stored))
        })
        .map_err(|e| format!("preprocessor thread: {}", e))?;
    let parse_ctx = dreammaker::Context::default();
    let objtree = {
        let mut parser = dreammaker::parser::Parser::new(&parse_ctx, rx.into_iter().flatten());
        parser.enable_procs();
        let (_fatal, mut tree) = parser.parse_object_tree_2();
        // A proc's body range ends in whatever file came next; nothing reads it (model_store splices files parsed alone).
        tree.drop_body_ranges();
        tree
    };
    let (ctx, defines) = match pp_thread.join() {
        Ok(r) => r?,
        Err(_) => return Err("preprocessor thread panicked".to_string()),
    };
    let errors = {
        let pp_errors = ctx.errors();
        let parse_errors = parse_ctx.errors();
        let mut all: Vec<&dreammaker::DMError> = pp_errors.iter().chain(parse_errors.iter()).filter(|e| matches!(e.severity(), dreammaker::Severity::Error)).collect();
        // One context interleaved them in stream order; by location is the same order.
        all.sort_by_key(|e| { let l = e.location(); (l.file, l.line, l.column) });
        all.iter().map(|e| format!("{}", e)).collect()
    };
    Ok(model_store::Parsed { objtree, files: ctx.clone_file_list(), errors, env: None, structure: None, defines })
}

/// One line of a file as the layering index reads it (see `Sem::build_with`).
#[derive(serde::Serialize, serde::Deserialize, Clone, Debug, PartialEq)]
enum LayerEvent {
    /// `/type/var/x`: the type owns a field (if the model has the type).
    Owner(String),
    /// A `CAPABILITY_TYPE` / `CAPABILITY_DEF` marker's type.
    Type(String),
    /// A non-empty line's indent (pops the header stack).
    Indent(u32),
    /// A bare type header at an indent.
    Header(u32, String),
}

fn layering_events(code: &str, capability_type: &regex::Regex, capability_def: &regex::Regex) -> Vec<LayerEvent> {
    let mut out = Vec::new();
    let mut headers: Vec<usize> = Vec::new();
    for raw in code.lines() {
        let text = raw.trim();
        if text.is_empty() { continue; }
        // An uninitialized absolute field declaration can carry no
        // useful value/declaration location in ObjectTree. Its explicit
        // owner is still an actual definition, not a typed reference.
        let declaration = text.split_whitespace().next().unwrap_or("");
        if declaration.starts_with('/') {
            if let Some((owner, member)) = declaration.split_once("/var/") {
                if !member.is_empty() {
                    out.push(LayerEvent::Owner(owner.to_string()));
                }
            }
        }
        if let Some(cap) = capability_type.captures(text) {
            out.push(LayerEvent::Type(cap[1].to_string()));
        }
        if let Some(cap) = capability_def.captures(text) {
            out.push(LayerEvent::Type(format!("/datum/capability/def/{}", &cap[1])));
        }
        let indent = raw.len() - raw.trim_start().len();
        // An indent can only pop a header stack entry at or past it: kept only while some earlier header could be on the stack.
        if headers.last().is_some_and(|n| *n >= indent) {
            while headers.last().is_some_and(|n| *n >= indent) { headers.pop(); }
            out.push(LayerEvent::Indent(indent as u32));
        }
        // A bare type header is a definition. Typed arguments, locals,
        // member declarations and proc definitions are only references.
        let header = text.trim_end_matches('{').trim();
        if !header.is_empty() && header.chars().all(|c| c.is_ascii_alphanumeric() || c == '_' || c == '/') {
            out.push(LayerEvent::Header(indent as u32, header.to_string()));
            headers.push(indent);
        }
    }
    out
}

fn tempfile_dir(root: &Path) -> PathBuf {
    static SEQ: std::sync::atomic::AtomicUsize = std::sync::atomic::AtomicUsize::new(0);
    let n = std::process::id();
    let seq = SEQ.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
    let t = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|d| d.as_nanos()).unwrap_or(0);
    let dir = std::env::temp_dir().join(format!("dq-sem-{}-{}-{}-{}", n, seq, t, root.file_name().map(|s| s.to_string_lossy().to_string()).unwrap_or_default().chars().take(12).collect::<String>()));
    let _ = std::fs::create_dir_all(&dir);
    dir
}

/// What the memo stores: the model, or nothing when the parse failed.
pub struct SemBox {
    sem: Option<Sem>,
}

/// A shared handle to the run's semantic model; derefs to [`Sem`].
#[derive(Clone)]
pub struct SemHandle(std::sync::Arc<SemBox>);

impl std::ops::Deref for SemHandle {
    type Target = Sem;
    fn deref(&self) -> &Sem {
        self.0.sem.as_ref().expect("SemHandle only exists for a built model")
    }
}

impl crate::lint::Cx<'_> {
    /// The semantic model for this tree, built once per run. `None` when the parse failed (the
    /// reason goes to stderr once).
    pub fn sem(&self) -> Option<SemHandle> {
        sem_for(self.tree)
    }
}

/// The memoized semantic model of `tree`.
pub fn sem_for(tree: &Tree) -> Option<SemHandle> {
    let b = tree.memo("sem/model", || SemBox {
        sem: {
            walk_cache::prefetch();
            match Sem::build(&tree.root, tree) {
                Ok(s) => Some(s),
                Err(e) => {
                    eprintln!("analyze: semantic model unavailable: {}", e);
                    None
                }
            }
        },
    });
    if b.sem.is_some() {
        model_store::save_later(b.clone());
        if b.sem.as_ref().map(|s| s.full).unwrap_or(false) {
            walk_cache::set_model(b.clone());
        }
        Some(SemHandle(b))
    } else {
        None
    }
}

impl Sem {
    /// `owner::proc` of the definition the code at `line` of `file` sits in (`?` when the model has none there): the reader a read
    /// ratchet's identity names. The model's own proc name and owner, so an edit of the line's text or a move within the proc keeps it.
    pub fn reader_ident(&self, file: &str, line: u32) -> String {
        match self.def_at(file, line) {
            Some((owner, name)) => format!("{owner}::{name}"),
            None => "?".to_string(),
        }
    }

    /// The nearest definition at or before `line` in `file`: `(owner, name)` of the proc or var it
    /// declares. A marker inside a proc body belongs to that proc.
    pub fn def_at(&self, file: &str, line: u32) -> Option<(String, String)> {
        self.touch_rel(file);
        let defs = self.def_index.get(file)?;
        let idx = defs.partition_point(|(l, _, _)| *l <= line);
        if idx == 0 {
            return None;
        }
        Some((defs[idx - 1].1.clone(), defs[idx - 1].2.clone()))
    }
}

/// Adds a worker thread's CPU time to `util::cpu_account` (under `DQ_CPU_ACCOUNT`) when it ends.
struct CpuGuard(&'static std::panic::Location<'static>, u64);

impl Drop for CpuGuard {
    fn drop(&mut self) {
        if crate::util::cpu_accounting() {
            crate::util::cpu_account(format!("par_map at {}:{}", self.0.file(), self.0.line()), crate::util::thread_cpu_ms().saturating_sub(self.1));
        }
    }
}

/// `items.iter().map(f).collect()` on plain OS threads, in order.
///
/// The semantic layer's memoized values (`Decls`, the write index, ...) are built inside `Tree::memo`, i.e. under a
/// `OnceLock` init. A rayon `par_iter` there lets the initializing worker steal another lint's task while it waits,
/// and a stolen task that needs the same cell blocks on the init this very thread is running (or two inits wait on
/// each other): a deadlock the stress run hit about one cold run in six. Scoped threads never steal engine work.
/// [`par_map`] on threads with a stack deep enough for the read walk (a followed proc is a few frames of a large recursive evaluator).
#[track_caller]
pub fn par_map_deep<T: Sync, R: Send>(items: &[T], f: impl Fn(&T) -> R + Sync) -> Vec<R> {
    let caller = std::panic::Location::caller();
    let n = std::thread::available_parallelism().map(|n| n.get()).unwrap_or(4).min(items.len().max(1));
    if n <= 1 {
        return items.iter().map(f).collect();
    }
    let next = std::sync::atomic::AtomicUsize::new(0);
    let chunk = 8;
    let mut parts: Vec<Vec<(usize, R)>> = Vec::new();
    std::thread::scope(|s| {
        let handles: Vec<_> = (0..n)
            .map(|_| {
                std::thread::Builder::new()
                    .stack_size(256 << 20)
                    .spawn_scoped(s, || {
                        let c0 = if crate::util::cpu_accounting() { crate::util::thread_cpu_ms() } else { 0 };
                        let _acct = CpuGuard(caller, c0);
                        let mut local: Vec<(usize, R)> = Vec::new();
                        loop {
                            let start = next.fetch_add(chunk, std::sync::atomic::Ordering::Relaxed);
                            if start >= items.len() {
                                break;
                            }
                            for i in start..(start + chunk).min(items.len()) {
                                local.push((i, f(&items[i])));
                            }
                        }
                        local
                    })
                    .expect("spawn a walk thread")
            })
            .collect();
        for h in handles {
            parts.push(h.join().expect("a walk thread panicked"));
        }
    });
    let mut all: Vec<(usize, R)> = parts.into_iter().flatten().collect();
    all.sort_by_key(|(i, _)| *i);
    all.into_iter().map(|(_, r)| r).collect()
}

#[track_caller]
pub fn par_map<T: Sync, R: Send>(items: &[T], f: impl Fn(&T) -> R + Sync) -> Vec<R> {
    let caller = std::panic::Location::caller();
    let n = std::thread::available_parallelism().map(|n| n.get()).unwrap_or(4).min(items.len().max(1));
    if n <= 1 || items.len() < 64 {
        return items.iter().map(f).collect();
    }
    let next = std::sync::atomic::AtomicUsize::new(0);
    let chunk = 32;
    let mut parts: Vec<Vec<(usize, R)>> = Vec::new();
    std::thread::scope(|s| {
        let handles: Vec<_> = (0..n)
            .map(|_| {
                s.spawn(|| {
                    let c0 = if crate::util::cpu_accounting() { crate::util::thread_cpu_ms() } else { 0 };
                    let _acct = CpuGuard(caller, c0);
                    let mut local: Vec<(usize, R)> = Vec::new();
                    loop {
                        let start = next.fetch_add(chunk, std::sync::atomic::Ordering::Relaxed);
                        if start >= items.len() {
                            break;
                        }
                        for i in start..(start + chunk).min(items.len()) {
                            local.push((i, f(&items[i])));
                        }
                    }
                    local
                })
            })
            .collect();
        for h in handles {
            parts.push(h.join().expect("par_map worker panicked"));
        }
    });
    let mut all: Vec<(usize, R)> = parts.into_iter().flatten().collect();
    all.sort_by_key(|(i, _)| *i);
    all.into_iter().map(|(_, r)| r).collect()
}

#[cfg(test)]
mod tests {
    #[test]
    fn par_map_keeps_order_and_covers_every_item() {
        let items: Vec<u32> = (0..1000).collect();
        let out = super::par_map(&items, |x| x * 2);
        assert_eq!(out.len(), 1000);
        assert!(out.iter().enumerate().all(|(i, v)| *v == (i as u32) * 2));
        // Small inputs take the serial path.
        assert_eq!(super::par_map(&[1u32, 2, 3], |x| x + 1), vec![2, 3, 4]);
    }

    #[test]
    fn reader_ident_names_the_proc_a_line_sits_in() {
        let text = "/obj/a/proc/one()
	var/x = 1
	return x
/obj/a
	var/y = 2
/obj/a/proc/two()
	return 2
";
        let root = tempfile::tempdir().unwrap();
        std::fs::create_dir_all(root.path().join("code")).unwrap();
        std::fs::write(root.path().join("code/probe.dm"), text).unwrap();
        let tree = crate::tree::Tree::from_files(vec![crate::tree::SourceFile::from_text("code/probe.dm", text)]);
        let sem = super::Sem::build(root.path(), &tree).unwrap();
        assert_eq!(sem.reader_ident("code/probe.dm", 3), "/obj/a::one");
        assert_eq!(sem.reader_ident("code/probe.dm", 7), "/obj/a::two");
        assert_eq!(sem.reader_ident("code/other.dm", 3), "?");
    }
}
