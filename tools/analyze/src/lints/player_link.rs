//! `player_link`: a raw write of a mob's `key` or `ckey` (doc/rewrite/proposals/relations.md D13).
//!
//! The native player link (`mob.key` / `mob.ckey`, which moves the client) is written in one place, `bind_player(mob, key)`
//! (code/content/mob/bind_player.dm), which also keeps the persistent client relation in step. Any other assignment to `.key` / `.ckey` on a
//! value the model types as a mob, or to `key` / `ckey` inside a mob's own proc, is reported. A hard ban; the choke
//! point's file is exempt by path.

use crate::lint::{Cx, Lint, Meta, Policy, Registry, RuleMeta, ScanKind, Sink};
use crate::lints::stored_refs::{collect_locals, path_of, Kinds, ProcScope, Walker};
use crate::model::expr::{chain, Form, Hop, Root};
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
        for ty in sem.m().types() {
            let owner = ty.path().to_string();
            let owner_is_mob = is_mob(sem, &owner);
            for pname in ty.proc_names() {
                for v in ty.proc_definitions(pname) {
                    let Some(code) = v.body() else { continue };
                    let Some(rel) = sem.file_of(v.site()) else { continue };
                    if cx.exempt(&rel) {
                        continue;
                    }
                    let mut locals = std::collections::HashMap::new();
                    for p in v.parameters().iter() {
                        locals.insert(p.name.to_string(), (path_of(&p.type_path), None));
                    }
                    collect_locals(code, &rel, &mut locals);
                    let sc = ProcScope { owner: &owner, locals };
                    crate::lints::rel_write_undeclared::walk_block_pub(code, &mut |top, _node, site| {
                        // Statement-level assignments only: a `key = x` inside a call's arguments is a named argument.
                        let Form::Assign { op: "=", lhs, .. } = top else { return };
                        let Some(c) = chain(lhs) else { return };
                        let hit = match c.hops.last() {
                            None => match &c.root {
                                Root::Ident(n) => owner_is_mob && (*n == "key" || *n == "ckey") && !sc.locals.contains_key(*n),
                                _ => false,
                            },
                            Some(last) => {
                                let Hop::Field { name: n, .. } = last else { return };
                                if *n != "key" && *n != "ckey" {
                                    return;
                                }
                                w.type_of(&sc, c.prefix_node(c.hops.len() - 1)).map(|t| is_mob(sem, &t)).unwrap_or(false)
                            }
                        };
                        if hit {
                            found.push((rel.to_string(), engine_line(root, &rel, sem.line(Some(site))) as u32));
                        }
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
