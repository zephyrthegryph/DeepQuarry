//! Prior conventional output facts are hints from an authenticated session record.
use super::*;
use crate::input_snapshot::{FileSystemInputs, InputSnapshot, SnapshotProvider, Stamp};

/// Crate-private: only the request runner supplies session-authenticated outputs.
#[derive(Clone, Copy)]
pub(crate) struct PriorResourceProof<'a> {
    snapshot: &'a InputSnapshot,
    now_ns: u128,
}
impl<'a> PriorResourceProof<'a> {
    pub(crate) fn new(snapshot: &'a InputSnapshot, now_ns: u128) -> Self {
        Self { snapshot, now_ns }
    }
    pub(super) fn authenticate(
        self,
        destination: &Path,
        expected: (u64, u128),
        exact: bool,
    ) -> io::Result<Option<receipt::InstalledFile>> {
        let Some(before) = crate::input_snapshot::isolated_output_stamp(destination)? else {
            return Ok(None);
        };
        let selected = self
            .snapshot
            .select_files(&[destination.to_owned()].into_iter().collect())?;
        let Some((stamp, hash)) =
            validate(&selected, &FileSystemInputs, expected, exact, self.now_ns)?
        else {
            return Ok(None);
        };
        // Bind the proof to the same actual isolated inode before and after validation.
        if before != stamp
            || crate::input_snapshot::isolated_output_stamp(destination)? != Some(stamp.clone())
        {
            return Ok(None);
        }
        receipt::InstalledFile::after_replace(destination, stamp, hash).map(Some)
    }
}
fn validate(
    snapshot: &InputSnapshot,
    provider: &impl SnapshotProvider,
    expected: (u64, u128),
    exact: bool,
    now_ns: u128,
) -> io::Result<Option<(Stamp, u128)>> {
    // Reject wrong pair content before using any filesystem metadata hint.
    let mut files = snapshot.files();
    let Some(file) = files.next() else {
        return Ok(None);
    };
    if files.next().is_some() || (file.stamp.size, file.content) != expected {
        return Ok(None);
    }
    let (validation, refreshed) = snapshot.validate(provider, exact, now_ns)?;
    if !validation.unchanged() {
        return Ok(None);
    }
    let validated = refreshed
        .files()
        .next()
        .map(|file| (file.stamp.clone(), file.content));
    Ok(validated)
}
#[cfg(test)]
#[path = "publish_install_prior_tests.rs"]
mod tests;
