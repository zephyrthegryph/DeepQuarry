//! Constructor arguments on the typed tree (doc/rewrite/final_api.html section 6, "param() and make()").
//!
//! `new /T(loc, a, b)` hands `a` (position 1) and `b` (position 2) to the instance. A position is taken when
//!
//! * `/T` or an ancestor declares `param(nameof(v), pos = N)` (the engine writes it before init), or
//! * a `New()` or `Initialize()` definition of `/T` or an ancestor (below the framework's `/atom` ones) reads the parameter at that
//!   position, or reads `args` (the legacy form, kept with `ALLOW(init/CTOR_ARGS)` until it becomes a param).
//!
//! An argument no one takes is dead: [`dead_args`] lists every `new` (a `new /T(...)`, or `var/T/x = new(...)`) that passes one.
//! [`forward_only`] lists the `New()` / `Initialize()` overrides whose trailing extra parameters are never read except to hand them
//! to `..()`: dropping them changes nothing (`..()` with no arguments passes the caller's).

use std::collections::{BTreeMap, BTreeSet, HashMap};

use dm_syntax::{Expr, Statement};

use super::procs::engine_line;
use super::Sem;
use crate::model::expr::{as_ident, chain, literal, Form, Lit, Root};
use crate::model::walk::{stmt_blocks, stmt_exprs, stmts, walk_block, walk_expr, ForInit, Stmt};

/// A `new` that passes an argument no one takes.
#[derive(Clone, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub struct DeadArg {
    pub rel: String,
    pub line: u32,
    pub ty: String,
    /// How many arguments after the location the call passes.
    pub passed: usize,
    /// The dead positions (1-based after the location).
    pub dead: Vec<usize>,
}

/// An override whose trailing extra parameters only reach `..()`.
#[derive(Clone, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub struct ForwardOnly {
    pub rel: String,
    pub line: u32,
    pub owner: String,
    pub name: String,
    /// The parameter names that can go (trailing, in order).
    pub params: Vec<String>,
}

/// The framework's own constructors, which hand every argument on (`/atom/New(loc, ...)` reads `args` for params).
fn framework(owner: &str) -> bool {
    matches!(owner, "/" | "/datum" | "/atom" | "/atom/movable")
}

const CTORS: &[&str] = &["New", "Initialize"];

/// Whether a body uses `name` other than as a bare argument of `..()` (which only forwards it).
fn reads_outside_parent_call(code: &[Statement], name: &str) -> bool {
    let mut uses = 0usize;
    let mut forwards = 0usize;
    walk_block(code, &mut |v, _| {
        if let Form::Chain(c) = &v.form {
            match &c.root {
                Root::Ident(n) if *n == name => uses += 1,
                Root::ParentCall(args) => forwards += args.iter().filter(|a| bare_ident(a) == Some(name)).count(),
                _ => {}
            }
        }
    });
    uses > forwards
}

fn bare_ident(e: &Expr) -> Option<&str> {
    as_ident(e)
}

/// The parameter at `pos` (0 is the location / mapload) of each constructor definition of `ty` and its ancestors: does one read it?
struct Ctors<'s> {
    sem: &'s Sem,
    params: HashMap<String, BTreeSet<usize>>,
    memo: std::cell::RefCell<HashMap<(String, usize), bool>>,
}

impl<'s> Ctors<'s> {
    fn lineage(&self, ty: &str) -> Vec<String> {
        let mut out = Vec::new();
        let mut cur = Some(ty.to_string());
        while let Some(t) = cur {
            if framework(&t) {
                break;
            }
            cur = self.sem.parent_of(&t);
            out.push(t);
        }
        out
    }

    fn taken(&self, ty: &str, pos: usize) -> bool {
        if let Some(&v) = self.memo.borrow().get(&(ty.to_string(), pos)) {
            return v;
        }
        let mut v = false;
        'outer: for t in self.lineage(ty) {
            if self.params.get(&t).is_some_and(|s| s.contains(&pos)) {
                v = true;
                break;
            }
            let Some(tr) = self.sem.ty(&t) else { continue };
            for name in CTORS {
                for def in tr.proc_definitions(name) {
                    let Some(code) = def.body() else { continue };
                    if reads_outside_parent_call(code, "args") {
                        v = true;
                        break 'outer;
                    }
                    if let Some(p) = def.parameters().get(pos) {
                        if reads_outside_parent_call(code, p.name.as_str()) {
                            v = true;
                            break 'outer;
                        }
                    }
                }
            }
        }
        self.memo.borrow_mut().insert((ty.to_string(), pos), v);
        v
    }
}

