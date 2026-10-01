//! Small offline compiler gates. No DreamDaemon, full project or game assets.
use byond_dmb::{
    compare::{self, CompareOptions},
    dmb::Dmb,
};
use dm_compiler::{
    bootstrap,
    frontend::OutlineSession,
    incremental::{self, IncrementalSession},
};
use std::{
    path::PathBuf,
    sync::atomic::{AtomicU64, Ordering},
};

const BUILTINS: &[u8] = include_bytes!("../../../fixtures/native_template.bin");
static SEQUENCE: AtomicU64 = AtomicU64::new(0);

struct IsolatedProject(PathBuf);
impl IsolatedProject {
    fn new() -> Self {
        assert!(
            std::env::var_os("DM_COMPILER_CACHE_ROOT").is_none(),
            "unset DM_COMPILER_CACHE_ROOT so correctness fixtures cannot write a shared cache"
        );
        // Outside Git: all caches are disposable and cannot mutate another
        // worktree's Git-common cache. create_dir never adopts an existing tree.
        loop {
            let path = std::env::temp_dir().join(format!(
                "dm-correctness-{}-{}",
                std::process::id(),
                SEQUENCE.fetch_add(1, Ordering::Relaxed)
            ));
            match std::fs::create_dir(&path) {
                Ok(()) => return Self(path),
                Err(error) if error.kind() == std::io::ErrorKind::AlreadyExists => continue,
                Err(error) => panic!("isolated fixture: {error}"),
            }
        }
    }
    fn compile(&self, source: &str) -> bootstrap::CompiledProject {
        bootstrap::compile_preprocessed_project_with_resources_cached(
            &self.0.join("probe.dme"),
            &dm_preprocess::PreprocessedProject {
                text: source.into(),
                ..Default::default()
            },
            BUILTINS,
            "correctness-gate",
            &mut OutlineSession::new(None),
        )
        .unwrap()
    }
}

