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


use dreammaker::ast::{Expression, Follow, Term};

use crate::lint::{Cx,Lint,Meta,Registry,Sink};


use crate::setter_publication_policy::META;

use crate::setter_publication_policy as policy;

/// Whether `code` publishes: a publisher call, another `set_*()` call (a delegation), or a chain to the parent.
fn publishes(code: &dreammaker::ast::Block) -> bool {
    let mut found = false;
    crate::sem::ast::walk_block(code, &mut |e, _| {
        let Expression::Base { term, follow } = e else { return };
        let named = policy::publishes_named;
        match &term.elem {
            Term::ParentCall(_) => found = true,
            Term::Call(n, _) if named(n.as_str()) => found = true,
            _ => {}
        }
        for fo in follow.iter() {
            if let Follow::Call(_, n, _) = &fo.elem {
                if named(n.as_str()) {
                    found = true;
                }
            }
        }
    });
    found
}

/// A value Rust owns (`native_write`, a heat body, a `vg_*` call) is not published from DM: it goes through `watched()`.
fn owned_elsewhere(code: &dreammaker::ast::Block) -> bool {
    let mut found = false;
    crate::sem::ast::walk_block(code, &mut |e, _| {
        if let Expression::Base { term, .. } = e {
            if let Term::Call(n, _) = &term.elem {
                let n = n.as_str();
                if policy::owned_base_call(n) {
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
        let mut judged = crate::setter_publication_policy::Judged::new();
        let mut control=crate::key_policy_control::Compatibility;
        for (_owner,var,why) in &set.blocked {
            crate::setter_publication_policy::inferred_judgment(&mut judged,var,why,&mut control).unwrap();
        }
        let decls=crate::sem::decls::Decls::get(tree);
        for (ty,vars) in &decls.tracked_explicit {
            for var in vars {
                if sem.ty(ty).and_then(|t| t.get().procs.get(&format!("set_{var}")).map(|_| ())).is_some() {
                    crate::setter_publication_policy::explicit_judgment(&mut judged,ty,var,&mut control).unwrap();
                }
            }
        }
        for (definer, name, var, must) in judged {
            let Some(t) = sem.ty(&definer) else { continue };
            let Some(tp) = t.get().procs.get(&name) else { continue };
            for v in tp.value.iter() {
                let Some(rel) = sem.file_of(v.location) else { continue };
                if rel.starts_with("code/engine/_generated/") {
                    continue;
                }
                let Some(code) = &*v.code else { continue };
                let mut w = std::collections::HashSet::new();
                crate::sem::reads::collect_writes_pub(code, &mut w);
                let writes = w.contains(var.as_str());
                let publishes = publishes(code) || owned_elsewhere(code);
                if tp.declaration.as_ref().is_some_and(|d| d.kind == dreammaker::ast::ProcDeclKind::Verb) {
                    continue;
                }
                let line = crate::sem::procs::engine_line(&sem.root, rel, v.location.line) as usize;
                if let Some(finding)=policy::judge(writes,publishes,must){
                    let message=match finding.message(&definer,&name,&var,&mut crate::key_policy_control::Compatibility){Ok(text)=>text,Err(never)=>match never{}};
                    out.site_in_msg(finding.rule(),rel,line,message);
                }
            }
        }
    }
}

pub fn register(reg: &mut Registry) {
    reg.add(SetterPublishes);
}
