mod fingerprints;
use std::{fs, path::PathBuf};

fn main() {
    let root = PathBuf::from(std::env::var("CARGO_MANIFEST_DIR").unwrap()).join("../..");
    let inputs = fingerprints::inputs(&root);
    let lock_path = root.join("Cargo.lock");
    println!("cargo:rerun-if-changed={}", lock_path.display());
    let lock = fs::read_to_string(lock_path).expect("read Cargo lockfile");
    let parse_lock =
        fingerprints::lock_closure(&lock, &["dm-syntax", "dm-store", "serde", "serde_json", "sha2"]);
    let lowering_lock = fingerprints::lock_closure(
        &lock,
        &[
            "dm-codegen-byond",
            "dm-syntax",
            "dm-ir",
            "dm-semantics",
            "dm-store",
            "salsa",
            "sha2",
            "serde_json",
            "lz4_flex",
        ],
    );
    for (name, stage, files, lock) in [
        (
            "DM_PROC_PARSE_FINGERPRINT",
            "procedure-syntax",
            &inputs.parse,
            parse_lock.as_slice(),
        ),
        (
            "DM_LOWERING_FINGERPRINT",
            "symbolic-lowering",
            &inputs.lowering,
            lowering_lock.as_slice(),
        ),
        (
            "DM_EMISSION_FINGERPRINT",
            "project-emission",
            &inputs.emission,
            lock.as_bytes(),
        ),
    ] {
        println!(
            "cargo:rustc-env={name}={}",
            fingerprints::fingerprint(&root, stage, files, lock)
        );
    }
}
