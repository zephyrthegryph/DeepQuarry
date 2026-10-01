//! Build-time cache dependency policy, also included by focused tests.
use sha2::{Digest, Sha256};
use std::collections::{BTreeMap, BTreeSet};
use std::fs;
use std::path::{Path, PathBuf};

pub struct Inputs {
    pub parse: Vec<PathBuf>,
    pub lowering: Vec<PathBuf>,
    pub emission: Vec<PathBuf>,
}

fn collect_rs(directory: &Path, files: &mut Vec<PathBuf>) {
    // Watch directories too: newly added modules must change the fingerprint.
    println!("cargo:rerun-if-changed={}", directory.display());
    for entry in
        fs::read_dir(directory).unwrap_or_else(|error| panic!("{}: {error}", directory.display()))
    {
        let path = entry.unwrap().path();
        if path.is_dir() {
            collect_rs(&path, files);
        } else if path.extension().is_some_and(|extension| extension == "rs") {
            files.push(path);
        }
    }
}
fn package(root: &Path, name: &str, files: &mut Vec<PathBuf>) {
    let directory = root.join("crates").join(name);
    files.push(directory.join("Cargo.toml"));
    collect_rs(&directory.join("src"), files);
}
pub fn inputs(root: &Path) -> Inputs {
    let policy = [
        root.join("crates/dm-compiler/build.rs"),
        root.join("crates/dm-compiler/fingerprints.rs"),
    ];
    let mut parse = policy.to_vec();
    package(root, "dm-syntax", &mut parse);
    package(root, "dm-store", &mut parse);
    parse.push(root.join("crates/dm-compiler/src/proc_parse_cache.rs"));
    let mut lowering = parse.clone();
    for name in ["dm-codegen-byond", "dm-ir", "dm-semantics", "dm-store"] {
        package(root, name, &mut lowering);
    }
    let mut adapters = Vec::new();
    collect_rs(&root.join("crates/dm-compiler/src"), &mut adapters);
    // Known producers/output-only modules have no effect on lowering a supplied
    // AST and binding frame. Unknown new modules are included conservatively.
    adapters.retain(|path| {
        !matches!(
            path.file_name().and_then(|name| name.to_str()),
            Some("frontend.rs" | "frontend_layout.rs" | "frontend_layout_tests.rs" | "maps.rs")
        )
    });
    lowering.extend(adapters);
    // The instruction constants depend on both generator and opcode registry.
    for name in [
        "build.rs",
        "src/lib.rs",
        "src/bytecode.rs",
        "src/operands.rs",
        "src/opcodes.txt",
        "src/ids.rs",
        "src/dmb.rs",
        "Cargo.toml",
        "crates/dm-compiler/Cargo.toml",
    ] {
        lowering.push(root.join(name));
    }
    let mut emission = policy.to_vec();
    emission.extend([
        root.join("Cargo.toml"),
        root.join("Cargo.lock"),
        root.join("build.rs"),
        root.join("src/opcodes.txt"),
    ]);
    collect_rs(&root.join("src"), &mut emission);
    for name in [
        "dm-compiler",
        "dm-codegen-byond",
        "dm-preprocess",
        "dm-syntax",
        "dm-semantics",
        "dm-ir",
        "dm-resources",
        "dm-store",
    ] {
        package(root, name, &mut emission);
    }
    for files in [&mut parse, &mut lowering, &mut emission] {
        files.sort();
        files.dedup();
    }
    Inputs {
        parse,
        lowering,
        emission,
    }
}

