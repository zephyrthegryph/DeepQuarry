//! `image_dir_after_build`: a `.dir` assigned to an `/image` or `/mutable_appearance` after it is built.
//!
//! A dir given to an image's constructor is kept when the image becomes an overlay or underlay; one assigned afterwards (to the image, to a
//! mutable appearance, or to the `.appearance` of either) is dropped, whatever its value and whatever the holder faces
//! (`dq_overlay_dir_renders`, `code/engine/present/appearance_builder.dm`): the shuttle corners drew a lighting state in a cardinal dir, a pink X.
//!
//! The rule is an assignment (`=` or a compound op) whose target is `<receiver>.dir`, where the receiver's static type is `/image`,
//! `/mutable_appearance` or a subtype. The receiver's type is what the semantic model can say: a typed local, parameter or var, `src`, a field
//! chain, `new /image(...)`, a call to a proc with a declared return type (`as /image` or `RETURN_TYPE(/image)`), and an untyped local
//! initialised from one of those or from `image(...)` / `mutable_appearance(...)`. A receiver the model cannot type (an untyped parameter, a
//! reassigned untyped local, an index, a ternary) is not judged. Reported at the assignment's line. Hard ban, no baseline.

use std::collections::HashMap;

use dreammaker::ast::{Block, Expression, Follow, ProcReturnType, Statement, Term};

use crate::lint::{Cx, Lint, Meta, Policy, Registry, RuleMeta, ScanKind, Sink};
use crate::lints::stored_refs::{collect_locals, path_of, Place, ProcScope};
use crate::sem::ast::{stmt_blocks, strip_parens, walk_block};
use crate::sem::procs::engine_line;
use crate::sem::Sem;
use crate::tree::CODE_DM;

const HINT: &str = "a dir assigned to an image or mutable_appearance after it is built is dropped when it becomes an overlay or underlay, whatever the value. \
Build the image with its dir: image(icon, loc, icon_state, layer, dir), image(of, dir = d) or look_overlay_image(..., dir =). A mutable_appearance has no \
dir argument: use an image, or leave the dir to the holder. dq_overlay_dir_renders holds the rule";

static META: Meta = Meta {
    name: "image_dir_after_build",
    group: "",
    label: "image_dir_after_build",
    legacy: "",
    select: CODE_DM,
    scan: ScanKind::Tree,
    policy: Policy::Hard,
    rules: &[RuleMeta { name: "dir_after_build", hint: HINT }],
    allow: &[],
    lists: &["exempt_files"],
};

struct ImageDirAfterBuild;

fn is_image(sem: &Sem, ty: &str) -> bool {
    !ty.is_empty() && (sem.is_subtype(ty, "/image") || sem.is_subtype(ty, "/mutable_appearance"))
}

/// A proc's declared return type: `as /type`, else a `RETURN_TYPE(/type)` (`set SpacemanDMM_return_type = /type`) in its body.
fn return_type(sem: &Sem, ty: &str, name: &str) -> Option<String> {
    let t = sem.ty(ty)?;
    if let Some(d) = t.get_proc_declaration(name) {
        if let ProcReturnType::TypePath(p) = &d.return_type {
            if !p.is_empty() {
                return Some(format!("/{}", p.iter().map(|s| s.as_str()).collect::<Vec<_>>().join("/")));
            }
        }
    }
    let p = t.get_proc(name)?;
    let code = p.get().code.as_ref()?;
    for st in code.iter() {
        if let Statement::Setting { name, value, .. } = &st.elem {
            if name.as_str() == "SpacemanDMM_return_type" {
                if let Expression::Base { term, follow } = value {
                    if follow.is_empty() {
                        if let Term::Prefab(prefab) = &term.elem {
                            let parts: Vec<String> = prefab.path.iter().map(|(_, n)| n.to_string()).collect();
                            return Some(format!("/{}", parts.join("/")));
                        }
                    }
                }
            }
        }
    }
    None
}

struct Typer<'a> {
    sem: &'a Sem,
    sc: ProcScope<'a>,
}

impl<'a> Typer<'a> {
    fn ident(&self, n: &str) -> Option<String> {
        match n {
            "src" => Some(self.sc.owner.to_string()).filter(|o| o != "/"),
            "usr" => Some("/mob".to_string()),
            _ => {
                if let Some((t, _)) = self.sc.locals.get(n) {
                    return Some(t.clone()).filter(|t| !t.is_empty());
                }
                if self.sc.owner != "/" {
                    if let Some(v) = self.sem.var_decl(self.sc.owner, n) {
                        return Some(v.declared).filter(|t| !t.is_empty());
                    }
                }
                self.sem.var_decl("/", n).map(|v| v.declared).filter(|t| !t.is_empty())
            }
        }
    }

