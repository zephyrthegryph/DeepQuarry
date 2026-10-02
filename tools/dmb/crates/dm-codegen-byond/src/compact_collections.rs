//! Small immutable owner inventories beneath persistent project indexes.
//!
//! A persistent B-tree reserves a large fixed leaf even for an empty inventory.
//! Owner-local declarations are usually empty or tiny, so use compact standard
//! B-trees behind a shared pointer. Mutation copies only this owner's inventory.
use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, BTreeSet};
use std::ops::{Deref, DerefMut};
use std::sync::Arc;

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(transparent)]
pub struct CompactMap<K: Ord, V>(Arc<BTreeMap<K, V>>);

impl<K: Ord, V> Default for CompactMap<K, V> {
    fn default() -> Self { Self(Arc::new(BTreeMap::new())) }
}
impl<K: Ord, V> CompactMap<K, V> {
    /// Allocation identity for accounting shared immutable inventories once.
    pub fn allocation_id(&self) -> usize { Arc::as_ptr(&self.0) as usize }
    /// Conservative standard B-tree node reservation, excluding key/value heaps.
    pub fn storage_bytes(&self) -> usize {
        16 + std::mem::size_of::<BTreeMap<K, V>>()
            + self.len().div_ceil(6) * (11 * std::mem::size_of::<(K, V)>() + 12 * std::mem::size_of::<usize>() + 64)
    }
}
impl<K: Ord, V> Deref for CompactMap<K, V> {
    type Target = BTreeMap<K, V>;
    fn deref(&self) -> &Self::Target { &self.0 }
}
impl<K: Ord + Clone, V: Clone> DerefMut for CompactMap<K, V> {
    fn deref_mut(&mut self) -> &mut Self::Target { Arc::make_mut(&mut self.0) }
}
impl<K: Ord, V> FromIterator<(K, V)> for CompactMap<K, V> {
    fn from_iter<T: IntoIterator<Item = (K, V)>>(items: T) -> Self {
        Self(Arc::new(items.into_iter().collect()))
    }
}
impl<K: Ord + Clone, V: Clone> Extend<(K, V)> for CompactMap<K, V> {
    fn extend<T: IntoIterator<Item = (K, V)>>(&mut self, items: T) {
        Arc::make_mut(&mut self.0).extend(items);
    }
}
impl<K: Ord + Clone, V: Clone> IntoIterator for CompactMap<K, V> {
    type Item = (K, V);
    type IntoIter = std::collections::btree_map::IntoIter<K, V>;
    fn into_iter(self) -> Self::IntoIter {
        Arc::try_unwrap(self.0).unwrap_or_else(|shared| (*shared).clone()).into_iter()
    }
}
impl<'a, K: Ord, V> IntoIterator for &'a CompactMap<K, V> {
    type Item = (&'a K, &'a V);
    type IntoIter = std::collections::btree_map::Iter<'a, K, V>;
    fn into_iter(self) -> Self::IntoIter { self.0.iter() }
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(transparent)]
pub struct CompactSet<T: Ord>(Arc<BTreeSet<T>>);

impl<T: Ord> Default for CompactSet<T> {
    fn default() -> Self { Self(Arc::new(BTreeSet::new())) }
}
impl<T: Ord> CompactSet<T> {
    /// Allocation identity for accounting shared immutable inventories once.
    pub fn allocation_id(&self) -> usize { Arc::as_ptr(&self.0) as usize }
    /// Conservative standard B-tree node reservation, excluding element heaps.
    pub fn storage_bytes(&self) -> usize {
        16 + std::mem::size_of::<BTreeSet<T>>()
            + self.len().div_ceil(6) * (11 * std::mem::size_of::<T>() + 12 * std::mem::size_of::<usize>() + 64)
    }
}
impl<T: Ord> Deref for CompactSet<T> {
    type Target = BTreeSet<T>;
    fn deref(&self) -> &Self::Target { &self.0 }
}
impl<T: Ord + Clone> DerefMut for CompactSet<T> {
    fn deref_mut(&mut self) -> &mut Self::Target { Arc::make_mut(&mut self.0) }
}
impl<T: Ord> FromIterator<T> for CompactSet<T> {
    fn from_iter<I: IntoIterator<Item = T>>(items: I) -> Self {
        Self(Arc::new(items.into_iter().collect()))
    }
}
impl<T: Ord + Clone> Extend<T> for CompactSet<T> {
    fn extend<I: IntoIterator<Item = T>>(&mut self, items: I) {
        Arc::make_mut(&mut self.0).extend(items);
    }
}
impl<T: Ord + Clone> IntoIterator for CompactSet<T> {
    type Item = T;
    type IntoIter = std::collections::btree_set::IntoIter<T>;
    fn into_iter(self) -> Self::IntoIter {
        Arc::try_unwrap(self.0).unwrap_or_else(|shared| (*shared).clone()).into_iter()
    }
}
impl<'a, T: Ord> IntoIterator for &'a CompactSet<T> {
    type Item = &'a T;
    type IntoIter = std::collections::btree_set::Iter<'a, T>;
    fn into_iter(self) -> Self::IntoIter { self.0.iter() }
}
