//! Sealed, short-lived evidence for authenticated conventional installations.
use super::*;
use crate::input_snapshot::{FileSystemInputs, InputSnapshot, SnapshotProvider, Stamp};

pub(super) struct InstalledFile {
    path: PathBuf,
    stamp: Stamp,
    content: u128,
}
impl InstalledFile {
    pub(super) fn after_replace(path: &Path, producer: Stamp, content: u128) -> io::Result<Self> {
        let stamp = FileSystemInputs.stamp(path)?;
        if stamp != producer {
            return Err(invalid("installed output inode changed during replacement"));
        }
        Ok(Self {
            path: path.to_owned(),
            stamp,
            content,
        })
    }
}
/// Fields and constructors remain private: only authenticated publication can issue this proof.
pub struct InstallationReceipt {
    pub(super) files: Vec<InstalledFile>,
    pub(super) exact: bool,
}
impl InstallationReceipt {
    pub fn record_outputs(&self, snapshot: &mut InputSnapshot) -> io::Result<()> {
        for file in &self.files {
            if self.exact {
                let (stamp, digest) = FileSystemInputs.digest(&file.path)?;
                if stamp != file.stamp || digest != file.content {
                    return Err(invalid("installed exact output changed before capture"));
                }
                snapshot.record_verified_digest(&file.path, stamp, digest)?;
            } else {
                if FileSystemInputs.stamp(&file.path)? != file.stamp {
                    return Err(invalid("installed output changed before capture"));
                }
                snapshot.record_verified_digest(&file.path, file.stamp.clone(), file.content)?;
            }
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn installed_receipt_rejects_changed_output_before_recording() {
        let store = super::super::tests::store();
        let pair = store.publish(1, b"dmb", b"rsc").unwrap();
        let dmb = store.root.join("output.dmb");
        let rsc = store.root.join("output.rsc");
        let marker = store.root.join("output.json");
        let receipt = store
            .install_receipt_exact(pair.id, &dmb, &rsc, &marker, false)
            .unwrap();
        receipt.record_outputs(&mut InputSnapshot::new(0)).unwrap();
        fs::write(&rsc, b"resource changed after authenticated installation").unwrap();
        assert!(receipt.record_outputs(&mut InputSnapshot::new(0)).is_err());
    }
    #[test]
    fn exact_receipt_rechecks_all_installed_contents() {
        let store = super::super::tests::store();
        let pair = store.publish(2, b"dmb", b"rsc").unwrap();
        let dmb = store.root.join("output.dmb");
        let rsc = store.root.join("output.rsc");
        let marker = store.root.join("output.json");
        let receipt = store
            .install_receipt_exact(pair.id, &dmb, &rsc, &marker, true)
            .unwrap();
        receipt.record_outputs(&mut InputSnapshot::new(0)).unwrap();
        fs::write(&dmb, b"bad").unwrap();
        assert!(receipt.record_outputs(&mut InputSnapshot::new(0)).is_err());
    }
}
