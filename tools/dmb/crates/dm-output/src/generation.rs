//! Immutable DMB/RSC generations with an append-only commit pointer.
//! A torn final HEAD line is ignored, so readers see the preceding complete pair.

use dm_host::file_stamp::{capture, FileStamp};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::fs::{self, File, OpenOptions};
use std::io::{self, BufReader, Read, Write};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};

static NEXT_TEMP: AtomicU64 = AtomicU64::new(0);

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct Generation {
    pub id: String,
    pub dmb: PathBuf,
    pub rsc: PathBuf,
}

fn invalid(message: &'static str) -> io::Error {
    io::Error::new(io::ErrorKind::InvalidData, message)
}

fn generation(root: &Path, id: String) -> Generation {
    let directory = root.join("generations").join(&id);
    Generation {
        id,
        dmb: directory.join("world.dmb"),
        rsc: directory.join("world.rsc"),
    }
}

fn generation_id(dmb: &[u8], rsc: &[u8]) -> String {
    generation_id_from_digests(
        dmb.len() as u64,
        &format!("{:x}", Sha256::digest(dmb)),
        rsc.len() as u64,
        &format!("{:x}", Sha256::digest(rsc)),
    )
}

/// Framed content digests make unchanged archives reusable without hashing
/// their complete payload on every procedure edit. Version-one IDs still read.
pub fn generation_id_from_digests(
    dmb_len: u64,
    dmb_digest: &str,
    rsc_len: u64,
    rsc_digest: &str,
) -> String {
    let mut hash = Sha256::new();
    hash.update(b"dm-output-generation-v2\0");
    hash.update(dmb_len.to_le_bytes());
    hash.update(dmb_digest.as_bytes());
    hash.update(rsc_len.to_le_bytes());
    hash.update(rsc_digest.as_bytes());
    format!("{:x}", hash.finalize())
}

#[derive(Clone, Debug, Serialize, Deserialize)]
struct ContentDigests {
    dmb_len: u64,
    dmb_digest: String,
    rsc_len: u64,
    rsc_digest: String,
    resources: String,
    #[serde(default)]
    pair_validated: bool,
}

/// An archive verified against a published generation and strong file stamp.
/// Fields are private so arbitrary paths/digests cannot become trusted inputs.
#[derive(Clone, Debug)]
pub struct VerifiedArchive {
    path: PathBuf,
    stamp: FileStamp,
    content: ContentDigests,
}
impl VerifiedArchive {
    pub fn path(&self) -> &Path {
        &self.path
    }
    pub fn digest(&self) -> &str {
        &self.content.rsc_digest
    }
    pub fn len(&self) -> u64 {
        self.content.rsc_len
    }
    pub fn is_empty(&self) -> bool {
        self.len() == 0
    }
}

/// A serialization receipt issued only from an immutable validated image.
/// It is process-local: persisted receipts must be independently verified.
pub struct VerifiedBytecode {
    digest: String,
    len: usize,
    resources: String,
}
impl VerifiedBytecode {
    pub fn serialize(
        image: &byond_dmb::dmb::ReferenceValidatedImage<'_>,
    ) -> io::Result<(Vec<u8>, Vec<std::ops::Range<usize>>, Self)> {
        let (bytes, spans) = image.to_bytes_with_list_spans()?;
        let image = image.image();
        let receipt = Self {
            digest: format!("{:x}", Sha256::digest(&bytes)),
            len: bytes.len(),
            resources: resource_digest(image),
        };
        Ok((bytes, spans, receipt))
    }
}

fn resource_digest(dmb: &byond_dmb::dmb::Dmb) -> String {
    let mut hash = Sha256::new();
    for resource in &dmb.resources {
        hash.update(resource.id.to_le_bytes());
        hash.update([resource.kind]);
    }
    format!("{:x}", hash.finalize())
}

fn valid_id(id: &str) -> bool {
    id.len() == 64 && id.bytes().all(|byte| byte.is_ascii_hexdigit())
}

fn head_id(root: &Path) -> io::Result<Option<String>> {
    let bytes = match fs::read(root.join("HEAD")) {
        Ok(bytes) => bytes,
        Err(error) if error.kind() == io::ErrorKind::NotFound => return Ok(None),
        Err(error) => return Err(error),
    };
    for line in bytes.split_inclusive(|byte| *byte == b'\n').rev() {
        if !line.ends_with(b"\n") {
            continue;
        }
        let Ok(id) = std::str::from_utf8(&line[..line.len() - 1]) else {
            continue;
        };
        if !valid_id(id) {
            continue;
        }
        let candidate = generation(root, id.to_owned());
        if candidate.dmb.is_file() && candidate.rsc.is_file() {
            return Ok(Some(id.to_owned()));
        }
    }
    Ok(None)
}

pub fn current_generation(root: &Path) -> io::Result<Option<Generation>> {
    Ok(head_id(root)?.map(|id| generation(root, id)))
}

