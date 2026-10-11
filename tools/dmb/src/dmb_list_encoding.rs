//! Canonical list-row ranges on a previously validated immutable output owner.
//! Addresses select candidates only; retained exact words and width authorize use.
use crate::dmb::EncodedDmb;
use std::{collections::HashMap, io, ops::Range, sync::Arc};

pub(in crate::dmb) struct ListEncoding {
    words: Vec<Arc<Vec<u32>>>,
    image: EncodedDmb,
    ranges: Vec<Range<usize>>,
    width: usize,
    by_owner: HashMap<usize, usize>,
}
impl ListEncoding {
    /// Called only after the ordinary canonical writer and independent output
    /// validation succeed. This is a serialization certificate, not source proof.
    pub(in crate::dmb) fn capture(
        words: &[Arc<Vec<u32>>],
        image: &EncodedDmb,
        ranges: Vec<Range<usize>>,
        width: usize,
    ) -> io::Result<Self> {
        if !matches!(width, 2 | 4) || words.len() != ranges.len() {
            return Err(io::Error::other("list encoding shape differs"));
        }
        let mut through = 0;
        for (words, range) in words.iter().zip(&ranges) {
            let size = words
                .len()
                .checked_mul(width)
                .and_then(|n| n.checked_add(2))
                .ok_or_else(|| io::Error::other("list encoding size overflow"))?;
            if words.len() > u16::MAX as usize
                || range.start < through
                || range.end.checked_sub(range.start) != Some(size)
                || image.bytes().get(range.clone()).is_none()
            {
                return Err(io::Error::other("list encoding range differs"));
            }
            through = range.end;
        }
        let mut by_owner = HashMap::with_capacity(words.len());
        for (ordinal, words) in words.iter().enumerate() {
            by_owner
                .entry(Arc::as_ptr(words) as usize)
                .or_insert(ordinal);
        }
        Ok(Self {
            words: words.to_vec(),
            image: image.clone(),
            ranges,
            width,
            by_owner,
        })
    }
    pub(in crate::dmb) fn matches(&self, words: &[Arc<Vec<u32>>]) -> bool {
        self.words.len() == words.len()
            && self
                .words
                .iter()
                .zip(words)
                .all(|(a, b)| Arc::ptr_eq(a, b) || a == b)
    }
    /// Reordered shared rows find their original owner; separately allocated
    /// words may reuse the same ordinal only after complete value equality.
    /// New/mutated rows and width changes follow the ordinary row encoder.
    pub(in crate::dmb) fn row(
        &self,
        words: &Arc<Vec<u32>>,
        ordinal: usize,
        width: usize,
    ) -> Option<&[u8]> {
        if self.width != width {
            return None;
        }
        let index = self
            .by_owner
            .get(&(Arc::as_ptr(words) as usize))
            .copied()
            .or_else(|| (ordinal < self.words.len()).then_some(ordinal))?;
        let previous = self.words.get(index)?;
        if !(Arc::ptr_eq(words, previous) || words.as_ref() == previous.as_ref()) {
            return None;
        }
        self.image.bytes().get(self.ranges.get(index)?.clone())
    }
    pub(in crate::dmb) fn visit_storage(
        &self,
        mut visit: impl FnMut(&Vec<Arc<Vec<u32>>>, &EncodedDmb, &Vec<Range<usize>>, usize, usize),
    ) {
        visit(
            &self.words,
            &self.image,
            &self.ranges,
            self.by_owner.len(),
            self.by_owner.capacity(),
        );
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    fn retain(model: &crate::dmb::Dmb) -> EncodedDmb {
        let (image, certificate) = model.encode_reusing_list_rows(None, None).unwrap();
        crate::dmb::Dmb::from_bytes(image.bytes())
            .unwrap()
            .validate_references()
            .unwrap();
        assert!(model.lists.retain_encoded_rows(certificate));
        image
    }
    #[test]
    fn retained_canonical_writer_matches_fresh_after_cow_reorder_new_rows_and_width_change() {
        let mut previous =
            crate::dmb::Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
        previous.lists.push(vec![]);
        previous.lists.push(vec![1, 2, 3]);
        let old = retain(&previous);
        let mut next = previous.clone();
        let last = next.lists.shared(next.lists.len() - 1).unwrap().clone();
        let empty = next.lists.shared(next.lists.len() - 2).unwrap().clone();
        next.lists.pop();
        next.lists.pop();
        assert!(
            next.lists.encoding().is_none(),
            "COW facade drops its old certificate"
        );
        assert!(
            previous.lists.encoding().is_some(),
            "immutable sibling stays admitted"
        );
        next.lists.push_shared(last);
        next.lists.push_shared(empty);
        next.lists.push(vec![7, 8]);
        let (retained, certificate) = next
            .encode_reusing_list_rows(Some(&previous.lists), None)
            .unwrap();
        assert_eq!(retained.bytes(), next.encode().unwrap().bytes());
        assert_eq!(
            retained.content_hash(),
            next.encode().unwrap().content_hash()
        );
        crate::dmb::Dmb::from_bytes(retained.bytes())
            .unwrap()
            .validate_references()
            .unwrap();
        assert!(next.lists.retain_encoded_rows(certificate));
        next.lists.last_mut().unwrap().push(9);
        assert!(next.lists.encoding().is_none());
        let (changed, certificate) = next
            .encode_reusing_list_rows(Some(&previous.lists), None)
            .unwrap();
        assert_eq!(changed.bytes(), next.encode().unwrap().bytes());
        next.lists.last_mut().unwrap().push(10);
        assert!(
            !next.lists.retain_encoded_rows(certificate),
            "changed words cannot install old issuance"
        );
        next.header.flags ^= 0x4000_0000;
        let (wide, _) = next
            .encode_reusing_list_rows(Some(&previous.lists), None)
            .unwrap();
        assert_eq!(wide.bytes(), next.encode().unwrap().bytes());
        assert_eq!(
            old.bytes(),
            previous.encode().unwrap().bytes(),
            "previous generation immutable"
        );
        let old_bytes = Arc::downgrade(old.shared_bytes());
        drop(old);
        drop(previous);
        assert!(
            old_bytes.upgrade().is_none(),
            "current certificates cannot retain historical images"
        );
    }
    #[test]
    fn checked_rows_preserve_exact_words_width_order_and_empty_rows() {
        let mut model =
            crate::dmb::Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
        model.lists.push(vec![]);
        model.lists.push(vec![1, 2, 3]);
        let image = model.encode().unwrap();
        let (bytes, ranges) = model.to_bytes_with_list_spans().unwrap();
        assert_eq!(image.bytes(), bytes);
        let width = if model.header.flags & 0x4000_0000 != 0 {
            4
        } else {
            2
        };
        let cached = ListEncoding::capture(model.lists.storage(), &image, ranges, width).unwrap();
        let last = model.lists.len() - 1;
        let words = model.lists.shared(last).unwrap();
        assert_eq!(
            cached.row(words, 0, width),
            cached.row(words, last, width),
            "shared reordering"
        );
        assert!(
            cached.row(&Arc::new(vec![1, 2, 3]), last, width).is_some(),
            "full equality fallback"
        );
        assert!(cached.row(&Arc::new(vec![1, 2, 4]), last, width).is_none());
        assert!(cached
            .row(words, last, if width == 2 { 4 } else { 2 })
            .is_none());
        assert_eq!(
            cached
                .row(model.lists.shared(last - 1).unwrap(), last - 1, width)
                .unwrap(),
            [0, 0]
        );
        assert!(ListEncoding::capture(model.lists.storage(), &image, vec![0..2], width).is_err());
    }
}
