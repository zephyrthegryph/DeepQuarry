//! Operation-local compact facts for the original name-based global policy.
//! Not a type/procedure model, source authority, or another cache.
use crate::{global_policy::{Facts, GlobalIndex, Node}, key_policy_control as kc};
use std::ops::Range;

type Id = u32;
const EMPTY: Id = Id::MAX;

struct Name {
    text: String,
    hash: u64,
}

/// One string per unique policy name. The open-addressed index consists only of
/// admitted Vec storage, so its visible capacities have a concrete upper bound.
#[derive(Default)]
struct Names {
    values: Vec<Name>,
    slots: Vec<Id>,
}

fn vector<C: kc::Control, T>(c: &mut C, rows: &mut Vec<T>, wanted: usize) -> Result<(), C::Error> {
    if wanted <= rows.capacity() { return Ok(()) }
    if !C::CHECKED { rows.reserve_exact(wanted - rows.len()); return Ok(()) }
    let admitted = wanted.checked_mul(2).ok_or_else(|| c.overflow())?;
    kc::reserve(c, || admitted.checked_mul(std::mem::size_of::<T>())?.checked_add(64))?;
    rows.try_reserve_exact(wanted - rows.len()).map_err(|_| c.allocation_failed())?;
    if rows.capacity() > admitted { return Err(c.allocation_failed()) }
    Ok(())
}

fn push<C: kc::Control, T>(c: &mut C, rows: &mut Vec<T>, value: T) -> Result<(), C::Error> {
    if rows.len() == rows.capacity() {
        let wanted = rows.capacity().checked_mul(2).map(|n| n.max(4)).ok_or_else(|| c.overflow())?;
        vector(c, rows, wanted)?;
    }
    rows.push(value);
    Ok(())
}

impl Names {
    fn hash<C: kc::Control>(c: &mut C, value: &str) -> Result<u64, C::Error> {
        let mut hash = 0xcbf29ce484222325u64;
        for part in value.as_bytes().chunks(64) {
            c.checkpoint()?;
            for byte in part { hash = (hash ^ u64::from(*byte)).wrapping_mul(0x100000001b3); }
        }
        Ok(hash)
    }
    fn rehash<C: kc::Control>(&mut self, c: &mut C, count: usize) -> Result<(), C::Error> {
        let wanted = count.checked_mul(2).and_then(|n| n.max(8).checked_next_power_of_two()).ok_or_else(|| c.overflow())?;
        if wanted <= self.slots.len() { return Ok(()) }
        let mut replacement = Vec::new();
        vector(c, &mut replacement, wanted)?;
        replacement.resize(wanted, EMPTY);
        for (id, name) in self.values.iter().enumerate() {
            c.checkpoint()?;
            let mut at = name.hash as usize & (wanted - 1);
            while replacement[at] != EMPTY { c.checkpoint()?; at = (at + 1) & (wanted - 1); }
            replacement[at] = Id::try_from(id).map_err(|_| c.overflow())?;
        }
        self.slots = replacement;
        Ok(())
    }
    fn intern<C: kc::Control>(&mut self, c: &mut C, text: &str) -> Result<Id, C::Error> {
        let hash = Self::hash(c, text)?;
        if !self.slots.is_empty() {
            let mut at = hash as usize & (self.slots.len() - 1);
            while self.slots[at] != EMPTY {
                c.checkpoint()?;
                let id = self.slots[at];
                let old = &self.values[id as usize];
                if old.hash == hash && old.text == text { return Ok(id) }
                at = (at + 1) & (self.slots.len() - 1);
            }
        }
        let id = Id::try_from(self.values.len()).ok().filter(|id| *id != EMPTY).ok_or_else(|| c.overflow())?;
        let count = self.values.len().checked_add(1).ok_or_else(|| c.overflow())?;
        self.rehash(c, count)?;
        let name = Name { text: kc::own(c, text)?, hash };
        push(c, &mut self.values, name)?;
        let mut at = hash as usize & (self.slots.len() - 1);
        while self.slots[at] != EMPTY { c.checkpoint()?; at = (at + 1) & (self.slots.len() - 1); }
        self.slots[at] = id;
        Ok(id)
    }
    fn get(&self, id: Id) -> &str { &self.values[id as usize].text }
}

