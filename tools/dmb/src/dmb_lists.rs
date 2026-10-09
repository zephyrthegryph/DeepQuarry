//! Shared immutable list payloads with copy-on-write mutation at the DMB boundary.
use std::{
    ops::{Index, IndexMut},
    sync::Arc,
};
#[derive(Clone, Debug, Default, PartialEq)]
pub struct WordLists(Vec<Arc<Vec<u32>>>);
impl WordLists {
    pub fn len(&self) -> usize {
        self.0.len()
    }
    pub fn is_empty(&self) -> bool {
        self.0.is_empty()
    }
    pub fn storage(&self) -> &Vec<Arc<Vec<u32>>> {
        &self.0
    }
    pub fn push(&mut self, words: Vec<u32>) {
        self.push_shared(Arc::new(words));
    }
    pub fn push_shared(&mut self, words: Arc<Vec<u32>>) {
        self.0.push(words);
    }
    pub fn get(&self, index: usize) -> Option<&Vec<u32>> {
        self.0.get(index).map(Arc::as_ref)
    }
    pub fn get_mut(&mut self, index: usize) -> Option<&mut Vec<u32>> {
        self.0.get_mut(index).map(Arc::make_mut)
    }
    pub fn last_mut(&mut self) -> Option<&mut Vec<u32>> {
        self.0.last_mut().map(Arc::make_mut)
    }
    pub fn shared(&self, index: usize) -> Option<&Arc<Vec<u32>>> {
        self.0.get(index)
    }
    pub fn iter(&self) -> impl DoubleEndedIterator<Item = &Vec<u32>> + ExactSizeIterator {
        self.0.iter().map(Arc::as_ref)
    }
    pub fn resize(&mut self, len: usize, words: Vec<u32>) {
        self.0.resize(len, Arc::new(words));
    }
    pub fn pop(&mut self) -> Option<Vec<u32>> {
        self.0
            .pop()
            .map(|v| Arc::try_unwrap(v).unwrap_or_else(|v| v.as_ref().clone()))
    }
    pub fn extend(&mut self, words: impl IntoIterator<Item = Vec<u32>>) {
        for words in words {
            self.push(words);
        }
    }
}
impl From<Vec<Vec<u32>>> for WordLists {
    fn from(words: Vec<Vec<u32>>) -> Self {
        Self(words.into_iter().map(Arc::new).collect())
    }
}
impl Index<usize> for WordLists {
    type Output = Vec<u32>;
    fn index(&self, index: usize) -> &Self::Output {
        self.0[index].as_ref()
    }
}
impl IndexMut<usize> for WordLists {
    fn index_mut(&mut self, index: usize) -> &mut Self::Output {
        Arc::make_mut(&mut self.0[index])
    }
}
impl<'a> IntoIterator for &'a WordLists {
    type Item = &'a Vec<u32>;
    type IntoIter =
        std::iter::Map<std::slice::Iter<'a, Arc<Vec<u32>>>, fn(&'a Arc<Vec<u32>>) -> &'a Vec<u32>>;
    fn into_iter(self) -> Self::IntoIter {
        self.0.iter().map(Arc::as_ref)
    }
}

impl FromIterator<Vec<u32>> for WordLists {
    fn from_iter<T: IntoIterator<Item = Vec<u32>>>(iter: T) -> Self {
        Self(iter.into_iter().map(Arc::new).collect())
    }
}
