//! Current output input admission, shared with the ordinary build pipeline.
pub(super) fn capture_output_digest(
    snapshot: &mut dmbc::input_snapshot::InputSnapshot,
    path: &std::path::Path,
) -> io::Result<()> {
    use dmbc::input_snapshot::{FileSystemInputs, SnapshotProvider};
    let (stamp, content) = FileSystemInputs.digest(path)?;
    snapshot.record_verified_digest(path, stamp, content)
}
