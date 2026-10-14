use super::*;

#[test]
fn first_use_and_exact_pair_verification_reject_corruption() {
    let store = store();
    let pair = store.publish(1, b"program", b"assets").unwrap();
    assert_eq!(store.verify(pair.id, false).unwrap(), pair);
    assert_eq!(store.verify(pair.id, false).unwrap(), pair);
    let path = store
        .root
        .join("pairs")
        .join(pair.name())
        .join("deepquarry.dmb");
    let mut permissions = fs::metadata(&path).unwrap().permissions();
    #[cfg(windows)]
    #[expect(
        clippy::permissions_set_readonly_false,
        reason = "On Windows this clears only the read-only attribute; the Unix branch preserves mode bits."
    )]
    permissions.set_readonly(false);
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        permissions.set_mode(permissions.mode() | 0o200);
    }
    fs::set_permissions(&path, permissions).unwrap();
    let mut file = OpenOptions::new().write(true).open(&path).unwrap();
    use std::io::Write;
    file.write_all(b"damaged").unwrap();
    drop(file);
    assert!(store.verify(pair.id, true).is_err());
    let reopened = PairStore::open(&store.root).unwrap();
    assert!(reopened.verify(pair.id, false).is_err());
}

fn interrupted<T>(point: &'static str, ordinal: usize, run: impl FnOnce() -> io::Result<T>) {
    struct Clear;
    impl Drop for Clear {
        fn drop(&mut self) {
            FAULT.with(|fault| *fault.borrow_mut() = None);
        }
    }
    FAULT.with(|fault| *fault.borrow_mut() = Some((point, ordinal)));
    let _clear = Clear;
    let error = match run() {
        Ok(_) => panic!("fault boundary was not reached: {point}"),
        Err(error) => error,
    };
    assert!(
        error
            .to_string()
            .contains("injected publication interruption"),
        "{error}"
    );
}

fn assert_slot(store: &PairStore, pair: &OutputPair) {
    let slot = store.acquire(pair.id, store.root.join("slots")).unwrap();
    assert_eq!(validate_directory(&slot, pair.id).unwrap(), *pair);
    assert!(slot.join("slot-complete").exists());
}

#[test]
fn publication_fault_boundaries_preserve_authenticated_generations_and_release_lock() {
    for point in [
        "pair_dmb_written",
        "resource_written",
        "resource_renamed",
        "pair_manifest_written",
        "pair_directory_renamed",
        "session_staged",
        "pair_session_committed",
    ] {
        let store = store();
        let old = store.publish(1, b"old-code", b"old-assets").unwrap();
        let new = OutputPair::from_bytes(b"new-code", b"new-assets");
        interrupted(point, 1, || store.publish(1, b"new-code", b"new-assets"));
        assert_slot(&store, &old);
        let destination = store.root.join("pairs").join(new.name());
        if destination.exists() {
            assert_eq!(validate_directory(&destination, new.id).unwrap(), new);
        }
        assert_eq!(store.publish(1, b"new-code", b"new-assets").unwrap(), new);
        assert_slot(&store, &new);
    }
}

#[test]
fn acquisition_fault_boundaries_never_mark_partial_slots_complete() {
    for (point, ordinal) in [
        ("slot_copy_finished", 1),
        ("slot_copy_finished", 2),
        ("slot_manifest_written", 1),
        ("slot_complete_written", 1),
    ] {
        let store = store();
        let pair = store.publish(1, b"code", b"assets").unwrap();
        let slots = store.root.join("slots");
        interrupted(point, ordinal, || store.acquire(pair.id, &slots));
        for entry in fs::read_dir(&slots).unwrap() {
            let path = entry.unwrap().path();
            if path.join("slot-complete").exists() {
                assert_eq!(validate_directory(&path, pair.id).unwrap(), pair);
            }
        }
        assert_slot(&store, &pair);
    }
}