/// Preserve full selected lockfile blocks, including versions/checksums and
/// transitive dependencies. All duplicate versions are included conservatively.
/// Unknown lockfile shapes fall back to hashing the whole file.
pub fn lock_closure(lock: &str, seeds: &[&str]) -> Vec<u8> {
    fn quoted(line: &str) -> Option<&str> {
        line.trim().strip_prefix('"')?.strip_suffix('"')
    }
    let mut packages: BTreeMap<&str, Vec<(&str, Vec<&str>)>> = BTreeMap::new();
    if !lock
        .lines()
        .any(|line| matches!(line.trim(), "version = 3" | "version = 4"))
    {
        return lock.as_bytes().to_vec();
    }
    for block in lock.split("[[package]]").skip(1) {
        let Some(name) = block
            .lines()
            .find_map(|line| line.strip_prefix("name = ").and_then(quoted))
        else {
            return lock.as_bytes().to_vec();
        };
        let mut dependencies = Vec::new();
        let mut in_dependencies = false;
        for line in block.lines() {
            if line.trim() == "dependencies = [" {
                in_dependencies = true;
                continue;
            }
            if line.trim_start().starts_with("dependencies =") {
                return lock.as_bytes().to_vec();
            }
            if in_dependencies {
                if line.trim() == "]" {
                    in_dependencies = false;
                    continue;
                }
                let Some(dependency) = quoted(line.trim().trim_end_matches(',')) else {
                    return lock.as_bytes().to_vec();
                };
                let Some(dependency) = dependency.split_whitespace().next() else {
                    return lock.as_bytes().to_vec();
                };
                dependencies.push(dependency);
            }
        }
        if in_dependencies {
            return lock.as_bytes().to_vec();
        }
        packages
            .entry(name)
            .or_default()
            .push((block, dependencies));
    }
    let mut wanted = seeds.iter().copied().collect::<Vec<_>>();
    let mut selected = BTreeSet::new();
    while let Some(name) = wanted.pop() {
        if !selected.insert(name) {
            continue;
        }
        let Some(entries) = packages.get(name) else {
            return lock.as_bytes().to_vec();
        };
        for (_, dependencies) in entries {
            wanted.extend(dependencies);
        }
    }
    let mut output = Vec::new();
    for name in selected {
        for (block, _) in &packages[name] {
            output.extend_from_slice(&(block.len() as u64).to_le_bytes());
            output.extend_from_slice(block.as_bytes());
        }
    }
    output
}
pub fn fingerprint(root: &Path, stage: &str, files: &[PathBuf], lock: &[u8]) -> String {
    let mut hash = Sha256::new();
    hash.update(b"dm-stage-implementation-v2\0");
    hash.update(stage.as_bytes());
    for path in files {
        let bytes = fs::read(path)
            .unwrap_or_else(|error| panic!("cannot fingerprint {}: {error}", path.display()));
        println!("cargo:rerun-if-changed={}", path.display());
        let name = path
            .strip_prefix(root)
            .unwrap()
            .to_string_lossy()
            .replace('\\', "/");
        hash.update((name.len() as u64).to_le_bytes());
        hash.update(name.as_bytes());
        hash.update((bytes.len() as u64).to_le_bytes());
        hash.update(&bytes);
    }
    hash.update((lock.len() as u64).to_le_bytes());
    hash.update(lock);
    format!("{:x}", hash.finalize())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn dependency_closure_ignores_unrelated_versions_but_keeps_transitive_changes() {
        let lock = "version = 4\n[[package]]\nname = \"parser\"\nversion = \"1\"\ndependencies = [\n \"codec 1\",\n]\n[[package]]\nname = \"codec\"\nversion = \"1\"\nchecksum = \"first\"\n[[package]]\nname = \"publisher\"\nversion = \"1\"\n";
        let original = lock_closure(lock, &["parser"]);
        assert_eq!(
            original,
            lock_closure(
                &lock.replace(
                    "name = \"publisher\"\nversion = \"1\"",
                    "name = \"publisher\"\nversion = \"2\""
                ),
                &["parser"]
            )
        );
        assert_ne!(
            original,
            lock_closure(
                &lock.replace("checksum = \"first\"", "checksum = \"second\""),
                &["parser"]
            )
        );
        assert_eq!(lock.as_bytes(), lock_closure(lock, &["missing"]));
    }
    #[test]
    fn duplicate_versions_and_unknown_format_fail_conservatively() {
        let lock = "version = 4\n[[package]]\nname = \"codec\"\nversion = \"1\"\n[[package]]\nname = \"codec\"\nversion = \"2\"\n";
        assert_ne!(
            lock_closure(lock, &["codec"]),
            lock_closure(
                &lock.replace("version = \"2\"", "version = \"3\""),
                &["codec"]
            )
        );
        let unsupported = lock.replace("version = 4", "version = 99");
        assert_eq!(
            unsupported.as_bytes(),
            lock_closure(&unsupported, &["codec"])
        );
    }
}