#[test]
fn canonical_cached_assembly_matches_empty_cache_across_edit_shapes() {
    let original = "/datum/parity\n    var/value = 3\n    var/static/shared = 7\n    var/asset = 'asset.txt'\n/datum/parity_other\n    var/value = 5\n    var/static/shared = 13\n/datum/parity/child\n    var/child_value = 9\n/datum/parity/proc/read()\n    return value + shared\n/datum/parity/child/proc/read_child()\n    return child_value\n/proc/edited(argument = 1)\n    return argument\n/proc/stable()\n    return 17\n/proc/builtin_user()\n    return abs(-2)\n/proc/read_subject(datum/parity/child/subject)\n    return subject.shared\n";
    let project = IsolatedProject::new();
    std::fs::write(project.0.join("asset.txt"), b"first asset").unwrap();
    let mut frontend = OutlineSession::new(Some(project.0.join("outline-cache")));
    let variants = [
        ("initial", original.to_owned(), b"first asset".as_slice()),
        ("upstream source shift", format!("// inserted upstream\n\n{original}"), b"first asset".as_slice()),
        ("internal source shift", original.replace("return argument", "// inserted internally\n    return argument"), b"first asset".as_slice()),
        (
            "body",
            original.replace("return argument", "return argument + 2"),
            b"first asset".as_slice(),
        ),
        (
            "new procedure",
            format!("{original}/proc/added()\n    return 29\n"),
            b"first asset".as_slice(),
        ),
        (
            "new variable",
            original.replace("var/value = 3", "var/value = 3\n    var/addition = 5"),
            b"first asset".as_slice(),
        ),
        (
            "variable type",
            original.replace("var/value = 3", "var/num/value = 3"),
            b"first asset".as_slice(),
        ),
        (
            "static override",
            format!("{original}/datum/parity/child/read()\n    var/static/local_shared = 11\n    return value + local_shared\n"),
            b"first asset".as_slice(),
        ),
        (
            "field becomes static",
            original.replace("var/value = 3", "var/static/value = 3"),
            b"first asset".as_slice(),
        ),
        (
            "negative static member resolution",
            original.replace("var/static/shared = 7", "var/shared = 7"),
            b"first asset".as_slice(),
        ),
        (
            "argument default",
            original.replace("argument = 1", "argument = 7"),
            b"first asset".as_slice(),
        ),
        (
            "inheritance",
            original.replace(
                "/datum/parity/child\n",
                "/datum/parity/child\n    parent_type = /datum/parity_other\n",
            ),
            b"first asset".as_slice(),
        ),
        (
            "delete",
            original.replace("/proc/stable()\n    return 17\n", ""),
            b"first asset".as_slice(),
        ),
        (
            "resource edit",
            original.to_owned(),
            b"second asset".as_slice(),
        ),
        ("revert", original.to_owned(), b"first asset".as_slice()),
    ];
    for (label, source, asset) in variants {
        std::fs::write(project.0.join("asset.txt"), asset).unwrap();
        let fresh_project = IsolatedProject::new();
        std::fs::write(fresh_project.0.join("asset.txt"), asset).unwrap();
        let compile = |project: &IsolatedProject, frontend: &mut OutlineSession| {
            bootstrap::compile_preprocessed_project_with_resources_prepared_mode(
                &project.0.join("probe.dme"),
                &dm_preprocess::PreprocessedProject {
                    text: source.clone(),
                    origins: source
                        .lines()
                        .enumerate()
                        .map(|(line, _)| dm_preprocess::Origin {
                            output_line: line + 1,
                            path: project.0.join("probe.dm").into(),
                            source_line: line + 1,
                        })
                        .collect(),
                    ..Default::default()
                },
                BUILTINS,
                "correctness-gate",
                frontend,
                &dm_compiler::maps::MapSet {
                    files: Vec::new(),
                    fingerprint: [0; 32],
                },
                &[dm_resources::ResourceRequest {
                    archive_name: "asset.txt".into(),
                    disk_path: project.0.join("asset.txt"),
                }],
                false,
            )
            .unwrap_or_else(|error| panic!("{label}: {error}"))
        };
        let incremental = compile(&project, &mut frontend);
        let fresh = compile(&fresh_project, &mut OutlineSession::new(None));
        assert!(incremental.checkpoint.is_none());
        if label == "upstream source shift" {
            assert!(incremental.lowering_cache_stats.hits > 0);
        }
        incremental.dmb.validate_references().unwrap();
        fresh.dmb.validate_references().unwrap();
        assert_eq!(
            incremental.dmb.to_bytes().unwrap(),
            fresh.dmb.to_bytes().unwrap(),
            "canonical DMB: {label}"
        );
        assert_eq!(
            incremental.rsc_bytes, fresh.rsc_bytes,
            "canonical RSC: {label}"
        );
        assert!(
            !incremental.rsc_bytes.is_empty(),
            "the resource gate must cover a real payload"
        );
    }
}
impl Drop for IsolatedProject {
    fn drop(&mut self) {
        if self.0.parent() == Some(std::env::temp_dir().as_path()) {
            let _ = std::fs::remove_dir_all(&self.0);
        }
    }
}

#[test]
fn fresh_compilation_has_deterministic_bytes() {
    let source = "/datum/parity\n    var/value = 3\n/proc/edited()\n    return 1\n/proc/stable()\n    return 17\n";
    let first = bootstrap::emit_global_procs(source, BUILTINS, "correctness-gate")
        .unwrap()
        .0;
    let second = bootstrap::emit_global_procs(source, BUILTINS, "correctness-gate")
        .unwrap()
        .0;
    first.validate_references().unwrap();
    second.validate_references().unwrap();
    assert_eq!(first.to_bytes().unwrap(), second.to_bytes().unwrap());
}

