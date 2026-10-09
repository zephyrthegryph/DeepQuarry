//! Immutable declaration leaves with a borrowed ordered projection.
use crate::Skeleton;
use std::{
    ops::{Index, Range},
    sync::Arc,
};
#[derive(Clone, Debug, Default)]
pub(crate) struct SkeletonRoster {
    chunks: Vec<Arc<Vec<Skeleton>>>,
    prefix: Vec<usize>,
    len: usize,
}
impl SkeletonRoster {
    pub(crate) fn from_owned(rows: Vec<Skeleton>) -> Self {
        let mut roster = Self::default();
        roster.push_leaf(Arc::new(rows));
        roster
    }
    pub(crate) fn push_leaf(&mut self, leaf: Arc<Vec<Skeleton>>) {
        if leaf.is_empty() {
            return;
        }
        self.prefix.push(self.len);
        self.len += leaf.len();
        self.chunks.push(leaf);
    }
    pub(crate) fn append(&mut self, other: Self) {
        for leaf in other.chunks {
            self.push_leaf(leaf);
        }
    }
    pub(crate) fn len(&self) -> usize {
        self.len
    }
    pub(crate) fn iter(&self) -> SkeletonIter<'_> {
        SkeletonView::from(self).iter()
    }
    pub(crate) fn view(&self) -> SkeletonView<'_> {
        self.into()
    }
    pub(crate) fn to_vec(&self) -> Vec<Skeleton> {
        self.iter().cloned().collect()
    }
    fn get(&self, index: usize) -> Option<&Skeleton> {
        if index >= self.len {
            return None;
        }
        let chunk = self.prefix.partition_point(|&begin| begin <= index) - 1;
        self.chunks[chunk].get(index - self.prefix[chunk])
    }
}
impl Index<usize> for SkeletonRoster {
    type Output = Skeleton;
    fn index(&self, index: usize) -> &Skeleton {
        self.get(index).expect("skeleton index within roster")
    }
}
#[derive(Clone, Copy)]
enum Backing<'a> {
    Flat(&'a [Skeleton]),
    Shared(&'a SkeletonRoster),
}
#[derive(Clone, Copy)]
pub(crate) struct SkeletonView<'a> {
    backing: Backing<'a>,
    begin: usize,
    len: usize,
}
impl<'a> SkeletonView<'a> {
    pub(crate) fn len(self) -> usize {
        self.len
    }
    pub(crate) fn get(self, index: usize) -> Option<&'a Skeleton> {
        if index >= self.len {
            return None;
        }
        match self.backing {
            Backing::Flat(rows) => rows.get(self.begin + index),
            Backing::Shared(roster) => roster.get(self.begin + index),
        }
    }
    pub(crate) fn slice(self, range: Range<usize>) -> Self {
        assert!(range.start <= range.end && range.end <= self.len);
        Self {
            backing: self.backing,
            begin: self.begin + range.start,
            len: range.end - range.start,
        }
    }
    /// Compatibility diagnostics only; production resolution borrows the roster.
    pub(crate) fn to_vec(self) -> Vec<Skeleton> {
        self.iter().cloned().collect()
    }
    pub(crate) fn iter(self) -> SkeletonIter<'a> {
        SkeletonIter {
            view: self,
            front: 0,
            back: self.len,
            front_chunk: match self.backing {
                Backing::Shared(roster) if self.len != 0 => {
                    roster.prefix.partition_point(|&begin| begin <= self.begin) - 1
                }
                _ => 0,
            },
            back_chunk: match self.backing {
                Backing::Shared(roster) if self.len != 0 => {
                    roster
                        .prefix
                        .partition_point(|&begin| begin < self.begin + self.len)
                        - 1
                }
                _ => 0,
            },
        }
    }
}
impl<'a> From<&'a [Skeleton]> for SkeletonView<'a> {
    fn from(rows: &'a [Skeleton]) -> Self {
        Self {
            backing: Backing::Flat(rows),
            begin: 0,
            len: rows.len(),
        }
    }
}
impl<'a> From<&'a Vec<Skeleton>> for SkeletonView<'a> {
    fn from(rows: &'a Vec<Skeleton>) -> Self {
        rows.as_slice().into()
    }
}
impl<'a, const N: usize> From<&'a [Skeleton; N]> for SkeletonView<'a> {
    fn from(rows: &'a [Skeleton; N]) -> Self {
        rows.as_slice().into()
    }
}
impl<'a> From<&'a SkeletonRoster> for SkeletonView<'a> {
    fn from(rows: &'a SkeletonRoster) -> Self {
        Self {
            backing: Backing::Shared(rows),
            begin: 0,
            len: rows.len,
        }
    }
}
impl Index<usize> for SkeletonView<'_> {
    type Output = Skeleton;
    fn index(&self, index: usize) -> &Skeleton {
        self.get(index).expect("skeleton index within view")
    }
}
#[derive(Clone)]
pub(crate) struct SkeletonIter<'a> {
    view: SkeletonView<'a>,
    front: usize,
    back: usize,
    front_chunk: usize,
    back_chunk: usize,
}
impl<'a> Iterator for SkeletonIter<'a> {
    type Item = &'a Skeleton;
    fn next(&mut self) -> Option<Self::Item> {
        if self.front == self.back {
            return None;
        }
        let index = self.front;
        self.front += 1;
        match self.view.backing {
            Backing::Flat(rows) => rows.get(self.view.begin + index),
            Backing::Shared(roster) => {
                let absolute = self.view.begin + index;
                while self.front_chunk + 1 < roster.chunks.len()
                    && roster.prefix[self.front_chunk + 1] <= absolute
                {
                    self.front_chunk += 1;
                }
                roster.chunks[self.front_chunk].get(absolute - roster.prefix[self.front_chunk])
            }
        }
    }
    fn size_hint(&self) -> (usize, Option<usize>) {
        let remaining = self.back - self.front;
        (remaining, Some(remaining))
    }
}
impl DoubleEndedIterator for SkeletonIter<'_> {
    fn next_back(&mut self) -> Option<Self::Item> {
        if self.front == self.back {
            return None;
        }
        self.back -= 1;
        match self.view.backing {
            Backing::Flat(rows) => rows.get(self.view.begin + self.back),
            Backing::Shared(roster) => {
                let absolute = self.view.begin + self.back;
                while roster.prefix[self.back_chunk] > absolute {
                    self.back_chunk -= 1;
                }
                roster.chunks[self.back_chunk].get(absolute - roster.prefix[self.back_chunk])
            }
        }
    }
}
impl ExactSizeIterator for SkeletonIter<'_> {}
impl<'a> IntoIterator for SkeletonView<'a> {
    type Item = &'a Skeleton;
    type IntoIter = SkeletonIter<'a>;
    fn into_iter(self) -> Self::IntoIter {
        self.iter()
    }
}

impl PartialEq for SkeletonRoster {
    fn eq(&self, other: &Self) -> bool {
        self.len == other.len && self.iter().eq(other.iter())
    }
}
impl Eq for SkeletonRoster {}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn shared_roster_slices_and_mixed_direction_preserve_order() {
        let row = |id| Skeleton::Type {
            path: dm_ir::SymbolId::of_bytes(&[id]),
            explicit_parent: None,
        };
        let mut roster = SkeletonRoster::default();
        for id in 0..6 {
            roster.push_leaf(Arc::new(vec![row(id)]));
        }
        let expected = (1..5).map(row).collect::<Vec<_>>();
        let view = roster.view().slice(1..5);
        assert_eq!(view.iter().cloned().collect::<Vec<_>>(), expected);
        let mut iter = view.iter();
        assert_eq!(iter.next(), Some(&expected[0]));
        assert_eq!(iter.next_back(), Some(&expected[3]));
        assert_eq!(iter.next_back(), Some(&expected[2]));
        assert_eq!(iter.next(), Some(&expected[1]));
        assert!(iter.next().is_none());
        assert!(iter.next_back().is_none());
        assert_eq!(roster.view().slice(6..6).iter().len(), 0);
    }
}
