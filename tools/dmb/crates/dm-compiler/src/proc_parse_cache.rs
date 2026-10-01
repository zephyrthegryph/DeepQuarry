//! Bounded transactional procedure syntax, with read-only legacy pack migration.
use dm_syntax::{Diagnostic, Item, ItemKind, Span};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::collections::{BTreeMap, HashMap};
use std::fs::{self, File};
use std::io::{Read, Seek, SeekFrom};
use std::path::{Path, PathBuf};
use std::time::{Duration, Instant};
#[cfg(test)]
use std::time::{SystemTime, UNIX_EPOCH};

const MAX_ENTRY: u64 = 2 * 1024 * 1024;
const MAX_PACK: u64 = 256 * 1024 * 1024;
const MAX_NODES: usize = 100_000;
const MAX_INDEX: u64 = 16 * 1024 * 1024;
const MAX_SEGMENTS: usize = 32;
const MAX_PENDING: usize = 16 * 1024 * 1024;

#[derive(Clone, Debug, Serialize, Deserialize)]
struct Entry {
    offset: u64,
    length: u64,
    checksum: String,
}
#[derive(Serialize, Deserialize)]
struct Node {
    kind: u8,
    header: String,
    spans: [usize; 4],
    indent: usize,
    children: Vec<usize>,
}
#[derive(Clone)]
struct Located {
    pack: PathBuf,
    entry: Entry,
}
#[derive(Default, Clone, Copy, Debug)]
pub struct ParseCacheStats {
    pub hits: u64,
    pub misses: u64,
    pub corrupt: u64,
    pub read_time: Duration,
    pub parse_time: Duration,
}

