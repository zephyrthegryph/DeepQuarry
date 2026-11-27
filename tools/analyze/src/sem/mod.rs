//! The semantic layer: type, proc and var resolution over the compiler's front end, and the queries
//! built on it (generated reads, key resolution, handler checks, the generator API).
//!
//! `Sem` holds the analysis view of one tree (`crate::model::Model`: dmbc's semantic tree, declaration
//! occurrences and typed bodies, which the registered front end provider hands over). It is built once
//! per run (`Cx::sem()`, memoized) and shared by every semantic lint and generator.
//!
//! Declarations that expand to nothing in DM (`CAPABILITIES(...)`, `STAT(...)`, `READS_AS(...)`,
//! `READS_FROM(...)`, ...) are read from source text by [`decls`]; everything that needs real
//! structure (what a proc body reads, what a type declares) comes from the typed tree here.

pub mod actor_tests;
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
pub mod value_schema;
pub mod walk_cache;
pub mod body_facts;
pub mod oracle;
pub mod procs;
pub mod reads;
pub mod ui_windows;

use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::Arc;

use crate::model::procs::Proc;
use crate::model::{Model, Param, Site, Ty};
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
    pub params: Arc<Vec<Param>>,
    pub code: Option<&'a [dm_syntax::Statement]>,
    pub file: String,
    pub line: u32,
    pub builtin: bool,
    pub proc: Proc<'a>,
}

/// The compiler's front end for a `.dme`: `dmbc` registers the provider at startup (its daemon's retained session of the root, or a cold
/// build). The semantic model reads it through [`crate::model::Model`].
pub type FrontendProvider = fn(dme: &Path) -> Result<dm_tree::frontend::FrontendRevision, String>;

static FRONTEND_PROVIDER: std::sync::OnceLock<FrontendProvider> = std::sync::OnceLock::new();

/// Registers the front end the model is built from. The first registration wins.
pub fn register_frontend_provider(provider: FrontendProvider) {
    let _ = FRONTEND_PROVIDER.set(provider);
}

fn provided_frontend(dme: &Path) -> Result<dm_tree::frontend::FrontendRevision, String> {
    // The crate's own unit tests have no dmbc process to register one: they use dmbc's front end directly (a dev-dependency).
    #[cfg(test)]
    register_frontend_provider(dmbc::analysis_frontend::frontend);
    let provider = FRONTEND_PROVIDER.get().ok_or("the semantic model needs the compiler's front end: run it as `dmbc analyze`")?;
    let started = std::time::Instant::now();
    let rev = provider(dme);
    if dq_hostio::var("DQ_ANALYZE_TRACE").is_ok() || dq_hostio::var("DQ_ANALYZE_PARSE_TRACE").is_ok() {
        eprintln!("analyze: front end for the model in {:.1?}", started.elapsed());
    }
    rev
}

pub struct Sem {
    model: Model,
    pub root: PathBuf,
    /// Diagnostics the front end raised (not findings: informational).
    pub errors: Vec<String>,
    /// file -> sorted (line, owner type path, name) of every var/proc definition, for locating the owner of a text marker by its line.
    def_index: HashMap<String, Vec<(u32, String, String)>>,
    /// type path -> repo-relative file of the type's first block.
    pub(crate) type_loc: HashMap<String, String>,
    pub(crate) layering_type_defs: HashMap<String, Vec<String>>,
    pub(crate) layering_owner_defs: HashMap<String, Vec<String>>,
    /// Files whose definitions (locations, bodies) the analysis consulted: the footprint a cached result depends on (see
    /// `sem::incremental`). Every file-attributed answer goes through [`Sem::rel`] or the def index, which record here.
    touched_rel: std::sync::RwLock<std::collections::HashSet<Arc<str>>>,
    /// Built from the real `.dme` (not a partial or fixture model): its walks may be kept between runs (`walk_cache`).
    full: bool,
    /// The front end's inputs (every file's path and bytes, in include order) and each file's content key: a proc body digests as its
    /// file's key.
    env_key: u128,
    file_keys: HashMap<String, u128>,
    structure: std::sync::OnceLock<u128>,
    globals: std::sync::OnceLock<globals::GlobalIndex>,
    writes: std::sync::OnceLock<reads::WriteIndex>,
}

