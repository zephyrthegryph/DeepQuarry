use super::*;
use std::{path::Path, sync::Arc};
struct Source;
impl dm_preprocess::SourceProvider for Source {
    fn read(&self, _: &Path) -> Result<String, String> {
        Ok("/proc/read()\n    return \"hello\"\n".into())
    }
}
struct Host;
impl dm_ir::Resolver for Host {
    fn resolve(&self, q: dm_ir::ResolveQuery) -> dm_ir::ResolvedMeaning {
        dm_ir::ResolvedMeaning::Unsupported(q)
    }
}
struct Policy;
impl crate::lowering::AbiPolicy for Policy {
    fn inputs(
        &self,
        _: crate::lowering::UnitIdentity,
        _: &dm_ir::ProcedureMetadata,
        _: &dm_ir::SymbolTable,
        _: &dm_tree::frontend::SourceLocation,
    ) -> Result<dm_codegen_byond::ProcedureInputs, String> {
        Ok(Default::default())
    }
}
fn record() -> Arc<super::super::super::Record> {
    let frontend =
        dm_tree::frontend::build(Path::new("project.dme"), &Source, &Default::default(), 1)
            .unwrap();
    let mut lowered =
        crate::lowering::lower_frontend(&frontend, &Host, &Policy, Default::default());
    assert!(lowered.diagnostics.is_empty());
    let contribution = crate::symbolic::prepare_contribution(
        lowered.units.remove(0),
        frontend.snapshot.tree.symbols(),
        &Default::default(),
        &crate::symbolic::ReferenceBindings::default(),
        false,
    )
    .unwrap();
    Arc::new(super::super::super::Record {
        local: None,
        recipe: None,
        key: Arc::from([1u8, 2, 3]),
        reads: Vec::new().into(),
        versions: Arc::from([]),
        value: super::super::super::RecordValue::Executable(contribution.shared_artifact()),
        relative_debug: vec![crate::debug_sources::RelativeDebugAnchor::AtBodyOffset(0)],
        required_types: Arc::clone(contribution.required_types_owner()),
        modified_recipes: Arc::clone(contribution.modified_recipes_owner().unwrap()),
    })
}
#[test]
fn pressure_keeps_actual_compact_code_and_rejects_undercharged_budget() {
    let record = record();
    let key = Arc::clone(&record.key);
    let weight = charge(&key, &record).expect("all immutable payloads are exposed");
    assert!(weight > 0);
    let memo = SessionSymbolicMemo::current_revision();
    let request = memo.for_request(true);
    let artifact = match &record.value {
        super::super::super::RecordValue::Executable(value) => Arc::clone(value),
        _ => unreachable!(),
    };
    // Insert through the production request lease, then publish it.
    assert!(request.insert_record(
        crate::lowering::UnitIdentity {
            owner: dm_ir::SymbolId::of("/"),
            name: dm_ir::SymbolId::of("read"),
            namespace: crate::lowering::Namespace::Proc,
            occurrence: 0,
        },
        Arc::try_unwrap(record).ok().unwrap()
    ));
    assert!(request.publish_successful());
    let kept = memo.compact_for_pressure(usize::MAX);
    assert_eq!(kept.retained_entries, 1);
    assert!(kept.payload_bytes >= weight);
    assert!(kept.index_logical_bytes > 0);
    assert_eq!(
        kept.charged_bytes,
        kept.payload_bytes + kept.index_logical_bytes
    );
    assert_eq!(memo.retention_stats().records, 1);
    let evicted = memo.compact_for_pressure(kept.charged_bytes - 1);
    assert_eq!(evicted.evicted_entries, 1);
    assert_eq!(memo.retention_stats().records, 0);
    // Escaped readers remain valid after core eviction.
    let mut census = HeapCensus::new("escaped");
    crate::symbolic::ReusableProcedureArtifact::retained_census(&artifact, &mut census);
    assert!(census.finish().unique_known_capacity_bytes > 0);
}
#[test]
fn debug_payload_capacity_is_charged_before_retention() {
    let mut record = record();
    let key = Arc::clone(&record.key);
    let before = charge(&key, &record).unwrap();
    Arc::get_mut(&mut record)
        .unwrap()
        .relative_debug
        .reserve(10000);
    assert!(charge(&key, &record).unwrap() > before + 10000);
}

#[test]
fn payload_allocation_allowance_deduplicates_shared_and_empty_encounters() {
    let bytes = vec![7u8; 11];
    let make = |repeat: bool| {
        let mut census = HeapCensus::new("payload");
        census.exposed_buffer(
            "payload",
            bytes.as_ptr() as usize,
            bytes.len(),
            bytes.capacity(),
        );
        if repeat {
            census.exposed_buffer(
                "payload",
                bytes.as_ptr() as usize,
                bytes.len(),
                bytes.capacity(),
            );
            census.exposed_buffer("empty", 1, 0, 0);
        }
        census.finish_compact_symbolic_charge().unwrap()
    };
    assert_eq!(make(false), bytes.capacity() + 64);
    assert_eq!(make(true), make(false));
}
#[test]
fn unknown_nested_payload_still_declines_pressure_retention() {
    let mut census = HeapCensus::new("unknown");
    census.unknown("nested", "private nested capacity is not exposed");
    assert!(census.finish_compact_symbolic_charge().is_none());
}
