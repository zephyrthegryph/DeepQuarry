//! Immutable asset entries compose deterministic archives without retaining
//! payloads. The physical entry store grows by new content; each generation
//! contains only its active entries in canonical source order.
use super::*;
use dm_host::file_stamp::{capture, FileStamp};
use dm_store::{Change, Key, Store};
use std::io::{BufReader, BufWriter, Read, Write};
use std::sync::atomic::{AtomicU64, Ordering};
static TEMP: AtomicU64 = AtomicU64::new(0);

#[derive(Clone, Debug)]
pub struct PreparedArchive {
    path: PathBuf,
    digest: String,
    len: u64,
    stamp: FileStamp,
    catalog: ResourceCatalog,
    receipt_store: Store,
    receipt_key: Key,
}
impl PreparedArchive {
    pub fn path(&self) -> &Path {
        &self.path
    }
    pub fn digest(&self) -> &str {
        &self.digest
    }
    pub fn len(&self) -> u64 {
        self.len
    }
    pub fn is_empty(&self) -> bool {
        self.len == 0
    }
    pub fn stamp(&self) -> &FileStamp {
        &self.stamp
    }
    pub fn catalog(&self) -> &ResourceCatalog {
        &self.catalog
    }
}
/// A Windows kernel-enforced denial of writes to the archive file identity.
/// The receipt can be refreshed only while this guard excludes content writes.
#[derive(Debug)]
pub struct ArchiveLease {
    file: std::fs::File, path: PathBuf, digest:String, len:u64,
    store:Store, key:Key,
}
impl PreparedArchive {
    pub fn guarded_lease(&self)->io::Result<Option<std::sync::Arc<ArchiveLease>>> {
        #[cfg(windows)] {
            use std::os::windows::fs::OpenOptionsExt;
            // Allow readers and link metadata operations, deny existing/new
            // write handles through every hardlink to this file identity.
            let file=std::fs::OpenOptions::new().read(true).share_mode(1|4).open(&self.path)?;
            if dm_host::file_stamp::capture_file(&file).as_ref()!=Some(&self.stamp) {
                return Err(io::Error::other("archive changed before guarded publication"));
            }
            Ok(Some(std::sync::Arc::new(ArchiveLease{file,path:self.path.clone(),digest:self.digest.clone(),len:self.len,store:self.receipt_store.clone(),key:self.receipt_key.clone()})))
        }
        #[cfg(not(windows))] {Ok(None)}
    }
}
impl ArchiveLease {
    pub fn current_stamp(&self)->Option<FileStamp> {dm_host::file_stamp::capture_file(&self.file)}
    /// Refresh only our immutable source's receipt after metadata mutation.
    /// A replaced path must still refer to the protected file identity.
    pub fn refresh_after_publication(&self)->io::Result<()> {
        #[cfg(windows)] {
            use std::os::windows::fs::OpenOptionsExt;
            let current=self.current_stamp().ok_or_else(||io::Error::other("guarded archive stamp unavailable"))?;
            let path_file=std::fs::OpenOptions::new().read(true).share_mode(1|4).open(&self.path)?;
            if dm_host::file_stamp::capture_file(&path_file).as_ref()!=Some(&current) || path_file.metadata()?.len()!=self.len {
                return Err(io::Error::other("guarded archive path replaced"));
            }
            let record=ArchiveRecord{digest:self.digest.clone(),len:self.len,stamp:current};
            self.store.commit(&[],&[Change::Put(self.key.clone(),serde_json::to_vec(&record).map_err(io::Error::other)?)],None)?;
        }
        Ok(())
    }
}