/// Publish a validated pair. Repeated content reuses its immutable files and
/// does not append another HEAD record. Callers may keep older generations for
/// rollback or collect them after no reader references them.
pub fn publish_generation(root: &Path, dmb: &[u8], rsc: &[u8]) -> io::Result<Generation> {
    publish_generation_reusing_archive(root, dmb, rsc, None)
}

/// Import conventional compiler outputs without loading the archive into RAM.
/// The private copied pair is validated before its immutable HEAD is advanced.
pub fn publish_generation_from_files(
    root: &Path,
    dmb: &Path,
    rsc: &Path,
) -> io::Result<Generation> {
    fn file_digest(path: &Path) -> io::Result<(u64, String)> {
        let mut reader = File::open(path)?;
        let mut hash = Sha256::new();
        let mut length = 0u64;
        let mut buffer = [0u8; 64 * 1024];
        loop {
            let count = reader.read(&mut buffer)?;
            if count == 0 {
                return Ok((length, format!("{:x}", hash.finalize())));
            }
            hash.update(&buffer[..count]);
            length += count as u64;
        }
    }
    fs::create_dir_all(root.join("generations"))?;
    let temp = root.join("generations").join(format!(
        ".pending-import-{}-{}",
        std::process::id(),
        NEXT_TEMP.fetch_add(1, Ordering::Relaxed)
    ));
    fs::create_dir(&temp)?;
    let result = (|| {
        let before = (capture(dmb), capture(rsc));
        for (source, name) in [(dmb, "world.dmb"), (rsc, "world.rsc")] {
            fs::copy(source, temp.join(name))?;
            OpenOptions::new()
                .write(true)
                .open(temp.join(name))?
                .sync_all()?;
        }
        let (dmb_len, dmb_digest) = file_digest(&temp.join("world.dmb"))?;
        let (rsc_len, rsc_digest) = file_digest(&temp.join("world.rsc"))?;
        let unchanged = if let (Some(left), Some(right)) = (&before.0, &before.1) {
            capture(dmb).as_ref() == Some(left) && capture(rsc).as_ref() == Some(right)
        } else {
            file_digest(dmb)? == (dmb_len, dmb_digest.clone())
                && file_digest(rsc)? == (rsc_len, rsc_digest.clone())
        };
        if !unchanged {
            return Err(invalid("compiler outputs changed during generation import"));
        }
        let id = generation_id_from_digests(dmb_len, &dmb_digest, rsc_len, &rsc_digest);
        let published = generation(root, id.clone());
        let lock = OpenOptions::new()
            .create(true)
            .read(true)
            .write(true)
            .open(root.join("HEAD.lock"))?;
        lock.lock()?;
        let directory = published
            .dmb
            .parent()
            .ok_or_else(|| invalid("generation has no directory"))?;
        if directory.exists() && verify_generation_digest(root, &published).is_err() {
            fs::rename(
                directory,
                root.join("generations").join(format!(
                    ".corrupt-{}-{}-{}",
                    id,
                    std::process::id(),
                    NEXT_TEMP.fetch_add(1, Ordering::Relaxed)
                )),
            )?;
        }
        if !directory.exists() {
            fs::rename(&temp, directory)?;
        }
        let stamps = generation_stamps(&published);
        let content = verify_generation_inner(root, &published, true)?;
        if let Some(stamps) =
            stamps.filter(|stamps| generation_stamps(&published).as_ref() == Some(stamps))
        {
            save_verification_receipt(&published, stamps, Some(content))?;
        }
        let head_path = root.join("HEAD");
        if let Ok(bytes) = fs::read(&head_path) {
            if !bytes.is_empty() && !bytes.ends_with(b"\n") {
                let complete = bytes
                    .iter()
                    .rposition(|byte| *byte == b'\n')
                    .map_or(0, |index| index + 1);
                OpenOptions::new()
                    .write(true)
                    .open(&head_path)?
                    .set_len(complete as u64)?;
            }
        }
        if head_id(root)?.as_deref() != Some(id.as_str()) {
            let mut head = OpenOptions::new()
                .create(true)
                .append(true)
                .open(head_path)?;
            writeln!(head, "{id}")?;
            head.sync_all()?;
        }
        Ok(published)
    })();
    if temp.exists() {
        let _ = fs::remove_dir_all(&temp);
    }
    result
}

