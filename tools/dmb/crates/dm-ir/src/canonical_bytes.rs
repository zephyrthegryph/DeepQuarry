//! Exact canonical declaration bytes with an optional compact storage layout.
use std::{fmt, mem::{size_of, MaybeUninit}, sync::Arc};

const ESCAPE: u8 = 0;
const RAW: u8 = 0;
const PACKED: u8 = 1;
const BITMAP: u8 = 2;
const PREFIXED: u8 = 4;
const GROUP: usize = 8;
const TRAILER: u8 = 8;
const VARIADIC_TRAILER: u8 = 16;
static PROCEDURE_TAG: &[u8] = b"dm-procedure-metadata-v2\0";
static SIGNATURE_TAG: &[u8] = b"dm-procedure-signature-v2\0";

const FLAGS: u8 = PREFIXED | TRAILER | VARIADIC_TRAILER;

// Metadata tag, framed signature, and empty settings. The canonical encoder
// remains the byte authority, independently exercised by the test below.
const TRIVIAL_PROCEDURE: &[u8] = b"dm-procedure-metadata-v2\0$\0\0\0\0\0\0\0dm-procedure-signature-v2\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0";
const TRIVIAL_VARIADIC_PROCEDURE: &[u8] = b"dm-procedure-metadata-v2\0$\0\0\0\0\0\0\0dm-procedure-signature-v2\0\x01\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0";

