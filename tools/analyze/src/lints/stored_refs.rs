//! `stored_refs`: every stored reference to an atom or datum is a declared relation or a weak ref
//! (doc/rewrite/final_api.html section 6, "Storing references"; doc/rewrite/proposals/reference_storage.md).
//!
//! A reference that nothing clears when its target is deleted keeps the target alive: the garbage
//! collector's check fails and the object hard-deletes (a full reference walk on the live server). The
//! declared forms clear themselves: `owns_one`/`owns_many`/`ref_one`/`ref_many`/`links()`/`slot()` (and
//! the legacy `owns()`/`rel_one()`/`rel_many()` tables and `OWN`/`REL` lines that still declare them on
//! master). A weak ref is a handle (`entity_handle()` / `resolve_handle()`): text, never a reference.
//!
//! On the typed model (the full dreammaker parse, `Cx::sem()`), two rules:
//!
//! * `var`: a var whose declared type is an atom or datum (not a turf, an area, a client, a registry or
//!   flyweight type, or a type in `[lint.stored_refs.lists] exempt_types`) that no relation declares.
//!   Reported at the declaration. Static and global vars count: a cache is storage too.
//! * `list`: a list var (a type's var, a global, or a proc's `var/static/list`) that some proc body
//!   fills with an atom or datum: `L += x`, `L |= x`, `L[k] = x`, `L[x] = v`, `L.Add(x)`, `L.Insert(i, x)`,
//!   `L = list(x, ...)`, LAZYADD and friends (macros are expanded by the parser), where the static type
//!   of `x` is an atom or datum. A list typed in its declaration (`var/list/obj/item/L`) counts with no
//!   write. Reported at the list's declaration with one write it was seen at. A declared `ref_many` /
//!   `owns_many` / many `links()` end is not counted.
//!
//! The static type of a value is what the model can say without running anything: `src`, `usr`, a
//! parameter, a local, a var reached by `a.b.c`, `new /type`, a typed list's element. A proc call's
//! result has no type here, so a list filled only from calls is not seen (the lint under-counts; it never
//! guesses).
//!
//! A shrink-only ratchet (`Policy::Sites`, `tools/ci/stored_refs_baseline.txt`, seeded at the count of the
//! day the rule landed). The reference machinery itself (`[lint.stored_refs] exempt_prefixes`) and tests
//! are exempt by path.

use std::collections::{BTreeMap, HashMap, HashSet};

use dreammaker::ast::{AssignOp, Block, Expression, Follow, Statement, Term, VarTypeFlags};

use crate::dm::ownership_index::Index;
use crate::lint::{Cx, Lint, Meta, Policy, Registry, RuleMeta, ScanKind, Sink};
use crate::sem::ast::{stmt_blocks, stmt_exprs, strip_parens, walk_expr};
use crate::sem::decls::Decls;
use crate::sem::procs::engine_line;
use crate::sem::Sem;
use crate::tree::CODE_DM;

const BASELINE: &str = "tools/ci/stored_refs_baseline.txt";

const H_VAR: &str = "declare the var: owns_one/ref_one/links()/slot() in the type's CAPABILITIES block (or its relations() table), which clears it when \
the other end is deleted; or keep a weak ref (entity_handle(x), read back with resolve_handle()). doc/rewrite/proposals/reference_storage.md";
const H_LIST: &str = "a list of atoms/datums is a declared many (owns_many/ref_many/a many links() end) or holds handles (entity_handle(x)); a cache or \
pool keys by a handle or a type, never by the object. doc/rewrite/proposals/reference_storage.md";

