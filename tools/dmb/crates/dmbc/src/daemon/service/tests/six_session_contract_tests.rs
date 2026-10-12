//! Six synthetic source roots through the real retained request pipeline.
//! This is not six registered Git worktrees or transport/runtime acceptance.
use super::*;
use crate::request::{BuildOutcome, BuildRequest};
use std::path::Path;
#[path = "implied_type_recovery_tests.rs"]
mod implied_type_recovery;
#[path = "declaration_error_recovery_tests.rs"]
mod declaration_error_recovery;
#[path = "six_session_contract_tests/retirement_pipe_tests.rs"]
mod retirement_pipe;
#[path = "six_session_contract_tests/query_failure_state_tests.rs"]
mod query_failure_state;

const SOURCE: &str = "/datum/base\n    var/value = 7\n    proc/result()\n        return value\n/proc/probe()\n    var/datum/base/item = new\n    return item.result()\n";

struct Roots(PathBuf);
impl Roots {
    fn new() -> Self {
        let parent = if cfg!(windows) {
            PathBuf::from("E:/dq-cache/dmb-protocol-checks")
        } else {
            std::env::temp_dir()
        };
        let stamp = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let root = parent.join(format!(
            "six-session-contract-{}-{stamp}",
            std::process::id()
        ));
        std::fs::create_dir_all(&root).unwrap();
        for index in 0..6 {
            let directory = root.join(format!("root-{index}"));
            std::fs::create_dir(&directory).unwrap();
            std::fs::write(directory.join("probe.dme"), "#include \"probe.dm\"\n").unwrap();
            std::fs::write(directory.join("probe.dm"), SOURCE).unwrap();
        }
        std::fs::write(
            root.join("template.bin"),
            include_bytes!("../../../../../../fixtures/native_template.bin"),
        )
        .unwrap();
        Self(root)
    }
    fn manifest(&self, index: usize) -> PathBuf {
        std::fs::canonicalize(self.0.join(format!("root-{index}/probe.dme"))).unwrap()
    }
    fn edit(&self, index: usize, source: &str) {
        std::fs::write(self.0.join(format!("root-{index}/probe.dm")), source).unwrap();
    }
}
impl Drop for Roots {
    fn drop(&mut self) {
        // Only this newly issued fixture root is owned by this guard.
        let _ = std::fs::remove_dir_all(&self.0);
    }
}
fn request(roots: &Roots, index: usize, fresh: bool) -> BuildRequest {
    let args = vec![
        "compile".into(),
        roots.manifest(index).to_string_lossy().into_owned(),
    ];
    let crate::request::Command::Build(request) = crate::cli::parse(&args).unwrap() else {
        panic!("compile request expected")
    };
    let mut request = *request;
    request.workers = 1;
    request.engine_template = Some(roots.0.join("template.bin"));
    request.bootstrap_catalog = true;
    request.progress_enabled = false;
    request.no_cache = true;
    request.exact_inputs = true;
    request.cache_root = Some(roots.0.join(format!("cache-{index}")));
    request.output_store = Some(roots.0.join(format!(
        "store-{index}-{}",
        if fresh { "fresh" } else { "retained" }
    )));
    request.artifact_directory = Some(roots.0.join(format!(
        "output-{index}-{}",
        if fresh { "fresh" } else { "retained" }
    )));
    request
}
fn published(
    outcome: BuildOutcome,
    destination: &Path,
) -> (crate::publish::OutputPair, Vec<u8>, Vec<u8>) {
    let BuildOutcome::Published {
        pair,
        output_project,
        ..
    } = outcome
    else {
        panic!("executable publication expected")
    };
    assert_eq!(output_project, destination.join("probe.dme"));
    let dmb = std::fs::read(output_project.with_extension("dmb")).unwrap();
    let rsc = std::fs::read(output_project.with_extension("rsc")).unwrap();
    assert_eq!(pair, crate::publish::OutputPair::from_bytes(&dmb, &rsc));
    (pair, dmb, rsc)
}

