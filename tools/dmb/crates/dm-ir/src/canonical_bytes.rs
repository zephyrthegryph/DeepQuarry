//! Exact canonical declaration bytes with an optional compact storage layout.
use std::{fmt, mem::{size_of, MaybeUninit}, sync::Arc};

const ESCAPE: u8 = 0;
const RAW: u8 = 0;
const PACKED: u8 = 1;
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
}

#[derive(Clone, Copy)]
enum Layout {
    Plain,
    Escaped,
    Packed,
}

impl CanonicalBytes {
    pub fn plan(bytes: &[u8]) -> CanonicalBytesPlan<'_> {
        let (mut layout, mut storage_len) = if bytes.first() == Some(&ESCAPE) {
            (Layout::Escaped, bytes.len() + 2)
        } else {
            (Layout::Plain, bytes.len())
        };
        let mut packed_len = PACKED_HEADER;
        for chunk in Runs(bytes) {
            let len = match chunk {
                Run::Literal(bytes) => bytes.len(),
                Run::Zero(_) => 2,
            };
            packed_len = packed_len.saturating_add(len);
            if packed_len >= storage_len {
                break;
            }
        }
        if packed_len < storage_len {
            layout = Layout::Packed;
            storage_len = packed_len;
        }
        CanonicalBytesPlan { bytes, storage_len, layout }
    }

    pub fn len(&self) -> usize {
        if self.0.first() != Some(&ESCAPE) {
            self.0.len()
        } else if self.0[1] == RAW {
            self.0.len() - 2
        } else {
            let bytes = self.0[2..PACKED_HEADER].try_into().expect("issued packed length");
            usize::try_from(u64::from_le_bytes(bytes)).expect("issued native canonical length")
        }
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
        if let Chunks::Raw(raw) = self.chunks() {
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
        match self.0.as_ref() {
            [ESCAPE, RAW, rest @ ..] => Chunks::Raw(rest),
            [ESCAPE, PACKED, ..] => Chunks::Packed(&self.0[PACKED_HEADER..]),
            raw => Chunks::Raw(raw),
        }
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
        match self.layout {
            Layout::Escaped => {
                write(&mut output, &[ESCAPE, RAW]);
                write(&mut output, self.bytes);
            }
            Layout::Packed => {
                write(&mut output, &[ESCAPE, PACKED]);
                write(&mut output, &(self.bytes.len() as u64).to_le_bytes());
                for chunk in Runs(self.bytes) {
                    match chunk {
                        Run::Literal(bytes) => write(&mut output, bytes),
                        Run::Zero(count) => write(&mut output, &[ESCAPE, count]),
                    }
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

enum Chunks<'a> {
    Raw(&'a [u8]),
    Packed(&'a [u8]),
}

impl<'a> Iterator for Chunks<'a> {
    type Item = &'a [u8];

    fn next(&mut self) -> Option<Self::Item> {
        match self {
            Self::Raw(raw) if !raw.is_empty() => Some(std::mem::take(raw)),
            Self::Raw(_) => None,
            Self::Packed(raw) => {
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
