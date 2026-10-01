//! Bounded immutable packs of relative procedure syntax, shared across worktrees.
use dm_syntax::{Diagnostic, Item, ItemKind, Span};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::collections::{BTreeMap, HashMap};
use std::fs::{self, File, OpenOptions};
use std::io::{Read, Seek, SeekFrom, Write};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

const MAX_ENTRY: u64 = 2 * 1024 * 1024;
const MAX_PACK: u64 = 256 * 1024 * 1024;
const MAX_NODES: usize = 100_000;
const MAX_INDEX: u64 = 16 * 1024 * 1024;
const MAX_SEGMENTS: usize = 32;
static SEGMENT_SEQUENCE: AtomicU64 = AtomicU64::new(0);

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
    writer: Option<(PathBuf, File, u64)>,
    published: BTreeMap<String, Entry>,
    stats: ParseCacheStats,
}
impl ProcParseCache {
    pub fn open(lower_root: Option<&Path>) -> Self {
        let root = lower_root.and_then(Path::parent).map(|root| {
            root.join("proc-parse-v1")
                .join(env!("DM_LOWERING_FINGERPRINT"))
        });
        let mut cache = Self {
            root,
            entries: HashMap::new(),
            readers: HashMap::new(),
            writer: None,
            published: BTreeMap::new(),
            stats: ParseCacheStats::default(),
        };
        let Some(root) = cache.root.as_ref() else {
            return cache;
        };
        if fs::create_dir_all(root).is_err() {
            cache.root = None;
            return cache;
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
        if bytes.len() as u64 > MAX_ENTRY || self.published.len() >= MAX_NODES {
            return;
        }
        let Some(root) = self.root.as_ref() else {
            return;
        };
        if self.writer.is_none() {
            let nonce = SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap_or_default()
                .as_nanos();
            let sequence = SEGMENT_SEQUENCE.fetch_add(1, Ordering::Relaxed);
            let path = root.join(format!(
                "{nonce:040}-{}-{sequence}.pack",
                std::process::id()
            ));
            let Ok(file) = OpenOptions::new().write(true).create_new(true).open(&path) else {
                return;
            };
            self.writer = Some((path, file, 0));
        }
        let (pack, file, size) = self.writer.as_mut().unwrap();
        if *size + bytes.len() as u64 > MAX_PACK {
            return;
        }
        let entry = Entry {
            offset: *size,
            length: bytes.len() as u64,
            checksum: format!("{:x}", Sha256::digest(&bytes)),
        };
        if file.write_all(&bytes).is_err() {
            return;
        }
        *size += entry.length;
        self.entries.insert(
            key.clone(),
            Located {
                pack: pack.clone(),
                entry: entry.clone(),
            },
        );
        self.published.insert(key, entry);
    }
}
impl Drop for ProcParseCache {
    fn drop(&mut self) {
        let Some((pack, mut file, _)) = self.writer.take() else {
            return;
        };
        if self.published.is_empty() || file.flush().is_err() {
            return;
        }
        drop(file);
        let Ok(bytes) = serde_json::to_vec(&self.published) else {
            return;
        };
        if bytes.len() as u64 > MAX_INDEX {
            return;
        }
        let temporary = pack.with_extension("idx.tmp");
        // Every writer publishes a unique immutable segment. Readers never see
        // its index before the completed pack; writers cannot clobber each other.
        if fs::write(&temporary, bytes).is_ok()
            && fs::rename(temporary, pack.with_extension("idx")).is_ok()
        {
            let Some(root) = self.root.as_ref() else {
                return;
            };
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
                .map(|entry| entry.path())
                .collect();
            indices.sort();
            let mut total = 0u64;
            for (ordinal, index) in indices.into_iter().rev().enumerate() {
                let pack = index.with_extension("pack");
                let size = fs::metadata(&pack).map_or(0, |metadata| metadata.len());
                total = total.saturating_add(size);
                if total > MAX_PACK || ordinal >= MAX_SEGMENTS {
                    let _ = fs::remove_file(index);
                    let _ = fs::remove_file(pack);
                }
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
