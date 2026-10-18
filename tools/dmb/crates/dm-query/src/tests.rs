use super::*;
use std::sync::atomic::AtomicUsize;

const INPUT: Kind = Kind(1);
const PARITY: Kind = Kind(2);
const TOTAL: Kind = Kind(3);
const CHOOSE: Kind = Kind(4);
const CYCLE: Kind = Kind(5);
const NOISE: Kind = Kind(6);
const BASE: u128 = 10_000;

fn input(n: u128) -> Key {
    Key::new(INPUT, n)
}
fn key(kind: Kind, n: u128) -> Key {
    Key::new(kind, n)
}
fn param(n: u128) -> Value {
    Arc::new(n)
}
fn id(params: &Value) -> u128 {
    *params.downcast_ref::<u128>().unwrap()
}
fn set(db: &Db, n: u128, value: u64) -> bool {
    db.set_input(input(n), value, value as u128 + 1)
}
fn outcome(value: u64) -> Result<Outcome, QueryError> {
    Ok(Outcome::new(value, value as u128 + 1, 8))
}

/// parity(n) reads input n; total(n) reads parity(n) and input 100.
fn database(counts: &Arc<[AtomicUsize; 2]>) -> Db {
    let db = Db::new();
    db.define_input(INPUT, "input");
    let c = Arc::clone(counts);
    db.define(PARITY, "parity", move |ctx, params| {
        c[0].fetch_add(1, Ordering::SeqCst);
        let n = *ctx.input::<u64>(input(id(params)))?;
        outcome(n % 2)
    });
    let c = Arc::clone(counts);
    db.define(TOTAL, "total", move |ctx, params| {
        c[1].fetch_add(1, Ordering::SeqCst);
        let parity = *ctx.get::<u64>(key(PARITY, id(params)), param(id(params)))?;
        let base = *ctx.input::<u64>(input(BASE))?;
        outcome(parity + base)
    });
    db
}
fn counters() -> Arc<[AtomicUsize; 2]> {
    Arc::new([AtomicUsize::new(0), AtomicUsize::new(0)])
}
fn total(db: &Db, n: u128) -> u64 {
    *db.get::<u64>(key(TOTAL, n), param(n)).unwrap()
}
fn runs(counts: &Arc<[AtomicUsize; 2]>) -> (usize, usize) {
    (counts[0].load(Ordering::SeqCst), counts[1].load(Ordering::SeqCst))
}

#[test]
fn computes_once_and_reuses_in_the_same_revision() {
    let counts = counters();
    let db = database(&counts);
    set(&db, 1, 3);
    set(&db, BASE, 10);
    assert_eq!(total(&db, 1), 11);
    assert_eq!(total(&db, 1), 11);
    assert_eq!(runs(&counts), (1, 1));
}

#[test]
fn unrelated_input_change_leaves_everything_green_without_running() {
    let counts = counters();
    let db = database(&counts);
    set(&db, 1, 3);
    set(&db, BASE, 10);
    set(&db, 2, 8);
    assert_eq!(total(&db, 1), 11);
    set(&db, 2, 9);
    assert_eq!(total(&db, 1), 11);
    assert_eq!(runs(&counts), (1, 1));
    assert_eq!(db.stats(TOTAL).green, 1);
    assert_eq!(db.stats(PARITY).green, 1);
}

#[test]
fn early_cutoff_keeps_dependants_green_when_a_recomputed_value_is_equal() {
    let counts = counters();
    let db = database(&counts);
    set(&db, 1, 3);
    set(&db, BASE, 10);
    assert_eq!(total(&db, 1), 11);
    // 3 -> 5: parity stays 1, so total does not rerun.
    set(&db, 1, 5);
    assert_eq!(total(&db, 1), 11);
    assert_eq!(runs(&counts), (2, 1));
    assert_eq!(db.stats(PARITY).cutoff, 1);
    // 5 -> 6: parity changes, total reruns.
    set(&db, 1, 6);
    assert_eq!(total(&db, 1), 10);
    assert_eq!(runs(&counts), (3, 2));
}