fn is_null(e: &Expr) -> bool {
    matches!(chain(e), Some(c) if c.hops.is_empty() && matches!(&c.root, Root::Literal(t) if matches!(literal(t), Lit::Null)))
}

/// The absolute path of a `new /a/b` (no initializer block), the names joined by `/` whatever operator spells them.
fn absolute_path(path: &str, has_vars: bool) -> Option<String> {
    if has_vars || !path.starts_with('/') {
        return None;
    }
    Some(format!("/{}", path.split(['/', '.', ':']).filter(|s| !s.is_empty()).collect::<Vec<_>>().join("/")))
}

/// `type -> declared param(pos = N)` positions, from the CAPABILITIES blocks (see `lints::lifeforms`).
pub type ParamPositions = HashMap<String, BTreeSet<usize>>;

/// Every `new` passing a dead argument. Only atoms (the location is the first argument) are judged.
pub fn dead_args(sem: &Sem, params: &ParamPositions) -> Vec<DeadArg> {
    let ctors = Ctors { sem, params: params.clone(), memo: Default::default() };
    let mut out: BTreeMap<(String, u32, String), DeadArg> = BTreeMap::new();
    for t in sem.m().types() {
        for pname in t.proc_names() {
            for def in t.proc_definitions(pname) {
                let Some(code) = def.body() else { continue };
                let Some(rel) = sem.file_of(def.site()) else { continue };
                let rel = rel.as_str();
                let mut sites: Vec<(u32, String, Vec<bool>)> = Vec::new();
                news(sem, code, &mut |line, ty, given| sites.push((line, ty, given)));
                for (line, ty, given) in sites {
                    let passed = given.len();
                    if passed < 2 || !sem.is_subtype(&ty, "/atom") {
                        continue;
                    }
                    // A literal null is no argument (the param keeps its default), so it is never dead.
                    let dead: Vec<usize> = (1..passed).filter(|pos| given[*pos] && !ctors.taken(&ty, *pos)).collect();
                    if dead.is_empty() {
                        continue;
                    }
                    let line = engine_line(&sem.root, rel, line);
                    out.insert((rel.to_string(), line, ty.clone()), DeadArg { rel: rel.to_string(), line, ty, passed: passed - 1, dead });
                }
            }
        }
    }
    out.into_values().collect()
}

/// The `new` expressions of a body: `(line, type, for each argument whether it is given (not a literal null))`, with `var/T/x = new(...)` typed by its declaration.
fn news(sem: &Sem, code: &[Statement], f: &mut dyn FnMut(u32, String, Vec<bool>)) {
    for st in stmts(code) {
        let mut exprs: Vec<&Expr> = stmt_exprs(&st.stmt);
        // An assignment statement has no node of its own: its two sides are the expressions.
        if let Stmt::Expr(Form::Assign { lhs, rhs, .. }, None) = &st.stmt {
            exprs.push(lhs);
            exprs.push(rhs);
        }
        if let Stmt::ForLoop { init, inc, .. } = &st.stmt {
            match init {
                Some(ForInit::Var(d)) => exprs.extend(d.value),
                Some(ForInit::Expr(e)) => exprs.push(e),
                None => {}
            }
            exprs.extend(inc.iter().copied());
        }
        for e in exprs {
            walk_expr(e, &mut |x| {
                if let Form::Chain(c) = &x.form {
                    if let Root::NewPrefab { path, vars, args: Some(args) } = &c.root {
                        if let Some(ty) = absolute_path(path, !vars.is_empty()) {
                            f(sem.line(Some(c.root_site())), ty, args.iter().map(|a| !is_null(a)).collect());
                        }
                    }
                }
            });
        }
        if let Stmt::Vars(vs) = &st.stmt {
            for v in vs {
                if v.type_path.is_empty() {
                    continue;
                }
                let Some(value) = v.value else { continue };
                if let Some(c) = chain(value) {
                    if c.hops.is_empty() {
                        if let Root::NewImplicit { args: Some(args) } = &c.root {
                            f(sem.line(Some(c.root_site())), format!("/{}", v.type_path.join("/")), args.iter().map(|a| !is_null(a)).collect());
                        }
                    }
                }
            }
        }
        for nb in stmt_blocks(&st.stmt) {
            news(sem, nb, f);
        }
    }
}

