//! Content-addressed whole-analysis reuse. Changed inputs fall back to a full scan.
use serde::{Deserialize, Serialize};
use serde_json::Value;
use sha2::{Digest, Sha256};
use std::collections::BTreeSet;
use std::fs;
use std::io::{self, Read};
use std::path::{Path, PathBuf};

#[derive(Serialize, Deserialize)]
pub struct CachedReport {
    pub key: String,
    pub strict_failed: bool,
    pub snapshot: Value,
}

#[derive(Serialize)]
struct BorrowedReport<'a> {
    key: &'a str,
    strict_failed: bool,
    snapshot: &'a Value,
}

fn update_file(hash: &mut Sha256, path: &Path) -> io::Result<()> {
    let mut file = fs::File::open(path)?;
    let mut file_hash = Sha256::new();
    let mut chunk = [0_u8; 65536];
    loop {
        let count = file.read(&mut chunk)?;
        if count == 0 {
            break;
        }
        file_hash.update(&chunk[..count]);
    }
    hash.update(file_hash.finalize());
    Ok(())
}

pub fn key(
    root: &Path,
    ast: &Path,
    baseline: Option<&Path>,
    strict_types: bool,
    strict_modules: &[String],
    included_files: &[PathBuf],
) -> io::Result<String> {
    let mut hash = Sha256::new();
    hash.update(b"dm-health-analysis-cache-v1\0");
    let root = root.canonicalize()?;
    hash.update(root.to_string_lossy().as_bytes());
    hash.update(b"\0");
    let binary = std::env::current_exe()?;
    update_file(&mut hash, &binary)?;
    let mut sidecar = ast.as_os_str().to_os_string();
    sidecar.push(".sha256");
    hash.update(fs::read(sidecar)?);
    hash.update([u8::from(strict_types)]);
    let mut modules = strict_modules.to_vec();
    modules.sort();
    for module in modules {
        hash.update(module.as_bytes());
        hash.update(b"\0");
    }
    if let Some(path) = baseline {
        hash.update(b"baseline\0");
        update_file(&mut hash, path)?;
    } else {
        hash.update(b"no-baseline\0");
    }
    let mut folders = BTreeSet::<PathBuf>::new();
    for file in included_files {
        let canonical_file = file.canonicalize()?;
        let mut current = canonical_file.parent();
        while let Some(folder) = current {
            if !folder.starts_with(&root) {
                break;
            }
            folders.insert(folder.to_path_buf());
            if folder == root {
                break;
            }
            current = folder.parent();
        }
    }
    for folder in folders {
        for name in ["README.md", "readme.md", "Readme.md"] {
            let path = folder.join(name);
            if path.is_file() {
                hash.update(
                    path.strip_prefix(&root)
                        .unwrap_or(&path)
                        .to_string_lossy()
                        .as_bytes(),
                );
                hash.update(b"\0");
                update_file(&mut hash, &path)?;
                hash.update(b"\0");
            }
        }
    }
    Ok(format!("{:x}", hash.finalize()))
}

pub fn load(directory: &Path, key: &str) -> Option<CachedReport> {
    let path = directory.join(format!("{key}.json"));
    let bytes = fs::read(&path).ok()?;
    let expected = fs::read_to_string(directory.join(format!("{key}.json.sha256"))).ok()?;
    if format!("{:x}", Sha256::digest(&bytes)) != expected.trim() {
        return None;
    }
    let cached: CachedReport = serde_json::from_slice(&bytes).ok()?;
    (cached.key == key
        && cached.snapshot["schema_version"] == 2
        && cached.snapshot["findings"].is_array()
        && cached.snapshot["new_fingerprints"].is_array()
        && cached.snapshot["counts"].is_object()
        && cached.snapshot["metrics"].is_object()
        && cached.snapshot["type_coverage"].is_object())
    .then_some(cached)
}

pub fn store(directory: &Path, cached: &CachedReport) -> io::Result<()> {
    store_snapshot(
        directory,
        &cached.key,
        cached.strict_failed,
        &cached.snapshot,
    )
}

/// Persist a snapshot without cloning its potentially large findings and
/// root-cause arrays merely to construct an owned cache record.
pub fn store_snapshot(
    directory: &Path,
    key: &str,
    strict_failed: bool,
    snapshot: &Value,
) -> io::Result<()> {
    fs::create_dir_all(directory)?;
    let path = directory.join(format!("{key}.json"));
    if load(directory, key).is_some() {
        return Ok(());
    }
    let temporary = directory.join(format!("{key}.{}.tmp", std::process::id()));
    let temporary_checksum = directory.join(format!("{key}.{}.sha256.tmp", std::process::id()));
    let bytes = serde_json::to_vec(&BorrowedReport {
        key,
        strict_failed,
        snapshot,
    })?;
    fs::write(&temporary, &bytes)?;
    fs::write(&temporary_checksum, format!("{:x}", Sha256::digest(&bytes)))?;
    if path.exists() {
        fs::remove_file(&path)?;
    }
    let checksum = directory.join(format!("{key}.json.sha256"));
    if checksum.exists() {
        fs::remove_file(&checksum)?;
    }
    fs::rename(temporary, path)?;
    fs::rename(temporary_checksum, checksum)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn cache_round_trip_rejects_wrong_key() {
        let directory = std::env::temp_dir().join(format!(
            "dm-health-cache-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        let cached = CachedReport {
            key: "test-key".into(),
            strict_failed: true,
            snapshot: serde_json::json!({"schema_version":2,"findings":[],"new_fingerprints":[],
                "counts":{},"metrics":{},"type_coverage":{}}),
        };
        store(&directory, &cached).unwrap();
        assert!(load(&directory, "test-key").unwrap().strict_failed);
        assert!(load(&directory, "other-key").is_none());
        fs::write(directory.join("test-key.json.sha256"), "bad").unwrap();
        assert!(load(&directory, "test-key").is_none());
        fs::remove_dir_all(directory).unwrap();
    }

    #[test]
    fn readme_change_invalidates_analysis_key() {
        let root = std::env::temp_dir().join(format!(
            "dm-health-cache-key-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        fs::create_dir_all(root.join("code/feature")).unwrap();
        fs::write(
            root.join("deepquarry.dme"),
            b"#include \"code/feature/test.dm\"\n",
        )
        .unwrap();
        fs::write(root.join("code/feature/test.dm"), b"/datum/test\n").unwrap();
        fs::write(root.join("code/feature/README.md"), b"first").unwrap();
        let ast = root.join("test.ast.jsonl");
        fs::write(format!("{}.sha256", ast.display()), b"test-checksum").unwrap();
        let files = vec![root.join("code/feature/test.dm")];
        let first = key(&root, &ast, None, false, &[], &files).unwrap();
        fs::write(root.join("code/feature/README.md"), b"second").unwrap();
        let second = key(&root, &ast, None, false, &[], &files).unwrap();
        assert_ne!(first, second);
        fs::remove_dir_all(root).unwrap();
    }
}