#[derive(Clone, Serialize, Deserialize)]
struct EntryRecord {
    digest: String,
    len: u64,
    stamp: FileStamp,
}
#[derive(Serialize, Deserialize)]
struct ArchiveRecord {
    digest: String,
    len: u64,
    stamp: FileStamp,
}
struct EntryFile {
    path: PathBuf,
    record: EntryRecord,
    key: Key,
    fresh: bool,
}
struct Temporary(PathBuf);
impl Drop for Temporary {
    fn drop(&mut self) {
        let _ = fs::remove_file(&self.0);
    }
}
fn temporary(path: &Path) -> Temporary {
    Temporary(path.with_extension(format!(
        "{}.{}.tmp",
        std::process::id(),
        TEMP.fetch_add(1, Ordering::Relaxed)
    )))
}
fn identical(path: &Path, expected: &str, length: u64) -> io::Result<bool> {
        let mut reader = fs::File::open(path)?;
        if reader.metadata()?.len() != length {
            return Ok(false);
        }
        let mut hash = Sha256::new();
        let mut buffer = [0u8; 64 * 1024];
        loop {
            let n = reader.read(&mut buffer)?;
            if n == 0 {
                break;
            }
            hash.update(&buffer[..n]);
        }
        Ok(format!("{:x}", hash.finalize()) == expected)
    }

// Concurrent worktrees publish immutable objects under the same digest. Keep
// an existing valid inode rather than replacing it and invalidating receipts.
fn promote(tmp: &Temporary, destination: &Path, digest: &str, length: u64) -> io::Result<()> {
    if destination.exists() && identical(destination, digest, length)? {
        return Ok(());
    }
    match fs::rename(&tmp.0, destination) {
        Ok(()) => Ok(()),
        Err(_) if destination.exists() && identical(destination, digest, length)? => Ok(()),
        Err(error) => Err(error),
    }
}
fn entry_identity(entry: &ResourceDescriptor) -> String {
    let mut hash = Sha256::new();
    hash.update(b"dm-resource-entry-v1\0");
    hash.update((entry.archive_name.len() as u64).to_le_bytes());
    hash.update(entry.archive_name.as_bytes());
    hash.update([entry.kind]);
    hash.update(entry.content_digest);
    format!("{:x}", hash.finalize())
}
fn entry_file(root: &Path, identity: &str) -> PathBuf {
    root.join("resource-entries-v1")
        .join(&identity[..2])
        .join(identity)
}
fn prepare_entry(
    root: &Path,
    input: &(ResourceRequest, u64, Option<FileStamp>),
    entry: &ResourceDescriptor,
    cached: Option<&EntryRecord>,
) -> io::Result<EntryFile> {
    let identity = entry_identity(entry);
    let key = Key::new("resource-entry-v1", &identity);
    let path = entry_file(root, &identity);
    if let Some(record) = cached.filter(|record| capture(&path).as_ref() == Some(&record.stamp)) {
        return Ok(EntryFile {
            path,
            record: record.clone(),
            key,
            fresh: false,
        });
    }
    fs::create_dir_all(path.parent().unwrap())?;
    let tmp = temporary(&path);
    let file = fs::OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(&tmp.0)?;
    let mut writer = BufWriter::with_capacity(64 * 1024, file);
    let size = u32::try_from(input.1).map_err(|_| invalid("resource exceeds u32"))?;
    let length = size
        .checked_add(18)
        .and_then(|size| size.checked_add(u32::try_from(entry.archive_name.len()).ok()?))
        .ok_or_else(|| invalid("resource entry size overflow"))?;
    let mut header = Vec::with_capacity(23 + entry.archive_name.len());
    header.extend_from_slice(&length.to_le_bytes());
    header.push(1);
    header.push(entry.kind);
    header.extend_from_slice(&entry.id.to_le_bytes());
    header.extend_from_slice(&0u32.to_le_bytes());
    header.extend_from_slice(&0u32.to_le_bytes());
    header.extend_from_slice(&size.to_le_bytes());
    header.extend_from_slice(entry.archive_name.as_bytes());
    header.push(0);
    writer.write_all(&header)?;
    let mut entry_hash = Sha256::new();
    entry_hash.update(&header);
    let before = capture(&input.0.disk_path);
    if input
        .2
        .as_ref()
        .is_some_and(|expected| before.as_ref() != Some(expected))
    {
        return Err(io::Error::other(
            "resource changed before entry construction",
        ));
    }
    let mut reader = BufReader::with_capacity(64 * 1024, fs::File::open(&input.0.disk_path)?);
    let mut buffer = [0u8; 64 * 1024];
    let mut count = 0u64;
    let mut content = Sha256::new();
    let mut id = u32::MAX;
    loop {
        let n = reader.read(&mut buffer)?;
        if n == 0 {
            break;
        }
        count = count
            .checked_add(n as u64)
            .ok_or_else(|| invalid("resource length overflow"))?;
        if count > input.1 {
            return Err(io::Error::other("resource grew during entry construction"));
        }
        let bytes = &buffer[..n];
        content.update(bytes);
        entry_hash.update(bytes);
        id = byond_dmb::hash::nqcrc(id, bytes);
        writer.write_all(bytes)?;
    }
    drop(reader);
    if count != input.1
        || id != entry.id
        || <[u8; 32]>::from(content.finalize()) != entry.content_digest
        || before
            .as_ref()
            .is_some_and(|expected| capture(&input.0.disk_path).as_ref() != Some(expected))
    {
        return Err(io::Error::other(
            "resource changed during entry construction",
        ));
    }
    writer.flush()?;
    // Entry nodes are disposable cache data. The composed archive below is
    // synced once before its verified receipt is published.
    drop(writer);
    let digest = format!("{:x}", entry_hash.finalize());
    let entry_len = header.len() as u64 + count;
    promote(&tmp, &path, &digest, entry_len)?;
    let stamp = capture(&path)
        .ok_or_else(|| io::Error::other("resource entry strong stamp unavailable"))?;
    Ok(EntryFile {
        path,
        key,
        fresh: true,
        record: EntryRecord {
            digest,
            len: entry_len,
            stamp,
        },
    })
}

