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
//! * `sampled_in_look`: a draw, a stat contribution or a STAT formula (or a proc one reaches) wraps a read in `read_once()`. A sample is taken
//!   once and never follows, so a look or a stat built from it goes stale: track the var, declare the relation or publish the key instead.
//! * `leaf_untracked`: a CAPABILITIES block names an untracked var as a stat input (`nameof(v)` in contributes()/contributes_to() or a when()
//!   around one).
//!
//! The reads are the closed walk's (`ReadsEngine::closed`): engine bodies are entered, a virtual call is the union of its overrides, a global
//! proc is walked like any proc, and global state that changes after boot is an untracked input (`untracked_global` in `sem/reads`). A site is
//! counted once however many consumers reach it. The baseline was re-seeded when the lint moved to this walk (a change of measurement:
//! `doc/rewrite/reads_closure_newly_visible.md` compares the two).
//!
//! A hard ban: any site fails, there is no baseline. Make the var TRACKED and write it through its setter, declare the relation, or publish a
//! READS_AS key where it changes. A read that genuinely cannot be tracked (global config a requirement asks, a clock, a profile record) is
//! sampled with `read_once(...)` (code/engine/parts/cond.dm), which the walk mutes and which rebuilds a menu that asked; the runtime treats
//! any consumer with an untracked read as untracked.

use crate::gens::deps;
use crate::lint::{Cx, Lint, Meta, Policy, Registry, RuleMeta, ScanKind, Sink};
use crate::tree::CODE_DM;

const H_STAT: &str = "make the var TRACKED (write it through set_<var>()), declare the relation, or publish a READS_AS key where it changes: a stat reading it recomputes on every read";
const H_DRAW: &str = "make the var TRACKED (write it through set_<var>()), declare the relation, or publish a READS_AS key where it changes: the look cannot follow it";
const H_SAMPLED: &str = "a draw or a stat input must not read_once(): track the var (write it through set_<var>()), declare the relation, or publish a READS_AS key";
const H_LEAF: &str = "make the var TRACKED and write it through its setter: a stat whose input never publishes recomputes on every read";

static META: Meta = Meta {
    name: "untracked_inputs",
    group: "",
    label: "untracked_inputs",
    legacy: "",
    select: CODE_DM,
    scan: ScanKind::Tree,
    policy: Policy::Hard,
    rules: &[
        RuleMeta { name: "stat_input_untracked", hint: H_STAT },
        RuleMeta { name: "draw_untracked", hint: H_DRAW },
        RuleMeta { name: "sampled_in_look", hint: H_SAMPLED },
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
        let sem = crate::sem::sem_for(cx.tree);
        let mut put = |out: &mut Sink, rule: &'static str, rel: &str, line: u32, ident: String, msg: String| {
            if rel.is_empty() || line == 0 || cx.exempt(rel) || !seen.insert((rule, rel.to_string(), line, msg.clone())) {
                return;
            }
            if let Some(f) = cx.tree.get(rel) {
                if out.allowed(f, line as usize, "untracked_inputs") {
                    return;
                }
            }
            out.site_decl(rule, rel, line as usize, msg, ident);
        };
        // A site is one finding however many consumers reach it (a helper line read by six hundred draws is one line to fix): the baseline
        // counts sites, not (consumer, site) pairs. The message names the first consumer and how many more reach the site.
        let mut sites: std::collections::BTreeMap<(&'static str, String, u32, String, String), Vec<&String>> = std::collections::BTreeMap::new();
        for (id, reads) in &an.consumers {
            let rule = if an.draws.contains(id) { "draw_untracked" } else { "stat_input_untracked" };
            for u in reads {
                sites.entry((rule, u.rel.clone(), u.line, u.what.clone(), u.owner.clone())).or_default().push(id);
            }
        }
        for ((rule, rel, line, what, owner), ids) in &sites {
            let more = if ids.len() > 1 { format!(" (and {} more)", ids.len() - 1) } else { String::new() };
            // The identity: the proc the read sits in (the model's owner and name) and what it reads (the declaring type and the var, with
            // its hops), not the line's text, so an edit of the line, a move within the proc or a reorder keeps its baseline row.
            let reader = sem.as_ref().map(|s| s.reader_ident(rel, *line)).unwrap_or_else(|| "?".to_string());
            let read = if owner.is_empty() { what.clone() } else { format!("{owner}::{what}") };
            put(out, rule, rel, *line, format!("{reader} reads {read}"), format!("{}{} reads `{}`, which nothing publishes", ids[0], more, what));
        }
        let mut sampled: std::collections::BTreeMap<(String, u32), Vec<&String>> = std::collections::BTreeMap::new();
        for (id, at) in &an.sampled {
            for site in at {
                sampled.entry(site.clone()).or_default().push(id);
            }
        }
        for ((rel, line), ids) in &sampled {
            let more = if ids.len() > 1 { format!(" (and {} more)", ids.len() - 1) } else { String::new() };
            let reader = sem.as_ref().map(|s| s.reader_ident(rel, *line)).unwrap_or_else(|| "?".to_string());
            put(out, "sampled_in_look", rel, *line, format!("{reader} samples"), format!("{}{} reaches a read_once(), which a look or a stat input must not sample", ids[0], more));
        }
        for l in &an.leaves {
            put(out, "leaf_untracked", &l.rel, l.line, format!("{}::{}", l.owner, l.var), format!("{} names `{}` as a stat input, and nothing publishes it", l.owner, l.var));
        }
    }
}

pub fn register(reg: &mut Registry) {
    reg.add(UntrackedInputs);
}
