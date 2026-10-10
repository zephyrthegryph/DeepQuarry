//! One borrowed current binding view used by namespace, inheritance and emission.
use crate::declaration_contributions::{DeclarationKey, KeyedDeclarations};
use crate::*;
use std::{
    collections::{BTreeMap, HashMap},
    ops::{Index, IndexMut},
};
#[derive(Clone, Copy)]
pub(crate) struct MemberView<'a> {
    pub definition: DefinitionMode,
    pub owner: TypeId,
    pub name: SymbolId,
    pub kind: MemberKind,
    pub metadata: &'a Arc<MemberMetadata>,
    pub content: u128,
    pub previous: Option<MemberId>,
}
impl MemberView<'_> {
    pub(crate) fn bind(self) -> MemberNode {
        MemberNode {
            definition: self.definition,
            owner: self.owner,
            name: self.name,
            kind: self.kind,
            metadata: Arc::clone(self.metadata),
            content: self.content,
            previous: self.previous,
        }
    }
    pub(crate) fn matches(self, node: &MemberNode) -> bool {
        self.definition == node.definition
            && self.owner == node.owner
            && self.name == node.name
            && self.kind == node.kind
            && self.content == node.content
            && self.previous == node.previous
            && (Arc::ptr_eq(self.metadata, &node.metadata) || self.metadata == &node.metadata)
    }
}
impl<'a> From<&'a MemberNode> for MemberView<'a> {
    fn from(node: &'a MemberNode) -> Self {
        Self {
            definition: node.definition,
            owner: node.owner,
            name: node.name,
            kind: node.kind,
            metadata: &node.metadata,
            content: node.content,
            previous: node.previous,
        }
    }
}
pub(crate) trait MemberRead {
    fn member(&self, index: usize) -> MemberView<'_>;
}
pub(crate) trait MemberWrite: MemberRead {
    fn set_previous(&mut self, index: usize, previous: Option<MemberId>);
    fn set_metadata(&mut self, index: usize, metadata: Arc<MemberMetadata>);
    fn install_namespace(
        &mut self,
        owner: SymbolId,
        rows: &Arc<[owner_normalization::ResolvedMember]>,
        projection: &CurrentProjection,
    ) {
        for row in rows.iter() {
            let index = projection.ids[&row.key].index();
            self.set_previous(index, row.previous.map(|key| projection.ids[&key]));
            self.set_metadata(index, Arc::clone(&row.metadata));
        }
        let _ = owner;
    }
}
impl<M: Index<usize, Output = MemberNode> + ?Sized> MemberRead for M {
    fn member(&self, index: usize) -> MemberView<'_> {
        (&self[index]).into()
    }
}
impl<M: Index<usize, Output = MemberNode> + IndexMut<usize> + ?Sized> MemberWrite for M {
    fn set_previous(&mut self, index: usize, previous: Option<MemberId>) {
        if self[index].previous != previous {
            self[index].previous = previous;
        }
    }
    fn set_metadata(&mut self, index: usize, metadata: Arc<MemberMetadata>) {
        if !(Arc::ptr_eq(&self[index].metadata, &metadata) || self[index].metadata == metadata) {
            self[index].metadata = metadata;
        }
    }
}
/// Stable key and owner-local row → CURRENT dense IDs, issued once by the builder.
pub(crate) struct CurrentProjection {
    pub keys: Vec<DeclarationKey>,
    pub ids: HashMap<DeclarationKey, MemberId>,
    pub owners: BTreeMap<SymbolId, Vec<usize>>,
    rows: Vec<usize>,
}
impl CurrentProjection {
    pub(crate) fn new(declarations: &KeyedDeclarations, count: usize) -> Option<Self> {
        let keys: Vec<_> = declarations
            .ordered()
            .filter_map(|row| matches!(row.skeleton, Skeleton::Member { .. }).then_some(row.key))
            .collect();
        if keys.len() != count {
            return None;
        }
        let mut owners = BTreeMap::<SymbolId, Vec<usize>>::new();
        let mut rows = Vec::with_capacity(count);
        let mut ids = HashMap::with_capacity(count);
        for (index, key) in keys.iter().enumerate() {
            let group = owners.entry(key.owner).or_default();
            rows.push(group.len());
            group.push(index);
            if ids
                .insert(*key, MemberId(u32::try_from(index).ok()?))
                .is_some()
            {
                return None;
            }
        }
        Some(Self {
            keys,
            ids,
            owners,
            rows,
        })
    }
}
/// Source metadata is borrowed. Admitted owner leaves are shared once per owner;
/// inheritance writes create only sparse current deltas, never a full node array.
pub(crate) struct MemberBindings<'a> {
    sources: Vec<MemberView<'a>>,
    projection: Option<&'a CurrentProjection>,
    normalized: owner_metadata::OwnerContributions,
    deltas: HashMap<usize, Arc<MemberMetadata>>,
    previous_deltas: HashMap<usize, Option<MemberId>>,
    #[cfg(test)]
    bound_nodes: std::cell::Cell<usize>,
}
impl<'a> MemberBindings<'a> {
    pub(crate) fn new(projection: Option<&'a CurrentProjection>) -> Self {
        Self {
            sources: Vec::new(),
            projection,
            normalized: BTreeMap::new(),
            deltas: HashMap::new(),
            previous_deltas: HashMap::new(),
            #[cfg(test)]
            bound_nodes: std::cell::Cell::new(0),
        }
    }
    pub(crate) fn len(&self) -> usize {
        self.sources.len()
    }
    pub(crate) fn push(&mut self, row: MemberView<'a>) {
        self.sources.push(row);
    }
    pub(crate) fn bind_node(&self, index: usize) -> MemberNode {
        #[cfg(test)]
        self.bound_nodes.set(self.bound_nodes.get() + 1);
        self.member(index).bind()
    }
    pub(crate) fn bind_all(&self) -> MemberArena {
        (0..self.len())
            .map(|index| self.bind_node(index))
            .collect::<Vec<_>>()
            .into()
    }
    #[cfg(test)]
    pub(crate) fn constructed_nodes(&self) -> usize {
        self.bound_nodes.get()
    }
}
impl MemberRead for MemberBindings<'_> {
    fn member(&self, index: usize) -> MemberView<'_> {
        let mut row: MemberView<'_> = self.sources[index];
        if let Some(projection) = self.projection {
            let key = projection.keys[index];
            if let Some(owner) = self.normalized.get(&key.owner) {
                let normalized = &owner[projection.rows[index]];
                debug_assert_eq!(normalized.key, key);
                row.metadata = &normalized.metadata;
                row.previous = normalized.previous.map(|key| projection.ids[&key]);
            }
        }
        if let Some(metadata) = self.deltas.get(&index) {
            row.metadata = metadata;
        }
        if let Some(previous) = self.previous_deltas.get(&index) {
            row.previous = *previous;
        }
        row
    }
}
impl MemberWrite for MemberBindings<'_> {
    fn set_previous(&mut self, index: usize, previous: Option<MemberId>) {
        if self.member(index).previous == previous {
            return;
        }
        self.sources[index].previous = previous;
        if self
            .projection
            .is_some_and(|projection| self.normalized.contains_key(&projection.keys[index].owner))
        {
            self.previous_deltas.insert(index, previous);
        }
    }
    fn set_metadata(&mut self, index: usize, metadata: Arc<MemberMetadata>) {
        let current = self.member(index).metadata;
        if !(Arc::ptr_eq(current, &metadata) || current == &metadata) {
            self.deltas.insert(index, metadata);
        }
    }
    fn install_namespace(
        &mut self,
        owner: SymbolId,
        rows: &Arc<[owner_normalization::ResolvedMember]>,
        projection: &CurrentProjection,
    ) {
        self.normalized.insert(owner, Arc::clone(rows));
        for index in &projection.owners[&owner] {
            self.deltas.remove(index);
            self.previous_deltas.remove(index);
        }
    }
}

#[cfg(test)]
mod tests;