static META: Meta = Meta {
    name: "stored_refs",
    group: "",
    label: "stored_refs",
    legacy: "",
    select: CODE_DM,
    scan: ScanKind::Tree,
    policy: Policy::Sites {
        baseline: BASELINE,
        header: &[
            "Stored references outside a declared relation or a weak ref (doc/rewrite/proposals/reference_storage.md). rule<TAB>file<TAB>text.",
            "`analyze check --lint stored_refs` fails on a site not listed here. Shrink-only: after a sweep run",
            "`analyze baseline --update --lint stored_refs`; it drops fixed sites and never adds one.",
        ],
        banned: &[],
    },
    rules: &[RuleMeta { name: "var", hint: H_VAR }, RuleMeta { name: "list", hint: H_LIST }],
    allow: &["stored_refs"],
    lists: &["exempt_types"],
};

struct StoredRefs;

/// Builtin roots that are not game objects, never deleted, or values.
const NOT_REFS: &[&str] = &["/turf", "/area", "/client", "/world", "/savefile", "/database", "/exception", "/regex", "/icon", "/image", "/mutable_appearance", "/sound", "/matrix", "/generator", "/particles", "/filter", "/alist", "/list", "/callee"];

fn under_any(path: &str, roots: &[&str]) -> bool {
    roots.iter().any(|r| path == *r || (path.starts_with(r) && path.as_bytes().get(r.len()) == Some(&b'/')))
}

/// The holder-side knowledge every rule asks: which declared types are references.
struct Kinds<'a> {
    sem: &'a Sem,
    exempt_types: Vec<String>,
    registry: Vec<String>,
    cache: std::cell::RefCell<HashMap<String, bool>>,
}

impl<'a> Kinds<'a> {
    /// `declared` names an atom or datum a reference to which can pin it.
    fn is_ref(&self, declared: &str) -> bool {
        if declared.is_empty() || declared == "/" {
            return false;
        }
        if let Some(v) = self.cache.borrow().get(declared) {
            return *v;
        }
        let v = self.compute(declared);
        self.cache.borrow_mut().insert(declared.to_string(), v);
        v
    }

    fn compute(&self, declared: &str) -> bool {
        if under_any(declared, NOT_REFS) {
            return false;
        }
        if self.exempt_types.iter().any(|t| under_any(declared, &[t.as_str()])) || self.registry.iter().any(|t| under_any(declared, &[t.as_str()])) {
            return false;
        }
        // A subtype of /turf or /area declared by its full path (`/turf/simulated`) is caught above; anything else must be a datum.
        if !(declared.starts_with("/datum") || declared.starts_with("/atom") || declared.starts_with("/obj") || declared.starts_with("/mob")) {
            // A type declared without its root (`/foo` defined as a datum): ask the model.
            return self.sem.ty(declared).is_some() && self.sem.is_subtype(declared, "/datum") && !self.sem.is_subtype(declared, "/turf") && !self.sem.is_subtype(declared, "/area");
        }
        true
    }
}

/// Relation declarations by var name: name -> the types declaring it.
fn relation_index(cx: &Cx) -> HashMap<String, Vec<String>> {
    let mut out: HashMap<String, Vec<String>> = HashMap::new();
    let d = Decls::get(cx.tree);
    for (t, vars) in &d.relations {
        for v in vars {
            out.entry(v.clone()).or_default().push(t.clone());
        }
    }
    let files = cx.all_files();
    let idx: std::sync::Arc<Index> = Index::get(cx.tree, &files);
    for (t, vars) in idx.decls.iter() {
        for (v, decl) in vars.iter() {
            // owns(nameof(x)) with no policy only annotates: it declares nothing that clears.
            if decl.macro_name == "ANNOTATE" {
                continue;
            }
            out.entry(v.to_string()).or_default().push(t.to_string());
        }
    }
    // links(A::a, B::b) written in a relations()/CAPABILITIES body that Decls did not see (a `link(`).
    out
}

fn declared_by_relation(sem: &Sem, rels: &HashMap<String, Vec<String>>, owner: &str, var: &str) -> bool {
    let Some(types) = rels.get(var) else { return false };
    types.iter().any(|t| t == owner || sem.is_subtype(t, owner) || sem.is_subtype(owner, t))
}

