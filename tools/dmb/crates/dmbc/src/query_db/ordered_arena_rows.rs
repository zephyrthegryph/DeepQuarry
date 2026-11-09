use std::{alloc::{alloc, Layout}, io, mem::size_of, ptr::NonNull};

type Entry<V> = (usize, V);

// Fixed-capacity ordered leaves keep one source-admission growth small.
// A split allocates a new leaf and, rarely, a new top-level directory.
const LEAF: usize = 32;
const DIRECTORY_STEP: usize = 64;
const MAX_BATCH: usize = 6;

pub(super) struct OrderedArenaRows<V> {
    pages: Vec<Vec<Entry<V>>>,
}

pub(super) struct StagedInsert<'a, V> {
    store: &'a mut OrderedArenaRows<V>,
    key: usize,
    page: usize,
    slot: Result<usize, usize>,
    leaf: Option<Vec<Entry<V>>>,
    directory: Option<Vec<Vec<Entry<V>>>>,
}

pub(super) struct StagedBatch<'a, V, const N: usize> {
    store: &'a mut OrderedArenaRows<V>,
    sorted: [(usize, usize, usize); N],
    leaves: [Option<Vec<Entry<V>>>; N],
    directory: Option<Vec<Vec<Entry<V>>>>,
}

impl<V> Default for OrderedArenaRows<V> {
    fn default() -> Self {
        Self { pages: Vec::new() }
    }
}

impl<V> OrderedArenaRows<V> {
    fn position(&self, key: usize) -> Option<(usize, Result<usize, usize>)> {
        let page = self.pages.partition_point(|page| page.last().unwrap().0 < key)
            .min(self.pages.len().saturating_sub(1));
        Some((page, self.pages.get(page)?.binary_search_by_key(&key, |entry| entry.0)))
    }

    pub(super) fn get(&self, key: usize) -> Option<&V> {
        let (page, slot) = self.position(key)?;
        Some(&self.pages[page][slot.ok()?].1)
    }

    pub(super) fn get_mut(&mut self, key: usize) -> Option<&mut V> {
        let (page, slot) = self.position(key)?;
        Some(&mut self.pages[page][slot.ok()?].1)
    }

    pub(super) fn iter(&self) -> impl Iterator<Item = (usize, &V)> {
        self.pages.iter().flatten().map(|(key, value)| (*key, value))
    }

    pub(super) fn len(&self) -> usize {
        self.pages.iter().map(Vec::len).sum()
    }

    pub(super) fn visit_storage(&self, mut visit: impl FnMut(usize, usize, usize)) {
        fn column<T>(rows: &Vec<T>, visit: &mut impl FnMut(usize, usize, usize)) {
            if rows.capacity() != 0 {
                visit(rows.as_ptr() as usize, rows.len() * size_of::<T>(), rows.capacity() * size_of::<T>());
            }
        }
        column(&self.pages, &mut visit);
        for page in &self.pages { column(page, &mut visit); }
    }

    pub(super) fn retained_bytes(&self) -> usize {
        self.pages.capacity() * size_of::<Vec<Entry<V>>>()
            + self.pages.len() * LEAF * size_of::<Entry<V>>()
    }

