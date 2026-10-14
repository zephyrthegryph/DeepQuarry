//! Immutable ordered semantic members with bounded copy-on-write updates.
use crate::MemberNode;
use std::{
    ops::{Index, IndexMut},
    sync::Arc,
};
pub(crate) const CHUNK: usize = 128;
mod publication;
pub(crate) use publication::MemberPublication;
#[derive(Clone, Debug, Default)]
pub struct MemberArena {
    chunks: Vec<Arc<[MemberNode]>>,
    len: usize,
    offsets: Arc<[usize]>,
    fixed: bool,
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
        let chunk = self.chunk_at(index);
        self.chunks.get(chunk)?.get(index - self.offsets[chunk])
    }
    pub fn iter(&self) -> MemberIter<'_> {
        self.into_iter()
    }
    fn chunk_at(&self, index: usize) -> usize {
        if self.fixed {
            index / CHUNK
        } else {
            self.offsets.partition_point(|&start| start <= index) - 1
        }
    }
    pub fn chunk_offsets(&self) -> &Arc<[usize]> {
        &self.offsets
    }
    /// Exact immutable backing for diagnostic owner census; no materialization.
    pub fn chunks(&self) -> &[Arc<[MemberNode]>] {
        &self.chunks
    }
    pub fn chunk_roster_capacity(&self) -> usize {
        self.chunks.capacity()
    }
}
impl MemberArena {
    /// Arena from `nodes` that shares the previous arena's longest prefix of
    /// equal chunks (same boundaries and nodes), then fixed-size chunks.
    /// Dense IDs shift after the first inserted or removed member, so only the
    /// prefix can be shared; this keeps snapshot copy-on-write for it.
    pub(crate) fn from_reusing(nodes: Vec<MemberNode>, previous: &MemberArena) -> Self {
        let mut chunks = Vec::new();
        let mut offsets = Vec::new();
        let mut position = 0;
        for (index, old) in previous.chunks.iter().enumerate() {
            let start = previous.offsets[index];
            let end = start + old.len();
            if start != position || end > nodes.len() || nodes[start..end] != old[..] {
                break;
            }
            chunks.push(Arc::clone(old));
            offsets.push(start);
            position = end;
        }
        let len = nodes.len();
        let mut rest = nodes.into_iter().skip(position).peekable();
        while rest.peek().is_some() {
            let chunk: Vec<_> = rest.by_ref().take(CHUNK).collect();
            offsets.push(position);
            position += chunk.len();
            chunks.push(chunk.into());
        }
        let fixed = offsets.iter().enumerate().all(|(index, &start)| start == index * CHUNK)
            && chunks.iter().rev().skip(1).all(|chunk| chunk.len() == CHUNK);
        Self {
            chunks,
            len,
            offsets: offsets.into(),
            fixed,
        }
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
        let offsets = (0..chunks.len())
            .map(|index| index * CHUNK)
            .collect::<Vec<_>>()
            .into();
        Self {
            chunks,
            len,
            offsets,
            fixed: true,
        }
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
        let chunk = self.chunk_at(index);
        &mut Arc::make_mut(&mut self.chunks[chunk])[index - self.offsets[chunk]]
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
            front_chunk: 0,
            back_chunk: self.chunks.len().saturating_sub(1),
        }
    }
}
#[derive(Clone)]
pub struct MemberIter<'a> {
    arena: &'a MemberArena,
    front: usize,
    back: usize,
    front_chunk: usize,
    back_chunk: usize,
}
impl<'a> Iterator for MemberIter<'a> {
    type Item = &'a MemberNode;
    fn next(&mut self) -> Option<Self::Item> {
        if self.front == self.back {
            return None;
        }
        let index = self.front;
        self.front += 1;
        while self.front_chunk + 1 < self.arena.chunks.len()
            && index >= self.arena.offsets[self.front_chunk + 1]
        {
            self.front_chunk += 1;
        }
        Some(&self.arena.chunks[self.front_chunk][index - self.arena.offsets[self.front_chunk]])
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
        while self.back < self.arena.offsets[self.back_chunk] {
            self.back_chunk -= 1;
        }
        Some(&self.arena.chunks[self.back_chunk][self.back - self.arena.offsets[self.back_chunk]])
    }
}
impl ExactSizeIterator for MemberIter<'_> {}
