//! Private writable staging authenticated from the actual encoder writer.
use super::*;
use crate::input_snapshot::{FileSystemInputs, SnapshotProvider, Stamp};
use std::io::{BufWriter, Write};
/// A sealed, destination-bound output owner. Drop cleans the private staging file.
pub struct PreparedOutputFile {
    staged: StagedPath,
    destination: PathBuf,
    stamp: Stamp,
    identity: ResourceIdentity,
}
impl PreparedOutputFile {
    pub(super) fn adopt(
        self,
        destination: &Path,
        expected: ResourceIdentity,
    ) -> io::Result<receipt::InstalledFile> {
        if self.identity != expected
            || !destinations::same_path(
                &self.destination,
                &destinations::absolute_identity(destination)?,
            )?
        {
            return Err(invalid("prepared output identity or destination differs"));
        }
        let metadata = fs::symlink_metadata(self.staged.path())?;
        if !metadata.file_type().is_file() || metadata.permissions().readonly() {
            return Err(invalid(
                "prepared output must remain an isolated writable file",
            ));
        }
        if FileSystemInputs.stamp(self.staged.path())? != self.stamp {
            return Err(invalid("prepared output changed before adoption"));
        }
        atomic_replace(self.staged.path(), destination)?;
        receipt::InstalledFile::after_replace(destination, self.stamp.clone(), self.identity.hash)
    }
}
/// Secondary IO is best effort: it cannot reorder compilation errors.
pub(super) struct ProbeOutput {
    writer: Option<(BufWriter<File>, StagedPath, PathBuf)>,
}
impl ProbeOutput {
    pub(super) fn new(destination: Option<&Path>) -> Self {
        let writer = destination.and_then(|destination| {
            let identity = destinations::absolute_identity(destination).ok()?;
            let staged = StagedPath::new(temporary_file(destination).ok()?);
            let file = OpenOptions::new().write(true).open(staged.path()).ok()?;
            Some((BufWriter::with_capacity(128 * 1024, file), staged, identity))
        });
        Self { writer }
    }
    pub(super) fn finish(mut self, identity: ResourceIdentity) -> Option<PreparedOutputFile> {
        let (mut writer, staged, destination) = self.writer.take()?;
        writer.flush().ok()?;
        let file = writer.into_inner().ok()?;
        file.sync_all().ok()?;
        let stamp = publication_io::finish_owned(file, staged.path()).ok()?;
        if stamp.size != identity.bytes {
            return None;
        }
        Some(PreparedOutputFile {
            staged,
            destination,
            stamp,
            identity,
        })
    }
}
impl Write for ProbeOutput {
    fn write(&mut self, bytes: &[u8]) -> io::Result<usize> {
        #[cfg(test)]
        if publication_fault("prepared_output_write").is_err() {
            self.writer.take();
        }
        if let Some((writer, _, _)) = self.writer.as_mut() {
            if writer.write_all(bytes).is_err() {
                self.writer.take();
            }
        }
        Ok(bytes.len())
    }
    fn flush(&mut self) -> io::Result<()> {
        if let Some((writer, _, _)) = self.writer.as_mut() {
            if writer.flush().is_err() {
                self.writer.take();
            }
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    fn entry() -> byond_dmb::rsc::NamedResource {
        byond_dmb::rsc::NamedResource::from_data(
            6,
            b"a.png".to_vec(),
            b"resource bytes".to_vec(),
            0,
            0,
        )
        .unwrap()
    }
    #[test]
    fn staging_keeps_destination_untouched_then_adopts_isolated_writer() {
        let store = super::super::tests::store();
        let destination = store.root.join("output.rsc");
        fs::write(&destination, b"old output").unwrap();
        let row = entry();
        let (identity, _pin, prepared) = store
            .publish_resource_views_prepared(&[row.as_view()], false, Some(&destination))
            .unwrap();
        assert_eq!(fs::read(&destination).unwrap(), b"old output");
        let prepared = prepared.unwrap();
        let path = prepared.staged.path().to_owned();
        let pair = store.publish_with_resource(1, b"dmb", identity).unwrap();
        let receipt = store
            .install_receipt_exact_with_prepared_resource(
                pair.id,
                &store.root.join("output.dmb"),
                &destination,
                &store.root.join("output.json"),
                false,
                Some(prepared),
            )
            .unwrap();
        receipt
            .record_outputs(&mut crate::input_snapshot::InputSnapshot::new(0))
            .unwrap();
        assert!(!path.exists());
        assert!(!fs::metadata(&destination).unwrap().permissions().readonly());
        let archive = store
            .root
            .join("resources")
            .join(format!("{:032x}-{}.rsc", identity.hash, identity.bytes));
        let before = fs::read(&archive).unwrap();
        assert_eq!(fs::read(&destination).unwrap(), before);
        fs::write(&destination, b"mutable output").unwrap();
        assert_eq!(fs::read(&archive).unwrap(), before);
    }
    #[test]
    fn tampered_identity_or_destination_rejects_and_cleans_private_stage() {
        let store = super::super::tests::store();
        let destination = store.root.join("output.rsc");
        let row = entry();
        for mode in 0..3 {
            let (identity, _pin, prepared) = store
                .publish_resource_views_prepared(&[row.as_view()], false, Some(&destination))
                .unwrap();
            let prepared = prepared.unwrap();
            let path = prepared.staged.path().to_owned();
            let mut expected = identity;
            let target = if mode == 1 {
                store.root.join("other.rsc")
            } else {
                destination.clone()
            };
            if mode == 0 {
                expected.hash ^= 1;
            }
            if mode == 2 {
                fs::write(&path, b"tamper").unwrap();
            }
            assert!(prepared.adopt(&target, expected).is_err());
            assert!(!path.exists());
            assert!(!destination.exists());
            assert!(!target.exists());
        }
    }
    #[test]
    fn failed_secondary_staging_keeps_primary_archive_and_pin() {
        let store = super::super::tests::store();
        let parent = store.root.join("not-a-directory");
        fs::write(&parent, b"block staging").unwrap();
        let row = entry();
        let (identity, _pin, prepared) = store
            .publish_resource_views_prepared(
                &[row.as_view()],
                false,
                Some(&parent.join("output.rsc")),
            )
            .unwrap();
        assert!(prepared.is_none());
        assert!(store
            .root
            .join("resources")
            .join(format!("{:032x}-{}.rsc", identity.hash, identity.bytes))
            .exists());
        assert_eq!(fs::read(parent).unwrap(), b"block staging");
    }
    #[test]
    fn failed_secondary_write_removes_stage_without_failing_archive() {
        let store = super::super::tests::store();
        let destination = store.root.join("output.rsc");
        fs::write(&destination, b"preserved").unwrap();
        let row = entry();
        FAULT.with(|fault| *fault.borrow_mut() = Some(("prepared_output_write", 2)));
        let (identity, _pin, prepared) = store
            .publish_resource_views_prepared(&[row.as_view()], false, Some(&destination))
            .unwrap();
        assert!(prepared.is_none());
        assert_eq!(fs::read(&destination).unwrap(), b"preserved");
        assert!(store.publish_with_resource(1, b"dmb", identity).is_ok());
        assert!(!fs::read_dir(&store.root).unwrap().any(|entry| entry
            .unwrap()
            .file_name()
            .to_string_lossy()
            .starts_with(".dmbd-install-")));
    }
}
