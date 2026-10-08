use super::*;
#[test]
fn differing_cpu_clocks_are_retained_without_rescaling() {
    let mut entry = Entry::default();
    record_cpu_interval(&mut entry, "worker", Some(40), true);
    record_coarse_interval(&mut entry, "worker", Some(30), true);
    assert_eq!(entry.threads["worker"], 40);
    assert_eq!(entry.coarse_threads["worker"], 30);
    record_cpu_interval(&mut entry, "worker", None, false);
    assert!(entry.cpu_missing);
    assert!(!entry.coarse_missing);
    assert!(entry.coarse_valid);
}
#[test]
fn same_named_nested_cpu_intervals_are_not_added_twice() {
    let frames = vec![Frame {
        name: "same",
        last_cpu: Some(10),
        last_coarse_cpu: Some(10),
        last_wall: Instant::now(),
    }];
    let mut entry = Entry::default();
    assert!(outermost_name(&[], "same"));
    assert!(!outermost_name(&frames, "same"));
    // The inner interval covers CPU 20..30; the outer covers 10..50.
    record_cpu_interval(
        &mut entry,
        "worker",
        Some(10),
        outermost_name(&frames, "same"),
    );
    record_cpu_interval(&mut entry, "worker", Some(40), outermost_name(&[], "same"));
    assert_eq!(entry.threads["worker"], 40);
    assert!(entry.cpu_valid && !entry.cpu_missing);
    // A missing inner boundary must still invalidate exclusive coverage.
    record_cpu_interval(&mut entry, "worker", None, false);
    assert!(entry.cpu_missing);
}
#[test]
fn shared_cpu_boundaries_partition_nested_intervals_exactly() {
    let state = State {
        calibration: clock::Calibration {
            method: "scripted",
            cycles_per_cpu_second: None,
            calibration_wall_s: 0.0,
            calibration_cpu_s: None,
            note: "test",
        },
        entries: Mutex::new(BTreeMap::new()),
        folded: Mutex::new(BTreeMap::new()),
        wall_folded: Mutex::new(BTreeMap::new()),
    };
    let wall = Instant::now();
    STACK.with(|stack| {
        stack.borrow_mut().push(Frame {
            name: "parent",
            last_cpu: Some(10),
            last_coarse_cpu: Some(10),
            last_wall: wall,
        })
    });
    cpu_segment(&state, Some(20), Some(20), wall);
    STACK.with(|stack| {
        stack.borrow_mut().push(Frame {
            name: "child",
            last_cpu: Some(20),
            last_coarse_cpu: Some(20),
            last_wall: wall,
        })
    });
    cpu_segment(&state, Some(30), Some(30), wall);
    STACK.with(|stack| {
        let mut stack = stack.borrow_mut();
        stack.pop();
        stack.last_mut().unwrap().last_cpu = Some(30);
    });
    cpu_segment(&state, Some(50), Some(50), wall);
    let entries = state.entries.lock().unwrap();
    assert_eq!(entries["parent"].exclusive, 30);
    assert_eq!(entries["child"].exclusive, 10);
    assert_eq!(
        entries.values().map(|entry| entry.exclusive).sum::<u64>(),
        cpu_interval(Some(10), Some(50)).unwrap()
    );
    drop(entries);
    cpu_segment(&state, None, None, wall);
    assert!(state.entries.lock().unwrap()["parent"].cpu_missing);
    STACK.with(|stack| stack.borrow_mut().clear());
    assert_eq!(cpu_interval(Some(50), Some(49)), None);
    assert_eq!(cpu_interval(None, Some(50)), None);
}
#[test]
fn coverage_union_does_not_multiply_nested_quantization() {
    let interval = |a, b| clock::CpuInterval {
        raw_begin: a,
        raw_end: b,
        coarse_begin: a,
        coarse_end: b,
    };
    let outer = interval(0, 1_000_000_000);
    let nested = union_interval_bounds(vec![outer, interval(10, 20), interval(20, 30)]).unwrap();
    assert_eq!(nested.lower, outer.bounds(cfg!(windows)).lower);
    assert_eq!(nested.upper, outer.bounds(cfg!(windows)).upper);
    let disjoint = union_interval_bounds(vec![interval(0, 100), interval(200, 300)]).unwrap();
    let expected = interval(0, 100)
        .bounds(cfg!(windows))
        .add(interval(200, 300).bounds(cfg!(windows)));
    assert_eq!(disjoint.lower, expected.lower);
    assert_eq!(disjoint.upper, expected.upper);
    let mut inconsistent = interval(0, 1_000_000_000);
    inconsistent.coarse_end += 1;
    assert!(union_interval_bounds(vec![outer, inconsistent]).is_none());
}

#[test]
fn exclusive_parent_selector_does_not_add_child_cpu_twice() {
    let stages = vec![
        StageReport {
            name: "parent".into(),
            max_thread_cpu_s: Some(10.0),
            max_thread_exclusive_cpu_s: Some(3.0),
            ..Default::default()
        },
        StageReport {
            name: "child".into(),
            max_thread_cpu_s: Some(7.0),
            ..Default::default()
        },
    ];
    let selected = ["exclusive:parent", "child"]
        .iter()
        .map(|selector| {
            let (stage, exclusive) = critical_stage(&stages, selector)?;
            if exclusive {
                stage.max_thread_exclusive_cpu_s
            } else {
                stage.max_thread_cpu_s
            }
        })
        .sum::<Option<f64>>();
    assert_eq!(selected, Some(10.0));
    assert!(critical_stage(&stages, "exclusive:missing").is_none());
    assert_eq!(
        critical_stage(&stages, "exclusive:child")
            .unwrap()
            .0
            .max_thread_exclusive_cpu_s,
        None
    );
}
