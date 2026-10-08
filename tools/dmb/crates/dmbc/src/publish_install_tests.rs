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
    let installed = resource(&source, &destination, (6, xxh3_128(b"assets")));
    #[cfg(windows)]
    {
        // Windows atomic replacement rejects a read-only destination. Do not
        // clear its attribute: that would change the shared store hardlink.
        assert_eq!(
            installed.unwrap_err().kind(),
            io::ErrorKind::PermissionDenied
        );
        assert!(fs::metadata(&destination).unwrap().permissions().readonly());
        assert!(fs::metadata(&source).unwrap().permissions().readonly());
        assert_eq!(fs::read(&destination).unwrap(), b"assets");
        assert_eq!(fs::read(&source).unwrap(), b"assets");
    }
    #[cfg(not(windows))]
    {
        installed.unwrap();
        assert!(!fs::metadata(&destination).unwrap().permissions().readonly());
        fs::write(&destination, b"writes").unwrap();
        assert_eq!(fs::read(&source).unwrap(), b"assets");
        assert!(fs::metadata(&source).unwrap().permissions().readonly());
    }
}
