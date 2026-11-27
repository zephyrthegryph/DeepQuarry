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

use dm_syntax::{Expr, Statement};

use crate::lint::{Cx, Lint, Meta, Policy, Registry, RuleMeta, ScanKind, Sink};
use crate::lints::stored_refs::{collect_locals, declared_return_type, path_of, prefab_path, Place, ProcScope};
use crate::model::expr::{chain, strip_groups, Chain, Form, Hop, Root};
use crate::model::walk::{stmt_blocks, stmts, walk_block, Stmt};
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
pub(crate) fn return_type(sem: &Sem, ty: &str, name: &str) -> Option<String> {
    let t = sem.ty(ty)?;
    if let Some(declared) = declared_return_type(t, name) {
        return Some(declared);
    }
    let p = t.proc(name)?;
    let code = p.body()?;
    for st in stmts(code) {
        if let Stmt::Setting { name, value, .. } = &st.stmt {
            if *name == "SpacemanDMM_return_type" {
                if let Some(Chain { root: Root::Prefab { path, .. }, hops, .. }) = chain(value) {
                    if hops.is_empty() {
                        return Some(prefab_path(path));
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

    /// The static type of the chain `c` read as its root and its first `n` hops, or None.
    fn chain(&self, c: &Chain<'_>, n: usize) -> Option<String> {
        let mut cur: Option<String> = match &c.root {
            Root::Ident(n) => self.ident(n),
            Root::NewPrefab { path, .. } => Some(prefab_path(path)),
            Root::Group(inner) => self.expr(inner),
            Root::Call { name, .. } => match *name {
                "image" => Some("/image".to_string()),
                "mutable_appearance" => Some("/mutable_appearance".to_string()),
                _ => (if self.sc.owner == "/" { None } else { return_type(self.sem, self.sc.owner, name) }).or_else(|| return_type(self.sem, "/", name)),
            },
            _ => None,
        };
        for fo in &c.hops[..n] {
            let t = cur.clone()?;
            cur = match fo {
                Hop::Field { name, .. } => self.sem.var_decl(&t, name).map(|v| v.declared).filter(|t| !t.is_empty()),
                Hop::Call { name, .. } => return_type(self.sem, &t, name),
                _ => None,
            };
        }
        cur
    }

    fn expr(&self, e: &Expr) -> Option<String> {
        let c = chain(strip_groups(e))?;
        self.chain(&c, c.hops.len())
    }

    /// Untyped locals take the type of what they are initialised with, in statement order.
    fn infer(&mut self, b: &[Statement]) {
        for st in stmts(b) {
            // `var/a` and `var/a, b` alike: each declaration in statement order.
            if let Stmt::Vars(vs) = &st.stmt {
                for v in vs {
                    self.infer_one(&v.name, &v.type_path, v.value);
                }
            }
            for nb in stmt_blocks(&st.stmt) {
                self.infer(nb);
            }
        }
    }

    fn infer_one(&mut self, name: &str, declared: &[String], value: Option<&Expr>) {
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
        // Kept per file (`procs::per_file_in`): a file's rows read its own bodies, the model's structure (declared types) and the
        // return types bodies declare (`return_type`), which the context names.
        let ctx = crate::incr::mix(&[sem.structure_digest(), crate::sem::procs::return_settings_digest(sem)]);
        let per_file: Vec<Vec<(String, u32)>> = crate::sem::procs::per_file_in(sem, "image_dir_after_build-rows", ctx, |rel, defs| {
            let mut rows: Vec<(String, u32)> = Vec::new();
            if !rel.starts_with("code/") || cx.exempt(rel) || exempt.iter().any(|p| rel == p.as_str()) {
                return rows;
            }
            for (owner, v) in defs {
                let Some(code) = v.body() else { continue };
                let mut locals: HashMap<String, (String, Option<Place>)> = HashMap::new();
                for p in v.parameters().iter() {
                    locals.insert(p.name.to_string(), (path_of(&p.type_path), None));
                }
                collect_locals(code, rel, &mut locals);
                let mut typer = Typer { sem, sc: ProcScope { owner, locals } };
                typer.infer(code);
                walk_block(code, &mut |vis, site| {
                    let Form::Assign { lhs, .. } = &vis.form else { return };
                    let Some(c) = chain(strip_groups(lhs)) else { return };
                    let Some((last, _)) = c.hops.split_last() else { return };
                    let Hop::Field { name: f, .. } = last else { return };
                    if *f != "dir" {
                        return;
                    }
                    if typer.chain(&c, c.hops.len() - 1).is_some_and(|t| is_image(sem, &t)) {
                        rows.push((rel.to_string(), sem.line(Some(site))));
                    }
                });
            }
            rows
        });
        rows.extend(per_file.into_iter().flatten());
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