fn compare_revision(shared: &Arc<Shared>, roots: &Roots) -> Vec<crate::publish::OutputPair> {
    let mut pairs = Vec::with_capacity(6);
    // Exactly two requests can be active, including their independent fresh
    // oracles. No detached workers or executor/store implementation is added.
    for batch in (0..6).step_by(2) {
        let rendezvous = std::sync::Barrier::new(2);
        std::thread::scope(|scope| {
            let handles = (batch..batch + 2)
                .map(|index| {
                    let rendezvous = &rendezvous;
                    scope.spawn(move || {
                        let retained = request(roots, index, false);
                        let fresh = request(roots, index, true);
                        let slot = shared.slot(
                            retained.project.clone(),
                            &retained.defines,
                            Some(&retained),
                        );
                        let token = control::Cancellation::default();
                        let _latest = LatestRequest::register(
                            &slot,
                            RequestKey::of(&retained, &retained.project),
                            token.clone(),
                        );
                        let _binding = control::bind(token);
                        let _serial = slot
                            .lock_request_until(&admission_deadline::AdmissionDeadline::new(
                                Instant::now(),
                            ))
                            .unwrap();
                        let _permit = shared.acquire(1).unwrap();
                        assert!(*shared.workers.lock().unwrap() <= 2);
                        rendezvous.wait();
                        let mut host = slot.lock_host().unwrap();
                        let retained_destination =
                            retained.artifact_directory.as_ref().unwrap().clone();
                        let a = published(
                            crate::request_runner::run_build_with_host(retained, &mut host)
                                .unwrap(),
                            &retained_destination,
                        );
                        drop(host);
                        // The fresh oracle is a distinct compiler request. A
                        // completed retained publication seals its original
                        // token permanently; it must not govern oracle workers.
                        drop(_binding);
                        drop(_latest);
                        drop(_serial);
                        let _oracle_binding = control::bind(control::Cancellation::default());
                        let fresh_destination = fresh.artifact_directory.as_ref().unwrap().clone();
                        let b = published(
                            crate::request_runner::run_build(fresh).unwrap(),
                            &fresh_destination,
                        );
                        assert_eq!(a, b, "root {index} retained output differs from fresh");
                        a.0
                    })
                })
                .collect::<Vec<_>>();
            for handle in handles {
                pairs.push(handle.join().unwrap());
            }
        });
    }
    assert_eq!(*shared.running.lock().unwrap(), 0);
    assert_eq!(*shared.workers.lock().unwrap(), 0);
    pairs
}

#[test]
fn six_source_sessions_asymmetric_edits_and_panic_reset_match_fresh_bytes() {
    let roots = Roots::new();
    let mut shared = shared();
    Arc::get_mut(&mut shared).unwrap().max_workers = 2;
    let slots = (0..6)
        .map(|index| {
            let request = request(&roots, index, false);
            shared.slot(request.project.clone(), &request.defines, Some(&request))
        })
        .collect::<Vec<_>>();
    for (index, slot) in slots.iter().enumerate() {
        for other in slots.iter().skip(index + 1) {
            assert!(!Arc::ptr_eq(slot, other));
        }
        let request = request(&roots, index, true);
        assert!(Arc::ptr_eq(
            slot,
            &shared.slot(request.project.clone(), &request.defines, Some(&request))
        ));
    }
    let initial = compare_revision(&shared, &roots);
    roots.edit(0, &SOURCE.replace("return value", "return value + 1"));
    roots.edit(
        1,
        &format!(
            "{SOURCE}/datum/base\n    var/extra = 11\n    proc/added()\n        return extra\n"
        ),
    );
    roots.edit(2, &SOURCE.replace("var/value = 7", "var/value = 9"));
    let edited = compare_revision(&shared, &roots);
    for index in 0..3 {
        assert_ne!(
            initial[index], edited[index],
            "edited root {index} must publish new content"
        );
    }
    assert_eq!(
        initial[3..],
        edited[3..],
        "unedited sessions must preserve exact outputs"
    );
    // Same reset operation as the production caught-panic branch. The host
    // guard remains outside catch_unwind, so an injected failure cannot poison
    // the session mutex or reset any of the other five owners.
    {
        let mut host = slots[5].host.lock().unwrap();
        let failed = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
            panic!("fixture compiler failure")
        }));
        assert!(failed.is_err());
        shared.reset_host(&mut host);
    }
    for index in 0..6 {
        roots.edit(index, SOURCE);
    }
    assert_eq!(compare_revision(&shared, &roots), initial);
    assert_eq!(shared.slots.lock().unwrap().len(), 6);
    assert!(slots
        .iter()
        .all(|slot| slot.newest.lock().unwrap().is_empty()));
}

