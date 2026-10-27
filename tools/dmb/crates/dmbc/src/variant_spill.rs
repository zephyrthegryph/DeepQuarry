//! A variant's patch base on disk (doc/incremental_core.md, "Model persistence").
//!
//! A session keeps the output of its last build as a patch base: the published image with its list rows, the link answers that
//! produced it and the source half a patch is compared with (`retained_output::OutputBase`). That state is what turns the next
//! edit of a variant into a body patch instead of a whole-program compile, and it is about a GB of the resident memory of each
//! variant, so idle tiers and variant stashes drop it. Before they do, the patch base is written here, one file per variant
//! (project, defines and compiler policy), and read back lazily when the next request of that variant reaches the patch
//! admission (`RetainedGeneration::restore_patch_base`), with nothing else assumed: admission compares the restored source half
//! with the request exactly as it compares the live one, and anything that differs sends the request down the ordinary path.
//!
//! A variant's base that a full build replaced with a base of other program text is stored too, in a file keyed by the
//! variant and that text (`text_key`): a compile root alternating between lanes whose declarations differ finds each lane's
//! base there (`RetainedGeneration::restore_patch_base`).
//!
//! Not stored, because a patch can do without it or rebuilds it: the retained model (decoded from the image when an edit needs
//! one, `RetainedGeneration::model_of`), unit symbolic records (a patch compares footprints only) and the expanded program text (numeric
//! default edits are not admitted on a restored output). The answer marks are not stored either: a restored output proves its
//! answers from the facts its version hashes (`QueryDb::prove_facts`), or is admitted on an equal answer-table version.
//!
//! The directory is bounded by size and age (`DMB_SPILL_BUDGET_GB`, default 4, `DMB_SPILL_MAX_AGE_DAYS`, default 7), enforced on
//! every write and by the daemon's cache pass. Everything here is a hint: an unreadable, truncated, stale or foreign file only
//! costs the compile it would have saved, and `DMB_VARIANT_SPILL=0` turns the feature off.
use crate::composition::{PatchImage, PatchLink};
use crate::retained_output::{BaseParts, OutputBase};
use dm_ir::SymbolId;
use serde::{Deserialize, Serialize};
use std::{
    collections::BTreeMap,
    fs,
    io::{BufWriter, Read, Write},
    path::{Path, PathBuf},
    time::{Duration, SystemTime, UNIX_EPOCH},
};

/// Bump with any change to the stored layout or to a stored type: an old file is then ignored (and ages out).
const VERSION: u32 = 2;
const MAGIC: &[u8; 8] = b"DMBSPIL1";
const EXTENSION: &str = "spill";
const DEFAULT_BUDGET_GB: u64 = 4;
const DEFAULT_MAX_AGE_DAYS: u64 = 7;
/// Largest stored frame (the one image frame is bounded by the address space instead).
const MAX_FRAME: usize = 1 << 30;

/// Disabled by `DMB_VARIANT_SPILL=0`.
pub fn enabled() -> bool {
    static ENABLED: std::sync::OnceLock<bool> = std::sync::OnceLock::new();
    *ENABLED.get_or_init(|| std::env::var_os("DMB_VARIANT_SPILL").is_none_or(|value| value != "0"))
}

/// Where a cache root keeps its spilled patch bases (a subdirectory the segment cache never looks at).
pub(crate) fn directory(cache_root: &Path) -> PathBuf {
    cache_root.join("variant-spill")
}

/// The file of one variant: its project, defines and the compiler/engine policy (which carries the compiler identity, so a new
/// compiler never reads an old compiler's file).
pub(crate) fn key(project: &Path, defines: &BTreeMap<String, String>, policy: u128) -> u128 {
    let mut hash = xxhash_rust::xxh3::Xxh3::new();
    hash.update(b"dm-variant-spill-key-v1\0");
    hash.update(&VERSION.to_le_bytes());
    hash.update(&policy.to_le_bytes());
    hash.update(project.as_os_str().as_encoded_bytes());
    for (name, value) in defines {
        hash.update(b"\0");
        hash.update(name.as_bytes());
        hash.update(b"=");
        hash.update(value.as_bytes());
    }
    hash.digest128()
}

