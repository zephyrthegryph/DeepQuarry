use memmap2::Mmap;
use std::{
    collections::{BTreeMap, BTreeSet},
    fs::File,
    path::Path,
    sync::{
        atomic::{AtomicBool, Ordering},
        Arc,
    },
};
use xxhash_rust::xxh3::{xxh3_128, Xxh3};
const MAGIC: &[u8; 8] = b"DMBCSEG1";
const FORMAT: u32 = 1;
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
        if cursor.take(8)? != MAGIC || cursor.u32()? != FORMAT || cursor.u32()? != 0 {
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
    fn find(&self, key: RecordKey) -> Option<Entry> {
        let at = self
            .order
            .binary_search_by_key(&key, |slot| descriptor_key(&self.map, self.descriptors, *slot))
            .ok()?;
        Some(self.entry_at(self.order[at]))
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
        let Some(entry) = self.find(key) else {
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
            let length = cursor.u64()?;
            let padding = (16 - (entry.offset + cursor.at) % 16) % 16;
            if cursor.take(padding)?.iter().any(|byte| *byte != 0) {
                return Err(invalid("payload alignment padding invalid"));
            }
            let payload = cursor
                .take(usize::try_from(length).map_err(|_| invalid("payload length overflow"))?)?;
            if cursor.at != bytes.len() {
                return Err(invalid("record trailing bytes"));
            }
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
        body.extend_from_slice(&(record.payload.len() as u64).to_le_bytes());
        let padding = (16 - (HEADER + metadata_len + body.len()) % 16) % 16;
        body.resize(body.len() + padding, 0);
        body.extend_from_slice(&record.payload);
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
