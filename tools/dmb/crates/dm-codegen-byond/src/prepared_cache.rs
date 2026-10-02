//! Persistent prepared sections. Database access is stage-batched; hot links
//! only apply relocations to a validated, resident flat section.
use crate::{
    relocatable::PreparedProc, Ledger, LinkError, SimpleProc, Symbol, SymbolicProc, Table,
};
use dm_store::{Key, Store};
use sha2::{Digest, Sha256};
use std::{
    collections::BTreeMap,
    io::{self, Write},
    path::Path,
    sync::Arc,
};

const SNAPSHOT_BYTES: usize = 128 * 1024 * 1024;
const RESIDENT_BYTES: usize = 64 * 1024 * 1024;
const PENDING_BYTES: usize = 32 * 1024 * 1024;

/// Metadata retains authored string ordering, local/formal slots and origins.
/// Its `code` is always empty; linked code is exclusively in the flat section.
/// The envelope is suitable for a semantic graph result keyed before codegen.
pub struct PreparedProcedureEnvelope {
    pub metadata: SimpleProc,
    pub section: Arc<PreparedProc>,
    /// Offset of the original body anchor from the current procedure span.
    /// Provenance is rebased by the caller and never participates in table IDs.
    pub body_base_relative: usize,
    reference_origins: Vec<(Symbol, Option<crate::debug::RelativeStatementSpan>)>,
}
#[derive(serde::Serialize)]
struct EnvelopeMetadataRef<'a> {
    procedure: &'a SimpleProc,
    reference_origins: &'a [(Symbol, Option<crate::debug::RelativeStatementSpan>)],
}
#[derive(serde::Deserialize)]
struct EnvelopeMetadata {
    procedure: SimpleProc,
    reference_origins: Vec<(Symbol, Option<crate::debug::RelativeStatementSpan>)>,
}
impl PreparedProcedureEnvelope {
    pub fn reference_origin(
        &self,
        table: Table,
        name: &str,
    ) -> Option<crate::debug::RelativeStatementSpan> {
        self.reference_origins
            .iter()
            .find(|(symbol, _)| symbol.table == table && symbol.key == name)
            .and_then(|(_, span)| *span)
    }
    pub fn reference_origin_bytes(&self) -> usize {
        self.reference_origins.capacity()
            * std::mem::size_of::<(Symbol, Option<crate::debug::RelativeStatementSpan>)>()
            + self
                .reference_origins
                .iter()
                .map(|(symbol, _)| symbol.key.capacity())
                .sum::<usize>()
    }
    pub fn prepare(source: &SimpleProc) -> Result<Self, LinkError> {
        let section = Arc::new(PreparedProc::prepare(&source.code)?);
        let mut metadata = source.clone();
        metadata.code = SymbolicProc::default();
        Ok(Self {
            metadata,
            section,
            body_base_relative: 0,
            reference_origins: crate::debug::reference_origins(source),
        })
    }
    pub fn encode(&self) -> Result<Vec<u8>, LinkError> {
        if !self.metadata.code.items.is_empty() {
            return Err(LinkError::Decode(
                "envelope metadata contains symbolic code".into(),
            ));
        }
        let metadata = serde_json::to_vec(&EnvelopeMetadataRef {
            procedure: &self.metadata,
            reference_origins: &self.reference_origins,
        })
        .map_err(|e| LinkError::Decode(e.to_string()))?;
        let section = self.section.encode()?;
        if metadata.len() + section.len() + 20 > 32 * 1024 * 1024 {
            return Err(LinkError::Decode("prepared envelope exceeds limit".into()));
        }
        let mut bytes = b"DMENV003".to_vec();
        bytes.extend_from_slice(&(metadata.len() as u32).to_le_bytes());
        bytes.extend_from_slice(&(self.body_base_relative as u64).to_le_bytes());
        bytes.extend_from_slice(&metadata);
        bytes.extend_from_slice(&section);
        Ok(bytes)
    }
    pub fn decode(bytes: &[u8]) -> Result<Self, LinkError> {
        if bytes.len() > 32 * 1024 * 1024 || bytes.len() < 20 || &bytes[..8] != b"DMENV003" {
            return Err(LinkError::Decode("invalid prepared envelope".into()));
        }
        let length = u32::from_le_bytes([bytes[8], bytes[9], bytes[10], bytes[11]]) as usize;
        let body_base_relative = usize::try_from(u64::from_le_bytes(
            bytes[12..20]
                .try_into()
                .map_err(|_| LinkError::Decode("invalid origin scalar".into()))?,
        ))
        .map_err(|_| LinkError::OffsetOverflow)?;
        let end = 20usize
            .checked_add(length)
            .filter(|end| *end <= bytes.len())
            .ok_or_else(|| LinkError::Decode("truncated prepared envelope".into()))?;
        let stored: EnvelopeMetadata = serde_json::from_slice(&bytes[20..end])
            .map_err(|e| LinkError::Decode(e.to_string()))?;
        let metadata = stored.procedure;
        if !metadata.code.items.is_empty() {
            return Err(LinkError::Decode(
                "envelope metadata contains symbolic code".into(),
            ));
        }
        let section = Arc::new(PreparedProc::decode(&bytes[end..])?);
        if stored.reference_origins.len() > section.word_count() {
            return Err(LinkError::Decode(
                "reference origin count exceeds section".into(),
            ));
        }
        let mut expected = std::collections::BTreeSet::new();
        section.for_each_reference(|table, name| {
            expected.insert(Symbol::new(table, name));
        });
        for (symbol, span) in &stored.reference_origins {
            if !expected.remove(symbol) || span.is_some_and(|span| span.end < span.start) {
                return Err(LinkError::Decode("invalid reference origin sidecar".into()));
            }
        }
        if !expected.is_empty() {
            return Err(LinkError::Decode(
                "incomplete reference origin sidecar".into(),
            ));
        }
        Ok(Self {
            metadata,
            section,
            body_base_relative,
            reference_origins: stored.reference_origins,
        })
    }
}

