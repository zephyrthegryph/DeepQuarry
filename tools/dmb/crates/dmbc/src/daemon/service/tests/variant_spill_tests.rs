//! A variant's patch base survives the session that built it: stored before the host is released, restored at the next edit.
//!
//! Each test builds and edits through the stored-record path (`no_cache` off, as the daemon does), releases the session the way
//! the idle tiers do (store the patch base, then replace the host), and edits again. The edit after the release must be applied
//! as a patch against the restored base (not a whole-program compile) and equal a fresh compile of the same tree.
use super::*;

fn build(shared: &Arc<Shared>, roots: &Roots) -> (crate::publish::OutputPair, Vec<u8>, Vec<u8>) {
    let mut retained = request(roots, 0, false);
    retained.no_cache = false;
    let slot = shared.slot(retained.project.clone(), Some(&retained));
    let token = control::Cancellation::default();
    let _latest = LatestRequest::register(&slot, RequestKey::of(&retained, &retained.project), token.clone());
    let _binding = control::bind(token);
    let _serial = slot
        .lock_request_until(&admission_deadline::AdmissionDeadline::new(Instant::now()))
        .unwrap();
    let _permit = shared.acquire(1).unwrap();
    let mut host = slot.lock_host().unwrap();
    let destination = retained.artifact_directory.as_ref().unwrap().clone();
    published(crate::request_runner::run_build_with_host(retained, &mut host).unwrap(), &destination)
}

/// What the idle tiers do to a session that goes: store its patch bases, then drop everything else.
fn release_session(shared: &Arc<Shared>, roots: &Roots) {
    let mut retained = request(roots, 0, false);
    retained.no_cache = false;
    let slot = shared.slot(retained.project.clone(), Some(&retained));
    let mut host = slot.lock_host().unwrap();
    host.spill_patch_bases();
    shared.reset_host(&mut host);
}

fn fresh(roots: &Roots) -> (crate::publish::OutputPair, Vec<u8>, Vec<u8>) {
    let request = request(roots, 0, true);
    let destination = request.artifact_directory.as_ref().unwrap().clone();
    let _oracle = control::bind(control::Cancellation::default());
    published(crate::request_runner::run_build(request).unwrap(), &destination)
}

fn spill_files(roots: &Roots) -> Vec<PathBuf> {
    let directory = crate::variant_spill::directory(&roots.0.join("cache-0"));
    std::fs::read_dir(directory)
        .map(|entries| {
            entries
                .flatten()
                .map(|entry| entry.path())
                .filter(|path| path.extension().is_some_and(|extension| extension == "spill"))
                .collect()
        })
        .unwrap_or_default()
}

const TREE: &str = "/proc/anchor()\n    return 0\n/proc/first(a)\n    return a + 1\n/proc/second(a)\n    var/x = a * 2\n    return \"two\" + \"[x]\"\n/datum/holder\n    var/list/items = list(1, 2)\n    proc/count()\n        return items.len\n";

fn started() -> (Roots, Arc<Shared>) {
    let roots = Roots::new();
    let mut shared = shared();
    Arc::get_mut(&mut shared).unwrap().max_workers = 2;
    roots.edit(0, TREE);
    (roots, shared)
}

#[test]
fn an_edit_after_the_session_is_released_patches_the_restored_base() {
    let (roots, shared) = started();
    let applied = || crate::retained_output::applied_with_declaration_patches(&roots.manifest(0));
    let initial = build(&shared, &roots);
    let start = applied();
    roots.edit(0, &TREE.replace("return a + 1", "return a + 2"));
    let edited = build(&shared, &roots);
    assert_ne!(initial.0, edited.0, "the edit must publish a new image");
    assert_eq!(applied(), start + 1, "the edit before the release patches in memory");

    release_session(&shared, &roots);
    assert_eq!(spill_files(&roots).len(), 1, "the released session stored its patch base");

    let again = TREE.replace("return a + 1", "return a + 3");
    roots.edit(0, &again);
    let patched = build(&shared, &roots);
    assert_ne!(edited.0, patched.0, "the edit must publish a new image");
    assert_eq!(applied(), start + 2, "the edit after the release patches the restored base, not a whole-program compile");
    assert_equivalent_outputs(&patched, &fresh(&roots), "edit after a release vs a fresh compile");

    // The restored base keeps working: the next edit patches in memory, and the second release stores the new image.
    roots.edit(0, &TREE.replace("return a + 1", "return a + 4"));
    let next = build(&shared, &roots);
    assert_eq!(applied(), start + 3, "the edit after a restored patch patches in memory");
    release_session(&shared, &roots);
    roots.edit(0, &TREE.replace("return a + 1", "return a + 5"));
    let last = build(&shared, &roots);
    assert_eq!(applied(), start + 4, "a second release and restore patch too");
    assert_ne!(next.0, last.0);
    assert_equivalent_outputs(&last, &fresh(&roots), "edit after a second release vs a fresh compile");
}

