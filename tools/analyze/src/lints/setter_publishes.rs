//! A hand-written `set_<v>()` on a tracked var must publish the change (doc/rewrite/read_driven_tracking.md).
//!
//! Read-driven tracking generates a type's `set_v()` unless a related type already declares one (`gens::auto_tracked::decide`, "already defines");
//! then that hand-written proc is the var's setter, and a write it makes that never reaches `tracked_changed()` leaves the var silently untracked:
//! whatever reads it is never told. This lint judges every such proc, and every `SETTER(T, v)`-registered one:
//!
//! * `no_publish`: it writes the var and neither calls a publisher (`tracked_changed`, `publish_change`, `state_changed`, `record_changed`, a relation
//!   or ownership write, another `set_*()`) nor chains to `..()`;
//! * `not_a_setter`: a proc named `set_<v>` that does not write the var at all, on a type whose var reactive code reads. The generator cannot give the
//!   var a setter, so the var is untracked; rename the proc.
//!
//! Hard lint, no baseline.

use std::collections::BTreeSet;

use dm_syntax::Statement;

use crate::lint::{Cx, Lint, Meta, Policy, Registry, RuleMeta, ScanKind, Sink};
use crate::model::expr::{Form, Hop, Root};
use crate::model::walk::walk_block;
use crate::tree::CODE_DM;

static META: Meta = Meta {
    name: "setter_publishes",
    group: "",
    label: "setter_publishes",
    legacy: "",
    select: CODE_DM,
    scan: ScanKind::Tree,
    policy: Policy::Hard,
    rules: &[
        RuleMeta { name: "no_publish", hint: "call tracked_changed(src, nameof(v)) on every path that changes the var (or chain to ..()): a write nothing publishes leaves the var silently untracked" },
        RuleMeta { name: "not_a_setter", hint: "this proc shares the name of a setter but does not write the var, so the var (read by reactive code) cannot get a generated setter: rename the proc" },
    ],
    allow: &[],
    lists: &[],
};

const PUBLISHERS: &[&str] = &["tracked_changed", "publish_change", "state_changed", "record_changed", "rel_set", "rel_add", "rel_remove", "own_set", "own_add", "own_put", "own_clear", "timed_set", "vars_write"];

/// Whether `code` publishes: a publisher call, another `set_*()` call (a delegation), or a chain to the parent.
fn publishes(code: &[Statement]) -> bool {
    let mut found = false;
    walk_block(code, &mut |v, _| {
        let Form::Chain(c) = &v.form else { return };
        let named = |n: &str| PUBLISHERS.contains(&n) || n.starts_with("set_") || n.starts_with("add_") || n.starts_with("remove_") || n.starts_with("publish");
        match &c.root {
            Root::ParentCall(_) => found = true,
            Root::Call { name, .. } if named(name) => found = true,
            _ => {}
        }
        for fo in c.hops.iter() {
            if let Hop::Call { name, .. } = fo {
                if named(name) {
                    found = true;
                }
            }
        }
    });
    found
}

/// A value Rust owns (`native_write`, a heat body, a `vg_*` call) is not published from DM: it goes through `watched()`.
fn owned_elsewhere(code: &[Statement]) -> bool {
    let mut found = false;
    walk_block(code, &mut |v, _| {
        if let Form::Chain(c) = &v.form {
            if let Root::Call { name: n, .. } = &c.root {
                if *n == "native_write" || n.starts_with("heat_") || n.starts_with("vg_") {
                    found = true;
                }
            }
        }
    });
    found
}

struct SetterPublishes;

impl Lint for SetterPublishes {
    fn meta(&self) -> &Meta {
        &META
    }

    fn scan_tree(&self, cx: &Cx, out: &mut Sink) {
        let tree = cx.tree;
        let Some(sem) = crate::sem::sem_for(tree) else { return };
        let inf = crate::gens::auto_tracked::inferred(tree);
        let Some(set) = inf.as_ref().as_ref() else { return };
        // (definer type, proc name, var, must it be a setter of the var)
        let mut judged: BTreeSet<(String, String, String, bool)> = BTreeSet::new();
        for (_owner, var, why) in &set.blocked {
            let Some((definer, rest)) = why.split_once(" already defines ") else { continue };
            let name = rest.trim_end_matches("()");
            if name == format!("set_{var}") {
                judged.insert((definer.to_string(), name.to_string(), var.clone(), true));
            }
        }
        let decls = crate::sem::decls::Decls::get(tree);
        for (ty, vars) in &decls.tracked_explicit {
            for var in vars {
                if sem.ty(ty).is_some_and(|t| !t.proc_definitions(&format!("set_{var}")).is_empty()) {
                    judged.insert((ty.clone(), format!("set_{var}"), var.clone(), false));
                }
            }
        }
        for (definer, name, var, must) in judged {
            let Some(t) = sem.ty(&definer) else { continue };
            let defs = t.proc_definitions(&name);
            if defs.is_empty() {
                continue;
            }
            // The declaration this type itself makes (a verb is no setter).
            let is_verb = defs.iter().find(|p| p.declares()).and_then(|p| p.declared_verb()) == Some(true);
            for v in defs.iter() {
                let Some(rel) = sem.file_of(v.site()) else { continue };
                if rel.starts_with("code/engine/_generated/") {
                    continue;
                }
                let Some(code) = v.body() else { continue };
                let mut w = std::collections::HashSet::new();
                crate::sem::reads::collect_writes_pub(code, &mut w);
                let writes = w.contains(var.as_str());
                let publishes = publishes(code) || owned_elsewhere(code);
                if is_verb {
                    continue;
                }
                let line = crate::sem::procs::engine_line(&sem.root, &rel, sem.line(v.site())) as usize;
                if writes && !publishes {
                    out.site_in_msg("no_publish", &rel, line, format!("{definer}/{name}() writes {var} and never publishes it"));
                } else if !writes && !publishes && must {
                    out.site_in_msg("not_a_setter", &rel, line, format!("{definer}/{name}() does not write {var}"));
                }
            }
        }
    }
}

pub fn register(reg: &mut Registry) {
    reg.add(SetterPublishes);
}
