//! Row-level splicing of a canonical image's list table.
//!
//! A list record is a u16 element count followed by width-sized words. The list
//! table follows the offset-ciphered string table, and no later record depends
//! on byte offsets, so replacing whole rows of a canonical image yields exactly
//! the canonical writer's output for the model with those rows replaced.
use crate::dmb::EncodedDmb;
use std::{io, ops::Range, sync::Arc};

/// Replace rows `(index, words)` (strictly increasing indexes). Returns the new
/// bytes and the shifted row ranges.
pub(in crate::dmb) fn splice_rows(
    old: &[u8],
    ranges: &[Range<usize>],
    width: usize,
    ordered: &[(usize, &[u32])],
) -> io::Result<(Vec<u8>, Vec<Range<usize>>)> {
    if !matches!(width, 2 | 4) {
        return Err(io::Error::other("list width differs"));
    }
    if ordered.windows(2).any(|pair| pair[0].0 >= pair[1].0) {
        return Err(io::Error::other("list row replacements are not ordered"));
    }
    let mut delta: isize = 0;
    for (index, words) in ordered {
        let range = ranges
            .get(*index)
            .ok_or_else(|| io::Error::other("list row replacement out of range"))?;
        if words.len() > u16::MAX as usize {
            return Err(io::Error::other("list exceeds u16 element count"));
        }
        if width == 2 && words.iter().any(|&word| word > u16::MAX as u32) {
            return Err(io::Error::other("object ID exceeds selected 16-bit width"));
        }
        if old.get(range.clone()).is_none() {
            return Err(io::Error::other("list row range outside image"));
        }
        delta += (2 + words.len() * width) as isize - range.len() as isize;
    }
    let mut bytes = Vec::with_capacity((old.len() as isize + delta).max(0) as usize);
    let mut through = 0usize;
    for (index, words) in ordered {
        let range = &ranges[*index];
        bytes.extend_from_slice(&old[through..range.start]);
        bytes.extend_from_slice(&(words.len() as u16).to_le_bytes());
        for &word in words.iter() {
            if width == 2 {
                bytes.extend_from_slice(&(word as u16).to_le_bytes());
            } else {
                bytes.extend_from_slice(&word.to_le_bytes());
            }
        }
        through = range.end;
    }
    bytes.extend_from_slice(&old[through..]);
    let mut shifted = Vec::with_capacity(ranges.len());
    let mut shift: isize = 0;
    let mut next = ordered.iter().peekable();
    for (index, range) in ranges.iter().enumerate() {
        let start = (range.start as isize + shift) as usize;
        match next.peek() {
            Some((replaced, words)) if *replaced == index => {
                let size = 2 + words.len() * width;
                shifted.push(start..start + size);
                shift += size as isize - range.len() as isize;
                next.next();
            }
            _ => shifted.push(start..(range.end as isize + shift) as usize),
        }
    }
    Ok((bytes, shifted))
}

/// A canonical image with its list-row ranges, detached from the model that
/// produced it (it holds no list words). It can be spliced repeatedly.
#[derive(Clone)]
pub struct ListRowImage {
    image: EncodedDmb,
    ranges: Arc<Vec<Range<usize>>>,
    width: usize,
}
impl ListRowImage {
    pub(in crate::dmb) fn new(image: EncodedDmb, ranges: Vec<Range<usize>>, width: usize) -> Self {
        Self {
            image,
            ranges: Arc::new(ranges),
            width,
        }
    }
    pub fn image(&self) -> &EncodedDmb {
        &self.image
    }
    pub fn len(&self) -> usize {
        self.ranges.len()
    }
    pub fn is_empty(&self) -> bool {
        self.ranges.is_empty()
    }
    /// Whether row `index` currently holds exactly `words`.
    pub fn row_equals(&self, index: usize, words: &[u32]) -> bool {
        let Some(row) = self
            .ranges
            .get(index)
            .and_then(|range| self.image.bytes().get(range.clone()))
        else {
            return false;
        };
        if row.len() != 2 + words.len() * self.width
            || row[..2] != (words.len() as u16).to_le_bytes()
        {
            return false;
        }
        row[2..]
            .chunks_exact(self.width)
            .zip(words)
            .all(|(bytes, &word)| match self.width {
                2 => word <= u16::MAX as u32 && bytes == (word as u16).to_le_bytes(),
                _ => bytes == word.to_le_bytes(),
            })
    }
    /// Replace whole rows; the result equals the canonical encoding of the
    /// model with those rows replaced. Errors leave `self` unchanged.
    pub fn splice(&self, replacements: &[(usize, Arc<Vec<u32>>)]) -> io::Result<Self> {
        let mut ordered: Vec<(usize, &[u32])> = replacements
            .iter()
            .map(|(index, words)| (*index, words.as_slice()))
            .collect();
        ordered.sort_by_key(|(index, _)| *index);
        let (bytes, ranges) =
            splice_rows(self.image.bytes(), &self.ranges, self.width, &ordered)?;
        Ok(Self {
            image: EncodedDmb::from_spliced(bytes),
            ranges: Arc::new(ranges),
            width: self.width,
        })
    }
}
