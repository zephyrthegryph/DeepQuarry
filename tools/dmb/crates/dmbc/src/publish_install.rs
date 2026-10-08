//! Conventional resources remain writable copies, authenticated on every install.
use super::*;

pub(super) fn resource(source: &Path, destination: &Path, expected: (u64, u128)) -> io::Result<()> {
    // Never turn a read-only store link or symlink into a writable output.
    // A failed destination read is repaired through the original copy path.
    let reusable = fs::symlink_metadata(destination).is_ok_and(|metadata| {
        metadata.file_type().is_file()
            && !metadata.permissions().readonly()
            && file_identity(destination).is_ok_and(|identity| identity == expected)
    });
    if reusable {
        Ok(())
    } else {
        replace_copy(source, destination, expected)
    }
}

#[cfg(test)]
#[path = "publish_install_tests.rs"]
mod tests;
