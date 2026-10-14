//! One validation-pass directory proofs. Never retain this view across publication
//! restats: payload reads and digests always use live FileSystemInputs.
use crate::input_snapshot::{FileSystemInputs, FolderListing, SnapshotProvider, Stamp};
use dm_preprocess::regions::canonical_path;
use std::{
    collections::{BTreeMap, BTreeSet, HashMap, HashSet},
    io,
    path::{Path, PathBuf},
    sync::atomic::{AtomicU64, Ordering},
};

pub struct BulkFileSystemProofs {
    directories: BTreeMap<PathBuf, DirectoryProof>,
    exact_files: HashMap<PathBuf, Stamp>,
    exact_missing_files: HashSet<PathBuf>,
    missing_directories: BTreeSet<PathBuf>,
    capture_missing: usize,
    capture_errors: usize,
    capture_budget_denials: usize,
    exact_path_hits: AtomicU64,
    fallback_directories: usize,
    stamp_hits: AtomicU64,
    negative_proofs: AtomicU64,
    live_stamp_fallbacks: AtomicU64,
    folder_hits: AtomicU64,
    folder_fallbacks: AtomicU64,
}
#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub struct ProofCounts {
    pub bulk_directories: usize,
    pub fallback_directories: usize,
    pub proven_missing_directories: usize,
    pub capture_missing: usize,
    pub capture_errors: usize,
    pub capture_budget_denials: usize,
    pub stamp_hits: u64,
    pub exact_path_hits: u64,
    pub negative_proofs: u64,
    pub live_stamp_fallbacks: u64,
    pub folder_hits: u64,
    pub folder_fallbacks: u64,
}
struct DirectoryProof {
    entries: BTreeMap<String, Option<Stamp>>,
    aliases: BTreeSet<String>,
    ascii: bool,
    charged: usize,
}
impl DirectoryProof {
    fn proves_absent(&self, name: &str) -> bool {
        self.ascii
            && ordinary_negative_name(name)
            && !self.entries.contains_key(name)
            && !self.aliases.contains(&name.to_ascii_lowercase())
    }
}
impl BulkFileSystemProofs {
    pub fn capture(
        paths: impl IntoIterator<Item = PathBuf>,
        folders: impl IntoIterator<Item = PathBuf>,
    ) -> Self {
        Self::capture_canonical(
            paths
                .into_iter()
                .map(|path| std::borrow::Cow::Owned(canonical_path(&path))),
            folders
                .into_iter()
                .map(|path| std::borrow::Cow::Owned(canonical_path(&path))),
        )
    }

