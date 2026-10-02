//! Read-only NTFS journal acceleration. Unknown APIs, wrapped journals and
//! sharing conflicts fall back to ordinary per-file proofs.
use crate::file_stamp::FileStamp;
use serde::{Deserialize, Serialize};
use std::{
    collections::BTreeMap,
    path::{Path, PathBuf},
};

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct JournalProof {
    #[cfg(windows)]
    volumes: Vec<VolumeProof>,
    #[cfg(windows)]
    directories: BTreeMap<PathBuf, DirectoryProof>,
    #[cfg(windows)]
    #[serde(skip)]
    live_volumes: std::cell::RefCell<Option<Vec<VolumeProof>>>,
}

#[cfg(windows)]
#[derive(Clone, Debug, Serialize, Deserialize)]
struct DirectoryProof {
    lexical: FileStamp,
    followed: FileStamp,
}

#[derive(Clone,Copy,Debug,Eq,PartialEq)]
pub enum Validation {
    Current,
    Changed,
    Unavailable,
}

impl JournalProof {
    pub fn for_files(&self, files: &BTreeMap<PathBuf, FileStamp>) -> Option<Self> {
        #[cfg(windows)]
        {
            let wanted = files
                .values()
                .map(FileStamp::file_id)
                .collect::<Option<std::collections::BTreeSet<_>>>()?;
            let mut proof = self.clone();
            if let Some(live) = proof.live_volumes.get_mut().take() {
                proof.volumes = live;
            }
            for volume in &mut proof.volumes {
                volume.ids.retain(|id| wanted.contains(id));
            }
            proof
                .volumes
                .retain(|volume| !volume.ids.is_empty() || !volume.directory_ids.is_empty());
            (!proof.volumes.is_empty()).then_some(proof)
        }
        #[cfg(not(windows))]
        {
            let _ = files;
            None
        }
    }
    /// Identify unchanged known files from one bounded volume-journal scan.
    /// Namespace/ancestor edits or unavailable journals require a strong fallback.
    pub fn unchanged_paths(
        &self,
        files: &BTreeMap<PathBuf, FileStamp>,
    ) -> Option<std::collections::BTreeSet<PathBuf>> {
        #[cfg(windows)]
        {
            if !self.junctions_current() {
                return None;
            }
            let mut live = self.live_volumes.borrow_mut();
            let volumes = live.get_or_insert_with(|| self.volumes.clone());
            let mut changed = std::collections::BTreeSet::new();
            for volume in volumes {
                if volume.directory_ids.is_empty() {
                    return None;
                }
                changed.extend(windows::changed_ids(volume)?);
            }
            Some(
                files
                    .iter()
                    .filter(|(_, stamp)| stamp.file_id().is_some_and(|id| !changed.contains(&id)))
                    .map(|(path, _)| path.clone())
                    .collect(),
            )
        }
        #[cfg(not(windows))]
        {
            let _ = files;
            None
        }
    }
    pub fn merged(&self, other: &Self) -> Option<Self> {
        #[cfg(windows)]
        {
            let mut directories = self.directories.clone();
            for (path, stamp) in &other.directories {
                if let Some(old) = directories.get(path) {
                    if !old.lexical.same_object(&stamp.lexical)
                        || !old.followed.same_object(&stamp.followed)
                    {
                        return None;
                    }
                }
                directories.insert(path.clone(), stamp.clone());
            }
            let mut volumes = self
                .live_volumes
                .borrow()
                .as_ref()
                .unwrap_or(&self.volumes)
                .clone();
            volumes.extend(
                other
                    .live_volumes
                    .borrow()
                    .as_ref()
                    .unwrap_or(&other.volumes)
                    .iter()
                    .cloned(),
            );
            if volumes.len() > 32 {
                return None;
            }
            // Merge equal cursors only; never bless earlier writes to a newly
            // introduced file by advancing its proof from another baseline.
            let mut merged: Vec<VolumeProof> = Vec::new();
            for volume in volumes {
                if let Some(old) = merged.iter_mut().find(|old| {
                    old.device == volume.device
                        && old.journal_id == volume.journal_id
                        && old.cursor == volume.cursor
                }) {
                    old.ids.extend(volume.ids);
                    old.ids.sort();
                    old.ids.dedup();
                    old.directory_ids.extend(volume.directory_ids);
                    old.directory_ids.sort();
                    old.directory_ids.dedup();
                    let mut names=std::collections::BTreeMap::<[u64;2],Vec<String>>::new();
                    for id in old.namespace_ids.iter().chain(&volume.namespace_ids) {
                        let left=old.namespace_names.binary_search_by_key(id,|(key,_)|*key).ok().map(|index|&old.namespace_names[index].1);
                        let right=volume.namespace_names.binary_search_by_key(id,|(key,_)|*key).ok().map(|index|&volume.namespace_names[index].1);
                        if (old.namespace_ids.binary_search(id).is_ok() && left.is_none()) || (volume.namespace_ids.binary_search(id).is_ok() && right.is_none()) {continue;}
                        let values=names.entry(*id).or_default();
                        values.extend(left.into_iter().chain(right).flat_map(|names|names.iter().cloned()));values.sort();values.dedup();
                    }
                    old.namespace_names=names.into_iter().collect();
                    old.namespace_ids.extend(volume.namespace_ids);
                    old.namespace_ids.sort();
                    old.namespace_ids.dedup();
                } else {
                    merged.push(volume);
                }
            }
            Some(Self {
                volumes: merged,
                directories,
                live_volumes: Default::default(),
            })
        }
        #[cfg(not(windows))]
        {
            let _ = other;
            None
        }
    }
    /// Reuse old barriers only for stamp-equal known files, with earlier cursors
    /// retained until those exact IDs have been revalidated.
    pub fn refreshed(
        &self,
        previous: &BTreeMap<PathBuf, FileStamp>,
        files: &BTreeMap<PathBuf, FileStamp>,
    ) -> Option<Self> {
        let unchanged = files
            .iter()
            .filter(|(path, stamp)| previous.get(*path) == Some(*stamp))
            .map(|(path, stamp)| (path.clone(), stamp.clone()))
            .collect::<BTreeMap<_, _>>();
        if unchanged.is_empty() {
            return Self::establish(files);
        }
        let retained = self.for_files(&unchanged)?;
        if !retained.current() {
            return None;
        }
        let dirty = files
            .iter()
            .filter(|(path, _)| !unchanged.contains_key(*path))
            .map(|(path, stamp)| (path.clone(), stamp.clone()))
            .collect::<BTreeMap<_, _>>();
        if dirty.is_empty() {
            return Some(retained);
        }
        retained.merged(&Self::establish(&dirty)?)
    }
    pub fn with_namespaces(&self, candidates: &[PathBuf]) -> Option<Self> {
        if !self.current() {
            return None;
        }
        if candidates.is_empty() {
            return Some(self.clone());
        }
        self.merged(&Self::establish_namespaces(&BTreeMap::new(), candidates)?)
    }
    pub fn resident_bytes(&self) -> usize {
        #[cfg(windows)]
        {
            self.volumes
                .iter()
                .map(|volume| {
                    volume.device.as_os_str().len() * 2
                        + (volume.ids.capacity()
                            + volume.directory_ids.capacity()
                            + volume.namespace_ids.capacity())
                            * 16
                        + volume.namespace_names.iter().map(|(_,names)|48+names.iter().map(|name|name.len()+24).sum::<usize>()).sum::<usize>()
                        + 128
                })
                .sum::<usize>()
                + self
                    .directories
                    .keys()
                    .map(|path| path.as_os_str().len() * 2 + 128)
                    .sum::<usize>()
        }
        #[cfg(not(windows))]
        {
            0
        }
    }
    pub fn establish(files: &BTreeMap<PathBuf, FileStamp>) -> Option<Self> {
        Self::establish_namespaces(files, &[])
    }
    /// Guard known files plus resolution candidates, including absent paths.
    pub fn establish_namespaces(
        files: &BTreeMap<PathBuf, FileStamp>,
        candidates: &[PathBuf],
    ) -> Option<Self> {
        #[cfg(windows)]
        {
            windows::establish(files, candidates)
        }
        #[cfg(not(windows))]
        {
            let _ = (files, candidates);
            None
        }
    }
    #[cfg(windows)]
    fn junctions_current(&self) -> bool {
        // A writer that predates the journal cursor can coalesce repeated reparse
        // reasons. Check the few actual junctions directly; ordinary ancestors
        // remain volume-batched rather than re-opening every known directory.
        self.directories
            .iter()
            .filter(|(_, stamp)| !stamp.lexical.same_object(&stamp.followed))
            .all(|(path, expected)| {
                crate::file_stamp::directory(path)
                    .is_some_and(|stamp| stamp.same_object(&expected.lexical))
                    && crate::file_stamp::directory_following(path)
                        .is_some_and(|stamp| stamp.same_object(&expected.followed))
            })
    }
    pub fn current(&self) -> bool {
        matches!(self.validate(), Validation::Current)
    }
    pub fn validate(&self) -> Validation {
        #[cfg(windows)]
        {
            if !self.junctions_current() {
                return Validation::Changed;
            }
            let batched = self
                .volumes
                .iter()
                .all(|volume| !volume.directory_ids.is_empty());
            if !batched
                && !self.directories.iter().all(|(path, expected)| {
                    crate::file_stamp::directory(path)
                        .is_some_and(|stamp| stamp.same_object(&expected.lexical))
                        && crate::file_stamp::directory_following(path)
                            .is_some_and(|stamp| stamp.same_object(&expected.followed))
                })
            {
                return Validation::Changed;
            }
            let mut live = self.live_volumes.borrow_mut();
            let volumes = live.get_or_insert_with(|| self.volumes.clone());
            for volume in volumes {
                match windows::validate(volume) {
                    Validation::Current => {}
                    status => return status,
                }
            }
            Validation::Current
        }
        #[cfg(not(windows))]
        {
            Validation::Unavailable
        }
    }
}

