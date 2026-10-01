//! Immutable DMB/RSC generations with an append-only commit pointer.
//! A torn final HEAD line is ignored, so readers see the preceding complete pair.

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
    let mut hash = Sha256::new();
    hash.update(b"dm-output-generation-v1\0");
    hash.update((dmb.len() as u64).to_le_bytes());
    hash.update(dmb);
    hash.update((rsc.len() as u64).to_le_bytes());
    hash.update(rsc);
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
            ".corrupt-{}-{}-{}", id, std::process::id(), NEXT_TEMP.fetch_add(1, Ordering::Relaxed)
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
    if !valid_existing { verify_generation_digest(root, &published)?; }
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
    Ok(published)
}

/// Verify an immutable generation before serving its bytes to a consumer.
pub fn verify_generation(root: &Path, generation: &Generation) -> io::Result<()> {
    verify_generation_inner(root, generation, true)
}

/// Confirm immutable files match a previously validated generation ID without
/// decoding the archive again. Use full `verify_generation` for unknown pairs.
pub fn verify_generation_digest(root: &Path, generation: &Generation) -> io::Result<()> {
    verify_generation_inner(root, generation, false)
}

fn verify_generation_inner(
    root: &Path,
    generation: &Generation,
    validate_structure: bool,
) -> io::Result<()> {
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
    };
    if validate_structure {
        crate::validate_byond_pair_reader(&dmb, &mut reader)?;
    } else {
        io::copy(&mut reader, &mut io::sink())?;
    }
    if reader.read_bytes != rsc_len || format!("{:x}", reader.hash.finalize()) != generation.id {
        return Err(invalid("generation bytes do not match its ID"));
    }
    Ok(())
}

struct HashingReader<R> {
    inner: R,
    hash: Sha256,
    read_bytes: u64,
}

impl<R: Read> Read for HashingReader<R> {
    fn read(&mut self, buf: &mut [u8]) -> io::Result<usize> {
        let count = self.inner.read(buf)?;
        self.hash.update(&buf[..count]);
        self.read_bytes += count as u64;
        Ok(count)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn damaged_generation_is_quarantined_and_republished() {
        let root = std::env::temp_dir().join(format!("dm-generation-repair-{}-{}", std::process::id(), NEXT_TEMP.fetch_add(1, Ordering::Relaxed)));
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
        let quarantined = fs::read_dir(root.join("generations")).unwrap()
            .filter_map(Result::ok).find(|entry| entry.file_name().to_string_lossy().starts_with(".corrupt-")).unwrap();
        assert_eq!(fs::read(quarantined.path().join("world.dmb")).unwrap(), b"damaged");
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
        assert_eq!(publish_generation(&root, &changed.to_bytes().unwrap(), &[]).unwrap(), second);
        verify_generation(&root, &second).unwrap();
        verify_generation(&root, &first).unwrap();
        fs::remove_dir_all(root).unwrap();
    }
}