#[test]
fn setting_an_input_to_the_same_hash_does_not_advance_the_revision() {
    let db = Db::new();
    db.define_input(INPUT, "input");
    assert!(set(&db, 1, 3));
    let revision = db.revision();
    assert!(!set(&db, 1, 3));
    assert_eq!(db.revision(), revision);
}

#[test]
fn dependencies_follow_the_branch_taken_and_reverse_edges_update() {
    // choose(n) reads input 1 or input 2 depending on input 0.
    let db = Db::new();
    db.define_input(INPUT, "input");
    db.define(CHOOSE, "choose", |ctx, _| {
        let pick = *ctx.input::<u64>(input(0))?;
        let n = if pick == 0 { *ctx.input::<u64>(input(1))? } else { *ctx.input::<u64>(input(2))? };
        outcome(n)
    });
    set(&db, 0, 0);
    set(&db, 1, 10);
    set(&db, 2, 20);
    let choose = key(CHOOSE, 0);
    let read = |db: &Db| *db.get::<u64>(choose, param(0)).unwrap();
    assert_eq!(read(&db), 10);
    assert_eq!(db.dependants(&[input(1)]), vec![choose]);
    assert!(db.dependants(&[input(2)]).is_empty());
    set(&db, 0, 1);
    assert_eq!(read(&db), 20);
    assert!(db.dependants(&[input(1)]).is_empty());
    assert_eq!(db.dependants(&[input(2)]), vec![choose]);
    // The branch not taken no longer reruns it.
    set(&db, 1, 11);
    assert_eq!(read(&db), 20);
    assert_eq!(db.stats(CHOOSE).computed, 2);
}

#[test]
fn dependants_are_transitive() {
    let counts = counters();
    let db = database(&counts);
    set(&db, 1, 3);
    set(&db, BASE, 10);
    total(&db, 1);
    let closure = db.dependants(&[input(1)]);
    assert_eq!(closure, vec![key(PARITY, 1), key(TOTAL, 1)]);
}

#[test]
fn a_cycle_is_an_error_not_a_hang() {
    let db = Db::new();
    db.define(CYCLE, "cycle", |ctx, params| {
        let n = id(params);
        let next = if n == 0 { 1 } else { 0 };
        let value = ctx.get::<u64>(key(CYCLE, next), param(next))?;
        outcome(*value)
    });
    let error = db.get::<u64>(key(CYCLE, 0), param(0)).unwrap_err();
    assert!(matches!(error, QueryError::Cycle(_)), "{error:?}");
    // The failed nodes are not left busy: a second attempt gives the same answer.
    assert!(matches!(db.get::<u64>(key(CYCLE, 0), param(0)), Err(QueryError::Cycle(_))));
}

#[test]
fn eviction_keeps_revalidation_and_refills_only_the_value() {
    let counts = counters();
    let db = database(&counts);
    set(&db, 1, 3);
    set(&db, BASE, 10);
    assert_eq!(total(&db, 1), 11);
    let freed = db.evict_values(&[]);
    assert_eq!(freed, 16);
    assert_eq!(db.value_bytes(), 0);
    assert_eq!(db.stats(TOTAL).evicted, 1);
    // Reading refills the value by recomputing; equal hash means a cutoff, not a change.
    assert_eq!(total(&db, 1), 11);
    assert_eq!(db.stats(TOTAL).cutoff, 1);
    // A dependant that only observes the hash does not need the value back.
    db.evict_values(&[TOTAL]);
    let hash = db.hash(key(TOTAL, 1), param(1)).unwrap();
    assert_eq!(hash, 12);
    assert_eq!(db.stats(TOTAL).computed, 2);
}