impl Sem {
    /// The analysis view over the compiler's front end.
    pub fn m(&self) -> &Model {
        &self.model
    }

    /// Builds the model. A tree with a non-empty `deepquarry.dme` uses it (include order matters for define visibility); anything else
    /// (a fixture) gets a synthesized `.dme` that includes every `code/**/*.dm` in path order.
    pub fn build(root: &Path, tree: &Tree) -> Result<Sem, String> {
        Sem::build_with(root, tree, None)
    }

    /// A model of only `files` (repo-relative) plus every `code/__defines/**` file for macros: the cheap model per-proc checks use when
    /// only a few files matter. Types the other files declare are absent.
    pub fn build_partial(root: &Path, tree: &Tree, files: &[String]) -> Result<Sem, String> {
        Sem::build_with(root, tree, Some(files))
    }

    fn build_with(root: &Path, tree: &Tree, only: Option<&[String]>) -> Result<Sem, String> {
        // The synthesized .dme lives in a temp dir, so every path it names must be absolute.
        let abs_root: PathBuf = if root.is_absolute() { root.to_path_buf() } else { dq_hostio::current_dir().map_err(|e| e.to_string())?.join(root) };
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
                    list.extend(tree.select(&CODE_DM).iter().filter(|f| crate::scopes::is_defines(&f.rel)).map(|f| f.rel.clone()));
                    // Macros are order sensitive: the defines compile in deepquarry.dme's order (their folders no longer sort the same
                    // way), not path order. A file the manifest does not name keeps its place after the named ones.
                    if let Ok(text) = std::fs::read_to_string(&dme) {
                        let slot: HashMap<String, usize> = text
                            .lines()
                            .filter_map(|l| l.trim().strip_prefix("#include \"").and_then(|r| r.strip_suffix('"')).map(|r| r.replace('\\', "/")))
                            .enumerate()
                            .map(|(i, r)| (r, i))
                            .collect();
                        list.sort_by_key(|r| slot.get(r).copied().unwrap_or(usize::MAX));
                    }
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
        let rev = provided_frontend(&dme_path);
        if let Some(dir) = _keep {
            let _ = std::fs::remove_dir_all(dir);
        }
        let rev = rev?;
        let model = Model::new(rev, root);
        let t_parsed = t_build.elapsed();
        // What a file's text says decides its key; the files in include order and their keys decide the environment.
        let mut file_keys: HashMap<String, u128> = HashMap::new();
        let mut env = blake3::Hasher::new();
        for rel in model.file_paths() {
            let key = tree.get(&rel).map(|f| f.hash).unwrap_or(0);
            env.update(rel.as_bytes());
            env.update(&key.to_le_bytes());
            file_keys.insert(rel, key);
        }
        let env_key = if real { u128::from_le_bytes(env.finalize().as_bytes()[..16].try_into().unwrap()) } else { 0 };
        let line = |site: Option<Site>| site.and_then(|s| model.line(s));
        // Each type's facts on every core (sites are looked up in the front end's line map), merged in type order.
        struct TypeFacts {
            path: String,
            loc: Option<String>,
            defs: Vec<(String, u32, String)>,
            owners: Vec<String>,
        }
        let types: Vec<Ty<'_>> = model.types().collect();
        let facts: Vec<TypeFacts> = {
            use rayon::prelude::*;
            types
                .par_iter()
                .map(|ty| {
                    let path = ty.path().to_string();
                    let loc = line(ty.site()).map(|(file, _)| file);
                    let mut defs = Vec::new();
                    let mut owners: Vec<String> = Vec::new();
                    for name in ty.var_names() {
                        let members: Vec<_> = ty.own_vars_named(&name).collect();
                        let declaration = members.iter().find(|m| m.declares()).and_then(|m| line(m.site()));
                        if let Some((file, l)) = &declaration {
                            defs.push((file.clone(), *l, name.clone()));
                        }
                        // The var's value (its last assignment) and its declaration on this type.
                        let value = members.last().and_then(|m| line(m.site()));
                        for (file, _) in value.into_iter().chain(declaration) {
                            if tree.get(&file).is_some() {
                                owners.push(file);
                            }
                        }
                    }
                    for name in ty.proc_names() {
                        for p in ty.proc_definitions(name) {
                            if let Some((file, l)) = line(p.site()) {
                                defs.push((file, l, name.to_string()));
                            }
                        }
                    }
                    TypeFacts { path, loc, defs, owners }
                })
                .collect()
        };
        let mut def_index: HashMap<String, Vec<(u32, String, String)>> = HashMap::new();
        let mut type_loc: HashMap<String, String> = HashMap::new();
        let mut owner_locations: Vec<(String, Vec<String>)> = Vec::new();
        for f in facts {
            if let Some(file) = f.loc {
                type_loc.insert(f.path.clone(), file);
            }
            for (file, l, name) in f.defs {
                def_index.entry(file).or_default().push((l, f.path.clone(), name));
            }
            owner_locations.push((f.path, f.owners));
        }
        for v in def_index.values_mut() {
            v.sort();
        }
        let t_indexed = t_build.elapsed();
        let (layering_type_defs, mut layering_owner_defs) = layering_definitions(tree, &model);
        for (path, files) in owner_locations {
            if !files.is_empty() {
                layering_owner_defs.entry(path).or_default().extend(files);
            }
        }
        // Synthetic DME locations are parser scaffolding, never type definitions.
        for (file, definitions) in &def_index {
            if tree.get(file).is_none() {
                continue;
            }
            for (_, owner, _) in definitions {
                layering_owner_defs.entry(owner.clone()).or_default().push(file.clone());
            }
        }
        if dq_hostio::var("DQ_ANALYZE_TRACE").is_ok() {
            eprintln!("analyze: sem build: front end {:.1?}, index {:.1?}, layering {:.1?}", t_parsed, t_indexed - t_parsed, t_build.elapsed() - t_indexed);
        }
        let errors = Vec::new();
        Ok(Sem {
            model,
            root: root.to_path_buf(),
            errors,
            def_index,
            type_loc,
            layering_type_defs,
            layering_owner_defs,
            touched_rel: Default::default(),
            full: real,
            env_key,
            file_keys,
            structure: Default::default(),
            globals: Default::default(),
            writes: Default::default(),
        })
    }

