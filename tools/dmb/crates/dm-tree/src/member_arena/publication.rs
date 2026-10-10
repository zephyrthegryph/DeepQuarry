//! Latest physical publication; semantic and dense bindings are already current.
use super::*;
use crate::declaration_contributions::DeclarationKey;
use std::collections::BTreeMap;

pub(crate) struct MemberPublication {
    arena: MemberArena,
    keys: Vec<Arc<[DeclarationKey]>>,
    index: BTreeMap<DeclarationKey, usize>,
}
impl MemberPublication {
    pub(crate) fn arena(&self) -> &MemberArena {
        &self.arena
    }
    pub(crate) fn index_len(&self) -> usize {
        self.index.len()
    }
    pub(crate) fn publish(
        nodes: Vec<MemberNode>,
        keys: Vec<DeclarationKey>,
        previous: Option<&Self>,
    ) -> Self {
        assert_eq!(nodes.len(), keys.len(), "current publication key coverage");
        let len = nodes.len();
        let mut remaining = nodes.into_iter();
        let mut chunks = Vec::new();
        let mut key_chunks = Vec::new();
        let mut offsets = Vec::new();
        let mut index = BTreeMap::new();
        let mut start = 0;
        while start < len {
            let owner = keys[start].owner;
            let count = keys[start..]
                .iter()
                .take(CHUNK)
                .take_while(|key| key.owner == owner)
                .count();
            let current_keys = &keys[start..start + count];
            let old = previous
                .and_then(|old| old.index.get(&current_keys[0]).map(|&i| (old, i)))
                .filter(|(old, i)| old.keys[*i].as_ref() == current_keys)
                .filter(|(old, i)| {
                    old.arena.chunks[*i]
                        .iter()
                        .eq(remaining.as_slice()[..count].iter())
                });
            let (chunk, key_chunk) = if let Some((old, i)) = old {
                // Complete final value equality includes CURRENT owner and previous
                // dense IDs. No stable key or pointer alone authorizes reuse.
                for _ in 0..count {
                    remaining.next();
                }
                (Arc::clone(&old.arena.chunks[i]), Arc::clone(&old.keys[i]))
            } else {
                (
                    remaining.by_ref().take(count).collect::<Vec<_>>().into(),
                    Arc::from(current_keys),
                )
            };
            index.insert(current_keys[0], chunks.len());
            offsets.push(start);
            chunks.push(chunk);
            key_chunks.push(key_chunk);
            start += count;
        }
        let fixed = offsets
            .iter()
            .enumerate()
            .all(|(index, &offset)| offset == index * CHUNK);
        Self {
            arena: MemberArena {
                chunks,
                len,
                offsets: offsets.into(),
                fixed,
            },
            keys: key_chunks,
            index,
        }
    }
    /// Known descriptor/slice storage only; BTree allocation is explicitly private.
    pub(crate) fn visit_storage(&self, mut visit: impl FnMut(usize, usize, usize)) {
        fn vec<T>(value: &Vec<T>, visit: &mut impl FnMut(usize, usize, usize)) {
            visit(
                value.as_ptr() as usize,
                value.len() * std::mem::size_of::<T>(),
                value.capacity() * std::mem::size_of::<T>(),
            );
        }
        fn slice<T>(value: &[T], visit: &mut impl FnMut(usize, usize, usize)) {
            let bytes = std::mem::size_of_val(value);
            visit(value.as_ptr() as usize, bytes, bytes);
        }
        vec(&self.arena.chunks, &mut visit);
        slice(&self.arena.offsets, &mut visit);
        for chunk in &self.arena.chunks {
            slice(chunk, &mut visit);
        }
        vec(&self.keys, &mut visit);
        for keys in &self.keys {
            slice(keys, &mut visit);
        }
    }
}
#[cfg(test)]
mod tests;
