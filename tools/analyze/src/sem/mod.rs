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

pub mod ast;
pub mod checks;
pub mod handlers;
pub mod hooks;
pub mod cli;
pub mod decls;
pub mod graph;
pub mod layering;
pub mod keys;
pub mod gen;
pub mod incremental;
pub mod oracle;
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
        let ctx = dreammaker::Context::default();
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
        let objtree = {
            let pp = dreammaker::preprocessor::Preprocessor::new(&ctx, dme_path.clone()).map_err(|e| format!("{}: {}", dme_path.display(), e))?;
            let indents = dreammaker::indents::IndentProcessor::new(&ctx, pp);
            let mut parser = dreammaker::parser::Parser::new(&ctx, indents);
            parser.enable_procs();
            let (_fatal, tree) = parser.parse_object_tree_2();
            tree
        };
        let mut files: HashMap<dreammaker::FileId, String> = HashMap::new();
        let mut def_index: HashMap<String, Vec<(u32, String, String)>> = HashMap::new();
        let rel_of = |loc: Location, files: &mut HashMap<dreammaker::FileId, String>| -> Option<String> {
            if loc.is_builtins() {
                return None;
            }
            let r = files
                .entry(loc.file)
                .or_insert_with(|| crate::util::rel_slash(&ctx.file_path(loc.file).to_path_buf(), root))
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
        let errors = ctx.errors().iter().filter(|e| matches!(e.severity(), dreammaker::Severity::Error)).map(|e| format!("{}", e)).collect();
        if let Some(dir) = _keep {
            let _ = std::fs::remove_dir_all(dir);
        }
        let mut layering_type_defs: HashMap<String, Vec<String>> = HashMap::new();
        let mut layering_owner_defs: HashMap<String, Vec<String>> = HashMap::new();
        let capability_type = regex::Regex::new(r"^CAPABILITY_TYPE\s*\(\s*[^,]+,\s*[^,]+,\s*(/[A-Za-z_][\w/]*)").unwrap();
        let capability_def = regex::Regex::new(r"^CAPABILITY_DEF\s*\(\s*([A-Za-z_]\w*)\s*,").unwrap();
        for file in tree.select(&CODE_DM) {
            let mut parents: Vec<(usize, String)> = Vec::new();
            for raw in file.code().text.lines() {
                let text = raw.trim();
                if text.is_empty() { continue; }
                // An uninitialized absolute field declaration can carry no
                // useful value/declaration location in ObjectTree. Its explicit
                // owner is still an actual definition, not a typed reference.
                let declaration = text.split_whitespace().next().unwrap_or("");
                if declaration.starts_with('/') {
                    if let Some((owner, member)) = declaration.split_once("/var/") {
                        if !member.is_empty() && objtree.find(owner).is_some() {
                            layering_owner_defs.entry(owner.to_string()).or_default().push(file.rel.clone());
                        }
                    }
                }
                if let Some(cap) = capability_type.captures(text) {
                    layering_type_defs.entry(cap[1].to_string()).or_default().push(file.rel.clone());
                }
                if let Some(cap) = capability_def.captures(text) {
                    layering_type_defs.entry(format!("/datum/capability/def/{}", &cap[1])).or_default().push(file.rel.clone());
                }
                let indent = raw.len() - raw.trim_start().len();
                while parents.last().is_some_and(|(n, _)| *n >= indent) { parents.pop(); }
                // A bare type header is a definition. Typed arguments, locals,
                // member declarations and proc definitions are only references.
                let header = text.trim_end_matches('{').trim();
                if !header.is_empty() && header.chars().all(|c| c.is_ascii_alphanumeric() || c == '_' || c == '/') {
                    let path = if header.starts_with('/') { header.to_string() }
                        else if let Some((_, parent)) = parents.last() { format!("{}/{}", parent, header) }
                        else { continue; };
                    if path.split('/').any(|part| matches!(part, "var" | "proc" | "verb")) { continue; }
                    if objtree.find(&path).is_some() {
                        layering_type_defs.entry(path.clone()).or_default().push(file.rel.clone());
                        parents.push((indent, path));
                    }
                }
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
        Ok(Sem { objtree, files, layering_type_defs, layering_owner_defs, root: root.to_path_buf(), errors, def_index, type_loc, touched: Default::default(), touched_rel: Default::default() })
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

fn tempfile_dir(root: &Path) -> PathBuf {
    let n = std::process::id();
    let t = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|d| d.as_nanos()).unwrap_or(0);
    let dir = std::env::temp_dir().join(format!("dq-sem-{}-{}-{}", n, t, root.file_name().map(|s| s.to_string_lossy().to_string()).unwrap_or_default().chars().take(12).collect::<String>()));
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
        sem: match Sem::build(&tree.root, tree) {
            Ok(s) => Some(s),
            Err(e) => {
                eprintln!("analyze: semantic model unavailable: {}", e);
                None
            }
        },
    });
    if b.sem.is_some() {
        Some(SemHandle(b))
    } else {
        None
    }
}

impl Sem {
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

/// `items.iter().map(f).collect()` on plain OS threads, in order.
///
/// The semantic layer's memoized values (`Decls`, the write index, ...) are built inside `Tree::memo`, i.e. under a
/// `OnceLock` init. A rayon `par_iter` there lets the initializing worker steal another lint's task while it waits,
/// and a stolen task that needs the same cell blocks on the init this very thread is running (or two inits wait on
/// each other): a deadlock the stress run hit about one cold run in six. Scoped threads never steal engine work.
pub fn par_map<T: Sync, R: Send>(items: &[T], f: impl Fn(&T) -> R + Sync) -> Vec<R> {
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
}
