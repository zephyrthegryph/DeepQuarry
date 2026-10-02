#[allow(dead_code)]
#[path = "../fingerprints.rs"]
mod fingerprints;

#[test]
fn fingerprint_stage_roles_preserve_parser_cache_across_backend_changes() {
    let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../..");
    let inputs = fingerprints::inputs(&root);
    let has = |files: &[std::path::PathBuf], relative: &str| files.contains(&root.join(relative));
    assert!(has(&inputs.parse, "crates/dm-syntax/src/lib.rs"));
    assert!(has(&inputs.parse, "crates/dm-store/src/lib.rs"));
    assert!(has(
        &inputs.parse,
        "crates/dm-compiler/src/proc_parse_cache.rs"
    ));
    assert!(!has(&inputs.parse, "crates/dm-compiler/src/bootstrap.rs"));
    assert!(!has(&inputs.parse, "crates/dm-codegen-byond/src/simple.rs"));
    assert!(has(
        &inputs.lowering,
        "crates/dm-compiler/src/semantic_queries.rs"
    ));
    assert!(has(
        &inputs.lowering,
        "crates/dm-compiler/src/procedure_pipeline.rs"
    ));
    assert!(has(
        &inputs.lowering,
        "crates/dm-codegen-byond/src/simple.rs"
    ));
    assert!(has(&inputs.lowering, "src/opcodes.txt"));
    assert!(has(&inputs.lowering, "build.rs"));
    assert!(!has(&inputs.lowering, "crates/dm-compiler/src/frontend.rs"));
    assert!(has(&inputs.emission, "crates/dm-compiler/src/frontend.rs"));
    assert!(has(&inputs.emission, "crates/dm-compiler/src/maps.rs"));
    assert!(has(&inputs.emission, "Cargo.lock"));
}
