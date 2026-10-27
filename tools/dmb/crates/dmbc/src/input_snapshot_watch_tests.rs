//! Watched validation: entries in directories no watcher event named are carried without asking the provider.
use super::*;
use std::cell::Cell;

/// The live file system, counting what validation asks it.
struct Counting {
    stamps: Cell<usize>,
    listings: Cell<usize>,
}
impl SnapshotProvider for Counting {
    fn stamp(&self, path: &Path) -> io::Result<Stamp> {
        self.stamps.set(self.stamps.get() + 1);
        FileSystemInputs.stamp(path)
    }
    fn read(&self, path: &Path) -> io::Result<(Stamp, Vec<u8>)> {
        FileSystemInputs.read(path)
    }
    fn list(&self, path: &Path) -> io::Result<FolderListing> {
        self.listings.set(self.listings.get() + 1);
        FileSystemInputs.list(path)
    }
    fn digest(&self, path: &Path) -> io::Result<(Stamp, u128)> {
        FileSystemInputs.digest(path)
    }
    fn watch_token(&self) -> Option<crate::fs_watch::WatchToken> {
        FileSystemInputs.watch_token()
    }
}
impl Counting {
    fn asked(&self) -> usize {
        let asked = self.stamps.get() + self.listings.get();
        self.stamps.set(0);
        self.listings.set(0);
        asked
    }
}

fn record(snapshot: &mut InputSnapshot, path: &Path) {
    let (stamp, bytes) = FileSystemInputs.read(path).unwrap();
    snapshot.record_file(path, stamp, &bytes).unwrap();
}

#[test]
fn watched_validation_carries_unchanged_directories_and_proves_changed_ones() {
    crate::fs_watch::enable();
    let root = crate::test_scratch::dir("watched-validation");
    let quiet = root.join("icons");
    let busy = root.join("sound");
    std::fs::create_dir_all(&quiet).unwrap();
    std::fs::create_dir_all(&busy).unwrap();
    std::fs::write(quiet.join("a.dmi"), b"a").unwrap();
    std::fs::write(busy.join("b.ogg"), b"b").unwrap();
    crate::fs_watch::arm(&root);
    crate::fs_watch::sync(&root);
    assert!(crate::fs_watch::covered(&root), "the watcher did not arm");
    // Scan well after the files' write times so no entry is racy.
    let later = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_nanos()
        + 10_000_000_000;
    let mut snapshot = InputSnapshot::new(later);
    record(&mut snapshot, &quiet.join("a.dmi"));
    record(&mut snapshot, &busy.join("b.ogg"));
    snapshot.record_folder(&quiet, FileSystemInputs.list(&quiet).unwrap()).unwrap();
    snapshot.record_negative(&busy.join("absent.ogg")).unwrap();
    let provider = Counting { stamps: Cell::new(0), listings: Cell::new(0) };

    // First proof: everything is asked (two stamps, one listing, one negative probe); the snapshot is now marked.
    let (report, first) = snapshot.validate(&provider, false, later).unwrap();
    assert!(report.unchanged());
    assert_eq!(provider.asked(), 4);

    // Nothing changed since: nothing is asked, and the refreshed snapshot carries the mark too.
    crate::fs_watch::sync(&root);
    let (report, second) = snapshot.validate(&provider, false, later).unwrap();
    assert!(report.unchanged());
    assert_eq!(provider.asked(), 0);
    assert!(second.same_recorded_facts(&first));
    let (report, _) = second.validate(&provider, false, later).unwrap();
    assert!(report.unchanged());
    assert_eq!(provider.asked(), 0);

    // Exact mode assumes nothing about events either.
    let (report, _) = snapshot.validate(&provider, true, later).unwrap();
    assert!(report.unchanged());
    assert_eq!(provider.asked(), 4);

    // A write in one directory re-proves that directory only (its file and its negative probe).
    std::fs::write(busy.join("b.ogg"), b"changed").unwrap();
    crate::fs_watch::sync(&root);
    let (report, _) = snapshot.validate(&provider, false, later).unwrap();
    assert_eq!(report.changed, vec![canonical_path(&busy.join("b.ogg"))]);
    assert_eq!(provider.asked(), 2);
    // A failed proof leaves the old mark, so the change is found again.
    let (report, _) = snapshot.validate(&provider, false, later).unwrap();
    assert_eq!(report.changed.len(), 1);
    provider.asked();

    // A refreshed snapshot holds the new content; a file appearing where a negative was proven is a change.
    let (_, refreshed) = snapshot.validate(&provider, false, later).unwrap();
    provider.asked();
    let (report, _) = refreshed.validate(&provider, false, later).unwrap();
    assert!(report.unchanged());
    assert_eq!(provider.asked(), 0);
    std::fs::write(busy.join("absent.ogg"), b"now here").unwrap();
    crate::fs_watch::sync(&root);
    let (report, _) = refreshed.validate(&provider, false, later).unwrap();
    assert_eq!(report.changed, vec![canonical_path(&busy.join("absent.ogg"))]);

    // A new entry in a listed folder changes its listing.
    let (report, _) = refreshed.validate(&provider, false, later).unwrap();
    assert!(!report.unchanged());
    std::fs::remove_file(busy.join("absent.ogg")).unwrap();
    std::fs::write(quiet.join("new.dmi"), b"n").unwrap();
    crate::fs_watch::sync(&root);
    let (report, _) = refreshed.validate(&provider, false, later).unwrap();
    assert_eq!(report.changed, vec![canonical_path(&quiet)]);

    // A removed directory takes its subtree with it.
    std::fs::remove_file(quiet.join("new.dmi")).unwrap();
    crate::fs_watch::sync(&root);
    let (_, settled) = refreshed.validate(&provider, false, later).unwrap();
    let (report, _) = settled.validate(&provider, false, later).unwrap();
    assert!(report.unchanged());
    provider.asked();
    std::fs::remove_dir_all(&quiet).unwrap();
    crate::fs_watch::sync(&root);
    let (report, _) = settled.validate(&provider, false, later).unwrap();
    assert!(report.changed.contains(&canonical_path(&quiet.join("a.dmi"))));
    assert!(report.changed.contains(&canonical_path(&quiet)));
}

#[test]
fn a_snapshot_outside_every_watched_root_is_always_proven() {
    crate::fs_watch::enable();
    let root = crate::test_scratch::dir("unwatched-validation");
    std::fs::write(root.join("c.dmi"), b"c").unwrap();
    let later = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_nanos()
        + 10_000_000_000;
    let mut snapshot = InputSnapshot::new(later);
    record(&mut snapshot, &root.join("c.dmi"));
    let provider = Counting { stamps: Cell::new(0), listings: Cell::new(0) };
    for _ in 0..2 {
        let (report, _) = snapshot.validate(&provider, false, later).unwrap();
        assert!(report.unchanged());
        assert_eq!(provider.asked(), 1);
    }
}
