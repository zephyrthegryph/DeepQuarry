//! Stream the unchanged DMBCSEG1 framing; no whole-segment byte Vec.
use super::*;
struct Temporary {
    path: PathBuf,
    file: Option<File>,
}
impl Drop for Temporary {
    fn drop(&mut self) {
        drop(self.file.take());
        let _ = std::fs::remove_file(&self.path);
    }
}
fn emit(output: &mut File, hash: &mut Xxh3, bytes: &[u8]) -> Result<(), CacheError> {
    output.write_all(bytes)?;
    hash.update(bytes);
    Ok(())
}
fn copy(
    source: &mut File,
    output: &mut File,
    hash: &mut Xxh3,
    extent: Extent,
) -> Result<(), CacheError> {
    source.seek(SeekFrom::Start(extent.at))?;
    let mut left = extent.len;
    let mut buffer = [0; COPY_BYTES];
    while left != 0 {
        let count = left.min(COPY_BYTES as u64) as usize;
        source.read_exact(&mut buffer[..count])?;
        emit(output, hash, &buffer[..count])?;
        left -= count as u64;
    }
    Ok(())
}
/// A spooled payload's original bytes.
fn read_payload(source: &mut File, extent: Extent) -> Result<Vec<u8>, CacheError> {
    source.seek(SeekFrom::Start(extent.at))?;
    let mut bytes = vec![0; extent.len as usize];
    source.read_exact(&mut bytes)?;
    if extent.packed {
        crate::segment::AlignedBytes::unpack(&bytes)
    } else {
        Ok(bytes)
    }
}
impl BatchSpool {
    pub(super) fn finish_inner(&mut self) -> Result<BatchReport, CacheError> {
        let count =
            u32::try_from(self.entries.len()).map_err(|_| invalid("record count overflow"))?;
        let metadata_len = self
            .entries
            .len()
            .checked_mul(DESCRIPTOR)
            .ok_or_else(|| invalid("metadata overflow"))?;
        let path = self.path.with_extension("segment.tmp");
        let file = OpenOptions::new()
            .read(true)
            .write(true)
            .create_new(true)
            .open(&path)?;
        let mut temporary = Temporary {
            path,
            file: Some(file),
        };
        let output = temporary.file.as_mut().unwrap();
        let body_at = HEADER
            .checked_add(metadata_len as u64)
            .ok_or_else(|| invalid("metadata overflow"))?;
        output.seek(SeekFrom::Start(body_at))?;
        let source = self.file.as_mut().ok_or_else(|| invalid("closed batch"))?;
        let mut metadata = Vec::with_capacity(metadata_len);
        let mut variants = 0usize;
        for (key, entry) in &self.entries {
            let at = output.stream_position()?;
            let mut checksum = Xxh3::new();
            let symbol_count =
                u32::try_from(entry.symbols.len()).map_err(|_| invalid("symbol count overflow"))?;
            emit(output, &mut checksum, &symbol_count.to_le_bytes())?;
            for (id, extent) in &entry.symbols {
                let len = u32::try_from(extent.len).map_err(|_| invalid("symbol text overflow"))?;
                emit(output, &mut checksum, &id.to_le_bytes())?;
                emit(output, &mut checksum, &len.to_le_bytes())?;
                copy(source, output, &mut checksum, *extent)?;
            }
            // The record's logical payload (the variant frame around the spooled variants, or the one raw payload), packed exactly as
            // the in-memory encoder packs it so both writers produce identical segments.
            let mut logical = Vec::new();
            if entry.framed {
                let count = u32::try_from(entry.payloads.len())
                    .map_err(|_| invalid("variant count overflow"))?;
                logical.extend_from_slice(b"DMCVAR01");
                logical.extend_from_slice(&count.to_le_bytes());
            }
            for extent in &entry.payloads {
                let bytes = read_payload(source, *extent)?;
                if entry.framed {
                    logical.extend_from_slice(&(bytes.len() as u64).to_le_bytes());
                }
                logical.extend_from_slice(&bytes);
            }
            let packed = crate::segment::pack_payload(key.stage, &logical);
            let stored: &[u8] = packed.as_deref().unwrap_or(&logical);
            let payload_len = stored.len() as u64
                | if packed.is_some() { crate::segment::COMPRESSED } else { 0 };
            emit(output, &mut checksum, &payload_len.to_le_bytes())?;
            let padding = (16 - output.stream_position()? % 16) % 16;
            emit(output, &mut checksum, &[0; 16][..padding as usize])?;
            emit(output, &mut checksum, stored)?;
            variants = variants
                .checked_add(entry.payloads.len())
                .ok_or_else(|| invalid("variant count overflow"))?;
            metadata.extend_from_slice(&key.stage.to_le_bytes());
            metadata.extend_from_slice(&key.version.to_le_bytes());
            metadata.extend_from_slice(&key.content.to_le_bytes());
            metadata.extend_from_slice(&at.to_le_bytes());
            metadata.extend_from_slice(&(output.stream_position()? - at).to_le_bytes());
            metadata.extend_from_slice(&checksum.digest128().to_le_bytes());
        }
        let length = output.stream_position()?;
        let mut identity = Xxh3::new();
        identity.update(&metadata);
        output.seek(SeekFrom::Start(body_at))?;
        let mut buffer = [0; COPY_BYTES];
        let mut left = length - body_at;
        while left != 0 {
            let n = left.min(COPY_BYTES as u64) as usize;
            output.read_exact(&mut buffer[..n])?;
            identity.update(&buffer[..n]);
            left -= n as u64;
        }
        let id = identity.digest128();
        let mut header = Vec::with_capacity(HEADER as usize);
        header.extend_from_slice(b"DMBCSEG1");
        header.extend_from_slice(&crate::segment::FORMAT.to_le_bytes());
        header.extend_from_slice(&0u32.to_le_bytes());
        header.extend_from_slice(&length.to_le_bytes());
        header.extend_from_slice(&(metadata_len as u64).to_le_bytes());
        header.extend_from_slice(&count.to_le_bytes());
        header.extend_from_slice(&0u32.to_le_bytes());
        header.extend_from_slice(&id.to_le_bytes());
        let mut framing = Xxh3::new();
        framing.update(&header);
        framing.update(&metadata);
        header.extend_from_slice(&framing.digest128().to_le_bytes());
        output.seek(SeekFrom::Start(0))?;
        output.write_all(&header)?;
        output.write_all(&metadata)?;
        output.flush()?;
        drop(temporary.file.take());
        let validated = crate::Segment::open(&temporary.path, self.cache.limits)?;
        if validated.id() != id {
            return Err(invalid("spooled segment identity differs"));
        }
        drop(validated);
        self.cache.publish_staged_file(id, &temporary.path, "seg")?;
        Ok(BatchReport {
            segment: Some(id),
            records: self.entries.len(),
            variants,
        })
    }
}