// This captures the production daemon diagnostic byte stream, without replacing
// the compiler or introducing a diagnostic/cache implementation in the fixture.
fn run_captured(
    request: BuildRequest,
    host: &mut crate::runner_host::BuildHost,
) -> (
    Result<BuildOutcome, Box<dyn std::error::Error>>,
    Vec<String>,
) {
    let records = Arc::new(Mutex::new(Vec::<u8>::new()));
    let captured = Arc::clone(&records);
    crate::daemon::OUTPUT.with(|sink| {
        assert!(sink.borrow().is_none());
        *sink.borrow_mut() = Some(Box::new(move |stdout, bytes| {
            if !stdout {
                captured.lock().unwrap().extend_from_slice(bytes);
            }
            Ok(())
        }));
    });
    let _output = crate::daemon::OutputBinding;
    // Each attempt owns a distinct cancellation/publication token. Publication
    // sealing of a successful predecessor cannot leak into a later request.
    let _request = control::bind(control::Cancellation::default());
    let result = crate::request_runner::run_build_with_host(request, host);
    let bytes = records.lock().unwrap().clone();
    let diagnostics = String::from_utf8(bytes)
        .unwrap()
        .lines()
        .filter(|line| {
            line.contains(":error:")
                || line.contains(":native unsupported:")
                || line.contains(":internal compiler error:")
        })
        .map(str::to_owned)
        .collect();
    (result, diagnostics)
}

#[test]
fn source_rejection_preserves_prior_pair_and_recovery_matches_fresh_current_include() {
    let roots = Roots::new();
    let shared = shared();
    let initial_request = request(&roots, 0, false);
    let slot = shared.slot(
        initial_request.project.clone(),
        &initial_request.defines,
        Some(&initial_request),
    );
    let destination = initial_request.artifact_directory.as_ref().unwrap().clone();
    let mut host = slot.lock_host().unwrap();
    let (initial, diagnostics) = run_captured(initial_request, &mut host);
    assert!(diagnostics.is_empty());
    let initial = published(initial.unwrap(), &destination);
    for shift in [0, 3] {
        // The actual included file changes, and both primary/related locations
        // must belong to this revision rather than the predecessor's source.
        let bad = format!("{}{}{}", "// moved include\n".repeat(shift), SOURCE,
            "/proc/rejected()\n    var/duplicate = 1\n    var/duplicate = 2\n    return duplicate\n");
        roots.edit(0, &bad);
        let (retained, retained_diagnostics) = run_captured(request(&roots, 0, false), &mut host);
        let (fresh, fresh_diagnostics) = run_captured(
            request(&roots, 0, true),
            &mut crate::runner_host::BuildHost::one_shot(),
        );
        for result in [retained, fresh] {
            let error = result.err().expect("invalid source must reject");
            assert_eq!(
                crate::request_failure::classify(error.as_ref()),
                crate::request_failure::FailureKind::Source
            );
        }
        assert_eq!(retained_diagnostics, fresh_diagnostics);
        let first_line = SOURCE.lines().count() + shift + 2;
        assert_eq!(
            retained_diagnostics,
            vec![
                format!(
                    "probe.dm:{}:error: duplicate: duplicate definition",
                    first_line + 1
                ),
                format!("probe.dm:{first_line}:error: duplicate: previous definition"),
            ]
        );
        // Error attempts cannot install outputs or replace the last valid pair.
        assert_eq!(
            std::fs::read(destination.join("probe.dmb")).unwrap(),
            initial.1
        );
        assert_eq!(
            std::fs::read(destination.join("probe.rsc")).unwrap(),
            initial.2
        );
    }
    roots.edit(0, &SOURCE.replace("return value", "return value + 2"));
    let (recovered, diagnostics) = run_captured(request(&roots, 0, false), &mut host);
    assert!(diagnostics.is_empty());
    let recovered = published(recovered.unwrap(), &destination);
    let fresh_request = request(&roots, 0, true);
    let fresh_destination = fresh_request.artifact_directory.as_ref().unwrap().clone();
    let (fresh, diagnostics) = run_captured(
        fresh_request,
        &mut crate::runner_host::BuildHost::one_shot(),
    );
    assert!(diagnostics.is_empty());
    assert_eq!(recovered, published(fresh.unwrap(), &fresh_destination));
    assert_ne!(recovered.0, initial.0);
}
