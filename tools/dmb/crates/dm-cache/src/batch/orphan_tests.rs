use super::*;
use std::time::Duration;

struct Directory(PathBuf);
impl Directory {
    fn new() -> Self {
        let stamp = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let path = PathBuf::from("E:/dq-cache/dmb-protocol-checks").join(format!(
            "orphan-spool-{}-{stamp}-{}",
            std::process::id(),
            NEXT.fetch_add(1, Ordering::Relaxed)
        ));
        std::fs::create_dir_all(&path).unwrap();
        Self(path)
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
fn bounds(entries: usize, reaped: usize) -> orphans::Bounds {
    orphans::Bounds {
        entries,
        reaped,
        time: Duration::from_secs(1),
    }
}

#[test]
fn live_writer_and_its_staging_survive_other_request_cleanup_then_finish() {
    let directory = Directory::new();
    let cache = directory.cache();
    let mut writer = cache.batch_spool().unwrap();
    writer
        .append(Record {
            key: RecordKey {
                stage: 2,
                version: 1,
                content: 9,
            },
            symbols: vec![],
            payload: std::sync::Arc::from(b"live payload".as_slice()),
        })
        .unwrap();
    let path = writer.path.clone();
    let staged = path.with_extension("segment.tmp");
    std::fs::write(&staged, b"in-flight staging").unwrap();
    assert_eq!(
        orphans::reap(path.parent().unwrap(), bounds(64, 8))
            .unwrap()
            .reaped,
        0
    );
    let other = cache.batch_spool().unwrap();
    assert!(path.exists());
    assert_eq!(std::fs::read(&staged).unwrap(), b"in-flight staging");
    drop(other);
    std::fs::remove_file(&staged).unwrap();
    assert!(writer.finish().unwrap().segment.is_some());
    assert!(!path.exists());
}

#[test]
fn published_root_leaves_cannot_starve_private_spool_cleanup() {
    let directory = Directory::new();
    let cache = directory.cache();
    for id in 0..80u128 {
        std::fs::write(
            directory.0.join(format!("{id:032x}.seg")),
            b"published sentinel",
        )
        .unwrap();
    }
    let private = orphans::prepare_root(&directory.0).unwrap();
    let orphan = private.join(".batch-v2-42-123-0.tmp");
    std::fs::write(&orphan, b"retired private payload").unwrap();
    let old_root_spool = directory.0.join(".batch-v2-42-122-0.tmp");
    std::fs::write(&old_root_spool, b"pre-child-layout preserved").unwrap();
    let writer = cache.batch_spool().unwrap();
    assert_eq!(writer.path.parent(), Some(private.as_path()));
    assert!(!orphan.exists());
    assert_eq!(
        std::fs::read(&old_root_spool).unwrap(),
        b"pre-child-layout preserved"
    );
    for id in 0..80u128 {
        assert_eq!(
            std::fs::read(directory.0.join(format!("{id:032x}.seg"))).unwrap(),
            b"published sentinel"
        );
    }
    drop(writer);
    assert_eq!(std::fs::read_dir(&private).unwrap().count(), 0);
}

#[test]
fn released_v2_writer_reaped_with_staging_but_legacy_and_segments_preserved() {
    let directory = Directory::new();
    let orphan = directory.0.join(".batch-v2-42-123-0.tmp");
    let file = OpenOptions::new()
        .read(true)
        .write(true)
        .create_new(true)
        .open(&orphan)
        .unwrap();
    FileExt::try_lock_exclusive(&file).unwrap();
    let staged = orphan.with_extension("segment.tmp");
    std::fs::write(&staged, b"abandoned segment payload").unwrap();
    let legacy = directory.0.join(".batch-42-123-0.tmp");
    let segment = directory.0.join("00000000000000000000000000000001.seg");
    let malformed = directory.0.join(".batch-v2-42-123-0-extra.tmp");
    let alias = directory.0.join(".batch-v2-042-123-0.tmp");
    for path in [&legacy, &segment, &malformed, &alias] {
        std::fs::write(path, b"preserve").unwrap();
    }
    // Models process termination releasing the OS lock; no PID-based permission.
    drop(file);
    assert_eq!(
        orphans::reap(&directory.0, bounds(64, 8)).unwrap().reaped,
        1
    );
    assert!(!orphan.exists());
    assert!(!staged.exists());
    for path in [&legacy, &segment, &malformed, &alias] {
        assert_eq!(std::fs::read(path).unwrap(), b"preserve");
    }
}

#[test]
fn cleanup_has_independent_scan_delete_and_time_bounds() {
    let directory = Directory::new();
    for index in 0..5 {
        std::fs::write(
            directory.0.join(format!(".batch-v2-42-123-{index}.tmp")),
            b"orphan",
        )
        .unwrap();
    }
    let none = orphans::reap(
        &directory.0,
        orphans::Bounds {
            entries: 64,
            reaped: 8,
            time: Duration::ZERO,
        },
    )
    .unwrap();
    assert_eq!((none.inspected, none.reaped), (0, 0));
    let one = orphans::reap(&directory.0, bounds(2, 1)).unwrap();
    assert!(one.inspected <= 2);
    assert_eq!(one.reaped, 1);
    assert_eq!(std::fs::read_dir(&directory.0).unwrap().count(), 4);
    let two = orphans::reap(&directory.0, bounds(2, 8)).unwrap();
    assert_eq!((two.inspected, two.reaped), (2, 2));
    assert_eq!(std::fs::read_dir(&directory.0).unwrap().count(), 2);
}

#[cfg(windows)]
#[test]
fn denied_staging_cleanup_retains_master_until_later_reap() {
    use std::os::windows::fs::OpenOptionsExt;
    let directory = Directory::new();
    let writer = directory.cache().batch_spool().unwrap();
    let master = writer.path.clone();
    let staged = master.with_extension("segment.tmp");
    std::fs::write(&staged, b"temporarily shared private staging").unwrap();
    // Deliberately omit FILE_SHARE_DELETE, as a transient Windows reader may.
    let reader = OpenOptions::new()
        .read(true)
        .share_mode(0x1 | 0x2)
        .open(&staged)
        .unwrap();
    let published = directory.0.join("00000000000000000000000000000001.seg");
    std::fs::write(&published, b"published evidence").unwrap();
    drop(writer);
    assert!(master.exists());
    assert!(staged.exists());
    assert_eq!(
        orphans::reap(master.parent().unwrap(), bounds(64, 8))
            .unwrap()
            .reaped,
        0
    );
    assert!(master.exists());
    drop(reader);
    assert_eq!(
        orphans::reap(master.parent().unwrap(), bounds(64, 8))
            .unwrap()
            .reaped,
        1
    );
    assert!(!master.exists());
    assert!(!staged.exists());
    assert_eq!(std::fs::read(&published).unwrap(), b"published evidence");
}
