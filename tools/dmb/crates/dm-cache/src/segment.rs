use memmap2::Mmap;
use std::{
    collections::{BTreeMap, BTreeSet},
    fs::File,
    path::Path,
    sync::{
        atomic::{AtomicBool, Ordering},
        Arc, OnceLock,
    },
};
use xxhash_rust::xxh3::{xxh3_128, Xxh3};
const MAGIC: &[u8; 8] = b"DMBCSEG1";
/// Segment format written now. Format 1 (every payload stored verbatim) stays readable; format 2 adds the per-record compression
/// flag in the payload length word (`COMPRESSED`), so an older binary rejects a format-2 segment instead of misreading it.
pub(crate) const FORMAT: u32 = 2;
const FORMAT_VERBATIM: u32 = 1;
/// Top bit of the payload length word: the stored bytes are an LZ4 block with its uncompressed size prepended.
pub(crate) const COMPRESSED: u64 = 1 << 63;
/// Payloads below this size are never compressed (the saving would not pay the decode).
const COMPRESS_MIN_BYTES: usize = 512;
/// A compressed payload must be at most this many eighths of the original, else it is stored verbatim.
const COMPRESS_MAX_EIGHTHS: usize = 7;
/// Upper bound on a decoded payload; a record's checksum is verified first, so this only guards a corrupt writer.
const DECODED_MAX_BYTES: usize = 1 << 30;
const HEADER: usize = 72;
const DESCRIPTOR: usize = 56;
#[derive(Clone, Copy, Debug, Eq, PartialEq, Ord, PartialOrd, Hash)]
pub struct RecordKey {
    pub stage: u32,
    pub version: u32,
    pub content: u128,
}
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct SymbolText {
    pub id: u64,
    pub text: Arc<[u8]>,
}
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct Record {
    pub key: RecordKey,
    pub symbols: Vec<SymbolText>,
    pub payload: Arc<[u8]>,
}
#[derive(Clone, Copy, Debug)]
pub struct Limits {
    pub segment_bytes: u64,
    pub payload_bytes: u64,
    pub records: u32,
    pub symbols_per_record: u32,
}
impl Default for Limits {
    fn default() -> Self {
        Self {
            segment_bytes: 64 * 1024 * 1024,
            payload_bytes: 32 * 1024 * 1024,
            records: 1_000_000,
            symbols_per_record: 1_000_000,
        }
    }
}
#[derive(Debug)]
pub enum CacheError {
    Io(std::io::Error),
    Invalid(String),
    Payload(String),
    Busy,
}
impl From<std::io::Error> for CacheError {
    fn from(e: std::io::Error) -> Self {
        Self::Io(e)
    }
}
impl std::fmt::Display for CacheError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{self:?}")
    }
}
impl std::error::Error for CacheError {}
fn invalid(message: &str) -> CacheError {
    CacheError::Invalid(message.into())
}
struct Cursor<'a> {
    data: &'a [u8],
    at: usize,
}
impl<'a> Cursor<'a> {
    fn take(&mut self, n: usize) -> Result<&'a [u8], CacheError> {
        let end = self
            .at
            .checked_add(n)
            .ok_or_else(|| invalid("offset overflow"))?;
        let value = self
            .data
            .get(self.at..end)
            .ok_or_else(|| invalid("truncated record"))?;
        self.at = end;
        Ok(value)
    }
    fn u32(&mut self) -> Result<u32, CacheError> {
        Ok(u32::from_le_bytes(self.take(4)?.try_into().unwrap()))
    }
    fn u64(&mut self) -> Result<u64, CacheError> {
        Ok(u64::from_le_bytes(self.take(8)?.try_into().unwrap()))
    }
    fn u128(&mut self) -> Result<u128, CacheError> {
        Ok(u128::from_le_bytes(self.take(16)?.try_into().unwrap()))
    }
}
fn descriptor_key(map: &[u8], descriptors: usize, slot: u32) -> RecordKey {
    let at = descriptors + slot as usize * DESCRIPTOR;
    RecordKey {
        stage: u32::from_le_bytes(map[at..at + 4].try_into().unwrap()),
        version: u32::from_le_bytes(map[at + 4..at + 8].try_into().unwrap()),
        content: u128::from_le_bytes(map[at + 8..at + 24].try_into().unwrap()),
    }
}
/// A decoded (decompressed) payload with 16-byte alignment, the alignment verbatim payloads have inside the mapping.
pub(crate) struct AlignedBytes {
    words: Vec<u128>,
    len: usize,
}
impl AlignedBytes {
    fn decode(stored: &[u8]) -> Result<Self, CacheError> {
        if stored.len() < 4 {
            return Err(invalid("compressed payload truncated"));
        }
        let len = u32::from_le_bytes(stored[..4].try_into().unwrap()) as usize;
        if len > DECODED_MAX_BYTES {
            return Err(invalid("decoded payload too large"));
        }
        let mut words = vec![0u128; len.div_ceil(16)];
        // SAFETY: `words` owns at least `len` initialized bytes and u8 has no alignment or validity requirement.
        let target = unsafe { std::slice::from_raw_parts_mut(words.as_mut_ptr().cast::<u8>(), len) };
        let written = lz4_flex::block::decompress_into(&stored[4..], target)
            .map_err(|error| CacheError::Invalid(format!("payload decode failed: {error}")))?;
        if written != len {
            return Err(invalid("payload decode length mismatch"));
        }
        Ok(Self { words, len })
    }
    /// The original bytes of a stored LZ4 payload (size prepended), as the spool and the streaming writer need them.
    pub(crate) fn unpack(stored: &[u8]) -> Result<Vec<u8>, CacheError> {
        Ok(Self::decode(stored)?.bytes().to_vec())
    }
    pub(crate) fn bytes(&self) -> &[u8] {
        // SAFETY: as in `decode`; the borrow of `self` bounds the slice.
        unsafe { std::slice::from_raw_parts(self.words.as_ptr().cast::<u8>(), self.len) }
    }
}
#[derive(Clone, Copy)]
struct Entry {
    offset: usize,
    length: usize,
    checksum: u128,
}
pub struct Segment {
    map: Arc<Mmap>,
    id: u128,
    supersedes: Vec<u128>,
    /// Byte offset of the first record descriptor in the mapping.
    descriptors: usize,
    /// Descriptor slots ordered by record key: 4 bytes per record on the heap. The descriptor itself (key, offset, length,
    /// checksum) is read from the validated mapping on demand; an entry-per-record `BTreeMap` held about 90 bytes per
    /// record, which for a multi-gigabyte shared cache was hundreds of megabytes of every compile.
    order: Vec<u32>,
    /// Decoded copy of each compressed record's payload, by descriptor slot, filled on first read and kept for the segment's life
    /// (a view borrows from it). Verbatim records never use their cell.
    decoded: Vec<OnceLock<Arc<AlignedBytes>>>,
    rejected: AtomicBool,
}
pub struct RecordView<'a> {
    pub key: RecordKey,
    pub symbols: Vec<(u64, &'a [u8])>,
    pub payload: &'a [u8],
}
impl Segment {
    pub fn open(path: &Path, _limits: Limits) -> Result<Self, CacheError> {
        let file = File::open(path)?;
        let length = file.metadata()?.len();
        if length < HEADER as u64 {
            return Err(invalid("segment size outside limits"));
        }
        // Published segments are immutable. The cache never modifies a mapped file;
        // callers must not externally truncate or overwrite published cache files.
        let map = unsafe { memmap2::MmapOptions::new().map(&file)? };
        let mut cursor = Cursor { data: &map, at: 0 };
        if cursor.take(8)? != MAGIC || !matches!(cursor.u32()?, FORMAT | FORMAT_VERBATIM) || cursor.u32()? != 0 {
            return Err(invalid("segment format mismatch"));
        }
        if cursor.u64()? != length {
            return Err(invalid("segment length mismatch"));
        }
        let metadata_len =
            usize::try_from(cursor.u64()?).map_err(|_| invalid("metadata length overflow"))?;
        let count = cursor.u32()?;
        let superseded = cursor.u32()?;
        let id = cursor.u128()?;
        let checksum = cursor.u128()?;
        let expected = (count as usize)
            .checked_mul(DESCRIPTOR)
            .and_then(|n| n.checked_add(superseded as usize * 16))
            .ok_or_else(|| invalid("metadata size overflow"))?;
        if expected != metadata_len {
            return Err(invalid("metadata framing mismatch"));
        }
        let metadata = cursor.take(metadata_len)?;
        let mut framing = Xxh3::new();
        framing.update(&map[..56]);
        framing.update(metadata);
        if framing.digest128() != checksum {
            return Err(invalid("metadata checksum mismatch"));
        }
        let mut meta = Cursor {
            data: metadata,
            at: 0,
        };
        let mut supersedes = Vec::new();
        let mut seen = BTreeSet::new();
        for _ in 0..superseded {
            let value = meta.u128()?;
            if value == id || !seen.insert(value) {
                return Err(invalid("invalid supersedes list"));
            }
            supersedes.push(value);
        }
        let descriptors = HEADER + superseded as usize * 16;
        let mut next = HEADER + metadata_len;
        for _ in 0..count {
            // Key fields are re-read from the mapping on lookup; here only the bounds are validated.
            meta.take(24)?;
            let offset =
                usize::try_from(meta.u64()?).map_err(|_| invalid("record offset overflow"))?;
            let length =
                usize::try_from(meta.u64()?).map_err(|_| invalid("record length overflow"))?;
            meta.take(16)?;
            let end = offset
                .checked_add(length)
                .ok_or_else(|| invalid("record bounds overflow"))?;
            if offset != next || end > map.len() {
                return Err(invalid("record bounds or ordering invalid"));
            }
            next = end;
        }
        if next != map.len() {
            return Err(invalid("unindexed segment bytes"));
        }
        let mut order: Vec<u32> = (0..count).collect();
        order.sort_unstable_by_key(|slot| descriptor_key(&map, descriptors, *slot));
        if order.windows(2).any(|pair| {
            descriptor_key(&map, descriptors, pair[0]) == descriptor_key(&map, descriptors, pair[1])
        }) {
            return Err(invalid("duplicate record key"));
        }
        Ok(Self {
            map: Arc::new(map),
            id,
            supersedes,
            descriptors,
            order,
            decoded: (0..count).map(|_| OnceLock::new()).collect(),
            rejected: AtomicBool::new(false),
        })
    }
    /// Descriptor of a record slot; the mapping's framing was validated by `open`.
    fn entry_at(&self, slot: u32) -> Entry {
        let at = self.descriptors + slot as usize * DESCRIPTOR;
        let bytes = &self.map[at + 24..at + DESCRIPTOR];
        Entry {
            offset: u64::from_le_bytes(bytes[0..8].try_into().unwrap()) as usize,
            length: u64::from_le_bytes(bytes[8..16].try_into().unwrap()) as usize,
            checksum: u128::from_le_bytes(bytes[16..32].try_into().unwrap()),
        }
    }
    fn find_slot(&self, key: RecordKey) -> Option<(u32, Entry)> {
        let at = self
            .order
            .binary_search_by_key(&key, |slot| descriptor_key(&self.map, self.descriptors, *slot))
            .ok()?;
        let slot = self.order[at];
        Some((slot, self.entry_at(slot)))
    }
    fn find(&self, key: RecordKey) -> Option<Entry> {
        self.find_slot(key).map(|(_, entry)| entry)
    }
    /// The decoded owner of `key`'s payload when that record is stored compressed and has been read.
    pub(crate) fn decoded_owner(&self, key: RecordKey) -> Option<Arc<AlignedBytes>> {
        let (slot, _) = self.find_slot(key)?;
        self.decoded[slot as usize].get().cloned()
    }
    pub(crate) fn map_ptr(&self) -> usize {
        self.map.as_ptr() as usize
    }
    pub(crate) fn map_len(&self) -> usize {
        self.map.len()
    }
    pub(crate) fn map_arc(&self) -> &Arc<Mmap> {
        &self.map
    }
    /// Whether the segment holds a record with this key (no payload validation).
    pub fn contains(&self, key: RecordKey) -> bool {
        self.find(key).is_some()
    }
    /// Number of records in the segment.
    pub fn record_count(&self) -> usize {
        self.order.len()
    }
    pub fn id(&self) -> u128 {
        self.id
    }
    pub fn mapped_bytes(&self) -> usize {
        self.map.len()
    }
    pub fn supersedes(&self) -> &[u128] {
        &self.supersedes
    }
    pub fn keys(&self) -> impl Iterator<Item = RecordKey> + '_ {
        self.order
            .iter()
            .map(|slot| descriptor_key(&self.map, self.descriptors, *slot))
    }
    pub fn is_rejected(&self) -> bool {
        self.rejected.load(Ordering::Acquire)
    }
    /// Checksum and caller's typed bytecheck run before exposing any payload.
    /// Any failure permanently rejects this entire mapped segment.
    pub fn get<'a>(
        &'a self,
        key: RecordKey,
        validate: impl FnOnce(&[u8], &[(u64, &[u8])]) -> Result<(), String>,
    ) -> Result<Option<RecordView<'a>>, CacheError> {
        if self.is_rejected() {
            return Ok(None);
        }
        let Some((slot, entry)) = self.find_slot(key) else {
            return Ok(None);
        };
        let result = (|| {
            let bytes = &self.map[entry.offset..entry.offset + entry.length];
            if xxh3_128(bytes) != entry.checksum {
                return Err(invalid("record checksum mismatch"));
            }
            let mut cursor = Cursor { data: bytes, at: 0 };
            let count = cursor.u32()?;
            // Each symbol needs its ID and length before any text bytes.
            if count as usize > bytes.len().saturating_sub(cursor.at) / 12 {
                return Err(invalid("symbol count exceeds record extent"));
            }
            let mut symbols = Vec::new();
            let mut seen = BTreeSet::new();
            for _ in 0..count {
                let id = cursor.u64()?;
                let len = cursor.u32()? as usize;
                let text = cursor.take(len)?;
                if !seen.insert(id) {
                    return Err(invalid("duplicate symbol identity"));
                }
                symbols.push((id, text));
            }
            let word = cursor.u64()?;
            let compressed = word & COMPRESSED != 0;
            let length = word & !COMPRESSED;
            let padding = (16 - (entry.offset + cursor.at) % 16) % 16;
            if cursor.take(padding)?.iter().any(|byte| *byte != 0) {
                return Err(invalid("payload alignment padding invalid"));
            }
            let payload = cursor
                .take(usize::try_from(length).map_err(|_| invalid("payload length overflow"))?)?;
            if cursor.at != bytes.len() {
                return Err(invalid("record trailing bytes"));
            }
            let payload: &[u8] = if compressed {
                let cell = &self.decoded[slot as usize];
                if cell.get().is_none() {
                    let _ = cell.set(Arc::new(AlignedBytes::decode(payload)?));
                }
                cell.get().expect("decoded payload was just stored").bytes()
            } else {
                payload
            };
            validate(payload, &symbols).map_err(CacheError::Payload)?;
            Ok(RecordView {
                key,
                symbols,
                payload,
            })
        })();
        if result.is_err() {
            self.rejected.store(true, Ordering::Release);
        }
        result.map(Some)
    }
}
/// Stages whose records a compile session retains as zero-copy mapped bytes (`MappedPayload`, stage 2: lowered procedure records
/// held by the resident session). Compressing them would move them from reclaimable file pages to private heap, so they are always
/// stored verbatim.
const RETAINED_MAPPED_STAGES: &[u32] = &[2];
static COMPRESS_WRITES: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(true);
/// Whether this process compresses the payloads it writes. A one-shot compile does (its decoded copies die with it); a resident
/// daemon turns it off at start, because a segment it reads keeps every decoded payload in private memory for as long as the
/// segment is open. `DMB_CACHE_COMPRESS=0` or `=1` overrides the process default either way (measurement and bisection).
pub fn set_compress_writes(on: bool) {
    COMPRESS_WRITES.store(on, Ordering::Relaxed);
}
fn compression_enabled() -> bool {
    match std::env::var("DMB_CACHE_COMPRESS").as_deref() {
        Ok("0") => false,
        Ok("1") => true,
        _ => COMPRESS_WRITES.load(Ordering::Relaxed),
    }
}
/// The LZ4 form of a `stage` record's `payload` (size prepended) when it is worth storing, else `None` (stored verbatim).
pub(crate) fn pack_payload(stage: u32, payload: &[u8]) -> Option<Vec<u8>> {
    if payload.len() < COMPRESS_MIN_BYTES
        || payload.len() > u32::MAX as usize
        || RETAINED_MAPPED_STAGES.contains(&stage)
        || !compression_enabled()
    {
        return None;
    }
    let packed = lz4_flex::block::compress_prepend_size(payload);
    (packed.len() * 8 <= payload.len() * COMPRESS_MAX_EIGHTHS).then_some(packed)
}
pub(crate) fn encode(
    records: &[Record],
    supersedes: &[u128],
    _limits: Limits,
) -> Result<(u128, Vec<u8>), CacheError> {
    let record_count =
        u32::try_from(records.len()).map_err(|_| invalid("record count overflow"))?;
    let superseded_count =
        u32::try_from(supersedes.len()).map_err(|_| invalid("supersedes count overflow"))?;
    let metadata_len = records
        .len()
        .checked_mul(DESCRIPTOR)
        .and_then(|n| n.checked_add(supersedes.len() * 16))
        .ok_or_else(|| invalid("metadata overflow"))?;
    let mut metadata = Vec::new();
    for id in supersedes {
        metadata.extend_from_slice(&id.to_le_bytes());
    }
    let mut body = Vec::new();
    let mut keys = BTreeSet::new();
    let mut all_symbols: BTreeMap<u64, Arc<[u8]>> = BTreeMap::new();
    for record in records {
        if !keys.insert(record.key) {
            return Err(invalid("duplicate record key"));
        }
        let symbol_count =
            u32::try_from(record.symbols.len()).map_err(|_| invalid("symbol count overflow"))?;
        let offset = HEADER + metadata_len + body.len();
        let start = body.len();
        body.extend_from_slice(&symbol_count.to_le_bytes());
        let mut local = BTreeSet::new();
        for symbol in &record.symbols {
            if !local.insert(symbol.id) {
                return Err(invalid("duplicate symbol identity"));
            }
            if all_symbols
                .insert(symbol.id, Arc::clone(&symbol.text))
                .is_some_and(|old| old != symbol.text)
            {
                return Err(invalid("symbol collision"));
            }
            let len =
                u32::try_from(symbol.text.len()).map_err(|_| invalid("symbol text overflow"))?;
            body.extend_from_slice(&symbol.id.to_le_bytes());
            body.extend_from_slice(&len.to_le_bytes());
            body.extend_from_slice(&symbol.text);
        }
        let packed = pack_payload(record.key.stage, &record.payload);
        let stored: &[u8] = packed.as_deref().unwrap_or(&record.payload);
        let word = stored.len() as u64 | if packed.is_some() { COMPRESSED } else { 0 };
        body.extend_from_slice(&word.to_le_bytes());
        let padding = (16 - (HEADER + metadata_len + body.len()) % 16) % 16;
        body.resize(body.len() + padding, 0);
        body.extend_from_slice(stored);
        metadata.extend_from_slice(&record.key.stage.to_le_bytes());
        metadata.extend_from_slice(&record.key.version.to_le_bytes());
        metadata.extend_from_slice(&record.key.content.to_le_bytes());
        metadata.extend_from_slice(&(offset as u64).to_le_bytes());
        metadata.extend_from_slice(&((body.len() - start) as u64).to_le_bytes());
        metadata.extend_from_slice(&xxh3_128(&body[start..]).to_le_bytes());
    }
    let mut identity = Xxh3::new();
    identity.update(&metadata);
    identity.update(&body);
    let id = identity.digest128();
    let mut result = Vec::with_capacity(HEADER + metadata.len() + body.len());
    result.extend_from_slice(MAGIC);
    result.extend_from_slice(&FORMAT.to_le_bytes());
    result.extend_from_slice(&0u32.to_le_bytes());
    result.extend_from_slice(&((HEADER + metadata.len() + body.len()) as u64).to_le_bytes());
    result.extend_from_slice(&(metadata.len() as u64).to_le_bytes());
    result.extend_from_slice(&record_count.to_le_bytes());
    result.extend_from_slice(&superseded_count.to_le_bytes());
    result.extend_from_slice(&id.to_le_bytes());
    let mut framing = Xxh3::new();
    framing.update(&result);
    framing.update(&metadata);
    result.extend_from_slice(&framing.digest128().to_le_bytes());
    result.extend(metadata);
    result.extend(body);
    Ok((id, result))
}

#[path = "mapped_payload.rs"]
mod mapped_payload;
pub use mapped_payload::MappedPayload;