#[cfg(windows)]
#[derive(Clone, Debug, Serialize, Deserialize)]
struct VolumeProof {
    device: PathBuf,
    journal_id: u64,
    cursor: i64,
    ids: Vec<[u64; 2]>,
    #[serde(default)]
    directory_ids: Vec<[u64; 2]>,
    #[serde(default)]
    namespace_ids: Vec<[u64; 2]>,
    #[serde(default)]
    namespace_names: Vec<([u64; 2], Vec<String>)>,
}

fn read_u16(bytes: &[u8], offset: usize) -> Option<u16> {
    Some(u16::from_le_bytes(
        bytes.get(offset..offset + 2)?.try_into().ok()?,
    ))
}
fn read_u32(bytes: &[u8], offset: usize) -> Option<u32> {
    Some(u32::from_le_bytes(
        bytes.get(offset..offset + 4)?.try_into().ok()?,
    ))
}
fn read_u64(bytes: &[u8], offset: usize) -> Option<u64> {
    Some(u64::from_le_bytes(
        bytes.get(offset..offset + 8)?.try_into().ok()?,
    ))
}

/// Unknown record versions and malformed offsets always reject acceleration.
#[cfg(test)]
fn scan_records(bytes: &[u8], watched: &[[u64; 2]]) -> Option<(i64, bool)> {
    scan_records_batched(bytes, watched, &[], &[])
}
#[cfg(test)]
fn scan_records_batched(
    bytes: &[u8],
    watched: &[[u64; 2]],
    directories: &[[u64; 2]],
    namespaces: &[[u64; 2]],
) -> Option<(i64, bool)> {
    scan_records_filtered(bytes,watched,directories,namespaces,&[])
}
fn scan_records_filtered(bytes:&[u8],watched:&[[u64;2]],directories:&[[u64;2]],namespaces:&[[u64;2]],names:&[([u64;2],Vec<String>)])->Option<(i64,bool)> {
    if !names.windows(2).all(|pair|pair[0].0<pair[1].0) || names.iter().any(|(_,values)| {
        !values.windows(2).all(|pair|pair[0]<pair[1]) || values.iter().any(|name|!name.is_ascii() || name.contains(['~',':']) || name.ends_with(['.',' ']))
    }) {return None;}
    let next = read_u64(bytes, 0)? as i64;
    let mut offset = 8;
    let mut changed = false;
    while offset < bytes.len() {
        let length = read_u32(bytes, offset)? as usize;
        if length < 8 || length % 8 != 0 {
            return None;
        }
        let record = bytes.get(offset..offset.checked_add(length)?)?;
        let major = read_u16(record, 4)?;
        let (id, name_offset, name_length) = match major {
            2 if length >= 60 => (
                [read_u64(record, 8)?, 0],
                read_u16(record, 58)? as usize,
                read_u16(record, 56)? as usize,
            ),
            3 if length >= 76 => (
                [read_u64(record, 8)?, read_u64(record, 16)?],
                read_u16(record, 74)? as usize,
                read_u16(record, 72)? as usize,
            ),
            _ => return None,
        };
        if name_length % 2 != 0
            || name_offset < if major == 2 { 60 } else { 76 }
            || name_offset.checked_add(name_length)? > length
        {
            return None;
        }
        // Even CLOSE-only and metadata events conservatively invalidate a file.
        let (parent, reason) = if major == 2 {
            ([read_u64(record, 16)?, 0], read_u32(record, 40)?)
        } else {
            (
                [read_u64(record, 24)?, read_u64(record, 32)?],
                read_u32(record, 56)?,
            )
        };
        // Ancestor identity/reparse changes invalidate all descendant paths.
        // Namespace events also invalidate cached absences and higher-priority
        // resolution candidates. Ordinary writes to unrelated siblings do not.
        if watched.binary_search(&id).is_ok()
            || (reason & 0x0011_3300 != 0 && directories.binary_search(&id).is_ok())
            || (reason & 0x0001_3300 != 0 && namespaces.binary_search(&parent).is_ok() && namespace_name_matches(record,name_offset,name_length,parent,names))
        {
            changed = true;
        }
        offset += length;
    }
    Some((next, changed))
}

