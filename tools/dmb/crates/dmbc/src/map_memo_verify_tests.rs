use super::*;
use dm_ir::{ResolveQuery as Q, ResolvedMeaning as M, SymbolId};
struct Host;
impl Resolver for Host {
    fn resolve(&self, query: Q) -> M {
        match query {
            Q::Type(path) => M::Symbol(path),
            Q::Ancestry(_) => M::Symbols(vec![SymbolId::of("/datum")].into()),
            _ => M::Unsupported(query),
        }
    }
}
fn captured(occurrence: u32) -> CapturedMap {
    CapturedMap {
        path: Arc::new("maps/verify.dmm".into()),
        include_occurrence: occurrence,
        source: Arc::from("\"a\"=(/obj,/turf,/area)\n(1,1,1)={\"a\"}"),
    }
}
fn defaults() -> WorldDefaults {
    WorldDefaults {
        turf: SymbolId::of("/turf"),
        area: SymbolId::of("/area"),
        minimum_dimensions: [1; 3],
    }
}
#[test]
fn verified_map_hits_use_current_occurrence_and_original_geometry_receipt() {
    let owner = Arc::new(RetainedMaps::current_revision());
    let first = MapMemo::with_resident(1, owner.clone(), None);
    let plan = first.parse(captured(1)).unwrap();
    let expected = first.project(&[plan], defaults(), &Host).unwrap();
    assert!(first.publish_successful());
    let mut current = MapMemo::with_resident(1, owner, None);
    current.verification = crate::lowering_memo::VerifyPolicy::all();
    let plan = current.parse(captured(9)).unwrap();
    assert_eq!(plan.captured.include_occurrence, 9);
    let actual = current.project(&[plan], defaults(), &Host).unwrap();
    assert!(same_projection(&expected, &actual));
    assert_eq!(current.map_verification_counts(), (2, 0));
    assert!(current.publish_successful());
}
#[test]
fn corrupt_admitted_map_hits_fail_closed_before_successful_publication() {
    let mut memo = MapMemo::with_resident(1, Arc::new(RetainedMaps::current_revision()), None);
    memo.verification = crate::lowering_memo::VerifyPolicy::all();
    let mut plan = dm_tree::maps::plan(captured(1)).unwrap();
    plan.template_origins = Arc::from([]);
    let key: Arc<[u8]> = memo.parse_locator(&plan.captured).into();
    memo.admit_retained_parse(key, &plan);
    let failure = memo.parse(captured(2)).unwrap_err();
    assert_eq!(failure.kind, dm_tree::maps::DiagnosticKind::Internal);
    assert!(!memo.publish_successful());

    let mut memo = MapMemo::with_resident(1, Arc::new(RetainedMaps::current_revision()), None);
    memo.verification = crate::lowering_memo::VerifyPolicy::all();
    let plan = dm_tree::maps::plan(captured(1)).unwrap();
    let value = crate::map_projection::project(
        &[plan.clone()],
        defaults(),
        &crate::map_projection::ResolverClassifier(&Host),
    )
    .unwrap();
    let key = retained::geometry_locator(1, &[plan.clone()], defaults());
    memo.admit_retained_geometry(key, &[plan.clone()], &value, Vec::new(), Vec::new());
    assert!(matches!(
        memo.project(&[plan], defaults(), &Host),
        Err(crate::map_projection::Error::Verification(_))
    ));
    assert_eq!(memo.map_verification_counts(), (1, 1));
    assert!(!memo.publish_successful());
}

#[test]
fn verified_disk_hydrated_map_geometry_compares_original_canonical_answers() {
    let memo = MapMemo::with_resident(1, Arc::new(RetainedMaps::current_revision()), None);
    let plan = dm_tree::maps::plan(captured(4)).unwrap();
    let maps = [plan];
    let recorder = RecordingResolver::new(&Host);
    let value = crate::map_projection::project(
        &maps,
        defaults(),
        &crate::map_projection::ResolverClassifier(&recorder),
    )
    .unwrap();
    let reads = recorder.reads();
    let key = geometry_key(1, &maps, defaults());
    let bytes = wire::encode_geometry(&key, &value, &reads).unwrap();
    let (hydrated, original) = wire::admit_geometry(&bytes, &key, &maps, defaults(), &Host)
        .unwrap()
        .unwrap();
    assert!(memo
        .verify_geometry(&maps, defaults(), &Host, &hydrated, &original)
        .is_ok());
    let mut changed = original;
    changed[0].answer = M::Missing;
    assert!(matches!(
        memo.verify_geometry(&maps, defaults(), &Host, &hydrated, &changed),
        Err(crate::map_projection::Error::Verification(_))
    ));
    assert!(!memo.publish_successful());
}