    /// The repo-relative file `site` is in (`""` for none), recorded in the footprint.
    pub fn rel(&self, site: Option<Site>) -> String {
        match site.and_then(|s| self.model.file_arc(s)) {
            Some(file) => {
                self.touch_arc(&file);
                file.to_string()
            }
            None => String::new(),
        }
    }

    /// The file and line `site` is at, without recording it in the footprint.
    pub(crate) fn file_of(&self, site: Option<Site>) -> Option<String> {
        site.and_then(|s| self.model.file_arc(s)).map(|f| f.to_string())
    }

    /// The line `site` is on (0 for none).
    pub fn line(&self, site: Option<Site>) -> u32 {
        site.and_then(|s| self.model.line_no(s)).unwrap_or(0)
    }

    fn touch_arc(&self, file: &Arc<str>) {
        if self.touched_rel.read().unwrap_or_else(|e| e.into_inner()).contains(file) {
            return;
        }
        self.touched_rel.write().unwrap_or_else(|e| e.into_inner()).insert(file.clone());
    }

    fn touch_rel(&self, file: &str) {
        if self.touched_rel.read().unwrap_or_else(|e| e.into_inner()).contains(file) {
            return;
        }
        self.touched_rel.write().unwrap_or_else(|e| e.into_inner()).insert(Arc::from(file));
    }

    /// Every file the analysis consulted so far (repo-relative, sorted).
    pub fn footprint(&self) -> Vec<String> {
        let out: std::collections::BTreeSet<String> = self.touched_rel.read().unwrap_or_else(|e| e.into_inner()).iter().map(|f| f.to_string()).collect();
        out.into_iter().collect()
    }

