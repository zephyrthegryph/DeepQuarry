//! Resource inputs shared by the direct compiler, its cache key, and RSC writer.
//! Callers resolve DM file literals to an authored archive name and a disk path.

#[cfg(test)]
use byond_dmb::rsc::Entry;
use byond_dmb::rsc::{NamedResource, ResourceKind};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::collections::HashMap;
use std::fs;
use std::io;
use std::path::{Component, Path, PathBuf};

mod archive;
mod input_cache;
pub use archive::{prepare_archive, PreparedArchive, ArchiveLease};
pub use input_cache::{ResourceFingerprintCache, ResourceFingerprintStats};

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
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

/// Payload-free facts used only with an independently verified immutable RSC.
/// The catalog is produced from loaded, collision-checked inputs; it is not an
/// alternative proof that an arbitrary resource payload has the claimed ID.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct ResourceDescriptor {
    pub archive_name: String,
    pub id: u32,
    pub kind: u8,
    pub content_digest: [u8; 32],
}
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct ResourceCatalog {
    pub fingerprint: [u8; 32],
    pub entries: Vec<ResourceDescriptor>,
}
impl ResourceCatalog {
    /// Dense resource layout, independent of content CRC values. Identical
    /// content aliases share a table slot; their equivalence partition remains
    /// part of this projection even when all CRC values change.
    pub fn layout_fingerprint(&self) -> [u8; 32] {
        let mut digest = Sha256::new();
        digest.update(b"dm-resource-layout-projection-v1\0");
        digest.update((self.entries.len() as u64).to_le_bytes());
        let mut groups = HashMap::new();
        for entry in &self.entries {
            let next = groups.len() as u64;
            let group = *groups.entry((entry.id, entry.kind)).or_insert(next);
            digest.update((entry.archive_name.len() as u64).to_le_bytes());
            digest.update(entry.archive_name.as_bytes());
            digest.update([entry.kind]); digest.update(group.to_le_bytes());
        }
        digest.finalize().into()
    }

    /// Patch only physical content IDs when the exact dense layout is preserved.
    /// No mutation occurs on failure. An independently keyed builtin prefix is
    /// preserved only if catalog attachment cannot alias against that prefix.
    pub fn remap_if_compatible(&self, old: &Self, dmb: &mut byond_dmb::dmb::Dmb) -> bool {
        if self.validate().is_err() || old.validate().is_err()
            || self.entries.len() != old.entries.len() { return false; }
        let mut forward = HashMap::new(); let mut reverse = HashMap::new();
        let mut old_rows = Vec::new(); let mut new_rows = Vec::new();
        for (old_entry, new_entry) in old.entries.iter().zip(&self.entries) {
            if old_entry.archive_name != new_entry.archive_name || old_entry.kind != new_entry.kind { return false; }
            let prior = (old_entry.id, old_entry.kind);
            let current = (new_entry.id, new_entry.kind);
            if forward.get(&prior).is_some_and(|mapped| *mapped != current)
                || reverse.get(&current).is_some_and(|mapped| *mapped != prior) { return false; }
            if forward.insert(prior,current).is_none() {
                old_rows.push(byond_dmb::dmb::ResourceRef {id:prior.0,kind:prior.1});
                new_rows.push(byond_dmb::dmb::ResourceRef {id:current.0,kind:current.1});
            }
            reverse.insert(current,prior);
        }
        let Some(prefix) = dmb.resources.len().checked_sub(old_rows.len()) else { return false; };
        if dmb.resources[prefix..] != old_rows { return false; }
        if dmb.resources[..prefix].iter().any(|row|
            forward.contains_key(&(row.id,row.kind)) || reverse.contains_key(&(row.id,row.kind))) {
            return false;
        }
        dmb.resources[prefix..].clone_from_slice(&new_rows);
        true
    }

    /// Exact resource assignment projection consumed by bytecode generation.
    /// CRC changes invalidate this exact projection. Asset-only reuse should
    /// use layout_fingerprint plus remap_if_compatible instead. Entry order
    /// matters because attachment assigns dense resource table indices in order.
    /// Callers must still validate this catalog and independently verify the RSC.
    pub fn bytecode_fingerprint(&self) -> [u8; 32] {
        let mut digest = Sha256::new();
        digest.update(b"dm-resource-bytecode-projection-v1\0");
        digest.update((self.entries.len() as u64).to_le_bytes());
        for entry in &self.entries {
            digest.update((entry.archive_name.len() as u64).to_le_bytes());
            digest.update(entry.archive_name.as_bytes());
            digest.update(entry.id.to_le_bytes());
            digest.update([entry.kind]);
        }
        digest.finalize().into()
    }