#[test]
fn conventional_fault_boundaries_keep_old_marker_and_repair_from_immutable_pair() {
    for (point, ordinal) in [
        ("install_copy_staged", 1),
        ("install_copy_staged", 2),
        ("install_rsc_replaced", 1),
        ("install_dmb_replaced", 1),
        ("install_marker_staged", 1),
    ] {
        let store = store();
        let root = store.root.join("worktree");
        let dmb = root.join("deepquarry.dmb");
        let rsc = root.join("deepquarry.rsc");
        let marker = root.join("deepquarry.pair");
        let old = store.publish(1, b"old-code", b"old-assets").unwrap();
        let new = store.publish(1, b"new-code", b"new-assets").unwrap();
        store.install(old.id, &dmb, &rsc, &marker).unwrap();
        interrupted(point, ordinal, || {
            store.install(new.id, &dmb, &rsc, &marker)
        });
        let marked: OutputPair = serde_json::from_slice(&fs::read(&marker).unwrap()).unwrap();
        assert_eq!(marked, old);
        let copies = OutputPair::from_bytes(&fs::read(&dmb).unwrap(), &fs::read(&rsc).unwrap());
        if copies != old {
            assert_ne!(
                marked, copies,
                "mixed compatibility copies must not authenticate"
            );
        }
        assert_slot(&store, &old);
        assert_slot(&store, &new);
        store.install(new.id, &dmb, &rsc, &marker).unwrap();
        let marked: OutputPair = serde_json::from_slice(&fs::read(&marker).unwrap()).unwrap();
        assert_eq!(marked, new);
        assert_eq!(
            OutputPair::from_bytes(&fs::read(&dmb).unwrap(), &fs::read(&rsc).unwrap()),
            new
        );
    }
}

#[cfg(windows)]
#[test]
fn output_store_is_shared_by_destination_drive() {
    let local = Path::new("C:/Users/demo/AppData/Local");
    assert_eq!(
        windows_store_path(Path::new("C:/work/a/project.dme"), local).unwrap(),
        local.join("dmbd/pairs")
    );
    let first = windows_store_path(Path::new("E:/work/a/project.dme"), local).unwrap();
    let second = windows_store_path(Path::new("E:/work/b/project.dme"), local).unwrap();
    assert_eq!(first, second);
    assert_eq!(first, Path::new("E:/").join(".dmbd/pairs"));
    assert!(windows_store_path(Path::new("//server/share/project.dme"), local).is_err());
}

pub(super) fn store() -> PairStore {
    let sequence = TEMP_SEQUENCE.fetch_add(1, Ordering::Relaxed);
    PairStore::open(
        std::env::temp_dir().join(format!("dmb-pair-test-{}-{sequence}", std::process::id())),
    )
    .unwrap()
}

#[test]
fn changing_dmb_reuses_resource_and_acquires_writable_copy() {
    let store = store();
    let first = store.publish(1, b"world-one", b"shared-resources").unwrap();
    let second = store.publish(1, b"world-two", b"shared-resources").unwrap();
    assert_ne!(first.id, second.id);
    assert_eq!(
        fs::read_dir(store.root.join("resources")).unwrap().count(),
        1
    );
    let slot = store.acquire(second.id, store.root.join("slots")).unwrap();
    assert_eq!(fs::read(slot.join("deepquarry.dmb")).unwrap(), b"world-two");
    assert_eq!(
        fs::read(slot.join("deepquarry.rsc")).unwrap(),
        b"shared-resources"
    );
    fs::write(slot.join("deepquarry.rsc"), b"runtime writes").unwrap();
    let pair = store.root.join("pairs").join(second.name());
    assert_eq!(validate_directory(&pair, second.id).unwrap(), second);
    assert!(slot.join("slot-complete").exists());
}

#[test]
fn archive_identity_composes_without_archive_input() {
    let store = store();
    let first = store.publish(1, b"first", b"assets").unwrap();
    let resource = ResourceIdentity {
        bytes: first.rsc_bytes,
        hash: first.rsc_hash,
    };
    let second = store.publish_with_resource(1, b"second", resource).unwrap();
    assert_eq!(second, OutputPair::from_bytes(b"second", b"assets"));
    assert_eq!(
        fs::read_dir(store.root.join("resources")).unwrap().count(),
        1
    );
    let slots = store.root.join("slots");
    let slot = store.acquire(second.id, slots).unwrap();
    assert_eq!(fs::read(slot.join("deepquarry.rsc")).unwrap(), b"assets");
    let missing = ResourceIdentity { hash: 0, bytes: 1 };
    let absent = OutputPair::from_hashes(4, xxh3_128(b"next"), 1, 0);
    assert!(store.publish_with_resource(1, b"next", missing).is_err());
    assert!(!store.root.join("pairs").join(absent.name()).exists());
}

