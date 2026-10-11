//! Shared immutable list payloads with copy-on-write mutation at the DMB boundary.
use std::{
    ops::{Index, IndexMut},
    sync::{Arc, Mutex},
};
#[path = "dmb_list_encoding.rs"]
mod encoding;
pub(super) use encoding::ListEncoding;
#[derive(Default)]
pub struct WordLists(Vec<Arc<Vec<u32>>>, Mutex<Option<Arc<ListEncoding>>>);
/// Private canonical-writer issuance; bytes and word bindings cannot be replaced.
pub struct EncodedListRows(Arc<ListEncoding>);
impl Clone for WordLists {
    fn clone(&self) -> Self {
        Self(
            self.0.clone(),
            Mutex::new(self.1.lock().unwrap_or_else(|e| e.into_inner()).clone()),
        )
    }
}
impl PartialEq for WordLists {
    fn eq(&self, b: &Self) -> bool {
        self.0 == b.0
    }
}
impl std::fmt::Debug for WordLists {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_tuple("WordLists").field(&self.0).finish()
    }
}
impl WordLists {
    fn clear_encoding(&mut self) {
        *self.1.get_mut().unwrap_or_else(|e| e.into_inner()) = None;
    }
    pub(super) fn encoding(&self) -> Option<Arc<ListEncoding>> {
        self.1.lock().unwrap_or_else(|e| e.into_inner()).clone()
    }
    pub(super) fn issue_encoding(
        &self,
        image: &crate::dmb::EncodedDmb,
        ranges: Vec<std::ops::Range<usize>>,
        width: usize,
    ) -> std::io::Result<EncodedListRows> {
        Ok(EncodedListRows(Arc::new(ListEncoding::capture(
            &self.0, image, ranges, width,
        )?)))
    }
    /// Install the canonical producer's certificate only after output validation.
    /// Exact current words remain mandatory even if a caller mutated this model.
    pub fn retain_encoded_rows(&self, certificate: EncodedListRows) -> bool {
        if !certificate.0.matches(&self.0) {
            return false;
        }
        *self.1.lock().unwrap_or_else(|e| e.into_inner()) = Some(certificate.0);
        true
    }
    pub fn visit_encoding(
        &self,
        mut visit: impl FnMut(
            usize,
            usize,
            &Vec<Arc<Vec<u32>>>,
            &crate::dmb::EncodedDmb,
            &Vec<std::ops::Range<usize>>,
            usize,
            usize,
        ),
    ) {
        let current = self.1.lock().unwrap_or_else(|e| e.into_inner());
        if let Some(owner) = current.as_ref() {
            owner.visit_storage(|words, image, ranges, len, capacity| {
                visit(
                    Arc::as_ptr(owner) as usize,
                    std::mem::size_of::<ListEncoding>(),
                    words,
                    image,
                    ranges,
                    len,
                    capacity,
                )
            });
        }
    }
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
        self.clear_encoding();
        self.0.push(words);
    }
    pub fn get(&self, index: usize) -> Option<&Vec<u32>> {
        self.0.get(index).map(Arc::as_ref)
    }
    pub fn get_mut(&mut self, index: usize) -> Option<&mut Vec<u32>> {
        self.clear_encoding();
        self.0.get_mut(index).map(Arc::make_mut)
    }
    pub fn last_mut(&mut self) -> Option<&mut Vec<u32>> {
        self.clear_encoding();
        self.0.last_mut().map(Arc::make_mut)
    }
    pub fn shared(&self, index: usize) -> Option<&Arc<Vec<u32>>> {
        self.0.get(index)
    }
    pub fn iter(&self) -> impl DoubleEndedIterator<Item = &Vec<u32>> + ExactSizeIterator {
        self.0.iter().map(Arc::as_ref)
    }
    pub fn resize(&mut self, len: usize, words: Vec<u32>) {
        self.clear_encoding();
        self.0.resize(len, Arc::new(words));
    }
    pub fn pop(&mut self) -> Option<Vec<u32>> {
        self.clear_encoding();
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
        Self(words.into_iter().map(Arc::new).collect(), Mutex::new(None))
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
        self.clear_encoding();
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
        Self(iter.into_iter().map(Arc::new).collect(), Mutex::new(None))
    }
}