/// Reuse the unchanged immutable archive through a hard link when available.
/// Publication still validates the final pair and content ID; cross-device or
/// unavailable links fall back to ordinary writing without weakening checks.
pub fn publish_generation_reusing_archive(
    root: &Path,
    dmb: &[u8],
    rsc: &[u8],
    archive_source: Option<&Path>,
) -> io::Result<Generation> {
    let archive_source = archive_source.filter(|path| {
        // Never link unverified caller-provided bytes into an immutable generation.
        let Ok(mut file) = File::open(path) else {
            return false;
        };
        let mut hash = Sha256::new();
        let mut len = 0usize;
        let mut buffer = [0u8; 64 * 1024];
        loop {
            let Ok(count) = file.read(&mut buffer) else {
                return false;
            };
            if count == 0 {
                break;
            }
            len += count;
            hash.update(&buffer[..count]);
        }
        len == rsc.len() && hash.finalize().as_slice() == Sha256::digest(rsc).as_slice()
    });
    crate::validate_byond_pair(dmb, rsc)?;
    let id = generation_id(dmb, rsc);
    let published = generation(root, id.clone());
    fs::create_dir_all(root.join("generations"))?;
    let lock = OpenOptions::new()
        .create(true)
        .read(true)
        .write(true)
        .open(root.join("HEAD.lock"))?;
    lock.lock()?;
    let directory = published
        .dmb
        .parent()
        .ok_or_else(|| invalid("generation has no directory"))?;
    let valid_existing = directory.exists() && verify_generation_digest(root, &published).is_ok();
    if directory.exists() && !valid_existing {
        // Keep damaged bytes for inspection while rebuilding the exact same
        // content ID. Publishers share HEAD.lock, so no second writer can
        // install or quarantine this directory concurrently.
        let quarantine = root.join("generations").join(format!(
            ".corrupt-{}-{}-{}",
            id,
            std::process::id(),
            NEXT_TEMP.fetch_add(1, Ordering::Relaxed)
        ));
        fs::rename(directory, quarantine)?;
    }
    if !directory.exists() {
        let temp = root.join("generations").join(format!(
            ".pending-{}-{}",
            std::process::id(),
            NEXT_TEMP.fetch_add(1, Ordering::Relaxed)
        ));
        fs::create_dir(&temp)?;
        let write_result = (|| {
            for (name, bytes) in [("world.dmb", dmb), ("world.rsc", rsc)] {
                if name == "world.rsc"
                    && archive_source
                        .is_some_and(|source| fs::hard_link(source, temp.join(name)).is_ok())
                {
                    continue;
                }
                let mut file = File::create(temp.join(name))?;
                file.write_all(bytes)?;
                file.sync_all()?;
            }
            fs::rename(&temp, directory)
        })();
        if let Err(error) = write_result {
            let _ = fs::remove_dir_all(&temp);
            if !directory.is_dir() {
                return Err(error);
            }
        }
    }
    // Input bytes were validated above. Confirm the published files match the
    // content ID without parsing the potentially large archive a second time.
    if !valid_existing {
        verify_generation_digest(root, &published)?;
    }
    let head_path = root.join("HEAD");
    if let Ok(bytes) = fs::read(&head_path) {
        if !bytes.is_empty() && !bytes.ends_with(b"\n") {
            let complete_len = bytes
                .iter()
                .rposition(|byte| *byte == b'\n')
                .map_or(0, |index| index + 1);
            OpenOptions::new()
                .write(true)
                .open(&head_path)?
                .set_len(complete_len as u64)?;
        }
    }
    if head_id(root)?.as_deref() != Some(id.as_str()) {
        let mut head = OpenOptions::new()
            .create(true)
            .append(true)
            .open(&head_path)?;
        head.write_all(id.as_bytes())?;
        head.write_all(b"\n")?;
        head.sync_all()?;
    }
    if let Some(stamps) = generation_stamps(&published) {
        if verification_receipt_matches(&published, &stamps) {
            if let Ok(receipt) = File::open(receipt_path(&published)).and_then(|file| {
                serde_json::from_reader::<_, VerificationReceipt>(file.take(8192))
                    .map_err(io::Error::other)
            }) {
                if let Some(mut content) = receipt.content {
                    content.pair_validated = true;
                    let _ = save_verification_receipt(&published, stamps, Some(content));
                }
            }
        }
    }
    Ok(published)
}

/// Verify an immutable generation before serving its bytes to a consumer.
pub fn verify_generation(root: &Path, generation: &Generation) -> io::Result<()> {
    verify_generation_inner(root, generation, true).map(|_| ())
}

/// Confirm immutable files match a previously validated generation ID without
/// decoding the archive again. Use full `verify_generation` for unknown pairs.
pub fn verify_generation_digest(root: &Path, generation: &Generation) -> io::Result<()> {
    if !valid_id(&generation.id) || generation != &self::generation(root, generation.id.clone()) {
        return Err(invalid("invalid generation path"));
    }
    let before = generation_stamps(generation);
    if let Some(stamps) = before
        .as_ref()
        .filter(|_| std::env::var("DM_BUILD_EXACT_INPUTS").as_deref() != Ok("1"))
    {
        if verification_receipt_matches(generation, stamps) {
            return Ok(());
        }
    }
    let content = verify_generation_inner(root, generation, false)?;
    if let Some(stamps) = before {
        if generation_stamps(generation).as_ref() == Some(&stamps) {
            // An unavailable receipt is only a performance miss; the bytes have
            // already been checked. Never weaken verification on stamp failure.
            let _ = save_verification_receipt(generation, stamps, Some(content));
        }
    }
    Ok(())
}