    pub(super) fn stage_insert(
        &mut self, key: usize, admit_peak: impl FnOnce(usize) -> io::Result<()>,
    ) -> io::Result<StagedInsert<'_, V>> {
        let (page, slot) = self.position(key).unwrap_or((0, Err(0)));
        let needs_leaf = slot.is_err()
            && self.pages.get(page).is_none_or(|rows| rows.len() == LEAF);
        let directory_capacity = if needs_leaf && self.pages.len() == self.pages.capacity() {
            self.pages.len().checked_add(DIRECTORY_STEP).ok_or(io::ErrorKind::OutOfMemory)?
        } else { 0 };
        let leaf_bytes = usize::from(needs_leaf) * LEAF * size_of::<Entry<V>>();
        let dir_bytes = directory_capacity.checked_mul(size_of::<Vec<Entry<V>>>())
            .ok_or(io::ErrorKind::OutOfMemory)?;
        let new_bytes = leaf_bytes.checked_add(dir_bytes).ok_or(io::ErrorKind::OutOfMemory)?;
        if new_bytes != 0 { admit_peak(new_bytes)?; }
        let leaf = needs_leaf.then(|| exact_vec(LEAF)).transpose()?;
        let directory = (directory_capacity != 0).then(|| exact_vec(directory_capacity)).transpose()?;
        Ok(StagedInsert { store: self, key, page, slot, leaf, directory })
    }

    pub(super) fn growth_for(&self, key: usize) -> io::Result<usize> {
        if let Some((page, slot)) = self.position(key) {
            if slot.is_ok() || self.pages[page].len() < LEAF { return Ok(0); }
        }
        self.growth_for_leaves(1)
    }

    fn growth_for_leaves(&self, leaves: usize) -> io::Result<usize> {
        let next = self.directory_capacity_for(leaves)?;
        let directory = next.checked_mul(size_of::<Vec<Entry<V>>>())
            .ok_or(io::ErrorKind::OutOfMemory)?;
        leaves.checked_mul(LEAF * size_of::<Entry<V>>())
            .and_then(|bytes| bytes.checked_add(directory)).ok_or_else(|| io::ErrorKind::OutOfMemory.into())
    }

    fn directory_capacity_for(&self, leaves: usize) -> io::Result<usize> {
        let required = self.pages.len().checked_add(leaves).ok_or(io::ErrorKind::OutOfMemory)?;
        if required <= self.pages.capacity() { return Ok(0); }
        required.div_ceil(DIRECTORY_STEP).checked_mul(DIRECTORY_STEP)
            .ok_or_else(|| io::ErrorKind::OutOfMemory.into())
    }

    fn batch_plan<const N: usize>(&self, keys: [usize; N])
        -> io::Result<([(usize, usize, usize); N], usize)> {
        assert!(N <= MAX_BATCH, "bounded native source partition");
        let mut sorted = [(0, 0, 0); N];
        for (index, key) in keys.into_iter().enumerate() {
            let (page, slot) = self.position(key).unwrap_or((0, Err(0)));
            if slot.is_ok() { return Err(io::ErrorKind::InvalidInput.into()); }
            sorted[index] = (page, key, index);
        }
        sorted.sort_unstable();
        if sorted.windows(2).any(|pair| pair[0].1 == pair[1].1) {
            return Err(io::ErrorKind::InvalidInput.into());
        }
        let mut leaves = 0;
        for group in sorted.chunk_by(|a,b| a.0 == b.0) {
            let old = self.pages.get(group[0].0).map_or(0, Vec::len);
            leaves += (old + group.len()).div_ceil(LEAF) - usize::from(old != 0);
        }
        Ok((sorted, leaves))
    }

    pub(super) fn growth_for_batch<const N: usize>(&self, keys: [usize; N]) -> io::Result<usize> {
        let (_, leaves) = self.batch_plan(keys)?;
        self.growth_for_leaves(leaves)
    }

    pub(super) fn stage_batch<const N: usize>(&mut self, keys: [usize; N],
        admit_peak: impl FnOnce(usize) -> io::Result<()>) -> io::Result<StagedBatch<'_, V, N>> {
        let (sorted, count) = self.batch_plan(keys)?;
        let peak = self.growth_for_leaves(count)?;
        if peak != 0 { admit_peak(peak)?; }
        let capacity = self.directory_capacity_for(count)?;
        let directory = (capacity != 0).then(|| exact_vec(capacity)).transpose()?;
        let mut leaves = std::array::from_fn(|_| None);
        for leaf in &mut leaves[..count] { *leaf = Some(exact_vec(LEAF)?); }
        Ok(StagedBatch { store: self, sorted, leaves, directory })
    }

    pub(super) fn remove(&mut self, key: usize) -> Option<V> {
        let (page, slot) = self.position(key)?;
        let (_, value) = self.pages[page].remove(slot.ok()?);
        if self.pages[page].is_empty() {
            self.pages.remove(page);
        }
        let first = page.saturating_sub(1);
        if !self.merge_pair(first) {
            self.merge_pair(page);
        }
        if self.pages.is_empty() { self.pages = Vec::new(); }
        Some(value)
    }

    pub(super) fn retain(&mut self, mut keep: impl FnMut(usize, &mut V) -> bool) {
        for page in &mut self.pages {
            page.retain_mut(|(key, value)| keep(*key, value));
        }
        self.merge_underfull();
    }

    fn merge_underfull(&mut self) {
        self.pages.retain(|page| !page.is_empty());
        let mut at = 0;
        while at + 1 < self.pages.len() {
            if !self.merge_pair(at) { at += 1; }
        }
        if self.pages.is_empty() { self.pages = Vec::new(); }
    }

    fn merge_pair(&mut self, at: usize) -> bool {
        if at + 1 >= self.pages.len() || self.pages[at].len() + self.pages[at + 1].len() > LEAF {
            return false;
        }
        let mut next = self.pages.remove(at + 1);
        self.pages[at].append(&mut next);
        true
    }
}

