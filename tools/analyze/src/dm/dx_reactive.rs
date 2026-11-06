//! Port of the reusable half of `tools/ci/sys_rules/dx_reactive.py`: the reactive-proc analysis
//! (design review H4, H5, M3, M5) that `sys/dx_reactive` runs and `sys/dx_look_side_effects`
//! reuses (`reactive_writes`, `WRITER_CALL`, `MEMBER_WRITER`).
//!
//! Everything works on a [`Proc`]'s sanitized body lines, like the Python, by VAR NAME and with
//! the documented static limits (see the Python module docstring).

use std::collections::{HashMap, HashSet};

use crate::dm::dx::{self, DxFacts, Proc};
use crate::tree::{SourceFile, Tree};
use crate::{pat, pat_match};
pub use crate::reactive_writer_policy::{writer_call,member_writer,reactive_writes_lines_using};

pub use crate::sys_reactive_policy::{is_reactive,blank_calls,foreign_reads,TimedPats};
pub fn caps_reads(proc:&Proc,tree:&Tree,table:&HashMap<String,HashSet<String>>)->Vec<(usize,String)>{let lines=proc.lines(tree);crate::sys_reactive_policy::caps_reads(proc,&lines,table)}
pub fn timed_vars(tree:&Tree,procs:&[Proc])->HashMap<String,HashSet<String>>{let mut out=HashMap::new();for proc in procs{let lines=proc.lines(tree);crate::sys_reactive_policy::add_timed_vars(proc,&lines,&|number|tree.get(&proc.rel).map(|f|f.line(number)).unwrap_or(""),&mut out);}out}
pub fn timed_writes(proc:&Proc,tree:&Tree,timed:&HashMap<String,HashSet<String>>,cache:&mut HashMap<String,TimedPats>)->Vec<usize>{let lines=proc.lines(tree);crate::sys_reactive_policy::timed_writes(proc,&lines,timed,cache)}
pub fn reactive_writes(proc:&Proc,tree:&Tree)->Vec<usize>{let lines=proc.lines(tree);reactive_writes_lines_using(proc,&lines,&mut crate::key_policy_control::Compatibility,&mut crate::key_policy_control::Compatibility).expect("original reactive writes")}
pub fn own_roots_of(proc:&Proc,tree:&Tree,relations:&HashSet<String>)->(HashSet<String>,HashSet<String>,HashSet<String>){let lines=proc.lines(tree);crate::sys_reactive_policy::own_roots_of(proc,&lines,relations)}

// ---- the whole analysis -----------------------------------------------------------------------

pub const RULE_READ: &str = "dx_untracked_read";
pub const RULE_WRITE: &str = "dx_reactive_write";
pub const RULE_CAPS: &str = "dx_caps_instance_read";
pub const RULE_TIMED: &str = "dx_timed_write";

/// One file's contribution to the shared context of [`analyse`]: the proc names it names as a
/// `needs =` handler, the vars it declares tracked, the relation vars it watches, and the
/// `timed_set` vars it writes (`(var, owning type)`). All sorted and deduplicated.
#[derive(Clone, Default, PartialEq, serde::Serialize, serde::Deserialize)]
struct ReactiveFacts {
    needs: Vec<String>,
    tracked: Vec<String>,
    watched: Vec<String>,
    timed: Vec<(String, String)>,
}

fn reactive_facts(tree:&Tree,f:&SourceFile,procs:&[Proc])->ReactiveFacts{
 let _=tree;let mut context=crate::sys_reactive_policy::Context::default();crate::sys_reactive_policy::add_file_context(f,procs,&mut context);
 let sorted=|s:HashSet<String>|{let mut rows=s.into_iter().collect::<Vec<_>>();rows.sort();rows};
 let mut timed=context.timed.into_iter().flat_map(|(name,paths)|paths.into_iter().map(move|path|(name.clone(),path))).collect::<Vec<_>>();timed.sort();
 ReactiveFacts{needs:sorted(context.needs),tracked:sorted(context.tracked),watched:sorted(context.watched),timed}
}

/// What the per-file judge reads (everything except the type-var table).
#[derive(serde::Serialize)]
struct ReactiveCtx {
    needs: std::collections::BTreeSet<String>,
    tracked: std::collections::BTreeSet<String>,
    watched: std::collections::BTreeSet<String>,
    timed: std::collections::BTreeMap<String, std::collections::BTreeSet<String>>,
}

/// One file's findings by emission group: reads, writes, timed.
type FileSites = (Vec<u32>, Vec<u32>, Vec<u32>);