pub fn verified_archive(root: &Path, generation: &Generation) -> io::Result<VerifiedArchive> {
    if std::env::var("DM_BUILD_EXACT_INPUTS").as_deref() == Ok("1") {
        return Err(invalid("exact input mode requires archive bytes"));
    }
    verify_generation_digest(root, generation)?;
    let mut stamps =
        generation_stamps(generation).ok_or_else(|| invalid("archive strong stamp unavailable"))?;
    let mut content = File::open(receipt_path(generation))
        .ok()
        .and_then(|file| serde_json::from_reader::<_, VerificationReceipt>(file.take(8192)).ok())
        .filter(|receipt| {
            receipt.stamps == stamps && verification_receipt_matches(generation, &stamps)
        })
        .and_then(|receipt| receipt.content)
        .filter(|content| content.pair_validated);
    if content.is_none() {
        let checked = verify_generation_inner(root, generation, true)?;
        let after = generation_stamps(generation)
            .ok_or_else(|| invalid("archive strong stamp unavailable"))?;
        if after != stamps {
            return Err(invalid("archive changed during validation"));
        }
        save_verification_receipt(generation, stamps.clone(), Some(checked.clone()))?;
        content = Some(checked);
        stamps = after;
    }
    Ok(VerifiedArchive {
        path: generation.rsc.clone(),
        stamp: stamps.rsc,
        content: content.unwrap(),
    })
}

/// Publish changed bytecode with a verified, unchanged archive. An exclusive
/// archive handle protects the proof until its new immutable link and receipt
/// have been published. Callers fall back to normal publication if unavailable.
pub fn publish_generation_with_archive(
    root: &Path,
    dmb: &[u8],
    archive: &VerifiedArchive,
) -> io::Result<Generation> {
    let decoded = byond_dmb::dmb::Dmb::from_bytes(dmb)?;
    decoded.validate_references()?;
    publish_verified_archive_inner(root, dmb, archive, &resource_digest(&decoded), None)
}

/// Publication of compiler-owned serialization without decoding it again.
/// Digest binding prevents a caller from pairing a receipt with different bytes.
pub fn publish_generation_with_verified_bytecode(
    root: &Path,
    dmb: &[u8],
    archive: &VerifiedArchive,
    receipt: &VerifiedBytecode,
) -> io::Result<Generation> {
    if receipt.len != dmb.len() || receipt.digest != format!("{:x}", Sha256::digest(dmb)) {
        return Err(invalid("bytecode differs from its validation receipt"));
    }
    publish_verified_archive_inner(
        root,
        dmb,
        archive,
        &receipt.resources,
        Some(&receipt.digest),
    )
}

