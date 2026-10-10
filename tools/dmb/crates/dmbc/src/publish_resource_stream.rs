//! File-backed resource production in the existing immutable publication store.
use super::*;
use fs2::FileExt;
use std::io::{BufWriter, Write};

/// Keeps an immutable archive reachable until its output pair is committed.
pub struct ResourcePin(File);
impl Drop for ResourcePin {
    fn drop(&mut self) {
        let _ = FileExt::unlock(&self.0);
    }
}
impl PairStore {
    pub(super) fn resource_pin_file(&self, identity: ResourceIdentity) -> io::Result<File> {
        OpenOptions::new()
            .read(true)
            .write(true)
            .create(true)
            .truncate(false)
            .open(
                self.root
                    .join("resource-pins")
                    .join(format!("{:032x}-{}.lock", identity.hash, identity.bytes)),
            )
    }
    /// Authenticate an existing immutable archive without reading an unrelated
    /// output pair. The shared pin remains held through the caller's publication.
    /// Exact mode still hashes the complete archive; ordinary mode uses the same
    /// boot/inode receipt policy as every other resource admission.
    pub fn verify_resource_pinned(
        &self,
        identity: ResourceIdentity,
        exact: bool,
    ) -> io::Result<ResourcePin> {
        let _lock = self.lock()?;
        let path = self
            .root
            .join("resources")
            .join(format!("{:032x}-{}.rsc", identity.hash, identity.bytes));
        self.authenticate_resource(&path, identity, exact)?;
        self.pin_resource(identity)
    }
    fn pin_resource(&self, identity: ResourceIdentity) -> io::Result<ResourcePin> {
        let file = self.resource_pin_file(identity)?;
        FileExt::lock_shared(&file)?;
        Ok(ResourcePin(file))
    }
}
struct HashWriter<W> {
    output: W,
    hash: Xxh3,
    bytes: u64,
}
impl<W: Write> Write for HashWriter<W> {
    fn write(&mut self, bytes: &[u8]) -> io::Result<usize> {
        let accepted = self.output.write(bytes)?;
        self.bytes = self
            .bytes
            .checked_add(accepted as u64)
            .ok_or_else(|| invalid("streamed archive length overflow"))?;
        self.hash.update(&bytes[..accepted]);
        Ok(accepted)
    }
    fn flush(&mut self) -> io::Result<()> {
        self.output.flush()
    }
}
fn encode_into<W: Write>(
    output: W,
    resources: &[byond_dmb::rsc::NamedResourceView<'_>],
) -> io::Result<(W, ResourceIdentity)> {
    let mut writer = HashWriter {
        output,
        hash: Xxh3::new(),
        bytes: 0,
    };
    for resource in resources {
        byond_dmb::rsc::write_named_view(&mut writer, resource)?;
    }
    writer.flush()?;
    let identity = ResourceIdentity {
        bytes: writer.bytes,
        hash: writer.hash.digest128(),
    };
    Ok((writer.output, identity))
}
fn encode(
    file: File,
    resources: &[byond_dmb::rsc::NamedResourceView<'_>],
) -> io::Result<(File, ResourceIdentity)> {
    let (output, identity) = encode_into(BufWriter::with_capacity(128 * 1024, file), resources)?;
    let file = output.into_inner().map_err(|error| error.into_error())?;
    file.sync_all()?;
    Ok((file, identity))
}
fn same_bytes(left: &Path, right: &Path) -> io::Result<bool> {
    let mut left = File::open(left)?;
    let mut right = File::open(right)?;
    let mut a = [0u8; 64 * 1024];
    let mut b = [0u8; 64 * 1024];
    loop {
        let count = left.read(&mut a)?;
        if count == 0 {
            return Ok(right.read(&mut b)? == 0);
        }
        match right.read_exact(&mut b[..count]) {
            Ok(()) => (),
            Err(error) if error.kind() == io::ErrorKind::UnexpectedEof => return Ok(false),
            Err(error) => return Err(error),
        }
        if a[..count] != b[..count] {
            return Ok(false);
        }
    }
}
impl PairStore {
    /// Stream an archive once into this publication store, then reuse its identity.
    /// No pair or conventional outputs are committed here. A caller may fall back
    /// to its memory encoder on IO failure and preserve compilation error ordering.
    pub fn publish_resource_views(
        &self,
        resources: &[byond_dmb::rsc::NamedResourceView<'_>],
        exact: bool,
    ) -> io::Result<ResourceIdentity> {
        self.publish_resource_views_pinned(resources, exact)
            .map(|(identity, _pin)| identity)
    }
    /// Pin acquisition and archive publication share the store lock, closing the
    /// gap in which maintenance could remove an old reused orphan archive.
    pub fn publish_resource_views_pinned(
        &self,
        resources: &[byond_dmb::rsc::NamedResourceView<'_>],
        exact: bool,
    ) -> io::Result<(ResourceIdentity, ResourcePin)> {
        self.publish_resource_views_prepared(resources, exact, None)
            .map(|(identity, pin, _)| (identity, pin))
    }
    /// Produce an isolated conventional resource staging file during the
    /// canonical probe. Its destination is untouched until pair installation.
    pub fn publish_resource_views_prepared(
        &self,
        resources: &[byond_dmb::rsc::NamedResourceView<'_>],
        exact: bool,
        conventional_rsc: Option<&Path>,
    ) -> io::Result<(ResourceIdentity, ResourcePin, Option<PreparedOutputFile>)> {
        let _profile = dm_profile::stage("publication.resource_stream");
        // One aggregate observation avoids per-record profiler/syscall overhead.
        // On secondary failure only successful certified bytes are attributed;
        // partial failed writes remain in independent process IO counters.
        let (expected, prepared) = dm_profile::io_call(
            || {
                let (probe, expected) =
                    encode_into(prepared::ProbeOutput::new(conventional_rsc), resources)?;
                Ok((expected, probe.finish(expected)))
            },
            |(expected, prepared)| {
                (
                    0,
                    if prepared.is_some() {
                        expected.bytes
                    } else {
                        0
                    },
                )
            },
        )?;
        let destination = self
            .root
            .join("resources")
            .join(format!("{:032x}-{}.rsc", expected.hash, expected.bytes));
        {
            let _lock = self.lock()?;
            if destination.exists() {
                self.authenticate_resource(&destination, expected, exact)?;
                return Ok((expected, self.pin_resource(expected)?, prepared));
            }
        }
        #[cfg(test)]
        publication_fault("resource_stream_writer_open")?;
        let staged = StagedPath::new(self.temporary("resource-stream")?);
        let path = staged.path().join("archive.rsc");
        let file = OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(&path)?;
        let (file, identity) = dm_profile::io_call(
            || encode(file, resources),
            |(_, identity)| (0, identity.bytes),
        )?;
        if identity != expected {
            return Err(invalid("streamed archive differs from canonical probe"));
        }
        let stamp = publication_io::finish_owned(file, &path)?;
        if stamp.size != identity.bytes {
            return Err(invalid("streamed archive writer size mismatch"));
        }
        #[cfg(test)]
        publication_fault("resource_stream_written")?;
        let _lock = self.lock()?;
        let destination = self
            .root
            .join("resources")
            .join(format!("{:032x}-{}.rsc", identity.hash, identity.bytes));
        if destination.exists() {
            let before = self.authenticate_resource(&destination, identity, exact)?;
            if !same_bytes(&path, &destination)? {
                return Err(invalid("shared resource content identity collision"));
            }
            use crate::input_snapshot::SnapshotProvider;
            if crate::input_snapshot::FileSystemInputs.stamp(&destination)? != before {
                return Err(invalid("shared resource changed during collision check"));
            }
            return Ok((identity, self.pin_resource(identity)?, prepared));
        }
        let mut permissions = fs::metadata(&path)?.permissions();
        permissions.set_readonly(true);
        fs::set_permissions(&path, permissions)?;
        fs::rename(&path, &destination)?;
        let destination_cleanup = StagedPath::new(destination.clone());
        #[cfg(test)]
        publication_fault("resource_stream_renamed")?;
        self.remember_resource(&destination, identity, &stamp)?;
        destination_cleanup.preserve();
        Ok((identity, self.pin_resource(identity)?, prepared))
    }
}
#[cfg(test)]
#[path = "publish_resource_stream/tests.rs"]
mod tests;