    pub fn ty(&self, path: &str) -> Option<Ty<'_>> {
        if path.is_empty() {
            return self.model.ty("/");
        }
        self.model.ty(path)
    }

    /// `child` is `parent` or one of its subtypes.
    pub fn is_subtype(&self, child: &str, parent: &str) -> bool {
        let Some(c) = self.ty(child) else { return false };
        let Some(p) = self.ty(parent) else { return false };
        c.is_subtype_of(&p)
    }

    /// The parent type's path (the `parent_type` chain, not the path nesting).
    pub fn parent_of(&self, path: &str) -> Option<String> {
        Some(self.ty(path)?.parent()?.path().to_string())
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

    /// The front end's environment key (0 for a model not built from the real `.dme`).
    pub fn env_key(&self) -> u128 {
        self.env_key
    }

    /// Whether this model's walks may be kept between runs.
    pub fn cacheable(&self) -> bool {
        self.full && self.env_key != 0
    }

    /// A digest of where `site` is: its file's content in this environment (a site in an unchanged file is unchanged).
    pub(crate) fn site_key(&self, site: Option<Site>) -> u128 {
        let Some(file) = self.file_of(site) else { return 1 };
        let k = self.file_keys.get(&file).copied().unwrap_or(2);
        let mut h = blake3::Hasher::new();
        h.update(&self.env_key.to_le_bytes());
        h.update(&k.to_le_bytes());
        h.update(file.as_bytes());
        u128::from_le_bytes(h.finalize().as_bytes()[..16].try_into().unwrap())
    }

    /// A digest of the tree's structure without any location or body: types and parents, each var's declaration and initial constant,
    /// each proc's definitions (parameters, whether it has a body) and declaration. What a walk can see of the tree besides the bodies it
    /// enters and the var declarations it looks up.
    pub fn structure_digest(&self) -> u128 {
        *self.structure.get_or_init(|| {
            let folded = self.model.folded();
            let mut h = blake3::Hasher::new();
            for ty in self.model.types() {
                h.update(ty.path().as_bytes());
                h.update(b"<");
                if let Some(p) = ty.parent() {
                    h.update(p.path().as_bytes());
                }
                for name in ty.var_names() {
                    h.update(b"|v");
                    h.update(name.as_bytes());
                    if let Some(d) = ty.var_declaration(&name).filter(|_| ty.declares_var(&name)) {
                        h.update(format!("{}:{}", d.flags, d.declared).as_bytes());
                    }
                    h.update(format!("={:?}", folded.values.get(&(ty.id, name.clone()))).as_bytes());
                }
                for name in ty.proc_names() {
                    h.update(b"|p");
                    h.update(name.as_bytes());
                    for p in ty.proc_definitions(name) {
                        h.update(b"(");
                        for prm in p.parameters().iter() {
                            h.update(format!("{}:{}:{:?},", prm.name, prm.declared(), prm.as_types).as_bytes());
                        }
                        h.update(if p.body().is_some() { b")b" } else { b")n" });
                        if p.declares() {
                            h.update(format!("d{:?}{:?}", p.declared_verb(), p.member().and_then(|m| m.return_type_path())).as_bytes());
                        }
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
        let d = t.var_declaration(name)?;
        // A builtin sits on line 1 of no file.
        let (file, line) = if d.builtin { (String::new(), 1) } else { (self.rel(d.site), self.line(d.site)) };
        Some(VarSig { declared: d.declared.clone(), is_static: d.is_static(), is_const: d.is_const(), is_tmp: d.is_tmp(), file, line })
    }

    /// The type that declares `name` (walking parents), for classification by owner.
    pub fn var_owner(&self, ty: &str, name: &str) -> Option<String> {
        let mut cur = self.ty(ty)?;
        loop {
            if cur.declares_var(name) {
                return Some(cur.path().to_string());
            }
            cur = cur.parent()?;
        }
    }

    pub fn proc_ref(&self, ty: &str, name: &str) -> Option<Proc<'_>> {
        self.ty(ty)?.proc(name)
    }

    pub fn global_proc(&self, name: &str) -> Option<Proc<'_>> {
        self.model.ty("/")?.proc(name)
    }

    pub fn proc_body<'a>(&'a self, p: Proc<'a>) -> ProcBody<'a> {
        let (file, line) = if p.is_builtin() { (String::new(), 1) } else { (self.rel(p.site()), self.line(p.site())) };
        ProcBody {
            owner: p.owner().path().to_string(),
            name: p.name().to_string(),
            params: p.parameters(),
            code: p.body(),
            file,
            line,
            builtin: p.is_builtin(),
            proc: p,
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
        let mut v: Vec<String> = self.model.types().map(|t| t.path().to_string()).collect();
        v.sort();
        v
    }
}

/// The CAPABILITY_TYPE / CAPABILITY_DEF and type-block headers each file's text names, replayed against the model: the files that
/// define each type (by its blocks) and each owner (by its capabilities), for the layering check.
fn layering_definitions(tree: &Tree, model: &Model) -> (HashMap<String, Vec<String>>, HashMap<String, Vec<String>>) {
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
                    if model.ty(owner).is_some() {
                        owners.push(owner.clone());
                    }
                }
                LayerEvent::Type(t) => types.push(t.clone()),
                LayerEvent::Indent(indent) => {
                    while parents.last().is_some_and(|(n, _)| *n >= *indent as usize) {
                        parents.pop();
                    }
                }
                LayerEvent::Header(indent, header) => {
                    let path = if header.starts_with('/') {
                        header.clone()
                    } else if let Some((_, parent)) = parents.last() {
                        format!("{}/{}", parent, header)
                    } else {
                        continue;
                    };
                    if path.split('/').any(|part| matches!(part, "var" | "proc" | "verb")) {
                        continue;
                    }
                    if model.ty(&path).is_some() {
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
    (layering_type_defs, layering_owner_defs)
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

/// The empty stubs a cold `gen` created for the generated includes (the generators overwrite every one of them).
static BOOTSTRAP_STUBS: std::sync::Mutex<Vec<PathBuf>> = std::sync::Mutex::new(Vec::new());

/// Names the stubs [`build_bootstrapping`] may declare missing types in (`analyze gen` sets them; empty for every other command).
pub(crate) fn set_bootstrap_stubs(stubs: Vec<PathBuf>) {
    *BOOTSTRAP_STUBS.lock().unwrap_or_else(|e| e.into_inner()) = stubs;
}

/// The type a refused model names as an invalid parent type (`"<path>: invalid parent type"` in the front end's refusal).
fn missing_parent_type(error: &str) -> Option<String> {
    let end = error.find(": invalid parent type")?;
    let start = error[..end].rfind(|c: char| c == '"' || c.is_whitespace()).map_or(0, |i| i + 1);
    let path = &error[start..end];
    path.starts_with('/').then(|| path.to_string())
}

/// [`Sem::build`] for a cold `gen`: the generated files are still empty stubs, and a type only a generated file declares (an `ACTION()`
/// type, an affliction family) is the `parent_type` of hand-written code, which the compiler's front end refuses as an invalid parent
/// type. Each such type is declared bare in a stub (the generators overwrite every stub) and the model is built again.
fn build_bootstrapping(root: &Path, tree: &Tree) -> Result<Sem, String> {
    let mut declared: Vec<String> = Vec::new();
    loop {
        match Sem::build(root, tree) {
            Err(e) => {
                let stub = BOOTSTRAP_STUBS.lock().unwrap_or_else(|e| e.into_inner()).first().cloned();
                let (Some(path), Some(stub)) = (missing_parent_type(&e), stub) else { return Err(e) };
                if declared.contains(&path) {
                    return Err(e);
                }
                if dq_hostio::var("DQ_ANALYZE_TRACE").is_ok() {
                    eprintln!("analyze: gen: the generated files are not there yet; declaring {path} in {} for the first model", stub.display());
                }
                let mut text = std::fs::read_to_string(&stub).unwrap_or_default();
                text.push_str(&format!("{path}\n"));
                std::fs::write(&stub, text).map_err(|w| format!("{}: {w}", stub.display()))?;
                declared.push(path);
            }
            ok => return ok,
        }
    }
}

/// The memoized semantic model of `tree`.
pub fn sem_for(tree: &Tree) -> Option<SemHandle> {
    let b = tree.memo("sem/model", || SemBox {
        sem: {
            walk_cache::prefetch();
            match build_bootstrapping(&tree.root, tree) {
                Ok(s) => Some(s),
                Err(e) => {
                    eprintln!("analyze: semantic model unavailable: {}", e);
                    None
                }
            }
        },
    });
    if b.sem.is_some() {
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
