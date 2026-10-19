//! `player_link`: a raw write of a mob's `key` or `ckey` (doc/rewrite/proposals/relations.md D13).
//!
//! The native player link (`mob.key` / `mob.ckey`, which moves the client) is written in one place, `bind_player(mob, key)`
//! (code/modules/mob/bind_player.dm), which also keeps the persistent client relation in step. Any other assignment to `.key` / `.ckey` on a
//! value the model types as a mob, or to `key` / `ckey` inside a mob's own proc, is reported. A hard ban; the choke
//! point's file is exempt by path.

use dreammaker::ast::{AssignOp, Expression, Follow, Term};

use crate::lint::{Cx, Lint, Meta, Policy, Registry, RuleMeta, ScanKind, Sink};
use crate::lints::stored_refs::{collect_locals, path_of, Kinds, ProcScope, Walker};
use crate::sem::procs::engine_line;
use crate::sem::Sem;
use crate::tree::CODE_DM;

const HINT: &str = "move a player with bind_player(mob, key) (or move_player() / transfer_mind() for a mind): the one place that writes mob.key and keeps the \
persistent client in step. doc/rewrite/proposals/relations.md D13";

static META: Meta = Meta {
    name: "player_link",
    group: "",
    label: "player_link",
    legacy: "",
    select: CODE_DM,
    scan: ScanKind::Tree,
    policy: Policy::Hard,
    rules: &[RuleMeta { name: "raw_key", hint: HINT }],
    allow: &[],
    lists: &[],
};

struct PlayerLink;

fn is_mob(sem: &Sem, t: &str) -> bool {
    t == "/mob" || sem.is_subtype(t, "/mob")
}

impl Lint for PlayerLink {
    fn meta(&self) -> &Meta {
        &META
    }

    fn scan_tree(&self, cx: &Cx, out: &mut Sink) {
        let Some(sem) = cx.sem() else {
            out.note("player_link: the semantic model is unavailable; nothing checked");
            return;
        };
        let sem: &Sem = &sem;
        let kinds = Kinds { sem, exempt_types: Vec::new(), registry: Vec::new(), cache: Default::default() };
        let w = Walker { sem, kinds: &kinds };
        let root = &cx.tree.root;
        let mut found: Vec<(String, u32)> = Vec::new();
        for ty in sem.objtree.iter_types() {
            let owner = if ty.get().path.is_empty() { "/".to_string() } else { ty.get().path.clone() };
            let owner_is_mob = is_mob(sem, &owner);
            for (_, tp) in ty.get().procs.iter() {
                for v in tp.value.iter() {
                    let Some(code) = v.code.as_ref() else { continue };
                    let Some(rel) = sem.file_of(v.location) else { continue };
                    if cx.exempt(rel) {
                        continue;
                    }
                    let mut locals = std::collections::HashMap::new();
                    for p in v.parameters.iter() {
                        locals.insert(p.name.to_string(), (path_of(&p.var_type.type_path), None));
                    }
                    collect_locals(code, rel, &mut locals);
                    let sc = ProcScope { owner: &owner, locals };
                    crate::lints::rel_write_undeclared::walk_block_pub(code, &mut |e, line| {
                        // Statement-level assignments only: a `key = x` inside a call's arguments is a named argument.
                        (|x: &Expression| {
                            let Expression::AssignOp { op: AssignOp::Assign, lhs, .. } = x else { return };
                            let Expression::Base { term, follow } = &**lhs else { return };
                            let hit = match follow.last() {
                                None => match &term.elem {
                                    Term::Ident(n) => owner_is_mob && (n.as_str() == "key" || n.as_str() == "ckey") && !sc.locals.contains_key(n.as_str()),
                                    _ => false,
                                },
                                Some(last) => {
                                    let Follow::Field(_, n) = &last.elem else { return };
                                    if n.as_str() != "key" && n.as_str() != "ckey" {
                                        return;
                                    }
                                    let recv = Expression::Base { term: term.clone(), follow: follow[..follow.len() - 1].to_vec().into_boxed_slice() };
                                    w.type_of(&sc, &recv).map(|t| is_mob(sem, &t)).unwrap_or(false)
                                }
                            };
                            if hit {
                                found.push((rel.to_string(), engine_line(root, rel, line) as u32));
                            }
                        })(e);
                    });
                }
            }
        }
        found.sort();
        found.dedup();
        for (rel, line) in found {
            out.site_in_msg("raw_key", &rel, line as usize, "a raw write of a mob's key or ckey: use bind_player(mob, key)".to_string());
        }
    }
}

pub fn register(reg: &mut Registry) {
    reg.add(PlayerLink);
}