#[test]
fn body_edits_and_revert_match_fresh_semantic_output() {
    let original = "/datum/parity\n    var/value = 3\n/proc/edited()\n    return 1\n/proc/stable()\n    return 17\n";
    let project = IsolatedProject::new();
    let baseline = project.compile(original);
    let mut dmb = baseline.dmb;
    let mut checkpoint = baseline.checkpoint.unwrap();
    let stable = checkpoint.procedures["/proc/stable"].proc_id as usize;
    let original_stable = dmb.procs[stable].clone();
    let mut session = IncrementalSession::default();
    for source in [
        original.replace(
            "return 1\n",
            "var/value = \"new literal\"\n    return value\n",
        ),
        original.replace(
            "return 1\n",
            "var/list/values = list(2, 3)\n    return values[2]\n",
        ),
        original.to_owned(),
    ] {
        session.set_baseline_identity(incremental::digest(&dmb.to_bytes().unwrap()));
        let next = incremental::try_emit(&source, dmb, checkpoint, &mut session)
            .unwrap()
            .expect("ordinary body edit");
        assert_eq!(next.changed_procs, 1);
        assert_eq!(next.dmb.procs[stable], original_stable);
        let fresh = project.compile(&source);
        let options = CompareOptions {
            authored_prefixes: vec!["/proc/".into(), "/datum/parity".into()],
            max_discrepancies: 64,
            ..Default::default()
        };
        let discrepancies = compare::compare_dmbs(&fresh.dmb, &next.dmb, &options);
        assert!(
            discrepancies.is_empty(),
            "incremental/fresh: {discrepancies:#?}"
        );
        dmb = next.dmb;
        checkpoint = next.checkpoint;
    }
}

#[test]
fn numeric_region_lookup_matches_native_operand_semantics() {
    let source = include_str!("../../../fixtures/native_compiler/numeric_region_lookup/probe.dm");
    let native = Dmb::from_bytes(include_bytes!(
        "../../../fixtures/native_compiler/numeric_region_lookup/probe.native.bin"
    ))
    .unwrap();
    let actual = bootstrap::emit_global_procs(source, BUILTINS, "probe")
        .unwrap()
        .0;
    let options = CompareOptions {
        authored_prefixes: vec![
            "/proc/read_power_region".into(),
            "/proc/missing_numeric_region".into(),
        ],
        ..Default::default()
    };
    let left = compare::procedure_groups(&native, &options);
    let right = compare::procedure_groups(&actual, &options);
    assert_eq!(left.len(), 2);
    assert_eq!(right.len(), 2);
    for (path, expected) in left {
        let actual_ids = &right[&path];
        let differences = compare::compare_proc_code(
            &native,
            expected[0],
            &actual,
            actual_ids[0],
            &String::from_utf8_lossy(&path),
            64,
            true,
        );
        assert!(differences.is_empty(), "numeric lookup: {differences:#?}");
    }
    // This establishes compiler operand parity, not a successful runtime lookup
    // of absent numeric index 3 into an empty list.
}

#[test]
fn callee_parameter_metadata_matches_native() {
    let source = include_str!("../../../fixtures/native_compiler/callee_parameters/probe.dm");
    let native = Dmb::from_bytes(include_bytes!(
        "../../../fixtures/native_compiler/callee_parameters/probe.native.bin"
    ))
    .unwrap();
    let actual = bootstrap::emit_global_procs(source, BUILTINS, "probe")
        .unwrap()
        .0;
    let options = CompareOptions {
        authored_prefixes: vec!["/proc/metadata".into()],
        ..Default::default()
    };
    let differences = compare::compare_dmbs(&native, &actual, &options);
    assert!(
        differences.is_empty(),
        "callee parameter metadata/code: {differences:#?}"
    );
}

#[test]
fn builtin_callee_and_caller_selectors_match_native() {
    let source = include_str!("../../../fixtures/native_compiler/builtin_callee/probe.dm");
    let native = Dmb::from_bytes(include_bytes!(
        "../../../fixtures/native_compiler/builtin_callee/probe.native.bin"
    ))
    .unwrap();
    let actual = bootstrap::emit_global_procs(source, BUILTINS, "probe")
        .unwrap()
        .0;
    let options = CompareOptions {
        authored_prefixes: vec![
            "/proc/direct".into(),
            "/proc/caller_direct".into(),
            "/proc/caller_safe".into(),
            "/proc/shadowed".into(),
            "/proc/builtin_caller".into(),
            "/proc/parameter_shadow".into(),
            "/proc/caller_chain".into(),
        ],
        ..Default::default()
    };
    let differences = compare::compare_dmbs(&native, &actual, &options);
    assert!(
        differences.is_empty(),
        "callee/caller selectors: {differences:#?}"
    );
}