/// The file of a variant's base with this program text (`OutputBase::text_key`): a base a full build replaced with one of
/// other text, kept so a compile root that alternates between trees with different declarations finds it again.
pub(crate) fn text_key(variant: u128, text: (u128, usize)) -> u128 {
    let mut hash = xxhash_rust::xxh3::Xxh3::new();
    hash.update(b"dm-variant-spill-text-v1\0");
    hash.update(&variant.to_le_bytes());
    hash.update(&text.0.to_le_bytes());
    hash.update(&(text.1 as u64).to_le_bytes());
    hash.digest128()
}

fn path_of(dir: &Path, key: u128) -> PathBuf {
    dir.join(format!("{key:032x}.{EXTENSION}"))
}

/// What a stored file says about itself before anything heavy is read.
#[derive(Clone, Debug, Serialize, Deserialize)]
pub(crate) struct Header {
    pub version: u32,
    pub key: u128,
    /// Digest of the stored image: what `OutputBase::dmb_hash` will be.
    pub dmb_hash: u128,
    /// `SourceShape::text_key` and body count of the stored build: a request whose program text differs cannot patch on it.
    pub text_key: (u128, u64),
    pub image_bytes: u64,
    pub written_unix: u64,
}

#[derive(Serialize, Deserialize)]
struct LinkParts {
    indexes: Vec<(dm_link::Key, u32)>,
    slots: Vec<(SymbolId, (SymbolId, SymbolId))>,
    strings: Vec<(SymbolId, Vec<u8>)>,
    mobs: Vec<(SymbolId, u32)>,
    initializers: crate::symbolic::PositionedList,
    fields: Option<Vec<((SymbolId, SymbolId), u32)>>,
    /// The build did not define `DEBUG`: patched procedure words are composed without debug instructions.
    strip_debug_ops: bool,
}

#[derive(Serialize, Deserialize)]
struct ImageParts {
    width: u8,
    /// `(gap since the previous row's end, length)` of every list row.
    rows: Vec<(u32, u32)>,
    proc_code: Vec<u32>,
}

fn schema(section: u32) -> u32 {
    VERSION * 16 + section
}

fn frame<T: Serialize>(out: &mut impl Write, section: u32, value: &T) -> Result<u64, String> {
    let bytes = dm_wire::encode_bounded(schema(section), value, MAX_FRAME)?;
    out.write_all(&(bytes.len() as u64).to_le_bytes()).map_err(|e| e.to_string())?;
    out.write_all(&bytes).map_err(|e| e.to_string())?;
    Ok(8 + bytes.len() as u64)
}

fn read_frame<T: for<'de> Deserialize<'de>>(input: &mut impl Read, section: u32) -> Result<T, String> {
    let mut length = [0u8; 8];
    input.read_exact(&mut length).map_err(|e| e.to_string())?;
    let length = usize::try_from(u64::from_le_bytes(length)).map_err(|e| e.to_string())?;
    if length > MAX_FRAME {
        return Err("stored frame is larger than any frame written".into());
    }
    let mut bytes = vec![0u8; length];
    input.read_exact(&mut bytes).map_err(|e| e.to_string())?;
    dm_wire::decode(schema(section), &bytes, MAX_FRAME)
}

fn open_checked(path: &Path) -> Result<fs::File, String> {
    let mut file = fs::File::open(path).map_err(|e| e.to_string())?;
    let mut magic = [0u8; 8];
    file.read_exact(&mut magic).map_err(|e| e.to_string())?;
    if &magic != MAGIC {
        return Err("not a stored patch base".into());
    }
    Ok(file)
}

/// The header of `key`'s file, if there is a current-format one.
pub(crate) fn peek(dir: &Path, key: u128) -> Option<Header> {
    let mut file = open_checked(&path_of(dir, key)).ok()?;
    let header: Header = read_frame(&mut file, 0).ok()?;
    (header.version == VERSION && header.key == key).then_some(header)
}

pub(crate) struct Written {
    pub bytes: u64,
    pub seconds: f64,
}

