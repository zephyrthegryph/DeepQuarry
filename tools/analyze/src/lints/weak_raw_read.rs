//! `weak_raw_read`: a weak relation var is read or written raw, not through its generated accessor
//! (doc/rewrite/proposals/relations.md, D5).
//!
//! A `ref_one` / `ref_many(nameof(v), ..., weak = TRUE)` var holds a handle (`handle_of()` number, or a list of them), never the target. The
//! target is read with the generated accessor `v()` and written with `rel_set` / `rel_add` / `rel_remove` / `rel_clear`. A raw read of
//! `v` sees the handle: `istype()` fails, `.name` is runtime-null, `== target` is false. A hard ban, no baseline.
//!
//! The holder of a read comes from the receiver's static type (`src` and bare names use the proc's own type). A receiver the model cannot
//! type is not judged: the lint is exact where it can see the type and silent where it cannot.

use std::collections::{HashMap, HashSet};

use crate::lint::{Cx, Lint, Meta, Policy, Registry, RuleMeta, ScanKind, Sink};
use crate::lints::rel_write_undeclared::walk_block_pub;
use crate::lints::stored_refs::{collect_locals, path_of, Kinds, ProcScope, Walker};
use crate::model::expr::{Form, Hop, Root};
use crate::model::walk::walk_form;
use crate::model::Site;
use crate::sem::procs::engine_line;
use crate::sem::Sem;
use crate::tree::{SourceFile, CODE_DM};

const HINT: &str = "a weak relation var holds a handle, not the target: read it with its generated accessor v() and write it with rel_set / rel_add / rel_remove / rel_clear. \
doc/rewrite/proposals/relations.md D5";

static META: Meta = Meta {
    name: "weak_raw_read",
    group: "",
    label: "weak_raw_read",
    legacy: "",
    select: CODE_DM,
    scan: ScanKind::Tree,
    policy: Policy::Hard,
    rules: &[RuleMeta { name: "raw", hint: HINT }],
    allow: &[],
    lists: &[],
};

struct WeakRawRead;

/// Weak declarations by var name: name -> the types whose CAPABILITIES block declares it `weak = TRUE`. Each file's declarations
/// are kept per file (`crate::incr`), folded in file order.
fn weak_index(cx: &Cx) -> HashMap<String, Vec<String>> {
    let header = crate::pat!(r"^\s*CAPABILITIES(?:_PART)?\(\s*(/[\w/]+)\s*[,)]");
    let decl = crate::pat!(r"\bref_(?:one|many)\(\s*nameof\(\s*(\w+)\s*\)[^\n]*\bweak\s*=\s*TRUE");
    let files: Vec<&SourceFile> = cx.files().into_iter().filter(|f| f.rel.ends_with(".dm")).collect();
    let per_file: Vec<Vec<(String, String)>> = crate::incr::facts("weak_raw_read-decls", &files, |f| {
        let mut found = Vec::new();
        let mut owner: Option<String> = None;
        for line in f.code().lines() {
            if let Some(c) = header.captures(line) {
                owner = Some(c.s(1).to_string());
                continue;
            }
            if !line.starts_with(char::is_whitespace) && !line.trim().is_empty() {
                owner = None;
            }
            let Some(o) = owner.as_ref() else { continue };
            if let Some(c) = decl.captures(line) {
                found.push((c.s(1).to_string(), o.clone()));
            }
        }
        found
    });
    let mut out: HashMap<String, Vec<String>> = HashMap::new();
    for (var, o) in per_file.into_iter().flatten() {
        let types = out.entry(var).or_default();
        if !types.contains(&o) {
            types.push(o);
        }
    }
    out
}

fn compatible(sem: &Sem, declarers: &[String], ty: &str) -> bool {
    declarers.iter().any(|d| d == ty || sem.is_subtype(ty, d) || sem.is_subtype(d, ty))
}

impl Lint for WeakRawRead {
    fn meta(&self) -> &Meta {
        &META
    }

