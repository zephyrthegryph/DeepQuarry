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

use dreammaker::ast::{Block, Expression, PathOp, Statement, Term};

use super::ast::{stmt_blocks, stmt_exprs, walk_block, walk_expr};
use super::procs::engine_line;
use super::Sem;

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
fn reads_outside_parent_call(code: &Block, name: &str) -> bool {
    let mut uses = 0usize;
    let mut forwards = 0usize;
    walk_block(code, &mut |e, _| {
        if let Expression::Base { term, .. } = e {
            match &term.elem {
                Term::Ident(n) if n.as_str() == name => uses += 1,
                Term::ParentCall(args) => forwards += args.iter().filter(|a| bare_ident(a) == Some(name)).count(),
                _ => {}
            }
        }
    });
    uses > forwards
}

fn bare_ident(e: &Expression) -> Option<&str> {
    match e {
        Expression::Base { term, follow } if follow.is_empty() => match &term.elem {
            Term::Ident(n) => Some(n.as_str()),
            _ => None,
        },
        _ => None,
    }
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
                let Some(tp) = tr.get().procs.get(*name) else { continue };
                for def in tp.value.iter() {
                    let Some(code) = def.code.as_ref() else { continue };
                    if reads_outside_parent_call(code, "args") {
                        v = true;
                        break 'outer;
                    }
                    if let Some(p) = def.parameters.get(pos) {
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

fn is_null(e: &Expression) -> bool {
    matches!(e, Expression::Base { term, follow } if follow.is_empty() && matches!(term.elem, Term::Null))
}

fn absolute_path(p: &dreammaker::ast::Prefab) -> Option<String> {
    if !p.vars.is_empty() || p.path.first().map(|(op, _)| *op != PathOp::Slash).unwrap_or(true) {
        return None;
    }
    Some(format!("/{}", p.path.iter().map(|(_, n)| n.as_str()).collect::<Vec<_>>().join("/")))
}

/// `type -> declared param(pos = N)` positions, from the CAPABILITIES blocks (see `lints::lifeforms`).
pub type ParamPositions = HashMap<String, BTreeSet<usize>>;

/// Every `new` passing a dead argument. Only atoms (the location is the first argument) are judged.
pub fn dead_args(sem: &Sem, params: &ParamPositions) -> Vec<DeadArg> {
    let ctors = Ctors { sem, params: params.clone(), memo: Default::default() };
    let mut out: BTreeMap<(String, u32, String), DeadArg> = BTreeMap::new();
    for t in sem.objtree.iter_types() {
        for (_, tp) in t.get().procs.iter() {
            for def in tp.value.iter() {
                let Some(code) = def.code.as_ref() else { continue };
                let Some(rel) = sem.file_of(def.location) else { continue };
                let mut sites: Vec<(u32, String, Vec<bool>)> = Vec::new();
                news(code, &mut |line, ty, given| sites.push((line, ty, given)));
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
fn news(code: &Block, f: &mut dyn FnMut(u32, String, Vec<bool>)) {
    for st in code.iter() {
        let mut exprs: Vec<&Expression> = Vec::new();
        match &st.elem {
            Statement::If { arms, .. } => exprs.extend(arms.iter().map(|(c, _)| &c.elem)),
            other => exprs.extend(stmt_exprs(other)),
        }
        if let Statement::ForLoop { init, inc, .. } = &st.elem {
            for s in [init, inc].into_iter().flatten() {
                exprs.extend(stmt_exprs(s));
            }
        }
        for e in exprs {
            walk_expr(e, &mut |x| {
                if let Expression::Base { term, .. } = x {
                    if let Term::NewPrefab { prefab, args: Some(args) } = &term.elem {
                        if let Some(ty) = absolute_path(prefab) {
                            f(term.location.line, ty, args.iter().map(|a| !is_null(a)).collect());
                        }
                    }
                }
            });
        }
        let typed: Vec<(&[String], &Option<Expression>)> = match &st.elem {
            Statement::Var(v) => vec![(&v.var_type.type_path[..], &v.value)],
            Statement::Vars(vs) => vs.iter().map(|v| (&v.var_type.type_path[..], &v.value)).collect(),
            _ => Vec::new(),
        };
        for (name_type, value) in typed {
            if name_type.is_empty() {
                continue;
            }
            if let Some(Expression::Base { term, follow }) = value {
                if follow.is_empty() {
                    if let Term::NewImplicit { args: Some(args) } = &term.elem {
                        f(term.location.line, format!("/{}", name_type.join("/")), args.iter().map(|a| !is_null(a)).collect());
                    }
                }
            }
        }
        for nb in stmt_blocks(&st.elem) {
            news(nb, f);
        }
    }
}

/// Every `New()` / `Initialize()` override (below the framework) whose trailing extra parameters are only forwarded to `..()` or unused.
pub fn forward_only(sem: &Sem) -> Vec<ForwardOnly> {
    let mut out = Vec::new();
    for t in sem.objtree.iter_types() {
        let owner = if t.get().path.is_empty() { "/".to_string() } else { t.get().path.clone() };
        if framework(&owner) || !sem.is_subtype(&owner, "/atom") {
            continue;
        }
        for name in CTORS {
            let Some(tp) = t.get().procs.get(*name) else { continue };
            for def in tp.value.iter() {
                let Some(code) = def.code.as_ref() else { continue };
                if def.parameters.len() < 2 || reads_outside_parent_call(code, "args") {
                    continue;
                }
                let mut drop: Vec<String> = Vec::new();
                for p in def.parameters.iter().skip(1).rev() {
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
                let Some(rel) = sem.file_of(def.location) else { continue };
                out.push(ForwardOnly { rel: rel.to_string(), line: engine_line(&sem.root, rel, def.location.line), owner: owner.clone(), name: name.to_string(), params: drop });
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
