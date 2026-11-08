//! Exact canonical declaration bytes with an optional compact storage layout.
use std::{fmt, mem::{size_of, MaybeUninit}, sync::Arc};

const ESCAPE: u8 = 0;
const RAW: u8 = 0;
const PACKED: u8 = 1;
const BITMAP: u8 = 2;
const PREFIXED: u8 = 4;
const GROUP: usize = 8;

/// Exact shared lexical token framing prefix.
pub static CANONICAL_HEADER_PREFIX: &[u8] = b"dm-declaration-tokens-v1\0";
const PACKED_HEADER: usize = 2 + size_of::<u64>();
static ZEROES: [u8; u8::MAX as usize] = [0; u8::MAX as usize];

/// Logical canonical bytes. The physical Arc is private because it may contain
/// an escaped raw value or a packed representation.
#[derive(Clone)]
pub struct CanonicalBytes(Arc<[u8]>);

/// A borrowed exact allocation plan. Measuring does not allocate. The native
/// producer can preadmit the Arc layout before sealing it.
pub struct CanonicalBytesPlan<'a> {
    bytes: &'a [u8],
    storage_len: usize,
    layout: Layout,
    prefix: bool,
}

#[derive(Clone, Copy)]
enum Layout {
    Plain,
    Escaped,
    Packed,
    Bitmap,
}

impl CanonicalBytes {
    pub fn plan(bytes: &[u8]) -> CanonicalBytesPlan<'_> {
        let prefixed = bytes.strip_prefix(CANONICAL_HEADER_PREFIX);
        let prefix = prefixed.is_some();
        let bytes = prefixed.unwrap_or(bytes);
        let (mut layout, mut storage_len) = if prefix || bytes.first() == Some(&ESCAPE) {
            (Layout::Escaped, bytes.len() + 2)
        } else {
            (Layout::Plain, bytes.len())
        };
        // The two Arc counters and allocation alignment are common to every
        // layout. Don't pay decode work if the padded allocation is equal.
        let allocation = |n: usize| n.checked_next_multiple_of(std::mem::align_of::<usize>()).unwrap_or(usize::MAX);
        if bytes.len() > PACKED_HEADER {
            let mut packed_len = PACKED_HEADER;
            let mut bitmap_len = PACKED_HEADER + bytes.len().div_ceil(GROUP);
            for run in Runs(bytes) {
                match run {
                    Run::Literal(bytes) => {
                        packed_len = packed_len.saturating_add(bytes.len());
                        bitmap_len += bytes.len();
                    }
                    Run::Zero(_) => packed_len = packed_len.saturating_add(2),
                }
                if packed_len >= storage_len && bitmap_len >= storage_len {
                    break;
                }
            }
            if allocation(packed_len) < allocation(storage_len) {
                layout = Layout::Packed;
                storage_len = packed_len;
            }
            if allocation(bitmap_len) < allocation(storage_len) {
                layout = Layout::Bitmap;
                storage_len = bitmap_len;
            }
        }
        CanonicalBytesPlan { bytes, storage_len, layout, prefix }
    }

    pub fn len(&self) -> usize {
        if self.0.first() != Some(&ESCAPE) {
            return self.0.len();
        }
        let flags = self.0[1];
        let prefix_len = if flags & PREFIXED == 0 { 0 } else { CANONICAL_HEADER_PREFIX.len() };
        let body_len = if flags & !PREFIXED == RAW {
            self.0.len() - 2
        } else {
            self.packed_len()
        };
        prefix_len + body_len
    }

    fn packed_len(&self) -> usize {
        let bytes = self.0[2..PACKED_HEADER].try_into().expect("issued packed length");
        usize::try_from(u64::from_le_bytes(bytes)).expect("issued native canonical length")
    }

    pub fn is_empty(&self) -> bool {
        self.0.is_empty()
    }

    pub fn to_vec(&self) -> Vec<u8> {
        let mut output = Vec::with_capacity(self.len());
        self.for_each_chunk(|chunk| output.extend_from_slice(chunk));
        output
    }

    pub fn xxh3_128(&self) -> u128 {
        if let Chunks { prefix: false, body: BodyChunks::Raw(raw) } = self.chunks() {
            return xxhash_rust::xxh3::xxh3_128(raw);
        }
        let mut hash = xxhash_rust::xxh3::Xxh3::new();
        self.for_each_chunk(|chunk| hash.update(chunk));
        hash.digest128()
    }

    pub fn try_for_each_chunk<E>(
        &self,
        mut visit: impl FnMut(&[u8]) -> Result<(), E>,
    ) -> Result<(), E> {
        for chunk in self.chunks() {
            visit(chunk)?;
        }
        Ok(())
    }

    /// Physical storage only, for allocation census and weak lifetime tracking.
    pub fn storage_arc(&self) -> &Arc<[u8]> {
        &self.0
    }

    fn for_each_chunk(&self, mut visit: impl FnMut(&[u8])) {
        let result = self.try_for_each_chunk(|chunk| {
            visit(chunk);
            Ok::<(), std::convert::Infallible>(())
        });
        match result {
            Ok(()) => (),
            Err(impossible) => match impossible {},
        }
    }

    fn chunks(&self) -> Chunks<'_> {
        let (prefix, body) = match self.0.as_ref() {
            [ESCAPE, flags, rest @ ..] => {
                let body = match *flags & !PREFIXED {
                    RAW => BodyChunks::Raw(rest),
                    PACKED => BodyChunks::Packed(&self.0[PACKED_HEADER..]),
                    BITMAP => BodyChunks::Bitmap {
                        raw: &self.0[PACKED_HEADER..], left: self.packed_len(), mask: 0, group_left: 0,
                    },
                    _ => unreachable!("issued canonical storage tag"),
                };
                (*flags & PREFIXED != 0, body)
            }
            raw => (false, BodyChunks::Raw(raw)),
        };
        Chunks { prefix, body }
    }
}

