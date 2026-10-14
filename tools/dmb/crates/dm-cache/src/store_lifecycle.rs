//! Disposable immutable cache leaves, evicted by age without session roots.
use super::*;
use std::{
    io::Read,
    time::{Duration, SystemTime},
};

#[derive(Debug, Default)]
pub struct EvictionReport {
    pub expired: usize,
    pub deleted: usize,
    pub ignored: usize,
    pub deferred_deletes: Vec<PathBuf>,
}
impl Cache {
    /// Delete authenticated, typed-valid immutable leaves older than `retention`.
    /// Existing readers keep their maps. Windows sharing violations defer removal
    /// until the next maintenance pass; writers never acquire this maintenance lock.
    /// Modification times in the future are retained. No temporary or legacy lease
    /// file is inspected, updated, repaired or deleted.
    pub fn evict_older_than(
        &self,
        now: SystemTime,
        retention: Duration,
        validate: impl Fn(RecordKey, &[u8], &[(u64, &[u8])]) -> Result<(), String>,
    ) -> Result<EvictionReport, CacheError> {
        check_root(&self.root)?;
        let _lock = self.compact_lock(false)?;
        let mut paths = Vec::new();
        for entry in fs::read_dir(&self.root)? {
            let entry = entry?;
            let path = entry.path();
            if path
                .extension()
                .is_some_and(|ext| ext == "seg" || ext == "grp")
            {
                paths.push(path);
            }
        }
        paths.sort();
        let mut report = EvictionReport::default();
        for path in paths {
            let metadata = match fs::symlink_metadata(&path) {
                Ok(metadata) if metadata.is_file() && !reparse(&metadata) => metadata,
                _ => {
                    report.ignored += 1;
                    continue;
                }
            };
            let modified = metadata.modified()?;
            if now.duration_since(modified).is_err()
                || now.duration_since(modified).unwrap_or_default() <= retention
            {
                continue;
            }
            let valid = if path.extension().is_some_and(|ext| ext == "seg") {
                validate_segment(&path, self.limits, &validate)
            } else {
                validate_group(&path)
            };
            if valid.is_err() {
                report.ignored += 1;
                continue;
            }
            // Recheck the leaf after validation. No mutable index or lease can
            // authorize a replaced file. Concurrent disappearance is harmless.
            let current = match fs::symlink_metadata(&path) {
                Ok(current) => current,
                Err(error) if error.kind() == std::io::ErrorKind::NotFound => continue,
                Err(error) => return Err(error.into()),
            };
            if !current.is_file()
                || reparse(&current)
                || current.len() != metadata.len()
                || current.modified()? != modified
            {
                report.ignored += 1;
                continue;
            }
            report.expired += 1;
            match fs::remove_file(&path) {
                Ok(()) => report.deleted += 1,
                Err(error) if error.kind() == std::io::ErrorKind::NotFound => (),
                Err(_) => report.deferred_deletes.push(path),
            }
        }
        Ok(report)
    }
}
fn validate_segment(
    path: &Path,
    limits: Limits,
    validate: &impl Fn(RecordKey, &[u8], &[(u64, &[u8])]) -> Result<(), String>,
) -> Result<(), CacheError> {
    let segment = Segment::open(path, limits)?;
    check_name(path, segment.id())?;
    for key in segment.keys() {
        if segment
            .get(key, |bytes, symbols| validate(key, bytes, symbols))?
            .is_none()
        {
            return Err(CacheError::Invalid("rejected maintenance segment".into()));
        }
    }
    // This maintenance-owned mapping is dropped before attempting deletion.
    Ok(())
}
fn validate_group(path: &Path) -> Result<(), CacheError> {
    let file = fs::File::open(path)?;
    if file.metadata()?.len() > group_manifest::MAX_GROUP_BYTES as u64 {
        return Err(CacheError::Invalid("group metadata exceeds bound".into()));
    }
    let mut bytes = Vec::new();
    file.take(group_manifest::MAX_GROUP_BYTES as u64 + 1)
        .read_to_end(&mut bytes)?;
    let group = group_manifest::GroupManifest::decode(&bytes)?;
    check_name(path, group.id)
}
fn check_name(path: &Path, id: u128) -> Result<(), CacheError> {
    if path.file_stem().and_then(|name| name.to_str()) != Some(format!("{id:032x}").as_str()) {
        return Err(CacheError::Invalid(
            "cache leaf identity/name mismatch".into(),
        ));
    }
    Ok(())
}
fn check_root(root: &Path) -> Result<(), CacheError> {
    if !root.is_absolute() || root.parent().is_none() {
        return Err(CacheError::Invalid(
            "maintenance requires an absolute cache directory".into(),
        ));
    }
    for ancestor in root.ancestors() {
        let metadata = fs::symlink_metadata(ancestor)?;
        if !metadata.is_dir() || reparse(&metadata) {
            return Err(CacheError::Invalid(
                "cache maintenance refuses reparse ancestors".into(),
            ));
        }
    }
    Ok(())
}
fn reparse(metadata: &fs::Metadata) -> bool {
    if metadata.file_type().is_symlink() {
        return true;
    }
    #[cfg(windows)]
    {
        use std::os::windows::fs::MetadataExt;
        if metadata.file_attributes() & 0x400 != 0 {
            return true;
        }
    }
    false
}
#[cfg(test)]
#[path = "store_lifecycle_tests.rs"]
mod tests;
