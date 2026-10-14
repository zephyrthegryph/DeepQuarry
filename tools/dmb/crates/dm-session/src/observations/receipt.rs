//! Shared immutable observation leaves; replay never flattens grouped storage.
use super::Observation;
use std::{slice, sync::Arc};

#[derive(Debug)]
pub struct Receipt<Q, A, D> {
    storage: Storage<Q, A, D>,
    len: usize,
}
#[derive(Debug)]
enum Storage<Q, A, D> {
    Flat(Arc<[Observation<Q, A, D>]>),
    Groups(Arc<[Arc<[Observation<Q, A, D>]>]>),
}
impl<Q, A, D> Clone for Receipt<Q, A, D> {
    fn clone(&self) -> Self {
        Self {
            len: self.len,
            storage: match &self.storage {
                Storage::Flat(value) => Storage::Flat(Arc::clone(value)),
                Storage::Groups(value) => Storage::Groups(Arc::clone(value)),
            },
        }
    }
}
pub enum ReceiptStorageView<'a, Q, A, D> {
    Flat(&'a Arc<[Observation<Q, A, D>]>),
    Groups(&'a Arc<[Arc<[Observation<Q, A, D>]>]>),
}
impl<Q, A, D> From<Arc<[Observation<Q, A, D>]>> for Receipt<Q, A, D> {
    fn from(value: Arc<[Observation<Q, A, D>]>) -> Self {
        Self {
            len: value.len(),
            storage: Storage::Flat(value),
        }
    }
}
impl<Q, A, D> From<Vec<Observation<Q, A, D>>> for Receipt<Q, A, D> {
    fn from(value: Vec<Observation<Q, A, D>>) -> Self {
        Self::from(Arc::from(value))
    }
}
impl<Q: Ord, A, D> Receipt<Q, A, D> {
    /// Leaves must already be canonical by query, including across boundaries.
    /// Equal queries are retained in supplied order: differing answers are proof
    /// obligations, not duplicates that may be discarded. No issuer is inferred.
    pub fn from_groups(groups: Arc<[Arc<[Observation<Q, A, D>]>]>) -> Result<Self, &'static str> {
        let mut previous = None;
        let mut len = 0usize;
        for group in groups.iter() {
            len = len
                .checked_add(group.len())
                .ok_or("receipt length overflow")?;
            for read in group.iter() {
                if previous.is_some_and(|query| query > &read.query) {
                    return Err("receipt groups are not in canonical query order");
                }
                previous = Some(&read.query);
            }
        }
        Ok(Self {
            len,
            storage: Storage::Groups(groups),
        })
    }
}
impl<Q, A, D> Receipt<Q, A, D> {
    pub fn len(&self) -> usize {
        self.len
    }
    pub fn is_empty(&self) -> bool {
        self.len == 0
    }
    pub fn flat(&self) -> Option<&Arc<[Observation<Q, A, D>]>> {
        match &self.storage {
            Storage::Flat(value) => Some(value),
            _ => None,
        }
    }
    /// Diagnostic storage only; groups and leaves are actual shared Arc owners.
    pub fn visit_storage(&self, mut visit: impl FnMut(ReceiptStorageView<'_, Q, A, D>)) {
        match &self.storage {
            Storage::Flat(value) => visit(ReceiptStorageView::Flat(value)),
            Storage::Groups(groups) => {
                visit(ReceiptStorageView::Groups(groups));
                for group in groups.iter() {
                    visit(ReceiptStorageView::Flat(group));
                }
            }
        }
    }
    pub fn iter(&self) -> ReceiptIter<'_, Q, A, D> {
        match &self.storage {
            Storage::Flat(value) => ReceiptIter {
                groups: None,
                current: value.iter(),
                remaining: self.len,
            },
            Storage::Groups(groups) => ReceiptIter {
                groups: Some(groups.iter()),
                current: [].iter(),
                remaining: self.len,
            },
        }
    }
    pub fn get(&self, index: usize) -> Option<&Observation<Q, A, D>> {
        self.iter().nth(index)
    }
}
impl<Q: Clone, A: Clone, D: Clone> Receipt<Q, A, D> {
    /// Compatibility materialization is explicit; hot replay uses iter().
    pub fn to_flat(&self) -> Arc<[Observation<Q, A, D>]> {
        self.flat()
            .map(Arc::clone)
            .unwrap_or_else(|| self.iter().cloned().collect::<Vec<_>>().into())
    }
}
impl<Q: PartialEq, A: PartialEq, D: PartialEq> PartialEq for Receipt<Q, A, D> {
    fn eq(&self, other: &Self) -> bool {
        self.len == other.len && self.iter().eq(other.iter())
    }
}
impl<Q: Eq, A: Eq, D: Eq> Eq for Receipt<Q, A, D> {}
impl<Q, A, D> std::ops::Index<usize> for Receipt<Q, A, D> {
    type Output = Observation<Q, A, D>;
    fn index(&self, index: usize) -> &Self::Output {
        self.get(index).expect("receipt index out of bounds")
    }
}
pub struct ReceiptIter<'a, Q, A, D> {
    groups: Option<slice::Iter<'a, Arc<[Observation<Q, A, D>]>>>,
    current: slice::Iter<'a, Observation<Q, A, D>>,
    remaining: usize,
}
impl<'a, Q, A, D> Iterator for ReceiptIter<'a, Q, A, D> {
    type Item = &'a Observation<Q, A, D>;
    fn next(&mut self) -> Option<Self::Item> {
        loop {
            if let Some(read) = self.current.next() {
                self.remaining -= 1;
                return Some(read);
            }
            self.current = self.groups.as_mut()?.next()?.iter();
        }
    }
    fn size_hint(&self) -> (usize, Option<usize>) {
        (self.remaining, Some(self.remaining))
    }
}
impl<Q, A, D> ExactSizeIterator for ReceiptIter<'_, Q, A, D> {}
impl<'a, Q, A, D> IntoIterator for &'a Receipt<Q, A, D> {
    type Item = &'a Observation<Q, A, D>;
    type IntoIter = ReceiptIter<'a, Q, A, D>;
    fn into_iter(self) -> Self::IntoIter {
        self.iter()
    }
}
#[cfg(test)]
mod tests;