impl CanonicalBytesPlan<'_> {
    pub fn storage_len(&self) -> usize {
        self.storage_len
    }

    pub fn seal(self) -> CanonicalBytes {
        if matches!(self.layout, Layout::Plain) {
            return CanonicalBytes(self.bytes.into());
        }
        let mut storage = Arc::<[u8]>::new_uninit_slice(self.storage_len);
        let mut output = Arc::get_mut(&mut storage).expect("new canonical storage");
        fn write(output: &mut &mut [MaybeUninit<u8>], bytes: &[u8]) {
            let (head, tail) = std::mem::take(output).split_at_mut(bytes.len());
            for (slot, byte) in head.iter_mut().zip(bytes) {
                slot.write(*byte);
            }
            *output = tail;
        }
        let encoding = match self.layout {
            Layout::Escaped => RAW,
            Layout::Packed => PACKED,
            Layout::Bitmap => BITMAP,
            Layout::Plain => unreachable!("plain storage handled above"),
        };
        let flags = encoding | if self.prefix { PREFIXED } else { 0 };
        write(&mut output, &[ESCAPE, flags]);
        if encoding != RAW {
            write(&mut output, &(self.bytes.len() as u64).to_le_bytes());
        }
        match self.layout {
            Layout::Escaped => write(&mut output, self.bytes),
            Layout::Packed => {
                for chunk in Runs(self.bytes) {
                    match chunk {
                        Run::Literal(bytes) => write(&mut output, bytes),
                        Run::Zero(count) => write(&mut output, &[ESCAPE, count]),
                    }
                }
            }
            Layout::Bitmap => {
                for group in self.bytes.chunks(GROUP) {
                    let mut mask = 0;
                    let mut values = [0; GROUP];
                    let mut count = 0;
                    for (bit, &byte) in group.iter().enumerate() {
                        if byte != 0 {
                            mask |= 1 << bit;
                            values[count] = byte;
                            count += 1;
                        }
                    }
                    write(&mut output, &[mask]);
                    write(&mut output, &values[..count]);
                }
            }
            Layout::Plain => unreachable!("plain storage handled above"),
        }
        assert!(output.is_empty(), "canonical plan wrote its exact allocation");
        // SAFETY: Every slot was initialized exactly once by the measured plan.
        CanonicalBytes(unsafe { storage.assume_init() })
    }
}

enum Run<'a> {
    Literal(&'a [u8]),
    Zero(u8),
}