impl<V> StagedInsert<'_, V> {
    // No allocation or fallible callback after moving a live row.
    pub(super) fn commit(mut self, value: V) -> Option<V> {
        let mut slot = match self.slot {
            Ok(slot) => return Some(std::mem::replace(&mut self.store.pages[self.page][slot].1, value)),
            Err(slot) => slot,
        };
        if let Some(mut directory) = self.directory.take() {
            directory.append(&mut self.store.pages);
            self.store.pages = directory;
        }
        if let Some(mut leaf) = self.leaf.take() {
            if self.store.pages.is_empty() {
                leaf.push((self.key, value));
                self.store.pages.push(leaf);
                return None;
            }
            leaf.extend(self.store.pages[self.page].drain(LEAF / 2..));
            self.store.pages.insert(self.page + 1, leaf);
            if slot >= LEAF / 2 {
                self.page += 1;
                slot -= LEAF / 2;
            }
        }
        self.store.pages[self.page].insert(slot, (self.key, value));
        None
    }
}

impl<V, const N: usize> StagedBatch<'_, V, N> {
    pub(super) fn commit(mut self, values: [V; N]) {
        let mut values = values.map(Some);
        if let Some(mut directory) = self.directory.take() {
            directory.append(&mut self.store.pages);
            self.store.pages = directory;
        }
        let mut spare = self.leaves.into_iter().flatten();
        for group in self.sorted.chunk_by(|a,b| a.0 == b.0).rev() {
            let page = group[0].0;
            let old_exists = !self.store.pages.is_empty();
            let mut rows = if old_exists { std::mem::take(&mut self.store.pages[page]) }
                else { spare.next().expect("first funded arena leaf") };
            let total = rows.len() + group.len();
            let page_count = total.div_ceil(LEAF);
            // Merge from high to low, preserving the existing allocation for
            // the low leaf. Only rows moved to a new leaf leave the old Vec.
            let mut new_rows = group.iter().rev().peekable();
            for local_page in (1..page_count).rev() {
                let target = total / page_count + usize::from(local_page < total % page_count);
                let mut next = spare.next().expect("funded arena split leaf");
                for _ in 0..target {
                    let use_new = new_rows.peek().is_some_and(|entry| {
                        rows.last().is_none_or(|old| entry.1 > old.0)
                    });
                    let entry = if use_new {
                        let &(_, key, index) = new_rows.next().unwrap();
                        (key, values[index].take().unwrap())
                    } else { rows.pop().unwrap() };
                    next.push(entry);
                }
                next.reverse();
                self.store.pages.insert(page + 1, next);
            }
            for &(_, key, index) in new_rows {
                let at = rows.binary_search_by_key(&key, |row| row.0).unwrap_err();
                rows.insert(at, (key, values[index].take().unwrap()));
            }
            if old_exists { self.store.pages[page] = rows; }
            else { self.store.pages.insert(0, rows); }
        }
        debug_assert!(spare.next().is_none());
    }
}

