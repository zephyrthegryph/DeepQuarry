//! `untyped_member`: a member read or write through a receiver with no static type, where DreamMaker can bind a static variable.
//!
//! DreamMaker resolves `recv.name` at compile time when it can. A receiver whose static type it knows (a typed local, parameter, field, `src`,
//! `usr`, `new /type`) reads that type's variable. A receiver it cannot type (an untyped local or parameter, a proc result, an index, a ternary)
//! gets a lookup by name over the whole tree; when `name` is declared as a `static` (or `global`) var on any type, that lookup can bind the static
//! declaration instead of the instance variable the object has, and which declaration wins depends on the order of DreamMaker's class table
//! (probes: `doc/rewrite/native_compiler_issues.md`, "untyped receiver"). Native answers the instance variable, so the two compilers disagree and
//! the game is wrong under DreamMaker.
//!
//! The rule is the condition under which DreamMaker can pick a static: the receiver has no static type, and the member name is declared `static`
//! or `global` on at least one type (a name declared on several types is covered by the same test: one static declaration among them is enough).
//! A proc's `RETURN_TYPE` does not type its result for DreamMaker, so a call result is untyped here too. Hard ban, no baseline: give the receiver
//! its type (a typed local, or a cast through a typed local after `istype`).

use std::collections::{BTreeSet, HashMap};

use crate::lint::{Cx, Lint, Meta, Policy, Registry, RuleMeta, ScanKind, Sink};
use crate::lints::stored_refs::{collect_locals, path_of, prefab_path, Place, ProcScope};
use crate::model::expr::{chain, strip_groups, Form, Hop, Root};
use crate::model::walk::walk_block;
use crate::sem::procs::engine_line;
use crate::sem::Sem;
use crate::tree::CODE_DM;

const HINT: &str = "the receiver has no static type and the member name is declared static/global on some type, so DreamMaker may bind the static. Give the receiver \
its type: a typed local (`var/obj/belly/B = x`, assigned after `istype`) or a typed parameter. A proc's RETURN_TYPE does not type its result for DreamMaker. \
doc/rewrite/native_compiler_issues.md, untyped receiver";

static META: Meta = Meta {
    name: "untyped_member",
    group: "",
    label: "untyped_member",
    legacy: "",
    select: CODE_DM,
    scan: ScanKind::Tree,
    policy: Policy::Hard,
    rules: &[RuleMeta { name: "static_member", hint: HINT }],
    allow: &[],
    lists: &[],
};

struct UntypedMember;

/// Every name declared `static` or `global` on any type (the root included).
pub(crate) fn static_names(sem: &Sem) -> BTreeSet<String> {
    let mut out = BTreeSet::new();
    for ty in sem.m().types() {
        for name in ty.var_names() {
            if !ty.declares_var(&name) {
                continue;
            }
            if ty.var_declaration(&name).is_some_and(|d| d.is_static()) {
                out.insert(name);
            }
        }
    }
    out
}

fn declared(sem: &Sem, ty: &str, name: &str) -> Option<String> {
    sem.var_decl(ty, name).and_then(|v| if v.declared.is_empty() { None } else { Some(v.declared) })
}

/// The declared type of an identifier in a proc, or None when DreamMaker has none for it.
fn ident_type(sem: &Sem, sc: &ProcScope, n: &str) -> Option<String> {
    match n {
        "src" => Some(sc.owner.to_string()).filter(|o| o != "/"),
        "usr" => Some("/mob".to_string()),
        "world" => Some("/world".to_string()),
        // `global.x` names a global var: the root type answers it.
        "global" => Some("/".to_string()),
        _ => {
            if let Some((t, _)) = sc.locals.get(n) {
                return if t.is_empty() { None } else { Some(t.clone()) };
            }
            if sc.owner != "/" {
                if let Some(v) = sem.var_decl(sc.owner, n) {
                    return if v.declared.is_empty() { None } else { Some(v.declared) };
                }
            }
            declared(sem, "/", n)
        }
    }
}

/// The static type of a chain's head term. Only declarations type a value: a call result (RETURN_TYPE included), an index, a ternary and an
/// operator result have none.
fn head_type(sem: &Sem, sc: &ProcScope, root: &Root<'_>) -> Option<String> {
    match root {
        Root::Ident(n) => ident_type(sem, sc, n),
        Root::NewPrefab { path, .. } => Some(prefab_path(path)),
        Root::Group(inner) => match chain(strip_groups(inner)) {
            Some(c) => {
                let mut cur = head_type(sem, sc, &c.root);
                for fo in c.hops.iter() {
                    cur = match fo {
                        Hop::Field { name: f, .. } => cur.and_then(|c| declared(sem, &c, f)),
                        _ => None,
                    };
                }
                cur
            }
            None => None,
        },
        _ => None,
    }
}

impl Lint for UntypedMember {
    fn meta(&self) -> &Meta {
        &META
    }

    fn scan_tree(&self, cx: &Cx, out: &mut Sink) {
        let Some(sem) = cx.sem() else {
            out.note("untyped_member: the semantic model is unavailable; nothing checked");
            return;
        };
        let sem: &Sem = &sem;
        let statics = static_names(sem);
        let root = &cx.tree.root;
        let mut rows: Vec<(String, u32, String)> = Vec::new();
        // Kept per file (`procs::per_file_in`): a file's rows read its own bodies and the model's structure (declarations, which vars
        // are static), which the context names.
        let per_file: Vec<Vec<(String, u32, String)>> = crate::sem::procs::per_file_in(sem, "untyped_member-rows", sem.structure_digest(), |rel, defs| {
            let mut rows: Vec<(String, u32, String)> = Vec::new();
            if !rel.starts_with("code/") || cx.exempt(rel) {
                return rows;
            }
            for (owner, v) in defs {
                let Some(code) = v.body() else { continue };
                let mut locals: HashMap<String, (String, Option<Place>)> = HashMap::new();
                for p in v.parameters().iter() {
                    locals.insert(p.name.to_string(), (path_of(&p.type_path), None));
                }
                collect_locals(code, rel, &mut locals);
                let sc = ProcScope { owner, locals };
                walk_block(code, &mut |vis, site| {
                    let Form::Chain(c) = &vis.form else { return };
                    let line = sem.line(Some(site));
                    let mut cur = head_type(sem, &sc, &c.root);
                    for fo in c.hops.iter() {
                        match fo {
                            Hop::Field { name: f, .. } => {
                                if cur.is_none() && statics.contains(*f) {
                                    rows.push((rel.to_string(), line, f.to_string()));
                                }
                                cur = cur.and_then(|c| declared(sem, &c, f));
                            }
                            _ => cur = None,
                        }
                    }
                });
            }
            rows
        });
        rows.extend(per_file.into_iter().flatten());
        rows.sort();
        rows.dedup();
        for (rel, line, name) in rows {
            out.site_in_msg(
                "static_member",
                &rel,
                engine_line(root, &rel, line) as usize,
                format!("`.{}` is read through a receiver with no static type, and `{}` is declared static on some type", name, name),
            );
        }
    }
}

pub fn register(reg: &mut Registry) {
    reg.add(UntypedMember);
}