fn trailer_bytes(flags: u8) -> &'static [u8] {
    if flags & TRAILER != 0 { TRIVIAL_PROCEDURE }
    else if flags & VARIADIC_TRAILER != 0 { TRIVIAL_VARIADIC_PROCEDURE }
    else { &[] }
}

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
    trailer: u8,
    procedure_tags: Option<usize>,
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
        Self::plan_inner(bytes, None)
    }

    /// The adapter supplies the exact byte at which its procedure encoder
    /// began. Both versioned tags must match before using the packed markers.
    pub fn plan_procedure(bytes: &[u8], suffix_start: usize) -> CanonicalBytesPlan<'_> {
        Self::plan_inner(bytes, Some(suffix_start))
    }

    fn plan_inner(bytes: &[u8], suffix_start: Option<usize>) -> CanonicalBytesPlan<'_> {
        let prefixed = bytes.strip_prefix(CANONICAL_HEADER_PREFIX);
        let prefix = prefixed.is_some();
        let (bytes, trailer) = if let Some(prefixed) = prefixed {
            if let Some(body) = prefixed.strip_suffix(TRIVIAL_PROCEDURE) {
                (body, TRAILER)
            } else if let Some(body) = prefixed.strip_suffix(TRIVIAL_VARIADIC_PROCEDURE) {
                (body, VARIADIC_TRAILER)
            } else {
                (prefixed, 0)
            }
        } else {
            (bytes, 0)
        };
        let procedure_tags = suffix_start
            .filter(|_| prefix && trailer == 0)
            .and_then(|start| start.checked_sub(CANONICAL_HEADER_PREFIX.len()))
            .filter(|&start| {
                let Some(suffix) = bytes.get(start..) else { return false };
                let Some(frame) = suffix.strip_prefix(PROCEDURE_TAG) else { return false };
                frame.get(size_of::<u64>()..).is_some_and(|body| body.starts_with(SIGNATURE_TAG))
            });
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
            for run in Runs::new(bytes, procedure_tags) {
                match run {
                    Run::Literal(bytes) => {
                        packed_len = packed_len.saturating_add(bytes.len());
                        bitmap_len += bytes.len();
                    }
                    Run::Zero(_) => packed_len = packed_len.saturating_add(2),
                    Run::Tag(tag) => {
                        packed_len = packed_len.saturating_add(3);
                        bitmap_len += tag.bytes().len() - 1;
                    }
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
        CanonicalBytesPlan { bytes, storage_len, layout, prefix, trailer, procedure_tags }
    }

    pub fn len(&self) -> usize {
        if self.0.first() != Some(&ESCAPE) {
            return self.0.len();
        }
        let flags = self.0[1];
        let prefix_len = if flags & PREFIXED == 0 { 0 } else { CANONICAL_HEADER_PREFIX.len() };
        let body_len = if flags & !FLAGS == RAW {
            self.0.len() - 2
        } else {
            self.packed_len()
        };
        prefix_len + body_len + trailer_bytes(flags).len()
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
        let chunks = self.chunks();
        if let Chunks { prefix: false, body: BodyChunks::Raw(raw), trailer } = &chunks {
            if trailer.is_empty() { return xxhash_rust::xxh3::xxh3_128(raw); }
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
        let (prefix, body, trailer) = match self.0.as_ref() {
            [ESCAPE, flags, rest @ ..] => {
                let body = match *flags & !FLAGS {
                    RAW => BodyChunks::Raw(rest),
                    PACKED => BodyChunks::Packed(&self.0[PACKED_HEADER..]),
                    BITMAP => BodyChunks::Bitmap {
                        raw: &self.0[PACKED_HEADER..], left: self.packed_len(), mask: 0, group_left: 0,
                    },
                    _ => unreachable!("issued canonical storage tag"),
                };
                (*flags & PREFIXED != 0, body, trailer_bytes(*flags))
            }
            raw => (false, BodyChunks::Raw(raw), &[][..]),
        };
        Chunks { prefix, body, trailer }
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
        let flags = encoding | self.trailer | if self.prefix { PREFIXED } else { 0 };
        write(&mut output, &[ESCAPE, flags]);
        if encoding != RAW {
            write(&mut output, &(self.bytes.len() as u64).to_le_bytes());
        }
        match self.layout {
            Layout::Escaped => write(&mut output, self.bytes),
            Layout::Packed => {
                for chunk in Runs::new(self.bytes, self.procedure_tags) {
                    match chunk {
                        Run::Literal(bytes) => write(&mut output, bytes),
                        Run::Zero(count) => write(&mut output, &[ESCAPE, count]),
                        Run::Tag(tag) => write(&mut output, &[ESCAPE, 0, tag as u8]),
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
    Tag(Tag),
}

#[derive(Clone, Copy)]
#[repr(u8)]
enum Tag {
    Procedure = 1,
    Signature = 2,
}
impl Tag {
    fn bytes(self) -> &'static [u8] {
        match self {
            Self::Procedure => PROCEDURE_TAG,
            Self::Signature => SIGNATURE_TAG,
        }
    }
}

struct Runs<'a> {
    rest: &'a [u8],
    next_tag: Option<(usize, Tag)>,
}

impl<'a> Runs<'a> {
    fn new(bytes: &'a [u8], procedure_tags: Option<usize>) -> Self {
        Self { rest: bytes, next_tag: procedure_tags.map(|at| (at, Tag::Procedure)) }
    }
}

impl<'a> Iterator for Runs<'a> {
    type Item = Run<'a>;

    fn next(&mut self) -> Option<Self::Item> {
        let limit = match self.next_tag {
            Some((0, tag)) => {
                self.rest = &self.rest[tag.bytes().len()..];
                self.next_tag = match tag {
                    Tag::Procedure => Some((size_of::<u64>(), Tag::Signature)),
                    Tag::Signature => None,
                };
                return Some(Run::Tag(tag));
            }
            Some((at, _)) => at,
            None => self.rest.len(),
        };
        let before_tag = &self.rest[..limit];
        let (width, is_zero) = if *before_tag.first()? == ESCAPE {
            (before_tag.iter().take(ZEROES.len()).take_while(|&&b| b == ESCAPE).count(), true)
        } else {
            (before_tag.iter().position(|&b| b == ESCAPE).unwrap_or(limit), false)
        };
        let (chunk, tail) = self.rest.split_at(width);
        self.rest = tail;
        if let Some((at, _)) = &mut self.next_tag {
            *at -= width;
        }
        Some(if is_zero { Run::Zero(width as u8) } else { Run::Literal(chunk) })
    }
}

struct Chunks<'a> {
    prefix: bool,
    body: BodyChunks<'a>,
    trailer: &'static [u8],
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
        self.body.next().or_else(|| {
            (!self.trailer.is_empty()).then(|| std::mem::take(&mut self.trailer))
        })
    }
}

impl<'a> Iterator for BodyChunks<'a> {
    type Item = &'a [u8];

    fn next(&mut self) -> Option<Self::Item> {
        match self {
            BodyChunks::Raw(raw) if !raw.is_empty() => Some(std::mem::take(raw)),
            BodyChunks::Raw(_) => None,
            BodyChunks::Packed(raw) => {
                let bytes = *raw;
                if *bytes.first()? == ESCAPE {
                    let n = usize::from(bytes[1]);
                    if n != 0 {
                        *raw = &bytes[2..];
                        Some(&ZEROES[..n])
                    } else {
                        *raw = &bytes[3..];
                        Some(match bytes[2] {
                            1 => Tag::Procedure.bytes(),
                            2 => Tag::Signature.bytes(),
                            _ => unreachable!("issued packed dictionary marker"),
                        })
                    }
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
    fn procedure_trailers_match_real_canonical_encoding_and_near_misses_keep_bytes() {
        use crate::{ProcedureMetadata, ProcedureSignature};

        for (variadic, flag) in [(false, TRAILER), (true, VARIADIC_TRAILER)] {
            let procedure = ProcedureMetadata {
                signature: ProcedureSignature {
                    parameters: Arc::from([]),
                    variadic,
                    return_annotation: None,
                },
                settings: Arc::from([]),
            };
            let trailer = procedure.canonical_bytes();
            assert_eq!(trailer_bytes(flag), trailer);
            for body in [vec![], vec![7, 8, 9], vec![0; 128], (0..128).map(|at| (at % 2) as u8).collect()] {
                let mut bytes = CANONICAL_HEADER_PREFIX.to_vec();
                bytes.extend_from_slice(&body);
                bytes.extend_from_slice(&trailer);
                let packed = CanonicalBytes::plan(&bytes).seal();
                assert_eq!(packed.storage_arc()[1] & (TRAILER | VARIADIC_TRAILER), flag);
                assert_eq!(packed.len(), bytes.len());
                assert_eq!(packed.to_vec(), bytes);
                assert_eq!(packed, CanonicalBytes::from(bytes.clone()));
                assert_eq!(packed.xxh3_128(), xxhash_rust::xxh3::xxh3_128(&bytes));
                assert!(std::ptr::eq(packed.chunks().last().unwrap(), trailer_bytes(flag)));
                *bytes.last_mut().unwrap() = 1;
                let mismatch = CanonicalBytes::plan(&bytes).seal();
                assert_eq!(mismatch.storage_arc()[1] & (TRAILER | VARIADIC_TRAILER), 0);
                assert_eq!(mismatch.to_vec(), bytes);
                assert_ne!(mismatch, packed);
            }
        }
    }

    #[test]
    fn dynamic_procedure_markers_match_real_encoder_and_require_both_exact_tags() {
        use crate::{Parameter, ProcedureMetadata, ProcedureSignature, SymbolId};
        let procedure = ProcedureMetadata {
            signature: ProcedureSignature {
                parameters: Arc::from([Parameter::new(
                    SymbolId::of("parameter"), Some(SymbolId::of("/datum")), None, 0,
                    dm_syntax::Span::new(0, 1),
                )]),
                variadic: true,
                return_annotation: None,
            },
            settings: Arc::from([]),
        };
        let mut bytes = CANONICAL_HEADER_PREFIX.to_vec();
        bytes.extend_from_slice(&[7, 0, 0, 9, 0]);
        let suffix_start = bytes.len();
        bytes.extend_from_slice(&procedure.canonical_bytes());
        let ordinary = CanonicalBytes::plan(&bytes).seal();
        let plan = CanonicalBytes::plan_procedure(&bytes, suffix_start);
        let storage_len = plan.storage_len();
        let packed = plan.seal();
        assert_eq!(packed.storage_arc().len(), storage_len);
        assert!(storage_len + 32 < ordinary.storage_arc().len());
        assert_eq!(packed.len(), bytes.len());
        assert_eq!(packed.to_vec(), bytes);
        assert_eq!(packed, ordinary);
        assert_eq!(packed, CanonicalBytes::from(bytes.clone()));
        assert_eq!(packed.xxh3_128(), xxhash_rust::xxh3::xxh3_128(&bytes));
        assert!(packed.chunks().any(|chunk| std::ptr::eq(chunk, SIGNATURE_TAG)));

        let signature_start = suffix_start + PROCEDURE_TAG.len() + size_of::<u64>();
        for at in [suffix_start, signature_start] {
            let mut mismatch = bytes.clone();
            mismatch[at] ^= 1;
            let packed = CanonicalBytes::plan_procedure(&mismatch, suffix_start).seal();
            assert_eq!(packed.to_vec(), mismatch);
            assert_eq!(packed.storage_arc(), CanonicalBytes::plan(&mismatch).seal().storage_arc());
        }
        let wrong_offset = CanonicalBytes::plan_procedure(&bytes, suffix_start + 1).seal();
        assert_eq!(wrong_offset.storage_arc(), ordinary.storage_arc());
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
