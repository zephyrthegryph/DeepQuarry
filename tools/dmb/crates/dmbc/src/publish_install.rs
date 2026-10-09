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
    let reusable = crate::input_snapshot::isolated_output_stamp(destination)
        .is_ok_and(|stamp| stamp.is_some());
    if reusable {
        // This full authenticated read is required for a previously writable output.
        if let Ok((stamp, hash)) = FileSystemInputs.digest(destination) {
            if (stamp.size, hash) == expected
                && crate::input_snapshot::isolated_output_stamp(destination)
                    .is_ok_and(|isolated| isolated.as_ref() == Some(&stamp))
            {
                return receipt::InstalledFile::after_replace(destination, stamp, hash);
            }
        }
    }
    replace_copy_receipt(source, destination, expected)
}

#[cfg(test)]
#[path = "publish_install_tests.rs"]
mod tests;

#[path = "publish_install_prior.rs"]
mod prior;
pub(crate) use prior::PriorResourceProof;
pub(super) fn resource_receipt_with_prior(
    source: &Path,
    destination: &Path,
    expected: (u64, u128),
    prior: Option<PriorResourceProof<'_>>,
    exact: bool,
) -> io::Result<receipt::InstalledFile> {
    if let Some(prior) = prior {
        if let Ok(Some(receipt)) = prior.authenticate(destination, expected, exact) {
            return Ok(receipt);
        }
    }
    resource_receipt(source, destination, expected)
}

pub(crate) struct ResourceInstall<'a> {
    pub prepared: Option<PreparedOutputFile>,
    pub prior: Option<PriorResourceProof<'a>>,
}
