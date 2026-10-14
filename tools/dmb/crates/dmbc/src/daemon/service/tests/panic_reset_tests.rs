use super::*;

#[test]
fn panic_recovery_keeps_six_hosts_on_shared_engine_and_executor_owners() {
    let shared = shared();
    let hosts = (0..6)
        .map(|index| shared.slot(PathBuf::from(format!("E:/fixture/recovered-{index}.dme")), &BTreeMap::new(), None))
        .collect::<Vec<_>>();
    assert_eq!(Arc::strong_count(&shared.engines), 7);
    for slot in &hosts {
        let mut host = slot.host.lock().unwrap();
        let failed = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
            panic!("injected compiler failure");
        }));
        assert!(failed.is_err());
        // Same operation used by the production panic branch. A default host
        // here would make the shared inventory report zero physical workers.
        shared.reset_host(&mut host);
        assert_eq!(Arc::strong_count(&shared.engines), 7);
        let (_, execution, _) = host.execution(2, None).unwrap();
        execution.run(|executor| assert_eq!(executor.workers(), 2)).unwrap();
        assert_eq!(shared.executors.physical_workers(), 2);
    }
    shared.executors.trim(Instant::now(), true);
    assert_eq!(shared.executors.physical_workers(), 0);
}