pub struct ProcParseCache {
    root: Option<PathBuf>,
    entries: HashMap<String, Located>,
    readers: HashMap<PathBuf, File>,
    store: Option<dm_store::Store>,
    snapshot: BTreeMap<String, Vec<u8>>,
    pending: BTreeMap<String, Vec<u8>>,
    pending_bytes: usize,
    stats: ParseCacheStats,
}
impl ProcParseCache {
    pub fn open(lower_root: Option<&Path>) -> Self {
        let root = lower_root.and_then(Path::parent).map(|root| {
            root.join("proc-parse-v1")
                .join(env!("DM_PROC_PARSE_FINGERPRINT"))
        });
        let mut cache = Self {
            root,
            entries: HashMap::new(),
            readers: HashMap::new(),
            store: None,
            snapshot: BTreeMap::new(),
            pending: BTreeMap::new(),
            pending_bytes: 0,
            stats: ParseCacheStats::default(),
        };
        let Some(root) = cache.root.as_ref() else {
            return cache;
        };
        if fs::create_dir_all(root).is_err() {
            cache.root = None;
            return cache;
        }
        if let Some(base) = lower_root.and_then(Path::parent) {
            if let Ok(store) = dm_store::Store::open(base.join("proc-parse.redb")) {
                let started = Instant::now();
                match store.snapshot_namespace(&Self::namespace(), 64_000, 128 * 1024 * 1024, None)
                {
                    Ok(snapshot) => {
                        if std::env::var_os("DM_BUILD_TRACE").is_some() {
                            let bytes = snapshot
                                .records
                                .iter()
                                .map(|(key, value)| key.name.len() + value.len())
                                .sum::<usize>();
                            eprintln!("DM_BUILD_TRACE parser store snapshot: {} entries, {} bytes, complete {}, {:.3}s", snapshot.records.len(), bytes, snapshot.complete, started.elapsed().as_secs_f64());
                        }
                        cache.snapshot = snapshot
                            .records
                            .into_iter()
                            .map(|(key, bytes)| (key.name, bytes))
                            .collect();
                    }
                    Err(_) => cache.stats.corrupt += 1,
                }
                cache.store = Some(store);
            }
        }
        let mut indices: Vec<_> = fs::read_dir(root)
            .into_iter()
            .flatten()
            .filter_map(Result::ok)
            .filter(|entry| {
                entry
                    .path()
                    .extension()
                    .is_some_and(|extension| extension == "idx")
            })
            .take(256)
            .map(|entry| entry.path())
            .collect();
        indices.sort();
        let mut budget = MAX_PACK;
        for index in indices.into_iter().rev().take(MAX_SEGMENTS) {
            if cache.entries.len() >= MAX_NODES {
                break;
            }
            let pack = index.with_extension("pack");
            let Ok(size) = fs::metadata(&pack).map(|metadata| metadata.len()) else {
                continue;
            };
            if size > budget
                || fs::metadata(&index).map_or(true, |metadata| metadata.len() > MAX_INDEX)
            {
                continue;
            }
            let Ok(bytes) = fs::read(&index) else {
                continue;
            };
            let Ok(records) = serde_json::from_slice::<BTreeMap<String, Entry>>(&bytes) else {
                continue;
            };
            if records.len() > MAX_NODES {
                continue;
            }
            budget -= size;
            for (key, entry) in records {
                if cache.entries.len() >= MAX_NODES {
                    break;
                }
                if entry.length <= MAX_ENTRY
                    && entry
                        .offset
                        .checked_add(entry.length)
                        .is_some_and(|end| end <= size)
                {
                    cache.entries.entry(key).or_insert_with(|| Located {
                        pack: pack.clone(),
                        entry,
                    });
                }
            }
        }
        cache
    }
    fn namespace() -> String {
        format!("procedure-syntax-v1-{}", env!("DM_PROC_PARSE_FINGERPRINT"))
    }
    pub fn stats(&self) -> ParseCacheStats {
        self.stats
    }
    pub fn parse(&mut self, source: &str, span: Span) -> Result<Item, Diagnostic> {
        if self.root.is_none() {
            return dm_syntax::parse_proc_at_span(source, span);
        }
        let raw = &source[span.range()];
        let key = format!("{:x}", Sha256::digest(raw.as_bytes()));
        let started = Instant::now();
        if let Some(bytes) = self.pending.get(&key).or_else(|| self.snapshot.get(&key)) {
            let result = decode(bytes, span.start, raw.len());
            self.stats.read_time += started.elapsed();
            if let Some(item) = result {
                self.stats.hits += 1;
                return Ok(item);
            }
            self.stats.corrupt += 1;
        }
        if let Some(located) = self.entries.get(&key).cloned() {
            let result = (|| {
                if !self.readers.contains_key(&located.pack) {
                    self.readers
                        .insert(located.pack.clone(), File::open(&located.pack).ok()?);
                }
                let file = self.readers.get_mut(&located.pack)?;
                file.seek(SeekFrom::Start(located.entry.offset)).ok()?;
                let mut bytes = vec![0; located.entry.length as usize];
                file.read_exact(&mut bytes).ok()?;
                if format!("{:x}", Sha256::digest(&bytes)) != located.entry.checksum {
                    return None;
                }
                decode(&bytes, span.start, raw.len())
            })();
            self.stats.read_time += started.elapsed();
            if let Some(item) = result {
                if let Some(bytes) = encode(&item, span.start) {
                    self.store(key.clone(), bytes);
                }
                self.stats.hits += 1;
                return Ok(item);
            }
            self.stats.corrupt += 1;
        }
        self.stats.misses += 1;
        let started = Instant::now();
        let item = dm_syntax::parse_proc_at_span(source, span)?;
        self.stats.parse_time += started.elapsed();
        if let Some(bytes) = encode(&item, span.start) {
            self.store(key, bytes);
        }
        Ok(item)
    }
    fn store(&mut self, key: String, bytes: Vec<u8>) {
        if self.store.is_none() || bytes.len() as u64 > MAX_ENTRY {
            return;
        }
        let old = self.pending.get(&key).map_or(0, Vec::len);
        if self
            .pending_bytes
            .saturating_sub(old)
            .saturating_add(bytes.len())
            > MAX_PENDING
            || self.pending.len() >= 64_000
        {
            if self.flush().is_err() {
                return;
            }
        }
        let len = bytes.len();
        if let Some(old) = self.pending.insert(key, bytes) {
            self.pending_bytes -= old.len();
        }
        self.pending_bytes += len;
    }
    fn flush(&mut self) -> std::io::Result<()> {
        if self.pending.is_empty() {
            return Ok(());
        }
        let Some(store) = &self.store else {
            return Ok(());
        };
        let changes = self
            .pending
            .iter()
            .map(|(key, bytes)| {
                dm_store::Change::Put(dm_store::Key::new(Self::namespace(), key), bytes.clone())
            })
            .collect::<Vec<_>>();
        match store.commit(&[], &changes, None)? {
            dm_store::Commit::Applied => {
                self.pending.clear();
                self.pending_bytes = 0;
                Ok(())
            }
            dm_store::Commit::Conflict => Err(std::io::Error::other(
                "unexpected unwitnessed parser cache conflict",
            )),
        }
    }
}
impl Drop for ProcParseCache {
    fn drop(&mut self) {
        if let Err(error) = self.flush() {
            if std::env::var_os("DM_BUILD_TRACE").is_some() {
                eprintln!("DM_BUILD_TRACE parser store flush: {error}");
            }
        }
    }
}
fn encode(item: &Item, base: usize) -> Option<Vec<u8>> {
    let mut nodes = Vec::new();
    let mut pending = vec![(item, None)];
    while let Some((item, parent)) = pending.pop() {
        if nodes.len() >= MAX_NODES {
            return None;
        }
        let index = nodes.len();
        if let Some(parent) = parent {
            let node: &mut Node = &mut nodes[parent];
            node.children.push(index);
        }
        let kind = match item.kind {
            ItemKind::Type => 0,
            ItemKind::Proc => 1,
            ItemKind::Verb => 2,
            ItemKind::Var => 3,
            ItemKind::Statement => 4,
            ItemKind::Unknown => 5,
        };
        nodes.push(Node {
            kind,
            header: item.header.clone(),
            spans: [
                item.span.start.checked_sub(base)?,
                item.span.end.checked_sub(base)?,
                item.header_span.start.checked_sub(base)?,
                item.header_span.end.checked_sub(base)?,
            ],
            indent: item.indent,
            children: Vec::new(),
        });
        pending.extend(item.children.iter().rev().map(|child| (child, Some(index))));
    }
    serde_json::to_vec(&nodes).ok()
}
fn decode(bytes: &[u8], base: usize, length: usize) -> Option<Item> {
    let nodes: Vec<Node> = serde_json::from_slice(bytes).ok()?;
    if nodes.is_empty() || nodes.len() > MAX_NODES {
        return None;
    }
    let mut items: Vec<Option<Item>> = (0..nodes.len()).map(|_| None).collect();
    for (index, node) in nodes.into_iter().enumerate().rev() {
        let [start, end, header_start, header_end] = node.spans;
        if start > end
            || end > length
            || header_start < start
            || header_end > end
            || header_start > header_end
        {
            return None;
        }
        let children = node
            .children
            .into_iter()
            .map(|child| {
                if child <= index {
                    return None;
                }
                items.get_mut(child)?.take()
            })
            .collect::<Option<Vec<_>>>()?;
        let kind = match node.kind {
            0 => ItemKind::Type,
            1 => ItemKind::Proc,
            2 => ItemKind::Verb,
            3 => ItemKind::Var,
            4 => ItemKind::Statement,
            5 => ItemKind::Unknown,
            _ => return None,
        };
        items[index] = Some(Item {
            kind,
            header: node.header,
            span: Span::new(base.checked_add(start)?, base.checked_add(end)?),
            header_span: Span::new(
                base.checked_add(header_start)?,
                base.checked_add(header_end)?,
            ),
            indent: node.indent,
            children,
        });
    }
    items[0].take()
}

