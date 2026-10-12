//! `untracked_inputs`: a read the dependency graph cannot see change, by a consumer whose value the runtime would like to keep.
//!
//! A stat input (a contribution, a when() condition around one, a STAT formula), a requirement, an output or a draw() is re-run when a key it
//! reads publishes (doc/rewrite/final_api.html section 7, "Generated reads"). A read of a var that nothing publishes (not tracked, a relation, a
//! stat, derived or constant), a read the walk cannot resolve, or a call into an engine body it does not enter leaves that consumer's inputs
//! incomplete: a stat that has one recomputes on every read instead of caching (code/engine/stats/recompute.dm), and a draw that has one can
//! show a stale look. The facts are `gen deps`' (`code/engine/_generated/deps.dm` lists the same consumers for the runtime).
//!
//! * `stat_input_untracked`: a condition, requirement, output or contribution handler reads untracked state.
//! * `draw_untracked`: a draw() reads untracked state.
//! * `leaf_untracked`: a CAPABILITIES block names an untracked var as a stat input (`nameof(v)` in contributes()/contributes_to() or a when()
//!   around one).
//!
//! Shrink-only over `tools/ci/untracked_inputs_baseline.txt`, which holds the reads that existed when generated dependencies landed: make the var
//! TRACKED and write it through its setter, declare the relation, or publish a READS_AS key where it changes. A read that cannot be tracked is
//! recorded with `// ALLOW(untracked_inputs): <reason>`, and the runtime still treats its consumer as untracked.

use crate::gens::deps;
use crate::lint::{Cx, Lint, Meta, Policy, Registry, RuleMeta, ScanKind, Sink};
use crate::tree::CODE_DM;

const H_STAT: &str = "make the var TRACKED (write it through set_<var>()), declare the relation, or publish a READS_AS key where it changes: a stat reading it recomputes on every read";
const H_DRAW: &str = "make the var TRACKED (write it through set_<var>()), declare the relation, or publish a READS_AS key where it changes: the look cannot follow it";
const H_LEAF: &str = "make the var TRACKED and write it through its setter: a stat whose input never publishes recomputes on every read";

static META: Meta = Meta {
    name: "untracked_inputs",
    group: "",
    label: "untracked_inputs",
    legacy: "",
    select: CODE_DM,
    scan: ScanKind::Tree,
    policy: Policy::Sites {
        baseline: "tools/ci/untracked_inputs_baseline.txt",
        header: &[
            "untracked_inputs: reads of untracked state by stat inputs, requirements, outputs and draws (analyze gen deps). rule<TAB>file<TAB>normalized line.",
            "Shrink-only: `analyze baseline --update --lint untracked_inputs` drops fixed sites and never adds one.",
        ],
        banned: &[],
    },
    rules: &[
        RuleMeta { name: "stat_input_untracked", hint: H_STAT },
        RuleMeta { name: "draw_untracked", hint: H_DRAW },
        RuleMeta { name: "leaf_untracked", hint: H_LEAF },
    ],
    allow: &["untracked_inputs"],
    lists: &[],
};

struct UntrackedInputs;

impl Lint for UntrackedInputs {
    fn meta(&self) -> &Meta {
        &META
    }

    fn scan_tree(&self, cx: &Cx, out: &mut Sink) {
        let an = deps::analyzed(cx.tree);
        let Some(an) = an.as_ref().as_ref() else { return };
        let mut seen = std::collections::HashSet::new();
        let mut put = |out: &mut Sink, rule: &'static str, rel: &str, line: u32, msg: String| {
            if rel.is_empty() || line == 0 || cx.exempt(rel) || !seen.insert((rule, rel.to_string(), line, msg.clone())) {
                return;
            }
            if let Some(f) = cx.tree.get(rel) {
                if out.allowed(f, line as usize, "untracked_inputs") {
                    return;
                }
            }
            out.site_in_msg(rule, rel, line as usize, msg);
        };
        for (id, reads) in &an.consumers {
            let rule = if an.draws.contains(id) { "draw_untracked" } else { "stat_input_untracked" };
            for u in reads {
                put(out, rule, &u.rel, u.line, format!("{} reads `{}`, which nothing publishes", id, u.what));
            }
        }
        for l in &an.leaves {
            put(out, "leaf_untracked", &l.rel, l.line, format!("{} names `{}` as a stat input, and nothing publishes it", l.owner, l.var));
        }
    }
}

pub fn register(reg: &mut Registry) {
    reg.add(UntrackedInputs);
}