fn link_parts(
    link: &PatchLink,
    fields: Option<&crate::class_projection::FieldRecords>,
    initializers: crate::symbolic::PositionedList,
) -> LinkParts {
    let mut mobs: Vec<(SymbolId, u32)> = link.mobs.iter().map(|(id, index)| (*id, *index)).collect();
    mobs.sort_unstable();
    LinkParts {
        indexes: link.tables.assignments().iter().map(|(key, index)| (*key, *index)).collect(),
        slots: link.tables.slots().iter().map(|(slot, pair)| (*slot, *pair)).collect(),
        strings: link.tables.string_contents().map(|(id, bytes)| (id, bytes.to_vec())).collect(),
        mobs,
        initializers,
        strip_debug_ops: link.tables.strips_debug_ops(),
        fields: fields.map(|fields| {
            let mut all: Vec<_> = fields.0.iter().map(|(pair, record)| (*pair, *record)).collect();
            all.sort_unstable();
            all
        }),
    }
}

fn image_parts(image: &PatchImage) -> Result<ImageParts, String> {
    let mut rows = Vec::with_capacity(image.rows.ranges().len());
    let mut through = 0usize;
    for range in image.rows.ranges() {
        let gap = range.start.checked_sub(through).ok_or("list rows overlap")?;
        rows.push((
            u32::try_from(gap).map_err(|_| "list row gap")?,
            u32::try_from(range.len()).map_err(|_| "list row length")?,
        ));
        through = range.end;
    }
    Ok(ImageParts {
        width: u8::try_from(image.rows.width()).map_err(|_| "list width")?,
        rows,
        proc_code: image.proc_code.as_ref().clone(),
    })
}

/// Store a patch base. The file appears whole or not at all (written aside, then renamed over the old one).
pub(crate) fn write(
    dir: &Path,
    key: u128,
    base: &OutputBase,
    link: &PatchLink,
    fields: Option<&crate::class_projection::FieldRecords>,
    image: &PatchImage,
    workers: usize,
) -> Result<Written, String> {
    let started = std::time::Instant::now();
    let dmb_hash = image.rows.image().content_hash();
    if base.dmb_hash() != dmb_hash {
        return Err("the base does not describe its image".into());
    }
    let initializers = crate::symbolic::PositionedList::of(&link.initializers);
    let header = Header {
        version: VERSION,
        key,
        dmb_hash,
        text_key: {
            let (text, bodies) = base.text_key();
            (text, bodies as u64)
        },
        image_bytes: image.rows.image().len() as u64,
        written_unix: SystemTime::now().duration_since(UNIX_EPOCH).map_or(0, |d| d.as_secs()),
    };
    fs::create_dir_all(dir).map_err(|e| e.to_string())?;
    let target = path_of(dir, key);
    static WRITES: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);
    let aside = dir.join(format!(
        "{key:032x}.{EXTENSION}.tmp{}-{}",
        std::process::id(),
        WRITES.fetch_add(1, std::sync::atomic::Ordering::Relaxed)
    ));
    let result = (|| -> Result<u64, String> {
        let mut out = BufWriter::with_capacity(1 << 20, fs::File::create(&aside).map_err(|e| e.to_string())?);
        out.write_all(MAGIC).map_err(|e| e.to_string())?;
        let mut total = 8u64;
        total += frame(&mut out, 0, &header)?;
        // One part at a time: each is built, written and dropped before the next, so a store made under memory
        // pressure holds one part's copy beside the retained state, not all of them.
        total += frame(&mut out, 1, &base.to_parts(workers).ok_or("the source half cannot be stored")?)?;
        total += frame(&mut out, 2, &link_parts(link, fields, initializers))?;
        total += frame(&mut out, 3, &image_parts(image)?)?;
        let bytes = image.rows.image().bytes();
        out.write_all(&(bytes.len() as u64).to_le_bytes()).map_err(|e| e.to_string())?;
        out.write_all(bytes).map_err(|e| e.to_string())?;
        total += 8 + bytes.len() as u64;
        out.flush().map_err(|e| e.to_string())?;
        Ok(total)
    })();
    let bytes = match result {
        Ok(bytes) => bytes,
        Err(error) => {
            let _ = fs::remove_file(&aside);
            return Err(error);
        }
    };
    if let Err(error) = fs::rename(&aside, &target) {
        let _ = fs::remove_file(&aside);
        return Err(error.to_string());
    }
    Ok(Written {
        bytes,
        seconds: started.elapsed().as_secs_f64(),
    })
}