    pub fn validate(&self) -> io::Result<()> {
        let mut names = HashMap::new();
        let mut identities = HashMap::new();
        for entry in &self.entries {
            validate_archive_name(&entry.archive_name)?;
            if names.insert(&entry.archive_name, ()).is_some() {
                return Err(invalid("duplicate resource catalog name"));
            }
            if identities
                .insert((entry.id, entry.kind), entry.content_digest)
                .is_some_and(|previous| previous != entry.content_digest)
            {
                return Err(invalid("resource catalog ID collision"));
            }
        }
        Ok(())
    }
    pub fn attach(
        &self,
        dmb: &mut byond_dmb::dmb::Dmb,
    ) -> io::Result<Vec<byond_dmb::ids::ResourceId>> {
        self.validate()?;
        let mut ids: HashMap<_, _> = dmb
            .resources
            .iter()
            .enumerate()
            .map(|(index, entry)| ((entry.id, entry.kind), index as u32))
            .collect();
        self.entries
            .iter()
            .map(|entry| {
                let key = (entry.id, entry.kind);
                let index = if let Some(index) = ids.get(&key) {
                    *index
                } else {
                    let index = u32::try_from(dmb.resources.len())
                        .map_err(|_| invalid("resource index exceeds u32"))?;
                    dmb.resources.push(byond_dmb::dmb::ResourceRef {
                        id: entry.id,
                        kind: entry.kind,
                    });
                    ids.insert(key, index);
                    index
                };
                byond_dmb::ids::ResourceId::from_raw(index)
                    .ok_or_else(|| invalid("reserved resource index"))
            })
            .collect()
    }
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
    pub fn catalog(&self) -> io::Result<ResourceCatalog> {
        let entries = dm_work::map_ordered(
            &self.inputs,
            dm_work::WorkLimits::configured(),
            |input| {
                input
                    .archive_name
                    .len()
                    .saturating_mul(2)
                    .saturating_add(1024)
            },
            |input| {
                if input.named.content_id()? != input.named.id {
                    return Err(invalid("resource content ID mismatch"));
                }
                Ok(ResourceDescriptor {
                    archive_name: input.archive_name.clone(),
                    id: input.named.id,
                    kind: input.named.kind,
                    content_digest: input.content_digest,
                })
            },
        )
        .map_err(input_cache::work_error)?
        .into_iter()
        .collect::<io::Result<Vec<_>>>()?;
        let catalog = ResourceCatalog {
            fingerprint: self.fingerprint,
            entries,
        };
        catalog.validate()?;
        Ok(catalog)
    }
    /// Match the loaded-set identity while retaining only a small read buffer.
    /// Cached build checks need asset identity, not an in-memory RSC payload.
    pub fn fingerprint_requests(
        requests: impl IntoIterator<Item = ResourceRequest>,
    ) -> io::Result<[u8; 32]> {
        ResourceFingerprintCache::default().fingerprint_requests(requests)
    }

    /// Read every referenced asset exactly once. Duplicate authored names must
    /// identify the same file; distinct names are retained as separate RSC entries.
    pub fn load(requests: impl IntoIterator<Item = ResourceRequest>) -> io::Result<Self> {
        Self::load_with_limits(requests, dm_work::WorkLimits::configured())
    }

