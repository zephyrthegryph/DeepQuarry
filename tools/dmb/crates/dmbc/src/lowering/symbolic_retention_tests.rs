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
        key: vec![1, 2, 3],
        reads: Arc::from([]),
        versions: Arc::from([]),
        artifact: contribution.shared_artifact(),
        relative_debug: vec![0],
        required_types: contribution.required_types().to_vec(),
        modified_recipes: Vec::new(),
    });
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
