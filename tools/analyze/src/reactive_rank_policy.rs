//! SAME derived-value cycle/rank policy with bounded explicit traversal frames.
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


impl DepGraph{
 pub fn add(&mut self,id:&str,deps:impl IntoIterator<Item=String>,rel:&str,line:u32){let n=self.nodes.entry(id.to_owned()).or_default();n.deps.extend(deps);if n.rel.is_empty(){n.rel=rel.to_owned();n.line=line;}}
 pub fn cycles(&self)->Vec<Vec<String>>{match self.cycles_using(&mut||Ok::<_,std::convert::Infallible>(())){Ok(v)=>v,Err(never)=>match never{}}}
 fn cycles_using<E>(&self,poll:&mut impl FnMut()->Result<(),E>)->Result<Vec<Vec<String>>,E>{
  struct Frame<'a>{id:&'a str,children:std::collections::btree_set::Iter<'a,String>}
  let mut index:BTreeMap<&str,usize>=BTreeMap::new();let mut low:BTreeMap<&str,usize>=BTreeMap::new();let mut on=BTreeSet::new();let mut stack=Vec::new();let mut frames:Vec<Frame<'_>>=Vec::new();let mut next=0;let mut out=Vec::new();
  for root in self.nodes.keys(){poll()?;if index.contains_key(root.as_str()){continue}
   index.insert(root,next);low.insert(root,next);next+=1;stack.push(root.as_str());on.insert(root.as_str());frames.push(Frame{id:root,children:self.nodes[root].deps.iter()});
   while !frames.is_empty(){poll()?;let v=frames.last().unwrap().id;
    if let Some(w)=frames.last_mut().unwrap().children.next(){let w=w.as_str();if !self.nodes.contains_key(w){continue}if !index.contains_key(w){index.insert(w,next);low.insert(w,next);next+=1;stack.push(w);on.insert(w);frames.push(Frame{id:w,children:self.nodes[w].deps.iter()});}else if on.contains(w){let value=low[v].min(index[w]);low.insert(v,value);}continue}
    frames.pop();if low[v]==index[v]{let mut comp=Vec::new();loop{poll()?;let w=stack.pop().unwrap();on.remove(w);comp.push(w.to_owned());if w==v{break}}let selfloop=comp.len()==1&&self.nodes[v].deps.contains(v);if comp.len()>1||selfloop{comp.reverse();out.push(comp);}}
    if let Some(parent)=frames.last(){let value=low[parent.id].min(low[v]);low.insert(parent.id,value);}
   }
  }Ok(out)
 }
 pub fn ranks(&self)->Result<BTreeMap<String,u32>,Vec<Vec<String>>>{match self.ranks_using(&mut||Ok::<_,std::convert::Infallible>(())){Ok(v)=>v,Err(never)=>match never{}}}
 pub(crate) fn ranks_using<E>(&self,poll:&mut impl FnMut()->Result<(),E>)->Result<Result<BTreeMap<String,u32>,Vec<Vec<String>>>,E>{let cycles=self.cycles_using(poll)?;if !cycles.is_empty(){return Ok(Err(cycles))}
  struct Frame<'a>{id:&'a str,children:std::collections::btree_set::Iter<'a,String>,rank:u32}
  let mut ranks=BTreeMap::new();let mut frames:Vec<Frame<'_>>=Vec::new();
  for root in self.nodes.keys(){poll()?;if ranks.contains_key(root.as_str()){continue}frames.push(Frame{id:root,children:self.nodes[root].deps.iter(),rank:0});while !frames.is_empty(){poll()?;if let Some(d)=frames.last_mut().unwrap().children.next(){let d=d.as_str();if !self.nodes.contains_key(d){continue}if let Some(&rank)=ranks.get(d){let parent=frames.last_mut().unwrap();parent.rank=parent.rank.max(rank+1);}else{frames.push(Frame{id:d,children:self.nodes[d].deps.iter(),rank:0});}continue}let frame=frames.pop().unwrap();ranks.insert(frame.id.to_owned(),frame.rank);if let Some(parent)=frames.last_mut(){parent.rank=parent.rank.max(frame.rank+1);}}}
  Ok(Ok(ranks))
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


#[cfg(feature="native-policy")]
impl DepGraph{pub(crate) fn ranks_admitted(&self,budget:&crate::captured_generator_budget::Budget,poll:&dyn Fn()->std::io::Result<()>)->std::io::Result<Result<BTreeMap<String,u32>,Vec<Vec<String>>>>{poll()?;let overflow=||{budget.deny();std::io::Error::new(std::io::ErrorKind::OutOfMemory,"read rank graph admission overflow")};let mut width=0usize;let mut count=0usize;for(id,node)in &self.nodes{poll()?;width=width.checked_add(id.len()).ok_or_else(&overflow)?;count=count.checked_add(1).ok_or_else(&overflow)?;for dependency in &node.deps{width=width.checked_add(dependency.len()).ok_or_else(&overflow)?;count=count.checked_add(1).ok_or_else(&overflow)?;}}
 let bytes=width.checked_mul(16).and_then(|n|count.checked_mul(4096).and_then(|v|n.checked_add(v))).ok_or_else(&overflow)?;budget.charge(bytes).map_err(|actual|std::io::Error::new(std::io::ErrorKind::OutOfMemory,actual))?;let result=self.ranks_using(&mut||{poll()?;budget.require().map_err(|actual|std::io::Error::new(std::io::ErrorKind::OutOfMemory,actual))});if result.is_err(){return result}poll()?;result}}
#[cfg(test)]mod original_policy_tests{use super::*;mod original{include!("reactive_rank_reference.rs");}
 #[test]fn iterative_rank_policy_preserves_entire_original_cycle_chains_and_ranks(){for seed in 0..128usize{let mut now=DepGraph::default();let mut old=original::DepGraph::default();for i in 0..17{let name=format!("n{i:02}");let deps:Vec<_>=(0..17).filter(|j|(i*37+j*13+seed*23)%47==0).map(|j|format!("n{j:02}")).collect();now.add(&name,deps.clone(),"x.dm",1);old.add(&name,deps,"x.dm",1);}assert_eq!(now.cycles(),old.cycles());assert_eq!(now.ranks(),old.ranks());}}
 #[cfg(feature="native-policy")]
 #[test]fn native_rank_explicit_frames_handle_deep_chain_and_preserve_actual_io_quota_retry(){let mut graph=DepGraph::default();for i in 0..20000{graph.add(&format!("n{i:05}"),if i==0{vec![]}else{vec![format!("n{:05}",i-1)]},"x.dm",1);}let budget=crate::captured_generator_budget::Budget::new(256*1024*1024).unwrap();assert_eq!(graph.ranks_admitted(&budget,&||Ok(())).unwrap().unwrap()["n19999"],19999);let tiny=crate::captured_generator_budget::Budget::new(1024).unwrap();assert_eq!(graph.ranks_admitted(&tiny,&||Ok(())).unwrap_err().kind(),std::io::ErrorKind::OutOfMemory);assert!(tiny.denied());assert_eq!(graph.ranks_admitted(&budget,&||Err(std::io::Error::from_raw_os_error(1450))).unwrap_err().raw_os_error(),Some(1450));}
}

#[cfg(test)]#[test]fn rank_reference_is_exact_frozen_original_algorithm_projection(){let frozen=include_str!("reactive_rank_frozen_original.rs");let reference=include_str!("reactive_rank_reference.rs");let nodes=&frozen[frozen.find("#[derive(Debug, Default, Clone)]").unwrap()..frozen.find("impl DepGraph").unwrap()];let methods=&frozen[frozen.find("    /// Adds a node").unwrap()..frozen.find("/// `rank<TAB>node`").unwrap()];let methods=methods.strip_suffix("\n").unwrap_or(methods);let expected=format!("// Independent original rank/cycle algorithms; no native/shared calls.\nuse std::collections::{{BTreeMap,BTreeSet}};\n{nodes}impl DepGraph {{\n{methods}");assert_eq!(reference.trim(),expected.trim());}
