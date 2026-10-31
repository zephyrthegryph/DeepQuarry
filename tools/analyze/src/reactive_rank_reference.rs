// Independent original rank/cycle algorithms; no native/shared calls.
use std::collections::{BTreeMap,BTreeSet};
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
