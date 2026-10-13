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
//! The reads are the closed walk's (`ReadsEngine::closed`): engine bodies are entered, a virtual call is the union of its overrides, a global
//! proc is walked like any proc, and global state that changes after boot is an untracked input (`untracked_global` in `sem/reads`). A site is
//! counted once however many consumers reach it. The baseline was re-seeded when the lint moved to this walk (a change of measurement:
//! `doc/rewrite/reads_closure_newly_visible.md` compares the two).
//!
//! Shrink-only over `tools/ci/untracked_inputs_baseline.txt`, which holds the sites that existed when the closed walk was adopted: make the var
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
        // A site is one finding however many consumers reach it (a helper line read by six hundred draws is one line to fix): the baseline
        // counts sites, not (consumer, site) pairs. The message names the first consumer and how many more reach the site.
        let mut sites: std::collections::BTreeMap<(&'static str, String, u32, String), Vec<&String>> = std::collections::BTreeMap::new();
        for (id, reads) in &an.consumers {
            let rule = if an.draws.contains(id) { "draw_untracked" } else { "stat_input_untracked" };
            for u in reads {
                sites.entry((rule, u.rel.clone(), u.line, u.what.clone())).or_default().push(id);
            }
        }
        for ((rule, rel, line, what), ids) in &sites {
            let more = if ids.len() > 1 { format!(" (and {} more)", ids.len() - 1) } else { String::new() };
            put(out, rule, rel, *line, format!("{}{} reads `{}`, which nothing publishes", ids[0], more, what));
        }
        for l in &an.leaves {
            put(out, "leaf_untracked", &l.rel, l.line, format!("{} names `{}` as a stat input, and nothing publishes it", l.owner, l.var));
        }
    }
}

pub fn register(reg: &mut Registry) {
    reg.add(UntrackedInputs);
}
