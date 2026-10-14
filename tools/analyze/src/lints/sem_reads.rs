//! `sem/reads`: what generated reads cannot cover is a build error (E5, doc/rewrite/final_api.html
//! section 7, "Generated reads").
//!
//! Over every output, condition, requirement and contribution a declaration names:
//!
//! * `unknown_read`: a read of a var that is not tracked, a relation, a stat, a derived value or
//!   constant (never written after init). The hint lists the four fixes.
//! * `untracked_global`: global state that changes after boot (`GLOB.x`, `SSx.y`, a real global var) read by reactive code. Constant-after-init
//!   globals (written only while the world boots, `sem/globals.rs`) read like constants; a tracked var of a system is a system read.
//! * `dynamic_read`: `vars[]` or `call()` in a handler.
//! * `hop_not_relation`: a read through a var that is not a declared relation.
//! * `unknown_field`: a var that the receiver's type does not have.
//! * `condition_cycle`: a cycle in the condition and stat graph, with the chain.
//! * `reads_as_uncovered`: a `READS_AS(proc, key)` accessor that reads untracked state nobody
//!   publishes under `key`.
//!
//! Nothing here parses the tree until a declaration names a handler.

use crate::lint::{Cx, Lint, Meta, Policy, Registry, RuleMeta, ScanKind, Sink};
use crate::sem::handlers;
use crate::tree::CODE_DM;

const H_UNKNOWN: &str = "make it tracked, add a relation, add READS_FROM(arg) to the global proc it came through, or add READS_AS(proc, key)";
const H_GLOBAL: &str = "move the state into a system's tracked vars (SYSTEM_DEF) and read it through its accessor, or write it only while the world boots: reactive code cannot read a global that changes and nothing publishes";
const H_DYNAMIC: &str = "read a declared var; nothing uses vars[] or call() in a handler";
const H_HOP: &str = "declare the link var a relation (REL/OWN or rel_one in relations()); a hop only follows a declared relation";
const H_FIELD: &str = "read a var the type declares (the build checks each read against the receiver's type)";
const H_CYCLE: &str = "break the cycle: a derived value cannot read itself through its own dependencies";
const H_COVER: &str = "publish the key where the state changes (PUBLISH_CHANGE(E, KEY)), or make the vars tracked";

static META: Meta = Meta {
    name: "sem/reads",
    group: "sem",
    label: "reads",
    legacy: "",
    select: CODE_DM,
    scan: ScanKind::Tree,
    policy: Policy::Sites {
        baseline: "tools/ci/sem_reads_baseline.txt",
        header: &[
            "sem/reads: what the closed read walk cannot cover in a handler, an output, a condition or a contribution. rule<TAB>file<TAB>identity (@reader reads owner::var).",
            "Shrink-only: `analyze baseline --update --lint sem/reads` drops fixed sites and never adds one.",
        ],
        banned: &[],
    },
    rules: &[
        RuleMeta { name: "unknown_read", hint: H_UNKNOWN },
        RuleMeta { name: "untracked_global", hint: H_GLOBAL },
        RuleMeta { name: "dynamic_read", hint: H_DYNAMIC },
        RuleMeta { name: "hop_not_relation", hint: H_HOP },
        RuleMeta { name: "unknown_field", hint: H_FIELD },
        RuleMeta { name: "condition_cycle", hint: H_CYCLE },
        RuleMeta { name: "reads_as_uncovered", hint: H_COVER },
    ],
    allow: &["reads"],
    lists: &[],
};

struct SemReads;

impl Lint for SemReads {
    fn meta(&self) -> &Meta {
        &META
    }

    fn scan_tree(&self, cx: &Cx, out: &mut Sink) {
        // The stored result of a run whose inputs are unchanged (or changed only where the model
        // cannot tell): no parse.
        if let Some(rec) = crate::sem::incremental::lookup(cx.tree) {
            if let Some(s) = rec.sinks.get("sem/reads") {
                out.sites.extend(s.sites.iter().cloned());
                out.allow_used.extend(s.allow_used.iter().cloned());
                out.notes.extend(s.notes.iter().cloned());
                return;
            }
        }
        let Some(an) = handlers::analyzed(cx.tree) else { return };
        let allowed = |out: &mut Sink, rel: &str, line: u32| -> bool {
            match cx.tree.get(rel) {
                Some(f) => out.allowed(f, line as usize, "reads"),
                None => false,
            }
        };
        // A site is one finding however many handlers reach it: the key leaves the handler out of the message.
        let mut seen: std::collections::HashSet<(String, String, u32, String)> = std::collections::HashSet::new();
        let sem = crate::sem::sem_for(cx.tree);
        let reader = |rel: &str, line: u32| -> String { sem.as_ref().map(|s| s.reader_ident(rel, line)).unwrap_or_else(|| "?".to_string()) };
        let mut put = |out: &mut Sink, rule: &'static str, rel: &str, line: u32, key: String, ident: String, msg: String| {
            if rel.is_empty() || !seen.insert((rule.to_string(), rel.to_string(), line, key)) {
                return;
            }
            if allowed(out, rel, line) {
                return;
            }
            out.site_decl(rule, rel, line as usize, msg, ident);
        };
        for a in &an.handlers {
            if !a.h.role.reads_covered() {
                continue;
            }
            let Some(set) = &a.closed else { continue };
            let who = format!("{}::{} ({}())", a.on, a.h.proc, a.h.form);
            for (key, var, owner, rel, line) in &a.unknown {
                put(out, "unknown_read", rel, *line, format!("{key}|{var}|{owner}"), format!("{} reads {}::{}", reader(rel, *line), owner, key), format!("{} reads `{}`: {} on {} is not tracked, a relation, a stat, derived or constant", who, key, var, owner));
            }
            for d in &set.diags {
                match d.rule {
                    "untracked_global" | "dynamic_read" | "hop_not_relation" | "unknown_field" => {
                        let rule: &'static str = match d.rule {
                            "untracked_global" => "untracked_global",
                            "dynamic_read" => "dynamic_read",
                            "hop_not_relation" => "hop_not_relation",
                            _ => "unknown_field",
                        };
                        put(out, rule, &d.rel, d.line, d.msg.clone(), format!("{} reads {}", reader(&d.rel, d.line), d.msg), format!("{}: {}", who, d.msg));
                    }
                    _ => {}
                }
            }
        }
        for c in &an.cycles {
            let first = an.graph.as_ref().and_then(|g| g.nodes.get(&c[0]));
            let (rel, line) = first.map(|n| (n.rel.clone(), n.line)).unwrap_or_default();
            put(out, "condition_cycle", &rel, line, c.join(">"), format!("cycle {}", c.join(">")), format!("cycle in the condition and stat graph: {} -> {}", c.join(" -> "), c[0]));
        }
        for g in &an.accessor_gaps {
            put(
                out,
                "reads_as_uncovered",
                &g.rel,
                g.line,
                format!("{}|{}", g.proc, g.key),
                format!("{}::{} publishes {}", g.ty, g.proc, g.key),
                format!("READS_AS({}, {}) on {} reads {} which are not tracked and nothing publishes {}", g.proc, g.key, g.ty, g.vars.join(", "), g.key),
            );
        }
        crate::sem::incremental::store(cx.tree, "sem/reads", out);
    }
}

pub fn register(reg: &mut Registry) {
    reg.add(SemReads);
}
