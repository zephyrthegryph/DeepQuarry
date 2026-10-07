#[cfg(feature = "allocation-counting")]
#[global_allocator]
static ALLOCATOR: dm_profile::CountingAllocator = dm_profile::CountingAllocator;

#[test]
fn trace_cpu_flame_and_summary_artifacts_are_written() {
    let directory = std::env::temp_dir().join(format!("dm-profile-fixture-{}", std::process::id()));
    std::fs::create_dir_all(&directory).unwrap();
    let path = directory.join("probe.trace.json");
    let profile = dm_profile::initialize(&path).unwrap();
    {
        let _stage = dm_profile::stage("fixture");
        let _leaf = dm_profile::stage("fixture.work");
        let mut bytes = vec![0u8; 4096];
        for n in 0..200_000usize {
            bytes[n % 4096] = std::hint::black_box((n % 255) as u8);
        }
        std::hint::black_box(bytes);
        dm_profile::record_io(123, 456, std::time::Duration::from_millis(1));
    }
    assert!(profile.has_stage("fixture"));
    assert!(profile.has_stage("fixture.work"));
    assert!(!profile.has_stage("missing"));
    let report = profile.finish(&["fixture"]).unwrap();
    assert_eq!(report.schema, 1);
    assert_eq!(report.critical_path_stages, vec!["fixture"]);
    let leaf = report
        .stages
        .iter()
        .find(|stage| stage.name == "fixture.work")
        .unwrap();
    assert_eq!(leaf.attributed_read_bytes, 123);
    assert_eq!(leaf.attributed_write_bytes, 456);
    assert_eq!(leaf.io_blocked_s, Some(0.001));
    assert!(report.total_cpu_s.is_some());
    #[cfg(feature = "allocation-counting")]
    {
        assert!(leaf.allocations > 0);
        assert!(leaf.allocated_bytes >= 4096);
        assert!(report.peak_allocator_live_bytes >= 4096);
    }
    for suffix in [
        "report.json",
        "cpu.folded",
        "cpu.svg",
        "wall.folded",
        "wall.svg",
        "tracing.folded",
    ] {
        assert!(
            std::fs::metadata(path.with_extension(suffix))
                .unwrap()
                .len()
                > 0
        );
    }
    assert!(std::fs::metadata(&path).unwrap().len() > 0);
    let chrome = std::fs::read_to_string(&path).unwrap();
    assert!(chrome.contains("fixture.work"));
    assert!(chrome.contains("allocated_bytes"));
    std::fs::remove_dir_all(directory).unwrap();
}
