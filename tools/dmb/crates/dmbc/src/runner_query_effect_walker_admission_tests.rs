//! Original primary source/Walker/Db resource regressions, not fabricated facts.
use super::*;
fn refused_then_recovers(source: &str, limit: usize) {
    let (snapshot, reads) = fixture(source, None);
    let input = snapshot.native_purity_input(&snapshot.tree).unwrap();
    let db = snapshot.native_raw_queries.as_ref().unwrap();
    let owner = dm_ir::Resolver::source_owner(snapshot.tree.as_ref());
    let before = reads.load(Ordering::Relaxed);
    let limited = db.effect_storage_limit_for_test(limit);
    let error = snapshot
        .native_purity_report(&input, &env(), None, &snapshot.tree)
        .unwrap_err();
    assert!(error.to_string().contains("budget"), "{error}");
    assert_eq!(
        db.effect_retained_values_for_test(dm_query::Kind(17)),
        0,
        "denied original Walker must not publish a body or String refusal"
    );
    assert_eq!(db.effect_retained_values_for_test(dm_query::Kind(20)), 0);
    drop(limited);
    let rows = snapshot
        .native_purity_report(&input, &env(), None, &snapshot.tree)
        .unwrap();
    assert!(
        rows.is_empty(),
        "original source is pure under default operational allowance"
    );
    assert_eq!(owner, dm_ir::Resolver::source_owner(snapshot.tree.as_ref()));
    assert_eq!(before, reads.load(Ordering::Relaxed));
}
#[test]
fn initial_parameter_locals_are_admitted_before_constructing_the_original_walker_map() {
    let args = (0..100)
        .map(|i| format!("p{i}"))
        .collect::<Vec<_>>()
        .join(",");
    refused_then_recovers(
        &format!("/proc/check({args})\n    set SpacemanDMM_should_be_pure=1\n    return\n"),
        32 * 1024,
    )
}
#[test]
fn expression_observation_growth_is_admitted_before_vector_replacement() {
    let mut source=String::from("/datum/box\n    var/value=0\n/proc/check(datum/box/B)\n    set SpacemanDMM_should_be_pure=1\n");
    for _ in 0..1000 {
        source.push_str("    B.value\n")
    }
    refused_then_recovers(&source, 64 * 1024)
}
#[test]
fn repeated_scope_maps_are_admitted_before_clone_and_void_failure_unwinds_without_clean_output() {
    let mut source = String::from("/proc/check()\n    set SpacemanDMM_should_be_pure=1\n");
    for i in 0..64 {
        source.push_str(&format!("    var/local_{i}=0\n"))
    }
    for i in 0..8 {
        source.push_str(&format!("    if(1)\n        var/branch_{i}=0\n"))
    }
    refused_then_recovers(&source, 256 * 1024)
}