#[test]
fn edits_that_move_lines_or_change_strings_patch_the_restored_base() {
    let (roots, shared) = started();
    let applied = || crate::retained_output::applied_with_declaration_patches(&roots.manifest(0));
    build(&shared, &roots);
    roots.edit(0, &TREE.replace("return a + 1", "return a + 2"));
    build(&shared, &roots);
    release_session(&shared, &roots);
    let start = applied();

    // A comment line added inside a body moves every later line (the line map), and a new literal needs the string
    // table's retained model, which is recovered from the restored image.
    let edited = TREE
        .replace("    var/x = a * 2\n", "    // a comment moves every later line\n    var/x = a * 2\n")
        .replace("\"two\"", "\"fresh literal\"");
    roots.edit(0, &edited);
    let patched = build(&shared, &roots);
    assert_eq!(applied(), start + 1, "moved lines and a new string patch the restored base");
    assert_equivalent_outputs(&patched, &fresh(&roots), "line and string edit after a release vs a fresh compile");
}

#[test]
fn a_declaration_edit_after_the_release_compiles_whole_and_is_correct() {
    let (roots, shared) = started();
    build(&shared, &roots);
    roots.edit(0, &TREE.replace("return a + 1", "return a + 2"));
    build(&shared, &roots);
    release_session(&shared, &roots);

    let edited = format!("{TREE}/datum/added\n    var/n = 3\n    proc/n2()\n        return n * 2\n");
    roots.edit(0, &edited);
    let built = build(&shared, &roots);
    assert_equivalent_outputs(&built, &fresh(&roots), "declaration edit after a release vs a fresh compile");
}

#[test]
fn a_damaged_or_foreign_spill_file_is_ignored() {
    let (roots, shared) = started();
    let applied = || crate::retained_output::applied_with_declaration_patches(&roots.manifest(0));
    build(&shared, &roots);
    roots.edit(0, &TREE.replace("return a + 1", "return a + 2"));
    build(&shared, &roots);
    release_session(&shared, &roots);
    let files = spill_files(&roots);
    assert_eq!(files.len(), 1);

    // One flipped byte in the image: the frame checks and the image digest refuse it, and the compile is whole and correct.
    let mut bytes = std::fs::read(&files[0]).unwrap();
    let last = bytes.len() - 100;
    bytes[last] ^= 0xff;
    std::fs::write(&files[0], &bytes).unwrap();
    let start = applied();
    roots.edit(0, &TREE.replace("return a + 1", "return a + 3"));
    let built = build(&shared, &roots);
    assert_eq!(applied(), start, "a damaged file never patches");
    assert_equivalent_outputs(&built, &fresh(&roots), "damaged spill vs a fresh compile");

    // Truncated and empty files are ignored the same way.
    release_session(&shared, &roots);
    for keep in [bytes.len() / 2, 0] {
        let files = spill_files(&roots);
        let whole = std::fs::read(&files[0]).unwrap();
        std::fs::write(&files[0], &whole[..keep.min(whole.len())]).unwrap();
        release_session(&shared, &roots);
        roots.edit(0, &TREE.replace("return a + 1", &format!("return a + {}", 10 + keep % 7)));
        let built = build(&shared, &roots);
        assert_equivalent_outputs(&built, &fresh(&roots), "truncated spill vs a fresh compile");
    }
}

#[test]
fn another_variants_file_is_not_this_variants_base() {
    let (roots, shared) = started();
    build(&shared, &roots);
    roots.edit(0, &TREE.replace("return a + 1", "return a + 2"));
    build(&shared, &roots);
    release_session(&shared, &roots);
    let files = spill_files(&roots);
    assert_eq!(files.len(), 1);
    let key = u128::from_str_radix(files[0].file_stem().unwrap().to_str().unwrap(), 16).unwrap();
    let directory = crate::variant_spill::directory(&roots.0.join("cache-0"));
    assert_eq!(crate::variant_spill::peek(&directory, key).map(|header| header.key), Some(key));
    // The same bytes under another variant's name are refused by the header's key.
    let other = key ^ 1;
    std::fs::copy(&files[0], directory.join(format!("{other:032x}.spill"))).unwrap();
    assert!(crate::variant_spill::peek(&directory, other).is_none());
    assert!(crate::variant_spill::read(&directory, other).is_err());
}

#[test]
fn a_retiring_daemon_and_the_idle_housekeeping_pass_store_the_base_before_they_drop_it() {
    let (roots, shared) = started();
    let applied = || crate::retained_output::applied_with_declaration_patches(&roots.manifest(0));
    build(&shared, &roots);
    roots.edit(0, &TREE.replace("return a + 1", "return a + 2"));
    build(&shared, &roots);
    // Retirement releases every idle session.
    assert!(shared.release_for_retire());
    assert_eq!(spill_files(&roots).len(), 1, "a retiring daemon stores its patch base");
    let start = applied();
    roots.edit(0, &TREE.replace("return a + 1", "return a + 3"));
    build(&shared, &roots);
    assert_eq!(applied(), start + 1, "the next daemon patches the stored base");

    // The idle pass: a session idle past the session limit is released whole (hard pressure, so the newest is not shielded).
    let mut retained = request(&roots, 0, false);
    retained.no_cache = false;
    let slot = shared.slot(retained.project.clone(), Some(&retained));
    *slot.last.lock().unwrap() = Instant::now() - Duration::from_secs(4000);
    drop(slot);
    std::fs::remove_dir_all(crate::variant_spill::directory(&roots.0.join("cache-0"))).unwrap();
    shared.housekeep(Instant::now(), true, true);
    assert_eq!(spill_files(&roots).len(), 1, "the idle pass stores the patch base of the session it releases");
}
