use super::*;
#[test]
fn shared_batch_keys_prune_exact_roster_without_copying_key_descriptors() {
    let keys: Arc<[Arc<[u8]>]> = Arc::from([Arc::from(b"unit".as_slice())]);
    let recipe = Arc::new(Recipe {
        rows: Arc::from([]),
        units: Arc::from([]),
        binding: Mutex::new(None),
        keys: Arc::clone(&keys),
    });
    let escaped = Arc::clone(&recipe);
    assert!(Arc::ptr_eq(&keys, &escaped.keys));
    let store = AbiArtifacts::default();
    for key in [KEY, b"unit".as_slice(), b"obsolete".as_slice()] {
        store.store.insert_with_receipt(
            Arc::from(key),
            Receipt::from(Vec::new()),
            Arc::from([]),
            0,
            || Artifact::Batch(Arc::clone(&recipe)),
        );
    }
    store.prune_keys(recipe.retained_keys());
    let mut retained = Vec::new();
    store.store.visit_storage(|view| {
        if let dm_session::ObservedArtifactStorageView::Entry { key, .. } = view {
            retained.push(key.to_vec());
        }
    });
    retained.sort();
    let mut expected = vec![KEY.to_vec(), b"unit".to_vec()];
    expected.sort();
    assert_eq!(retained, expected);
    assert!(Arc::ptr_eq(&keys, &recipe.keys));
    drop(store);
    drop(recipe);
    assert_eq!(
        escaped.retained_keys().collect::<Vec<_>>(),
        vec![b"unit".as_slice(), KEY]
    );
}