#[test]
fn eviction_only_touches_the_named_kinds() {
    let counts = counters();
    let db = database(&counts);
    set(&db, 1, 3);
    set(&db, BASE, 10);
    total(&db, 1);
    db.evict_values(&[PARITY]);
    assert_eq!(db.stats(PARITY).evicted, 1);
    assert_eq!(db.stats(TOTAL).evicted, 0);
}

#[test]
fn removing_a_dependency_reruns_its_dependants() {
    let db = Db::new();
    db.define_input(INPUT, "input");
    db.define(CHOOSE, "present", |ctx, _| match ctx.input::<u64>(input(1)) {
        Ok(value) => outcome(*value),
        Err(_) => outcome(0),
    });
    set(&db, 1, 7);
    let present = key(CHOOSE, 0);
    assert_eq!(*db.get::<u64>(present, param(0)).unwrap(), 7);
    assert!(db.remove(input(1)));
    assert_eq!(*db.get::<u64>(present, param(0)).unwrap(), 0);
}

#[test]
fn verify_mode_reports_a_query_that_is_not_a_function_of_its_reads() {
    let flip = Arc::new(AtomicUsize::new(0));
    let db = Db::new();
    db.define_input(INPUT, "input");
    let seen = Arc::clone(&flip);
    db.define(NOISE, "noise", move |ctx, _| {
        ctx.input::<u64>(input(1))?;
        outcome(seen.fetch_add(1, Ordering::SeqCst) as u64)
    });
    set(&db, 1, 1);
    let noise = key(NOISE, 0);
    db.get::<u64>(noise, param(0)).unwrap();
    db.set_verify(true);
    set(&db, 2, 1);
    db.get::<u64>(noise, param(0)).unwrap();
    let failures = db.verify_failures();
    assert_eq!(failures.len(), 1, "{failures:?}");
    assert!(failures[0].contains("noise"), "{failures:?}");
}

#[test]
fn a_panicking_query_does_not_wedge_the_node() {
    let db = Db::new();
    db.define_input(INPUT, "input");
    let tries = Arc::new(AtomicUsize::new(0));
    let seen = Arc::clone(&tries);
    db.define(NOISE, "flaky", move |ctx, _| {
        ctx.input::<u64>(input(1))?;
        if seen.fetch_add(1, Ordering::SeqCst) == 0 {
            panic!("first attempt fails");
        }
        outcome(5)
    });
    set(&db, 1, 1);
    let flaky = key(NOISE, 0);
    let first = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| db.get::<u64>(flaky, param(0))));
    assert!(first.is_err());
    assert_eq!(*db.get::<u64>(flaky, param(0)).unwrap(), 5);
}

#[test]
fn threads_share_one_computation() {
    let counts = counters();
    let db = Arc::new(database(&counts));
    set(&db, 1, 3);
    set(&db, BASE, 10);
    let handles: Vec<_> = (0..8)
        .map(|_| {
            let db = Arc::clone(&db);
            std::thread::spawn(move || total(&db, 1))
        })
        .collect();
    for handle in handles {
        assert_eq!(handle.join().unwrap(), 11);
    }
    assert_eq!(runs(&counts), (1, 1));
}

#[test]
fn many_independent_queries_revalidate_only_the_changed_ones() {
    let counts = counters();
    let db = database(&counts);
    set(&db, BASE, 0);
    for n in 0..200u128 {
        set(&db, n, n as u64);
    }
    for n in 0..200u128 {
        total(&db, n);
    }
    assert_eq!(runs(&counts), (200, 200));
    // Flip the parity of three inputs and the shared base: everything reruns for the base,
    // but parity only for the three.
    set(&db, 7, 1000);
    set(&db, 8, 1001);
    set(&db, 9, 1002);
    set(&db, BASE, 1);
    for n in 0..200u128 {
        total(&db, n);
    }
    assert_eq!(counts[0].load(Ordering::SeqCst), 203);
    assert_eq!(counts[1].load(Ordering::SeqCst), 400);
}