/// Prepare a payload-free catalog and verified archive. Unchanged archives
/// return through a strong stamp proof. An asset edit creates only missing
/// immutable entries, then streams the active entry sequence through 64KiB.
pub fn prepare_archive(root: &Path, requests: &[ResourceRequest]) -> io::Result<PreparedArchive> {
    let started = std::time::Instant::now();
    let (catalog, inputs) = ResourceFingerprintCache::open(root).archive_inputs(requests)?;
    if std::env::var_os("DM_BUILD_TRACE").is_some() {eprintln!("DM_BUILD_TRACE archive fingerprint inputs: {} requests, {:.3}s",requests.len(),started.elapsed().as_secs_f64());}
    let lookup_started=std::time::Instant::now();
    let identity = catalog
        .fingerprint
        .iter()
        .map(|byte| format!("{byte:02x}"))
        .collect::<String>();
    let store = Store::open(root.join("resource-archives.redb"))?;
    let archive_key = Key::new("resource-archive-v1", &identity);
    let staging_path = root
        .join("resource-archives-v1")
        .join(format!("{identity}.rsc"));
    let cached = store
        .read_many(std::slice::from_ref(&archive_key), None)?
        .values
        .into_iter()
        .next()
        .flatten()
        .and_then(|bytes| serde_json::from_slice::<ArchiveRecord>(&bytes).ok())
        .filter(|record| {
            record.digest.len() == 64 && record.digest.bytes().all(|byte| byte.is_ascii_hexdigit())
        });
    if let Some(record) = cached {
        let path = root
            .join("project-rsc-v1")
            .join(&record.digest[..2])
            .join(&record.digest);
        let before = capture(&path);
        if before.as_ref() == Some(&record.stamp) {
            if std::env::var_os("DM_BUILD_TRACE").is_some() {eprintln!("DM_BUILD_TRACE archive receipt hit: lookup {:.3}s, total {:.3}s",lookup_started.elapsed().as_secs_f64(),started.elapsed().as_secs_f64());}
            return Ok(PreparedArchive {
                path,
                digest: record.digest,
                len: record.len,
                stamp: record.stamp,
                catalog,
                receipt_store: store.clone(), receipt_key: archive_key.clone(),
            });
        }
        // Adding a hardlink changes Windows change clocks without changing bytes.
        // Refresh a verified identity instead of recomposing the unchanged archive.
        if let Some(stamp) = before {
            if std::env::var_os("DM_BUILD_TRACE").is_some() {eprintln!("DM_BUILD_TRACE archive strong stamp miss: hashing {} bytes",record.len);}
            if identical(&path, &record.digest, record.len).unwrap_or(false)
                && capture(&path).as_ref() == Some(&stamp) {
                let refreshed = ArchiveRecord {digest: record.digest.clone(), len: record.len, stamp: stamp.clone()};
                store.commit(&[], &[Change::Put(archive_key.clone(), serde_json::to_vec(&refreshed).map_err(io::Error::other)?)], None)?;
                return Ok(PreparedArchive {path, digest: record.digest, len: record.len, stamp, catalog, receipt_store:store.clone(), receipt_key:archive_key.clone()});
            }
        }
    }
    let keys: Vec<_> = catalog
        .entries
        .iter()
        .map(|entry| Key::new("resource-entry-v1", entry_identity(entry)))
        .collect();
    let mut cached = Vec::with_capacity(keys.len());
    for group in keys.chunks(256) {
        cached.extend(
            store
                .read_many(group, None)?
                .values
                .into_iter()
                .map(|bytes| {
                    bytes.and_then(|bytes| serde_json::from_slice::<EntryRecord>(&bytes).ok())
                }),
        );
    }
    let jobs: Vec<_> = inputs.iter().zip(&catalog.entries).zip(&cached).collect();
    let entries = dm_work::map_ordered(
        &jobs,
        dm_work::WorkLimits::configured(),
        |_| 256 * 1024,
        |((input, entry), cached)| prepare_entry(root, input, entry, cached.as_ref()),
    )
    .map_err(input_cache::work_error)?
    .into_iter()
    .collect::<io::Result<Vec<_>>>()?;
    fs::create_dir_all(staging_path.parent().unwrap())?;
    let tmp = temporary(&staging_path);
    let mut writer = BufWriter::with_capacity(
        64 * 1024,
        fs::OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(&tmp.0)?,
    );
    let mut hash = Sha256::new();
    let mut len = 0u64;
    let mut buffer = [0u8; 64 * 1024];
    for entry in &entries {
        if capture(&entry.path).as_ref() != Some(&entry.record.stamp) {
            return Err(io::Error::other(
                "resource entry changed before composition",
            ));
        }
        let mut reader = BufReader::with_capacity(64 * 1024, fs::File::open(&entry.path)?);
        let mut digest = Sha256::new();
        let mut size = 0u64;
        loop {
            let n = reader.read(&mut buffer)?;
            if n == 0 {
                break;
            }
            let bytes = &buffer[..n];
            writer.write_all(bytes)?;
            hash.update(bytes);
            digest.update(bytes);
            size += n as u64;
        }
        drop(reader);
        if size != entry.record.len
            || format!("{:x}", digest.finalize()) != entry.record.digest
            || capture(&entry.path).as_ref() != Some(&entry.record.stamp)
        {
            return Err(io::Error::other(
                "resource entry changed during composition",
            ));
        }
        len = len
            .checked_add(size)
            .ok_or_else(|| invalid("archive length overflow"))?;
    }
    writer.flush()?;
    writer.get_ref().sync_all()?;
    drop(writer);
    let digest = format!("{:x}", hash.finalize());
    let archive_path = root.join("project-rsc-v1").join(&digest[..2]).join(&digest);
    fs::create_dir_all(archive_path.parent().unwrap())?;
    promote(&tmp, &archive_path, &digest, len)?;
    let stamp = capture(&archive_path)
        .ok_or_else(|| io::Error::other("archive strong stamp unavailable"))?;
    let mut changes = Vec::new();
    for entry in &entries {
        if entry.fresh {
            changes.push(Change::Put(
                entry.key.clone(),
                serde_json::to_vec(&entry.record).map_err(io::Error::other)?,
            ));
        }
    }
    changes.push(Change::Put(
        archive_key.clone(),
        serde_json::to_vec(&ArchiveRecord {
            digest: digest.clone(),
            len,
            stamp: stamp.clone(),
        })
        .map_err(io::Error::other)?,
    ));
    store.commit(&[], &changes, None)?;
    if std::env::var_os("DM_BUILD_TRACE").is_some() {
        eprintln!(
            "DM_BUILD_TRACE streamed resource archive: {} entries, {} new, {} bytes, {:.3}s",
            entries.len(),
            entries.iter().filter(|entry| entry.fresh).count(),
            len,
            started.elapsed().as_secs_f64()
        );
    }
    Ok(PreparedArchive {
        path: archive_path,
        digest,
        len,
        stamp,
        catalog,
        receipt_store:store.clone(), receipt_key:archive_key,
    })
}