    /// InputSnapshot checks canonical structure once; every capture still obtains
    /// fresh complete directory proofs and leaves payload digests live.
    pub fn capture_snapshot(inputs: &crate::input_snapshot::InputSnapshot) -> io::Result<Self> {
        inputs.check_structure()?;
        Ok(Self::capture_canonical(
            inputs
                .canonical_proof_paths()
                .map(std::borrow::Cow::Borrowed),
            inputs
                .canonical_proof_folders()
                .map(std::borrow::Cow::Borrowed),
        ))
    }
    fn capture_canonical<'a>(
        paths: impl IntoIterator<Item = std::borrow::Cow<'a, Path>>,
        folders: impl IntoIterator<Item = std::borrow::Cow<'a, Path>>,
    ) -> Self {
        let mut requested: BTreeSet<std::borrow::Cow<'a, Path>> = folders.into_iter().collect();
        let mut exact_candidates = Vec::new();
        let mut exact_bytes = 0usize;
        for path in paths {
            match &path {
                std::borrow::Cow::Borrowed(path) => {
                    let path: &'a Path = path;
                    if let Some(parent) = path.parent() {
                        requested.insert(std::borrow::Cow::Borrowed(parent));
                    }
                }
                std::borrow::Cow::Owned(path) => {
                    if let Some(parent) = path.parent() {
                        requested.insert(std::borrow::Cow::Owned(parent.to_owned()));
                    }
                }
            }
            // A separate bounded positive index removes repeated path rebuilding
            // for authenticated canonical facts. Budget denial only slows lookup.
            let charge = path
                .as_os_str()
                .as_encoded_bytes()
                .len()
                .saturating_mul(2)
                .saturating_add(256);
            if exact_bytes.saturating_add(charge) <= 16 * 1024 * 1024 {
                exact_bytes += charge;
                exact_candidates.push(path.into_owned());
            }
        }
        let requested_count = requested.len();
        let mut directories = BTreeMap::new();
        let mut bytes = 0usize;
        let mut missing_candidates = BTreeSet::new();
        let mut capture_missing = 0;
        let mut capture_errors = 0;
        let mut capture_budget_denials = 0;
        // Directory captures are independent kernel queries; run them on scoped
        // threads, then admit results in the same ordered pass (and budget order).
        let ordered: Vec<&std::borrow::Cow<'a, Path>> = requested.iter().collect();
        let captured = capture_directories_parallel(&ordered);
        for (path, result) in ordered.into_iter().zip(captured) {
            match result {
                Ok(proof) => {
                    if bytes.saturating_add(proof.charged) <= 64 * 1024 * 1024 {
                        bytes += proof.charged;
                        directories.insert(path.to_path_buf(), proof);
                    } else {
                        capture_budget_denials += 1;
                    }
                }
                Err(error) if error.kind() == io::ErrorKind::NotFound => {
                    capture_missing += 1;
                    missing_candidates.insert(path.to_path_buf());
                }
                Err(_) => {
                    capture_errors += 1;
                }
            }
        }
        // A failed open is never an absence proof. Obtain bounded additional
        // parent listings and authorize Missing only from complete membership.
        let mut parents: BTreeSet<PathBuf> = missing_candidates
            .iter()
            .filter_map(|path| path.parent().map(Path::to_owned))
            .collect();
        parents.retain(|path| !requested.contains(path.as_path()));
        for parent in parents.into_iter().take(1024) {
            if let Ok(proof) = capture_directory(&parent) {
                if bytes.saturating_add(proof.charged) <= 64 * 1024 * 1024 {
                    bytes += proof.charged;
                    directories.insert(parent, proof);
                }
            }
        }
        let mut missing_directories = BTreeSet::new();
        for _ in 0..32 {
            let before = missing_directories.len();
            for path in &missing_candidates {
                if let (Some(parent), Some(name)) = (
                    path.parent(),
                    path.file_name().and_then(|name| name.to_str()),
                ) {
                    if ordinary_negative_name(name)
                        && (missing_directories.contains(parent)
                            || directories
                                .get(parent)
                                .is_some_and(|proof| proof.proves_absent(name)))
                    {
                        missing_directories.insert(path.clone());
                    }
                }
            }
            if before == missing_directories.len() {
                break;
            }
        }
        let fallback_directories = requested_count
            - requested
                .iter()
                .filter(|path| {
                    directories.contains_key(path.as_ref())
                        || missing_directories.contains(path.as_ref())
                })
                .count();
        let mut exact_files = HashMap::new();
        let mut exact_missing_files = HashSet::new();
        for path in exact_candidates {
            let stamp = path
                .parent()
                .and_then(|parent| directories.get(parent))
                .and_then(|proof| {
                    path.file_name()
                        .and_then(|name| name.to_str())
                        .and_then(|name| proof.entries.get(name))
                })
                .and_then(|stamp| stamp.clone());
            if let Some(stamp) = stamp {
                exact_files.insert(path, stamp);
            } else if let (Some(parent), Some(name)) = (
                path.parent(),
                path.file_name().and_then(|name| name.to_str()),
            ) {
                if ordinary_negative_name(name)
                    && (missing_directories.contains(parent)
                        || directories
                            .get(parent)
                            .is_some_and(|proof| proof.proves_absent(name)))
                {
                    exact_missing_files.insert(path);
                }
            }
        }
        Self {
            exact_files,
            exact_missing_files,
            exact_path_hits: AtomicU64::new(0),
            fallback_directories,
            missing_directories,
            capture_missing,
            capture_errors,
            capture_budget_denials,
            directories,
            stamp_hits: AtomicU64::new(0),
            negative_proofs: AtomicU64::new(0),
            live_stamp_fallbacks: AtomicU64::new(0),
            folder_hits: AtomicU64::new(0),
            folder_fallbacks: AtomicU64::new(0),
        }
    }
    pub fn counts(&self) -> ProofCounts {
        ProofCounts {
            bulk_directories: self.directories.len(),
            fallback_directories: self.fallback_directories,
            proven_missing_directories: self.missing_directories.len(),
            capture_missing: self.capture_missing,
            capture_errors: self.capture_errors,
            capture_budget_denials: self.capture_budget_denials,
            stamp_hits: self.stamp_hits.load(Ordering::Relaxed),
            exact_path_hits: self.exact_path_hits.load(Ordering::Relaxed),
            negative_proofs: self.negative_proofs.load(Ordering::Relaxed),
            live_stamp_fallbacks: self.live_stamp_fallbacks.load(Ordering::Relaxed),
            folder_hits: self.folder_hits.load(Ordering::Relaxed),
            folder_fallbacks: self.folder_fallbacks.load(Ordering::Relaxed),
        }
    }
    pub fn bulk_directories(&self) -> usize {
        self.directories.len()
    }
}
// Win32 normalizes these spellings or routes them into alternate namespaces.
// A directory's exact long/short-name membership cannot prove their absence.
fn ordinary_negative_name(name: &str) -> bool {
    if !name.is_ascii() || name.ends_with(['.', ' ']) || name.contains(':') {
        return false;
    }
    let stem = name
        .split('.')
        .next()
        .unwrap_or(name)
        .trim_end_matches(' ')
        .to_ascii_uppercase();
    !matches!(
        stem.as_str(),
        "CON" | "PRN" | "AUX" | "NUL" | "CONIN$" | "CONOUT$"
    ) && !(stem.len() == 4
        && (stem.starts_with("COM") || stem.starts_with("LPT"))
        && matches!(stem.as_bytes()[3], b'1'..=b'9'))
}
impl SnapshotProvider for BulkFileSystemProofs {
    fn stamp(&self, path: &Path) -> io::Result<Stamp> {
        if let Some(stamp) = self.exact_files.get(path) {
            self.exact_path_hits.fetch_add(1, Ordering::Relaxed);
            self.stamp_hits.fetch_add(1, Ordering::Relaxed);
            return Ok(stamp.clone());
        }
        if self.exact_missing_files.contains(path) {
            self.negative_proofs.fetch_add(1, Ordering::Relaxed);
            return Err(io::Error::new(
                io::ErrorKind::NotFound,
                "file absent from captured parent membership",
            ));
        }
        // Canonical captured parents can be probed through borrowed Path keys.
        // Authored aliases still pass through the same canonical fallback.
        let canonical = if path.parent().is_some_and(|parent| {
            self.directories.contains_key(parent) || self.missing_directories.contains(parent)
        }) {
            std::borrow::Cow::Borrowed(path)
        } else {
            std::borrow::Cow::Owned(canonical_path(path))
        };
        if let (Some(parent), Some(name)) = (
            canonical.parent(),
            canonical.file_name().and_then(|s| s.to_str()),
        ) {
            if self.missing_directories.contains(parent) && ordinary_negative_name(name) {
                self.negative_proofs.fetch_add(1, Ordering::Relaxed);
                return Err(io::Error::new(
                    io::ErrorKind::NotFound,
                    "file parent absent from complete directory proof",
                ));
            }
            if let Some(proof) = self.directories.get(parent) {
                if let Some(Some(stamp)) = proof.entries.get(name) {
                    self.stamp_hits.fetch_add(1, Ordering::Relaxed);
                    return Ok(stamp.clone());
                }
                // Reparse entries, directory entries and alternate spelling require
                // ordinary handle validation. No Unicode case-fold guesses.
                if !proof.entries.contains_key(name)
                    && proof.ascii
                    && ordinary_negative_name(name)
                    && !proof.aliases.contains(&name.to_ascii_lowercase())
                {
                    self.negative_proofs.fetch_add(1, Ordering::Relaxed);
                    return Err(io::Error::new(
                        io::ErrorKind::NotFound,
                        "file absent from complete directory proof",
                    ));
                }
            }
        }
        self.live_stamp_fallbacks.fetch_add(1, Ordering::Relaxed);
        FileSystemInputs.stamp(path)
    }
    fn list(&self, path: &Path) -> io::Result<FolderListing> {
        let canonical =
            if self.directories.contains_key(path) || self.missing_directories.contains(path) {
                std::borrow::Cow::Borrowed(path)
            } else {
                std::borrow::Cow::Owned(canonical_path(path))
            };
        if self.missing_directories.contains(canonical.as_ref()) {
            self.folder_hits.fetch_add(1, Ordering::Relaxed);
            return Ok(FolderListing::Missing);
        }
        match self.directories.get(canonical.as_ref()) {
            Some(proof) => {
                self.folder_hits.fetch_add(1, Ordering::Relaxed);
                Ok(FolderListing::Present(
                    proof.entries.keys().cloned().collect(),
                ))
            }
            None => {
                self.folder_fallbacks.fetch_add(1, Ordering::Relaxed);
                FileSystemInputs.list(path)
            }
        }
    }
    fn read(&self, path: &Path) -> io::Result<(Stamp, Vec<u8>)> {
        FileSystemInputs.read(path)
    }
    fn digest(&self, path: &Path) -> io::Result<(Stamp, u128)> {
        FileSystemInputs.digest(path)
    }
}
#[cfg(not(windows))]
fn capture_directory(_: &Path) -> io::Result<DirectoryProof> {
    Err(io::Error::new(
        io::ErrorKind::Unsupported,
        "Windows directory proof unavailable",
    ))
}

