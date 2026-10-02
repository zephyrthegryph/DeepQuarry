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

#[derive(Default)]
struct RequestedSyntax {
    records:BTreeMap<String,Vec<u8>>, missing:std::collections::BTreeSet<String>, bytes:usize,
}
pub struct ProcParseCache {
    root: Option<PathBuf>,
    entries: HashMap<String, Located>,
    readers: HashMap<PathBuf, File>,
    store: Option<dm_store::Store>,
    snapshot: std::sync::Arc<std::sync::Mutex<RequestedSyntax>>,
    pending: BTreeMap<String, Vec<u8>>,
    pending_bytes: usize,
    stats: ParseCacheStats,
    disk_ready: bool,
}
impl ProcParseCache {
    pub fn open(cache_root: Option<&Path>) -> Self {
        let root = cache_root.map(|root| {
            root.join("proc-parse-v1")
                .join(env!("DM_PROC_PARSE_FINGERPRINT"))
        });
        let mut cache = Self {
            root,
            entries: HashMap::new(),
            readers: HashMap::new(),
            store: None,
            snapshot: Default::default(),
            pending: BTreeMap::new(),
            pending_bytes: 0,
            stats: ParseCacheStats::default(),
            disk_ready: false,
        };
        let Some(root) = cache.root.as_ref() else {
            return cache;
        };
        if fs::create_dir_all(root).is_err() {
            cache.root = None;
            return cache;
        }
        if let Some(base) = cache_root {
            if let Ok(store) = dm_store::Store::open(base.join("proc-parse.redb")) {
                cache.disk_ready=store.read_many(&[dm_store::Key::new("procedure-syntax-ready",Self::namespace())],None)
                    .ok().is_some_and(|read|read.values.first().is_some_and(Option::is_some));
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
    /// Stage workers share one immutable startup snapshot, with private readers
    /// and pending writes. No database opens occur during fork.
    pub fn fork(&self) -> Self {
        Self {
            root: self.root.clone(),
            entries: self.entries.clone(),
            readers: HashMap::new(),
            store: self.store.clone(),
            snapshot: std::sync::Arc::clone(&self.snapshot),
            disk_ready:self.disk_ready,
            pending: BTreeMap::new(),
            pending_bytes: 0,
            stats: ParseCacheStats::default(),
        }
    }
    /// Requested source identities share a bounded byte cache and negative
    /// inventory across workers, without loading unrelated namespace rows.
    pub(crate) fn prefetch_keys(&self,keys:&[String]) {
        if !self.disk_ready {return;}
        let Some(store)=&self.store else {return;};
        let mut requested=self.snapshot.lock().unwrap_or_else(|error|error.into_inner());
        let keys:Vec<_>=keys.iter().filter(|key|!requested.records.contains_key(*key)&&!requested.missing.contains(*key))
            .map(|key|dm_store::Key::new(Self::namespace(),key)).collect();
        for keys in keys.chunks(4096) {
            let Ok(read)=store.read_grouped_bounded(keys,128,MAX_ENTRY as usize,8*1024*1024,64*1024*1024,None) else {continue;};
            for (key,bytes) in keys.iter().zip(read.values) {
                if let Some(bytes)=bytes {
                    while requested.bytes.saturating_add(bytes.len())>64*1024*1024 {
                        let Some(old)=requested.records.keys().next().cloned() else {break;};
                        if let Some(bytes)=requested.records.remove(&old) {requested.bytes=requested.bytes.saturating_sub(bytes.len());}
                    }
                    requested.bytes+=bytes.len();requested.records.insert(key.name.clone(),bytes);
                } else if requested.missing.len()<128_000 {requested.missing.insert(key.name.clone());}
            }
        }
    }
    pub fn parse(&mut self, source: &str, span: Span) -> Result<Item, Diagnostic> {
        if self.root.is_none() {
            return dm_syntax::parse_proc_at_span(source, span);
        }
        let raw = &source[span.range()];
        let key = format!("{:x}", Sha256::digest(raw.as_bytes()));
        let started = Instant::now();
        self.prefetch_keys(std::slice::from_ref(&key));
        let restored=self.snapshot.lock().ok().and_then(|snapshot|snapshot.records.get(&key).cloned());
        if let Some(bytes) = self.pending.get(&key).or(restored.as_ref()) {
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
        let mut changes = self
            .pending
            .iter()
            .map(|(key, bytes)| {
                dm_store::Change::Put(dm_store::Key::new(Self::namespace(), key), bytes.clone())
            })
            .collect::<Vec<_>>();
        changes.push(dm_store::Change::Put(dm_store::Key::new("procedure-syntax-ready",Self::namespace()),vec![1]));
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
    fn configured_sibling_roots_do_not_share_syntax_records() {
        let parent = root("isolation");
        let first_root = parent.join("first");
        let second_root = parent.join("second");
        let source = "/proc/test()\n    return 42\n";
        {
            let mut first = ProcParseCache::open(Some(&first_root));
            first.parse(source, Span::new(0, source.len())).unwrap();
            first.flush().unwrap();
        }
        let mut second = ProcParseCache::open(Some(&second_root));
        second.parse(source, Span::new(0, source.len())).unwrap();
        assert_eq!(second.stats().hits, 0);
        assert_eq!(second.stats().misses, 1);
        assert!(first_root.join("proc-parse.redb").is_file());
        assert!(second_root.join("proc-parse.redb").is_file());
        assert!(!parent.join("proc-parse.redb").exists());
        let mut restarted = ProcParseCache::open(Some(&first_root));
        restarted.parse(source, Span::new(0, source.len())).unwrap();
        assert_eq!(restarted.stats().hits, 1);
    }
    #[test]
    fn corrupt_transactional_syntax_is_reparsed_and_repaired() {
        let root = root("corrupt");
        let source = "/proc/test()\n    return 42\n";
        let key = format!("{:x}", Sha256::digest(source.as_bytes()));
        let mut first = ProcParseCache::open(Some(&root));
        let expected = first.parse(source, Span::new(0, source.len())).unwrap();
        first.flush().unwrap();
        first
            .store
            .as_ref()
            .unwrap()
            .put_many(
                vec![(
                    dm_store::Key::new(ProcParseCache::namespace(), &key),
                    b"torn".to_vec(),
                )],
                None,
            )
            .unwrap();
        drop(first);
        let mut cold = ProcParseCache::open(Some(&root));
        assert_eq!(
            cold.parse(source, Span::new(0, source.len())).unwrap(),
            expected
        );
        assert_eq!(cold.stats().corrupt, 1);
        assert_eq!(cold.stats().misses, 1);
        drop(cold);
        let mut repaired = ProcParseCache::open(Some(&root));
        assert_eq!(
            repaired.parse(source, Span::new(0, source.len())).unwrap(),
            expected
        );
        assert_eq!(repaired.stats().hits, 1);
        assert!(fs::read_dir(repaired.root.as_ref().unwrap())
            .unwrap()
            .all(|entry| entry
                .unwrap()
                .path()
                .extension()
                .is_none_or(|e| e != "pack" && e != "idx")));
    }
    #[test]
    fn legacy_pack_is_read_only_and_migrates_to_transactional_store() {
        let root = root("legacy");
        let source = "/proc/test()\n    return 42\n";
        let expected = dm_syntax::parse_proc_at_span(source, Span::new(0, source.len())).unwrap();
        let bytes = encode(&expected, 0).unwrap();
        let key = format!("{:x}", Sha256::digest(source.as_bytes()));
        let cache = ProcParseCache::open(Some(&root));
        let directory = cache.root.as_ref().unwrap().clone();
        let pack = directory.join("fixture.pack");
        let index = directory.join("fixture.idx");
        let metadata = serde_json::to_vec(&BTreeMap::from([(
            key,
            Entry {
                offset: 0,
                length: bytes.len() as u64,
                checksum: format!("{:x}", Sha256::digest(&bytes)),
            },
        )]))
        .unwrap();
        fs::write(&pack, &bytes).unwrap();
        fs::write(&index, &metadata).unwrap();
        drop(cache);
        let mut legacy = ProcParseCache::open(Some(&root));
        assert_eq!(
            legacy.parse(source, Span::new(0, source.len())).unwrap(),
            expected
        );
        assert_eq!(legacy.stats().hits, 1);
        drop(legacy);
        assert_eq!(fs::read(&pack).unwrap(), bytes);
        assert_eq!(fs::read(&index).unwrap(), metadata);
        fs::remove_file(pack).unwrap();
        fs::remove_file(index).unwrap();
        let mut migrated = ProcParseCache::open(Some(&root));
        assert_eq!(
            migrated.parse(source, Span::new(0, source.len())).unwrap(),
            expected
        );
        assert_eq!(migrated.stats().hits, 1);
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
    fn simultaneous_writers_commit_independent_syntax_records() {
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
