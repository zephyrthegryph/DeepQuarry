//! Bounded ordered tree streams. Hashes locate chunks; exact key bytes and the
//! current semantic issuer authorize reuse. Publication commits the manifest last.
use dm_tree::tree_reuse::{TreePublication, TreeReuseStorage};
use serde::{Deserialize, Serialize};
use std::sync::Arc;
const STAGE: u32 = 7;
const MANIFEST_VERSION: u32 = 2;
const CHUNK_VERSION: u32 = 3;
const CHUNK_BYTES: usize = 8 * 1024 * 1024;
const STREAM_BYTES: usize = 256 * 1024 * 1024;
const MAX_CHUNKS: usize = 4096;
const CHUNK_MAGIC: &[u8; 8] = b"TREECH03";
#[derive(Serialize, Deserialize)]
struct ChunkRef {
    hash: u128,
    bytes: u64,
}
#[derive(Serialize, Deserialize)]
struct Manifest {
    policy: u128,
    keys: Vec<ChunkRef>,
    payload: Vec<ChunkRef>,
}
pub struct DiskTreeMemo {
    policy: u128,
    snapshot: Arc<dm_cache::CacheSnapshot>,
    publisher: Arc<crate::lowering_memo::CachePublisher>,
}
impl DiskTreeMemo {
    pub fn new(
        policy: u128,
        snapshot: Arc<dm_cache::CacheSnapshot>,
        publisher: Arc<crate::lowering_memo::CachePublisher>,
    ) -> Self {
        Self {
            policy,
            snapshot,
            publisher,
        }
    }
    fn key(&self, key: &[Vec<u8>]) -> dm_cache::RecordKey {
        let mut hash = xxhash_rust::xxh3::Xxh3::new();
        hash.update(b"dmbc-tree-stream-v2\0");
        hash.update(&self.policy.to_le_bytes());
        hash.update(&(key.len() as u64).to_le_bytes());
        for chunk in key {
            hash.update(&(chunk.len() as u64).to_le_bytes());
            hash.update(chunk);
        }
        dm_cache::RecordKey {
            stage: STAGE,
            version: MANIFEST_VERSION,
            content: hash.digest128(),
        }
    }
    pub fn validate_payload(bytes: &[u8]) -> Result<(), String> {
        Self::validate_cache_payload(MANIFEST_VERSION, bytes)
    }
    pub fn validate_cache_payload(version: u32, bytes: &[u8]) -> Result<(), String> {
        match version {
            MANIFEST_VERSION => {
                let _: Manifest = manifest(bytes)?;
                Ok(())
            }
            CHUNK_VERSION => {
                chunk(bytes)?;
                Ok(())
            }
            _ => Err("tree cache record version differs".into()),
        }
    }
    fn read_chunk(&self, reference: &ChunkRef) -> Result<Option<Vec<u8>>, String> {
        let key = chunk_key(reference.hash);
        let record = self.snapshot.get(key, |bytes, _| {
            let payload = chunk(bytes)?;
            if payload.len() as u64 != reference.bytes
                || xxhash_rust::xxh3::xxh3_128(payload) != reference.hash
            {
                return Err("tree chunk reference differs".into());
            }
            Ok(())
        });
        // The successful get already validated framing, extent and checksum.
        Ok(record.map(|record| record.payload[32..].to_vec()))
    }
}
fn chunk_key(hash: u128) -> dm_cache::RecordKey {
    dm_cache::RecordKey {
        stage: STAGE,
        version: CHUNK_VERSION,
        content: hash,
    }
}
fn refs(chunks: &[Vec<u8>]) -> Vec<ChunkRef> {
    chunks
        .iter()
        .map(|bytes| ChunkRef {
            hash: xxhash_rust::xxh3::xxh3_128(bytes),
            bytes: bytes.len() as u64,
        })
        .collect()
}
fn valid_refs(rows: &[ChunkRef]) -> Result<(), String> {
    if rows.is_empty() || rows.len() > MAX_CHUNKS {
        return Err("tree stream chunk count exceeds bound".into());
    }
    let mut total = 0u64;
    for row in rows {
        if row.bytes == 0 || row.bytes > CHUNK_BYTES as u64 {
            return Err("tree chunk extent exceeds bound".into());
        }
        total = total
            .checked_add(row.bytes)
            .ok_or("tree stream extent overflow")?;
    }
    if total > STREAM_BYTES as u64 {
        return Err("tree stream extent exceeds bound".into());
    }
    Ok(())
}
fn manifest(bytes: &[u8]) -> Result<Manifest, String> {
    if bytes.len() > CHUNK_BYTES {
        return Err("tree manifest exceeds bound".into());
    }
    let value: Manifest = dm_wire::decode(2, bytes, CHUNK_BYTES)?;
    valid_refs(&value.keys)?;
    valid_refs(&value.payload)?;
    Ok(value)
}
fn chunk(bytes: &[u8]) -> Result<&[u8], String> {
    if bytes.len() < 32
        || bytes.len() > CHUNK_BYTES + 32
        || bytes.get(..8) != Some(CHUNK_MAGIC.as_slice())
    {
        return Err("tree chunk framing differs".into());
    }
    let length = u64::from_le_bytes(bytes[8..16].try_into().unwrap());
    let payload = &bytes[32..];
    if length != payload.len() as u64
        || payload.is_empty()
        || u128::from_le_bytes(bytes[16..32].try_into().unwrap())
            != xxhash_rust::xxh3::xxh3_128(payload)
    {
        return Err("tree chunk extent/checksum differs".into());
    }
    Ok(payload)
}
fn framed_chunk(payload: &[u8]) -> Result<Vec<u8>, String> {
    if payload.is_empty() || payload.len() > CHUNK_BYTES {
        return Err("tree chunk exceeds bound".into());
    }
    let mut bytes = Vec::with_capacity(32 + payload.len());
    bytes.extend_from_slice(CHUNK_MAGIC);
    bytes.extend_from_slice(&(payload.len() as u64).to_le_bytes());
    bytes.extend_from_slice(&xxhash_rust::xxh3::xxh3_128(payload).to_le_bytes());
    bytes.extend_from_slice(payload);
    Ok(bytes)
}
impl TreeReuseStorage for DiskTreeMemo {
    fn load(
        &self,
        exact_key: &[Vec<u8>],
        admit: &mut dyn FnMut(&[Vec<u8>]) -> Result<(), String>,
    ) -> Result<bool, String> {
        let admitted = std::cell::Cell::new(false);
        let admit = std::cell::RefCell::new(admit);
        let record = self.snapshot.get(self.key(exact_key), |bytes, _| {
            let manifest = manifest(bytes)?;
            if manifest.policy != self.policy || manifest.keys.len() != exact_key.len() {
                return Err("tree stream exact key differs".into());
            }
            for (reference, current) in manifest.keys.iter().zip(exact_key) {
                let stored = self
                    .read_chunk(reference)?
                    .ok_or("tree key chunk unavailable")?;
                if stored != *current {
                    return Err("tree stream exact key differs".into());
                }
            }
            let mut payload = Vec::with_capacity(manifest.payload.len());
            for reference in &manifest.payload {
                payload.push(
                    self.read_chunk(reference)?
                        .ok_or("tree payload chunk unavailable")?,
                );
            }
            (admit.borrow_mut())(&payload)?;
            admitted.set(true);
            Ok(())
        });
        Ok(record.is_some() && admitted.get())
    }
    fn publish(
        &self,
        exact_key: &[Vec<u8>],
        payload: Vec<Vec<u8>>,
    ) -> Result<TreePublication, String> {
        let manifest = Manifest {
            policy: self.policy,
            keys: refs(exact_key),
            payload: refs(&payload),
        };
        valid_refs(&manifest.keys)?;
        valid_refs(&manifest.payload)?;
        let size = dm_wire::encoded_len(2, &manifest)?;
        if size > CHUNK_BYTES {
            return Ok(TreePublication {
                envelope_bytes: size as u64,
                envelope_oversize: true,
            });
        }
        // One bounded chunk per callback. The shared sink batches bounded segments.
        // Orphan chunks after failure are harmless; no manifest authorizes them.
        for bytes in exact_key.iter().chain(payload.iter()) {
            let hash = xxhash_rust::xxh3::xxh3_128(bytes);
            (self.publisher)(vec![dm_cache::Record {
                key: chunk_key(hash),
                symbols: Vec::new(),
                payload: framed_chunk(bytes)?.into(),
            }])?;
        }
        (self.publisher)(vec![dm_cache::Record {
            key: self.key(exact_key),
            symbols: Vec::new(),
            payload: dm_wire::encode(2, &manifest)?.into(),
        }])?;
        Ok(TreePublication {
            envelope_bytes: size as u64,
            envelope_oversize: false,
        })
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn tree_disk_envelope_checks_exact_bounds_and_truncated_lengths() {
        assert!(DiskTreeMemo::validate_cache_payload(2, &[]).is_err());
        assert!(DiskTreeMemo::validate_cache_payload(3, &[]).is_err());
        let good = framed_chunk(b"payload").unwrap();
        assert_eq!(chunk(&good).unwrap(), b"payload");
        let mut corrupt = good.clone();
        *corrupt.last_mut().unwrap() ^= 1;
        assert!(chunk(&corrupt).is_err());
        assert!(chunk(&good[..31]).is_err());
        let bad = Manifest {
            policy: 1,
            keys: vec![ChunkRef {
                hash: 1,
                bytes: STREAM_BYTES as u64,
            }],
            payload: vec![ChunkRef { hash: 2, bytes: 1 }],
        };
        assert!(DiskTreeMemo::validate_payload(&dm_wire::encode(2, &bad).unwrap()).is_err());
    }
    #[test]
    fn tree_disk_key_is_policy_and_exact_input_scoped() {
        let path = std::env::temp_dir().join(format!("dmbc-tree-key-{}", std::process::id()));
        let cache = dm_cache::Cache::open(path, dm_cache::Limits::default()).unwrap();
        let snapshot = Arc::new(cache.snapshot().unwrap());
        let publisher: Arc<crate::lowering_memo::CachePublisher> = Arc::new(|_| Ok(()));
        let first = DiskTreeMemo::new(1, snapshot.clone(), publisher.clone());
        let other = DiskTreeMemo::new(2, snapshot, publisher);
        assert_ne!(
            first.key(&[b"input".to_vec()]),
            other.key(&[b"input".to_vec()])
        );
        assert_ne!(
            first.key(&[b"input".to_vec()]),
            first.key(&[b"inputs".to_vec()])
        );
        assert_ne!(
            first.key(&[b"a".to_vec(), b"bc".to_vec()]),
            first.key(&[b"ab".to_vec(), b"c".to_vec()])
        );
    }
    #[test]
    fn tree_chunk_manifest_replays_once_and_records_all_accessed_roots() {
        let path = std::env::temp_dir().join(format!("dmbc-tree-stream-{}", std::process::id()));
        let cache = Arc::new(dm_cache::Cache::open(path, dm_cache::Limits::default()).unwrap());
        let sink = cache.clone();
        let publisher: Arc<crate::lowering_memo::CachePublisher> = Arc::new(move |records| {
            sink.publish(&records)
                .map(|_| ())
                .map_err(|error| error.to_string())
        });
        let writer = DiskTreeMemo::new(17, Arc::new(cache.snapshot().unwrap()), publisher.clone());
        let key = vec![b"first-exact-key".to_vec(), b"second-exact-key".to_vec()];
        let payload = vec![
            b"first-tree-section".to_vec(),
            b"second-tree-section".to_vec(),
        ];
        let report = writer.publish(&key, payload.clone()).unwrap();
        assert!(!report.envelope_oversize);
        let snapshot = Arc::new(cache.snapshot().unwrap());
        let reader = DiskTreeMemo::new(17, snapshot.clone(), publisher);
        let mut calls = 0;
        assert!(reader
            .load(&key, &mut |stored| {
                calls += 1;
                assert_eq!(stored, payload.as_slice());
                Ok(())
            })
            .unwrap());
        assert_eq!(calls, 1);
        assert_eq!(snapshot.record_used_keys().len(), 5);
        let changed = vec![b"different-exact-key".to_vec()];
        assert!(!reader
            .load(&changed, &mut |_| panic!("wrong key admitted"))
            .unwrap());
    }
}
