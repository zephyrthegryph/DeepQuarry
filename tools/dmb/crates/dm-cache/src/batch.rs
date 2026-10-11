//! Request-owned spool using the ordinary segment format. Payload bytes live on
//! disk; index descriptors grow with record/variant/symbol count, not payload size.
//! Producers serialize append through their request owner. Only finish publishes.
use crate::{Cache, CacheError, Record, RecordKey};
use fs2::FileExt;
use std::{
    collections::BTreeMap,
    fs::{File, OpenOptions},
    io::{Read, Seek, SeekFrom, Write},
    path::PathBuf,
    sync::atomic::{AtomicU64, Ordering},
};
use xxhash_rust::xxh3::Xxh3;
#[cfg(test)]
mod orphan_tests;
mod orphans;
#[cfg(test)]
mod tests;
mod write;
const HEADER: u64 = 72;
const DESCRIPTOR: usize = 56;
const COPY_BYTES: usize = 65536;
static NEXT: AtomicU64 = AtomicU64::new(0);
#[derive(Clone, Copy)]
struct Extent {
    at: u64,
    len: u64,
}
struct Entry {
    symbols: Vec<(u64, Extent)>,
    payloads: Vec<Extent>,
    framed: bool,
}
pub struct BatchSpool {
    cache: Cache,
    file: Option<File>,
    path: PathBuf,
    entries: BTreeMap<RecordKey, Entry>,
    symbols: BTreeMap<u64, Extent>,
    failed: bool,
}
#[derive(Debug, Default)]
pub struct BatchReport {
    pub segment: Option<u128>,
    pub records: usize,
    pub variants: usize,
}
/// Vec allocations are exact. BTree values/counts describe logical ownership,
/// not private node capacity; callers must disclose that index overhead separately.
pub enum BatchStorageView {
    Index {
        records: usize,
        symbols: usize,
    },
    Buffer {
        pointer: usize,
        len_bytes: usize,
        capacity_bytes: usize,
    },
}
fn invalid(message: &str) -> CacheError {
    CacheError::Invalid(message.into())
}
impl Cache {
    pub fn batch_spool(&self) -> Result<BatchSpool, CacheError> {
        let directory = orphans::prepare_root(self.root())?;
        // Advisory, bounded maintenance of only lifetime-locked v2 spools.
        let _ = orphans::reap(&directory, orphans::Bounds::default());
        let stamp = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map_err(|error| invalid(&error.to_string()))?
            .as_nanos();
        let path = directory.join(format!(
            ".batch-v2-{}-{stamp}-{}.tmp",
            std::process::id(),
            NEXT.fetch_add(1, Ordering::Relaxed)
        ));
        // Publish the recognizable name only after acquiring its lifetime lock.
        // A killed opening leaves at most an empty, unrecognized file.
        let opening = path.with_extension("opening");
        let file = OpenOptions::new()
            .read(true)
            .write(true)
            .create_new(true)
            .open(&opening)?;
        if let Err(error) = FileExt::try_lock_exclusive(&file) {
            drop(file);
            let _ = std::fs::remove_file(&opening);
            return Err(error.into());
        }
        if let Err(error) = std::fs::rename(&opening, &path) {
            drop(file);
            let _ = std::fs::remove_file(&opening);
            return Err(error.into());
        }
        Ok(BatchSpool {
            cache: Cache {
                root: self.root.clone(),
                limits: self.limits,
            },
            file: Some(file),
            path,
            entries: BTreeMap::new(),
            symbols: BTreeMap::new(),
            failed: false,
        })
    }
}
impl BatchSpool {
    pub fn append(&mut self, record: Record) -> Result<(), CacheError> {
        if self.failed {
            return Err(invalid("batch append previously failed"));
        }
        let result = self.append_inner(record);
        self.failed |= result.is_err();
        result
    }
    fn append_inner(&mut self, record: Record) -> Result<(), CacheError> {
        let mut local = BTreeMap::new();
        for symbol in &record.symbols {
            if local.insert(symbol.id, &symbol.text).is_some() {
                return Err(invalid("duplicate symbol identity"));
            }
            if let Some(extent) = self.symbols.get(&symbol.id).copied() {
                if !self.equal(extent, &symbol.text)? {
                    return Err(invalid("symbol collision"));
                }
            }
        }
        u32::try_from(record.symbols.len()).map_err(|_| invalid("symbol count overflow"))?;
        let framed = record.payload.starts_with(b"DMCVAR01");
        let payloads = if framed {
            crate::decode_variants(&record.payload).map_err(|error| invalid(&error))?
        } else {
            vec![record.payload.as_ref()]
        };
        if let Some(entry) = self.entries.get(&record.key) {
            if entry.framed != framed {
                return Err(invalid("same key has incompatible variant framing"));
            }
        }
        let mut symbols = self
            .entries
            .get(&record.key)
            .map(|entry| entry.symbols.clone())
            .unwrap_or_default();
        for symbol in &record.symbols {
            let extent = if let Some(extent) = self.symbols.get(&symbol.id) {
                *extent
            } else {
                let extent = self.write(&symbol.text)?;
                self.symbols.insert(symbol.id, extent);
                extent
            };
            if !symbols.iter().any(|(id, _)| *id == symbol.id) {
                symbols.push((symbol.id, extent));
            }
        }
        let mut extents = self
            .entries
            .get(&record.key)
            .map(|entry| entry.payloads.clone())
            .unwrap_or_default();
        for payload in payloads {
            let mut duplicate = false;
            for extent in &extents {
                if self.equal(*extent, payload)? {
                    duplicate = true;
                    break;
                }
            }
            if duplicate {
                continue;
            }
            if !framed && !extents.is_empty() {
                return Err(invalid("different raw payloads share one key"));
            }
            extents.push(self.write(payload)?);
        }
        u32::try_from(extents.len()).map_err(|_| invalid("variant count overflow"))?;
        self.entries.insert(
            record.key,
            Entry {
                symbols,
                payloads: extents,
                framed,
            },
        );
        Ok(())
    }
    fn write(&mut self, bytes: &[u8]) -> Result<Extent, CacheError> {
        self.cache.check_population_space(bytes.len() as u64)?;
        let file = self.file.as_mut().ok_or_else(|| invalid("closed batch"))?;
        let at = file.seek(SeekFrom::End(0))?;
        file.write_all(bytes)?;
        Ok(Extent {
            at,
            len: bytes.len() as u64,
        })
    }
    fn equal(&mut self, extent: Extent, bytes: &[u8]) -> Result<bool, CacheError> {
        if extent.len != bytes.len() as u64 {
            return Ok(false);
        }
        let file = self.file.as_mut().ok_or_else(|| invalid("closed batch"))?;
        file.seek(SeekFrom::Start(extent.at))?;
        let mut buffer = [0; COPY_BYTES];
        for chunk in bytes.chunks(COPY_BYTES) {
            file.read_exact(&mut buffer[..chunk.len()])?;
            if &buffer[..chunk.len()] != chunk {
                return Ok(false);
            }
        }
        Ok(true)
    }
    pub fn visit_storage(&self, mut visit: impl FnMut(BatchStorageView)) {
        visit(BatchStorageView::Index {
            records: self.entries.len(),
            symbols: self.symbols.len(),
        });
        for entry in self.entries.values() {
            visit(BatchStorageView::Buffer {
                pointer: entry.symbols.as_ptr() as usize,
                len_bytes: entry.symbols.len() * std::mem::size_of::<(u64, Extent)>(),
                capacity_bytes: entry.symbols.capacity() * std::mem::size_of::<(u64, Extent)>(),
            });
            visit(BatchStorageView::Buffer {
                pointer: entry.payloads.as_ptr() as usize,
                len_bytes: entry.payloads.len() * std::mem::size_of::<Extent>(),
                capacity_bytes: entry.payloads.capacity() * std::mem::size_of::<Extent>(),
            });
        }
    }
    pub fn finish(mut self) -> Result<BatchReport, CacheError> {
        if self.failed {
            return Err(invalid("batch append previously failed"));
        }
        if self.entries.is_empty() {
            return Ok(BatchReport::default());
        }
        self.finish_inner()
    }
}
impl Drop for BatchSpool {
    fn drop(&mut self) {
        drop(self.file.take());
        let _ = std::fs::remove_file(&self.path);
    }
}