    pub fn load_with_limits(
        requests: impl IntoIterator<Item = ResourceRequest>,
        limits: dm_work::WorkLimits,
    ) -> io::Result<Self> {
        use std::io::Read;
        let mut seen = std::collections::HashSet::new();
        let mut jobs = Vec::new();
        for request in requests {
            validate_archive_name(&request.archive_name)?;
            if seen.insert((request.archive_name.clone(), request.disk_path.clone())) {
                let length = usize::try_from(fs::metadata(&request.disk_path)?.len())
                    .map_err(|_| invalid("resource size exceeds usize"))?;
                jobs.push((request, length));
            }
        }
        let loaded = dm_work::map_ordered(
            &jobs,
            limits,
            |(_, len)| len.saturating_mul(2).saturating_add(64 * 1024),
            |(request, _)| {
                let before = dm_host::file_stamp::capture(&request.disk_path);
                let file = fs::File::open(&request.disk_path).map_err(|error| {
                    io::Error::new(
                        error.kind(),
                        format!("{}: {error}", request.disk_path.display()),
                    )
                })?;
                let length = file.metadata()?.len();
                let limit = limits.max_active_bytes.saturating_sub(64 * 1024) / 2;
                let mut bytes = Vec::new();
                file.take(limit as u64 + 1).read_to_end(&mut bytes)?;
                if bytes.len() > limit {
                    return Err(invalid("resource exceeds work allocation budget"));
                }
                if bytes.len() as u64 != length
                    || before.as_ref().is_some_and(|stamp| {
                        dm_host::file_stamp::capture(&request.disk_path).as_ref() != Some(stamp)
                    })
                {
                    return Err(io::Error::new(
                        io::ErrorKind::InvalidData,
                        format!(
                            "{}: resource changed while loading",
                            request.disk_path.display()
                        ),
                    ));
                }
                let content_digest: [u8; 32] = Sha256::digest(&bytes).into();
                let named = NamedResource::from_data(
                    kind_for_name(&request.archive_name).as_byte(),
                    request.archive_name.as_bytes().to_vec(),
                    bytes,
                    0,
                    0,
                )?;
                Ok(ResourceInput {
                    archive_name: request.archive_name.clone(),
                    disk_path: request.disk_path.clone(),
                    content_digest,
                    named,
                })
            },
        )
        .map_err(input_cache::work_error)?;
        let mut inputs = Vec::new();
        let mut names: HashMap<String, (PathBuf, [u8; 32])> = HashMap::new();
        for result in loaded {
            let input = result?;
            if let Some((_, previous)) = names.insert(
                input.archive_name.clone(),
                (input.disk_path.clone(), input.content_digest),
            ) {
                if previous == input.content_digest {
                    continue;
                }
                return Err(invalid("resource archive name resolves to different data"));
            }
            inputs.push(input);
        }
        let fingerprint = input_cache::fingerprint(inputs.iter().map(|input| {
            (
                input.archive_name.as_str(),
                input.named.data.len() as u64,
                input.content_digest,
            )
        }));
        Ok(Self {
            inputs,
            fingerprint,
        })
    }

    pub fn rsc_bytes(&self) -> io::Result<Vec<u8>> {
        let resources = self
            .inputs
            .iter()
            .map(|input| &input.named)
            .collect::<Vec<_>>();
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

    #[test]
    fn ordered_parallel_resources_match_and_disk_cache_reuses_proven_hashes() {
        let root = std::env::temp_dir().join(format!(
            "dm-resource-cache-{}-{}",
            std::process::id(),
            NEXT.fetch_add(1, Ordering::Relaxed)
        ));
        fs::create_dir_all(&root).unwrap();
        let requests: Vec<_> = (0..6)
            .map(|index| {
                let path = root.join(format!("asset{index}.txt"));
                fs::write(&path, format!("resource {index}")).unwrap();
                ResourceRequest {
                    archive_name: format!("data/{index}.txt"),
                    disk_path: path,
                }
            })
            .collect();
        let serial = ResourceSet::load_with_limits(
            requests.clone(),
            dm_work::WorkLimits {
                workers: 1,
                max_active_bytes: 1024 * 1024,
            },
        )
        .unwrap();
        let parallel = ResourceSet::load_with_limits(
            requests.clone(),
            dm_work::WorkLimits {
                workers: 4,
                max_active_bytes: 1024 * 1024,
            },
        )
        .unwrap();
        assert_eq!(serial.fingerprint, parallel.fingerprint);
        assert_eq!(serial.rsc_bytes().unwrap(), parallel.rsc_bytes().unwrap());
        let cache_root = root.join("cache");
        fs::create_dir_all(&cache_root).unwrap();
        let proven = {
            let mut cache = ResourceFingerprintCache::open(&cache_root);
            assert_eq!(
                cache.fingerprint_requests(requests.clone()).unwrap(),
                parallel.fingerprint
            );
            assert_eq!(cache.stats().files_hashed, 6);
            cache.verified_stamps(&requests).is_some()
        };
        let mut cache = ResourceFingerprintCache::open(&cache_root);
        assert_eq!(
            cache.fingerprint_requests(requests.clone()).unwrap(),
            parallel.fingerprint
        );
        if proven {
            assert_eq!(cache.stats().files_hashed, 0);
            assert_eq!(cache.stats().proof_hits, 6);
            assert_eq!(cache.stats().disk_records, 6);
        }
        let modified = fs::metadata(&requests[0].disk_path)
            .unwrap()
            .modified()
            .unwrap();
        fs::write(&requests[0].disk_path, b"resource X").unwrap();
        fs::OpenOptions::new()
            .write(true)
            .open(&requests[0].disk_path)
            .unwrap()
            .set_modified(modified)
            .unwrap();
        let changed = cache.fingerprint_requests(requests.clone()).unwrap();
        assert_ne!(changed, parallel.fingerprint);
        assert!(cache.stats().files_hashed >= 1);
        assert_eq!(changed, ResourceSet::load(requests).unwrap().fingerprint);
        drop(cache);
        fs::remove_dir_all(root).unwrap();
    }
}