    /// The static type of the chain `term` then `follow`, or None.
    fn chain(&self, term: &Term, follow: &[dreammaker::ast::Spanned<Follow>]) -> Option<String> {
        let mut cur: Option<String> = match term {
            Term::Ident(n) => self.ident(n),
            Term::NewPrefab { prefab, .. } => Some(path_of(&prefab.path.iter().map(|(_, n)| n.to_string()).collect::<Vec<_>>())),
            Term::Expr(inner) => self.expr(inner),
            Term::Call(n, _) => match n.as_str() {
                "image" => Some("/image".to_string()),
                "mutable_appearance" => Some("/mutable_appearance".to_string()),
                _ => (if self.sc.owner == "/" { None } else { return_type(self.sem, self.sc.owner, n) }).or_else(|| return_type(self.sem, "/", n)),
            },
            Term::GlobalCall(n, _) => return_type(self.sem, "/", n),
            _ => None,
        };
        for fo in follow {
            let c = cur.clone()?;
            cur = match &fo.elem {
                Follow::Field(_, f) => self.sem.var_decl(&c, f).map(|v| v.declared).filter(|t| !t.is_empty()),
                Follow::Call(_, n, _) => return_type(self.sem, &c, n),
                _ => None,
            };
        }
        cur
    }

    fn expr(&self, e: &Expression) -> Option<String> {
        match strip_parens(e) {
            Expression::Base { term, follow } => self.chain(&term.elem, follow),
            _ => None,
        }
    }

    /// Untyped locals take the type of what they are initialised with, in statement order.
    fn infer(&mut self, b: &Block) {
        for st in b.iter() {
            match &st.elem {
                Statement::Var(v) => self.infer_one(&v.name, &v.var_type.type_path, v.value.as_ref()),
                Statement::Vars(vs) => {
                    for v in vs {
                        self.infer_one(&v.name, &v.var_type.type_path, v.value.as_ref());
                    }
                }
                _ => {}
            }
            for nb in stmt_blocks(&st.elem) {
                self.infer(nb);
            }
        }
    }

    fn infer_one(&mut self, name: &str, declared: &[String], value: Option<&Expression>) {
        if !declared.is_empty() {
            return;
        }
        let Some(t) = value.and_then(|v| self.expr(v)) else { return };
        self.sc.locals.insert(name.to_string(), (t, None));
    }
}

impl Lint for ImageDirAfterBuild {
    fn meta(&self) -> &Meta {
        &META
    }

    fn scan_tree(&self, cx: &Cx, out: &mut Sink) {
        let Some(sem) = cx.sem() else {
            out.note("image_dir_after_build: the semantic model is unavailable; nothing checked");
            return;
        };
        let sem: &Sem = &sem;
        let root = &cx.tree.root;
        let exempt = cx.list("exempt_files");
        let mut rows: Vec<(String, u32)> = Vec::new();
        for ty in sem.objtree.iter_types() {
            let owner = if ty.get().path.is_empty() { "/".to_string() } else { ty.get().path.clone() };
            for (_, tp) in ty.get().procs.iter() {
                for v in tp.value.iter() {
                    let Some(code) = v.code.as_ref() else { continue };
                    let Some(rel) = sem.file_of(v.location) else { continue };
                    if !rel.starts_with("code/") || cx.exempt(rel) || exempt.iter().any(|p| rel == p.as_str()) {
                        continue;
                    }
                    let mut locals: HashMap<String, (String, Option<Place>)> = HashMap::new();
                    for p in v.parameters.iter() {
                        locals.insert(p.name.to_string(), (path_of(&p.var_type.type_path), None));
                    }
                    collect_locals(code, rel, &mut locals);
                    let mut typer = Typer { sem, sc: ProcScope { owner: &owner, locals } };
                    typer.infer(code);
                    walk_block(code, &mut |e, line| {
                        let Expression::AssignOp { lhs, .. } = e else { return };
                        let Expression::Base { term, follow } = strip_parens(lhs) else { return };
                        let Some((last, rest)) = follow.split_last() else { return };
                        let Follow::Field(_, f) = &last.elem else { return };
                        if f.as_str() != "dir" {
                            return;
                        }
                        if typer.chain(&term.elem, rest).is_some_and(|t| is_image(sem, &t)) {
                            rows.push((rel.to_string(), line));
                        }
                    });
                }
            }
        }
        rows.sort();
        rows.dedup();
        for (rel, line) in rows {
            out.site_in_msg("dir_after_build", &rel, engine_line(root, &rel, line) as usize, "`.dir` assigned to an image or mutable_appearance after it is built".to_string());
        }
    }
}

pub fn register(reg: &mut Registry) {
    reg.add(ImageDirAfterBuild);
}
