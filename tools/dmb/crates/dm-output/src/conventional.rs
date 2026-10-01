//! Detached conventional outputs for build tools that expect PROJECT.dmb/rsc.
//! Immutable generations remain authoritative. A recovery journal rolls back an
//! interrupted two-file installation; mutable outputs never hardlink to a cache.
use crate::generation::{verified_archive, verify_generation_digest, Generation};
use dm_host::file_stamp::{capture, FileStamp};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::fs::{self, File, OpenOptions};
use std::io::{self, Read, Write};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};

static NEXT: AtomicU64 = AtomicU64::new(0);

#[derive(Debug, Clone, Serialize)]
pub struct ConventionalPair {
    pub dmb: PathBuf,
    pub rsc: PathBuf,
    pub unchanged: bool,
    pub reused_archive: bool,
}

#[derive(Serialize, Deserialize)]
struct Receipt {
    dmb_digest: String,
    rsc_digest: String,
    dmb_stamp: Option<FileStamp>,
    rsc_stamp: Option<FileStamp>,
}

#[derive(Serialize, Deserialize)]
struct Transaction {
    version: u32,
    pending: String,
    dmb: bool,
    rsc: bool,
    old_dmb: bool,
    old_rsc: bool,
    committed: bool,
}

#[derive(Serialize, Deserialize)]
struct CheckedRecord {
    checksum: String,
    payload: String,
}

fn invalid(message: &str) -> io::Error {
    io::Error::new(io::ErrorKind::InvalidData, message)
}

fn digest_file(path: &Path) -> io::Result<String> {
    let mut input = File::open(path)?;
    let mut hash = Sha256::new();
    let mut buffer = [0u8; 64 * 1024];
    loop {
        let count = input.read(&mut buffer)?;
        if count == 0 {
            return Ok(format!("{:x}", hash.finalize()));
        }
        hash.update(&buffer[..count]);
    }
}

fn copy_checked(source: &Path, destination: &Path, expected: &str) -> io::Result<()> {
    let mut input = File::open(source)?;
    let mut output = OpenOptions::new()
        .create_new(true)
        .write(true)
        .open(destination)?;
    let mut hash = Sha256::new();
    let mut buffer = [0u8; 64 * 1024];
    loop {
        let count = input.read(&mut buffer)?;
        if count == 0 {
            break;
        }
        output.write_all(&buffer[..count])?;
        hash.update(&buffer[..count]);
    }
    if format!("{:x}", hash.finalize()) != expected {
        return Err(invalid(
            "immutable generation changed while copying conventional output",
        ));
    }
    output.sync_all()
}

#[cfg(windows)]
fn replace(source: &Path, destination: &Path) -> io::Result<()> {
    use std::os::windows::ffi::OsStrExt;
    #[link(name = "kernel32")]
    unsafe extern "system" {
        fn MoveFileExW(source: *const u16, destination: *const u16, flags: u32) -> i32;
    }
    let source: Vec<u16> = source.as_os_str().encode_wide().chain(Some(0)).collect();
    let destination: Vec<u16> = destination
        .as_os_str()
        .encode_wide()
        .chain(Some(0))
        .collect();
    if unsafe { MoveFileExW(source.as_ptr(), destination.as_ptr(), 1 | 8) } == 0 {
        Err(io::Error::last_os_error())
    } else {
        Ok(())
    }
}

#[cfg(not(windows))]
fn replace(source: &Path, destination: &Path) -> io::Result<()> {
    fs::rename(source, destination)
}

fn save<T: Serialize>(path: &Path, value: &T) -> io::Result<()> {
    let payload = serde_json::to_string(value).map_err(io::Error::other)?;
    let record = CheckedRecord {
        checksum: format!("{:x}", Sha256::digest(payload.as_bytes())),
        payload,
    };
    let temporary = path.with_extension(format!(
        "pending-{}-{}",
        std::process::id(),
        NEXT.fetch_add(1, Ordering::Relaxed)
    ));
    let mut file = OpenOptions::new()
        .create_new(true)
        .write(true)
        .open(&temporary)?;
    serde_json::to_writer(&mut file, &record).map_err(io::Error::other)?;
    file.write_all(b"\n")?;
    file.sync_all()?;
    drop(file);
    let result = replace(&temporary, path);
    if result.is_err() {
        let _ = fs::remove_file(temporary);
    }
    result
}

fn load<T: for<'de> Deserialize<'de>>(path: &Path) -> io::Result<T> {
    let file = File::open(path)?;
    if file.metadata()?.len() > 128 * 1024 {
        return Err(invalid("publication record is oversized"));
    }
    let record: CheckedRecord = serde_json::from_reader(file).map_err(io::Error::other)?;
    if record.checksum != format!("{:x}", Sha256::digest(record.payload.as_bytes())) {
        return Err(invalid("publication record checksum mismatch"));
    }
    serde_json::from_str(&record.payload).map_err(io::Error::other)
}

