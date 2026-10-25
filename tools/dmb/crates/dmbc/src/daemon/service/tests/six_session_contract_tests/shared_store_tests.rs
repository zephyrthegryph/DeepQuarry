//! Two project roots served by one daemon share one store (`shared_store.rs`) and never see each other's edits.
//!
//! The daemon activates the process-wide store, which a unit-test process must not do (every other test would silently share
//! it), so the retained builds run in a child process of this test binary with the store active, and this process computes
//! the fresh oracles with sharing off. Each state's output must be equivalent to its oracle (the retained patch path is only
//! required to be semantically equal to a fresh compile, `assert_equivalent_outputs`); a body edit in one root that leaked
//! into the other root through a shared variant would change the other root's marker proc.
use super::*;
use crate::publish::OutputPair;

const CHILD: &str = "DMB_SHARED_STORE_TEST_CHILD";
const CHILD_TEST: &str = "daemon::service::tests::six_session_contract::shared_store::child_builds_two_roots_through_one_store";
type Triple = (OutputPair, Vec<u8>, Vec<u8>);

fn marked(label: &str, revision: u32) -> String {
    format!("{SOURCE}/proc/dq_root_marker()\n    return \"MARKER-{label}-{revision}\"\n")
}

fn fresh_output(roots: &Roots, index: usize) -> Triple {
    let request = request(roots, index, true);
    let destination = request.artifact_directory.clone().unwrap();
    let _binding = control::bind(control::Cancellation::default());
    published(crate::request_runner::run_build(request).unwrap(), &destination)
}

fn retained_output(shared: &Arc<Shared>, roots: &Roots, index: usize) -> Triple {
    let retained = request(roots, index, false);
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
    published(
        crate::request_runner::run_build_with_host(retained, &mut host).unwrap(),
        &destination,
    )
}

/// The retained builds of the scenario, in order: edit the named root to (label, revision), then build it. The roots alternate,
/// so each build runs in a daemon that already holds the other root's session.
const STEPS: [(usize, &str, u32); 6] = [(0, "A", 1), (1, "B", 1), (0, "A", 2), (1, "B", 1), (1, "B", 2), (0, "A", 2)];

/// Runs only as the child of `two_roots_in_one_daemon_store_match_fresh_bytes_and_never_leak`.
#[test]
fn child_builds_two_roots_through_one_store() {
    let Some(directory) = std::env::var_os(CHILD) else {
        return;
    };
    let roots = Roots(PathBuf::from(directory));
    let shared = shared();
    crate::shared_store::activate(&shared.store);
    assert!(crate::shared_store::active().is_some(), "the child process runs with the store active");
    // Both roots start as the same source, each with its own marker; the builds alternate between them.
    roots.edit(0, &marked("A", 1));
    roots.edit(1, &marked("B", 1));
    for (step, (index, label, revision)) in STEPS.into_iter().enumerate() {
        roots.edit(index, &marked(label, revision));
        let (_, dmb, rsc) = retained_output(&shared, &roots, index);
        std::fs::write(roots.0.join(format!("step-{step}.dmb")), dmb).unwrap();
        std::fs::write(roots.0.join(format!("step-{step}.rsc")), rsc).unwrap();
    }
    assert!(shared.store.core_count() > 0, "the sessions created their cores in the shared store");
    std::mem::forget(roots);
}

#[test]
fn two_roots_in_one_daemon_store_match_fresh_output_and_never_leak() {
    if std::env::var_os(CHILD).is_some() {
        return;
    }
    assert!(crate::shared_store::active().is_none(), "this process computes the oracles with sharing off");
    let roots = Roots::new();
    // Oracles: a fresh, private compile of every state, in a spare root (the output depends on the source only).
    let mut oracle = std::collections::BTreeMap::new();
    for (_, label, revision) in STEPS {
        roots.edit(5, &marked(label, revision));
        oracle.insert(format!("{label}{revision}"), fresh_output(&roots, 5));
    }
    assert_eq!(oracle.len(), 4);
    assert_eq!(
        oracle.values().map(|triple| triple.0.id).collect::<std::collections::BTreeSet<_>>().len(),
        4,
        "every marker state is a different build, so a leak between roots would be visible"
    );
    let output = std::process::Command::new(std::env::current_exe().unwrap())
        .args([CHILD_TEST, "--exact", "--nocapture", "--test-threads=1"])
        .env(CHILD, &roots.0)
        .output()
        .unwrap();
    assert!(
        output.status.success(),
        "child failed:\n{}\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    for (step, (index, label, revision)) in STEPS.into_iter().enumerate() {
        let dmb = std::fs::read(roots.0.join(format!("step-{step}.dmb"))).unwrap();
        let rsc = std::fs::read(roots.0.join(format!("step-{step}.rsc"))).unwrap();
        let state = format!("{label}{revision}");
        let retained = (OutputPair::from_bytes(&dmb, &rsc), dmb, rsc);
        assert_equivalent_outputs(
            &retained,
            &oracle[&state],
            &format!("root {index} state {state} through the shared daemon store"),
        );
        // The other root's marker must not be in this output: equal to this state's oracle up to table order, and a
        // different build from every other state's oracle.
        for (other, triple) in &oracle {
            if *other != state {
                assert_ne!(retained.0.id, triple.0.id, "step {step} ({state}) equals the build of state {other}");
            }
        }
    }
}
