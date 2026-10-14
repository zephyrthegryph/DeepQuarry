//! Dedicated process: verifies exact request and stage propagation to workers.
use dm_exec::BuildExecutor;
use std::sync::atomic::{AtomicUsize, Ordering};

#[test]
fn explicit_jobs_inherit_nested_context_and_unwind_without_leaking() {
    let directory = std::env::temp_dir().join(format!("dm-exec-context-{}", std::process::id()));
    std::fs::create_dir_all(&directory).unwrap();
    let profile = dm_profile::initialize(&directory.join("context.trace.json")).unwrap();
    let clean_context = dm_profile::StageContext::capture();
    let executor = BuildExecutor::new(2).unwrap();
    let completed = AtomicUsize::new(0);
    {
        let _parent = dm_profile::stage("context.parent");
        executor.scope(|scope| {
            scope.spawn(|scope| {
                let _child = dm_profile::stage("context.child");
                scope.spawn(|_| {
                    let _leaf = dm_profile::stage("context.leaf");
                    completed.fetch_add(1, Ordering::SeqCst);
                });
            });
        });
        let failed = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
            executor.scope(|scope| scope.spawn(|_| panic!("intentional context unwind")));
        }));
        assert!(failed.is_err());
        executor.install(|| {
            let _installed = dm_profile::stage("context.installed");
            completed.fetch_add(1, Ordering::SeqCst);
        });
    }
    // Reuse workers after all inherited guards have unwound.
    executor.scope(|scope| {
        scope.spawn(|_| {
            assert_eq!(dm_profile::StageContext::capture(), clean_context);
            let _clean = dm_profile::stage("context.clean");
            completed.fetch_add(1, Ordering::SeqCst);
        })
    });
    assert_eq!(completed.load(Ordering::SeqCst), 3);
    executor.shutdown();
    let report = profile
        .finish(&["context.parent", "context.clean"])
        .unwrap();
    let find = |name| report.stages.iter().find(|row| row.name == name).unwrap();
    assert!(find("context.parent").calls >= 4);
    assert!(find("context.child").calls >= 2);
    assert_eq!(find("context.leaf").calls, 1);
    assert_eq!(find("context.clean").calls, 1);
}