/// A list a proc body writes into.
#[derive(Clone, Debug, PartialEq, Eq, Hash, PartialOrd, Ord)]
enum Place {
    /// (declaring type, var name)
    Member(String, String),
    /// A proc's `var/static/list` (file, model line).
    ProcStatic(String, u32),
}

struct ProcScope<'a> {
    owner: &'a str,
    /// local and parameter names -> declared type ("" untyped); `Some(place)` for a proc-static list.
    locals: HashMap<String, (String, Option<Place>)>,
}

fn path_of(tp: &[String]) -> String {
    if tp.is_empty() {
        String::new()
    } else {
        format!("/{}", tp.join("/"))
    }
}

fn collect_locals(b: &Block, rel: &str, out: &mut HashMap<String, (String, Option<Place>)>) {
    for st in b.iter() {
        match &st.elem {
            Statement::Var(v) => {
                let ty = path_of(&v.var_type.type_path);
                let place = if v.var_type.flags.contains(VarTypeFlags::STATIC) && (ty == "/list" || ty.starts_with("/list/")) {
                    Some(Place::ProcStatic(rel.to_string(), st.location.line))
                } else {
                    None
                };
                out.insert(v.name.to_string(), (ty, place));
            }
            Statement::Vars(vs) => {
                for v in vs {
                    out.insert(v.name.to_string(), (path_of(&v.var_type.type_path), None));
                }
            }
            Statement::ForList(fl) => {
                let ty = fl.var_type.as_ref().map(|t| path_of(&t.type_path)).unwrap_or_default();
                out.entry(fl.name.to_string()).or_insert((ty, None));
            }
            Statement::ForKeyValue(fk) => {
                out.entry(fk.key.to_string()).or_insert((String::new(), None));
                out.entry(fk.value.to_string()).or_insert((String::new(), None));
            }
            Statement::ForLoop { init: Some(init), .. } => {
                if let Statement::Var(v) = init.as_ref() {
                    out.insert(v.name.to_string(), (path_of(&v.var_type.type_path), None));
                }
            }
            _ => {}
        }
        for nb in stmt_blocks(&st.elem) {
            collect_locals(nb, rel, out);
        }
    }
}

struct Walker<'a, 'k> {
    sem: &'a Sem,
    kinds: &'k Kinds<'a>,
}

impl<'a, 'k> Walker<'a, 'k> {
    /// The declared type of a var reached on `ty`, or None.
    fn field_type(&self, ty: &str, name: &str) -> Option<String> {
        if ty.is_empty() {
            return None;
        }
        self.sem.var_decl(ty, name).map(|v| v.declared)
    }

    /// The static type of `e`: a type path, or None when the model can't say.
    fn type_of(&self, sc: &ProcScope, e: &Expression) -> Option<String> {
        let e = strip_parens(e);
        match e {
            Expression::Base { term, follow } => {
                let mut cur: Option<String> = match &term.elem {
                    Term::Ident(n) => self.ident_type(sc, n),
                    Term::NewPrefab { prefab, .. } => Some(format!("/{}", prefab.path.iter().map(|(_, n)| n.as_str()).collect::<Vec<_>>().join("/"))),
                    Term::Expr(inner) => self.type_of(sc, inner),
                    Term::Call(n, _) => self.return_type(if sc.owner == "/" { "/" } else { sc.owner }, n).or_else(|| self.return_type("/", n)),
                    Term::GlobalCall(n, _) => self.return_type("/", n),
                    _ => None,
                };
                for fo in follow.iter() {
                    let Some(c) = cur.clone() else { return None };
                    cur = match &fo.elem {
                        Follow::Field(_, f) => self.field_type(&c, f),
                        Follow::Index(_, _) => c.strip_prefix("/list").filter(|r| r.starts_with('/')).map(|r| r.to_string()),
                        Follow::Call(_, n, _) => self.return_type(&c, n),
                        Follow::Unary(_) => return None,
                        _ => return None,
                    };
                }
                cur
            }
            Expression::TernaryOp { if_, else_, .. } => self.type_of(sc, if_).filter(|t| self.kinds.is_ref(t)).or_else(|| self.type_of(sc, else_)),
            _ => None,
        }
    }