fn matches(path: &Path, expected: &str, stamp: Option<&FileStamp>) -> bool {
    if std::env::var("DM_BUILD_EXACT_INPUTS").ok().as_deref() != Some("1")
        && stamp.is_some_and(|stamp| capture(path).as_ref() == Some(stamp))
    {
        return true;
    }
    let before = capture(path);
    digest_file(path).is_ok_and(|digest| digest == expected) && before == capture(path)
}

fn verified_stamp(path: &Path, expected: &str) -> io::Result<Option<FileStamp>> {
    let before = capture(path);
    if digest_file(path)? != expected || before != capture(path) {
        return Err(invalid("conventional output changed during publication"));
    }
    Ok(before)
}

fn pending_directory(state: &Path, transaction: &Transaction) -> io::Result<PathBuf> {
    if transaction.version != 1
        || !transaction.pending.starts_with("pair-")
        || !transaction
            .pending
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || byte == b'-')
    {
        return Err(invalid("invalid conventional publication journal"));
    }
    Ok(state.join(&transaction.pending))
}

fn recover(state: &Path, dmb: &Path, rsc: &Path) -> io::Result<()> {
    let journal = state.join("transaction.json");
    let transaction: Transaction = match load(&journal) {
        Ok(transaction) => transaction,
        Err(error) if error.kind() == io::ErrorKind::NotFound => return Ok(()),
        Err(error) => return Err(error),
    };
    let pending = pending_directory(state, &transaction)?;
    if !transaction.committed {
        for (changed, existed, name, target) in [
            (transaction.dmb, transaction.old_dmb, "dmb", dmb),
            (transaction.rsc, transaction.old_rsc, "rsc", rsc),
        ] {
            if !changed {
                continue;
            }
            let backup = pending.join(format!("old.{name}"));
            if backup.exists() {
                replace(&backup, target)?;
            } else if !existed && !pending.join(format!("new.{name}")).exists() && target.exists() {
                fs::remove_file(target)?;
            }
        }
    }
    // The validated single-component journal name keeps cleanup within state.
    if pending.exists() {
        fs::remove_dir_all(&pending)?;
    }
    fs::remove_file(journal)
}

