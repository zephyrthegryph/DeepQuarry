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
    println!("cargo:rerun-if-changed=vendor");
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
    // The vendored parser shapes the stored model (sem/model_store.rs): its sources key the cache too.
    collect(&manifest.join("vendor"), &mut files);
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

    // ---- per-lint versions (hosted path) ------------------------------------------------------
    // A lint module no other source names (`lints::<m>`) is a leaf: its own files version it, and every other source is the
    // core version. A module some other source names stays in the core, so editing it changes every lint's version.
    let lints_dir = src.join("lints");
    let lint_mods = discover(&lints_dir);
    let mut texts: Vec<(PathBuf, String)> = Vec::new();
    for f in &files {
        if let Ok(t) = fs::read_to_string(f) {
            texts.push((f.clone(), t));
        }
    }
    let mut leaves: Vec<(String, Vec<PathBuf>)> = Vec::new();
    for m in &lint_mods {
        let own = lints_dir.join(m);
        let own_file = lints_dir.join(format!("{}.rs", m));
        let is_own = |p: &Path| p == own_file || p.starts_with(&own);
        let needle = format!("lints::{}", m);
        let named = texts.iter().any(|(p, t)| !is_own(p) && t.contains(&needle) && !p.ends_with("build.rs"));
        if !named {
            leaves.push((m.clone(), texts.iter().filter(|(p, _)| is_own(p)).map(|(p, _)| p.clone()).collect()));
        }
    }
    let leaf_files: std::collections::HashSet<PathBuf> = leaves.iter().flat_map(|(_, fs)| fs.iter().cloned()).collect();
    let mut core = blake3_lite::Hasher::new();
    for f in &files {
        if leaf_files.contains(f) {
            continue;
        }
        if let Ok(bytes) = fs::read(f) {
            core.update(f.file_name().unwrap().to_string_lossy().as_bytes());
            core.update(&bytes);
        }
    }
    let mut table = String::new();
    let _ = writeln!(table, "pub const CORE_HASH: &str = \"{}\";", core.finish_hex());
    let _ = writeln!(table, "pub const LEAF_HASHES: &[(&str, &str)] = &[");
    for (m, fs_) in &leaves {
        let mut h = blake3_lite::Hasher::new();
        for f in fs_ {
            if let Ok(bytes) = fs::read(f) {
                h.update(f.file_name().unwrap().to_string_lossy().as_bytes());
                h.update(&bytes);
            }
        }
        let _ = writeln!(table, "    (\"{}\", \"{}\"),", m, h.finish_hex());
    }
    let _ = writeln!(table, "];");
    fs::write(out_dir.join("lint_versions_gen.rs"), table).unwrap();
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
