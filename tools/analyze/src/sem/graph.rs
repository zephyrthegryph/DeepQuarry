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

#[derive(Debug, Default, Clone)]
pub struct Node {
    /// Same-entity edges: the derived nodes this one reads.
    pub deps: BTreeSet<String>,
    /// Edges through a relation hop (kept for the generated table, ignored by the cycle check).
    pub hop_deps: BTreeSet<String>,
    pub rel: String,
    pub line: u32,
}

#[derive(Debug, Default)]
pub struct DepGraph {
    pub nodes: BTreeMap<String, Node>,
}

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
                    if tp.value.iter().any(|v| v.code.is_some()) {
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

    /// Adds a node (for stats and other callers).
    pub fn add(&mut self, id: &str, deps: impl IntoIterator<Item = String>, rel: &str, line: u32) {
        let n = self.nodes.entry(id.to_string()).or_default();
        n.deps.extend(deps);
        if n.rel.is_empty() {
            n.rel = rel.to_string();
            n.line = line;
        }
    }

    /// Strongly connected components with a cycle (size > 1, or a self edge), as the node chains.
    pub fn cycles(&self) -> Vec<Vec<String>> {
        struct T<'a> {
            g: &'a DepGraph,
            index: BTreeMap<&'a str, usize>,
            low: BTreeMap<&'a str, usize>,
            on: BTreeSet<&'a str>,
            stack: Vec<&'a str>,
            n: usize,
            out: Vec<Vec<String>>,
        }
        fn visit<'a>(t: &mut T<'a>, v: &'a str) {
            t.index.insert(v, t.n);
            t.low.insert(v, t.n);
            t.n += 1;
            t.stack.push(v);
            t.on.insert(v);
            if let Some(node) = t.g.nodes.get(v) {
                for w in &node.deps {
                    let w: &'a str = w.as_str();
                    if !t.g.nodes.contains_key(w) {
                        continue;
                    }
                    if !t.index.contains_key(w) {
                        visit(t, w);
                        let lw = t.low[w];
                        let lv = t.low[v];
                        t.low.insert(v, lv.min(lw));
                    } else if t.on.contains(w) {
                        let iw = t.index[w];
                        let lv = t.low[v];
                        t.low.insert(v, lv.min(iw));
                    }
                }
            }
            if t.low[v] == t.index[v] {
                let mut comp = Vec::new();
                loop {
                    let w = t.stack.pop().unwrap();
                    t.on.remove(w);
                    comp.push(w.to_string());
                    if w == v {
                        break;
                    }
                }
                let selfloop = comp.len() == 1 && t.g.nodes.get(v).map(|n| n.deps.contains(v)).unwrap_or(false);
                if comp.len() > 1 || selfloop {
                    comp.reverse();
                    t.out.push(comp);
                }
            }
        }
        let mut t = T { g: self, index: BTreeMap::new(), low: BTreeMap::new(), on: BTreeSet::new(), stack: Vec::new(), n: 0, out: Vec::new() };
        for k in self.nodes.keys() {
            if !t.index.contains_key(k.as_str()) {
                visit(&mut t, k.as_str());
            }
        }
        t.out
    }

    /// Ranks of every node; `Err` carries the cycles when there is no order.
    pub fn ranks(&self) -> Result<BTreeMap<String, u32>, Vec<Vec<String>>> {
        let cyc = self.cycles();
        if !cyc.is_empty() {
            return Err(cyc);
        }
        let mut rank: BTreeMap<String, u32> = BTreeMap::new();
        fn go(g: &DepGraph, id: &str, rank: &mut BTreeMap<String, u32>) -> u32 {
            if let Some(r) = rank.get(id) {
                return *r;
            }
            let mut r = 0;
            if let Some(n) = g.nodes.get(id) {
                for d in &n.deps {
                    if g.nodes.contains_key(d) {
                        r = r.max(go(g, d, rank) + 1);
                    }
                }
            }
            rank.insert(id.to_string(), r);
            r
        }
        for k in self.nodes.keys() {
            go(self, k, &mut rank);
        }
        Ok(rank)
    }
}

/// `rank<TAB>node` lines, ordered by rank then name: the golden format.
pub fn render_ranks(ranks: &BTreeMap<String, u32>) -> String {
    let mut rows: Vec<(&u32, &String)> = ranks.iter().map(|(k, v)| (v, k)).collect();
    rows.sort();
    let mut s = String::new();
    for (r, n) in rows {
        s.push_str(&format!("{}\t{}\n", r, n));
    }
    s
}

#[cfg(test)]
mod tests {
    use super::*;

    fn g(edges: &[(&str, &[&str])]) -> DepGraph {
        let mut g = DepGraph::default();
        for (n, d) in edges {
            g.add(n, d.iter().map(|s| s.to_string()), "x.dm", 1);
        }
        g
    }

    #[test]
    fn ranks_follow_depth() {
        let g = g(&[("c", &["b"]), ("b", &["a"]), ("a", &[]), ("d", &["a"])]);
        let r = g.ranks().unwrap();
        assert_eq!((r["a"], r["b"], r["c"], r["d"]), (0, 1, 2, 1));
    }

    #[test]
    fn a_cycle_has_no_ranks_and_is_named() {
        let g = g(&[("a", &["b"]), ("b", &["c"]), ("c", &["a"]), ("d", &[])]);
        let c = g.cycles();
        assert_eq!(c.len(), 1);
        assert_eq!(c[0].len(), 3);
        assert!(g.ranks().is_err());
    }

    #[test]
    fn a_self_edge_is_a_cycle() {
        let g = g(&[("a", &["a"])]);
        assert_eq!(g.cycles().len(), 1);
    }
}