#[test]
fn duplicate_publication_and_session_history_are_coherent() {
    let store = store();
    let mut expected = Vec::new();
    for byte in 0..5 {
        let pair = store.publish(7, &[byte], b"resource").unwrap();
        assert_eq!(store.publish(7, &[byte], b"resource").unwrap(), pair);
        expected.insert(0, pair.id);
    }
    expected.truncate(3);
    let actual: Vec<u128> = serde_json::from_slice(
        &fs::read(
            store
                .root
                .join("sessions/00000000000000000000000000000007.json"),
        )
        .unwrap(),
    )
    .unwrap();
    assert_eq!(actual, expected);
    assert_eq!(fs::read_dir(store.root.join("pairs")).unwrap().count(), 5);
}

#[test]
fn conventional_paths_replace_existing_copies_and_marker_last() {
    let store = store();
    let root = store.root.join("worktree");
    let dmb = root.join("deepquarry.dmb");
    let rsc = root.join("deepquarry.rsc");
    let marker = root.join("deepquarry.pair");
    let first = store.publish(3, b"first", b"assets-one").unwrap();
    store.install(first.id, &dmb, &rsc, &marker).unwrap();
    let second = store.publish(3, b"second", b"assets-two").unwrap();
    store.install(second.id, &dmb, &rsc, &marker).unwrap();
    assert_eq!(fs::read(&dmb).unwrap(), b"second");
    assert_eq!(fs::read(&rsc).unwrap(), b"assets-two");
    let actual: OutputPair = serde_json::from_slice(&fs::read(marker).unwrap()).unwrap();
    assert_eq!(actual, second);
}

#[test]
fn reused_resource_keeps_marker_last_across_interrupted_dmb_install() {
    let store = store();
    let root = store.root.join("worktree");
    let dmb = root.join("world.dmb");
    let rsc = root.join("world.rsc");
    let marker = root.join("world.pair");
    let old = store.publish(1, b"old-code", b"same-assets").unwrap();
    let new = store.publish(1, b"new-code", b"same-assets").unwrap();
    store.install(old.id, &dmb, &rsc, &marker).unwrap();
    interrupted("install_dmb_replaced", 1, || {
        store.install(new.id, &dmb, &rsc, &marker)
    });
    let marked: OutputPair = serde_json::from_slice(&fs::read(&marker).unwrap()).unwrap();
    assert_eq!(marked, old);
    assert_eq!(fs::read(&rsc).unwrap(), b"same-assets");
    store.install(new.id, &dmb, &rsc, &marker).unwrap();
    let marked: OutputPair = serde_json::from_slice(&fs::read(marker).unwrap()).unwrap();
    assert_eq!(marked, new);
}

#[test]
fn boot_receipt_reuses_across_stores_and_rejects_replaced_identity() {
    let store = store();
    let pair = store.publish(1, b"original", b"resource").unwrap();
    assert_eq!(store.verify(pair.id, false).unwrap(), pair);
    let next = PairStore::open(&store.root).unwrap();
    assert_eq!(next.verify(pair.id, false).unwrap(), pair);
    assert_eq!(next.verify(pair.id, true).unwrap(), pair);
    let path = store
        .root
        .join("pairs")
        .join(pair.name())
        .join("deepquarry.dmb");
    let replaced = path.with_extension("replacement");
    fs::write(&replaced, b"corrupt!").unwrap();
    fs::rename(&path, path.with_extension("old")).unwrap();
    fs::rename(&replaced, &path).unwrap();
    assert!(next.verify(pair.id, false).is_err());
    assert!(PairStore::open(&store.root)
        .unwrap()
        .verify(pair.id, false)
        .is_err());
}

#[test]
fn same_length_corruption_is_rejected_before_slot_exposure() {
    let store = store();
    let pair = store.publish(1, b"original", b"resource").unwrap();
    let path = store.root.join("pairs").join(pair.name()).join("pair.json");
    // Change an unlinked manifest by replacing its directory entry. Leave
    // immutable inode permissions unchanged, as real acquisition must do.
    let replacement = path.with_extension("replacement");
    let mut false_manifest = pair.clone();
    false_manifest.dmb_hash ^= 1;
    write_json(&replacement, &false_manifest).unwrap();
    fs::rename(&path, path.with_extension("original")).unwrap();
    fs::rename(replacement, path).unwrap();
    let slots = store.root.join("slots");
    assert!(store.acquire(pair.id, &slots).is_err());
    assert!(!slots.exists());
}