/// `analyse`: every site of the four rules, in the Python's emission order.
///
/// Incremental: per-file facts (cached by content) merge into the shared name sets; each file's
/// reactive/timed findings are cached while those sets are unchanged, and the capabilities()
/// instance reads (the only rule that reads the type-var table) while the file facts that feed that
/// table are unchanged.
pub fn analyse(tree: &Tree, files: &[&SourceFile]) -> Vec<(&'static str, String, usize)> {
    let dxf = DxFacts::all(tree);
    let facts: Vec<ReactiveFacts> = crate::incr::facts("dx-reactive-facts", files, |f| reactive_facts(tree, f, &dxf.of(f).procs));
    let mut ctx = ReactiveCtx { needs: Default::default(), tracked: Default::default(), watched: Default::default(), timed: Default::default() };
    for fs in &facts {
        ctx.needs.extend(fs.needs.iter().cloned());
        ctx.tracked.extend(fs.tracked.iter().cloned());
        ctx.watched.extend(fs.watched.iter().cloned());
        for (n, p) in &fs.timed {
            ctx.timed.entry(n.clone()).or_default().insert(p.clone());
        }
    }
    // The vars read-driven tracking gives a generated setter (gens/auto_tracked.rs) are tracked as the TRACKED() lines they replace were.
    if let Some(auto) = tree.get(crate::gens::auto_tracked::AUTO_REL) {
        let line = crate::pat!(r"^TRACKED\(/[A-Za-z0-9_/]+, (\w+)\)");
        for l in auto.raw().lines() {
            if let Some(m) = line.captures(l) {
                ctx.tracked.insert(m.s(1).to_string());
            }
        }
    }
    // A var no proc ever writes (a per-type default overridden in subtypes, read across objects) is constant: nothing could publish its change, so
    // reading it needs no tracking (the dependency analysis classes it Constant the same way).
    if let Some(sem) = crate::sem::sem_for(tree).filter(|_| tree.get(crate::gens::auto_tracked::AUTO_REL).is_some()) {
        let written = crate::gens::auto_tracked::writes_outside_setters_of(tree, &sem);
        let calls = crate::gens::auto_tracked::set_calls(tree);
        for t in sem.objtree.iter_types() {
            for (name, v) in &t.get().vars {
                if v.declaration.is_some() && !written.is_written(name.as_str()) && !calls.contains(name.as_str()) {
                    ctx.tracked.insert(name.clone());
                }
            }
        }
    }
    // `dir` is a tracked read of every drawn atom: /atom/set_dir() publishes its change (code/domains/world_model/atom/atom.dm), so a draw
    // reading `dir` (its own or a watched neighbour's) redraws.
    ctx.tracked.insert("dir".to_string());
    let needs_names: HashSet<String> = ctx.needs.iter().cloned().collect();
    let tracked: HashSet<String> = ctx.tracked.iter().cloned().collect();
    let watched: HashSet<String> = ctx.watched.iter().cloned().collect();
    let timed: HashMap<String, HashSet<String>> = ctx.timed.iter().map(|(n, ps)| (n.clone(), ps.iter().cloned().collect())).collect();
    let context=crate::sys_reactive_policy::Context{needs:needs_names,tracked,watched,timed};

    let sites: Vec<FileSites> = crate::incr::keyed("dx-reactive-judge-runtime-data-v2", crate::incr::ctx_key(&ctx), files, |f| {
        let fd=dxf.of(f);
        let [reads,writes,timed]=crate::sys_reactive_policy::judge_procs(f,&fd,&context);(reads.into_iter().map(|n|n as u32).collect(),writes.into_iter().map(|n|n as u32).collect(),timed.into_iter().map(|n|n as u32).collect())
    });

    // capabilities() instance reads: the one rule that reads the `{type: vars}` table. Keyed by the
    // files' var facts; the merged table is only built when a capabilities() file must be judged.
    let vars_key = {
        let cows: Vec<std::borrow::Cow<'_, dx::FileDx>> = files.iter().map(|f| dxf.of(f)).collect();
        let all: Vec<&Vec<(String, Vec<String>)>> = cows.iter().map(|c| &c.vars).filter(|v| !v.is_empty()).collect();
        crate::incr::ctx_key(&all)
    };
    let table: std::sync::OnceLock<HashMap<String, HashSet<String>>> = std::sync::OnceLock::new();
    let caps: Vec<Vec<u32>> = crate::incr::keyed("dx-reactive-caps", vars_key, files, |f| {
        let fd = dxf.of(f);
        if !fd.procs.iter().any(|p| p.name == "capabilities" && p.path != "/atom") {
            return Vec::new();
        }
        let table = table.get_or_init(|| {
            let mut t: HashMap<String, HashSet<String>> = HashMap::new();
            for g in files {
                for (ty, vs) in &dxf.of(g).vars {
                    t.entry(ty.clone()).or_default().extend(vs.iter().cloned());
                }
            }
            t
        });
        crate::sys_reactive_policy::judge_caps(f,&fd,table).into_iter().map(|n|n as u32).collect()
    });

    let mut out: Vec<(&'static str, String, usize)> = Vec::new();
    for (f, s) in files.iter().zip(&sites) {
        out.extend(s.0.iter().map(|&n| (RULE_READ, f.rel.clone(), n as usize)));
    }
    for (f, s) in files.iter().zip(&sites) {
        out.extend(s.1.iter().map(|&n| (RULE_WRITE, f.rel.clone(), n as usize)));
    }
    for (f, c) in files.iter().zip(&caps) {
        out.extend(c.iter().map(|&n| (RULE_CAPS, f.rel.clone(), n as usize)));
    }
    for (f, s) in files.iter().zip(&sites) {
        out.extend(s.2.iter().map(|&n| (RULE_TIMED, f.rel.clone(), n as usize)));
    }
    out
}

/// `m.group(i)` is truthy: it participated and is not empty.
fn m_nonempty(c: &crate::pat::Caps, i: usize) -> bool {
    c.matched(i) && !c.s(i).is_empty()
}
