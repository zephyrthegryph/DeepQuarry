//! Seal Cargo's ACTUAL compiler/target inputs, not a runtime opt-in tuple.
mod source_arc_profile_policy;
use sha2::{Digest, Sha256};
use source_arc_profile_policy as policy;
use std::{
    env, fs,
    path::{Path, PathBuf},
    process::Command,
};
fn output(rustc: &std::ffi::OsStr, args: &[&str]) -> Option<String> {
    let result = Command::new(rustc).args(args).output().ok()?;
    result
        .status
        .success()
        .then(|| String::from_utf8(result.stdout).ok())
        .flatten()
}
fn hash(path: &Path) -> Option<String> {
    println!("cargo:rerun-if-changed={}", path.display());
    let bytes = fs::read(path).ok()?;
    Some(format!("{:x}", Sha256::digest(bytes)))
}
fn main() {
    println!("cargo:rustc-check-cfg=cfg(dmb_arc_probe)");
    println!("cargo:rerun-if-changed=source_arc_profile_policy.rs");
    for name in [
        "RUSTC",
        "TARGET",
        "RUSTUP_TOOLCHAIN",
        "CARGO_CFG_TARGET_POINTER_WIDTH",
        "CARGO_CFG_TARGET_HAS_ATOMIC",
    ] {
        println!("cargo:rerun-if-env-changed={name}");
    }
    let mut candidate = false;
    let mut compiler_path = String::new();
    let mut cargo_target = String::new();
    let mut compiler_sysroot = String::new();
    let mut compiler_target_libdir = String::new();
    let mut liballoc_artifact = String::new();
    let mut description = String::from("actual compiler profile unavailable");
    if let (Some(rustc), Ok(target), Ok(width), Ok(atomics)) = (
        env::var_os("RUSTC"),
        env::var("TARGET"),
        env::var("CARGO_CFG_TARGET_POINTER_WIDTH"),
        env::var("CARGO_CFG_TARGET_HAS_ATOMIC"),
    ) {
        compiler_path = rustc.to_str().unwrap_or("").to_owned();
        cargo_target = target.clone();
        if let (Some(verbose), Some(sysroot), Some(libdir)) = (
            output(&rustc, &["-vV"]),
            output(&rustc, &["--print", "sysroot"]),
            output(&rustc, &["--print", "target-libdir", "--target", &target]),
        ) {
            compiler_sysroot = sysroot.trim().to_owned();
            compiler_target_libdir = libdir.trim().to_owned();
            let field = |prefix: &str| {
                verbose
                    .lines()
                    .find_map(|line| line.strip_prefix(prefix))
                    .unwrap_or("")
            };
            let source = PathBuf::from(sysroot.trim())
                .join("lib/rustlib/src/rust/library/alloc/src/sync.rs");
            // A new second liballoc can invalidate the exact-one-artifact
            // contract without changing the previously watched artifact.
            println!("cargo:rerun-if-changed={}", libdir.trim());
            let mut allocs = fs::read_dir(libdir.trim())
                .ok()
                .into_iter()
                .flatten()
                .filter_map(Result::ok)
                .map(|e| e.path())
                .filter(|p| {
                    p.file_name()
                        .and_then(|s| s.to_str())
                        .is_some_and(|s| s.starts_with("liballoc-") && s.ends_with(".rlib"))
                });
            if let (Some(alloc), None) = (allocs.next(), allocs.next()) {
                liballoc_artifact = alloc.to_str().unwrap_or("").to_owned();
                if let (Some(source_sha), Some(alloc_sha)) = (hash(&source), hash(&alloc)) {
                    candidate = !compiler_path.is_empty()
                        && Path::new(&compiler_path).is_absolute()
                        && !liballoc_artifact.is_empty()
                        && policy::matches(&policy::Candidate {
                            commit: field("commit-hash: "),
                            release: field("release: "),
                            target: &target,
                            pointer_width: &width,
                            source_sha: &source_sha,
                            alloc_sha: &alloc_sha,
                            has_pointer_atomics: atomics.split(',').any(|s| s == "ptr"),
                        });
                    description = format!(
                        "{}|{}|{}|{}|{}|{}",
                        field("commit-hash: "),
                        field("release: "),
                        target,
                        width,
                        source_sha,
                        alloc_sha
                    );
                }
            }
        }
    }
    let out = PathBuf::from(env::var_os("OUT_DIR").expect("Cargo OUT_DIR"));
    let code=format!("pub const CANDIDATE_MATCHED:bool={candidate};\npub const PROBE_APPROVED:bool={};\npub const DESCRIPTION:&str={description:?};\n",candidate&&policy::PROBE_APPROVED);
    let code=format!("{code}pub const CARGO_RUSTC_PATH:&str={compiler_path:?};\npub const CARGO_TARGET:&str={cargo_target:?};\npub const SYSROOT:&str={compiler_sysroot:?};\npub const TARGET_LIBDIR:&str={compiler_target_libdir:?};\npub const LIBALLOC_ARTIFACT:&str={liballoc_artifact:?};\n");
    fs::write(out.join("native_arc_profile.rs"), code)
        .expect("write crate-local Arc profile receipt");
}
