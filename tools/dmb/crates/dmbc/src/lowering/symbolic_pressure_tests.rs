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
    let weight = charge(&key, &record, usize::MAX).expect("all immutable payloads are exposed");
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
    let before = charge(&key, &record, usize::MAX).unwrap();
    Arc::get_mut(&mut record)
        .unwrap()
        .relative_debug
        .reserve(10000);
    assert!(charge(&key, &record, usize::MAX).unwrap() > before + 10000);
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

#[test]
fn compact_charge_matches_diagnostic_capacity_and_declines_before_pointer_growth() {
    let record = record();
    let key = Arc::clone(&record.key);
    let expected = {
        let mut census = HeapCensus::new("diagnostic");
        census.slice("compact_symbolic.locator", &key, true);
        census_record(&record, &mut census);
        census.finish_compact_symbolic_charge().unwrap()
    };
    assert_eq!(charge(&key, &record, expected), Some(expected));
    assert!(charge(&key, &record, expected - 1).is_none());
    // A huge exposed capacity is refused before adding its address to the
    // scratch ledger; later nested observations cannot regrow that ledger.
    let mut census = HeapCensus::compact_symbolic_charge(128);
    assert!(!census.exposed_buffer("oversized", 1, 1024, 1024));
    for address in 2..10000 {
        assert!(!census.exposed_buffer("later", address, 1, 1));
    }
    assert!(census.finish_compact_symbolic_charge().is_none());
}

#[test]
fn shared_pressure_footprint_preserves_exact_unique_and_shared_backing() {
    let first = record();
    let second = Arc::new(super::super::super::Record {
        local: None,
        recipe: None,
        key: Arc::from([4u8, 5, 6]),
        reads: first.reads.clone(),
        versions: Arc::clone(&first.versions),
        value: match &first.value {
            super::super::super::RecordValue::Executable(value) => {
                super::super::super::RecordValue::Executable(Arc::clone(value))
            }
            _ => unreachable!(),
        },
        relative_debug: first.relative_debug.clone(),
        required_types: Arc::clone(&first.required_types),
        modified_recipes: Arc::clone(&first.modified_recipes),
    });
    let a = shared_charge(&first.key, &first, usize::MAX).unwrap();
    let b = shared_charge(&second.key, &second, usize::MAX).unwrap();
    let left: std::collections::BTreeMap<_, _> =
        a.iter().map(|item| (item.address, item.bytes)).collect();
    let shared: usize = b
        .iter()
        .filter_map(|item| {
            left.get(&item.address).map(|old| {
                assert_eq!(*old, item.bytes);
                item.bytes
            })
        })
        .sum();
    assert!(shared > 0, "actual frozen code/frame owners must be shared");
    let standalone_a: usize = a.iter().map(|item| item.bytes).sum();
    assert_eq!(
        standalone_a,
        charge(&first.key, &first, usize::MAX).unwrap()
    );
    assert!(
        shared < standalone_a,
        "record and current debug buffers remain unique"
    );
    assert!(shared_charge(&first.key, &first, 0).is_none());
}
