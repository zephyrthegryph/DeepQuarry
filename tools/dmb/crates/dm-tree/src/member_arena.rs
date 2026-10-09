//! Immutable ordered semantic members with bounded copy-on-write updates.
use crate::MemberNode;
use std::{
    ops::{Index, IndexMut},
    sync::Arc,
};
const CHUNK: usize = 128;
#[derive(Clone, Debug, Default)]
pub struct MemberArena {
    chunks: Vec<Arc<[MemberNode]>>,
    len: usize,
}
impl MemberArena {
    pub fn len(&self) -> usize {
        self.len
    }
    pub fn is_empty(&self) -> bool {
        self.len == 0
    }
    pub fn get(&self, index: usize) -> Option<&MemberNode> {
        if index >= self.len {
            return None;
        }
        self.chunks.get(index / CHUNK)?.get(index % CHUNK)
    }
    pub fn iter(&self) -> impl ExactSizeIterator<Item = &MemberNode> + DoubleEndedIterator + Clone {
        (0..self.len).map(|index| &self[index])
    }
    /// Exact immutable backing for diagnostic owner census; no materialization.
    pub fn chunks(&self) -> &[Arc<[MemberNode]>] {
        &self.chunks
    }
    pub fn chunk_roster_capacity(&self) -> usize {
        self.chunks.capacity()
    }
}
impl From<Vec<MemberNode>> for MemberArena {
    fn from(nodes: Vec<MemberNode>) -> Self {
        let len = nodes.len();
        let mut nodes = nodes.into_iter();
        let mut chunks = Vec::with_capacity(len.div_ceil(CHUNK));
        while !nodes.as_slice().is_empty() {
            let chunk: Vec<_> = nodes.by_ref().take(CHUNK).collect();
            chunks.push(chunk.into());
        }
        Self { chunks, len }
    }
}
impl Index<usize> for MemberArena {
    type Output = MemberNode;
    fn index(&self, index: usize) -> &MemberNode {
        self.get(index)
            .expect("semantic member index out of bounds")
    }
}
impl IndexMut<usize> for MemberArena {
    fn index_mut(&mut self, index: usize) -> &mut MemberNode {
        assert!(index < self.len, "semantic member index out of bounds");
        &mut Arc::make_mut(&mut self.chunks[index / CHUNK])[index % CHUNK]
    }
}
impl<'a> IntoIterator for &'a MemberArena {
    type Item = &'a MemberNode;
    type IntoIter = MemberIter<'a>;
    fn into_iter(self) -> Self::IntoIter {
        MemberIter {
            arena: self,
            front: 0,
            back: self.len,
        }
    }
}
pub struct MemberIter<'a> {
    arena: &'a MemberArena,
    front: usize,
    back: usize,
}
impl<'a> Iterator for MemberIter<'a> {
    type Item = &'a MemberNode;
    fn next(&mut self) -> Option<Self::Item> {
        if self.front == self.back {
            return None;
        }
        let index = self.front;
        self.front += 1;
        Some(&self.arena[index])
    }
    fn size_hint(&self) -> (usize, Option<usize>) {
        let n = self.back - self.front;
        (n, Some(n))
    }
}
impl DoubleEndedIterator for MemberIter<'_> {
    fn next_back(&mut self) -> Option<Self::Item> {
        if self.front == self.back {
            return None;
        }
        self.back -= 1;
        Some(&self.arena[self.back])
    }
}
impl ExactSizeIterator for MemberIter<'_> {}
