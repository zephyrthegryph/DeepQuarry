use sha2::{Digest, Sha256};
use std::fs;
use std::path::{Path, PathBuf};

fn collect_rs(directory: &Path, files: &mut Vec<PathBuf>) {
    let Ok(entries) = fs::read_dir(directory) else {
        return;
    };
    for entry in entries.flatten() {
        let path = entry.path();
        if path.is_dir() {
            collect_rs(&path, files);
        } else if path.extension().is_some_and(|extension| extension == "rs") {
            files.push(path);
        }
    }
}

fn main() {
    let root = PathBuf::from(std::env::var("CARGO_MANIFEST_DIR").unwrap()).join("../..");
    let packages = [
        "dm-compiled",
        "dm-compiler",
        "dm-codegen-byond",
        "dm-preprocess",
        "dm-syntax",
        "dm-semantics",
        "dm-ir",
        "dm-output",
        "dm-resources",
        "dm-host",
    ];
    let mut files = vec![root.join("Cargo.toml"), root.join("Cargo.lock")];
    collect_rs(&root.join("src"), &mut files);
    for package in packages {
        let directory = root.join("crates").join(package);
        files.push(directory.join("Cargo.toml"));
        collect_rs(&directory.join("src"), &mut files);
    }
    files.push(root.join("crates/dm-compiled/build.rs"));
    files.sort();
    let mut hash = Sha256::new();
    hash.update(b"dm-build-implementation-v1\0");
    for path in files {
        let bytes = fs::read(&path)
            .unwrap_or_else(|error| panic!("cannot fingerprint {}: {error}", path.display()));
        println!("cargo:rerun-if-changed={}", path.display());
        let relative = path.strip_prefix(&root).unwrap_or(&path);
        let name = relative.to_string_lossy();
        hash.update((name.len() as u64).to_le_bytes());
        hash.update(name.as_bytes());
        hash.update((bytes.len() as u64).to_le_bytes());
        hash.update(&bytes);
    }
    println!("cargo:rustc-env=DM_BUILD_FINGERPRINT={:x}", hash.finalize());
}