#[derive(Clone, Copy, Debug, Default)]
pub struct PreparedCacheStats {
    pub hits: usize,
    pub misses: usize,
    pub corrupt: usize,
    pub snapshot_records: usize,
    pub snapshot_bytes: usize,
    pub snapshot_complete: bool,
}

pub struct PreparedProcCache {
    store: Option<Store>,
    namespace: String,
    snapshot: BTreeMap<String, Vec<u8>>,
    resident: BTreeMap<String, Arc<PreparedProc>>,
    resident_bytes: usize,
    pending: BTreeMap<String, Vec<u8>>,
    pending_bytes: usize,
    stats: PreparedCacheStats,
}

impl PreparedProcCache {
    /// Optional cache failures never prevent correct fresh compilation.
    pub fn open(root: &Path, stage_fingerprint: &str) -> Self {
        let namespace = format!("prepared-v1-{stage_fingerprint}");
        let store = Store::open(root.join("prepared.redb")).ok();
        let mut stats = PreparedCacheStats::default();
        let snapshot = store.as_ref().and_then(|store| {
            store
                .snapshot_namespace(&namespace, 128_000, SNAPSHOT_BYTES, None)
                .ok()
        });
        let records = if let Some(snapshot) = snapshot {
            stats.snapshot_records = snapshot.records.len();
            stats.snapshot_bytes = snapshot
                .records
                .iter()
                .map(|(key, value)| key.name.len() + value.len())
                .sum();
            stats.snapshot_complete = snapshot.complete;
            snapshot
                .records
                .into_iter()
                .map(|(key, value)| (key.name, value))
                .collect()
        } else {
            BTreeMap::new()
        };
        Self {
            store,
            namespace,
            snapshot: records,
            resident: BTreeMap::new(),
            resident_bytes: 0,
            pending: BTreeMap::new(),
            pending_bytes: 0,
            stats,
        }
    }
    pub fn stats(&self) -> PreparedCacheStats {
        self.stats
    }