    fn scan_tree(&self, cx: &Cx, out: &mut Sink) {
        let Some(sem) = cx.sem() else {
            out.note("weak_raw_read: the semantic model is unavailable; nothing checked");
            return;
        };
        let sem: &Sem = &sem;
        let weak = weak_index(cx);
        if weak.is_empty() {
            return;
        }
        let root = &cx.tree.root;
        let mut seen: HashSet<(String, u32, String)> = HashSet::new();
        let mut found: Vec<(String, u32, String)> = Vec::new();
        // Each file's raw reads, kept per file (`procs::per_file_in`): a judgement reads the file's own bodies, the model's
        // structure (types, var and proc declarations) and the weak index, which the context names.
        let mut weak_rows: Vec<(&String, &Vec<String>)> = weak.iter().collect();
        weak_rows.sort();
        let ctx = crate::incr::mix(&[sem.structure_digest(), crate::incr::ctx_key(&weak_rows)]);
        let per_file: Vec<Vec<(String, u32, String, String)>> = crate::sem::procs::per_file_in(sem, "weak_raw_read-reads", ctx, |rel, defs| {
            let mut hits_out: Vec<(String, u32, String, String)> = Vec::new();
            if cx.exempt(rel) {
                return hits_out;
            }
            // The type cache is per file (a judgement runs on many threads).
            let kinds = Kinds { sem, exempt_types: Vec::new(), registry: Vec::new(), cache: Default::default() };
            let w = Walker { sem, kinds: &kinds };
            for (owner, v) in defs {
                let Some(code) = v.body() else { continue };
                let mut locals = HashMap::new();
                for p in v.parameters().iter() {
                    locals.insert(p.name.to_string(), (path_of(&p.type_path), None));
                }
                collect_locals(code, rel, &mut locals);
                let sc = ProcScope { owner, locals };
                walk_block_pub(code, &mut |top, node, site| {
                    let line = sem.line(Some(site));
                    // Everything inside a nameof(...) names the var, it does not read it: the expanded-offset ranges of its arguments
                    // (an expression's address is not stable across the walk's passes, an interpolated part being parsed on the fly,
                    // but its site is).
                    let mut named: Vec<(usize, usize)> = Vec::new();
                    // The walk's own site for the root: where its node starts (an assignment statement has none: the statement's).
                    let root_site = node.map_or(site, |e| Site(e.span.start as u32));
                    walk_form(top.clone(), node, root_site, 0, &mut |x| {
                        if let (Form::Chain(c), Some(n)) = (&x.form, x.node) {
                            if let Root::Call { name: "nameof", args } = &c.root {
                                let base = x.site.0 as usize - n.span.start;
                                for a in args.iter() {
                                    named.push((base + a.span.start, base + a.span.end));
                                }
                            }
                        }
                    });
                    walk_form(top, node, root_site, 0, &mut |x| {
                        let at = x.site.0 as usize;
                        if named.iter().any(|(s, e)| *s <= at && at < *e) {
                            return;
                        }
                        let Form::Chain(c) = &x.form else { return };
                        let mut hits: Vec<(String, Option<String>)> = Vec::new();
                        if let Root::Ident(n) = &c.root {
                            if weak.contains_key(*n) && !sc.locals.contains_key(*n) {
                                hits.push((n.to_string(), Some(owner.clone())));
                            }
                        }
                        for (i, fo) in c.hops.iter().enumerate() {
                            let Hop::Field { name: f, .. } = fo else { continue };
                            if !weak.contains_key(*f) {
                                continue;
                            }
                            hits.push((f.to_string(), w.type_of(&sc, c.prefix_node(i))));
                        }
                        for (var, holder) in hits {
                            let Some(holder) = holder.filter(|t| !t.is_empty() && t != "/") else { continue };
                            if !compatible(sem, &weak[&var], &holder) {
                                continue;
                            }
                            let at = engine_line(root, rel, line) as u32;
                            hits_out.push((rel.to_string(), at, var.clone(), format!("`{}` of {} is a weak relation read raw; use {}()", var, holder, var)));
                        }
                    });
                });
            }
            hits_out
        });
        for (rel, at, var, msg) in per_file.into_iter().flatten() {
            if seen.insert((rel.clone(), at, var)) {
                found.push((rel, at, msg));
            }
        }
        found.sort();
        for (rel, line, msg) in found {
            out.site_in_msg("raw", &rel, line as usize, msg);
        }
    }
}

pub fn register(reg: &mut Registry) {
    reg.add(WeakRawRead);
}