#[derive(Clone, Copy)]
pub(crate) enum Kind { Call = 0, Reference = 1, Write = 2, FieldWrite = 3 }

struct Row {
    name: Id,
    root: bool,
    ranges: [Range<Id>; 4],
}

struct Pending { name: Id, root: bool, starts: [Id; 4] }

pub(crate) struct Builder {
    names: Names,
    rows: Vec<Row>,
    edges: [Vec<Id>; 4],
    pending: Option<Pending>,
    typed_writes: Vec<(Id, Id)>,
}

impl Builder {
    pub(crate) fn new<C: kc::Control>(c: &mut C, original_row_bound: usize) -> Result<Self, C::Error> {
        let mut rows = Vec::new();
        vector(c, &mut rows, original_row_bound)?;
        Ok(Self { names: Names::default(), rows, edges: Default::default(), pending: None, typed_writes: Vec::new() })
    }
    pub(crate) fn begin<C: kc::Control>(&mut self, c: &mut C, name: &str, root: bool) -> Result<(), C::Error> {
        assert!(self.pending.is_none(), "one actual body contribution at a time");
        let mut starts = [0; 4];
        for (i, edge) in self.edges.iter().enumerate() { starts[i] = Id::try_from(edge.len()).map_err(|_| c.overflow())?; }
        self.pending = Some(Pending { name: self.names.intern(c, name)?, root, starts });
        Ok(())
    }
    pub(crate) fn edge<C: kc::Control>(&mut self, c: &mut C, kind: Kind, name: &str) -> Result<(), C::Error> {
        assert!(self.pending.is_some(), "edge requires its real body contribution");
        let id = self.names.intern(c, name)?;
        push(c, &mut self.edges[kind as usize], id)
    }
    pub(crate) fn finish<C: kc::Control>(&mut self, c: &mut C) -> Result<(), C::Error> {
        let pending = self.pending.take().expect("actual body contribution");
        let mut ranges = std::array::from_fn(|_| 0..0);
        for (kind, edges) in self.edges.iter_mut().enumerate() {
            c.checkpoint()?;
            let start = pending.starts[kind] as usize;
            edges[start..].sort_unstable();
            let mut end = start;
            for at in start..edges.len() {
                c.checkpoint()?;
                if end == start || edges[at] != edges[end - 1] { edges[end] = edges[at]; end += 1; }
            }
            edges.truncate(end);
            ranges[kind] = pending.starts[kind]..Id::try_from(end).map_err(|_| c.overflow())?;
        }
        push(c, &mut self.rows, Row { name: pending.name, root: pending.root, ranges })
    }
    /// Typed writes include test bodies, unlike the global boot graph.
    /// No body-local String crosses this boundary: persistent unique names
    /// are parent-funded here before copying out of the source scratch scope.
    pub(crate) fn typed_write<C: kc::Control>(&mut self, c: &mut C, owner: &str, variable: &str) -> Result<(), C::Error> {
        let owner = self.names.intern(c, owner)?;
        let variable = self.names.intern(c, variable)?;
        push(c, &mut self.typed_writes, (owner, variable))
    }
    pub(crate) fn write_rows<C: kc::Control>(&mut self, c: &mut C) -> Result<crate::write_policy::WriteRows, C::Error> {
        c.checkpoint()?;
        let names = &self.names;
        self.typed_writes.sort_unstable_by(|a,b| names.get(a.1).cmp(names.get(b.1)).then_with(||names.get(a.0).cmp(names.get(b.0))));
        self.typed_writes.dedup();
        c.checkpoint()?;
        crate::write_policy::WriteRows::from_sorted_pairs(self.typed_writes.iter().map(|(owner,var)|(names.get(*owner),names.get(*var))), c)
    }
    fn values(&self, row: usize, kind: Kind) -> &[Id] {
        let range = &self.rows[row].ranges[kind as usize];
        &self.edges[kind as usize][range.start as usize..range.end as usize]
    }
    pub(crate) fn from_facts<C: kc::Control>(nodes: &[(Node, Facts)], roots: &[bool], c: &mut C) -> Result<Self, C::Error> {
        assert_eq!(nodes.len(), roots.len());
        let mut graph = Self::new(c, nodes.len())?;
        for ((node, facts), root) in nodes.iter().zip(roots) {
            graph.begin(c, &node.1, *root)?;
            for (kind, names) in [(Kind::Call, &facts.calls), (Kind::Reference, &facts.refs), (Kind::Write, &facts.writes), (Kind::FieldWrite, &facts.field_writes)] {
                for name in names { graph.edge(c, kind, name)?; }
            }
            graph.finish(c)?;
        }
        Ok(graph)
    }
}

