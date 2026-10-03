//! Build script: (1) discovers the lint modules under src/lints/ so adding a lint is adding a
//! file (no shared registry to edit), and (2) hashes the engine's own sources into ENGINE_HASH,
//! which keys the on-disk cache so a rebuilt engine never serves a stale result.
use std::fmt::Write as _;
use std::fs;
use std::path::{Path, PathBuf};

fn collect(dir: &Path, out: &mut Vec<PathBuf>) {
    let Ok(rd) = fs::read_dir(dir) else { return };
    let mut entries: Vec<_> = rd.filter_map(|e| e.ok()).collect();
    entries.sort_by_key(|e| e.file_name());
    for e in entries {
        let p = e.path();
        if p.is_dir() {
            collect(&p, out);
        } else if p.extension().map(|x| x == "rs").unwrap_or(false) {
            out.push(p);
        }
    }
}

/// The module names under `dir`: `x.rs` files and `x/mod.rs` directories, except `mod` itself.
fn discover(dir: &Path) -> Vec<String> {
    let mut mods: Vec<String> = Vec::new();
    if let Ok(rd) = fs::read_dir(dir) {
        for e in rd.filter_map(|e| e.ok()) {
            let p = e.path();
            let name = p.file_stem().unwrap().to_string_lossy().to_string();
            if name == "mod" {
                continue;
            }
            if p.is_dir() {
                if p.join("mod.rs").exists() {
                    mods.push(e.file_name().to_string_lossy().to_string());
                }
            } else if p.extension().map(|x| x == "rs").unwrap_or(false) {
                mods.push(name);
            }
        }
    }
    mods.sort();
    mods.dedup();
    mods
}

fn main() {
    let manifest = PathBuf::from(std::env::var("CARGO_MANIFEST_DIR").unwrap());
    let src = manifest.join("src");

    println!("cargo:rerun-if-changed=src");
    println!("cargo:rerun-if-changed=build.rs");

    // ---- module discovery -----------------------------------------------------------------
    let out_dir = PathBuf::from(std::env::var("OUT_DIR").unwrap());
    let base = manifest.display().to_string().replace('\\', "/");
    for (sub, with_register, reg_ty) in [("lints", true, "crate::lint::Registry"), ("gens", true, "Vec<Box<dyn crate::sem::gen::Generator>>"), ("codemods", true, "Vec<Box<dyn crate::codemod::Codemod>>"), ("dm", false, "")] {
        let dir = src.join(sub);
        let mods = discover(&dir);
        let mut gen = String::new();
        for m in &mods {
            let file = if dir.join(m).is_dir() { format!("{}/mod.rs", m) } else { format!("{}.rs", m) };
            let _ = writeln!(gen, "#[path = \"{}/src/{}/{}\"]", base, sub, file);
            let _ = writeln!(gen, "pub mod {};", m);
        }
        if with_register {
            let _ = writeln!(gen, "pub fn register(reg: &mut {}) {{", reg_ty);
            for m in &mods {
                let _ = writeln!(gen, "    {}::register(reg);", m);
            }
            let _ = writeln!(gen, "}}");
        }
        fs::write(out_dir.join(format!("{}_gen.rs", sub)), gen).unwrap();
    }

    // ---- engine hash ---------------------------------------------------------------------
    let mut files = Vec::new();
    collect(&src, &mut files);
    files.push(manifest.join("build.rs"));
    files.push(manifest.join("Cargo.toml"));
    let mut hasher = blake3_lite::Hasher::new();
    for f in &files {
        if let Ok(bytes) = fs::read(f) {
            hasher.update(f.file_name().unwrap().to_string_lossy().as_bytes());
            hasher.update(&bytes);
        }
    }
    println!("cargo:rustc-env=DQ_ENGINE_HASH={}", hasher.finish_hex());
}

/// A tiny FNV-1a/128-style hasher: the build script has no dependencies, and this only needs to
/// change when the sources change.
mod blake3_lite {
    pub struct Hasher(u64, u64);
    impl Hasher {
        pub fn new() -> Self {
            Hasher(0xcbf29ce484222325, 0x84222325cbf29ce4)
        }
        pub fn update(&mut self, data: &[u8]) {
            for &b in data {
                self.0 ^= b as u64;
                self.0 = self.0.wrapping_mul(0x100000001b3);
                self.1 ^= (b as u64).rotate_left(7);
                self.1 = self.1.wrapping_mul(0x9e3779b97f4a7c15).rotate_left(13);
            }
        }
        pub fn finish_hex(&self) -> String {
            format!("{:016x}{:016x}", self.0, self.1)
        }
    }
}