fn capture_directories_parallel(
    paths: &[&std::borrow::Cow<'_, Path>],
) -> Vec<io::Result<DirectoryProof>> {
    const MIN_CHUNK: usize = 32;
    let threads = std::thread::available_parallelism()
        .map_or(1, |n| n.get())
        .min(8)
        .min(paths.len().div_ceil(MIN_CHUNK).max(1));
    if threads <= 1 {
        return paths.iter().map(|path| capture_directory(path)).collect();
    }
    let chunk = paths.len().div_ceil(threads);
    std::thread::scope(|scope| {
        let handles: Vec<_> = paths
            .chunks(chunk)
            .map(|part| {
                scope.spawn(move || {
                    part.iter()
                        .map(|path| capture_directory(path))
                        .collect::<Vec<_>>()
                })
            })
            .collect();
        handles
            .into_iter()
            .flat_map(|handle| handle.join().expect("directory proof worker"))
            .collect()
    })
}
#[cfg(windows)]
fn capture_directory(path: &Path) -> io::Result<DirectoryProof> {
    use std::ffi::c_void;
    use std::os::windows::{fs::OpenOptionsExt, io::AsRawHandle};
    #[repr(C)]
    struct Information {
        attributes: u32,
        creation: [u32; 2],
        access: [u32; 2],
        write: [u32; 2],
        volume: u32,
        size_high: u32,
        size_low: u32,
        links: u32,
        index_high: u32,
        index_low: u32,
    }
    #[link(name = "kernel32")]
    extern "system" {
        fn GetFileInformationByHandle(handle: *mut c_void, info: *mut Information) -> i32;
        fn GetFileInformationByHandleEx(
            handle: *mut c_void,
            class: i32,
            buffer: *mut c_void,
            size: u32,
        ) -> i32;
        fn GetVolumeInformationByHandleW(
            handle: *mut c_void,
            name: *mut u16,
            name_size: u32,
            serial: *mut u32,
            max_component: *mut u32,
            flags: *mut u32,
            fs_name: *mut u16,
            fs_size: u32,
        ) -> i32;
    }
    let file = std::fs::OpenOptions::new()
        .access_mode(0x81)
        .share_mode(7)
        .custom_flags(0x02200000)
        .open(path)?;
    let handle = file.as_raw_handle();
    let mut info = std::mem::MaybeUninit::<Information>::uninit();
    // SAFETY: live handle and correctly sized writable C structures/buffers.
    if unsafe { GetFileInformationByHandle(handle, info.as_mut_ptr()) } == 0 {
        return Err(io::Error::last_os_error());
    }
    let info = unsafe { info.assume_init() };
    if info.attributes & 0x10 == 0 || info.attributes & 0x400 != 0 {
        return Err(invalid("directory is a reparse point or not a directory"));
    }
    let mut fs_name = [0u16; 32];
    if unsafe {
        GetVolumeInformationByHandleW(
            handle,
            std::ptr::null_mut(),
            0,
            std::ptr::null_mut(),
            std::ptr::null_mut(),
            std::ptr::null_mut(),
            fs_name.as_mut_ptr(),
            32,
        )
    } == 0
    {
        return Err(io::Error::last_os_error());
    }
    let end = fs_name
        .iter()
        .position(|v| *v == 0)
        .ok_or_else(|| invalid("unterminated filesystem name"))?;
    if String::from_utf16(&fs_name[..end]).map_err(|_| invalid("invalid filesystem name"))?
        != "NTFS"
    {
        return Err(invalid("uncertified filesystem identity format"));
    }
    let mut proof = DirectoryProof {
        entries: BTreeMap::new(),
        aliases: BTreeSet::new(),
        ascii: true,
        charged: 0,
    };
    let mut buffer = vec![0u64; 8192];
    let mut restart = true;
    loop {
        buffer.fill(0);
        let success = unsafe {
            GetFileInformationByHandleEx(
                handle,
                if restart { 11 } else { 10 },
                buffer.as_mut_ptr().cast(),
                65536,
            )
        };
        if success == 0 {
            let error = io::Error::last_os_error();
            if error.raw_os_error() == Some(18) {
                return Ok(proof);
            }
            return Err(error);
        }
        restart = false;
        // SAFETY: buffer is initialized and owns 65536 bytes; parsing uses checked slices.
        let bytes = unsafe { std::slice::from_raw_parts(buffer.as_ptr().cast::<u8>(), 65536) };
        parse_batch(bytes, info.volume, &mut proof)?;
        if proof.entries.len() > 250_000 {
            return Err(invalid("directory proof exceeds entry budget"));
        }
    }
}
fn invalid(message: &str) -> io::Error {
    io::Error::new(io::ErrorKind::InvalidData, message)
}
#[cfg(any(windows, test))]
fn parse_batch(bytes: &[u8], volume: u32, proof: &mut DirectoryProof) -> io::Result<()> {
    let mut offset = 0usize;
    loop {
        let row = bytes
            .get(offset..)
            .ok_or_else(|| invalid("directory row offset outside buffer"))?;
        let u32_at = |at: usize| -> io::Result<u32> {
            Ok(u32::from_le_bytes(
                row.get(at..at + 4)
                    .ok_or_else(|| invalid("truncated directory row"))?
                    .try_into()
                    .unwrap(),
            ))
        };
        let u64_at = |at: usize| -> io::Result<u64> {
            Ok(u64::from_le_bytes(
                row.get(at..at + 8)
                    .ok_or_else(|| invalid("truncated directory row"))?
                    .try_into()
                    .unwrap(),
            ))
        };
        let next = u32_at(0)? as usize;
        let length = u32_at(60)? as usize;
        let extent = 104usize
            .checked_add(length)
            .ok_or_else(|| invalid("directory name overflow"))?;
        if !length.is_multiple_of(2)
            || extent > row.len()
            || (next != 0 && (!next.is_multiple_of(8) || next < extent || next > row.len()))
        {
            return Err(invalid("invalid directory row extent"));
        }
        let decode = |slice: &[u8]| -> io::Result<String> {
            let units: Vec<u16> = slice
                .chunks_exact(2)
                .map(|p| u16::from_le_bytes([p[0], p[1]]))
                .collect();
            String::from_utf16(&units).map_err(|_| invalid("directory name is not Unicode"))
        };
        let name = decode(&row[104..extent])?;
        if name.is_empty() || name.contains(['\0', '/', '\\']) {
            return Err(invalid("invalid directory filename"));
        }
        if name != "." && name != ".." {
            proof.charged = proof
                .charged
                .saturating_add(name.len().saturating_mul(2).saturating_add(512));
            if proof.charged > 64 * 1024 * 1024 {
                return Err(invalid("directory proof exceeds memory budget"));
            }
            proof.ascii &= name.is_ascii();
            proof.aliases.insert(name.to_ascii_lowercase());
            let short = usize::from(*row.get(68).ok_or_else(|| invalid("truncated short name"))?);
            if short > 24 || short % 2 != 0 {
                return Err(invalid("invalid short name length"));
            }
            let short_name = decode(&row[70..70 + short])?;
            proof.ascii &= short_name.is_ascii();
            if !short_name.is_empty() {
                proof.aliases.insert(short_name.to_ascii_lowercase());
            }
            let attributes = u32_at(56)?;
            let size = u64_at(40)?;
            let time = u64_at(24)?;
            let id = u64_at(96)?;
            let stamp = if attributes & (0x10 | 0x400) == 0 && size <= i64::MAX as u64 && id != 0 {
                Some(Stamp {
                    size,
                    modified_ns: u128::from(
                        time.checked_sub(116_444_736_000_000_000)
                            .ok_or_else(|| invalid("directory time predates epoch"))?,
                    ) * 100,
                    file_id: Some((u128::from(volume) << 64) | u128::from(id)),
                })
            } else {
                None
            };
            if proof.entries.insert(name, stamp).is_some() {
                return Err(invalid("duplicate directory filename"));
            }
        }
        if next == 0 {
            return Ok(());
        }
        offset = offset
            .checked_add(next)
            .ok_or_else(|| invalid("directory offset overflow"))?;
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[cfg(windows)]
    #[test]
    fn missing_directory_proofs_require_complete_parent_membership() {
        let root = std::env::temp_dir().join(format!(
            "dmbc-parent-proof-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        std::fs::create_dir(&root).unwrap();
        std::fs::create_dir(root.join("Existing")).unwrap();
        let missing = root.join("Missing");
        let nested = missing.join("nested");
        let provider = BulkFileSystemProofs::capture(
            [missing.join("asset.txt"), nested.join("other.txt")],
            [missing.clone(), nested.clone()],
        );
        assert_eq!(provider.counts().proven_missing_directories, 2);
        assert_eq!(
            provider.list(&missing).unwrap(),
            FileSystemInputs.list(&missing).unwrap()
        );
        assert_eq!(provider.list(&nested).unwrap(), FolderListing::Missing);
        assert_eq!(
            provider
                .stamp(&missing.join("asset.txt"))
                .unwrap_err()
                .kind(),
            io::ErrorKind::NotFound
        );
        assert_eq!(provider.counts().live_stamp_fallbacks, 0);
        // Alternate namespaces still require the ordinary provider even when
        // the apparent parent has a proven missing long-name directory.
        let _ = provider.stamp(&missing.join("NUL"));
        assert_eq!(provider.counts().live_stamp_fallbacks, 1);
        std::fs::remove_dir_all(root).unwrap();
    }
    #[test]
    fn bulk_directory_stamps_match_live_files_and_preserve_case_fallback() {
        let root = std::env::temp_dir().join(format!(
            "dmbc-bulk-proof-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        std::fs::create_dir(&root).unwrap();
        let path = root.join("Mixed.txt");
        std::fs::write(&path, b"captured bytes").unwrap();
        std::fs::write(root.join("unicode-\u{e9}.txt"), b"unicode").unwrap();
        let provider = BulkFileSystemProofs::capture([path.clone()], [root.clone()]);
        #[cfg(windows)]
        assert_eq!(provider.bulk_directories(), 1);
        assert_eq!(
            provider.stamp(&path).unwrap(),
            FileSystemInputs.stamp(&path).unwrap()
        );
        assert_eq!(
            provider.list(&root).unwrap(),
            FileSystemInputs.list(&root).unwrap()
        );
        assert_eq!(
            provider.stamp(&root.join("mixed.txt")).ok(),
            FileSystemInputs.stamp(&root.join("mixed.txt")).ok()
        );
        assert_eq!(
            provider.stamp(&root.join("absent")).unwrap_err().kind(),
            io::ErrorKind::NotFound
        );
        assert_eq!(
            provider.list(&root.join("missing-dir")).unwrap(),
            FolderListing::Missing
        );
        assert_eq!(
            provider.digest(&path).unwrap(),
            FileSystemInputs.digest(&path).unwrap()
        );
        let counts = provider.counts();
        #[cfg(windows)]
        assert_eq!(counts.exact_path_hits, 1);
        assert_eq!(
            counts.stamp_hits + counts.negative_proofs + counts.live_stamp_fallbacks,
            3
        );
        assert_eq!(counts.folder_hits + counts.folder_fallbacks, 2);
        std::fs::remove_dir_all(root).unwrap();
    }
    #[test]
    fn alternate_windows_names_never_issue_negative_membership_proofs() {
        for name in [
            "Mixed.txt.",
            "Mixed.txt ",
            "Mixed.txt:stream",
            "NUL",
            "con.txt",
            "COM1.log",
            "LPT9",
            "CONIN$",
        ] {
            assert!(!ordinary_negative_name(name), "{name}");
        }
        assert!(ordinary_negative_name("ordinary.txt"));
        assert!(ordinary_negative_name("COM10.txt"));
        #[cfg(windows)]
        {
            let root = std::env::temp_dir().join(format!(
                "dmbc-bulk-alias-{}-{}",
                std::process::id(),
                std::time::SystemTime::now()
                    .duration_since(std::time::UNIX_EPOCH)
                    .unwrap()
                    .as_nanos()
            ));
            std::fs::create_dir(&root).unwrap();
            let file = root.join("Mixed.txt");
            std::fs::write(&file, b"ordinary").unwrap();
            std::fs::write(root.join("Mixed.txt:stream"), b"stream").unwrap();
            let provider = BulkFileSystemProofs::capture([file], [root.clone()]);
            for name in [
                "Mixed.txt.",
                "Mixed.txt ",
                "Mixed.txt:stream",
                "NUL",
                "con.txt",
            ] {
                let path = root.join(name);
                let actual = provider.stamp(&path);
                let expected = FileSystemInputs.stamp(&path);
                match (actual, expected) {
                    (Ok(actual), Ok(expected)) => assert_eq!(actual, expected, "{name}"),
                    (Err(actual), Err(expected)) => {
                        assert_eq!(actual.kind(), expected.kind(), "{name}")
                    }
                    (actual, expected) => {
                        panic!("alias proof differs for {name}: {actual:?} / {expected:?}")
                    }
                }
            }
            std::fs::remove_dir_all(root).unwrap();
        }
    }
    #[test]
    fn malformed_directory_rows_and_reparse_entries_never_issue_file_stamps() {
        let mut row = vec![0u8; 112];
        row[60..64].copy_from_slice(&2u32.to_le_bytes());
        row[104..106].copy_from_slice(&(b'x' as u16).to_le_bytes());
        row[56..60].copy_from_slice(&0x400u32.to_le_bytes());
        let mut proof = DirectoryProof {
            entries: BTreeMap::new(),
            aliases: BTreeSet::new(),
            ascii: true,
            charged: 0,
        };
        parse_batch(&row, 1, &mut proof).unwrap();
        assert_eq!(proof.entries.get("x"), Some(&None));
        row[104..106].copy_from_slice(&0xd800u16.to_le_bytes());
        assert!(parse_batch(&row, 1, &mut proof).is_err());
        row[104..106].copy_from_slice(&(b'x' as u16).to_le_bytes());
        row[0..4].copy_from_slice(&108u32.to_le_bytes());
        assert!(parse_batch(&row, 1, &mut proof).is_err());
    }
}

#[cfg(test)]
#[path = "filesystem_proofs_lookup_tests.rs"]
mod lookup_tests;
