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
/// A directory holding this file is a compile root: its conventional outputs are hard links to the immutable store files, not
/// copies (`tools/build/lib/compile_root.ts` writes the marker). A user-visible worktree never has it, so its outputs stay
/// independent writable files that a tool may overwrite in place. `DMB_INSTALL_LINK=0` turns linking off.
pub const LINK_MARKER: &str = ".dmb-link-outputs";
pub(super) fn links_allowed(destination: &Path) -> bool {
    std::env::var_os("DMB_INSTALL_LINK").map_or(true, |value| value != "0")
        && destination
            .parent()
            .is_some_and(|directory| directory.join(LINK_MARKER).is_file())
}
/// The destination already is the store file (same volume and file identity): a linked output, identical by construction because
/// store files are sealed read-only and never rewritten.
fn same_file(source: &Path, destination: &Path) -> bool {
    use crate::input_snapshot::{FileSystemInputs, SnapshotProvider};
    match (FileSystemInputs.stamp(source), FileSystemInputs.stamp(destination)) {
        (Ok(a), Ok(b)) => a.file_id.is_some() && a.file_id == b.file_id && a.size == b.size,
        _ => false,
    }
}
/// Make `destination` a hard link to `source`, replacing what is there. Falls back to an ordinary copy where the filesystem
/// cannot link (another volume).
fn link_receipt(
    source: &Path,
    destination: &Path,
    expected: (u64, u128),
) -> io::Result<receipt::InstalledFile> {
    use crate::input_snapshot::{FileSystemInputs, SnapshotProvider};
    if same_file(source, destination) {
        let stamp = FileSystemInputs.stamp(destination)?;
        if stamp.size == expected.0 {
            return receipt::InstalledFile::after_replace(destination, stamp, expected.1);
        }
    }
    let _profile = dm_profile::stage("publication.install_link");
    let parent = destination
        .parent()
        .filter(|path| !path.as_os_str().is_empty())
        .unwrap_or(Path::new("."));
    fs::create_dir_all(parent)?;
    let staged = parent.join(format!(
        ".dmbd-link-{}-{}.tmp",
        std::process::id(),
        TEMP_SEQUENCE.fetch_add(1, Ordering::Relaxed)
    ));
    let _ = fs::remove_file(&staged);
    if fs::hard_link(source, &staged).is_err() {
        return replace_copy_receipt(source, destination, expected);
    }
    let _cleanup = StagedPath::new(staged.clone());
    // (`atomic_replace` replaces a read-only previous link by name; it never clears the attribute the store file shares.)
    atomic_replace(&staged, destination)?;
    let stamp = FileSystemInputs.stamp(destination)?;
    if stamp.size != expected.0 {
        return Err(invalid("linked output size differs from its pair"));
    }
    receipt::InstalledFile::after_replace(destination, stamp, expected.1)
}
/// The destination as an exact, authenticated writable regular file, when it already is one: the install then writes nothing.
pub(super) fn reusable_receipt(
    destination: &Path,
    expected: (u64, u128),
) -> Option<receipt::InstalledFile> {
    use crate::input_snapshot::{FileSystemInputs, SnapshotProvider};
    crate::input_snapshot::isolated_output_stamp(destination)
        .ok()
        .flatten()?;
    // This full authenticated read is required for a previously writable output.
    let (stamp, hash) = FileSystemInputs.digest(destination).ok()?;
    ((stamp.size, hash) == expected
        && crate::input_snapshot::isolated_output_stamp(destination)
            .is_ok_and(|isolated| isolated.as_ref() == Some(&stamp)))
    .then(|| receipt::InstalledFile::after_replace(destination, stamp, hash).ok())
    .flatten()
}
/// Reuse only an exact, authenticated writable regular file. Immutable store
/// hardlinks/read-only outputs still require isolated atomic copy replacement,
/// except in a compile root, whose outputs are links to the store file.
pub(super) fn conventional_receipt(
    source: &Path,
    destination: &Path,
    expected: (u64, u128),
) -> io::Result<receipt::InstalledFile> {
    if links_allowed(destination) {
        return link_receipt(source, destination, expected);
    }
    if let Some(receipt) = reusable_receipt(destination, expected) {
        return Ok(receipt);
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