struct Runs<'a>(&'a [u8]);

impl<'a> Iterator for Runs<'a> {
    type Item = Run<'a>;

    fn next(&mut self) -> Option<Self::Item> {
        if *self.0.first()? == ESCAPE {
            let n = self.0.iter().take(ZEROES.len()).take_while(|&&b| b == ESCAPE).count();
            self.0 = &self.0[n..];
            Some(Run::Zero(n as u8))
        } else {
            let n = self.0.iter().position(|&b| b == ESCAPE).unwrap_or(self.0.len());
            let (chunk, tail) = self.0.split_at(n);
            self.0 = tail;
            Some(Run::Literal(chunk))
        }
    }
}

struct Chunks<'a> {
    prefix: bool,
    body: BodyChunks<'a>,
}

enum BodyChunks<'a> {
    Raw(&'a [u8]),
    Packed(&'a [u8]),
    Bitmap { raw: &'a [u8], left: usize, mask: u8, group_left: u8 },
}

impl<'a> Iterator for Chunks<'a> {
    type Item = &'a [u8];

    fn next(&mut self) -> Option<Self::Item> {
        if std::mem::take(&mut self.prefix) {
            return Some(CANONICAL_HEADER_PREFIX);
        }
        match &mut self.body {
            BodyChunks::Raw(raw) if !raw.is_empty() => Some(std::mem::take(raw)),
            BodyChunks::Raw(_) => None,
            BodyChunks::Packed(raw) => {
                let bytes = *raw;
                if *bytes.first()? == ESCAPE {
                    let n = usize::from(bytes[1]);
                    *raw = &bytes[2..];
                    Some(&ZEROES[..n])
                } else {
                    let n = bytes.iter().position(|&b| b == ESCAPE).unwrap_or(bytes.len());
                    let (chunk, tail) = bytes.split_at(n);
                    *raw = tail;
                    Some(chunk)
                }
            }
            BodyChunks::Bitmap { raw, left, mask, group_left } => {
                if *left == 0 { return None; }
                if *group_left == 0 {
                    let (&next, rest) = (*raw).split_first().expect("issued canonical bitmap group");
                    *raw = rest;
                    *mask = next;
                    *group_left = (*left).min(GROUP) as u8;
                }
                let nonzero = *mask & 1 != 0;
                let width = if nonzero { mask.trailing_ones() } else { mask.trailing_zeros() };
                let n = width.min(u32::from(*group_left));
                *mask = mask.checked_shr(n).unwrap_or(0);
                *group_left -= n as u8;
                let n = n as usize;
                *left -= n;
                if nonzero {
                    let (chunk, rest) = (*raw).split_at(n);
                    *raw = rest;
                    Some(chunk)
                } else {
                    Some(&ZEROES[..n])
                }
            }
        }
    }
}

impl PartialEq for CanonicalBytes {
    fn eq(&self, other: &Self) -> bool {
        if Arc::ptr_eq(&self.0, &other.0) || self.0 == other.0 {
            return true;
        }
        if self.len() != other.len() {
            return false;
        }
        let (mut left, mut right) = (self.chunks(), other.chunks());
        let (mut a, mut b) = (&[][..], &[][..]);
        loop {
            if a.is_empty() { a = left.next().unwrap_or_default(); }
            if b.is_empty() { b = right.next().unwrap_or_default(); }
            if a.is_empty() || b.is_empty() { return a.is_empty() && b.is_empty(); }
            let n = a.len().min(b.len());
            if a[..n] != b[..n] { return false; }
            a = &a[n..];
            b = &b[n..];
        }
    }
}
impl Eq for CanonicalBytes {}

impl fmt::Debug for CanonicalBytes {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("CanonicalBytes").field("len", &self.len()).finish_non_exhaustive()
    }
}

impl Default for CanonicalBytes {
    fn default() -> Self {
        Self(Arc::from([]))
    }
}

impl From<Arc<[u8]>> for CanonicalBytes {
    fn from(bytes: Arc<[u8]>) -> Self {
        if bytes.first() == Some(&ESCAPE) { Self::plan(&bytes).seal() } else { Self(bytes) }
    }
}

impl From<Vec<u8>> for CanonicalBytes {
    fn from(bytes: Vec<u8>) -> Self {
        if bytes.first() == Some(&ESCAPE) { Self::plan(&bytes).seal() } else { Self(bytes.into()) }
    }
}

impl From<&[u8]> for CanonicalBytes {
    fn from(bytes: &[u8]) -> Self {
        if bytes.first() == Some(&ESCAPE) { Self::plan(bytes).seal() } else { Self(bytes.into()) }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn storage_is_exact_and_logical_bytes_survive_every_layout() {
        let mut mixed = vec![7, 0, 8];
        mixed.extend_from_slice(&[0; 760]);
        mixed.extend_from_slice(&[8, 0, 7]);
        for bytes in [vec![], vec![1, 2, 3], vec![0, 1, 2], vec![0; 760], mixed] {
            let plan = CanonicalBytes::plan(&bytes);
            let storage_len = plan.storage_len();
            let actual = plan.seal();
            assert_eq!(actual.storage_arc().len(), storage_len);
            assert_eq!(actual.len(), bytes.len());
            assert_eq!(actual.is_empty(), bytes.is_empty());
            assert_eq!(actual.to_vec(), bytes);
            assert_eq!(actual.xxh3_128(), xxhash_rust::xxh3::xxh3_128(&bytes));
            assert_eq!(actual, CanonicalBytes::from(bytes));
        }
    }

    #[test]
    fn prefix_and_bitmap_choose_only_smaller_storage_and_preserve_the_exact_stream() {
        let prefix_only = CanonicalBytes::plan(CANONICAL_HEADER_PREFIX).seal();
        assert_eq!(prefix_only.storage_arc().as_ref(), &[ESCAPE, PREFIXED | RAW]);
        assert_eq!(prefix_only.to_vec(), CANONICAL_HEADER_PREFIX);

        let mut bytes = CANONICAL_HEADER_PREFIX.to_vec();
        bytes.extend((0..251).map(|at| if at % 2 == 0 { 7 } else { 0 }));
        let packed = CanonicalBytes::plan(&bytes).seal();
        assert_eq!(packed.storage_arc()[1], PREFIXED | BITMAP);
        assert_eq!(packed.storage_arc().len(), PACKED_HEADER + 32 + 126);
        let mut chunks = packed.chunks();
        assert!(std::ptr::eq(chunks.next().unwrap(), CANONICAL_HEADER_PREFIX));
        assert_eq!(packed.len(), bytes.len());
        assert_eq!(packed.to_vec(), bytes);
        assert_eq!(packed, CanonicalBytes::from(bytes.clone()));
        assert_eq!(packed.xxh3_128(), xxhash_rust::xxh3::xxh3_128(&bytes));

        let mut bytes = CANONICAL_HEADER_PREFIX.to_vec();
        bytes.extend_from_slice(&[0; 1000]);
        let runs = CanonicalBytes::plan(&bytes).seal();
        assert_eq!(runs.storage_arc()[1], PREFIXED | PACKED);
        assert_eq!(runs.to_vec(), bytes);

        let almost = b"dm-declaration-tokens-v1X";
        let raw = CanonicalBytes::plan(almost).seal();
        assert_eq!(raw.storage_arc().as_ref(), almost);
        assert_eq!(raw.len(), almost.len());
    }

    #[test]
    fn packed_and_plain_owners_compare_without_sharing_storage() {
        let mut bytes = vec![7; 3];
        bytes.extend_from_slice(&[0; 1000]);
        let plain = CanonicalBytes::from(bytes.clone());
        let packed = CanonicalBytes::plan(&bytes).seal();
        assert_eq!(plain, packed);
        assert!(packed.storage_arc().len() < plain.storage_arc().len());
        let mut calls = 0;
        let error = packed.try_for_each_chunk(|_| {
            calls += 1;
            Err("first error")
        }).unwrap_err();
        assert_eq!((calls, error), (1, "first error"));
        bytes[8] = 4;
        assert_ne!(packed, CanonicalBytes::plan(&bytes).seal());
        assert_eq!(size_of::<CanonicalBytes>(), size_of::<Arc<[u8]>>());
    }
}