/// A stored patch base, ready to install in a generation's patch slot.
pub(crate) struct Restored {
    pub base: OutputBase,
    pub link: PatchLink,
    pub fields: Option<crate::class_projection::FieldRecords>,
    pub image: PatchImage,
}

/// Read `key`'s file back. Every frame is checksummed and the image must hash to the digest it was stored with and parse as
/// the list rows it was stored with; any failure is an `Err` and the caller compiles as if there were no file.
pub(crate) fn read(dir: &Path, key: u128) -> Result<Restored, String> {
    let mut file = std::io::BufReader::with_capacity(1 << 20, open_checked(&path_of(dir, key))?);
    let header: Header = read_frame(&mut file, 0)?;
    if header.version != VERSION || header.key != key {
        return Err("stored for another variant or format".into());
    }
    let base_parts: BaseParts = read_frame(&mut file, 1)?;
    let link_parts: LinkParts = read_frame(&mut file, 2)?;
    let image_parts: ImageParts = read_frame(&mut file, 3)?;
    let mut length = [0u8; 8];
    file.read_exact(&mut length).map_err(|e| e.to_string())?;
    let length = usize::try_from(u64::from_le_bytes(length)).map_err(|e| e.to_string())?;
    if length as u64 != header.image_bytes {
        return Err("stored image length differs from its header".into());
    }
    let mut bytes = vec![0u8; length];
    file.read_exact(&mut bytes).map_err(|e| e.to_string())?;
    let mut ranges = Vec::with_capacity(image_parts.rows.len());
    let mut through = 0usize;
    for (gap, len) in &image_parts.rows {
        let start = through.checked_add(*gap as usize).ok_or("list row start")?;
        let end = start.checked_add(*len as usize).ok_or("list row end")?;
        ranges.push(start..end);
        through = end;
    }
    let rows = byond_dmb::dmb::ListRowImage::from_stored(bytes, header.dmb_hash, ranges, image_parts.width as usize)
        .map_err(|e| e.to_string())?;
    let image = PatchImage {
        rows,
        proc_code: std::sync::Arc::new(image_parts.proc_code),
    };
    let base = OutputBase::from_parts(base_parts, header.dmb_hash).ok_or("the stored source half is inconsistent")?;
    let tables = dm_link::LinkTables::from_stored(
        link_parts.indexes.into_iter().collect(),
        link_parts.slots.into_iter().collect(),
        link_parts
            .strings
            .into_iter()
            .map(|(id, bytes)| (id, std::sync::Arc::<[u8]>::from(bytes))),
    )
    .with_strip_debug_ops(link_parts.strip_debug_ops);
    let link = PatchLink {
        tables,
        mobs: link_parts.mobs.into_iter().collect(),
        initializers: link_parts.initializers.restore().ok_or("the stored initializer code is invalid")?,
    };
    let fields = link_parts
        .fields
        .map(|fields| crate::class_projection::FieldRecords(std::sync::Arc::new(fields.into_iter().collect())));
    Ok(Restored {
        base,
        link,
        fields,
        image,
    })
}

fn budget_bytes() -> Option<u64> {
    let gb = std::env::var("DMB_SPILL_BUDGET_GB")
        .ok()
        .and_then(|text| text.parse::<u64>().ok())
        .unwrap_or(DEFAULT_BUDGET_GB);
    (gb > 0).then(|| gb.saturating_mul(1_000_000_000))
}

fn max_age() -> Option<Duration> {
    let days = std::env::var("DMB_SPILL_MAX_AGE_DAYS")
        .ok()
        .and_then(|text| text.parse::<u64>().ok())
        .unwrap_or(DEFAULT_MAX_AGE_DAYS);
    (days > 0).then(|| Duration::from_secs(days * 86_400))
}

/// Keep the directory inside its budget: files older than the age cap go, then the least recently written until the rest fit.
/// `keep` (the file just written) is never removed. Aside files of a writer that died are removed after a day.
pub(crate) fn evict(dir: &Path, keep: Option<&Path>) -> String {
    evict_with(dir, keep, budget_bytes(), max_age(), SystemTime::now())
}

