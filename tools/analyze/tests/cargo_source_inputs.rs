#[path = "../cargo_source_inputs.rs"]
mod cargo_source_inputs;
#[path = "../../dmb/shared/test_scratch.rs"]
mod test_scratch;
use std::{
    fs,
    path::{Path, PathBuf},
};
fn put(root: &Path, p: &str, text: &str) {
    let p = root.join(p);
    fs::create_dir_all(p.parent().unwrap()).unwrap();
    fs::write(p, text).unwrap();
}
fn fixture(label: &str) -> PathBuf {
    let root = test_scratch::dir(label);
    put(&root,"app/Cargo.toml","[package]\nname='app'\nversion='0.1.0'\n[dependencies]\nrenamed={path='../native/a',optional=true}\n[workspace]\n");
    put(&root, "app/src/lib.rs", "pub fn app() {}\n");
    put(&root, "app/Cargo.lock", "# lock\n");
    put(&root,"native/Cargo.toml","[workspace]\nmembers=['a','b']\n[workspace.dependencies]\nb={path='b'}\n[workspace.metadata.dq-source-key]\ninputs=['shared/helper.rs','fixtures/source.dm']\n");
    put(&root,"native/a/Cargo.toml","[package]\nname='a'\nversion='0.1.0'\n[target.'cfg(windows)'.build-dependencies]\nb={workspace=true}\n");
    put(&root, "native/a/src/lib.rs", "pub fn a() {}\n");
    put(
        &root,
        "native/b/Cargo.toml",
        "[package]\nname='b'\nversion='0.1.0'\n",
    );
    put(&root, "native/b/src/lib.rs", "pub fn b() {}\n");
    put(&root, "native/shared/helper.rs", "pub fn helper() {}\n");
    put(&root, "native/fixtures/source.dm", "/datum/probe\n");
    root
}
fn identity(root: &Path) -> Vec<(String, Vec<u8>)> {
    cargo_source_inputs::source_inputs(root, &root.join("app/Cargo.toml"))
        .unwrap()
        .files
        .into_iter()
        .map(|p| {
            (
                cargo_source_inputs::relative_path(root, &p).unwrap(),
                fs::read(p).unwrap(),
            )
        })
        .collect()
}
#[test]
fn transitive_workspace_target_source_and_insertions_change_identity() {
    let root = fixture("source-key-transitive");
    let old = identity(&root);
    put(&root, "native/b/src/lib.rs", "pub fn changed() {}\n");
    assert_ne!(old, identity(&root));
    let old = identity(&root);
    put(&root, "native/b/src/new_data.bin", "new data");
    assert_ne!(old, identity(&root));
    let old = identity(&root);
    put(
        &root,
        "native/shared/helper.rs",
        "pub fn changed_helper() {}\n",
    );
    assert_ne!(old, identity(&root));
    let inputs = cargo_source_inputs::source_inputs(&root, &root.join("app/Cargo.toml")).unwrap();
    assert!(inputs
        .directories
        .iter()
        .any(|p| p.ends_with("native/b/src")));
}
#[test]
fn missing_path_and_invalid_manifest_fail_closed() {
    let root = fixture("source-key-missing");
    fs::remove_file(root.join("native/b/Cargo.toml")).unwrap();
    assert!(cargo_source_inputs::source_inputs(&root, &root.join("app/Cargo.toml")).is_err());
    put(&root, "native/b/Cargo.toml", "[package\ninvalid");
    assert!(cargo_source_inputs::source_inputs(&root, &root.join("app/Cargo.toml")).is_err());
}
#[test]
fn paths_are_reproducible_and_build_outputs_are_excluded() {
    let a = fixture("source-key-root-a");
    let b = fixture("source-key-root-b");
    assert_eq!(identity(&a), identity(&b));
    put(&a, "native/b/target/release/output", "must not key");
    put(&a, "app/node_modules/cache/blob", "must not key");
    assert_eq!(identity(&a), identity(&b));
    assert!(identity(&a)
        .iter()
        .all(|(p, _)| !p.contains('\\') && !Path::new(p).is_absolute()));
}
#[test]
fn missing_declared_shared_input_and_missing_workspace_dependency_refuse() {
    let root = fixture("source-key-contract");
    fs::remove_file(root.join("native/shared/helper.rs")).unwrap();
    fs::remove_dir(root.join("native/shared")).unwrap();
    assert!(cargo_source_inputs::source_inputs(&root, &root.join("app/Cargo.toml")).is_err());
    put(&root, "native/shared/helper.rs", "// restored\n");
    put(
        &root,
        "native/a/Cargo.toml",
        "[package]\nname='a'\nversion='0.1.0'\n[dependencies]\nnot_defined={workspace=true}\n",
    );
    assert!(cargo_source_inputs::source_inputs(&root, &root.join("app/Cargo.toml")).is_err());
}

#[test]
fn root_insertions_new_config_and_source_module_named_target_are_inputs() {
    let root = fixture("source-key-root-insert");
    let inputs = cargo_source_inputs::source_inputs(&root, &root.join("app/Cargo.toml")).unwrap();
    assert!(inputs
        .missing_paths
        .iter()
        .any(|p| p.ends_with(".cargo/config.toml")));
    assert!(!inputs.directories.iter().any(|p| p.ends_with("native/b")));
    let before = identity(&root);
    put(&root, "native/b/root_source.rs", "pub fn added() {}\n");
    assert_ne!(before, identity(&root));
    let before = identity(&root);
    put(
        &root,
        ".cargo/config.toml",
        "[build]\nrustflags=['--cfg','source_key_probe']\n",
    );
    assert_ne!(before, identity(&root));
    let before = identity(&root);
    put(&root, "native/b/src/target/mod.rs", "pub fn source() {}\n");
    assert_ne!(before, identity(&root));
}
