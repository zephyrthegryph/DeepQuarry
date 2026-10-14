//! Current output input admission, shared with the ordinary build pipeline.
use std::io;
pub(super) fn capture_output_digest(
    snapshot: &mut crate::input_snapshot::InputSnapshot,
    path: &std::path::Path,
) -> io::Result<()> {
    use crate::input_snapshot::{FileSystemInputs, SnapshotProvider};
    let (stamp, content) = FileSystemInputs.digest(path)?;
    snapshot.record_verified_digest(path, stamp, content)
}
