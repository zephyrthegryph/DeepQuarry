//! Conventional outputs remain writable copies, authenticated on every install.
use super::*;

#[cfg(test)]
pub(super) fn resource(source: &Path, destination: &Path, expected: (u64, u128)) -> io::Result<()> {
    resource_receipt(source, destination, expected).map(|_| ())
}
pub(super) fn resource_receipt(
    source: &Path,
    destination: &Path,
    expected: (u64, u128),
) -> io::Result<receipt::InstalledFile> {
    conventional_receipt(source, destination, expected)
}
/// Reuse only an exact, authenticated writable regular file. Immutable store
/// hardlinks/read-only outputs still require isolated atomic copy replacement.
pub(super) fn conventional_receipt(
    source: &Path,
    destination: &Path,
    expected: (u64, u128),
) -> io::Result<receipt::InstalledFile> {
    use crate::input_snapshot::{FileSystemInputs, SnapshotProvider};
    let reusable = fs::symlink_metadata(destination)
        .is_ok_and(|metadata| metadata.file_type().is_file() && !metadata.permissions().readonly());
    if reusable {
        // This full authenticated read is required for a previously writable output.
        if let Ok((stamp, hash)) = FileSystemInputs.digest(destination) {
            if (stamp.size, hash) == expected {
                return receipt::InstalledFile::after_replace(destination, stamp, hash);
            }
        }
    }
    replace_copy_receipt(source, destination, expected)
}

#[cfg(test)]
#[path = "publish_install_tests.rs"]
mod tests;