fn namespace_name_matches(record:&[u8],offset:usize,length:usize,parent:[u64;2],watches:&[([u64;2],Vec<String>)])->bool {
    let Ok(index)=watches.binary_search_by_key(&parent,|(id,_)|*id) else {return true;};
    let Some(bytes)=record.get(offset..offset+length) else {return true;};
    let mut name=String::with_capacity(length/2);
    for pair in bytes.chunks_exact(2) {
        let character=u16::from_le_bytes([pair[0],pair[1]]);
        if character>127 {return true;}
        name.push((character as u8).to_ascii_lowercase() as char);
    }
    if name.contains(['~',':']) || name.ends_with(['.',' ']) {return true;}
    watches[index].1.binary_search(&name).is_ok()
}

#[cfg(windows)]
mod windows {
    use super::*;
    use std::{
        collections::{BTreeMap, BTreeSet},
        fs,
        os::windows::io::AsRawHandle,
    };
    #[link(name = "kernel32")]
    unsafe extern "system" {
        fn CreateFileW(
            name: *const u16,
            access: u32,
            sharing: u32,
            security: *mut std::ffi::c_void,
            disposition: u32,
            flags: u32,
            template: *mut std::ffi::c_void,
        ) -> *mut std::ffi::c_void;
        fn DeviceIoControl(
            handle: *mut std::ffi::c_void,
            code: u32,
            input: *const std::ffi::c_void,
            input_len: u32,
            output: *mut std::ffi::c_void,
            output_len: u32,
            returned: *mut u32,
            overlapped: *mut std::ffi::c_void,
        ) -> i32;
    }
    fn traced<T>(value: Option<T>, stage: &str, path: &Path) -> Option<T> {
        let error = std::io::Error::last_os_error();
        if value.is_none() && std::env::var_os("DM_BUILD_TRACE").is_some() {
            eprintln!(
                "DM_BUILD_TRACE journal unavailable: {stage}, {}, {}",
                path.display(),
                error
            );
        }
        value
    }
    fn control(file: &fs::File, code: u32, input: &[u8], output: &mut [u8]) -> Option<usize> {
        let mut returned = 0;
        let ok = unsafe {
            DeviceIoControl(
                file.as_raw_handle(),
                code,
                input.as_ptr().cast(),
                input.len() as u32,
                output.as_mut_ptr().cast(),
                output.len() as u32,
                &mut returned,
                std::ptr::null_mut(),
            )
        };
        (ok != 0 && returned as usize <= output.len()).then_some(returned as usize)
    }
    fn open(device: &Path) -> Option<fs::File> {
        use std::os::windows::{ffi::OsStrExt, io::FromRawHandle};
        let text = device.to_string_lossy();
        let root = PathBuf::from(format!("{}\\", text.strip_prefix(r"\\.\")?));
        // Directory-root handles support unprivileged journal operations;
        // a zero-access raw volume handle returns ERROR_INVALID_FUNCTION.
        for (path, access, flags) in [
            (device, 0x80000000, 0),
            (root.as_path(), 0x80000000, 0x02000000),
            (root.as_path(), 0, 0x02000000),
        ] {
            let name = path
                .as_os_str()
                .encode_wide()
                .chain(Some(0))
                .collect::<Vec<_>>();
            let handle = unsafe {
                CreateFileW(
                    name.as_ptr(),
                    access,
                    3,
                    std::ptr::null_mut(),
                    3,
                    flags,
                    std::ptr::null_mut(),
                )
            };
            if handle as isize != -1 {
                return Some(unsafe { fs::File::from_raw_handle(handle) });
            }
        }
        None
    }
    fn query(file: &fs::File) -> Option<(u64, i64, i64, i64)> {
        let mut bytes = [0u8; 80];
        let length = control(file, 0x900f4, &[], &mut bytes)?;
        let bytes = bytes.get(..length)?;
        Some((
            read_u64(bytes, 0)?,
            read_u64(bytes, 8)? as i64,
            read_u64(bytes, 16)? as i64,
            read_u64(bytes, 24)? as i64,
        ))
    }
    fn device(path: &Path) -> Option<PathBuf> {
        let text = fs::canonicalize(path).ok()?.to_string_lossy().into_owned();
        let text = text.strip_prefix(r"\\?\").unwrap_or(&text);
        let bytes = text.as_bytes();
        if bytes.len() < 3
            || bytes[1] != b':'
            || bytes[2] != b'\\'
            || !bytes[0].is_ascii_alphabetic()
        {
            return None;
        }
        Some(PathBuf::from(format!(r"\\.\{}:", bytes[0] as char)))
    }
    pub(super) fn establish(
        files: &BTreeMap<PathBuf, FileStamp>,
        candidates: &[PathBuf],
    ) -> Option<JournalProof> {
        if files.is_empty() && candidates.is_empty() {
            return None;
        }
        let mut by_volume: BTreeMap<PathBuf, Vec<[u64; 2]>> = BTreeMap::new();
        let mut devices: BTreeMap<u64, PathBuf> = BTreeMap::new();
        let mut paths = Vec::with_capacity(files.len());
        let mut ancestors = BTreeSet::new();
        for (path, stamp) in files {
            // Volume identity was obtained from the same handle as this file's
            // proof. Resolve one physical device per volume, rather than opening
            // and canonicalizing every resource path again.
            let volume_id = stamp.volume_id()?;
            let volume = if let Some(device) = devices.get(&volume_id) {
                device.clone()
            } else {
                let volume = traced(device(path), "file volume", path)?;
                devices.insert(volume_id, volume.clone());
                volume
            };
            by_volume.entry(volume).or_default().push(stamp.file_id()?);
            paths.push((path, stamp));
            for ancestor in path.ancestors().skip(1) {
                if !ancestor.as_os_str().is_empty() {
                    // A previously visited ancestor already contributed its
                    // entire parent chain during this establishment.
                    if !ancestors.insert(ancestor.to_path_buf()) { break; }
                }
            }
        }
        let mut namespace_paths = BTreeSet::new();
        let mut parent_names=BTreeMap::<PathBuf,Option<BTreeSet<String>>>::new();
        let mut directory_exists = BTreeMap::new();
        for candidate in candidates {
            let candidate_parent=candidate.parent()?;
            let parent=candidate_parent.ancestors().find(|path| {
                *directory_exists.entry(path.to_path_buf()).or_insert_with(||path.is_dir())
            })?;
            namespace_paths.insert(parent.to_path_buf());
            // Watch the first unresolved component, or the final candidate name
            // if all of its directories already exist.
            let child=candidate.strip_prefix(parent).ok()?.components().next()?;
            let name=child.as_os_str().to_str().filter(|name| {
                name.is_ascii() && !name.contains(['~',':']) && !name.ends_with(['.',' ']) && *name!="." && *name!=".."
            }).map(str::to_ascii_lowercase);
            let names=parent_names.entry(parent.to_path_buf()).or_insert_with(||Some(BTreeSet::new()));
            match (names.as_mut(),name) { (Some(names),Some(name))=>{names.insert(name);},(_,None)=>*names=None,_=>{} }
            for ancestor in parent.ancestors() {
                if !ancestor.as_os_str().is_empty() && !ancestors.insert(ancestor.to_path_buf()) {break;}
            }
        }
        // Find lexical and followed ancestor volumes before taking cursors;
        // junctions can connect filesystems with independent change journals.
        for ancestor in &ancestors {
            for (stamp, path) in [
                (
                    crate::file_stamp::directory(ancestor)?,
                    ancestor.parent().unwrap_or(ancestor),
                ),
                (
                    crate::file_stamp::directory_following(ancestor)?,
                    ancestor.as_path(),
                ),
            ] {
                let volume_id = stamp.volume_id()?;
                if !devices.contains_key(&volume_id) {
                    let volume = device(path)?;
                    devices.insert(volume_id, volume.clone());
                    by_volume.entry(volume).or_default();
                }
            }
        }
        let mut volumes = Vec::new();
        // Journal cursors MUST precede every sharing barrier.
        for (device, mut ids) in by_volume {
            let file = traced(open(&device), "volume open", &device)?;
            let (journal_id, _, cursor, _) = traced(query(&file), "volume query", &device)?;
            ids.sort();
            ids.dedup();
            volumes.push(VolumeProof {
                device,
                journal_id,
                cursor,
                ids,
                directory_ids: Vec::new(),
                namespace_ids: Vec::new(),
                namespace_names: Vec::new(),
            });
        }
        let directories: BTreeMap<PathBuf, DirectoryProof> = ancestors
            .into_iter()
            .map(|path| {
                Some((
                    path.clone(),
                    DirectoryProof {
                        lexical: traced(
                            crate::file_stamp::directory(&path),
                            "lexical directory",
                            &path,
                        )?,
                        followed: traced(
                            crate::file_stamp::directory_following(&path),
                            "followed directory",
                            &path,
                        )?,
                    },
                ))
            })
            .collect::<Option<BTreeMap<_, _>>>()?;
        let mut broad_namespace_ids=BTreeSet::new();
        for (path, stamps) in &directories {
            for stamp in [&stamps.lexical, &stamps.followed] {
                let device = devices.get(&stamp.volume_id()?)?;
                let volume = volumes.iter_mut().find(|v| &v.device == device)?;
                volume.directory_ids.push(stamp.file_id()?);
            }
            if namespace_paths.contains(path) {
                let device=devices.get(&stamps.followed.volume_id()?)?;
                let volume=volumes.iter_mut().find(|v|&v.device==device)?;
                let id=stamps.followed.file_id()?;
                volume.namespace_ids.push(id);
                if let Some(Some(names))=parent_names.get(path) {
                    volume.namespace_names.push((id,names.iter().cloned().collect()));
                } else {broad_namespace_ids.insert((device.clone(),id));}
            }
        }
        for volume in &mut volumes {
            volume.directory_ids.sort();
            volume.directory_ids.dedup();
            volume.namespace_ids.sort();
            volume.namespace_ids.dedup();
            let mut names=BTreeMap::<[u64;2],BTreeSet<String>>::new();
            for (id,values) in std::mem::take(&mut volume.namespace_names) {
                if !broad_namespace_ids.contains(&(volume.device.clone(),id)) {names.entry(id).or_default().extend(values);}
            }
            volume.namespace_names=names.into_iter().map(|(id,names)|(id,names.into_iter().collect())).collect();
        }
        for (path, expected) in paths {
            if !crate::file_stamp::exclusive_barrier(path, expected) {
                return traced(None, "file sharing barrier or changed stamp", path);
            }
        }
        let proof = JournalProof {
            volumes,
            directories,
            live_volumes: Default::default(),
        };
        if proof.current() {
            Some(proof)
        } else {
            traced(None, "journal validation", &proof.volumes[0].device)
        }
    }
    fn scan_pages()->usize {
        // The fixed 16 MiB limit forced per-file fallback during ordinary
        // compiler/temp-file churn. Stream a bounded configurable window with
        // the same 64 KiB buffer; memory use does not grow with this allowance.
        std::env::var("DM_JOURNAL_SCAN_MIB").ok().and_then(|value|value.parse::<usize>().ok()).unwrap_or(64).clamp(16,256)*16
    }
    fn scan_trace(proof:&VolumeProof,reason:&str,start:i64,end:i64,pages:usize) {
        if std::env::var_os("DM_BUILD_TRACE").is_some() {
            eprintln!("DM_BUILD_TRACE journal scan: {} {reason}, cursor {start}..{end}, {pages} pages, {} files, {} namespace barriers",proof.device.display(),proof.ids.len(),proof.namespace_ids.len());
        }
    }
    pub(super) fn changed_ids(proof: &mut VolumeProof) -> Option<BTreeSet<[u64; 2]>> {
        let file = open(&proof.device)?;
        let (journal_id, first, end, lowest) = query(&file)?;
        if journal_id != proof.journal_id
            || proof.cursor < first
            || proof.cursor < lowest
            || proof.cursor > end
        {
            return None;
        }
        let mut cursor = proof.cursor;
        let mut buffer = vec![0u8; 64 * 1024];
        let mut changed = BTreeSet::new();
        for page in 0..scan_pages() {
            if cursor >= end {
                if changed.is_empty() {
                    proof.cursor = end;
                }
                scan_trace(proof,"changed-ids complete",proof.cursor,end,page);
                return Some(changed);
            }
            let mut request = [0u8; 48];
            request[..8].copy_from_slice(&cursor.to_le_bytes());
            request[8..12].copy_from_slice(&u32::MAX.to_le_bytes());
            request[32..40].copy_from_slice(&journal_id.to_le_bytes());
            request[40..42].copy_from_slice(&2u16.to_le_bytes());
            request[42..44].copy_from_slice(&3u16.to_le_bytes());
            let length = control(&file, 0x900bb, &request, &mut buffer)
                .or_else(|| control(&file, 0x903ab, &request, &mut buffer))?;
            let bytes = &buffer[..length];
            let (next, namespace_changed) =
                scan_records_filtered(bytes, &[], &proof.directory_ids, &proof.namespace_ids, &proof.namespace_names)?;
            if namespace_changed || next <= cursor {
                return None;
            }
            let mut offset = 8;
            while offset < bytes.len() {
                let length = read_u32(bytes, offset)? as usize;
                let record = bytes.get(offset..offset.checked_add(length)?)?;
                let id = match read_u16(record, 4)? {
                    2 => [read_u64(record, 8)?, 0],
                    3 => [read_u64(record, 8)?, read_u64(record, 16)?],
                    _ => return None,
                };
                if proof.ids.binary_search(&id).is_ok() {
                    changed.insert(id);
                }
                offset += length;
            }
            cursor = next;
        }
        scan_trace(proof,"changed-ids scan cap",proof.cursor,end,scan_pages());
        None
    }
    pub(super) fn validate(proof: &mut VolumeProof) -> Validation {
        let Some(file) = open(&proof.device) else {
            return Validation::Unavailable;
        };
        let Some((journal_id, first, end, lowest)) = query(&file) else {
            return Validation::Unavailable;
        };
        if journal_id != proof.journal_id
            || proof.cursor < first
            || proof.cursor < lowest
            || proof.cursor > end
        {
            return Validation::Unavailable;
        }
        let mut cursor = proof.cursor;
        let mut buffer = vec![0u8; 64 * 1024];
        // Stream journal pages through one fixed-size buffer. A bounded window
        // is enforced independently from the amount of source metadata.
        for page in 0..scan_pages() {
            if cursor >= end {
                scan_trace(proof,"validation current",proof.cursor,end,page);
                proof.cursor = end;
                return Validation::Current;
            }
            let mut request = [0u8; 48];
            request[..8].copy_from_slice(&cursor.to_le_bytes());
            request[8..12].copy_from_slice(&u32::MAX.to_le_bytes());
            request[32..40].copy_from_slice(&journal_id.to_le_bytes());
            request[40..42].copy_from_slice(&2u16.to_le_bytes());
            request[42..44].copy_from_slice(&3u16.to_le_bytes());
            let length = control(&file, 0x900bb, &request, &mut buffer)
                .or_else(|| control(&file, 0x903ab, &request, &mut buffer));
            let Some(length) = length else {
                return Validation::Unavailable;
            };
            let Some((next, changed)) = scan_records_filtered(
                &buffer[..length],
                &proof.ids,
                &proof.directory_ids,
                &proof.namespace_ids,
                &proof.namespace_names,
            ) else {
                return Validation::Unavailable;
            };
            if changed {
                scan_trace(proof,"validation relevant change",proof.cursor,end,page+1);
                return Validation::Changed;
            }
            if next <= cursor {
                return Validation::Unavailable;
            }
            cursor = next;
        }
        scan_trace(proof,"validation scan cap",proof.cursor,end,scan_pages());
        Validation::Unavailable
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    fn record(major: u16, id: [u64; 2]) -> Vec<u8> {
        let length = if major == 2 { 64 } else { 80 };
        let mut bytes = vec![0u8; length + 8];
        bytes[..8].copy_from_slice(&99u64.to_le_bytes());
        bytes[8..12].copy_from_slice(&(length as u32).to_le_bytes());
        bytes[12..14].copy_from_slice(&major.to_le_bytes());
        bytes[16..24].copy_from_slice(&id[0].to_le_bytes());
        if major == 3 {
            bytes[24..32].copy_from_slice(&id[1].to_le_bytes());
        }
        let name = if major == 2 { 58 } else { 74 };
        bytes[8 + name..10 + name]
            .copy_from_slice(&(if major == 2 { 60u16 } else { 76u16 }).to_le_bytes());
        bytes
    }
    #[test]
    fn parser_matches_64_and_128_bit_ids_and_rejects_unknown_or_truncated_records() {
        assert_eq!(
            scan_records(&record(2, [7, 0]), &[[7, 0]]),
            Some((99, true))
        );
        assert_eq!(
            scan_records(&record(3, [7, 9]), &[[7, 0], [7, 9]]),
            Some((99, true))
        );
        assert_eq!(
            scan_records(&record(3, [7, 9]), &[[7, 0]]),
            Some((99, false))
        );
        assert!(scan_records(&record(4, [7, 9]), &[]).is_none());
        let bytes = record(2, [7, 0]);
        assert!(scan_records(&bytes[..bytes.len() - 1], &[]).is_none());
    }

    #[test]
    fn batches_namespace_events_and_directory_retargets_without_sibling_data_writes() {
        let mut bytes = record(2, [8, 0]);
        // Parent 7, create event: a previously absent/shadowing child appeared.
        bytes[24..32].copy_from_slice(&7u64.to_le_bytes());
        bytes[48..52].copy_from_slice(&0x100u32.to_le_bytes());
        assert_eq!(
            scan_records_batched(&bytes, &[], &[], &[[7, 0]]),
            Some((99, true))
        );
        bytes[48..52].copy_from_slice(&1u32.to_le_bytes());
        assert_eq!(
            scan_records_batched(&bytes, &[], &[], &[[7, 0]]),
            Some((99, false))
        );
        // A junction/ancestor reparse target change invalidates its descendants.
        bytes[48..52].copy_from_slice(&0x10_0000u32.to_le_bytes());
        assert_eq!(
            scan_records_batched(&bytes, &[], &[[8, 0]], &[]),
            Some((99, true))
        );
    }

    #[cfg(windows)]
    #[test]
    fn shared_missing_candidate_ancestors_detect_directory_creation() {
        let root = std::env::temp_dir().join(format!(
            "dm-shared-namespace-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        std::fs::create_dir_all(&root).unwrap();
        let candidates = (0..64)
            .map(|index| root.join(format!("missing/nested/{index}.dmi")))
            .collect::<Vec<_>>();
        if let Some(proof) = JournalProof::establish_namespaces(&BTreeMap::new(), &candidates) {
            assert!(proof.current());
            std::fs::create_dir_all(root.join("missing/nested")).unwrap();
            std::fs::write(&candidates[0], "shadow").unwrap();
            assert!(!proof.current());
        }
        std::fs::remove_dir_all(root).unwrap();
    }

    #[cfg(windows)]
    #[test]
    fn held_ordinary_directory_rename_invalidates_original_paths() {
        use std::{fs, os::windows::fs::OpenOptionsExt};
        let root = std::env::temp_dir().join(format!(
            "dm-directory-proof-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        let original = root.join("original");
        let moved = root.join("moved");
        fs::create_dir_all(&original).unwrap();
        fs::write(original.join("source.dm"), "before").unwrap();
        let handle = fs::OpenOptions::new()
            .read(true)
            .write(true)
            .share_mode(7)
            .custom_flags(0x0200_0000)
            .open(&original)
            .unwrap();
        fs::rename(&original, &moved).unwrap();
        fs::rename(&moved, &original).unwrap();
        let path = original.join("source.dm");
        let files = [(path.clone(), crate::file_stamp::capture(&path).unwrap())]
            .into_iter()
            .collect();
        if let Some(proof) = JournalProof::establish(&files) {
            assert!(proof.current());
            fs::rename(&original, &moved).unwrap();
            fs::create_dir(&original).unwrap();
            fs::write(original.join("source.dm"), "after").unwrap();
            assert!(
                !proof.current(),
                "held directory rename must invalidate path replacement"
            );
        }
        drop(handle);
        fs::remove_dir_all(root).unwrap();
    }

    #[cfg(windows)]
    #[test]
    fn same_identity_junction_retarget_from_held_handle_invalidates() {
        use std::{
            fs,
            os::windows::{ffi::OsStrExt, fs::OpenOptionsExt, io::AsRawHandle},
        };
        #[link(name = "kernel32")]
        unsafe extern "system" {
            fn DeviceIoControl(
                handle: *mut std::ffi::c_void,
                code: u32,
                input: *const std::ffi::c_void,
                input_len: u32,
                output: *mut std::ffi::c_void,
                output_len: u32,
                returned: *mut u32,
                overlapped: *mut std::ffi::c_void,
            ) -> i32;
        }
        fn retarget(file: &fs::File, target: &Path) -> bool {
            let target = target.canonicalize().unwrap();
            let text = target.to_string_lossy();
            let print = std::ffi::OsStr::new(text.strip_prefix(r"\\?\").unwrap_or(&text))
                .encode_wide()
                .collect::<Vec<_>>();
            let substitute = format!(r"\??\{}", String::from_utf16_lossy(&print))
                .encode_utf16()
                .collect::<Vec<_>>();
            let path_len = (substitute.len() + print.len() + 2) * 2;
            let mut bytes = Vec::with_capacity(16 + path_len);
            bytes.extend_from_slice(&0xa000_0003u32.to_le_bytes());
            bytes.extend_from_slice(&((8 + path_len) as u16).to_le_bytes());
            bytes.extend_from_slice(&0u16.to_le_bytes());
            bytes.extend_from_slice(&0u16.to_le_bytes());
            bytes.extend_from_slice(&((substitute.len() * 2) as u16).to_le_bytes());
            bytes.extend_from_slice(&(((substitute.len() + 1) * 2) as u16).to_le_bytes());
            bytes.extend_from_slice(&((print.len() * 2) as u16).to_le_bytes());
            for value in substitute
                .into_iter()
                .chain(Some(0))
                .chain(print)
                .chain(Some(0))
            {
                bytes.extend_from_slice(&value.to_le_bytes());
            }
            let mut returned = 0;
            unsafe {
                DeviceIoControl(
                    file.as_raw_handle(),
                    0x900a4,
                    bytes.as_ptr().cast(),
                    bytes.len() as u32,
                    std::ptr::null_mut(),
                    0,
                    &mut returned,
                    std::ptr::null_mut(),
                ) != 0
            }
        }
        let root = std::env::temp_dir().join(format!(
            "dm-junction-proof-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        for name in ["a", "b", "link"] {
            fs::create_dir_all(root.join(name)).unwrap();
        }
        fs::write(root.join("a/source.dm"), "same").unwrap();
        fs::write(root.join("b/source.dm"), "same").unwrap();
        let handle = fs::OpenOptions::new()
            .read(true)
            .write(true)
            .share_mode(7)
            .custom_flags(0x0200_0000 | 0x0020_0000)
            .open(root.join("link"))
            .unwrap();
        if !retarget(&handle, &root.join("a")) {
            drop(handle);
            fs::remove_dir_all(root).unwrap();
            return;
        }
        assert!(retarget(&handle, &root.join("b")));
        assert!(retarget(&handle, &root.join("a")));
        let lexical = crate::file_stamp::directory(&root.join("link")).unwrap();
        let path = root.join("link/source.dm");
        let files = [(path.clone(), crate::file_stamp::capture(&path).unwrap())]
            .into_iter()
            .collect();
        if let Some(proof) = JournalProof::establish(&files) {
            assert!(proof.current());
            assert!(retarget(&handle, &root.join("b")));
            assert!(crate::file_stamp::directory(&root.join("link"))
                .unwrap()
                .same_object(&lexical));
            assert!(
                !proof.current(),
                "same-ID reparse change must not reuse old descendants"
            );
        }
        drop(handle);
        fs::remove_dir_all(root).unwrap();
    }

    #[cfg(windows)]
    #[test]
    fn sharing_barriers_reject_existing_readers_and_writers_and_detect_later_writes() {
        use std::io::{Seek, SeekFrom, Write};
        let dir = std::env::temp_dir().join(format!(
            "dm-journal-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join("source.dm");
        std::fs::write(&path, "before").unwrap();
        let files: BTreeMap<_, _> =
            [(path.clone(), crate::file_stamp::capture(&path).unwrap())].into();
        let reader = std::fs::File::open(&path).unwrap();
        assert!(
            JournalProof::establish(&files).is_none(),
            "existing readers can retain dirty USN flags and must block the baseline"
        );
        drop(reader);
        let mut writer = std::fs::OpenOptions::new().write(true).open(&path).unwrap();
        assert!(
            JournalProof::establish(&files).is_none(),
            "an unwritten existing writer must block the baseline"
        );
        writer.write_all(b"writer").unwrap();
        writer.flush().unwrap();
        assert!(
            crate::file_stamp::capture(&path).is_none(),
            "a coalescing writer must force exact input validation"
        );
        assert!(
            JournalProof::establish(&files).is_none(),
            "existing writers must block the baseline"
        );
        drop(writer);
        let files: BTreeMap<_, _> =
            [(path.clone(), crate::file_stamp::capture(&path).unwrap())].into();
        if let Some(proof) = JournalProof::establish(&files) {
            assert!(proof.current());
            std::fs::write(dir.join("unrelated.log"), "output").unwrap();
            assert!(
                proof.current(),
                "unrelated child creation must not invalidate the directory identity proof"
            );
            let mut writer = std::fs::OpenOptions::new().write(true).open(&path).unwrap();
            writer.write_all(b"first!").unwrap();
            writer.flush().unwrap();
            assert!(!proof.current());
            writer.seek(SeekFrom::Start(0)).unwrap();
            writer.write_all(b"second").unwrap();
            writer.flush().unwrap();
            assert!(
                !proof.current(),
                "coalesced subsequent writes cannot revive an invalid proof"
            );
        } else {
            eprintln!("journal unavailable; exercised conservative sharing-barrier fallback");
        }
        std::fs::remove_dir_all(dir).unwrap();
    }
}
