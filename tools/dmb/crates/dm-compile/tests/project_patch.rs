//! Exercise persisted incremental patching through separate CLI processes.
use byond_dmb::dmb::Dmb;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::{Command, Output};
use std::sync::atomic::{AtomicU64, Ordering};

fn invoke(root: &Path, args: &[&str]) -> Output {
    Command::new(env!("CARGO_BIN_EXE_dm-compile"))
        .current_dir(root)
        .args(args)
        .output()
        .unwrap()
}
fn successful(output: Output) -> String {
    assert!(
        output.status.success(),
        "stdout={} stderr={}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    String::from_utf8(output.stdout).unwrap()
}
fn proc_id(dmb: &Dmb, path: &[u8]) -> usize {
    dmb.procs
        .iter()
        .position(|proc_| dmb.string(proc_.strings[0]) == Some(path))
        .unwrap()
}

#[test]
fn cold_cli_patches_reuse_disk_cache_and_lower_only_changed_body() {
    static SEQUENCE: AtomicU64 = AtomicU64::new(0);
    let parent = std::env::temp_dir();
    let root = parent.join(format!(
        "dm-cli-patch-{}-{}",
        std::process::id(),
        SEQUENCE.fetch_add(1, Ordering::Relaxed)
    ));
    fs::create_dir_all(&root).unwrap();
    fs::write(root.join("probe.dme"), "#include \"code.dm\"\n").unwrap();
    let source = "#ifdef CLI_CACHE_TEST\n/proc/changed()\n    return 7\n#endif\n/proc/unchanged()\n    return 9\n";
    fs::write(root.join("code.dm"), source).unwrap();
    fs::write(
        root.join("builtins.dmb"),
        include_bytes!("../../../fixtures/native_template.bin"),
    )
    .unwrap();
    let first = successful(invoke(
        &root,
        &[
            "build-project",
            "probe.dme",
            "builtins.dmb",
            "output",
            "-DCLI_CACHE_TEST",
        ],
    ));
    assert!(first.contains("2 lowered, 0 reused"), "{first}");
    let generation: PathBuf = fs::read_dir(root.join("output/generations"))
        .unwrap()
        .next()
        .unwrap()
        .unwrap()
        .path();
    fs::copy(generation.join("world.dmb"), root.join("live.dmb")).unwrap();
    fs::copy(generation.join("world.rsc"), root.join("live.rsc")).unwrap();
    let old_bytes = fs::read(root.join("live.dmb")).unwrap();
    let old = Dmb::from_bytes(&old_bytes).unwrap();
    let old_changed = old
        .proc_code_words(proc_id(&old, b"/proc/changed"))
        .unwrap()
        .to_vec();
    let old_unchanged = old
        .proc_code_words(proc_id(&old, b"/proc/unchanged"))
        .unwrap()
        .to_vec();
    let args = [
        "build-project-patch",
        "probe.dme",
        "builtins.dmb",
        "live.dmb",
        "live.rsc",
        "--exclusive",
        "-DCLI_CACHE_TEST",
    ];
    for _ in 0..2 {
        let report = successful(invoke(&root, &args));
        assert!(
            report.contains("output cache hit, 0 lowered, 2 reused"),
            "{report}"
        );
        assert_eq!(fs::read(root.join("live.dmb")).unwrap(), old_bytes);
    }
    fs::write(root.join("code.dm"), source.replace("return 7", "return 8")).unwrap();
    let changed = successful(invoke(&root, &args));
    assert!(changed.contains("1 lowered, 1 reused"), "{changed}");
    let updated_bytes = fs::read(root.join("live.dmb")).unwrap();
    assert_eq!(
        updated_bytes.len(),
        old_bytes.len(),
        "constant-only edit preserves layout"
    );
    let updated = Dmb::from_bytes(&updated_bytes).unwrap();
    updated.validate_references().unwrap();
    assert_ne!(
        updated
            .proc_code_words(proc_id(&updated, b"/proc/changed"))
            .unwrap(),
        old_changed
    );
    assert_eq!(
        updated
            .proc_code_words(proc_id(&updated, b"/proc/unchanged"))
            .unwrap(),
        old_unchanged
    );
    assert!(!root.join("live.dmb.undo-journal").exists());
    let denied = invoke(
        &root,
        &[
            "build-project-patch",
            "probe.dme",
            "builtins.dmb",
            "live.dmb",
            "live.rsc",
        ],
    );
    assert!(!denied.status.success());
    assert_eq!(fs::read(root.join("live.dmb")).unwrap(), updated_bytes);
    let repeat = successful(invoke(&root, &args));
    assert!(
        repeat.contains("output cache hit, 0 lowered, 2 reused"),
        "{repeat}"
    );
    assert_eq!(root.parent(), Some(parent.as_path()));
    fs::remove_dir_all(root).unwrap();
}
