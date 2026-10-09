//! Immutable output pairs. Acquisition and publication share one OS lock.
//!
//! Run slots are writable copies: the Phase 0 engine probe rejected read-only
//! hardlinks. Conventional output installation is intentionally a separate step.

use fs2::FileExt;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::fs::{self, File, OpenOptions};
use std::io::{self, Read};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Mutex;
use std::time::SystemTime;
use xxhash_rust::xxh3::{xxh3_128, Xxh3};

#[path = "publish_admission.rs"]
mod admission;
#[path = "publish_destinations.rs"]
mod destinations;
#[path = "publish_eviction.rs"]
mod eviction;
#[path = "publish_install.rs"]
mod install;
#[path = "publish_receipt.rs"]
mod receipt;
pub use receipt::InstallationReceipt;
#[path = "publish_io.rs"]
mod publication_io;
#[path = "publish_resource_stream.rs"]
mod resource_stream;
pub use eviction::EvictionResult;
use publication_io::{copy_hashed, write_owned, StagedPath};
pub use resource_stream::ResourcePin;

static TEMP_SEQUENCE: AtomicU64 = AtomicU64::new(0);

#[cfg(test)]
thread_local! {
    static FAULT: std::cell::RefCell<Option<(&'static str, usize)>> = const { std::cell::RefCell::new(None) };
}
#[cfg(test)]
fn publication_fault(point: &'static str) -> io::Result<()> {
    FAULT.with(|fault| {
        let mut fault = fault.borrow_mut();
        if let Some((selected, remaining)) = fault.as_mut() {
            if *selected == point {
                *remaining -= 1;
                if *remaining == 0 {
                    *fault = None;
                    return Err(io::Error::other(format!(
                        "injected publication interruption: {point}"
                    )));
                }
            }
        }
        Ok(())
    })
}

/// Select the shared output store on the destination drive. Callers may override
/// this for network volumes or installations without a writable drive root.
pub fn default_store_path(project: &Path) -> io::Result<PathBuf> {
    #[cfg(windows)]
    {
        let local = std::env::var_os("LOCALAPPDATA")
            .ok_or_else(|| io::Error::other("LOCALAPPDATA is absent; specify --output-store"))?;
        windows_store_path(project, Path::new(&local))
    }
    #[cfg(not(windows))]
    {
        Ok(project
            .parent()
            .ok_or_else(|| io::Error::other("manifest has no parent"))?
            .join(".dmbc/outputs"))
    }
}

#[cfg(windows)]
fn windows_store_path(project: &Path, local: &Path) -> io::Result<PathBuf> {
    use std::path::{Component, Prefix};
    let drive = |path: &Path| match path.components().next() {
        Some(Component::Prefix(prefix)) => match prefix.kind() {
            Prefix::Disk(letter) | Prefix::VerbatimDisk(letter) => {
                Some(letter.to_ascii_uppercase())
            }
            _ => None,
        },
        _ => None,
    };
    let destination = drive(project)
        .ok_or_else(|| io::Error::other("network output volume requires --output-store"))?;
    if drive(local) == Some(destination) {
        Ok(local.join("dmbd/pairs"))
    } else {
        Ok(PathBuf::from(format!("{}:\\", destination as char)).join(".dmbd/pairs"))
    }
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct OutputPair {
    pub version: u32,
    pub id: u128,
    pub dmb_bytes: u64,
    pub dmb_hash: u128,
    pub rsc_bytes: u64,
    pub rsc_hash: u128,
}

impl OutputPair {
    pub fn from_bytes(dmb: &[u8], rsc: &[u8]) -> Self {
        Self::from_hashes(
            dmb.len() as u64,
            xxh3_128(dmb),
            rsc.len() as u64,
            xxh3_128(rsc),
        )
    }

    fn from_hashes(dmb_bytes: u64, dmb_hash: u128, rsc_bytes: u64, rsc_hash: u128) -> Self {
        let mut identity = Vec::from(&b"dmbd-output-pair-v1\0"[..]);
        identity.extend_from_slice(&dmb_bytes.to_le_bytes());
        identity.extend_from_slice(&dmb_hash.to_le_bytes());
        identity.extend_from_slice(&rsc_bytes.to_le_bytes());
        identity.extend_from_slice(&rsc_hash.to_le_bytes());
        Self {
            version: 1,
            id: xxh3_128(&identity),
            dmb_bytes,
            dmb_hash,
            rsc_bytes,
            rsc_hash,
        }
    }

    pub fn name(&self) -> String {
        format!("{:032x}", self.id)
    }
}

pub struct PairStore {
    root: PathBuf,
    verified: Mutex<HashMap<u128, (OutputPair, Vec<crate::input_snapshot::Stamp>)>>,
    verified_resources: Mutex<HashMap<(u64, u128), crate::input_snapshot::Stamp>>,
}

/// Content identity of an archive already owned by this store. A cold linker
/// can reuse this handle without loading the archive into its output buffer.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct ResourceIdentity {
    pub bytes: u64,
    pub hash: u128,
}

#[derive(Serialize, Deserialize)]
struct BootVerification {
    schema: u32,
    boot: [u8; 16],
    pair: OutputPair,
    stamps: Vec<crate::input_snapshot::Stamp>,
}

// Failure to obtain a kernel-issued boot identity disables persistent trust.
#[cfg(windows)]
fn boot_identity() -> Option<[u8; 16]> {
    #[link(name = "ntdll")]
    unsafe extern "system" {
        fn NtQuerySystemInformation(
            class: u32,
            buffer: *mut std::ffi::c_void,
            length: u32,
            returned: *mut u32,
        ) -> i32;
    }
    // SYSTEM_BOOT_ENVIRONMENT_INFORMATION (phnt/ntexapi.h, class 90) starts
    // with the boot GUID. Use an
    // aligned buffer large enough for the firmware type and boot flags too.
    let mut buffer = [0u64; 8];
    let mut returned = 0;
    let status =
        unsafe { NtQuerySystemInformation(90, buffer.as_mut_ptr().cast(), 64, &mut returned) };
    if status < 0 || returned < 16 {
        return None;
    }
    let mut id = [0u8; 16];
    id[..8].copy_from_slice(&buffer[0].to_ne_bytes());
    id[8..].copy_from_slice(&buffer[1].to_ne_bytes());
    (id != [0; 16]).then_some(id)
}

#[cfg(not(windows))]
fn boot_identity() -> Option<[u8; 16]> {
    let bytes = fs::read("/proc/sys/kernel/random/boot_id").ok()?;
    Some(xxh3_128(&bytes).to_le_bytes())
}

fn stable_pair_stamps(path: &Path) -> io::Result<Vec<crate::input_snapshot::Stamp>> {
    use crate::input_snapshot::SnapshotProvider;
    ["pair.json", "deepquarry.dmb", "deepquarry.rsc"]
        .iter()
        .map(|name| crate::input_snapshot::FileSystemInputs.stamp(&path.join(name)))
        .collect()
}

impl PairStore {
    /// The caller selects a store on the output volume; no drive-root permission
    /// or junction behavior is assumed here.
    pub fn open(root: impl AsRef<Path>) -> io::Result<Self> {
        fs::create_dir_all(root.as_ref())?;
        let root = fs::canonicalize(root)?;
        for name in [
            "pairs",
            "resources",
            "sessions",
            "temporary",
            "quarantine",
            "verified",
            "resource-pins",
        ] {
            fs::create_dir_all(root.join(name))?;
        }
        Ok(Self {
            root,
            verified: Mutex::new(HashMap::new()),
            verified_resources: Mutex::new(HashMap::new()),
        })
    }

    /// First use after a boot hashes the pair. Later processes may reuse an
    /// authenticated boot receipt with unchanged file identities and stamps.
    /// Exact mode deliberately hashes every use.
    /// The store lock covers validation and use, including future eviction.
    pub fn verify(&self, id: u128, exact: bool) -> io::Result<OutputPair> {
        let _lock = self.lock()?;
        self.verify_locked(id, exact)
    }

    fn verify_locked(&self, id: u128, exact: bool) -> io::Result<OutputPair> {
        let source = self.root.join("pairs").join(format!("{id:032x}"));
        let stamps = pair_stamps(&source)?;
        let boot = boot_identity();
        let stable = stable_pair_stamps(&source)?;
        let receipt_path = self.root.join("verified").join(format!("{id:032x}.json"));
        if !exact {
            let memo = self
                .verified
                .lock()
                .map_err(|_| invalid("pair verification lock poisoned"))?;
            if let Some((pair, old)) = memo.get(&id) {
                if *old == stable && stable.iter().all(|stamp| stamp.file_id.is_some()) {
                    return Ok(pair.clone());
                }
            }
            if let Some(boot) = boot {
                if stable.iter().all(|stamp| stamp.file_id.is_some()) {
                    if let Ok(file) = File::open(&receipt_path) {
                        let mut bytes = Vec::new();
                        let read = file.take(65537).read_to_end(&mut bytes);
                        if read.is_ok() && bytes.len() <= 65536 {
                            if let Ok(receipt) = serde_json::from_slice::<BootVerification>(&bytes)
                            {
                                let canonical = OutputPair::from_hashes(
                                    receipt.pair.dmb_bytes,
                                    receipt.pair.dmb_hash,
                                    receipt.pair.rsc_bytes,
                                    receipt.pair.rsc_hash,
                                );
                                if receipt.schema == 1
                                    && receipt.boot == boot
                                    && receipt.pair.id == id
                                    && receipt.pair == canonical
                                    && receipt.stamps == stable
                                    && stable[1].size == receipt.pair.dmb_bytes
                                    && stable[2].size == receipt.pair.rsc_bytes
                                {
                                    let manifest: OutputPair = serde_json::from_slice(&fs::read(
                                        source.join("pair.json"),
                                    )?)
                                    .map_err(invalid)?;
                                    if manifest == receipt.pair
                                        && stable_pair_stamps(&source)? == stable
                                    {
                                        drop(memo);
                                        self.verified
                                            .lock()
                                            .map_err(|_| {
                                                invalid("pair verification lock poisoned")
                                            })?
                                            .insert(id, (manifest.clone(), stable));
                                        return Ok(manifest);
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        let pair = validate_directory(&source, id)?;
        if pair_stamps(&source)? != stamps || stable_pair_stamps(&source)? != stable {
            return Err(invalid("immutable pair changed during verification"));
        }
        self.remember_verified(&pair, stable)?;
        Ok(pair)
    }

    fn lock(&self) -> io::Result<File> {
        let file = OpenOptions::new()
            .read(true)
            .write(true)
            .create(true)
            .truncate(false)
            .open(self.root.join("store.lock"))?;
        file.lock_exclusive()?;
        Ok(file)
    }

    fn temporary(&self, prefix: &str) -> io::Result<PathBuf> {
        loop {
            let sequence = TEMP_SEQUENCE.fetch_add(1, Ordering::Relaxed);
            let path = self
                .root
                .join("temporary")
                .join(format!("{prefix}-{}-{sequence}", std::process::id()));
            match fs::create_dir(&path) {
                Ok(()) => return Ok(path),
                Err(error) if error.kind() == io::ErrorKind::AlreadyExists => continue,
                Err(error) => return Err(error),
            }
        }
    }

    /// Writes only new immutable content. The last-three record is updated while
    /// the store lock is still held, closing the publication/eviction race.
    pub fn publish(&self, session: u128, dmb: &[u8], rsc: &[u8]) -> io::Result<OutputPair> {
        self.publish_exact(session, dmb, rsc, false)
    }

    /// Exact requests authenticate existing store bytes even with valid boot receipts.
    pub fn publish_exact(
        &self,
        session: u128,
        dmb: &[u8],
        rsc: &[u8],
        exact: bool,
    ) -> io::Result<OutputPair> {
        let pair = OutputPair::from_bytes(dmb, rsc);
        self.publish_inner(session, dmb, pair, Some(rsc), exact)
    }

    /// Compose a new DMB with a previously published archive. Authentication
    /// remains mandatory, but no RSC-sized allocation or archive rewrite occurs.
    pub fn publish_with_resource(
        &self,
        session: u128,
        dmb: &[u8],
        resource: ResourceIdentity,
    ) -> io::Result<OutputPair> {
        self.publish_with_resource_exact(session, dmb, resource, false)
    }

    pub fn publish_with_resource_exact(
        &self,
        session: u128,
        dmb: &[u8],
        resource: ResourceIdentity,
        exact: bool,
    ) -> io::Result<OutputPair> {
        let pair = OutputPair::from_hashes(
            dmb.len() as u64,
            xxh3_128(dmb),
            resource.bytes,
            resource.hash,
        );
        self.publish_inner(session, dmb, pair, None, exact)
    }

    /// Publish the immutable encoder owner without hashing the DMB buffer again.
    /// Its private byte/hash pairing cannot be manufactured from a mutable Vec.
    pub fn publish_encoded_exact(
        &self,
        session: u128,
        image: &byond_dmb::dmb::EncodedDmb,
        rsc: &[u8],
        exact: bool,
    ) -> io::Result<OutputPair> {
        let pair = OutputPair::from_hashes(
            image.len() as u64,
            image.content_hash(),
            rsc.len() as u64,
            xxh3_128(rsc),
        );
        self.publish_inner(session, image.bytes(), pair, Some(rsc), exact)
    }

    /// Both encoded owners supply immutable streaming hashes; neither buffer
    /// is scanned again before writing the new immutable pair.
    pub fn publish_images_exact(
        &self,
        session: u128,
        image: &byond_dmb::dmb::EncodedDmb,
        archive: &byond_dmb::rsc::EncodedRsc,
        exact: bool,
    ) -> io::Result<OutputPair> {
        let pair = OutputPair::from_hashes(
            image.len() as u64,
            image.content_hash(),
            archive.len() as u64,
            archive.content_hash(),
        );
        self.publish_inner(session, image.bytes(), pair, Some(archive.bytes()), exact)
    }

    /// Reuse a stored resource identity with a certified immutable encoder owner.
    pub fn publish_encoded_with_resource_exact(
        &self,
        session: u128,
        image: &byond_dmb::dmb::EncodedDmb,
        resource: ResourceIdentity,
        exact: bool,
    ) -> io::Result<OutputPair> {
        let pair = OutputPair::from_hashes(
            image.len() as u64,
            image.content_hash(),
            resource.bytes,
            resource.hash,
        );
        self.publish_inner(session, image.bytes(), pair, None, exact)
    }

    fn publish_inner(
        &self,
        session: u128,
        dmb: &[u8],
        pair: OutputPair,
        rsc: Option<&[u8]>,
        exact: bool,
    ) -> io::Result<OutputPair> {
        let _lock = self.lock()?;
        let destination = self.root.join("pairs").join(pair.name());
        if let Ok(existing) = self.verify_locked(pair.id, exact) {
            if existing != pair {
                return Err(invalid("output pair identity collision"));
            }
            self.record_session(session, pair.id)?;
            return Ok(pair);
        }
        let temp_guard = StagedPath::new(self.temporary("pair")?);
        let temp = temp_guard.path();
        let dmb_stamp = write_owned(&temp.join("deepquarry.dmb"), dmb)?;
        #[cfg(test)]
        publication_fault("pair_dmb_written")?;
        let resource = self
            .root
            .join("resources")
            .join(format!("{:032x}-{}.rsc", pair.rsc_hash, pair.rsc_bytes));
        let identity = ResourceIdentity {
            bytes: pair.rsc_bytes,
            hash: pair.rsc_hash,
        };
        let resource_stamp = if resource.exists() {
            self.authenticate_resource(&resource, identity, exact)?
        } else {
            let rsc =
                rsc.ok_or_else(|| invalid("shared RSC identity is absent from this store"))?;
            let resource_guard = StagedPath::new(self.temporary("resource")?);
            let staged = resource_guard.path().join("archive.rsc");
            let stamp = write_owned(&staged, rsc)?;
            #[cfg(test)]
            publication_fault("resource_written")?;
            let mut permissions = fs::metadata(&staged)?.permissions();
            permissions.set_readonly(true);
            fs::set_permissions(&staged, permissions)?;

            fs::rename(&staged, &resource)?;
            #[cfg(test)]
            publication_fault("resource_renamed")?;
            self.remember_resource(&resource, identity, &stamp)?
        };
        let rsc_stamp = if fs::hard_link(&resource, temp.join("deepquarry.rsc")).is_ok() {
            resource_stamp.clone()
        } else {
            copy_hashed(
                &resource,
                &temp.join("deepquarry.rsc"),
                (pair.rsc_bytes, pair.rsc_hash),
            )?
        };
        use crate::input_snapshot::SnapshotProvider;
        if crate::input_snapshot::FileSystemInputs.stamp(&resource)? != resource_stamp {
            return Err(invalid("resource inode changed during pair publication"));
        }
        let manifest_stamp = write_json(&temp.join("pair.json"), &pair)?;
        #[cfg(test)]
        publication_fault("pair_manifest_written")?;
        let owned_stamps = vec![manifest_stamp, dmb_stamp, rsc_stamp];
        if stable_pair_stamps(temp)? != owned_stamps {
            return Err(invalid("owned pair changed before sealing"));
        }
        for name in ["deepquarry.dmb", "deepquarry.rsc", "pair.json"] {
            let path = temp.join(name);
            let mut permissions = fs::metadata(&path)?.permissions();
            permissions.set_readonly(true);
            fs::set_permissions(path, permissions)?;
        }
        if destination.exists() {
            // Do not change attributes: existing hardlink readers may exist.
            let quarantine = StagedPath::new(self.temporary("quarantine")?);
            let name = quarantine.path().file_name().expect("temporary basename");
            fs::rename(&destination, self.root.join("quarantine").join(name))?;
        }
        fs::rename(temp, &destination)?;
        #[cfg(test)]
        publication_fault("pair_directory_renamed")?;
        if stable_pair_stamps(&destination)? != owned_stamps {
            return Err(invalid("owned pair inode changed during publication"));
        }
        self.remember_verified(&pair, owned_stamps)?;
        self.record_session(session, pair.id)?;
        #[cfg(test)]
        publication_fault("pair_session_committed")?;
        Ok(pair)
    }

    fn record_session(&self, session: u128, pair: u128) -> io::Result<()> {
        let path = self
            .root
            .join("sessions")
            .join(format!("{session:032x}.json"));
        let mut pairs: Vec<u128> = match fs::read(&path) {
            Ok(bytes) => serde_json::from_slice(&bytes).map_err(invalid)?,
            Err(error) if error.kind() == io::ErrorKind::NotFound => Vec::new(),
            Err(error) => return Err(error),
        };
        pairs.retain(|&id| id != pair);
        pairs.insert(0, pair);
        pairs.truncate(3);
        let staged = StagedPath::new(self.temporary("session")?);
        let temp = staged.path().join("record.json");
        write_json(&temp, &pairs)?;
        #[cfg(test)]
        publication_fault("session_staged")?;
        // Session records are mutable hints protected by the store lock. Keep
        // the old complete record until replacement succeeds on every platform.
        atomic_replace(&temp, &path)
    }

    /// Authenticate acquisition through the same boot/stamp proof as compile
    /// reuse, then create a writable independent runtime slot.
    pub fn acquire(&self, id: u128, slots: impl AsRef<Path>) -> io::Result<PathBuf> {
        let _lock = self.lock()?;
        let source = self.root.join("pairs").join(format!("{id:032x}"));
        let pair = self.verify_locked(id, false)?;
        fs::create_dir_all(slots.as_ref())?;
        let slot = loop {
            let sequence = TEMP_SEQUENCE.fetch_add(1, Ordering::Relaxed);
            let path = slots
                .as_ref()
                .join(format!("slot-{}-{sequence}", std::process::id()));
            match fs::create_dir(&path) {
                Ok(()) => break path,
                Err(error) if error.kind() == io::ErrorKind::AlreadyExists => continue,
                Err(error) => return Err(error),
            }
        };
        let slot_cleanup = StagedPath::new(slot.clone());
        for name in ["deepquarry.dmb", "deepquarry.rsc"] {
            let destination = slot.join(name);
            let expected = if name == "deepquarry.dmb" {
                (pair.dmb_bytes, pair.dmb_hash)
            } else {
                (pair.rsc_bytes, pair.rsc_hash)
            };
            copy_hashed(&source.join(name), &destination, expected)?;
            #[cfg(test)]
            publication_fault("slot_copy_finished")?;
        }
        write_json(&slot.join("pair.json"), &pair)?;
        #[cfg(test)]
        publication_fault("slot_manifest_written")?;
        fs::write(slot.join("slot-complete"), pair.name())?;
        #[cfg(test)]
        publication_fault("slot_complete_written")?;
        slot_cleanup.preserve();
        Ok(slot)
    }

    /// Conventional output paths are compatibility copies, never run-slot
    /// authority. Publish RSC, DMB, then the marker; a crash can leave copies
    /// mismatched, and the next successful installation repairs them.
    pub fn install(&self, id: u128, dmb: &Path, rsc: &Path, marker: &Path) -> io::Result<()> {
        self.install_exact(id, dmb, rsc, marker, false)
    }

    pub fn install_exact(
        &self,
        id: u128,
        dmb: &Path,
        rsc: &Path,
        marker: &Path,
        exact: bool,
    ) -> io::Result<()> {
        self.install_receipt_exact(id, dmb, rsc, marker, exact)
            .map(|_| ())
    }

    pub fn install_receipt_exact(
        &self,
        id: u128,
        dmb: &Path,
        rsc: &Path,
        marker: &Path,
        exact: bool,
    ) -> io::Result<InstallationReceipt> {
        destinations::distinct([dmb, rsc, marker])?;
        let _lock = self.lock()?;
        let source = self.root.join("pairs").join(format!("{id:032x}"));
        let pair = self.verify_locked(id, exact)?;
        let rsc_receipt = install::resource_receipt(
            &source.join("deepquarry.rsc"),
            rsc,
            (pair.rsc_bytes, pair.rsc_hash),
        )?;
        #[cfg(test)]
        publication_fault("install_rsc_replaced")?;
        let dmb_receipt = install::conventional_receipt(
            &source.join("deepquarry.dmb"),
            dmb,
            (pair.dmb_bytes, pair.dmb_hash),
        )?;
        #[cfg(test)]
        publication_fault("install_dmb_replaced")?;
        let staged = temporary_file(marker)?;
        let _cleanup = StagedPath::new(staged.clone());
        let (marker_stamp, marker_hash) = write_json_hashed(&staged, &pair)?;
        #[cfg(test)]
        publication_fault("install_marker_staged")?;
        atomic_replace(&staged, marker)?;
        let marker_receipt =
            receipt::InstalledFile::after_replace(marker, marker_stamp, marker_hash)?;
        Ok(InstallationReceipt {
            files: vec![rsc_receipt, dmb_receipt, marker_receipt],
            exact,
        })
    }
}

fn temporary_file(destination: &Path) -> io::Result<PathBuf> {
    let parent = destination
        .parent()
        .filter(|path| !path.as_os_str().is_empty())
        .unwrap_or(Path::new("."));
    fs::create_dir_all(parent)?;
    loop {
        let sequence = TEMP_SEQUENCE.fetch_add(1, Ordering::Relaxed);
        let path = parent.join(format!(
            ".dmbd-install-{}-{sequence}.tmp",
            std::process::id()
        ));
        match OpenOptions::new().write(true).create_new(true).open(&path) {
            Ok(_) => return Ok(path),
            Err(error) if error.kind() == io::ErrorKind::AlreadyExists => continue,
            Err(error) => return Err(error),
        }
    }
}

fn replace_copy_receipt(
    source: &Path,
    destination: &Path,
    expected: (u64, u128),
) -> io::Result<receipt::InstalledFile> {
    let _profile = dm_profile::stage("publication.install_copy");
    let staged = temporary_file(destination)?;
    let _cleanup = StagedPath::new(staged.clone());
    let stamp = copy_hashed(source, &staged, expected)?;
    #[cfg(test)]
    publication_fault("install_copy_staged")?;
    atomic_replace(&staged, destination)?;
    receipt::InstalledFile::after_replace(destination, stamp, expected.1)
}

#[cfg(not(windows))]
fn atomic_replace(source: &Path, destination: &Path) -> io::Result<()> {
    fs::rename(source, destination)
}

#[cfg(windows)]
fn atomic_replace(source: &Path, destination: &Path) -> io::Result<()> {
    use std::os::windows::ffi::OsStrExt;
    #[link(name = "kernel32")]
    extern "system" {
        fn MoveFileExW(existing: *const u16, replacement: *const u16, flags: u32) -> i32;
    }
    fn wide(path: &Path) -> io::Result<Vec<u16>> {
        let mut result: Vec<_> = path.as_os_str().encode_wide().collect();
        if result.contains(&0) {
            return Err(invalid("path contains NUL"));
        }
        result.push(0);
        Ok(result)
    }
    let source = wide(source)?;
    let destination = wide(destination)?;
    // Both terminated UTF-16 buffers outlive the call. REPLACE_EXISTING preserves
    // the old destination if Windows rejects replacement because it is locked.
    let result = unsafe { MoveFileExW(source.as_ptr(), destination.as_ptr(), 1) };
    if result == 0 {
        Err(io::Error::last_os_error())
    } else {
        Ok(())
    }
}

fn write_json(path: &Path, value: &impl Serialize) -> io::Result<crate::input_snapshot::Stamp> {
    write_json_hashed(path, value).map(|(stamp, _)| stamp)
}
fn write_json_hashed(
    path: &Path,
    value: &impl Serialize,
) -> io::Result<(crate::input_snapshot::Stamp, u128)> {
    let bytes = serde_json::to_vec(value).map_err(invalid)?;
    let digest = xxh3_128(&bytes);
    use std::io::Write;
    let mut file = OpenOptions::new()
        .write(true)
        .create(true)
        .truncate(true)
        .open(path)?;
    dm_profile::io_call(|| file.write_all(&bytes), |_| (0, bytes.len() as u64))?;
    Ok((publication_io::finish_owned(file, path)?, digest))
}

fn invalid(error: impl std::fmt::Display) -> io::Error {
    io::Error::new(io::ErrorKind::InvalidData, error.to_string())
}

fn file_identity(path: &Path) -> io::Result<(u64, u128)> {
    let _profile = dm_profile::stage("publication.authenticate_file");
    let mut file = File::open(path)?;
    let mut hasher = Xxh3::new();
    let mut bytes = 0u64;
    let mut buffer = [0u8; 65536];
    loop {
        let count = dm_profile::io_call(|| file.read(&mut buffer), |count| (*count as u64, 0))?;
        if count == 0 {
            break;
        }
        bytes += count as u64;
        hasher.update(&buffer[..count]);
    }
    Ok((bytes, hasher.digest128()))
}

fn pair_stamps(path: &Path) -> io::Result<Vec<(u64, SystemTime)>> {
    ["pair.json", "deepquarry.dmb", "deepquarry.rsc"]
        .iter()
        .map(|name| {
            let metadata = fs::metadata(path.join(name))?;
            Ok((metadata.len(), metadata.modified()?))
        })
        .collect()
}

fn validate_directory(path: &Path, id: u128) -> io::Result<OutputPair> {
    let pair: OutputPair =
        serde_json::from_slice(&fs::read(path.join("pair.json"))?).map_err(invalid)?;
    if pair.version != 1 || pair.id != id {
        return Err(invalid("unsupported or mismatched pair manifest"));
    }
    let (dmb_bytes, dmb_hash) = file_identity(&path.join("deepquarry.dmb"))?;
    let (rsc_bytes, rsc_hash) = file_identity(&path.join("deepquarry.rsc"))?;
    let actual = OutputPair::from_hashes(dmb_bytes, dmb_hash, rsc_bytes, rsc_hash);
    if actual != pair {
        return Err(invalid("output pair bytes do not match manifest"));
    }
    Ok(pair)
}

#[cfg(test)]
#[path = "publish_tests.rs"]
mod tests;