    /// A proc's declared return type (`proc/x() as /type`), or None.
    fn return_type(&self, ty: &str, name: &str) -> Option<String> {
        let d = self.sem.ty(ty)?.get_proc_declaration(name)?;
        match &d.return_type {
            dreammaker::ast::ProcReturnType::TypePath(p) if !p.is_empty() => Some(format!("/{}", p.iter().map(|s| s.as_str()).collect::<Vec<_>>().join("/"))),
            _ => None,
        }
    }

    fn ident_type(&self, sc: &ProcScope, n: &str) -> Option<String> {
        match n {
            "src" => Some(sc.owner.to_string()).filter(|o| o != "/"),
            "usr" => Some("/mob".to_string()),
            _ => {
                if let Some((t, _)) = sc.locals.get(n) {
                    return Some(t.clone());
                }
                if sc.owner != "/" {
                    if let Some(v) = self.sem.var_decl(sc.owner, n) {
                        return Some(v.declared);
                    }
                }
                self.sem.var_decl("/", n).map(|v| v.declared)
            }
        }
    }

    /// The list `e` names, when it is a type's var, a global or a proc-static list.
    fn place_of(&self, sc: &ProcScope, e: &Expression) -> Option<Place> {
        let e = strip_parens(e);
        let Expression::Base { term, follow } = e else { return None };
        if follow.is_empty() {
            let Term::Ident(n) = &term.elem else { return None };
            if let Some((_, p)) = sc.locals.get(n.as_str()) {
                return p.clone();
            }
            if sc.owner != "/" {
                if let Some(o) = self.sem.var_owner(sc.owner, n) {
                    return Some(Place::Member(o, n.to_string()));
                }
            }
            return self.sem.var_owner("/", n).map(|o| Place::Member(o, n.to_string()));
        }
        // a.b.c: the last follow is the field; everything before it is the receiver.
        let Follow::Field(_, last) = &follow[follow.len() - 1].elem else { return None };
        let recv = Expression::Base { term: term.clone(), follow: follow[..follow.len() - 1].to_vec().into_boxed_slice() };
        let rt = self.type_of(sc, &recv)?;
        if rt.is_empty() {
            return None;
        }
        self.sem.var_owner(&rt, last).map(|o| Place::Member(o, last.to_string()))
    }

    /// The values `e` stores when added to a list: itself, or the members of a `list(...)` literal (keys and values).
    fn stored_ref(&self, sc: &ProcScope, e: &Expression) -> bool {
        let e = strip_parens(e);
        if let Expression::Base { term, follow } = e {
            if follow.is_empty() {
                if let Term::List(args) = &term.elem {
                    return args.iter().any(|a| match a {
                        Expression::AssignOp { op: AssignOp::Assign, lhs, rhs } => self.stored_ref(sc, lhs) || self.stored_ref(sc, rhs),
                        other => self.stored_ref(sc, other),
                    });
                }
            }
        }
        self.type_of(sc, e).map(|t| self.kinds.is_ref(&t)).unwrap_or(false)
    }

