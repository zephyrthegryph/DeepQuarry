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
#[derive(Clone, Copy)]
struct Entry {
    offset: usize,
    length: usize,
    checksum: u128,
}
pub struct Segment {
    map: Mmap,
    id: u128,
    supersedes: Vec<u128>,
    index: BTreeMap<RecordKey, Entry>,
    rejected: AtomicBool,
    limits: Limits,
}
pub struct RecordView<'a> {
    pub key: RecordKey,
    pub symbols: Vec<(u64, &'a [u8])>,
    pub payload: &'a [u8],
}
impl Segment {
    pub fn open(path: &Path, limits: Limits) -> Result<Self, CacheError> {
        let file = File::open(path)?;
        let length = file.metadata()?.len();
        if length < HEADER as u64 || length > limits.segment_bytes {
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
        if count > limits.records || superseded > limits.records {
            return Err(invalid("record count outside limits"));
        }
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
        let mut index = BTreeMap::new();
        let mut next = HEADER + metadata_len;
        for _ in 0..count {
            let key = RecordKey {
                stage: meta.u32()?,
                version: meta.u32()?,
                content: meta.u128()?,
            };
            let offset =
                usize::try_from(meta.u64()?).map_err(|_| invalid("record offset overflow"))?;
            let length =
                usize::try_from(meta.u64()?).map_err(|_| invalid("record length overflow"))?;
            let checksum = meta.u128()?;
            let end = offset
                .checked_add(length)
                .ok_or_else(|| invalid("record bounds overflow"))?;
            if offset != next || end > map.len() {
                return Err(invalid("record bounds or ordering invalid"));
            }
            next = end;
            if index
                .insert(
                    key,
                    Entry {
                        offset,
                        length,
                        checksum,
                    },
                )
                .is_some()
            {
                return Err(invalid("duplicate record key"));
            }
        }
        if next != map.len() {
            return Err(invalid("unindexed segment bytes"));
        }
        Ok(Self {
            map,
            id,
            supersedes,
            index,
            rejected: AtomicBool::new(false),
            limits,
        })
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
        self.index.keys().copied()
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
        let Some(entry) = self.index.get(&key) else {
            return Ok(None);
        };
        let result = (|| {
            let bytes = &self.map[entry.offset..entry.offset + entry.length];
            if xxh3_128(bytes) != entry.checksum {
                return Err(invalid("record checksum mismatch"));
            }
            let mut cursor = Cursor { data: bytes, at: 0 };
            let count = cursor.u32()?;
            if count > self.limits.symbols_per_record {
                return Err(invalid("symbol count outside limits"));
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
            if length > self.limits.payload_bytes {
                return Err(invalid("payload outside limits"));
            }
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
    limits: Limits,
) -> Result<(u128, Vec<u8>), CacheError> {
    if records.len() > limits.records as usize || supersedes.len() > limits.records as usize {
        return Err(invalid("segment count outside limits"));
    }
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
        if record.payload.len() as u64 > limits.payload_bytes
            || record.symbols.len() > limits.symbols_per_record as usize
        {
            return Err(invalid("record outside limits"));
        }
        let offset = HEADER + metadata_len + body.len();
        let start = body.len();
        body.extend_from_slice(&(record.symbols.len() as u32).to_le_bytes());
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
            if (HEADER + metadata_len + body.len()) as u64 + 12 + u64::from(len)
                > limits.segment_bytes
            {
                return Err(invalid("segment exceeds byte limit"));
            }
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
        if (HEADER + metadata_len + body.len()) as u64 > limits.segment_bytes {
            return Err(invalid("segment exceeds byte limit"));
        }
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
    result.extend_from_slice(&(records.len() as u32).to_le_bytes());
    result.extend_from_slice(&(supersedes.len() as u32).to_le_bytes());
    result.extend_from_slice(&id.to_le_bytes());
    let mut framing = Xxh3::new();
    framing.update(&result);
    framing.update(&metadata);
    result.extend_from_slice(&framing.digest128().to_le_bytes());
    result.extend(metadata);
    result.extend(body);
    Ok((id, result))
}