#[cfg(test)]
mod tests {
    use super::*;
    fn root(name: &str) -> PathBuf {
        let nonce = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        std::env::temp_dir()
            .join(format!("dm-parse-cache-{name}-{nonce}"))
            .join("lower")
    }
    #[test]
    fn persisted_cache_relocates_across_worktree_source_offsets() {
        let root = root("relocate");
        let proc = "/proc/test()\n    return 42\n";
        let mut cache = ProcParseCache::open(Some(&root));
        let expected = cache.parse(proc, Span::new(0, proc.len())).unwrap();
        drop(cache);
        let shifted = format!("// worktree include changed\n{proc}");
        let start = shifted.len() - proc.len();
        let mut cache = ProcParseCache::open(Some(&root));
        let actual = cache
            .parse(&shifted, Span::new(start, shifted.len()))
            .unwrap();
        assert_eq!(cache.stats().hits, 1);
        assert_eq!(actual.header, expected.header);
        assert_eq!(
            actual.children[0].span.start,
            expected.children[0].span.start + start
        );
        assert_eq!(
            actual,
            dm_syntax::parse_proc_at_span(&shifted, Span::new(start, shifted.len())).unwrap()
        );
    }
    #[test]
    fn truncated_pack_falls_back_to_parser() {
        let root = root("truncated");
        let proc = "/proc/test()\n    return 42\n";
        let mut cache = ProcParseCache::open(Some(&root));
        cache.parse(proc, Span::new(0, proc.len())).unwrap();
        drop(cache);
        let mut cache = ProcParseCache::open(Some(&root));
        let pack = cache.entries.values().next().unwrap().pack.clone();
        fs::write(pack, b"torn").unwrap();
        assert!(cache.parse(proc, Span::new(0, proc.len())).is_ok());
        assert_eq!(cache.stats().corrupt, 1);
        assert_eq!(cache.stats().misses, 1);
    }

    #[test]
    fn external_header_indentation_matches_direct_slice_parser() {
        let root = root("indent");
        let proc = "proc/test()\n        return 42\n";
        let mut cache = ProcParseCache::open(Some(&root));
        cache.parse(proc, Span::new(0, proc.len())).unwrap();
        drop(cache);
        let source = format!("/datum/holder\n    {proc}");
        let span = Span::new(source.len() - proc.len(), source.len());
        let mut cache = ProcParseCache::open(Some(&root));
        assert_eq!(
            cache.parse(&source, span).unwrap(),
            dm_syntax::parse_proc_at_span(&source, span).unwrap()
        );
        assert_eq!(cache.stats().hits, 1);
    }
    #[test]
    fn simultaneous_writers_publish_independent_immutable_segments() {
        let root = root("writers");
        let a = "/proc/a()\n    return 1\n";
        let b = "/proc/b()\n    return 2\n";
        let barrier = std::sync::Arc::new(std::sync::Barrier::new(2));
        let writers: Vec<_> = [a, b]
            .into_iter()
            .map(|source| {
                let root = root.clone();
                let barrier = barrier.clone();
                std::thread::spawn(move || {
                    let mut writer = ProcParseCache::open(Some(&root));
                    writer.parse(source, Span::new(0, source.len())).unwrap();
                    barrier.wait();
                    drop(writer);
                })
            })
            .collect();
        for writer in writers {
            writer.join().unwrap();
        }
        let mut reader = ProcParseCache::open(Some(&root));
        reader.parse(a, Span::new(0, a.len())).unwrap();
        reader.parse(b, Span::new(0, b.len())).unwrap();
        assert_eq!(reader.stats().hits, 2);
    }
}
