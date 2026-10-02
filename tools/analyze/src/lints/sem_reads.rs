//! `sem/reads`: what generated reads cannot cover is a build error (E5, doc/rewrite/final_api.html
//! section 7, "Generated reads").
//!
//! Over every output, condition, requirement and contribution a declaration names:
//!
//! * `unknown_read`: a read of a var that is not tracked, a relation, a stat, a derived value or
//!   constant (never written after init). The hint lists the four fixes.
//! * `unannotated_global`: a global proc called without `READS_FROM(arg)`.
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
const H_GLOBAL: &str = "add READS_FROM(arg) to the global proc (READS_FROM() when it reads nothing): a condition cannot call what the graph cannot follow";
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
    policy: Policy::Hard,
    rules: &[
        RuleMeta { name: "unknown_read", hint: H_UNKNOWN },
        RuleMeta { name: "unannotated_global", hint: H_GLOBAL },
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
        let Some(an) = handlers::analyzed(cx.tree) else { return };
        let allowed = |out: &mut Sink, rel: &str, line: u32| -> bool {
            match cx.tree.get(rel) {
                Some(f) => out.allowed(f, line as usize, "reads"),
                None => false,
            }
        };
        let mut seen: std::collections::HashSet<(String, String, u32, String)> = std::collections::HashSet::new();
        let mut put = |out: &mut Sink, rule: &'static str, rel: &str, line: u32, msg: String| {
            if rel.is_empty() || !seen.insert((rule.to_string(), rel.to_string(), line, msg.clone())) {
                return;
            }
            if allowed(out, rel, line) {
                return;
            }
            out.site_in_msg(rule, rel, line as usize, msg);
        };
        for a in &an.handlers {
            if !a.h.role.reads_covered() {
                continue;
            }
            let Some(set) = &a.set else { continue };
            let who = format!("{}::{} ({}())", a.on, a.h.proc, a.h.form);
            for (key, var, owner, rel, line) in &a.unknown {
                put(out, "unknown_read", rel, *line, format!("{} reads `{}`: {} on {} is not tracked, a relation, a stat, derived or constant", who, key, var, owner));
            }
            for d in &set.diags {
                match d.rule {
                    "unannotated_global" | "dynamic_read" | "hop_not_relation" | "unknown_field" => {
                        let rule: &'static str = match d.rule {
                            "unannotated_global" => "unannotated_global",
                            "dynamic_read" => "dynamic_read",
                            "hop_not_relation" => "hop_not_relation",
                            _ => "unknown_field",
                        };
                        put(out, rule, &d.rel, d.line, format!("{}: {}", who, d.msg));
                    }
                    _ => {}
                }
            }
        }
        for c in &an.cycles {
            let first = an.graph.as_ref().and_then(|g| g.nodes.get(&c[0]));
            let (rel, line) = first.map(|n| (n.rel.clone(), n.line)).unwrap_or_default();
            put(out, "condition_cycle", &rel, line, format!("cycle in the condition and stat graph: {} -> {}", c.join(" -> "), c[0]));
        }
        for g in &an.accessor_gaps {
            put(
                out,
                "reads_as_uncovered",
                &g.rel,
                g.line,
                format!("READS_AS({}, {}) on {} reads {} which are not tracked and nothing publishes {}", g.proc, g.key, g.ty, g.vars.join(", "), g.key),
            );
        }
    }
}

pub fn register(reg: &mut Registry) {
    reg.add(SemReads);
}