    /// Includes the full current symbolic code (including injected debug words).
    pub fn symbolic_key(source: &SymbolicProc) -> Result<String, LinkError> {
        let mut writer = HashWriter(Sha256::new());
        writer.0.update(b"dm-prepared-symbolic-v1\0");
        serde_json::to_writer(&mut writer, source).map_err(|e| LinkError::Decode(e.to_string()))?;
        Ok(format!("{:x}", writer.0.finalize()))
    }
    pub fn link(&mut self, source: &SymbolicProc, ledger: &Ledger) -> Result<Vec<u32>, LinkError> {
        let key = Self::symbolic_key(source)?;
        self.link_cached(&key, || Ok(source), ledger)
    }
    /// `key` must identify exact symbolic words and semantic frame under the
    /// supplied stage fingerprint. Include current debug provenance when used.
    /// The source callback is never called on a validated cache hit.
    pub fn link_cached<'a>(
        &mut self,
        key: &str,
        source: impl FnOnce() -> Result<&'a SymbolicProc, LinkError>,
        ledger: &Ledger,
    ) -> Result<Vec<u32>, LinkError> {
        self.section_cached(key, source)?.materialize(ledger)
    }
    pub fn section_cached<'a>(
        &mut self,
        key: &str,
        source: impl FnOnce() -> Result<&'a SymbolicProc, LinkError>,
    ) -> Result<Arc<PreparedProc>, LinkError> {
        // Reject unbounded external names; the normal key is a SHA-256 hex string.
        if key.len() > 256 || key.is_empty() {
            return Err(LinkError::Decode("invalid prepared cache key".into()));
        }
        if let Some(section) = self.resident.get(key) {
            self.stats.hits += 1;
            return Ok(section.clone());
        }
        let encoded = self.pending.get(key).or_else(|| self.snapshot.get(key));
        if let Some(encoded) = encoded {
            match PreparedProc::decode(encoded) {
                Ok(section) => {
                    self.stats.hits += 1;
                    let section = Arc::new(section);
                    self.retain(key, &section);
                    return Ok(section);
                }
                Err(_) => self.stats.corrupt += 1,
            }
        }
        self.stats.misses += 1;
        let section = Arc::new(PreparedProc::prepare(source()?)?);
        if let Ok(encoded) = section.encode() {
            if self.pending_bytes + encoded.len() > PENDING_BYTES {
                let _ = self.flush();
            }
            if encoded.len() <= PENDING_BYTES && self.pending_bytes + encoded.len() <= PENDING_BYTES
            {
                if let Some(previous) = self.pending.insert(key.to_owned(), encoded.clone()) {
                    self.pending_bytes -= previous.len();
                }
                self.pending_bytes += encoded.len();
            }
        }
        self.retain(key, &section);
        Ok(section)
    }
    fn retain(&mut self, key: &str, section: &Arc<PreparedProc>) {
        let bytes = section.resident_bytes() + key.len();
        if bytes > RESIDENT_BYTES {
            return;
        }
        if self.resident_bytes + bytes > RESIDENT_BYTES {
            self.resident.clear();
            self.resident_bytes = 0;
        }
        self.resident.insert(key.to_owned(), section.clone());
        self.resident_bytes += bytes;
    }
    pub fn flush(&mut self) -> io::Result<()> {
        if self.pending.is_empty() {
            return Ok(());
        }
        if let Some(store) = &self.store {
            let values: Vec<_> = self
                .pending
                .iter()
                .map(|(key, bytes)| (Key::new(&self.namespace, key), bytes.clone()))
                .collect();
            store.put_many(values, None)?;
        }
        // Keep only the bounded resident decoded hot set; disk is next-stage authority.
        self.pending.clear();
        self.pending_bytes = 0;
        Ok(())
    }
}
impl Drop for PreparedProcCache {
    fn drop(&mut self) {
        let _ = self.flush();
    }
}
struct HashWriter(Sha256);
impl Write for HashWriter {
    fn write(&mut self, bytes: &[u8]) -> io::Result<usize> {
        self.0.update(bytes);
        Ok(bytes.len())
    }
    fn flush(&mut self) -> io::Result<()> {
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{Instruction, Item, Symbol, Table, ValueWord, Word};
    #[test]
    fn envelope_roundtrips_body_origin_without_symbolic_code() {
        let procedure = SimpleProc {
            code: SymbolicProc {
                items: vec![Item::Instruction(Instruction {
                    opcode: 0,
                    operands: vec![],
                })],
            },
            ..Default::default()
        };
        let mut envelope = PreparedProcedureEnvelope::prepare(&procedure).unwrap();
        envelope.body_base_relative = 113;
        let decoded = PreparedProcedureEnvelope::decode(&envelope.encode().unwrap()).unwrap();
        assert_eq!(decoded.body_base_relative, 113);
        assert!(decoded.metadata.code.items.is_empty());
        assert_eq!(
            decoded.section.materialize(&Ledger::default()).unwrap(),
            vec![0]
        );
    }
    #[test]
    fn envelope_preserves_first_reference_statement_origins() {
        let body =
            dm_syntax::parse("/proc/probe()\n    var/value = 1\n    return new /datum/missing\n")
                .items
                .remove(0)
                .children;
        let source = crate::compile_simple_proc(&body).unwrap();
        let expected =
            crate::debug::reference_origin(&source, Table::Class, "/datum/missing").unwrap();
        let envelope = PreparedProcedureEnvelope::prepare(&source).unwrap();
        let decoded = PreparedProcedureEnvelope::decode(&envelope.encode().unwrap()).unwrap();
        assert!(decoded.metadata.code.items.is_empty());
        assert_eq!(
            decoded.reference_origin(Table::Class, "/datum/missing"),
            Some(expected)
        );
        assert_eq!(decoded.reference_origin(Table::Class, "/datum/other"), None);
    }
    #[test]
    fn restart_hits_bypass_source_and_relocate_ids() {
        let root = std::env::temp_dir().join(format!(
            "dm-prepared-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        let source = SymbolicProc {
            items: vec![
                Item::Instruction(Instruction {
                    opcode: 0x60,
                    operands: vec![Word::Value(ValueWord::String("hello".into()))],
                }),
                Item::Instruction(Instruction {
                    opcode: 0,
                    operands: vec![],
                }),
            ],
        };
        let key = PreparedProcCache::symbolic_key(&source).unwrap();
        let mut ledger = Ledger::default();
        ledger.bind(Symbol::new(Table::String, "hello"), 1).unwrap();
        let mut cache = PreparedProcCache::open(&root, "test-stage");
        assert_eq!(
            cache.link(&source, &ledger).unwrap(),
            crate::link_proc(&source, &ledger).unwrap().words
        );
        cache.flush().unwrap();
        drop(cache);
        let mut cache = PreparedProcCache::open(&root, "test-stage");
        let mut moved = Ledger::default();
        moved
            .bind(Symbol::new(Table::String, "hello"), 0x123456)
            .unwrap();
        assert_eq!(
            cache
                .link_cached(
                    &key,
                    || panic!("cache hit must not request symbolic source"),
                    &moved
                )
                .unwrap(),
            crate::link_proc(&source, &moved).unwrap().words
        );
        assert_eq!(cache.stats().hits, 1);
        let mut other = PreparedProcCache::open(&root, "changed-stage");
        other.link_cached(&key, || Ok(&source), &moved).unwrap();
        assert_eq!(other.stats().misses, 1);
        drop(cache);
        drop(other);
        std::fs::remove_dir_all(root).unwrap();
    }
}
