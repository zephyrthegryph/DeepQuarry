//! Output publication for compiled BYOND worlds.
//!
//! This crate deliberately separates *planning* from *publishing*. The planner
//! only patches when the complete desired serialization is known and has the
//! same length as the previous generation. A future indexed serializer can
//! provide that proof without materializing every unchanged record.

pub mod generation;
pub mod conventional;
pub mod list_image;
pub mod chunks;
pub mod object_directory;
pub mod typed_pages;
pub mod wire_image;
pub mod assembly;
pub mod wire_relocation;

use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::collections::HashSet;
use std::fs::{self, File, OpenOptions};
use std::io::{self, Cursor, Read, Seek, SeekFrom, Write};
use std::ops::Range;
use std::path::{Path, PathBuf};

#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum OutputKind {
    Dmb,
    Rsc,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct RecordSpan {
    /// Stable linker-provided identity, independent of global table indices.
    pub key: String,
    pub offset: u64,
    pub len: u64,
    /// Records with absolute-offset encodings must be re-serialized if moved.
    pub position_dependent: bool,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct LayoutIndex {
    pub kind: OutputKind,
    pub format_version: u32,
    pub image_len: u64,
    pub image_sha256: [u8; 32],
    /// Ordered, non-overlapping record spans; gaps are permitted for headers.
    pub records: Vec<RecordSpan>,
}

impl LayoutIndex {
    pub fn new(
        kind: OutputKind,
        format_version: u32,
        image: &[u8],
        records: Vec<RecordSpan>,
    ) -> io::Result<Self> {
        let index = Self {
            kind,
            format_version,
            image_len: image.len() as u64,
            image_sha256: digest(image),
            records,
        };
        index.validate(image)?;
        Ok(index)
    }

    pub fn validate(&self, image: &[u8]) -> io::Result<()> {
        if self.image_len != image.len() as u64 || self.image_sha256 != digest(image) {
            return Err(invalid("layout index does not match its image"));
        }
        let mut end = 0;
        for record in &self.records {
            if record.key.is_empty() || record.offset < end {
                return Err(invalid(
                    "layout records are unordered, overlapping, or unnamed",
                ));
            }
            end = record
                .offset
                .checked_add(record.len)
                .ok_or_else(|| invalid("layout span overflow"))?;
            if end > self.image_len {
                return Err(invalid("layout record extends past image"));
            }
        }
        Ok(())
    }

    /// Validate an index against a file without allocating an image-sized
    /// buffer. The caller's cursor is restored before returning.
    pub fn validate_reader<R: Read + Seek>(&self, reader: &mut R) -> io::Result<()> {
        let position = reader.stream_position()?;
        let result = (|| {
            reader.seek(SeekFrom::Start(0))?;
            let (length, hash) = digest_reader(reader)?;
            if length != self.image_len || hash != self.image_sha256 {
                return Err(invalid("layout index does not match its image"));
            }
            let mut end = 0;
            for record in &self.records {
                if record.key.is_empty() || record.offset < end {
                    return Err(invalid(
                        "layout records are unordered, overlapping, or unnamed",
                    ));
                }
                end = record
                    .offset
                    .checked_add(record.len)
                    .ok_or_else(|| invalid("layout span overflow"))?;
                if end > self.image_len {
                    return Err(invalid("layout record extends past image"));
                }
            }
            Ok(())
        })();
        reader.seek(SeekFrom::Start(position))?;
        result
    }
}

/// Index RSC entries without changing the archive's names, order, or wrappers.
/// Duplicate names are distinguished by ordinal; a linker may supply stronger
/// semantic keys in its own index.
pub fn index_rsc(image: &[u8]) -> io::Result<LayoutIndex> {
    let mut cursor = Cursor::new(image);
    let mut records = Vec::new();
    let mut ordinal = 0;
    loop {
        let start = cursor.position();
        let Some(entry) = byond_dmb::rsc::read_entry(&mut cursor)? else {
            break;
        };
        let key = match entry {
            byond_dmb::rsc::Entry::Named(resource) => {
                resource.asset_bytes()?;
                format!("entry:{ordinal}:name:{}", hex(&resource.name))
            }
            byond_dmb::rsc::Entry::Opaque { wrapper, .. } => {
                format!("entry:{ordinal}:wrapper:{wrapper}")
            }
        };
        records.push(RecordSpan {
            key,
            offset: start,
            len: cursor.position() - start,
            position_dependent: false,
        });
        ordinal += 1;
    }
    LayoutIndex::new(OutputKind::Rsc, 1, image, records)
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct SpanPatch {
    pub offset: u64,
    pub before: Vec<u8>,
    pub after: Vec<u8>,
}

impl SpanPatch {
    pub fn span(&self) -> Range<u64> {
        self.offset..self.offset + self.before.len() as u64
    }
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct FilePatch {
    pub old_len: u64,
    pub old_sha256: [u8; 32],
    pub new_sha256: [u8; 32],
    pub spans: Vec<SpanPatch>,
}

impl FilePatch {
    pub fn is_empty(&self) -> bool {
        self.spans.is_empty()
    }

    /// Verify every byte of the old generation before accepting a patch.
    pub fn apply_to_bytes(&self, current: &[u8]) -> io::Result<Vec<u8>> {
        if current.len() as u64 != self.old_len || digest(current) != self.old_sha256 {
            return Err(invalid("stale output generation"));
        }
        let mut result = current.to_vec();
        let mut previous_end = 0;
        for span in &self.spans {
            if span.before.len() != span.after.len() || span.offset < previous_end {
                return Err(invalid("invalid or overlapping patch span"));
            }
            let start =
                usize::try_from(span.offset).map_err(|_| invalid("patch offset exceeds usize"))?;
            let end = start
                .checked_add(span.before.len())
                .ok_or_else(|| invalid("patch span overflow"))?;
            if result.get(start..end) != Some(span.before.as_slice()) {
                return Err(invalid("patch undo bytes do not match old generation"));
            }
            result[start..end].copy_from_slice(&span.after);
            previous_end = end as u64;
        }
        if digest(&result) != self.new_sha256 {
            return Err(invalid("patch does not reconstruct desired generation"));
        }
        Ok(result)
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct PatchPolicy {
    /// Merge nearby changed runs to reduce seek overhead.
    pub merge_gap: usize,
    pub max_spans: usize,
    /// Fall back to a rebuild if patch writes exceed this fraction of the file.
    pub max_changed_percent: u8,
}

impl Default for PatchPolicy {
    fn default() -> Self {
        Self {
            merge_gap: 32,
            max_spans: 4096,
            max_changed_percent: 50,
        }
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum FilePlan {
    Unchanged,
    Patch(FilePatch),
    Rebuild { reason: RebuildReason },
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum RebuildReason {
    LengthChanged,
    TooManySpans,
    PatchTooLarge,
}

/// Compare complete serialized images. This is conservative even for DMB
/// strings, checksums, ID relocations, and RSC entry headers: all changed bytes
/// become part of the patch, and the reconstructed image is hash checked.
pub fn plan_file(old: &[u8], new: &[u8], policy: PatchPolicy) -> FilePlan {
    if old == new {
        return FilePlan::Unchanged;
    }
    if old.len() != new.len() {
        return FilePlan::Rebuild {
            reason: RebuildReason::LengthChanged,
        };
    }
    let mut spans: Vec<SpanPatch> = Vec::new();
    let mut at = 0;
    while at < old.len() {
        if old[at] == new[at] {
            at += 1;
            continue;
        }
        let start = at;
        while at < old.len() && old[at] != new[at] {
            at += 1;
        }
        if let Some(last) = spans.last_mut() {
            let previous_end = last.offset as usize + last.before.len();
            if start - previous_end <= policy.merge_gap {
                last.before.extend_from_slice(&old[previous_end..at]);
                last.after.extend_from_slice(&new[previous_end..at]);
                continue;
            }
        }
        spans.push(SpanPatch {
            offset: start as u64,
            before: old[start..at].to_vec(),
            after: new[start..at].to_vec(),
        });
        if spans.len() > policy.max_spans {
            return FilePlan::Rebuild {
                reason: RebuildReason::TooManySpans,
            };
        }
    }
    let changed: usize = spans.iter().map(|span| span.before.len()).sum();
    if changed.saturating_mul(100)
        > old
            .len()
            .saturating_mul(policy.max_changed_percent as usize)
    {
        return FilePlan::Rebuild {
            reason: RebuildReason::PatchTooLarge,
        };
    }
    let patch = FilePatch {
        old_len: old.len() as u64,
        old_sha256: digest(old),
        new_sha256: digest(new),
        spans,
    };
    debug_assert!(patch.apply_to_bytes(old).is_ok_and(|bytes| bytes == new));
    FilePlan::Patch(patch)
}

/// Plan a fixed-size patch from two seekable images without loading either
/// image wholesale. Only changed spans and a bounded comparison buffer are
/// retained. The input cursors are reset to the beginning and left at EOF.
/// The caller must still validate the resulting BYOND pair before publishing.
pub fn plan_file_streaming<O: Read + Seek, N: Read + Seek>(
    old: &mut O,
    new: &mut N,
    policy: PatchPolicy,
) -> io::Result<FilePlan> {
    let old_len = old.seek(SeekFrom::End(0))?;
    let new_len = new.seek(SeekFrom::End(0))?;
    old.seek(SeekFrom::Start(0))?;
    new.seek(SeekFrom::Start(0))?;
    if old_len != new_len {
        return Ok(FilePlan::Rebuild {
            reason: RebuildReason::LengthChanged,
        });
    }
    let mut old_hash = Sha256::new();
    let mut new_hash = Sha256::new();
    let mut old_buffer = [0u8; 8192];
    let mut new_buffer = [0u8; 8192];
    let mut spans = Vec::<SpanPatch>::new();
    let mut active: Option<SpanPatch> = None;
    let mut gap_before = Vec::<u8>::new();
    let mut gap_after = Vec::<u8>::new();
    let mut offset = 0u64;
    while offset < old_len {
        let count = usize::try_from((old_len - offset).min(old_buffer.len() as u64))
            .map_err(|_| invalid("comparison chunk exceeds usize"))?;
        old.read_exact(&mut old_buffer[..count])?;
        new.read_exact(&mut new_buffer[..count])?;
        old_hash.update(&old_buffer[..count]);
        new_hash.update(&new_buffer[..count]);
        for i in 0..count {
            let before = old_buffer[i];
            let after = new_buffer[i];
            if before == after {
                if active.is_some() {
                    gap_before.push(before);
                    gap_after.push(after);
                    if gap_before.len() > policy.merge_gap {
                        spans.push(active.take().expect("active span"));
                        gap_before.clear();
                        gap_after.clear();
                    }
                }
            } else if let Some(span) = active.as_mut() {
                span.before.append(&mut gap_before);
                span.after.append(&mut gap_after);
                span.before.push(before);
                span.after.push(after);
            } else {
                active = Some(SpanPatch {
                    offset: offset + i as u64,
                    before: vec![before],
                    after: vec![after],
                });
            }
        }
        offset += count as u64;
    }
    if let Some(span) = active {
        spans.push(span);
    }
    if spans.is_empty() {
        return Ok(FilePlan::Unchanged);
    }
    if spans.len() > policy.max_spans {
        return Ok(FilePlan::Rebuild {
            reason: RebuildReason::TooManySpans,
        });
    }
    let changed: u64 = spans.iter().map(|span| span.before.len() as u64).sum();
    if changed.saturating_mul(100) > old_len.saturating_mul(policy.max_changed_percent as u64) {
        return Ok(FilePlan::Rebuild {
            reason: RebuildReason::PatchTooLarge,
        });
    }
    Ok(FilePlan::Patch(FilePatch {
        old_len,
        old_sha256: old_hash.finalize().into(),
        new_sha256: new_hash.finalize().into(),
        spans,
    }))
}

/// A DMB/RSC pair is a single generation: one changed length rebuilds both.
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum PairPlan {
    Unchanged,
    Patch {
        old_dmb_sha256: [u8; 32],
        old_rsc_sha256: [u8; 32],
        dmb: Option<FilePatch>,
        rsc: Option<FilePatch>,
    },
    Rebuild {
        dmb_reason: Option<RebuildReason>,
        rsc_reason: Option<RebuildReason>,
    },
}

pub fn plan_pair(
    old_dmb: &[u8],
    old_rsc: &[u8],
    new_dmb: &[u8],
    new_rsc: &[u8],
    policy: PatchPolicy,
) -> PairPlan {
    let dmb = plan_file(old_dmb, new_dmb, policy);
    let rsc = plan_file(old_rsc, new_rsc, policy);
    let reason = |plan: &FilePlan| match plan {
        FilePlan::Rebuild { reason } => Some(*reason),
        _ => None,
    };
    if reason(&dmb).is_some() || reason(&rsc).is_some() {
        return PairPlan::Rebuild {
            dmb_reason: reason(&dmb),
            rsc_reason: reason(&rsc),
        };
    }
    let patch = |plan| match plan {
        FilePlan::Patch(patch) => Some(patch),
        _ => None,
    };
    match (patch(dmb), patch(rsc)) {
        (None, None) => PairPlan::Unchanged,
        (dmb, rsc) => PairPlan::Patch {
            old_dmb_sha256: digest(old_dmb),
            old_rsc_sha256: digest(old_rsc),
            dmb,
            rsc,
        },
    }
}

/// Validate the complete target pair before attempting publication.
pub fn validate_byond_pair(dmb: &[u8], rsc: &[u8]) -> io::Result<()> {
    validate_byond_pair_reader(dmb, &mut Cursor::new(rsc))
}

/// Validate a pair while consuming its RSC archive one entry at a time.
pub fn validate_byond_pair_reader(dmb: &[u8], rsc: &mut impl Read) -> io::Result<()> {
    let world = byond_dmb::dmb::Dmb::from_bytes(dmb)?;
    world.validate_references()?;
    let required: HashSet<_> = world
        .resources
        .iter()
        .map(|resource| (resource.id, resource.kind))
        .collect();
    let mut present = HashSet::new();
    let mut complete = HashSet::new();
    while let Some(entry) = byond_dmb::rsc::read_entry(rsc)? {
        if let byond_dmb::rsc::Entry::Named(resource) = entry {
            let key = (resource.id, resource.kind);
            if required.contains(&key) {
                present.insert(key);
                if resource.asset_bytes().is_ok() {
                    complete.insert(key);
                }
            }
        }
    }
    let missing = required.difference(&present).count();
    if missing != 0 {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            format!("DMB references {missing} resources absent from RSC"),
        ));
    }
    if complete.len() != required.len() {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            "DMB resource reference has no complete RSC asset",
        ));
    }
    Ok(())
}

#[derive(Clone, Debug, Serialize, Deserialize)]
struct UndoJournal {
    version: u32,
    dmb: Option<FilePatch>,
    rsc: Option<FilePatch>,
}

/// Apply an exact-length pair patch to exclusive, stopped-server outputs.
/// The caller must ensure no external reader holds either file. An OS file lock
/// prevents competing compiler writers; undo data is flushed first. The lock
/// file itself may remain after a crash because the OS releases its lock.
pub fn apply_pair_in_place(
    dmb_path: &Path,
    rsc_path: &Path,
    journal_path: &Path,
    plan: &PairPlan,
) -> io::Result<()> {
    apply_pair_in_place_with_validator(dmb_path, rsc_path, journal_path, plan, |dmb, rsc| {
        validate_byond_pair(&fs::read(dmb)?, &fs::read(rsc)?)
    })
}

/// Apply an already linked fixed-span pair using streaming hash and undo
/// checks. `validate` must reject invalid DMB/RSC pairs before publication is
/// committed; the default wrapper above uses the current in-memory codec.
/// A future streaming BYOND reader can be supplied without changing the
/// transaction and recovery protocol.
pub fn apply_pair_in_place_with_validator<F>(
    dmb_path: &Path,
    rsc_path: &Path,
    journal_path: &Path,
    plan: &PairPlan,
    validate: F,
) -> io::Result<()>
where
    F: Fn(&Path, &Path) -> io::Result<()>,
{
    let PairPlan::Patch {
        old_dmb_sha256,
        old_rsc_sha256,
        dmb,
        rsc,
    } = plan
    else {
        return Err(invalid("pair plan is not an in-place patch"));
    };
    let _lock = acquire_pair_lock(journal_path)?;
    let result = (|| {
        if journal_path.exists() {
            recover_pair_locked(dmb_path, rsc_path, journal_path)?;
        }
        if hash_file(dmb_path)? != *old_dmb_sha256 || hash_file(rsc_path)? != *old_rsc_sha256 {
            return Err(invalid("stale output pair"));
        }
        if let Some(p) = dmb {
            verify_patch_source(dmb_path, p)?;
        }
        if let Some(p) = rsc {
            verify_patch_source(rsc_path, p)?;
        }
        let journal = UndoJournal {
            version: 1,
            dmb: dmb.clone(),
            rsc: rsc.clone(),
        };
        let journal_bytes = serde_json::to_vec(&journal).map_err(io::Error::other)?;
        let pending_journal = journal_path.with_extension("pending");
        if pending_journal.exists() {
            fs::remove_file(&pending_journal)?;
        }
        let mut file = OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(&pending_journal)?;
        file.write_all(&journal_bytes)?;
        file.sync_all()?;
        fs::rename(&pending_journal, journal_path)?;
        if let Some(p) = dmb {
            write_spans(dmb_path, p)?;
        }
        if let Some(p) = rsc {
            write_spans(rsc_path, p)?;
        }
        let expected_dmb_hash = dmb.as_ref().map_or(*old_dmb_sha256, |p| p.new_sha256);
        let expected_rsc_hash = rsc.as_ref().map_or(*old_rsc_sha256, |p| p.new_sha256);
        if hash_file(dmb_path)? != expected_dmb_hash || hash_file(rsc_path)? != expected_rsc_hash {
            return Err(invalid("published output does not match target generation"));
        }
        validate(dmb_path, rsc_path)?;
        fs::remove_file(journal_path)?;
        Ok(())
    })();
    if result.is_err() && journal_path.exists() {
        let _ = recover_pair_locked(dmb_path, rsc_path, journal_path);
    }
    result
}

fn hash_file(path: &Path) -> io::Result<[u8; 32]> {
    let (_, hash) = digest_reader(&mut File::open(path)?)?;
    Ok(hash)
}

fn verify_patch_source(path: &Path, patch: &FilePatch) -> io::Result<()> {
    let mut file = File::open(path)?;
    if file.metadata()?.len() != patch.old_len || hash_file(path)? != patch.old_sha256 {
        return Err(invalid("stale patch source"));
    }
    let mut end = 0u64;
    for span in &patch.spans {
        let span_end = span
            .offset
            .checked_add(span.before.len() as u64)
            .ok_or_else(|| invalid("patch span overflow"))?;
        if span.before.len() != span.after.len() || span.offset < end || span_end > patch.old_len {
            return Err(invalid("invalid or overlapping patch span"));
        }
        file.seek(SeekFrom::Start(span.offset))?;
        let mut actual = vec![0; span.before.len()];
        file.read_exact(&mut actual)?;
        if actual != span.before {
            return Err(invalid("patch undo bytes do not match old generation"));
        }
        end = span_end;
    }
    Ok(())
}

/// Roll back an interrupted pair patch. The journal contains only changed spans;
/// it is meaningful only while both files retain their original lengths.
fn acquire_pair_lock(journal_path: &Path) -> io::Result<File> {
    let lock = OpenOptions::new()
        .read(true)
        .write(true)
        .create(true)
        .open(journal_path.with_extension("lock"))?;
    lock.try_lock()?;
    Ok(lock)
}

pub fn recover_pair(dmb_path: &Path, rsc_path: &Path, journal_path: &Path) -> io::Result<()> {
    let _lock = acquire_pair_lock(journal_path)?;
    recover_pair_locked(dmb_path, rsc_path, journal_path)
}

fn recover_pair_locked(dmb_path: &Path, rsc_path: &Path, journal_path: &Path) -> io::Result<()> {
    let bytes = fs::read(journal_path)?;
    let journal: UndoJournal = serde_json::from_slice(&bytes).map_err(io::Error::other)?;
    if journal.version != 1 {
        return Err(invalid("unsupported undo journal version"));
    }
    // Prove both original files can be reconstructed before writing either.
    if let Some(p) = &journal.dmb {
        verify_recovery_source(dmb_path, p)?;
    }
    if let Some(p) = &journal.rsc {
        verify_recovery_source(rsc_path, p)?;
    }
    if let Some(p) = &journal.dmb {
        restore_spans(dmb_path, p)?;
    }
    if let Some(p) = &journal.rsc {
        restore_spans(rsc_path, p)?;
    }
    fs::remove_file(journal_path)?;
    Ok(())
}

fn verify_recovery_source(path: &Path, patch: &FilePatch) -> io::Result<()> {
    let mut file = File::open(path)?;
    if file.metadata()?.len() != patch.old_len {
        return Err(invalid("cannot restore resized output"));
    }
    let mut hash = Sha256::new();
    let mut position = 0u64;
    let mut buffer = [0u8; 64 * 1024];
    for span in &patch.spans {
        let end = span
            .offset
            .checked_add(span.before.len() as u64)
            .ok_or_else(|| invalid("undo span overflow"))?;
        if span.before.len() != span.after.len() || span.offset < position || end > patch.old_len {
            return Err(invalid("invalid or overlapping undo span"));
        }
        hash_file_segment(&mut file, span.offset - position, &mut hash, &mut buffer)?;
        hash.update(&span.before);
        file.seek(SeekFrom::Start(end))?;
        position = end;
    }
    hash_file_segment(&mut file, patch.old_len - position, &mut hash, &mut buffer)?;
    let reconstructed: [u8; 32] = hash.finalize().into();
    if reconstructed != patch.old_sha256 {
        return Err(invalid("undo journal does not match output generation"));
    }
    Ok(())
}

fn hash_file_segment(
    file: &mut File,
    mut bytes: u64,
    hash: &mut Sha256,
    buffer: &mut [u8],
) -> io::Result<()> {
    while bytes != 0 {
        let count = bytes.min(buffer.len() as u64) as usize;
        file.read_exact(&mut buffer[..count])?;
        hash.update(&buffer[..count]);
        bytes -= count as u64;
    }
    Ok(())
}

fn write_spans(path: &Path, patch: &FilePatch) -> io::Result<()> {
    let mut file = OpenOptions::new().write(true).open(path)?;
    for span in &patch.spans {
        file.seek(SeekFrom::Start(span.offset))?;
        file.write_all(&span.after)?;
    }
    file.sync_all()
}

fn restore_spans(path: &Path, patch: &FilePatch) -> io::Result<()> {
    let mut file = OpenOptions::new().write(true).open(path)?;
    if file.metadata()?.len() != patch.old_len {
        return Err(invalid("cannot restore resized output"));
    }
    for span in &patch.spans {
        file.seek(SeekFrom::Start(span.offset))?;
        file.write_all(&span.before)?;
    }
    file.sync_all()?;
    if hash_file(path)? != patch.old_sha256 {
        return Err(invalid("restored output hash mismatch"));
    }
    Ok(())
}

fn digest(bytes: &[u8]) -> [u8; 32] {
    Sha256::digest(bytes).into()
}
fn digest_reader(reader: &mut impl Read) -> io::Result<(u64, [u8; 32])> {
    let mut hash = Sha256::new();
    let mut length = 0u64;
    let mut buffer = [0u8; 64 * 1024];
    loop {
        let read = reader.read(&mut buffer)?;
        if read == 0 {
            break;
        }
        length = length
            .checked_add(read as u64)
            .ok_or_else(|| invalid("image length overflow"))?;
        hash.update(&buffer[..read]);
    }
    Ok((length, hash.finalize().into()))
}
fn invalid(message: &str) -> io::Error {
    io::Error::new(io::ErrorKind::InvalidData, message)
}
fn hex(bytes: &[u8]) -> String {
    const DIGITS: &[u8; 16] = b"0123456789abcdef";
    let mut result = String::with_capacity(bytes.len() * 2);
    for byte in bytes {
        result.push(DIGITS[(byte >> 4) as usize] as char);
        result.push(DIGITS[(byte & 15) as usize] as char);
    }
    result
}

/// Worktree-specific pair paths are part of the generation identity.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct OutputPaths {
    pub dmb: PathBuf,
    pub rsc: PathBuf,
    pub journal: PathBuf,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn pair_validation_rejects_missing_resources() {
        let mut world = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/native_template.bin"
        ))
        .unwrap();
        let resource = byond_dmb::rsc::NamedResource::from_data(
            6,
            b"test.txt".to_vec(),
            b"contents".to_vec(),
            0,
            0,
        )
        .unwrap();
        world.resources.push(byond_dmb::dmb::ResourceRef {
            id: resource.id,
            kind: resource.kind,
        });
        let dmb = world.to_bytes().unwrap();
        assert_eq!(
            validate_byond_pair(&dmb, &[]).unwrap_err().kind(),
            io::ErrorKind::InvalidData
        );

        let mut truncated = resource.clone();
        truncated.declared_size += 1;
        let mut invalid_rsc = Vec::new();
        byond_dmb::rsc::write_all(&mut invalid_rsc, &[byond_dmb::rsc::Entry::Named(truncated)])
            .unwrap();
        assert_eq!(
            validate_byond_pair(&dmb, &invalid_rsc).unwrap_err().kind(),
            io::ErrorKind::InvalidData
        );

        let entry = byond_dmb::rsc::Entry::Named(resource);
        let mut rsc = Vec::new();
        byond_dmb::rsc::write_all(&mut rsc, &[entry]).unwrap();
        validate_byond_pair(&dmb, &rsc).unwrap();
    }

    #[test]
    fn same_size_patch_reconstructs_exact_target() {
        let old = b"header-AAAA-trailer";
        let new = b"header-BBBB-trailer";
        let FilePlan::Patch(patch) = plan_file(old, new, PatchPolicy::default()) else {
            panic!("expected patch")
        };
        assert_eq!(patch.apply_to_bytes(old).unwrap(), new);
        assert!(patch.apply_to_bytes(b"header-CCCC-trailer").is_err());
    }

    #[test]
    fn length_change_rebuilds_pair() {
        assert!(matches!(
            plan_pair(b"ab", b"xy", b"abc", b"xz", PatchPolicy::default()),
            PairPlan::Rebuild { .. }
        ));
    }

    #[test]
    fn rsc_index_covers_ordered_entries() {
        let entries = vec![
            byond_dmb::rsc::Entry::Named(
                byond_dmb::rsc::NamedResource::from_data(
                    3,
                    b"a.dmi".to_vec(),
                    b"abc".to_vec(),
                    1,
                    2,
                )
                .unwrap(),
            ),
            byond_dmb::rsc::Entry::Opaque {
                wrapper: 0,
                payload: b"gone".to_vec(),
            },
        ];
        let mut image = Vec::new();
        byond_dmb::rsc::write_all(&mut image, &entries).unwrap();
        let index = index_rsc(&image).unwrap();
        assert_eq!(index.records.len(), 2);
        assert_eq!(index.records[0].offset, 0);
        assert_eq!(index.records[1].offset, index.records[0].len);
        assert_eq!(
            index.records[1].offset + index.records[1].len,
            image.len() as u64
        );
    }

    #[test]
    fn index_rejects_stale_and_overlapping_spans() {
        let mut index = LayoutIndex::new(
            OutputKind::Dmb,
            1,
            b"abcdef",
            vec![RecordSpan {
                key: "one".into(),
                offset: 0,
                len: 3,
                position_dependent: false,
            }],
        )
        .unwrap();
        assert!(index.validate(b"abcdeg").is_err());
        index.records.push(RecordSpan {
            key: "two".into(),
            offset: 2,
            len: 2,
            position_dependent: false,
        });
        assert!(index.validate(b"abcdef").is_err());
    }

    #[test]
    fn recovery_is_locked_and_preflights_both_files_before_writing() {
        let directory = std::env::temp_dir().join(format!(
            "dm-recovery-preflight-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        fs::create_dir(&directory).unwrap();
        let dmb = directory.join("world.dmb");
        let rsc = directory.join("world.rsc");
        let journal_path = directory.join("world.journal");
        let old_dmb = b"header-A-tail";
        let new_dmb = b"header-B-tail";
        let old_rsc = b"asset-X-tail";
        let new_rsc = b"asset-Y-tail";
        let FilePlan::Patch(dmb_patch) = plan_file(old_dmb, new_dmb, PatchPolicy::default()) else {
            panic!()
        };
        let FilePlan::Patch(rsc_patch) = plan_file(old_rsc, new_rsc, PatchPolicy::default()) else {
            panic!()
        };
        let mut journal = UndoJournal {
            version: 1,
            dmb: Some(dmb_patch),
            rsc: Some(rsc_patch),
        };
        fs::write(&dmb, new_dmb).unwrap();
        fs::write(&rsc, new_rsc).unwrap();
        fs::write(&journal_path, serde_json::to_vec(&journal).unwrap()).unwrap();
        let lock = acquire_pair_lock(&journal_path).unwrap();
        assert!(recover_pair(&dmb, &rsc, &journal_path).is_err());
        assert_eq!(fs::read(&dmb).unwrap(), new_dmb);
        assert!(journal_path.exists());
        drop(lock);
        fs::write(&rsc, b"other-Y-tail").unwrap();
        assert!(recover_pair(&dmb, &rsc, &journal_path).is_err());
        assert_eq!(
            fs::read(&dmb).unwrap(),
            new_dmb,
            "failed RSC preflight must not roll back DMB"
        );
        assert_eq!(fs::read(&rsc).unwrap(), b"other-Y-tail");
        fs::write(&rsc, new_rsc).unwrap();
        let original_offset = journal.rsc.as_ref().unwrap().spans[0].offset;
        journal.rsc.as_mut().unwrap().spans[0].offset = old_rsc.len() as u64;
        fs::write(&journal_path, serde_json::to_vec(&journal).unwrap()).unwrap();
        assert!(recover_pair(&dmb, &rsc, &journal_path).is_err());
        assert_eq!(fs::read(&dmb).unwrap(), new_dmb);
        assert_eq!(fs::read(&rsc).unwrap(), new_rsc);
        journal.rsc.as_mut().unwrap().spans[0].offset = original_offset;
        fs::write(&journal_path, serde_json::to_vec(&journal).unwrap()).unwrap();
        recover_pair(&dmb, &rsc, &journal_path).unwrap();
        assert_eq!(fs::read(&dmb).unwrap(), old_dmb);
        assert_eq!(fs::read(&rsc).unwrap(), old_rsc);
        fs::remove_dir_all(directory).unwrap();
    }

    #[test]
    fn undo_journal_restores_interrupted_pair_patch() {
        let unique = format!(
            "dm-output-test-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        );
        let directory = std::env::temp_dir().join(unique);
        fs::create_dir(&directory).unwrap();
        let dmb_path = directory.join("world.dmb");
        let rsc_path = directory.join("world.rsc");
        let journal_path = directory.join("world.journal");
        let old_dmb = b"header-A-tail";
        let new_dmb = b"header-B-tail";
        let old_rsc = b"asset-X-tail";
        let new_rsc = b"asset-Y-tail";
        let FilePlan::Patch(dmb_patch) = plan_file(old_dmb, new_dmb, PatchPolicy::default()) else {
            panic!()
        };
        let FilePlan::Patch(rsc_patch) = plan_file(old_rsc, new_rsc, PatchPolicy::default()) else {
            panic!()
        };
        fs::write(&dmb_path, new_dmb).unwrap();
        fs::write(&rsc_path, old_rsc).unwrap();
        let journal = UndoJournal {
            version: 1,
            dmb: Some(dmb_patch),
            rsc: Some(rsc_patch),
        };
        fs::write(&journal_path, serde_json::to_vec(&journal).unwrap()).unwrap();
        recover_pair(&dmb_path, &rsc_path, &journal_path).unwrap();
        assert_eq!(fs::read(&dmb_path).unwrap(), old_dmb);
        assert_eq!(fs::read(&rsc_path).unwrap(), old_rsc);
        assert!(!journal_path.exists());
        fs::remove_dir_all(directory).unwrap();
    }

    #[test]
    fn varied_same_length_edits_reconstruct_clean_bytes() {
        let mut state = 0x1234_5678u32;
        let old: Vec<u8> = (0..4096).map(|i| i as u8).collect();
        for _ in 0..32 {
            let mut new = old.clone();
            for _ in 0..16 {
                state ^= state << 13;
                state ^= state >> 17;
                state ^= state << 5;
                let at = state as usize % new.len();
                new[at] ^= (state >> 16) as u8 | 1;
            }
            match plan_file(&old, &new, PatchPolicy::default()) {
                FilePlan::Patch(patch) => assert_eq!(patch.apply_to_bytes(&old).unwrap(), new),
                other => panic!("sparse equal-length edit should patch: {other:?}"),
            }
        }
    }

    #[test]
    fn streaming_planner_matches_image_planner_across_chunks() {
        let old: Vec<u8> = (0..20_000).map(|i| (i % 251) as u8).collect();
        let mut new = old.clone();
        for at in [0, 8191, 8192, 8193, 12_345, 19_999] {
            new[at] ^= 0x5a;
        }
        let policy = PatchPolicy {
            merge_gap: 2,
            ..PatchPolicy::default()
        };
        let mut old_reader = Cursor::new(&old);
        let mut new_reader = Cursor::new(&new);
        let streaming = plan_file_streaming(&mut old_reader, &mut new_reader, policy).unwrap();
        assert_eq!(streaming, plan_file(&old, &new, policy));
        let FilePlan::Patch(patch) = streaming else {
            panic!("expected patch")
        };
        assert_eq!(patch.apply_to_bytes(&old).unwrap(), new);
    }

    #[test]
    fn streaming_planner_handles_rebuild_and_unchanged() {
        let mut old = Cursor::new(b"same".as_slice());
        let mut same = Cursor::new(b"same".as_slice());
        assert_eq!(
            plan_file_streaming(&mut old, &mut same, PatchPolicy::default()).unwrap(),
            FilePlan::Unchanged
        );
        let mut longer = Cursor::new(b"longer".as_slice());
        assert_eq!(
            plan_file_streaming(&mut old, &mut longer, PatchPolicy::default()).unwrap(),
            FilePlan::Rebuild {
                reason: RebuildReason::LengthChanged
            }
        );
    }

    #[test]
    fn index_reader_restores_cursor_and_detects_stale_image() {
        let image = b"header-record-trailer";
        let index = LayoutIndex::new(
            OutputKind::Dmb,
            1,
            image,
            vec![RecordSpan {
                key: "record".into(),
                offset: 7,
                len: 6,
                position_dependent: false,
            }],
        )
        .unwrap();
        let mut reader = Cursor::new(image.as_slice());
        reader.set_position(3);
        index.validate_reader(&mut reader).unwrap();
        assert_eq!(reader.position(), 3);
        let mut stale = Cursor::new(b"header-recorD-trailer".as_slice());
        assert!(index.validate_reader(&mut stale).is_err());
    }

    #[test]
    fn streaming_pair_publication_and_validator_rollback() {
        let directory = std::env::temp_dir().join(format!(
            "dm-output-streaming-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        fs::create_dir(&directory).unwrap();
        let dmb = directory.join("world.dmb");
        let rsc = directory.join("world.rsc");
        let journal = directory.join("world.journal");
        let old_dmb = b"header-A-tail";
        let new_dmb = b"header-B-tail";
        let old_rsc = b"asset-X-tail";
        let new_rsc = b"asset-Y-tail";
        let plan = plan_pair(old_dmb, old_rsc, new_dmb, new_rsc, PatchPolicy::default());
        fs::write(&dmb, old_dmb).unwrap();
        fs::write(&rsc, old_rsc).unwrap();
        apply_pair_in_place_with_validator(&dmb, &rsc, &journal, &plan, |d, r| {
            assert_eq!(fs::read(d)?, new_dmb);
            assert_eq!(fs::read(r)?, new_rsc);
            Ok(())
        })
        .unwrap();
        assert!(!journal.exists());
        assert_eq!(fs::read(&dmb).unwrap(), new_dmb);
        fs::write(&dmb, old_dmb).unwrap();
        fs::write(&rsc, old_rsc).unwrap();
        assert!(
            apply_pair_in_place_with_validator(&dmb, &rsc, &journal, &plan, |_, _| {
                Err(invalid("reject linked output"))
            })
            .is_err()
        );
        assert_eq!(fs::read(&dmb).unwrap(), old_dmb);
        assert_eq!(fs::read(&rsc).unwrap(), old_rsc);
        assert!(!journal.exists());
        fs::remove_dir_all(directory).unwrap();
    }
}

pub mod typed_table;