fn exact_vec<T>(count: usize) -> io::Result<Vec<T>> {
    let layout = Layout::array::<T>(count).map_err(|_| io::ErrorKind::OutOfMemory)?;
    assert_ne!(layout.size(), 0);
    // SAFETY: nonzero exact Global layout for T, without initialized elements.
    // Vec receives the original address and layout, then initializes on insert.
    let pointer = NonNull::new(unsafe { alloc(layout) }.cast::<T>())
        .ok_or(io::ErrorKind::OutOfMemory)?;
    Ok(unsafe { Vec::from_raw_parts(pointer.as_ptr(), 0, count) })
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::BTreeMap;

    #[test]
    fn ordered_leaves_preserve_reference_order_and_true_peak() {
        let mut rows = OrderedArenaRows::default();
        let mut old = BTreeMap::new();
        for n in 0..4096 {
            let key = n * 61 % 4096;
            let before = rows.retained_bytes();
            let mut peak = 0;
            let staged = rows.stage_insert(key, |delta| { peak = delta; Ok(()) }).unwrap();
            assert_eq!(staged.commit(key * 7), old.insert(key, key * 7));
            assert!(rows.retained_bytes() <= before + peak);
        }
        let order = |map: &OrderedArenaRows<usize>| map.iter().map(|(k,v)| (k,*v)).collect::<Vec<_>>();
        assert_eq!(order(&rows), old.iter().map(|(&k,&v)| (k,v)).collect::<Vec<_>>());
        let mut visited = Vec::new();
        rows.retain(|key, _| {
            visited.push(key);
            key % 31 == 0
        });
        assert_eq!(visited, (0..4096).collect::<Vec<_>>());
        assert!(rows.retained_bytes() < 4096 * 24);
        for key in (0..4096).step_by(31) { assert_eq!(rows.remove(key), Some(key * 7)); }
        assert_eq!(rows.retained_bytes(), 0);
    }

    #[test]
    fn batch_splits_two_leaves_without_partial_publication() {
        let mut rows = OrderedArenaRows::default();
        for key in (0..96).step_by(2) {
            rows.stage_insert(key, |_| Ok(())).unwrap().commit(key);
        }
        let keys = [93, 31, 91, 89, 87, 85];
        let peak = rows.growth_for_batch(keys).unwrap();
        assert!(peak > 0);
        let before: Vec<_> = rows.iter().map(|(key, _)| key).collect();
        assert!(rows.stage_batch(keys, |_| Err(io::ErrorKind::OutOfMemory.into())).is_err());
        assert_eq!(rows.iter().map(|(key, _)| key).collect::<Vec<_>>(), before);
        rows.stage_batch(keys, |bytes| { assert_eq!(bytes, peak); Ok(()) }).unwrap().commit(keys);
        let mut expected = before;
        expected.extend(keys);
        expected.sort_unstable();
        assert_eq!(rows.iter().map(|(key, _)| key).collect::<Vec<_>>(), expected);
    }

    #[test]
    fn denied_or_abandoned_peak_keeps_actual_old_leaves() {
        let mut rows = OrderedArenaRows::default();
        for key in 0..LEAF {
            rows.stage_insert(key, |_| Ok(())).unwrap().commit(key);
        }
        let before = rows.retained_bytes();
        let deny = rows.stage_insert(LEAF, |bytes| {
            assert_eq!(bytes, LEAF * size_of::<Entry<usize>>());
            Err(io::Error::from_raw_os_error(1450))
        });
        assert_eq!(deny.err().unwrap().raw_os_error(), Some(1450));
        drop(rows.stage_insert(LEAF, |_| Ok(())).unwrap());
        assert_eq!(rows.retained_bytes(), before);
        assert_eq!(rows.iter().count(), LEAF);
        assert!(rows.get(LEAF).is_none());
    }
}