fn matching(rows: &[(Id, Id)], name: Id) -> impl Iterator<Item = usize> + '_ {
    let at = rows.partition_point(|(key, _)| *key < name);
    rows[at..].iter().take_while(move |(key, _)| *key == name).map(|(_, node)| *node as usize)
}

impl Builder {
    pub(crate) fn classify<C: kc::Control>(&self, c: &mut C) -> Result<GlobalIndex, C::Error> {
        assert!(self.pending.is_none());
        let mut definitions = Vec::new();
        vector(c, &mut definitions, self.rows.len())?;
        let mut callers = Vec::new();
        vector(c, &mut callers, self.edges[Kind::Call as usize].len())?;
        let mut references = Vec::new();
        vector(c, &mut references, self.edges[Kind::Reference as usize].len())?;
        for (i, row) in self.rows.iter().enumerate() {
            c.checkpoint()?;
            let id = Id::try_from(i).map_err(|_| c.overflow())?;
            definitions.push((row.name, id));
            callers.extend(self.values(i, Kind::Call).iter().map(|name| (*name, id)));
            references.extend_from_slice(self.values(i, Kind::Reference));
        }
        definitions.sort_unstable(); callers.sort_unstable(); references.sort_unstable(); references.dedup();
        let mut boot = Vec::new(); vector(c, &mut boot, self.rows.len())?; boot.resize(self.rows.len(), false);
        let mut stack = Vec::new(); vector(c, &mut stack, self.rows.len())?;
        for (i, row) in self.rows.iter().enumerate() { c.checkpoint()?; if row.root { boot[i] = true; stack.push(i); } }
        while let Some(i) = stack.pop() {
            c.checkpoint()?;
            for name in self.values(i, Kind::Call) {
                for next in matching(&definitions, *name) { c.checkpoint()?; if !boot[next] { boot[next] = true; stack.push(next); } }
            }
        }
        loop {
            let mut changed = false;
            for (i, row) in self.rows.iter().enumerate() {
                c.checkpoint()?;
                if !boot[i] || row.root { continue }
                let mut outside = references.binary_search(&row.name).is_ok();
                if !outside {
                    for caller in matching(&callers, row.name) { c.checkpoint()?; if !boot[caller] { outside = true; break } }
                }
                if outside {
                    boot[i] = false; changed = true;
                }
            }
            if !changed { break }
        }
        let mut out = GlobalIndex { boot_procs: boot.iter().filter(|v| **v).count(), ..Default::default() };
        for (kind, runtime_only, destination) in [
            (Kind::Write, false, &mut out.written),
            (Kind::Write, true, &mut out.runtime_written),
            (Kind::FieldWrite, true, &mut out.runtime_field_written),
        ] {
            let mut selected = Vec::new(); vector(c, &mut selected, self.edges[kind as usize].len())?;
            for (i, running) in boot.iter().enumerate() { c.checkpoint()?; if !runtime_only || !running { selected.extend_from_slice(self.values(i, kind)); } }
            selected.sort_unstable(); selected.dedup();
            kc::reserve(c, || selected.len().checked_mul(4)?.checked_mul(std::mem::size_of::<String>() + 1)?.checked_add(256))?;
            destination.try_reserve(selected.len()).map_err(|_| c.allocation_failed())?;
            if C::CHECKED && destination.capacity() > selected.len().checked_mul(4).ok_or_else(|| c.overflow())? { return Err(c.allocation_failed()) }
            for id in selected { c.checkpoint()?; destination.insert(kc::own(c, self.names.get(id))?); }
        }
        c.checkpoint()?;
        Ok(out)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    struct Limit { limit: usize, used: usize, polls: usize, stop: usize }
    impl kc::Control for Limit {
        type Error = &'static str;
        const CHECKED: bool = true;
        fn checkpoint(&mut self) -> Result<(), Self::Error> { self.polls += 1; if self.polls == self.stop { Err("actual stop") } else { Ok(()) } }
        fn reserve(&mut self, n: usize) -> Result<(), Self::Error> { let next = self.used.checked_add(n).ok_or("overflow")?; if next > self.limit { return Err("budget") } self.used = next; Ok(()) }
        fn overflow(&mut self) -> Self::Error { "overflow" }
        fn allocation_failed(&mut self) -> Self::Error { "allocation" }
    }
    #[test]
    fn compact_graph_keeps_every_roster_row_under_unchanged_policy_limit() {
        let count = 93_579;
        let mut c = Limit { limit: 64 * 1024 * 1024, used: 0, polls: 0, stop: usize::MAX };
        let mut graph = Builder::new(&mut c, count).unwrap();
        for i in 0..count {
            let name = if i == 0 { "root" } else if i == count - 1 { "tail" } else { "runtime" };
            graph.begin(&mut c, name, i == 0).unwrap();
            if i == 0 || i == count / 2 { graph.edge(&mut c, Kind::Call, "tail").unwrap(); }
            if i == count - 1 { graph.edge(&mut c, Kind::Write, "last_value").unwrap(); }
            graph.finish(&mut c).unwrap();
        }
        assert_eq!(graph.rows.len(), count, "no truncation or per-page clean answer");
        let result = graph.classify(&mut c).unwrap();
        assert_eq!(result.boot_procs, 1);
        assert!(result.is_written("last_value"));
        assert!(!result.constant_after_init("last_value"), "outside caller retracts reachable tail");
        assert!(c.used < c.limit);
    }
    #[test]
    fn compact_graph_refuses_before_allocation_and_retries_without_a_failed_value() {
        let mut denied = Limit { limit: 128, used: 0, polls: 0, stop: usize::MAX };
        assert!(matches!(Builder::new(&mut denied, 93_579), Err("budget")));
        assert_eq!(denied.used, 0);
        let mut c = Limit { limit: 1024 * 1024, used: 0, polls: 0, stop: usize::MAX };
        let mut graph = Builder::new(&mut c, 2).unwrap();
        graph.begin(&mut c, "root", true).unwrap(); graph.edge(&mut c, Kind::Call, "child").unwrap(); graph.finish(&mut c).unwrap();
        graph.begin(&mut c, "child", false).unwrap(); graph.edge(&mut c, Kind::Write, "only_boot").unwrap(); graph.finish(&mut c).unwrap();
        c.stop = c.polls + 3;
        assert!(matches!(graph.classify(&mut c), Err("actual stop")));
        let result = graph.classify(&mut c).unwrap();
        assert_eq!(result.boot_procs, 2); assert!(result.is_written("only_boot")); assert!(result.constant_after_init("only_boot"));
    }

    #[test]
    fn compact_typed_pairs_preserve_complete_old_union_and_untyped_rows() {
        let mut c=Limit{limit:4*1024*1024,used:0,polls:0,stop:usize::MAX};
        let mut graph=Builder::new(&mut c,0).unwrap();
        let pairs=[("/base","charge"),("/child","charge"),("?","charge"),("/base","charge"),("?","wild"),("/base","only")];
        for(owner,var)in pairs{graph.typed_write(&mut c,owner,var).unwrap();}
        let result=graph.write_rows(&mut c).unwrap();
        let old=crate::write_policy::WriteIndex::from_facts(vec![pairs.into_iter().map(|(o,v)|(o.to_owned(),v.to_owned())).collect()]).into_rows(&mut kc::Compatibility).unwrap();
        let observed=serde_json::to_value(&result).unwrap();assert_eq!(observed,serde_json::to_value(&old).unwrap());
        assert_eq!(observed,serde_json::json!({"written":["charge","only","wild"],"untyped":["charge","wild"],"typed":{"charge":["/base","/child"],"only":["/base"]}}));
    }
}
