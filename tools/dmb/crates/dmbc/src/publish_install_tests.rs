use super::*;

#[test]
fn equal_resource_is_authenticated_without_opening_replacement_source() {
    let store = super::super::tests::store();
    let destination = store.root.join("same.rsc");
    fs::write(&destination, b"assets").unwrap();
    let expected = (6, xxh3_128(b"assets"));
    // Missing source proves the equal destination takes no staged copy path.
    resource(&store.root.join("absent.rsc"), &destination, expected).unwrap();
    assert_eq!(file_identity(&destination).unwrap(), expected);
    fs::write(&destination, b"edited").unwrap();
    assert!(resource(&store.root.join("absent.rsc"), &destination, expected).is_err());
}

#[test]
fn missing_and_same_length_corrupt_resource_are_repaired() {
    let store = super::super::tests::store();
    let source = store.root.join("source.rsc");
    let destination = store.root.join("output.rsc");
    fs::write(&source, b"assets").unwrap();
    let expected = (6, xxh3_128(b"assets"));
    resource(&source, &destination, expected).unwrap();
    fs::write(&destination, b"edited").unwrap();
    resource(&source, &destination, expected).unwrap();
    assert_eq!(file_identity(&destination).unwrap(), expected);
    fs::write(&destination, b"writes").unwrap();
    assert_eq!(fs::read(&source).unwrap(), b"assets");
}

#[test]
fn readonly_store_link_is_never_made_writable_in_place() {
    let store = super::super::tests::store();
    let source = store.root.join("immutable.rsc");
    let destination = store.root.join("linked.rsc");
    fs::write(&source, b"assets").unwrap();
    let mut permissions = fs::metadata(&source).unwrap().permissions();
    permissions.set_readonly(true);
    fs::set_permissions(&source, permissions).unwrap();
    fs::hard_link(&source, &destination).unwrap();
    // A read-only destination (a link to the sealed store file) is replaced by name; its attribute is never cleared, because the
    // store file shares it.
    resource(&source, &destination, (6, xxh3_128(b"assets"))).unwrap();
    assert!(!fs::metadata(&destination).unwrap().permissions().readonly());
    fs::write(&destination, b"writes").unwrap();
    assert_eq!(fs::read(&source).unwrap(), b"assets");
    assert!(fs::metadata(&source).unwrap().permissions().readonly());
}

#[test]
fn equal_program_reuses_existing_file_and_tamper_requires_replacement() {
    let store = super::super::tests::store();
    let destination = store.root.join("same.dmb");
    fs::write(&destination, b"program").unwrap();
    let expected = (7, xxh3_128(b"program"));
    let absent = store.root.join("absent.dmb");
    conventional_receipt(&absent, &destination, expected).unwrap();
    fs::write(&destination, b"damaged").unwrap();
    assert!(conventional_receipt(&absent, &destination, expected).is_err());
}

#[test]
fn repeated_pair_install_preserves_program_inode_and_repairs_same_size_tamper() {
    use crate::input_snapshot::{FileSystemInputs, SnapshotProvider};
    let store = super::super::tests::store();
    let pair = store.publish(1, b"program", b"assets").unwrap();
    let dmb = store.root.join("output.dmb");
    let rsc = store.root.join("output.rsc");
    let marker = store.root.join("output.json");
    store
        .install_exact(pair.id, &dmb, &rsc, &marker, false)
        .unwrap();
    let before = FileSystemInputs.stamp(&dmb).unwrap();
    store
        .install_exact(pair.id, &dmb, &rsc, &marker, true)
        .unwrap();
    assert_eq!(FileSystemInputs.stamp(&dmb).unwrap(), before);
    fs::write(&dmb, b"damaged").unwrap();
    store
        .install_exact(pair.id, &dmb, &rsc, &marker, false)
        .unwrap();
    assert_eq!(fs::read(&dmb).unwrap(), b"program");
    fs::write(&dmb, b"mutable").unwrap();
    assert_eq!(
        fs::read(
            store
                .root
                .join("pairs")
                .join(pair.name())
                .join("deepquarry.dmb")
        )
        .unwrap(),
        b"program"
    );
}

#[test]
fn resource_install_failure_precedes_program_and_marker_replacement() {
    let store = super::super::tests::store();
    let pair = store.publish(1, b"program", b"assets").unwrap();
    let dmb = store.root.join("output.dmb");
    let rsc = store.root.join("output.rsc");
    let marker = store.root.join("output.json");
    fs::write(&dmb, b"old program").unwrap();
    fs::write(&marker, b"old marker").unwrap();
    FAULT.with(|fault| *fault.borrow_mut() = Some(("install_rsc_replaced", 1)));
    let result = store.install_exact(pair.id, &dmb, &rsc, &marker, false);
    FAULT.with(|fault| *fault.borrow_mut() = None);
    assert!(result
        .unwrap_err()
        .to_string()
        .contains("install_rsc_replaced"));
    assert_eq!(fs::read(&rsc).unwrap(), b"assets");
    assert_eq!(fs::read(&dmb).unwrap(), b"old program");
    assert_eq!(fs::read(&marker).unwrap(), b"old marker");
}

#[test]
fn compile_root_outputs_are_links_to_the_store_and_relink_on_change() {
    use crate::input_snapshot::{FileSystemInputs, SnapshotProvider};
    let store = super::super::tests::store();
    let root = store.root.join("compile-root");
    fs::create_dir_all(&root).unwrap();
    fs::write(root.join(LINK_MARKER), b"").unwrap();
    let dmb = root.join("output.dmb");
    let rsc = root.join("output.rsc");
    let marker = root.join("output.json");
    let first = store.publish(1, b"program", b"assets").unwrap();
    store
        .install_exact(first.id, &dmb, &rsc, &marker, false)
        .unwrap();
    let stored = store.root.join("pairs").join(first.name());
    assert!(same_file(&stored.join("deepquarry.dmb"), &dmb));
    assert!(same_file(&stored.join("deepquarry.rsc"), &rsc));
    let before = FileSystemInputs.stamp(&dmb).unwrap();
    store
        .install_exact(first.id, &dmb, &rsc, &marker, true)
        .unwrap();
    assert_eq!(FileSystemInputs.stamp(&dmb).unwrap(), before);
    // A different program replaces the read-only link without touching the first pair's store file.
    let second = store.publish(1, b"program-2", b"assets").unwrap();
    store
        .install_exact(second.id, &dmb, &rsc, &marker, false)
        .unwrap();
    assert_eq!(fs::read(&dmb).unwrap(), b"program-2");
    assert_eq!(fs::read(stored.join("deepquarry.dmb")).unwrap(), b"program");
    assert!(same_file(
        &store.root.join("pairs").join(second.name()).join("deepquarry.dmb"),
        &dmb
    ));
    assert!(same_file(&stored.join("deepquarry.rsc"), &rsc));
    // Without the marker a destination is an independent writable copy again.
    fs::remove_file(root.join(LINK_MARKER)).unwrap();
    store
        .install_exact(first.id, &dmb, &rsc, &marker, false)
        .unwrap();
    assert!(!same_file(&stored.join("deepquarry.dmb"), &dmb));
    assert_eq!(fs::read(&dmb).unwrap(), b"program");
}
