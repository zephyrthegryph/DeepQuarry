use super::*;
use crate::lowering::{AbiPolicy, LoweringConfig, UnitIdentity};
use dm_codegen_byond::ProcedureInputs;
use dm_ir::{ProcedureMetadata, ResolveQuery, ResolvedMeaning, Resolver, SymbolTable};
use std::{path::Path, sync::Arc};
struct Source;
impl dm_preprocess::SourceProvider for Source {
    fn read(&self, _: &Path) -> Result<String, String> {
        Ok("/proc/read()\n    return \"hello\"\n".into())
    }
}
struct Host;
impl Resolver for Host {
    fn resolve(&self, query: ResolveQuery) -> ResolvedMeaning {
        ResolvedMeaning::Unsupported(query)
    }
}
struct Policy;
#[test]
fn replay_meaning_fast_equality_preserves_canonical_fallback_and_rejection() {
    let data = Arc::new(dm_ir::DeclarationMeaning {
        inherited_opaque: None,
        declared_type: None,
        list_element_type: None,
        display_name: None,
        flags: 0,
        procedure: None,
        array: None,
        initializer: None,
        declared_initializer: None,
        resolved_constant: None,
        canonical: Arc::from([]),
    });
    let previous = ResolvedMeaning::Member {
        owner: dm_ir::SymbolId::of("/probe"),
        name: dm_ir::SymbolId::of("value"),
        fingerprint: 1,
        data: Arc::clone(&data),
    };
    assert!(super::super::same_meaning(&previous, &previous));
    let mut current = previous.clone();
    if let ResolvedMeaning::Member { fingerprint, .. } = &mut current {
        *fingerprint = 2;
    }
    assert_ne!(current, previous);
    assert!(super::super::same_meaning(&current, &previous));
    if let ResolvedMeaning::Member { data, .. } = &mut current {
        Arc::make_mut(data).flags = 2;
    }
    assert!(!super::super::same_meaning(&current, &previous));
}
impl AbiPolicy for Policy {
    fn inputs(
        &self,
        _: UnitIdentity,
        _: &ProcedureMetadata,
        _: &SymbolTable,
        _: &dm_tree::frontend::SourceLocation,
    ) -> Result<ProcedureInputs, String> {
        Ok(ProcedureInputs::default())
    }
}
#[test]
fn symbolic_census_deduplicates_shared_records_and_counts_pruned_members() {
    let frontend =
        dm_tree::frontend::build(Path::new("project.dme"), &Source, &Default::default(), 1)
            .unwrap();
    let mut lowered =
        crate::lowering::lower_frontend(&frontend, &Host, &Policy, LoweringConfig::default());
    assert!(lowered.diagnostics.is_empty(), "{:?}", lowered.diagnostics);
    let contribution = crate::symbolic::prepare_contribution(
        lowered.units.remove(0),
        frontend.snapshot.tree.symbols(),
        &Default::default(),
        &crate::symbolic::ReferenceBindings::default(),
        false,
    )
    .unwrap();
    let identity = contribution.identity();
    let record = Arc::new(super::super::Record {
        key: vec![1, 2, 3].into(),
        reads: Vec::new().into(),
        versions: Arc::from([]),
        value: super::super::RecordValue::Executable(contribution.shared_artifact()),
        relative_debug: vec![0],
        required_types: Arc::clone(contribution.required_types_owner()),
        modified_recipes: Arc::clone(contribution.modified_recipes_owner().unwrap()),
    });
    assert!(Arc::ptr_eq(
        &record.required_types,
        contribution.required_types_owner()
    ));
    assert!(Arc::ptr_eq(
        &record.modified_recipes,
        contribution.modified_recipes_owner().unwrap()
    ));
    let memo = SessionSymbolicMemo::default();
    memo.records
        .lock()
        .unwrap()
        .insert(identity, Arc::clone(&record));
    let one = memo.retention_stats();
    assert_eq!(one.records, 1);
    assert!(one.known_capacity_bytes > 0);
    let extra = UnitIdentity {
        occurrence: identity.occurrence + 1,
        ..identity
    };
    memo.records.lock().unwrap().insert(extra, record);
    let shared = memo.retention_stats();
    assert_eq!(shared.records, 2);
    assert_eq!(shared.known_capacity_bytes, one.known_capacity_bytes);
    let mut combined = HeapCensus::new("combined_boundary");
    assert_eq!(memo.retained_census(&mut combined), 2);
    assert_eq!(memo.retained_census(&mut combined), 2);
    assert_eq!(
        combined.finish().unique_known_capacity_bytes,
        shared.known_capacity_bytes
    );
    assert!(shared
        .owners
        .owners
        .iter()
        .any(|owner| owner.shared_encounters > 0));
    assert!(shared
        .owners
        .owners
        .iter()
        .any(|owner| !owner.unknown.is_empty()));
    memo.retain_current(&frontend);
    let pruned = memo.retention_stats();
    assert_eq!(pruned.records, 1);
    assert_eq!(pruned.pruned_members, 1);
    assert_eq!(pruned.known_capacity_bytes, one.known_capacity_bytes);
    memo.retain_current(&frontend);
    assert_eq!(memo.retention_stats().pruned_members, 1);
}