/// Every `New()` / `Initialize()` override (below the framework) whose trailing extra parameters are only forwarded to `..()` or unused.
pub fn forward_only(sem: &Sem) -> Vec<ForwardOnly> {
    let mut out = Vec::new();
    for t in sem.m().types() {
        let owner = t.path().to_string();
        if framework(&owner) || !sem.is_subtype(&owner, "/atom") {
            continue;
        }
        for name in CTORS {
            for def in t.proc_definitions(name) {
                let Some(code) = def.body() else { continue };
                let parameters = def.parameters();
                if parameters.len() < 2 || reads_outside_parent_call(code, "args") {
                    continue;
                }
                let mut drop: Vec<String> = Vec::new();
                for p in parameters.iter().skip(1).rev() {
                    // `...` takes any further arguments and hands them on: it is the form, not a parameter to drop.
                    if p.name.as_str() == "..." || reads_outside_parent_call(code, p.name.as_str()) {
                        break;
                    }
                    drop.push(p.name.to_string());
                }
                if drop.is_empty() {
                    continue;
                }
                drop.reverse();
                let Some(rel) = sem.file_of(def.site()) else { continue };
                let line = engine_line(&sem.root, &rel, sem.line(def.site()));
                out.push(ForwardOnly { rel, line, owner: owner.clone(), name: name.to_string(), params: drop });
            }
        }
    }
    out.sort();
    out
}

#[cfg(test)]
mod tests {
    use super::{dead_args, forward_only, ParamPositions};
    use crate::sem::Sem;
    use crate::tree::{SourceFile, Tree};

    fn model(text: &str) -> (tempfile::TempDir, Sem) {
        let root = tempfile::tempdir().unwrap();
        std::fs::create_dir_all(root.path().join("code")).unwrap();
        std::fs::write(root.path().join("code/probe.dm"), text).unwrap();
        let tree = Tree::from_files(vec![SourceFile::from_text("code/probe.dm", text)]);
        let sem = Sem::build(root.path(), &tree).unwrap();
        (root, sem)
    }

    const SRC: &str = concat!(
        "/atom/New(loc, ...)\n",
        "\treturn\n",
        "/atom/proc/Initialize(mapload, ...)\n",
        "\treturn\n",
        "/obj/reads/Initialize(mapload, amount)\n",
        "\t. = ..()\n",
        "\tamount += 1\n",
        "/obj/forwards/Initialize(mapload, colour)\n",
        "\treturn ..(mapload, colour)\n",
        "/obj/forwards/child\n",
        "/obj/declared\n",
        "/proc/make_them(loc)\n",
        "\tnew /obj/reads(loc, 2)\n",
        "\tnew /obj/forwards/child(loc, \"red\")\n",
        "\tnew /obj/declared(loc, 1, null)\n",
        "\tvar/obj/reads/R = new(loc, 3, 4)\n",
        "\treturn R\n",
    );

    #[test]
    fn dead_positions_are_the_ones_nothing_takes() {
        let (_root, sem) = model(SRC);
        let mut params = ParamPositions::new();
        params.entry("/obj/declared".to_string()).or_default().insert(1);
        let found: Vec<(u32, String, Vec<usize>)> = dead_args(&sem, &params).into_iter().map(|d| (d.line, d.ty, d.dead)).collect();
        assert_eq!(found, vec![(14, "/obj/forwards/child".to_string(), vec![1]), (16, "/obj/reads".to_string(), vec![2])]);
    }

    #[test]
    fn an_override_that_only_forwards_is_found() {
        let (_root, sem) = model(SRC);
        let found: Vec<(String, Vec<String>)> = forward_only(&sem).into_iter().map(|f| (f.owner, f.params)).collect();
        assert_eq!(found, vec![("/obj/forwards".to_string(), vec!["colour".to_string()])]);
    }
}
