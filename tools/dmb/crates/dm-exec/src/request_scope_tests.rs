use super::*;
#[test]
fn persistent_workers_rebind_and_cleanup_panics_and_stale_tokens() {
    let stamp = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    let directory = std::path::PathBuf::from("E:/dq-cache/dmb-protocol-checks")
        .join(format!("executor-requests-{}-{stamp}", std::process::id()));
    std::fs::create_dir_all(&directory).unwrap();
    let mut executor = BuildExecutor::new_unbound(2).unwrap();
    let mut identities = None;
    let mut stale = None;
    for (name, panic) in [("first", false), ("panicked", true), ("last", false)] {
        let profile =
            dm_profile::initialize(&directory.join(format!("{name}.trace.json"))).unwrap();
        let context = profile.request_context();
        let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
            executor
                .with_request(Some(&context), |executor| {
                    let current = executor.pool.as_ref().unwrap().broadcast(|_| {
                        dm_profile::tracing::info!(request = name, "persistent worker");
                        std::thread::current().id()
                    });
                    if let Some(previous) = &identities {
                        assert_eq!(&current, previous);
                    } else {
                        identities = Some(current);
                    }
                    executor.scope(|scope| {
                        scope.spawn(|_| {
                            let _stage = dm_profile::stage("worker.job");
                            if panic {
                                panic!("intentional bracket panic");
                            }
                        });
                    });
                })
                .unwrap()
        }));
        assert_eq!(result.is_err(), panic);
        let report = profile.finish(&[]).unwrap();
        let lifetime = report
            .stages
            .iter()
            .find(|stage| stage.name == "compiler.worker_lifetime")
            .unwrap();
        assert_eq!(lifetime.calls, 2);
        if stale.is_none() {
            stale = Some(context);
        }
    }
    let called = std::cell::Cell::new(false);
    assert!(executor
        .with_request(stale.as_ref(), |_| called.set(true))
        .is_err());
    assert!(!called.get());
    executor
        .with_request(None, |executor| assert_eq!(executor.install(|| 17), 17))
        .unwrap();
    executor.shutdown();
    let first = std::fs::read_to_string(directory.join("first.trace.json")).unwrap();
    let last = std::fs::read_to_string(directory.join("last.trace.json")).unwrap();
    assert!(first.contains("first"));
    assert!(!first.contains("last"));
    assert!(last.contains("last"));
    assert!(!last.contains("first"));
    std::fs::remove_dir_all(directory).unwrap();
}
#[test]
fn compatibility_pool_rejects_request_brackets() {
    let mut executor = BuildExecutor::new(1).unwrap();
    assert!(executor.with_request(None, |_| ()).is_err());
}
#[test]
fn unbound_pool_refuses_jobs_outside_a_bracket() {
    let executor = BuildExecutor::new_unbound(1).unwrap();
    assert!(
        std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| executor.install(|| 1))).is_err()
    );
    assert!(
        std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| executor.scope(|_| ()))).is_err()
    );
}
