//! Resource inputs shared by the direct compiler, its cache key, and RSC writer.
//! Callers resolve DM file literals to an authored archive name and a disk path.

use byond_dmb::rsc::{NamedResource, ResourceKind};
#[cfg(test)]
use byond_dmb::rsc::Entry;
use sha2::{Digest, Sha256};
use std::collections::HashMap;
use std::fs;
use std::io::{self, Read};
use std::path::{Component, Path, PathBuf};

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ResourceRequest {
    /// Project-relative name serialized in the RSC, with `/` separators.
    pub archive_name: String,
    pub disk_path: PathBuf,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ResourceInput {
    pub archive_name: String,
    pub disk_path: PathBuf,
    pub content_digest: [u8; 32],
    pub named: NamedResource,
}

#[derive(Clone, Debug, Default)]
pub struct ResourceSet {
    pub inputs: Vec<ResourceInput>,
    /// SHA-256 of every archive name and payload, in authored order.
    pub fingerprint: [u8; 32],
}

fn invalid(message: &'static str) -> io::Error {
    io::Error::new(io::ErrorKind::InvalidInput, message)
}

fn validate_archive_name(name: &str) -> io::Result<()> {
    if name.is_empty() || name.contains(['\0', '\\']) || name.starts_with('/') {
        return Err(invalid(
            "resource archive name must be a relative slash path",
        ));
    }
    if Path::new(name)
        .components()
        .any(|part| !matches!(part, Component::Normal(_)))
        || name
            .split('/')
            .any(|part| part.is_empty() || part == "." || part == "..")
    {
        return Err(invalid(
            "resource archive name contains an unsafe path segment",
        ));
    }
    Ok(())
}

fn kind_for_name(name: &str) -> ResourceKind {
    match Path::new(name)
        .extension()
        .and_then(|value| value.to_str())
        .unwrap_or("")
        .to_ascii_lowercase()
        .as_str()
    {
        "mid" | "midi" => ResourceKind::Midi,
        "ogg" | "wav" | "mp3" => ResourceKind::Sound,
        "dmi" => ResourceKind::Dmi,
        "bmp" => ResourceKind::Bmp,
        "png" => ResourceKind::Png,
        "zip" => ResourceKind::Zip,
        "rsc" => ResourceKind::Rsc,
        "jpg" | "jpeg" => ResourceKind::Jpeg,
        "gif" => ResourceKind::Gif,
        "ttf" | "otf" => ResourceKind::Font,
        _ => ResourceKind::Text,
    }
}

impl ResourceSet {
    /// Match the loaded-set identity while retaining only a small read buffer.
    /// Cached build checks need asset identity, not an in-memory RSC payload.
    pub fn fingerprint_requests(
        requests: impl IntoIterator<Item = ResourceRequest>,
    ) -> io::Result<[u8; 32]> {
        let mut names: HashMap<String, (PathBuf, [u8; 32])> = HashMap::new();
        let mut fingerprint = Sha256::new();
        fingerprint.update(b"dm-resources-v1\0");
        let mut buffer = [0u8; 64 * 1024];
        for request in requests {
            validate_archive_name(&request.archive_name)?;
            if names
                .get(&request.archive_name)
                .is_some_and(|(path, _)| path == &request.disk_path)
            {
                continue;
            }
            let mut file = fs::File::open(&request.disk_path).map_err(|error|
                io::Error::new(error.kind(), format!("{}: {error}", request.disk_path.display())))?;
            let length = file.metadata()?.len();
            let mut candidate = fingerprint.clone();
            candidate.update((request.archive_name.len() as u64).to_le_bytes());
            candidate.update(request.archive_name.as_bytes());
            candidate.update(length.to_le_bytes());
            let mut content = Sha256::new();
            let mut read_length = 0u64;
            loop {
                let count = file.read(&mut buffer)?;
                if count == 0 {
                    break;
                }
                read_length += count as u64;
                candidate.update(&buffer[..count]);
                content.update(&buffer[..count]);
            }
            if read_length != length {
                return Err(io::Error::new(
                    io::ErrorKind::InvalidData,
                    "resource changed while hashing",
                ));
            }
            let digest: [u8; 32] = content.finalize().into();
            if let Some((_, previous)) =
                names.insert(request.archive_name, (request.disk_path, digest))
            {
                if previous != digest {
                    return Err(invalid("resource archive name resolves to different data"));
                }
            } else {
                fingerprint = candidate;
            }
        }
        Ok(fingerprint.finalize().into())
    }

    /// Read every referenced asset exactly once. Duplicate authored names must
    /// identify the same file; distinct names are retained as separate RSC entries.
    pub fn load(requests: impl IntoIterator<Item = ResourceRequest>) -> io::Result<Self> {
        let mut inputs = Vec::new();
        let mut names: HashMap<String, (PathBuf, [u8; 32])> = HashMap::new();
        let mut fingerprint = Sha256::new();
        fingerprint.update(b"dm-resources-v1\0");
        for request in requests {
            validate_archive_name(&request.archive_name)?;
            if names
                .get(&request.archive_name)
                .is_some_and(|(path, _)| path == &request.disk_path)
            {
                continue;
            }
            let bytes = fs::read(&request.disk_path).map_err(|error|
                io::Error::new(error.kind(), format!("{}: {error}", request.disk_path.display())))?;
            let content_digest: [u8; 32] = Sha256::digest(&bytes).into();
            if let Some((_, previous)) = names.insert(
                request.archive_name.clone(),
                (request.disk_path.clone(), content_digest),
            ) {
                if previous == content_digest {
                    continue;
                }
                return Err(invalid("resource archive name resolves to different data"));
            }
            fingerprint.update((request.archive_name.len() as u64).to_le_bytes());
            fingerprint.update(request.archive_name.as_bytes());
            fingerprint.update((bytes.len() as u64).to_le_bytes());
            fingerprint.update(&bytes);
            let named = NamedResource::from_data(
                kind_for_name(&request.archive_name).as_byte(),
                request.archive_name.as_bytes().to_vec(),
                bytes,
                0,
                0,
            )?;
            inputs.push(ResourceInput {
                archive_name: request.archive_name,
                disk_path: request.disk_path,
                content_digest,
                named,
            });
        }
        Ok(Self {
            inputs,
            fingerprint: fingerprint.finalize().into(),
        })
    }

    pub fn rsc_bytes(&self) -> io::Result<Vec<u8>> {
        let resources = self.inputs.iter().map(|input| &input.named).collect::<Vec<_>>();
        byond_dmb::rsc::named_archive_bytes(&resources)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicU64, Ordering};
    static NEXT: AtomicU64 = AtomicU64::new(0);

    #[test]
    fn fingerprints_asset_changes_and_keeps_worktree_names_stable() {
        let root = std::env::temp_dir().join(format!(
            "dm-resources-{}-{}",
            std::process::id(),
            NEXT.fetch_add(1, Ordering::Relaxed)
        ));
        let first = root.join("first/icons");
        let second = root.join("second/icons");
        fs::create_dir_all(&first).unwrap();
        fs::create_dir_all(&second).unwrap();
        fs::write(first.join("test.png"), b"one").unwrap();
        fs::write(second.join("test.png"), b"one").unwrap();
        let request = |path| ResourceRequest {
            archive_name: "icons/test.png".into(),
            disk_path: path,
        };
        let a = ResourceSet::load([request(first.join("test.png"))]).unwrap();
        let b = ResourceSet::load([request(second.join("test.png"))]).unwrap();
        let repeated = ResourceSet::load([
            request(first.join("test.png")),
            request(first.join("test.png")),
        ])
        .unwrap();
        assert_eq!(a.fingerprint, repeated.fingerprint);
        assert_eq!(repeated.inputs.len(), 1);
        assert_eq!(a.fingerprint, b.fingerprint);
        assert_eq!(
            a.fingerprint,
            ResourceSet::fingerprint_requests([
                request(first.join("test.png")),
                request(first.join("test.png")),
                request(second.join("test.png")),
            ])
            .unwrap()
        );
        assert_eq!(a.rsc_bytes().unwrap(), b.rsc_bytes().unwrap());
        let decoded = byond_dmb::rsc::read_all(&mut a.rsc_bytes().unwrap().as_slice()).unwrap();
        assert_eq!(decoded, vec![Entry::Named(a.inputs[0].named.clone())]);
        fs::write(second.join("test.png"), b"two").unwrap();
        let changed = ResourceSet::load([request(second.join("test.png"))]).unwrap();
        assert_eq!(
            changed.fingerprint,
            ResourceSet::fingerprint_requests([request(second.join("test.png"))]).unwrap()
        );
        assert!(ResourceSet::fingerprint_requests([
            request(first.join("test.png")),
            request(second.join("test.png")),
        ])
        .is_err());
        assert_ne!(a.fingerprint, changed.fingerprint);
        assert_ne!(a.inputs[0].named.id, changed.inputs[0].named.id);
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn rejects_escaping_archive_names() {
        for name in [
            "../secret",
            "/absolute",
            "icons//bad",
            "icons/./bad",
            "icons\\bad",
        ] {
            assert!(validate_archive_name(name).is_err(), "{name}");
        }
    }
}