    /// Every list write in one proc body that stores a reference: (place, model line).
    fn writes(&self, sc: &ProcScope, code: &Block, out: &mut Vec<(Place, u32)>) {
        let visit = |e: &Expression, line: u32, out: &mut Vec<(Place, u32)>| {
            walk_expr(e, &mut |x| match x {
                Expression::AssignOp { op, lhs, rhs } => {
                    let lhs = strip_parens(lhs);
                    // L[k] = v
                    if let Expression::Base { term, follow } = lhs {
                        if let Some(last) = follow.last() {
                            if let Follow::Index(_, key) = &last.elem {
                                if matches!(op, AssignOp::Assign) {
                                    let list = Expression::Base { term: term.clone(), follow: follow[..follow.len() - 1].to_vec().into_boxed_slice() };
                                    if self.stored_ref(sc, key) || self.stored_ref(sc, rhs) {
                                        if let Some(p) = self.place_of(sc, &list) {
                                            out.push((p, line));
                                        }
                                    }
                                }
                                return;
                            }
                        }
                    }
                    let adds = matches!(op, AssignOp::AddAssign | AssignOp::BitOrAssign | AssignOp::OrAssign);
                    let list_literal = matches!(op, AssignOp::Assign) && matches!(strip_parens(rhs), Expression::Base { term, follow } if follow.is_empty() && matches!(term.elem, Term::List(_)));
                    if (adds || list_literal) && self.stored_ref(sc, rhs) {
                        if let Some(p) = self.place_of(sc, lhs) {
                            if self.is_list_place(&p) {
                                out.push((p, line));
                            }
                        }
                    }
                }
                Expression::Base { term, follow } => {
                    for (i, fo) in follow.iter().enumerate() {
                        let Follow::Call(_, name, args) = &fo.elem else { continue };
                        let skip = match name.as_str() {
                            "Add" => 0,
                            "Insert" => 1,
                            _ => continue,
                        };
                        if args.iter().skip(skip).any(|a| self.stored_ref(sc, a)) {
                            let list = Expression::Base { term: term.clone(), follow: follow[..i].to_vec().into_boxed_slice() };
                            if let Some(p) = self.place_of(sc, &list) {
                                if self.is_list_place(&p) {
                                    out.push((p, line));
                                }
                            }
                        }
                    }
                }
                _ => {}
            });
        };
        walk(code, &mut |e, line| visit(e, line, out));
    }

    fn is_list_place(&self, p: &Place) -> bool {
        match p {
            Place::ProcStatic(..) => true,
            Place::Member(o, v) => self.sem.var_decl(o, v).map(|s| s.is_list() || s.declared.is_empty()).unwrap_or(false),
        }
    }
}

/// Every expression of every statement (headers of nested blocks included) with its statement's line.
fn walk(b: &Block, f: &mut dyn FnMut(&Expression, u32)) {
    for st in b.iter() {
        let line = st.location.line;
        for e in stmt_exprs(&st.elem) {
            f(e, line);
        }
        if let Statement::ForLoop { init, inc, .. } = &st.elem {
            for s in [init, inc].into_iter().flatten() {
                for e in stmt_exprs(s) {
                    f(e, line);
                }
            }
        }
        for nb in stmt_blocks(&st.elem) {
            walk(nb, f);
        }
    }
}

impl Lint for StoredRefs {
    fn meta(&self) -> &Meta {
        &META
    }

