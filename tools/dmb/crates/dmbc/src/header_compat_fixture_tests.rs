//! Each probe under `fixtures/native_compiler/header_compat/` was compiled by DreamMaker 516.1687; its
//! `.native.bin` is the output. The native compiler must print the same `min compatibility` line.
use crate::request::{BuildOutcome, BuildRequest, Command};
use std::path::{Path, PathBuf};

fn fixture_root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../fixtures/native_compiler/header_compat")
}

fn scratch() -> PathBuf {
    let parent = if cfg!(windows) {
        PathBuf::from("E:/dq-cache/dmb-protocol-checks")
    } else {
        std::env::temp_dir()
    };
    let stamp = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    let root = parent.join(format!("header-compat-{}-{stamp}", std::process::id()));
    std::fs::create_dir_all(&root).unwrap();
    root
}

fn request(root: &Path, manifest: &Path) -> BuildRequest {
    let args = vec!["compile".into(), manifest.to_string_lossy().into_owned()];
    let Command::Build(request) = crate::cli::parse(&args).unwrap() else {
        panic!("compile request expected")
    };
    let mut request = *request;
    request.workers = 1;
    request.engine_template = Some(
        PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../fixtures/native_template.bin"),
    );
    request.bootstrap_catalog = true;
    request.progress_enabled = false;
    request.no_cache = true;
    request.exact_inputs = true;
    request.cache_root = Some(root.join("cache"));
    request.output_store = Some(root.join("store"));
    request.artifact_directory = Some(root.join("output"));
    request
}

fn compat_line(bytes: &[u8]) -> String {
    let dmb = byond_dmb::dmb::Dmb::from_bytes(bytes).unwrap();
    String::from_utf8(dmb.header.compatibility_line).unwrap()
}

fn native_line(name: &str) -> String {
    let root = scratch();
    let project = root.join("project");
    std::fs::create_dir_all(&project).unwrap();
    for extension in ["dm", "dme"] {
        std::fs::copy(
            fixture_root().join(format!("{name}.{extension}")),
            project.join(format!("{name}.{extension}")),
        )
        .unwrap();
    }
    let manifest = std::fs::canonicalize(project.join(format!("{name}.dme"))).unwrap();
    let outcome = crate::request_runner::run_build(request(&root, &manifest)).unwrap();
    let BuildOutcome::Published { output_project, .. } = outcome else {
        panic!("{name}: executable publication expected")
    };
    let line = compat_line(&std::fs::read(output_project.with_extension("dmb")).unwrap());
    let _ = std::fs::remove_dir_all(&root);
    line
}

#[test]
fn native_header_line_matches_dreammaker_for_each_probe() {
    let mut failures = Vec::new();
    let mut checked = 0;
    for entry in std::fs::read_dir(fixture_root()).unwrap() {
        let path = entry.unwrap().path();
        let Some(name) = path
            .file_name()
            .and_then(|n| n.to_str())
            .and_then(|n| n.strip_suffix(".native.bin"))
        else {
            continue;
        };
        let expected = compat_line(&std::fs::read(&path).unwrap());
        let actual = native_line(name);
        checked += 1;
        if actual != expected {
            failures.push(format!("{name}: native {actual:?}, DreamMaker {expected:?}"));
        }
    }
    assert!(checked >= 8, "probe set shrank to {checked}");
    assert!(failures.is_empty(), "{}", failures.join("\n"));
}

/// `world.name` defaults to the project file stem (DreamMaker 516.1687, `fixtures/native_compiler/world_name`).
#[test]
fn world_name_defaults_to_the_project_name() {
    let root = scratch();
    let project = root.join("project");
    std::fs::create_dir_all(&project).unwrap();
    let dir = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../fixtures/native_compiler/world_name");
    for extension in ["dm", "dme"] {
        std::fs::copy(
            dir.join(format!("world_name_probe.{extension}")),
            project.join(format!("world_name_probe.{extension}")),
        )
        .unwrap();
    }
    let manifest = std::fs::canonicalize(project.join("world_name_probe.dme")).unwrap();
    let outcome = crate::request_runner::run_build(request(&root, &manifest)).unwrap();
    let BuildOutcome::Published { output_project, .. } = outcome else {
        panic!("executable publication expected")
    };
    let native = byond_dmb::dmb::Dmb::from_bytes(&std::fs::read(output_project.with_extension("dmb")).unwrap()).unwrap();
    let reference = byond_dmb::dmb::Dmb::from_bytes(&std::fs::read(dir.join("world_name_probe.native.bin")).unwrap()).unwrap();
    let _ = std::fs::remove_dir_all(&root);
    assert_eq!(native.string(native.world.ids[6]), Some(b"world_name_probe".as_slice()));
    assert_eq!(native.string(native.world.ids[6]), reference.string(reference.world.ids[6]));
}

/// Source subclasses of /image get a null name and text, and an authored `icon_state = ""` is null, while an authored
/// `name = ""` stays empty (DreamMaker 516.1687, `fixtures/native_compiler/null_defaults`).
#[test]
fn null_and_empty_text_defaults_match_dreammaker() {
    let root = scratch();
    let project = root.join("project");
    std::fs::create_dir_all(&project).unwrap();
    let dir = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../fixtures/native_compiler/null_defaults");
    for extension in ["dm", "dme"] {
        std::fs::copy(
            dir.join(format!("null_defaults_probe.{extension}")),
            project.join(format!("null_defaults_probe.{extension}")),
        )
        .unwrap();
    }
    let manifest = std::fs::canonicalize(project.join("null_defaults_probe.dme")).unwrap();
    let outcome = crate::request_runner::run_build(request(&root, &manifest)).unwrap();
    let BuildOutcome::Published { output_project, .. } = outcome else {
        panic!("executable publication expected")
    };
    let native = std::fs::read(output_project.with_extension("dmb")).unwrap();
    let reference = std::fs::read(dir.join("null_defaults_probe.native.bin")).unwrap();
    let _ = std::fs::remove_dir_all(&root);
    let report = dmb_equiv::compare_bytes(
        &reference,
        None,
        &native,
        None,
        &dmb_equiv::Options {
            ignore_debug: true,
            ..Default::default()
        },
    )
    .unwrap();
    assert!(report.equivalent(), "{}", report.render_text());
}
