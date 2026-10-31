//! The condition and stat graph: cycles and ranks.
//!
//! Nodes are derived values: a `derive_<var>()` value on a type, and a stat on the type its
//! `STAT(T, name, ...)` declares. An edge `a -> b` means the body that computes `a` reads `b` on
//! the same entity (no relation hop), and `b` is itself derived. A cycle on those edges is a
//! build error: no evaluation order exists. A cycle that crosses a relation hop depends on
//! which entities are linked, so it is a runtime topology: the kernel refuses the edge when
//! it is added (section 7), and the static pass does not guess.
//!
//! Ranks are the evaluation order: a node with no derived reads is rank 0; otherwise one more
//! than its deepest derived read. The generated reads table carries them; the golden is
//! `tools/analyze/oracle/ranks.golden`.

use std::collections::{BTreeMap, BTreeSet};

use super::reads::{ReadKind, ReadsEngine};
use super::Sem;

pub use crate::reactive_rank_policy::{DepGraph,Node,render_ranks};

impl DepGraph {
    /// Builds the graph from every `derive_<var>` proc in the tree.
    pub fn from_derives(sem: &Sem, eng: &ReadsEngine) -> DepGraph {
        let mut g = DepGraph::default();
        let mut owners: Vec<(String, String, String)> = Vec::new(); // (type, var, proc)
        for ty in sem.objtree.iter_types() {
            let path = ty.get().path.clone();
            if path.is_empty() {
                continue;
            }
            for (name, tp) in ty.get().procs.iter() {
                if let Some(var) = name.strip_prefix("derive_") {
                    if tp.value.iter().any(|v| v.code.has_body()) {
                        owners.push((path.clone(), var.to_string(), name.clone()));
                    }
                }
            }
        }
        let mut ids: BTreeSet<String> = BTreeSet::new();
        for (ty, var, _) in &owners {
            let owner = sem.var_owner(ty, var).unwrap_or_else(|| ty.clone());
            ids.insert(format!("{}::{}", owner, var));
        }
        for (ty, var, proc) in &owners {
            let owner = sem.var_owner(ty, var).unwrap_or_else(|| ty.clone());
            let id = format!("{}::{}", owner, var);
            let set = eng.analyze(ty, proc);
            let node = g.nodes.entry(id.clone()).or_default();
            if let Some(p) = sem.proc_ref(ty, proc) {
                let b = sem.proc_body(p);
                node.rel = b.file;
                node.line = b.line;
            }
            for r in &set.reads {
                if r.kind != ReadKind::Var {
                    continue;
                }
                let target = format!("{}::{}", r.owner, r.var);
                if !ids.contains(&target) {
                    continue;
                }
                if r.hops.is_empty() && r.root == "holder" {
                    node.deps.insert(target);
                } else {
                    node.hop_deps.insert(target);
                }
            }
        }
        g
    }

}