    fn scan_tree(&self, cx: &Cx, out: &mut Sink) {
        let Some(sem) = cx.sem() else {
            out.note("stored_refs: the semantic model is unavailable; nothing checked");
            return;
        };
        let sem: &Sem = &sem;
        let files = cx.all_files();
        let idx = Index::get(cx.tree, &files);
        let kinds = Kinds { sem, exempt_types: cx.list("exempt_types").to_vec(), registry: idx.registry.clone(), cache: Default::default() };
        let rels = relation_index(cx);
        let root = &cx.tree.root;
        let line_of = |rel: &str, l: u32| engine_line(root, rel, l) as usize;
        let mut emitted: HashSet<(String, String, u32)> = HashSet::new();
        let mut put = |out: &mut Sink, rule: &str, rel: &str, line: usize, msg: String| {
            if !rel.starts_with("code/") || cx.exempt(rel) || !emitted.insert((rule.to_string(), rel.to_string(), line as u32)) {
                return;
            }
            if let Some(f) = cx.tree.get(rel) {
                if out.allowed(f, line, "stored_refs") {
                    return;
                }
            }
            out.site_in_msg(rule, rel, line, msg);
        };

        // ---- var: declarations ----
        let mut typed_lists: Vec<(String, String, String, u32)> = Vec::new();
        let mut decls: Vec<(String, String, String, String, u32)> = Vec::new();
        for ty in sem.objtree.iter_types() {
            let owner = if ty.get().path.is_empty() { "/".to_string() } else { ty.get().path.clone() };
            for (name, tv) in ty.get().vars.iter() {
                let Some(d) = tv.declaration.as_ref() else { continue };
                if d.location.is_builtins() || d.var_type.flags.contains(VarTypeFlags::CONST) {
                    continue;
                }
                let Some(rel) = sem.file_of(d.location) else { continue };
                let declared = path_of(&d.var_type.type_path);
                if declared == "/list" {
                    continue;
                }
                if let Some(elem) = declared.strip_prefix("/list").filter(|r| r.starts_with('/')) {
                    if kinds.is_ref(elem) {
                        typed_lists.push((owner.clone(), name.to_string(), rel.to_string(), d.location.line));
                    }
                    continue;
                }
                if kinds.is_ref(&declared) {
                    decls.push((owner.clone(), name.to_string(), declared, rel.to_string(), d.location.line));
                }
            }
        }
        decls.sort_by(|a, b| (a.3.as_str(), a.4).cmp(&(b.3.as_str(), b.4)));
        for (owner, name, declared, rel, line) in decls {
            if declared_by_relation(sem, &rels, &owner, &name) {
                continue;
            }
            put(out, "var", &rel, line_of(&rel, line), format!("{}/var/{} holds a {} outside a declared relation", if owner == "/" { "" } else { owner.as_str() }, name, declared));
        }

        // ---- list: writes in proc bodies ----
        let w = Walker { sem, kinds: &kinds };
        let mut found: BTreeMap<Place, (String, u32)> = BTreeMap::new();
        for ty in sem.objtree.iter_types() {
            let owner = if ty.get().path.is_empty() { "/".to_string() } else { ty.get().path.clone() };
            for (_, tp) in ty.get().procs.iter() {
                for v in tp.value.iter() {
                    let Some(code) = v.code.as_ref() else { continue };
                    let Some(rel) = sem.file_of(v.location) else { continue };
                    if cx.exempt(rel) {
                        continue;
                    }
                    let mut locals: HashMap<String, (String, Option<Place>)> = HashMap::new();
                    for p in v.parameters.iter() {
                        locals.insert(p.name.to_string(), (path_of(&p.var_type.type_path), None));
                    }
                    collect_locals(code, rel, &mut locals);
                    let sc = ProcScope { owner: &owner, locals };
                    let mut writes = Vec::new();
                    w.writes(&sc, code, &mut writes);
                    for (p, l) in writes {
                        found.entry(p).or_insert_with(|| (rel.to_string(), l));
                    }
                }
            }
        }
        for (owner, name, rel, line) in typed_lists {
            found.entry(Place::Member(owner, name)).or_insert((rel, line));
        }
        let mut lists: Vec<(String, u32, String)> = Vec::new();
        for (place, (wrel, wline)) in found {
            match place {
                Place::Member(o, v) => {
                    if declared_by_relation(sem, &rels, &o, &v) {
                        continue;
                    }
                    let Some(sig) = sem.var_decl(&o, &v) else { continue };
                    if sig.is_const || sig.file.is_empty() {
                        continue;
                    }
                    let at = format!("{}:{}", wrel, line_of(&wrel, wline));
                    lists.push((sig.file.clone(), sig.line, format!("{}/var/{} stores atoms/datums (e.g. {})", if o == "/" { "" } else { o.as_str() }, v, at)));
                }
                Place::ProcStatic(rel, line) => {
                    let at = format!("{}:{}", wrel, line_of(&wrel, wline));
                    lists.push((rel, line, format!("a proc's static list stores atoms/datums (e.g. {})", at)));
                }
            }
        }
        lists.sort();
        for (rel, line, msg) in lists {
            put(out, "list", &rel, line_of(&rel, line), msg);
        }
    }
}

pub fn register(reg: &mut Registry) {
    reg.add(StoredRefs);
}