#[test]
fn failed_staging_removes_owned_paths_without_mutating_resource_links() {
    let store = store();
    let old = store.publish(1, b"old", b"shared-assets").unwrap();
    interrupted("pair_manifest_written", 1, || {
        store.publish(1, b"new", b"shared-assets")
    });
    assert_eq!(
        fs::read_dir(store.root.join("temporary")).unwrap().count(),
        0
    );
    assert_eq!(store.verify(old.id, true).unwrap(), old);
    let resource = store
        .root
        .join("resources")
        .join(format!("{:032x}-{}.rsc", old.rsc_hash, old.rsc_bytes));
    assert!(fs::metadata(resource).unwrap().permissions().readonly());
}

#[test]
fn resource_admission_rejects_replaced_inode_across_store_handles() {
    let store = store();
    let first = store.publish(1, b"first", b"assets").unwrap();
    let resource = store
        .root
        .join("resources")
        .join(format!("{:032x}-{}.rsc", first.rsc_hash, first.rsc_bytes));
    let replacement = resource.with_extension("replacement");
    fs::write(&replacement, b"edited").unwrap();
    fs::rename(&resource, resource.with_extension("old")).unwrap();
    fs::rename(&replacement, &resource).unwrap();
    let next = PairStore::open(&store.root).unwrap();
    assert!(next
        .publish_with_resource(
            1,
            b"next",
            ResourceIdentity {
                bytes: first.rsc_bytes,
                hash: first.rsc_hash
            }
        )
        .is_err());
    assert_eq!(
        fs::read_dir(store.root.join("temporary")).unwrap().count(),
        0
    );
    // The old pair retained the original immutable hardlink.
    assert_eq!(next.verify(first.id, true).unwrap(), first);
}

#[test]
fn exact_resource_publication_bypasses_current_boot_admission() {
    let store = store();
    let first = store.publish(1, b"first", b"assets").unwrap();
    let resource = ResourceIdentity {
        bytes: first.rsc_bytes,
        hash: first.rsc_hash,
    };
    // Cached resource admission is present, but exact publication must read it.
    interrupted("resource_authentication_read", 1, || {
        store.publish_with_resource_exact(1, b"exact", resource, true)
    });
    assert_eq!(
        fs::read_dir(store.root.join("temporary")).unwrap().count(),
        0
    );
    assert!(store.publish_with_resource(1, b"normal", resource).is_ok());
}

#[test]
fn certified_encoder_publication_matches_bytes_and_reuses_resource_identity() {
    let store = store();
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../fixtures/native_compiler/proc_namespace.native.bin"
    ))
    .unwrap();
    let image = native.encode().unwrap();
    let first = store
        .publish_encoded_exact(1, &image, b"assets", false)
        .unwrap();
    assert_eq!(first, OutputPair::from_bytes(image.bytes(), b"assets"));
    assert_eq!(first.dmb_hash, image.content_hash());
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../fixtures/native_compiler/proc_override_chain.native.bin"
    ))
    .unwrap();
    let changed = native.encode().unwrap();
    let second = store
        .publish_encoded_with_resource_exact(
            1,
            &changed,
            ResourceIdentity {
                bytes: first.rsc_bytes,
                hash: first.rsc_hash,
            },
            true,
        )
        .unwrap();
    assert_eq!(second, OutputPair::from_bytes(changed.bytes(), b"assets"));
    assert_eq!(
        fs::read_dir(store.root.join("resources")).unwrap().count(),
        1
    );
    assert_eq!(store.verify(second.id, true).unwrap(), second);
}

#[test]
fn both_certified_images_publish_without_detaching_their_hashes() {
    let store = store();
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../fixtures/native_compiler/proc_namespace.native.bin"
    ))
    .unwrap();
    let image = native.encode().unwrap();
    let entry =
        byond_dmb::rsc::NamedResource::from_data(0, b"a.txt".to_vec(), b"assets".to_vec(), 0, 0)
            .unwrap();
    let archive = byond_dmb::rsc::named_archive_encoded(&[&entry]).unwrap();
    let pair = store
        .publish_images_exact(1, &image, &archive, true)
        .unwrap();
    assert_eq!(pair, OutputPair::from_bytes(image.bytes(), archive.bytes()));
    assert_eq!(store.verify(pair.id, true).unwrap(), pair);
}
