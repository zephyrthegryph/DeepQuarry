//! Build script: (1) discovers the lint modules under src/lints/ so adding a lint is adding a
//! file (no shared registry to edit), and (2) hashes the engine's own sources into ENGINE_HASH,
//! which keys the on-disk cache so a rebuilt engine never serves a stale result.
#[path = "cargo_source_inputs.rs"]
mod cargo_source_inputs;
#[path = "src/native_policy_roster.rs"]
mod native_policy_roster;
use std::fmt::Write as _;
use std::fs;
use std::path::{Path, PathBuf};

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
    let legacy = std::env::var_os("CARGO_FEATURE_LEGACY_SEM").is_some();
    let _ = native_policy_roster::LINT_NAMES.len();
    // SAME full discovery as real legacy registration, even in native-only
    // builds. A newly registered module without its metadata descriptor fails.
    let full_metadata_modules=discover(&src.join("lints"));
    let mut full_metadata=String::new();
    for module in &full_metadata_modules {
        let descriptor=src.join("allow_registry_fields").join(format!("{module}.rs"));
        assert!(descriptor.is_file(),"registered lint lacks shared ALLOW metadata: {module}");
        writeln!(full_metadata,"#[path = \"{}\"] pub mod {};",descriptor.display().to_string().replace('\\',"/"),module).unwrap();
    }
    full_metadata.push_str("pub(crate) fn collect_all<C:crate::key_policy_control::Control>(names:&mut std::collections::BTreeSet<String>,control:&mut C)->Result<(),C::Error>{\n");
    for module in &full_metadata_modules {
        // Exactly the same two delegated registrations as lints_gen.rs.
        if matches!(module.as_str(),"lifeform_allows"|"escape_hatches"){continue}
        writeln!(full_metadata,"{}::collect(names,control)?;",module).unwrap();
    }
    full_metadata.push_str("control.checkpoint()\n}\n");
    full_metadata.push_str("#[cfg(feature=\"native-policy\")]\n pub(crate) fn visit_all_scopes<C:crate::key_policy_control::Control>(control:&mut C,visit:&mut dyn FnMut(crate::required_scope_policy::Requirement<'_>,&mut C)->Result<(),C::Error>)->Result<(),C::Error>{\n");
    for module in &full_metadata_modules {if matches!(module.as_str(),"lifeform_allows"|"escape_hatches"){continue}writeln!(full_metadata,"{}::visit_scopes(control,visit)?;",module).unwrap();}
    full_metadata.push_str("control.checkpoint()\n}\n");
    fs::write(out_dir.join("allow_registry_fields_gen.rs"),full_metadata).unwrap();

    let mut native_registry = String::from("{\n");
    for (module, _) in native_policy_roster::MODULES {
        let _ = writeln!(
            native_registry,
            "crate::lints::{}::register(&mut reg);",
            module
        );
    }
    native_registry.push_str("}\n");
    fs::write(
        out_dir.join("native_policy_registry_gen.rs"),
        native_registry,
    )
    .unwrap();
    let base = manifest.display().to_string().replace('\\', "/");
    for (sub, with_register, reg_ty) in [
        ("lints", true, "crate::lint::Registry"),
        ("gens", true, "Vec<Box<dyn crate::sem::gen::Generator>>"),
        ("codemods", true, "Vec<Box<dyn crate::codemod::Codemod>>"),
        ("dm", false, ""),
    ] {
        let dir = src.join(sub);
        let mods = if legacy {
            discover(&dir)
        } else {
            match sub {
                "lints" => native_policy_roster::MODULES
                    .iter()
                    .map(|(module, _)| (*module).to_string())
                    .chain([
                        "decl".to_string(),
                        "init".to_string(),
                        "requirement_bool".to_string(),
                        "check_grep".to_string(),
                    ])
                    .collect(),
                "dm" => vec![
                    "dx".to_string(),
                    "sys".to_string(),
                    "pylines".to_string(),
                    "walk".to_string(),
                    "deadline".to_string(),
                    "field_write".to_string(),
                    "ownership_index".to_string(),
                ],
                _ => continue,
            }
        };
        let mut gen = String::new();
        for m in &mods {
            let file = if dir.join(m).is_dir() {
                format!("{}/mod.rs", m)
            } else {
                format!("{}.rs", m)
            };
            let _ = writeln!(gen, "#[path = \"{}/src/{}/{}\"]", base, sub, file);
            let _ = writeln!(gen, "pub mod {};", m);
        }
        if with_register {
            let _ = writeln!(gen, "pub fn register(reg: &mut {}) {{", reg_ty);
            for m in &mods {
                // These two adapters retain their original legacy Lifeforms registration position.
                if legacy && sub == "lints" && matches!(m.as_str(), "lifeform_allows" | "escape_hatches") { continue; }
                let _ = writeln!(gen, "    {}::register(reg);", m);
            }
            let _ = writeln!(gen, "}}");
        }
        fs::write(out_dir.join(format!("{}_gen.rs", sub)), gen).unwrap();
    }

    // ---- engine hash ---------------------------------------------------------------------
    let repository = manifest
        .ancestors()
        .find(|p| p.join("AGENTS.md").is_file())
        .expect("analyzer repository root not found");
    let inputs = cargo_source_inputs::source_inputs(repository, &manifest.join("Cargo.toml"))
        .expect("cannot authenticate analyzer source dependency closure");
    let mut hasher = blake3_lite::Hasher::new();
    fn frame(hash: &mut blake3_lite::Hasher, bytes: &[u8]) {
        hash.update(&(bytes.len() as u64).to_le_bytes());
        hash.update(bytes);
    }
    frame(&mut hasher, b"analyze-engine-source-closure-v1");
    let mut features: Vec<_> = std::env::vars()
        .filter(|(key, _)| key.starts_with("CARGO_FEATURE_"))
        .collect();
    features.sort();
    for (key, value) in features {
        frame(&mut hasher, key.as_bytes());
        frame(&mut hasher, value.as_bytes());
    }
    // Source subtrees catch insertions without recursively watching target/.
    // Missing Cargo config/lock paths are deliberate correctness-first watches:
    // Cargo may rerun this script while they are absent; do not silently drop them.
    for missing in inputs.missing_paths {
        println!("cargo:rerun-if-changed={}", missing.display());
        frame(&mut hasher, b"absent");
        frame(
            &mut hasher,
            cargo_source_inputs::relative_path(repository, &missing)
                .expect("missing input outside repository")
                .as_bytes(),
        );
    }
    for dir in inputs.directories {
        println!("cargo:rerun-if-changed={}", dir.display());
    }
    for file in inputs.files {
        println!("cargo:rerun-if-changed={}", file.display());
        let relative = cargo_source_inputs::relative_path(repository, &file)
            .expect("source path left repository");
        frame(&mut hasher, relative.as_bytes());
        frame(
            &mut hasher,
            &fs::read(&file).expect("source input vanished during engine hashing"),
        );
    }
    println!("cargo:rustc-env=DQ_ENGINE_HASH={}", hasher.finish_hex());
}

/// A tiny FNV-1a/128-style hasher; this only needs to
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
