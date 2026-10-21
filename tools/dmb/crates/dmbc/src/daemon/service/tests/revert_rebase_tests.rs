//! Edit, revert, edit through the stored-record path (`no_cache` off).
//!
//! A revert is answered from a stored record when its inputs match an earlier build. The session's patch base used to stay on
//! the edited build, so the next edit was compared with the wrong image and fell off the patch path (full compile). The revert
//! must now be applied as a patch (so the base moves to the reverted image) and the edit after it must patch too.
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

#[test]
fn a_revert_answered_from_the_stored_record_rebases_the_patch_base() {
    let tree = "/proc/anchor()\n    return 0\n/proc/first(a)\n    return a + 1\n/datum/holder\n    var/list/items = list(1, 2)\n    proc/count()\n        return items.len\n";
    let roots = Roots::new();
    let mut shared = shared();
    Arc::get_mut(&mut shared).unwrap().max_workers = 2;
    roots.edit(0, tree);
    let initial = build(&shared, &roots);
    let applied = || crate::retained_output::applied_with_declaration_patches(&roots.manifest(0));
    let start = applied();

    roots.edit(0, &tree.replace("return a + 1", "return a + 2"));
    let edited = build(&shared, &roots);
    assert_ne!(initial.0, edited.0, "the edit must publish a new image");
    assert_eq!(applied(), start + 1, "the first edit patches");

    roots.edit(0, tree);
    let reverted = build(&shared, &roots);
    assert_equivalent_outputs(&reverted, &initial, "revert vs the initial build");
    assert_eq!(applied(), start + 2, "the revert is applied from the patch base, not answered from a record that leaves a stale base");

    let again = tree.replace("return a + 1", "return a + 3");
    roots.edit(0, &again);
    let second = build(&shared, &roots);
    assert_eq!(applied(), start + 3, "the edit after a revert stays on the patch path");
    let fresh_request = request(&roots, 0, true);
    let destination = fresh_request.artifact_directory.as_ref().unwrap().clone();
    let _oracle = control::bind(control::Cancellation::default());
    let fresh = published(crate::request_runner::run_build(fresh_request).unwrap(), &destination);
    assert_equivalent_outputs(&second, &fresh, "edit after a revert vs a fresh compile");
}

/// A retained session must survive a bulk edit, the edit back, and a bulk edit that also touches declarations: every build
/// publishes, none reports a consumed body, and each equals a fresh compile of the same tree.
#[test]
fn a_bulk_edit_and_the_edit_back_never_corrupt_the_retained_session() {
    let procs = |tag: &str, count: usize| -> String {
        let mut text = String::from("/proc/anchor()\n    return 0\n/datum/holder\n    var/list/items = list(1, 2)\n    proc/count()\n        return items.len\n");
        for index in 0..count {
            text.push_str(&format!("/proc/site_{index}(a)\n    var/x = a + {index}\n    if(x)\n        return \"{tag}{index}\"\n    return x\n"));
        }
        text
    };
    let roots = Roots::new();
    let mut shared = shared();
    Arc::get_mut(&mut shared).unwrap().max_workers = 2;
    let base = procs("a", 600);
    roots.edit(0, &base);
    let initial = build(&shared, &roots);

    // Rule-style edit: every body now references more of the program (calls, types, strings), changing link footprints.
    let bulk = procs("b", 600)
        .replace("    var/x = a + ", "    anchor()
    var/datum/holder/h = new /datum/holder()
    h.count()
    var/x = a + ");
    roots.edit(0, &bulk);
    let edited = build(&shared, &roots);
    assert_ne!(initial.0, edited.0, "the bulk edit must publish a new image");

    roots.edit(0, &base);
    let back = build(&shared, &roots);
    assert_equivalent_outputs(&back, &initial, "edit back vs the initial build");

    // Declarations move too (procs added and removed), then the session must still answer.
    let reshaped = format!("{}/proc/extra(a)\n    return a\n", procs("c", 550));
    roots.edit(0, &reshaped);
    let reshaped_build = build(&shared, &roots);
    let fresh_request = request(&roots, 0, true);
    let destination = fresh_request.artifact_directory.as_ref().unwrap().clone();
    let _oracle = control::bind(control::Cancellation::default());
    let fresh = published(crate::request_runner::run_build(fresh_request).unwrap(), &destination);
    assert_equivalent_outputs(&reshaped_build, &fresh, "reshaped tree vs a fresh compile");
}