pub(crate) fn evict_with(
    dir: &Path,
    keep: Option<&Path>,
    budget: Option<u64>,
    age: Option<Duration>,
    now: SystemTime,
) -> String {
    let Ok(entries) = fs::read_dir(dir) else {
        return String::new();
    };
    let mut files: Vec<(SystemTime, u64, PathBuf)> = Vec::new();
    let mut removed = 0usize;
    let mut removed_bytes = 0u64;
    for entry in entries.flatten() {
        let path = entry.path();
        let Ok(metadata) = entry.metadata() else { continue };
        if !metadata.is_file() {
            continue;
        }
        let Ok(modified) = metadata.modified() else { continue };
        let name = path.file_name().and_then(|name| name.to_str()).unwrap_or_default();
        let aside = name.contains(&format!(".{EXTENSION}.tmp"));
        if aside {
            if now.duration_since(modified).is_ok_and(|old| old > Duration::from_secs(86_400)) {
                removed_bytes += metadata.len();
                removed += usize::from(fs::remove_file(&path).is_ok());
            }
            continue;
        }
        if path.extension().is_some_and(|extension| extension == EXTENSION) {
            files.push((modified, metadata.len(), path));
        }
    }
    files.sort_by(|a, b| a.0.cmp(&b.0).then_with(|| a.2.cmp(&b.2)));
    let mut total: u64 = files.iter().map(|(_, bytes, _)| *bytes).sum();
    let before = total;
    for (modified, bytes, path) in files {
        if keep.is_some_and(|keep| keep == path) {
            continue;
        }
        let aged = age.is_some_and(|limit| now.duration_since(modified).is_ok_and(|old| old > limit));
        let over = budget.is_some_and(|budget| total > budget);
        if !aged && !over {
            break;
        }
        if fs::remove_file(&path).is_ok() {
            total = total.saturating_sub(bytes);
            removed += 1;
            removed_bytes += bytes;
        }
    }
    if removed == 0 {
        return String::new();
    }
    format!(
        "dmbd variant spill: {:.2} GB -> {:.2} GB, removed {removed} files ({:.2} GB)",
        before as f64 / 1e9,
        total as f64 / 1e9,
        removed_bytes as f64 / 1e9
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn keys_separate_projects_defines_and_policies() {
        let none = BTreeMap::new();
        let test = BTreeMap::from([("CITESTING".to_owned(), "1".to_owned())]);
        let project = Path::new("E:/a/deepquarry.dme");
        let base = key(project, &none, 1);
        assert_eq!(base, key(project, &none, 1));
        assert_ne!(base, key(project, &test, 1));
        assert_ne!(base, key(project, &none, 2));
        assert_ne!(base, key(Path::new("E:/b/deepquarry.dme"), &none, 1));
    }

    #[test]
    fn eviction_drops_aged_files_then_the_oldest_over_budget_and_keeps_the_written_one() {
        let dir = crate::test_scratch::dir("variant-spill-evict");
        let now = SystemTime::now();
        let make = |name: &str, bytes: usize, age_days: u64| {
            let path = dir.join(name);
            fs::write(&path, vec![0u8; bytes]).unwrap();
            let file = fs::File::options().write(true).open(&path).unwrap();
            file.set_modified(now - Duration::from_secs(age_days * 86_400)).unwrap();
            path
        };
        let aged = make("a.spill", 10, 30);
        let old = make("b.spill", 10, 3);
        let mid = make("c.spill", 10, 2);
        let fresh = make("d.spill", 10, 0);
        let stray = make("e.spill.tmp1", 10, 0);
        let dead = make("f.spill.tmp2", 10, 3);
        let other = make("notes.txt", 10, 30);
        // Age cap: only the 30 day file goes; the young aside file (a writer at work) stays, the abandoned one goes.
        evict_with(&dir, Some(&fresh), None, Some(Duration::from_secs(7 * 86_400)), now);
        assert!(!aged.exists() && old.exists() && mid.exists() && fresh.exists() && stray.exists() && other.exists());
        assert!(!dead.exists(), "an aside file a day old belongs to a writer that died");
        // Budget of 15 bytes: the oldest go until the rest fit; the kept file survives even when it alone is the newest.
        evict_with(&dir, Some(&fresh), Some(15), None, now);
        assert!(!old.exists() && !mid.exists() && fresh.exists());
        // A budget below the kept file's size removes nothing more.
        evict_with(&dir, Some(&fresh), Some(1), None, now);
        assert!(fresh.exists() && other.exists());
    }
}
