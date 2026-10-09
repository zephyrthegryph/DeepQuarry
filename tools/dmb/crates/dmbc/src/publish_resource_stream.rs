//! File-backed resource production in the existing immutable publication store.
use super::*;
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
        let _profile = dm_profile::stage("publication.resource_stream");
        let (_, expected) = encode_into(io::sink(), resources)?;
        let destination = self
            .root
            .join("resources")
            .join(format!("{:032x}-{}.rsc", expected.hash, expected.bytes));
        {
            let _lock = self.lock()?;
            if destination.exists() {
                self.authenticate_resource(&destination, expected, exact)?;
                return Ok((expected, self.pin_resource(expected)?));
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
            return Ok((identity, self.pin_resource(identity)?));
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
        Ok((identity, self.pin_resource(identity)?))
    }
}
#[cfg(test)]
#[path = "publish_resource_stream/tests.rs"]
mod tests;
