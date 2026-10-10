use super::*;
use std::sync::Arc;
struct Directory(PathBuf);
impl Directory {
    fn new() -> Self {
        let stamp = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        Self(
            PathBuf::from("E:/dq-cache/dmb-protocol-checks").join(format!(
                "batch-{}-{stamp}-{}",
                std::process::id(),
                NEXT.fetch_add(1, Ordering::Relaxed)
            )),
        )
    }
    fn cache(&self) -> Cache {
        Cache::open(&self.0, crate::Limits::default()).unwrap()
    }
}
impl Drop for Directory {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.0);
    }
}
fn record(content: u128, payload: &[u8]) -> Record {
    Record {
        key: RecordKey {
            stage: 2,
            version: 1,
            content,
        },
        symbols: vec![],
        payload: Arc::from(payload),
    }
}
#[test]
fn streamed_segment_matches_existing_encoder_and_is_invisible_until_finish() {
    let directory = Directory::new();
    let cache = directory.cache();
    let values = vec![record(1, b"first"), record(2, &vec![7; 200_000])];
    let (expected_id, expected_bytes) =
        crate::segment::encode(&values, &[], crate::Limits::default()).unwrap();
    let mut spool = cache.batch_spool().unwrap();
    for value in values {
        spool.append(value).unwrap();
    }
    assert!(cache
        .snapshot()
        .unwrap()
        .get(
            RecordKey {
                stage: 2,
                version: 1,
                content: 1
            },
            |_, _| Ok(())
        )
        .is_none());
    let report = spool.finish().unwrap();
    assert_eq!(report.segment, Some(expected_id));
    assert_eq!(report.records, 2);
    assert_eq!(report.variants, 2);
    assert_eq!(
        std::fs::read(directory.0.join(format!("{expected_id:032x}.seg"))).unwrap(),
        expected_bytes
    );
}
#[test]
fn framed_same_key_candidates_survive_and_identical_variants_deduplicate() {
    let directory = Directory::new();
    let cache = directory.cache();
    let mut spool = cache.batch_spool().unwrap();
    for bytes in [b"a".as_slice(), b"b".as_slice(), b"a".as_slice()] {
        let payload = crate::encode_variants(&[bytes.to_vec()]).unwrap();
        spool.append(record(1, &payload)).unwrap();
    }
    let report = spool.finish().unwrap();
    assert_eq!(report.records, 1);
    assert_eq!(report.variants, 2);
    let snapshot = cache.snapshot().unwrap();
    let view = snapshot.get(record(1, b"").key, |_, _| Ok(())).unwrap();
    assert_eq!(
        crate::decode_variants(view.payload).unwrap(),
        [b"a".as_slice(), b"b".as_slice()]
    );
}
#[test]
fn cancellation_and_poisoned_append_publish_nothing_and_remove_private_files() {
    let directory = Directory::new();
    let cache = directory.cache();
    {
        let mut spool = cache.batch_spool().unwrap();
        spool.append(record(1, b"old")).unwrap();
    }
    assert_eq!(std::fs::read_dir(&directory.0).unwrap().count(), 0);
    let mut spool = cache.batch_spool().unwrap();
    spool.append(record(1, b"old")).unwrap();
    assert!(spool.append(record(1, b"different")).is_err());
    assert!(spool.finish().is_err());
    assert_eq!(std::fs::read_dir(&directory.0).unwrap().count(), 0);
    assert!(cache
        .batch_spool()
        .unwrap()
        .finish()
        .unwrap()
        .segment
        .is_none());
}
#[test]
fn symbol_conflicts_poison_batch_and_descriptor_visitor_borrows_real_backing() {
    let directory = Directory::new();
    let cache = directory.cache();
    let mut spool = cache.batch_spool().unwrap();
    let mut a = record(1, b"first");
    a.symbols.push(crate::SymbolText {
        id: 7,
        text: Arc::from(b"name".as_slice()),
    });
    spool.append(a).unwrap();
    let expected = spool.entries.values().next().unwrap().payloads.as_ptr() as usize;
    let mut seen = false;
    spool.visit_storage(|view| {
        if let BatchStorageView::Buffer {
            pointer,
            len_bytes,
            capacity_bytes,
        } = view
        {
            if pointer == expected {
                assert_eq!(len_bytes, std::mem::size_of::<Extent>());
                assert!(capacity_bytes >= len_bytes);
                seen = true;
            }
        }
    });
    assert!(seen);
    let mut b = record(2, b"second");
    b.symbols.push(crate::SymbolText {
        id: 7,
        text: Arc::from(b"wrong".as_slice()),
    });
    assert!(spool.append(b).is_err());
    assert!(spool.finish().is_err());
}

#[test]
fn finish_content_collision_preserves_destination_and_cleans_every_private_file() {
    let directory = Directory::new();
    let cache = directory.cache();
    let value = record(1, b"admitted payload");
    let (id, _) =
        crate::segment::encode(std::slice::from_ref(&value), &[], crate::Limits::default())
            .unwrap();
    let destination = directory.0.join(format!("{id:032x}.seg"));
    let incumbent = b"existing different content must never be replaced";
    std::fs::write(&destination, incumbent).unwrap();
    let mut spool = cache.batch_spool().unwrap();
    let private = spool.path.clone();
    let staged = private.with_extension("segment.tmp");
    spool.append(value).unwrap();
    assert!(private.exists());
    let error = spool.finish().unwrap_err();
    assert!(
        matches!(error, CacheError::Invalid(message) if message == "segment content identity collision")
    );
    assert_eq!(std::fs::read(&destination).unwrap(), incumbent);
    assert!(!private.exists());
    assert!(!staged.exists());
    let remaining: Vec<_> = std::fs::read_dir(&directory.0)
        .unwrap()
        .map(|entry| entry.unwrap().path())
        .collect();
    assert_eq!(remaining, vec![destination]);
}