/// Install detached PROJECT.dmb/rsc after a successful immutable generation.
/// The caller must stop consumers before replacing conventional paths. Readers
/// of generation paths do not participate in this compatibility transaction.
pub fn materialize_generation(
    project: &Path,
    root: &Path,
    generation: &Generation,
) -> io::Result<ConventionalPair> {
    // The daemon returns canonical paths (including Windows' extended prefix),
    // while --output-root may be an ordinary or relative caller spelling.
    // Resolve both before enforcing the generation's root/id/path contract.
    let root = root.canonicalize()?;
    let generation = Generation {
        id: generation.id.clone(),
        dmb: generation.dmb.canonicalize()?,
        rsc: generation.rsc.canonicalize()?,
    };
    verify_generation_digest(&root, &generation)?;
    let project = project.canonicalize()?;
    let parent = project
        .parent()
        .ok_or_else(|| invalid("project has no directory"))?;
    let file_name = project
        .file_name()
        .ok_or_else(|| invalid("project has no filename"))?;
    let state = parent
        .join(".dm-native")
        .join("publication")
        .join(file_name);
    fs::create_dir_all(&state)?;
    let lock = OpenOptions::new()
        .create(true)
        .read(true)
        .write(true)
        .open(state.join("lock"))?;
    lock.lock()?;
    let dmb = project.with_extension("dmb");
    let rsc = project.with_extension("rsc");
    recover(&state, &dmb, &rsc)?;
    let expected_dmb = digest_file(&generation.dmb)?;
    let expected_rsc = verified_archive(&root, &generation)?.digest().to_owned();
    let receipt: Option<Receipt> = load(&state.join("receipt.json")).ok();
    let same_dmb = receipt.as_ref().is_some_and(|receipt| {
        receipt.dmb_digest == expected_dmb
            && matches(&dmb, &expected_dmb, receipt.dmb_stamp.as_ref())
    });
    let same_rsc = receipt.as_ref().is_some_and(|receipt| {
        receipt.rsc_digest == expected_rsc
            && matches(&rsc, &expected_rsc, receipt.rsc_stamp.as_ref())
    });
    if same_dmb && same_rsc {
        return Ok(ConventionalPair {
            dmb,
            rsc,
            unchanged: true,
            reused_archive: true,
        });
    }
    let transaction = Transaction {
        version: 1,
        pending: format!(
            "pair-{}-{}",
            std::process::id(),
            NEXT.fetch_add(1, Ordering::Relaxed)
        ),
        dmb: !same_dmb,
        rsc: !same_rsc,
        old_dmb: dmb.exists(),
        old_rsc: rsc.exists(),
        committed: false,
    };
    let pending = pending_directory(&state, &transaction)?;
    fs::create_dir(&pending)?;
    let result = (|| {
        if !same_dmb {
            copy_checked(&generation.dmb, &pending.join("new.dmb"), &expected_dmb)?;
        }
        if !same_rsc {
            copy_checked(&generation.rsc, &pending.join("new.rsc"), &expected_rsc)?;
        }
        save(&state.join("transaction.json"), &transaction)?;
        for (changed, name, target) in [
            (transaction.dmb, "dmb", &dmb),
            (transaction.rsc, "rsc", &rsc),
        ] {
            if !changed {
                continue;
            }
            if target.exists() {
                fs::rename(target, pending.join(format!("old.{name}")))?;
            }
            fs::rename(pending.join(format!("new.{name}")), target)?;
        }
        save(
            &state.join("receipt.json"),
            &Receipt {
                dmb_stamp: if same_dmb {
                    receipt
                        .as_ref()
                        .and_then(|receipt| receipt.dmb_stamp.clone())
                } else {
                    verified_stamp(&dmb, &expected_dmb)?
                },
                rsc_stamp: if same_rsc {
                    receipt
                        .as_ref()
                        .and_then(|receipt| receipt.rsc_stamp.clone())
                } else {
                    verified_stamp(&rsc, &expected_rsc)?
                },
                dmb_digest: expected_dmb,
                rsc_digest: expected_rsc,
            },
        )?;
        let committed = Transaction {
            committed: true,
            ..transaction
        };
        save(&state.join("transaction.json"), &committed)?;
        recover(&state, &dmb, &rsc)
    })();
    if result.is_err() {
        if state.join("transaction.json").exists() {
            let _ = recover(&state, &dmb, &rsc);
        } else if pending.exists() {
            let _ = fs::remove_dir_all(pending);
        }
    }
    result?;
    Ok(ConventionalPair {
        dmb,
        rsc,
        unchanged: false,
        reused_archive: same_rsc,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::generation::publish_generation;
    fn fixture() -> PathBuf {
        let root = std::env::temp_dir().join(format!(
            "dm-conventional-{}-{}",
            std::process::id(),
            NEXT.fetch_add(1, Ordering::Relaxed)
        ));
        fs::create_dir_all(&root).unwrap();
        fs::write(root.join("project.dme"), "").unwrap();
        root
    }
    #[test]
    fn conventional_files_are_detached_and_unchanged_archive_is_reused() {
        let root = fixture();
        let mut world = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/native_template.bin"
        ))
        .unwrap();
        world.resources.clear();
        let first = publish_generation(&root.join("out"), &world.to_bytes().unwrap(), &[]).unwrap();
        let pair =
            materialize_generation(&root.join("project.dme"), &root.join("out"), &first).unwrap();
        assert!(!pair.unchanged);
        let repeated =
            materialize_generation(&root.join("project.dme"), &root.join("out"), &first).unwrap();
        assert!(repeated.unchanged);
        fs::write(&pair.dmb, b"mutable output").unwrap();
        verify_generation_digest(&root.join("out"), &first).unwrap();
        let repaired =
            materialize_generation(&root.join("project.dme"), &root.join("out"), &first).unwrap();
        assert!(!repaired.unchanged && repaired.reused_archive);
        assert_eq!(fs::read(&pair.dmb).unwrap(), fs::read(&first.dmb).unwrap());
        fs::remove_dir_all(root).unwrap();
    }
    #[test]
    fn prepared_transaction_rolls_back_a_partial_install() {
        let root = fixture();
        let state = root.join("state");
        fs::create_dir_all(state.join("pair-test")).unwrap();
        let dmb = root.join("project.dmb");
        let rsc = root.join("project.rsc");
        fs::write(&dmb, b"new dmb").unwrap();
        fs::write(&rsc, b"old rsc").unwrap();
        fs::write(state.join("pair-test/old.dmb"), b"old dmb").unwrap();
        fs::write(state.join("pair-test/new.rsc"), b"new rsc").unwrap();
        save(
            &state.join("transaction.json"),
            &Transaction {
                version: 1,
                pending: "pair-test".into(),
                dmb: true,
                rsc: true,
                old_dmb: true,
                old_rsc: true,
                committed: false,
            },
        )
        .unwrap();
        recover(&state, &dmb, &rsc).unwrap();
        assert_eq!(fs::read(dmb).unwrap(), b"old dmb");
        assert_eq!(fs::read(rsc).unwrap(), b"old rsc");
        assert!(!state.join("transaction.json").exists());
        fs::remove_dir_all(root).unwrap();
    }
    #[test]
    fn canonical_daemon_paths_accept_an_ordinary_output_root() {
        let root = fixture();
        let mut world = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/native_template.bin"
        ))
        .unwrap();
        world.resources.clear();
        let output = root.join("output");
        let published = publish_generation(&output, &world.to_bytes().unwrap(), &[]).unwrap();
        let canonical = Generation {
            id: published.id.clone(),
            dmb: published.dmb.canonicalize().unwrap(),
            rsc: published.rsc.canonicalize().unwrap(),
        };
        materialize_generation(&root.join("project.dme"), &output, &canonical).unwrap();
        fs::remove_dir_all(root).unwrap();
    }
}
