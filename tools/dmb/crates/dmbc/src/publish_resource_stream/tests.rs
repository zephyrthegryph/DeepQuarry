use super::*;
fn archive() -> byond_dmb::rsc::NamedResource {
    byond_dmb::rsc::NamedResource::from_data(
        6,
        b"a.png".to_vec(),
        b"exact resource bytes".to_vec(),
        13,
        19,
    )
    .unwrap()
}
fn resource_path(store: &PairStore, identity: ResourceIdentity) -> PathBuf {
    store
        .root
        .join("resources")
        .join(format!("{:032x}-{}.rsc", identity.hash, identity.bytes))
}
#[test]
fn streamed_resource_matches_memory_codec_and_immutable_reuse() {
    let store = super::super::tests::store();
    let entry = archive();
    let memory = byond_dmb::rsc::named_archive_encoded(&[&entry]).unwrap();
    let identity = store
        .publish_resource_views(&[entry.as_view()], false)
        .unwrap();
    assert_eq!(identity.bytes, memory.len() as u64);
    assert_eq!(identity.hash, memory.content_hash());
    let path = resource_path(&store, identity);
    assert_eq!(fs::read(&path).unwrap(), memory.bytes());
    assert!(fs::metadata(&path).unwrap().permissions().readonly());
    assert_eq!(
        store
            .publish_resource_views(&[entry.as_view()], true)
            .unwrap(),
        identity
    );
    assert_eq!(
        fs::read_dir(store.root.join("temporary")).unwrap().count(),
        0
    );
    let pair = store.publish_with_resource(1, b"dmb", identity).unwrap();
    let dmb = store.root.join("output.dmb");
    let rsc = store.root.join("output.rsc");
    store
        .install(pair.id, &dmb, &rsc, &store.root.join("output.json"))
        .unwrap();
    assert!(!fs::metadata(&rsc).unwrap().permissions().readonly());
    fs::write(&rsc, b"mutable compatibility").unwrap();
    assert_eq!(fs::read(&path).unwrap(), memory.bytes());
}
#[test]
fn existing_resource_tamper_rejects_stream_and_cleans_staging() {
    let store = super::super::tests::store();
    let entry = archive();
    let identity = store
        .publish_resource_views(&[entry.as_view()], false)
        .unwrap();
    let path = resource_path(&store, identity);
    eviction::unlink_immutable(&path).unwrap();
    fs::write(&path, vec![0; identity.bytes as usize]).unwrap();
    assert!(store
        .publish_resource_views(&[entry.as_view()], true)
        .is_err());
    assert_eq!(
        fs::read_dir(store.root.join("temporary")).unwrap().count(),
        0
    );
}
#[test]
fn codec_failure_and_injected_failures_leave_no_partial_archive() {
    let store = super::super::tests::store();
    let mut entry = archive();
    entry.name.push(0);
    assert!(store
        .publish_resource_views(&[entry.as_view()], false)
        .is_err());
    assert_eq!(
        fs::read_dir(store.root.join("temporary")).unwrap().count(),
        0
    );
    entry.name.pop();
    for point in ["resource_stream_written", "resource_stream_renamed"] {
        FAULT.with(|fault| *fault.borrow_mut() = Some((point, 1)));
        assert!(store
            .publish_resource_views(&[entry.as_view()], false)
            .is_err());
        assert_eq!(
            fs::read_dir(store.root.join("temporary")).unwrap().count(),
            0
        );
        assert_eq!(
            fs::read_dir(store.root.join("resources")).unwrap().count(),
            0
        );
    }
}

#[test]
fn shared_request_pins_protect_reused_orphans_until_last_drop() {
    use std::time::{Duration, SystemTime};
    let store = super::super::tests::store();
    let entry = archive();
    let (identity, first) = store
        .publish_resource_views_pinned(&[entry.as_view()], false)
        .unwrap();
    let (_, second) = store
        .publish_resource_views_pinned(&[entry.as_view()], true)
        .unwrap();
    let another = PairStore::open(&store.root).unwrap();
    let now = SystemTime::now() + Duration::from_secs(8 * 86400);
    let retention = Duration::from_secs(7 * 86400);
    assert_eq!(another.evict(now, retention).unwrap().resources, 0);
    drop(first);
    assert_eq!(another.evict(now, retention).unwrap().resources, 0);
    assert!(resource_path(&store, identity).exists());
    drop(second);
    assert_eq!(another.evict(now, retention).unwrap().resources, 1);
    assert!(!resource_path(&store, identity).exists());
}

#[test]
fn existing_archive_reuse_does_not_open_a_staged_writer() {
    let store = super::super::tests::store();
    let entry = archive();
    let identity = store
        .publish_resource_views(&[entry.as_view()], false)
        .unwrap();
    FAULT.with(|fault| *fault.borrow_mut() = Some(("resource_stream_writer_open", 1)));
    assert_eq!(
        store
            .publish_resource_views(&[entry.as_view()], true)
            .unwrap(),
        identity
    );
    FAULT.with(|fault| *fault.borrow_mut() = None);
    assert_eq!(
        fs::read_dir(store.root.join("temporary")).unwrap().count(),
        0
    );
}

#[test]
fn resource_only_admission_ignores_unrelated_pair_and_rejects_archive_tamper() {
    let store = super::super::tests::store();
    let entry = archive();
    let identity = store
        .publish_resource_views(&[entry.as_view()], false)
        .unwrap();
    let pair = store
        .publish_with_resource(1, b"old executable", identity)
        .unwrap();
    let old_dmb = store
        .root
        .join("pairs")
        .join(format!("{:032x}", pair.id))
        .join("deepquarry.dmb");
    // A previous executable is not part of resource-only authority.
    eviction::unlink_immutable(&old_dmb).unwrap();
    let pin = store.verify_resource_pinned(identity, true).unwrap();
    drop(pin);
    let path = resource_path(&store, identity);
    eviction::unlink_immutable(&path).unwrap();
    fs::write(&path, vec![0; identity.bytes as usize]).unwrap();
    assert!(store.verify_resource_pinned(identity, true).is_err());
}