fn publish_verified_archive_inner(
    root: &Path,
    dmb: &[u8],
    archive: &VerifiedArchive,
    resources: &str,
    digest: Option<&str>,
) -> io::Result<Generation> {
    use dm_host::file_stamp::{capture_file, open_verified};
    if resources != archive.content.resources {
        return Err(invalid("changed DMB resource table requires a new archive"));
    }
    let content = ContentDigests {
        dmb_len: dmb.len() as u64,
        dmb_digest: digest
            .map(str::to_owned)
            .unwrap_or_else(|| format!("{:x}", Sha256::digest(dmb))),
        rsc_len: archive.len(),
        rsc_digest: archive.digest().into(),
        resources: archive.content.resources.clone(),
        pair_validated: true,
    };
    let id = generation_id_from_digests(
        content.dmb_len,
        &content.dmb_digest,
        content.rsc_len,
        &content.rsc_digest,
    );
    let published = generation(root, id.clone());
    fs::create_dir_all(root.join("generations"))?;
    let lock = OpenOptions::new()
        .create(true)
        .read(true)
        .write(true)
        .open(root.join("HEAD.lock"))?;
    lock.lock()?;
    let directory = published.dmb.parent().unwrap();
    if directory.exists() && verify_generation_digest(root, &published).is_err() {
        fs::rename(
            directory,
            root.join("generations").join(format!(
                ".corrupt-{}-{}-{}",
                id,
                std::process::id(),
                NEXT_TEMP.fetch_add(1, Ordering::Relaxed)
            )),
        )?;
    }
    let mut protected = None;
    let mut copied_stamp = None;
    let created = !directory.exists();
    if !directory.exists() {
        protected = Some(
            open_verified(&archive.path, &archive.stamp)
                .ok_or_else(|| invalid("verified archive unavailable or changed"))?,
        );
        let temp = root.join("generations").join(format!(
            ".pending-{}-{}",
            std::process::id(),
            NEXT_TEMP.fetch_add(1, Ordering::Relaxed)
        ));
        fs::create_dir(&temp)?;
        let result = (|| {
            let mut output = File::create(temp.join("world.dmb"))?;
            output.write_all(dmb)?;
            output.sync_all()?;
            drop(output);
            if fs::hard_link(&archive.path, temp.join("world.rsc")).is_err() {
                let mut copy = File::create(temp.join("world.rsc"))?;
                let copied = io::copy(protected.as_mut().unwrap(), &mut copy)?;
                if copied != archive.len() {
                    return Err(invalid("archive copy length mismatch"));
                }
                copy.sync_all()?;
                copied_stamp = capture_file(&copy);
            }
            fs::rename(&temp, directory).map_err(|error| {
                io::Error::new(
                    error.kind(),
                    format!("archive generation directory publication: {error}"),
                )
            })
        })();
        if let Err(error) = result {
            let _ = fs::remove_dir_all(&temp);
            return Err(error);
        }
    }
    if created {
        let dmb_stamp =
            capture(&published.dmb).ok_or_else(|| invalid("published DMB stamp unavailable"))?;
        if fs::read(&published.dmb)? != dmb {
            return Err(invalid("published DMB bytes changed"));
        }
        if capture(&published.dmb).as_ref() != Some(&dmb_stamp) {
            return Err(invalid("published DMB changed during validation"));
        }
        let rsc_stamp = copied_stamp
            .or_else(|| capture_file(protected.as_ref().unwrap()))
            .ok_or_else(|| invalid("published archive stamp unavailable"))?;
        save_verification_receipt(
            &published,
            GenerationStamps {
                dmb: dmb_stamp,
                rsc: rsc_stamp,
            },
            Some(content),
        )?;
    }
    let head_path = root.join("HEAD");
    if let Ok(bytes) = fs::read(&head_path) {
        if !bytes.is_empty() && !bytes.ends_with(b"\n") {
            let complete = bytes
                .iter()
                .rposition(|byte| *byte == b'\n')
                .map_or(0, |offset| offset + 1);
            OpenOptions::new()
                .write(true)
                .open(&head_path)?
                .set_len(complete as u64)?;
        }
    }
    if head_id(root)?.as_deref() != Some(id.as_str()) {
        let mut head = OpenOptions::new()
            .create(true)
            .append(true)
            .open(head_path)?;
        head.write_all(id.as_bytes())?;
        head.write_all(b"\n")?;
        head.sync_all()?;
    }
    Ok(published)
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
struct GenerationStamps {
    dmb: FileStamp,
    rsc: FileStamp,
}

#[derive(Serialize, Deserialize)]
struct VerificationReceipt {
    version: u32,
    generation: String,
    stamps: GenerationStamps,
    checksum: String,
    #[serde(default)]
    content: Option<ContentDigests>,
}

fn generation_stamps(generation: &Generation) -> Option<GenerationStamps> {
    Some(GenerationStamps {
        dmb: capture(&generation.dmb)?,
        rsc: capture(&generation.rsc)?,
    })
}

fn receipt_path(generation: &Generation) -> PathBuf {
    generation.dmb.with_file_name("verified.json")
}

fn receipt_checksum(
    id: &str,
    stamps: &GenerationStamps,
    content: Option<&ContentDigests>,
) -> Option<String> {
    let bytes = match content {
        Some(content) => serde_json::to_vec(&(2u32, id, stamps, content)).ok()?,
        None => serde_json::to_vec(&(1u32, id, stamps)).ok()?,
    };
    Some(format!("{:x}", Sha256::digest(bytes)))
}

fn verification_receipt_matches(generation: &Generation, stamps: &GenerationStamps) -> bool {
    let Ok(file) = File::open(receipt_path(generation)) else {
        return false;
    };
    let Ok(receipt) = serde_json::from_reader::<_, VerificationReceipt>(file.take(8192)) else {
        return false;
    };
    receipt.version == (if receipt.content.is_some() { 2 } else { 1 })
        && receipt.generation == generation.id
        && &receipt.stamps == stamps
        && receipt_checksum(
            &receipt.generation,
            &receipt.stamps,
            receipt.content.as_ref(),
        )
        .as_deref()
            == Some(&receipt.checksum)
}

fn save_verification_receipt(
    generation: &Generation,
    stamps: GenerationStamps,
    content: Option<ContentDigests>,
) -> io::Result<()> {
    let checksum = receipt_checksum(&generation.id, &stamps, content.as_ref())
        .ok_or_else(|| invalid("receipt serialization failed"))?;
    let receipt = VerificationReceipt {
        version: if content.is_some() { 2 } else { 1 },
        generation: generation.id.clone(),
        stamps,
        checksum,
        content,
    };
    let path = receipt_path(generation);
    let temp = path.with_extension(format!(
        "pending-{}-{}",
        std::process::id(),
        NEXT_TEMP.fetch_add(1, Ordering::Relaxed)
    ));
    let result = (|| {
        let mut file = OpenOptions::new()
            .create_new(true)
            .write(true)
            .open(&temp)?;
        serde_json::to_writer(&mut file, &receipt).map_err(io::Error::other)?;
        file.flush()?;
        fs::rename(&temp, &path)
    })();
    if result.is_err() {
        let _ = fs::remove_file(temp);
    }
    result
}

fn verify_generation_inner(
    root: &Path,
    generation: &Generation,
    validate_structure: bool,
) -> io::Result<ContentDigests> {
    if !valid_id(&generation.id) || generation != &self::generation(root, generation.id.clone()) {
        return Err(invalid("invalid generation path"));
    }
    let mut dmb = Vec::new();
    File::open(&generation.dmb)?.read_to_end(&mut dmb)?;
    let rsc = File::open(&generation.rsc)?;
    let rsc_len = rsc.metadata()?.len();
    let mut hash = Sha256::new();
    hash.update(b"dm-output-generation-v1\0");
    hash.update((dmb.len() as u64).to_le_bytes());
    hash.update(&dmb);
    hash.update(rsc_len.to_le_bytes());
    let mut reader = HashingReader {
        inner: BufReader::new(rsc),
        hash,
        read_bytes: 0,
        content_hash: Sha256::new(),
    };
    if validate_structure {
        crate::validate_byond_pair_reader(&dmb, &mut reader)?;
    } else {
        io::copy(&mut reader, &mut io::sink())?;
    }
    let decoded = byond_dmb::dmb::Dmb::from_bytes(&dmb)?;
    let content = ContentDigests {
        dmb_len: dmb.len() as u64,
        dmb_digest: format!("{:x}", Sha256::digest(&dmb)),
        rsc_len,
        rsc_digest: format!("{:x}", reader.content_hash.finalize()),
        resources: resource_digest(&decoded),
        pair_validated: validate_structure,
    };
    if reader.read_bytes != rsc_len
        || (format!("{:x}", reader.hash.finalize()) != generation.id
            && generation_id_from_digests(
                content.dmb_len,
                &content.dmb_digest,
                content.rsc_len,
                &content.rsc_digest,
            ) != generation.id)
    {
        return Err(invalid("generation bytes do not match its ID"));
    }
    Ok(content)
}

struct HashingReader<R> {
    inner: R,
    hash: Sha256,
    read_bytes: u64,
    content_hash: Sha256,
}

impl<R: Read> Read for HashingReader<R> {
    fn read(&mut self, buf: &mut [u8]) -> io::Result<usize> {
        let count = self.inner.read(buf)?;
        self.hash.update(&buf[..count]);
        self.content_hash.update(&buf[..count]);
        self.read_bytes += count as u64;
        Ok(count)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn publication_route_does_not_change_generation_identity() {
        let root = std::env::temp_dir().join(format!(
            "dm-generation-route-{}-{}",
            std::process::id(),
            NEXT_TEMP.fetch_add(1, Ordering::Relaxed)
        ));
        let mut world = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/native_template.bin"
        ))
        .unwrap();
        world.resources.clear();
        let bytes = world.to_bytes().unwrap();
        let normal = publish_generation(&root, &bytes, &[]).unwrap();
        let archive = verified_archive(&root, &normal).unwrap();
        let reused = publish_generation_with_archive(&root, &bytes, &archive).unwrap();
        assert_eq!(normal, reused);
        let imported = publish_generation_from_files(&root, &normal.dmb, &normal.rsc).unwrap();
        assert_eq!(normal, imported);
        assert_eq!(
            normal.id,
            generation_id_from_digests(
                bytes.len() as u64,
                &format!("{:x}", Sha256::digest(&bytes)),
                0,
                &format!("{:x}", Sha256::digest([]))
            )
        );
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn legacy_generation_ids_remain_readable() {
        let root = std::env::temp_dir().join(format!(
            "dm-generation-legacy-{}-{}",
            std::process::id(),
            NEXT_TEMP.fetch_add(1, Ordering::Relaxed)
        ));
        let mut world = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/native_template.bin"
        ))
        .unwrap();
        world.resources.clear();
        let bytes = world.to_bytes().unwrap();
        let mut hash = Sha256::new();
        hash.update(b"dm-output-generation-v1\0");
        hash.update((bytes.len() as u64).to_le_bytes());
        hash.update(&bytes);
        hash.update(0u64.to_le_bytes());
        let legacy = generation(&root, format!("{:x}", hash.finalize()));
        fs::create_dir_all(legacy.dmb.parent().unwrap()).unwrap();
        fs::write(&legacy.dmb, bytes).unwrap();
        fs::write(&legacy.rsc, []).unwrap();
        fs::write(root.join("HEAD"), format!("{}\n", legacy.id)).unwrap();
        assert_eq!(current_generation(&root).unwrap(), Some(legacy.clone()));
        verify_generation(&root, &legacy).unwrap();
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn verification_receipt_detects_same_length_corruption_with_restored_mtime() {
        let root = std::env::temp_dir().join(format!(
            "dm-generation-stamp-{}-{}",
            std::process::id(),
            NEXT_TEMP.fetch_add(1, Ordering::Relaxed)
        ));
        let mut dmb = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/native_template.bin"
        ))
        .unwrap();
        dmb.resources.clear();
        let bytes = dmb.to_bytes().unwrap();
        let published = publish_generation(&root, &bytes, b"").unwrap();
        let modified = fs::metadata(&published.dmb).unwrap().modified().unwrap();
        if let Some(stamps) = generation_stamps(&published) {
            assert!(verification_receipt_matches(&published, &stamps));
        }
        verify_generation_digest(&root, &published).unwrap();
        let mut damaged = bytes.clone();
        damaged[0] ^= 1;
        fs::write(&published.dmb, damaged).unwrap();
        File::options()
            .write(true)
            .open(&published.dmb)
            .unwrap()
            .set_times(fs::FileTimes::new().set_modified(modified))
            .unwrap();
        assert!(verify_generation_digest(&root, &published).is_err());
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn corrupt_verification_receipt_falls_back_to_content_verification() {
        let root = std::env::temp_dir().join(format!(
            "dm-generation-receipt-{}-{}",
            std::process::id(),
            NEXT_TEMP.fetch_add(1, Ordering::Relaxed)
        ));
        let mut dmb = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/native_template.bin"
        ))
        .unwrap();
        dmb.resources.clear();
        let published = publish_generation(&root, &dmb.to_bytes().unwrap(), b"").unwrap();
        fs::write(receipt_path(&published), b"broken receipt").unwrap();
        verify_generation_digest(&root, &published).unwrap();
        if let Some(stamps) = generation_stamps(&published) {
            assert!(verification_receipt_matches(&published, &stamps));
        }
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn damaged_generation_is_quarantined_and_republished() {
        let root = std::env::temp_dir().join(format!(
            "dm-generation-repair-{}-{}",
            std::process::id(),
            NEXT_TEMP.fetch_add(1, Ordering::Relaxed)
        ));
        let bytes = include_bytes!("../../../fixtures/native_template.bin");
        let mut dmb = byond_dmb::dmb::Dmb::from_bytes(bytes).unwrap();
        dmb.resources.clear();
        let bytes = dmb.to_bytes().unwrap();
        let first = publish_generation(&root, &bytes, b"").unwrap();
        fs::write(&first.dmb, b"damaged").unwrap();
        assert!(verify_generation_digest(&root, &first).is_err());
        let repaired = publish_generation(&root, &bytes, b"").unwrap();
        assert_eq!(first, repaired);
        assert_eq!(fs::read(&repaired.dmb).unwrap(), bytes);
        verify_generation(&root, &repaired).unwrap();
        assert_eq!(current_generation(&root).unwrap(), Some(repaired));
        let quarantined = fs::read_dir(root.join("generations"))
            .unwrap()
            .filter_map(Result::ok)
            .find(|entry| entry.file_name().to_string_lossy().starts_with(".corrupt-"))
            .unwrap();
        assert_eq!(
            fs::read(quarantined.path().join("world.dmb")).unwrap(),
            b"damaged"
        );
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn verifies_nonempty_resource_archive_while_streaming() {
        let root = std::env::temp_dir().join(format!(
            "dm-output-resource-generation-{}-{}",
            std::process::id(),
            NEXT_TEMP.fetch_add(1, Ordering::Relaxed)
        ));
        let resource = byond_dmb::rsc::NamedResource::from_data(
            6,
            b"asset.txt".to_vec(),
            b"asset bytes".to_vec(),
            0,
            0,
        )
        .unwrap();
        let mut world = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/native_template.bin"
        ))
        .unwrap();
        world.resources.push(byond_dmb::dmb::ResourceRef {
            id: resource.id,
            kind: resource.kind,
        });
        let mut rsc = Vec::new();
        byond_dmb::rsc::write_all(&mut rsc, &[byond_dmb::rsc::Entry::Named(resource)]).unwrap();
        let published = publish_generation(&root, &world.to_bytes().unwrap(), &rsc).unwrap();
        verify_generation(&root, &published).unwrap();
        let mut damaged = rsc;
        *damaged.last_mut().unwrap() ^= 1;
        fs::write(&published.rsc, damaged).unwrap();
        assert!(verify_generation(&root, &published).is_err());
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn generations_reuse_bytes_and_ignore_torn_head() {
        let root = std::env::temp_dir().join(format!(
            "dm-output-generation-{}-{}",
            std::process::id(),
            NEXT_TEMP.fetch_add(1, Ordering::Relaxed)
        ));
        let dmb = include_bytes!("../../../fixtures/native_template.bin");
        let first = publish_generation(&root, dmb, &[]).unwrap();
        assert_eq!(publish_generation(&root, dmb, &[]).unwrap(), first);
        assert_eq!(current_generation(&root).unwrap(), Some(first.clone()));
        verify_generation(&root, &first).unwrap();
        let before = fs::read(root.join("HEAD")).unwrap();
        assert_eq!(before.iter().filter(|byte| **byte == b'\n').count(), 1);
        OpenOptions::new()
            .append(true)
            .open(root.join("HEAD"))
            .unwrap()
            .write_all(b"partial")
            .unwrap();
        assert_eq!(current_generation(&root).unwrap(), Some(first));
        publish_generation(&root, dmb, &[]).unwrap();
        assert_eq!(fs::read(root.join("HEAD")).unwrap(), before);
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn body_generation_reuses_verified_archive_and_rejects_wrong_source() {
        let root = std::env::temp_dir().join(format!(
            "dm-output-link-{}-{}",
            std::process::id(),
            NEXT_TEMP.fetch_add(1, Ordering::Relaxed)
        ));
        let original = include_bytes!("../../../fixtures/native_template.bin");
        let first = publish_generation(&root, original, &[]).unwrap();
        let mut changed = byond_dmb::dmb::Dmb::from_bytes(original).unwrap();
        changed.strings.push(byond_dmb::dmb::DmString {
            data: b"new generation".to_vec(),
            long_chunks: 0,
        });
        let second = publish_generation_reusing_archive(
            &root,
            &changed.to_bytes().unwrap(),
            &[],
            Some(&first.rsc),
        )
        .unwrap();
        verify_generation(&root, &first).unwrap();
        verify_generation(&root, &second).unwrap();
        // File identity proves this is a link, not an archive rewrite.
        if let (Some(a), Some(b)) = (capture(&first.rsc), capture(&second.rsc)) {
            assert_eq!(a, b);
        }
        let wrong = root.join("wrong.rsc");
        fs::write(&wrong, b"not the archive").unwrap();
        changed.strings.push(byond_dmb::dmb::DmString {
            data: b"third generation".to_vec(),
            long_chunks: 0,
        });
        let third = publish_generation_reusing_archive(
            &root,
            &changed.to_bytes().unwrap(),
            &[],
            Some(&wrong),
        )
        .unwrap();
        assert!(fs::read(&third.rsc).unwrap().is_empty());
        verify_generation(&root, &third).unwrap();
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    #[cfg(windows)]
    fn merkle_generation_reuses_guarded_archive_and_reads_legacy_generation() {
        let root = std::env::temp_dir().join(format!(
            "dm-output-merkle-{}-{}",
            std::process::id(),
            NEXT_TEMP.fetch_add(1, Ordering::Relaxed)
        ));
        let original = include_bytes!("../../../fixtures/native_template.bin");
        let first = publish_generation(&root, original, &[]).unwrap();
        let archive = verified_archive(&root, &first).unwrap();
        let mut changed = byond_dmb::dmb::Dmb::from_bytes(original).unwrap();
        changed.strings.push(byond_dmb::dmb::DmString {
            data: b"merkle generation".to_vec(),
            long_chunks: 0,
        });
        let bytes = changed.to_bytes().unwrap();
        let second = publish_generation_with_archive(&root, &bytes, &archive).unwrap();
        assert_eq!(
            second.id,
            generation_id_from_digests(
                bytes.len() as u64,
                &format!("{:x}", Sha256::digest(&bytes)),
                0,
                &format!("{:x}", Sha256::digest([]))
            )
        );
        verify_generation(&root, &first).unwrap();
        verify_generation(&root, &second).unwrap();
        let next_archive = verified_archive(&root, &second).unwrap();
        assert_eq!(
            publish_generation_with_archive(&root, &bytes, &next_archive).unwrap(),
            second
        );
        fs::write(&second.rsc, b"changed after proof").unwrap();
        changed.strings.push(byond_dmb::dmb::DmString {
            data: b"third".to_vec(),
            long_chunks: 0,
        });
        assert!(publish_generation_with_archive(
            &root,
            &changed.to_bytes().unwrap(),
            &next_archive
        )
        .is_err());
        assert!(verify_generation_digest(&root, &second).is_err());
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn new_generation_keeps_old_pair_available() {
        let root = std::env::temp_dir().join(format!(
            "dm-output-history-{}-{}",
            std::process::id(),
            NEXT_TEMP.fetch_add(1, Ordering::Relaxed)
        ));
        let original = include_bytes!("../../../fixtures/native_template.bin");
        let first = publish_generation(&root, original, &[]).unwrap();
        let mut changed = byond_dmb::dmb::Dmb::from_bytes(original).unwrap();
        changed.strings.push(byond_dmb::dmb::DmString {
            data: b"generation-test".to_vec(),
            long_chunks: 0,
        });
        let second = publish_generation(&root, &changed.to_bytes().unwrap(), &[]).unwrap();
        assert_ne!(first.id, second.id);
        assert_eq!(current_generation(&root).unwrap(), Some(second.clone()));
        verify_generation(&root, &first).unwrap();
        verify_generation(&root, &second).unwrap();
        OpenOptions::new()
            .append(true)
            .open(&second.dmb)
            .unwrap()
            .write_all(b"corrupt")
            .unwrap();
        assert!(verify_generation(&root, &second).is_err());
        assert_eq!(
            publish_generation(&root, &changed.to_bytes().unwrap(), &[]).unwrap(),
            second
        );
        verify_generation(&root, &second).unwrap();
        verify_generation(&root, &first).unwrap();
        fs::remove_dir_all(root).unwrap();
    }
}
