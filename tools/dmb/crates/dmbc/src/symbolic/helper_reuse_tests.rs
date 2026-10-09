use super::*;
use crate::lowering::LoweringConfig;
use crate::procedure_policy::AbiContext;
use crate::procedure_policy::{
    CapturedConstantEvaluator, CapturedInheritedFacts, CapturedProcedurePolicy, InheritedLayout,
};
struct Source(&'static str);
impl dm_preprocess::SourceProvider for Source {
    fn read(&self, _: &std::path::Path) -> Result<String, String> {
        Ok(self.0.into())
    }
}
struct Host;
impl dm_ir::Resolver for Host {
    fn resolve(&self, q: dm_ir::ResolveQuery) -> dm_ir::ResolvedMeaning {
        dm_ir::ResolvedMeaning::Unsupported(q)
    }
}
struct Facts;
impl CapturedInheritedFacts for Facts {
    fn inherited(
        &self,
        _: &AbiContext<'_>,
    ) -> Result<InheritedLayout, dm_codegen_byond::procedure_abi::AbiError> {
        Ok(InheritedLayout::Fresh)
    }
}
impl CapturedConstantEvaluator for Facts {
    fn evaluate(
        &self,
        _: &dm_ir::SymbolicExpression,
        _: &AbiContext<'_>,
    ) -> Result<dm_ir::SemanticValue, dm_codegen_byond::procedure_abi::AbiError> {
        Err(dm_codegen_byond::procedure_abi::AbiError::unsupported(
            "no constants in fixture",
        ))
    }
}
fn frontend(source: &'static str) -> dm_tree::frontend::ColdFrontend {
    dm_tree::frontend::build(
        std::path::Path::new("project.dme"),
        &Source(source),
        &Default::default(),
        1,
    )
    .unwrap()
}
#[test]
fn frozen_helpers_share_code_but_rebind_current_header_origins_and_reject_wrong_frame() {
    let old = frontend("/proc/source(value in list(value))\n    return value\n");
    let moved = frontend("\n/proc/source(value in list(value))\n    return value\n");
    let facts = Facts;
    let policy = CapturedProcedurePolicy {
        evaluator: &facts,
        inherited: &facts,
        resource_search_context: None,
    };
    let mut old_batch =
        crate::lowering::lower_frontend(&old, &Host, &policy, LoweringConfig::default());
    let mut moved_batch =
        crate::lowering::lower_frontend(&moved, &Host, &policy, LoweringConfig::default());
    assert!(
        old_batch.diagnostics.is_empty(),
        "{:?}",
        old_batch.diagnostics
    );
    assert!(
        moved_batch.diagnostics.is_empty(),
        "{:?}",
        moved_batch.diagnostics
    );
    let old_unit = old_batch.units.remove(0);
    let current = moved_batch.units.remove(0);
    let prepared = crate::procedure_policy::PreparedUnit {
        inputs: dm_codegen_byond::ProcedureInputs {
            parameters: vec!["value".into()],
            ..Default::default()
        },
        executable_body: Vec::new(),
        abi: current.abi.clone(),
    };
    let frozen = prepare_contribution(
        old_unit,
        old.snapshot.tree.symbols(),
        &Default::default(),
        &ReferenceBindings::default(),
        false,
    )
    .unwrap();
    assert!(frozen.is_reusable());
    let artifact = frozen.shared_artifact();
    let rebound = PreparedContribution::rebind(
        &artifact,
        &moved,
        &moved.bodies[0],
        &prepared,
        current.debug_origins.clone(),
        frozen.required_types(),
    )
    .unwrap();
    assert!(Arc::ptr_eq(&artifact, &rebound.shared_artifact()));
    let mut early = link_prepared_artifact_tables(
        vec![rebound],
        moved.snapshot.tree.symbols(),
        &ReferenceBindings::default(),
        LinkInventory::default(),
        Vec::new(),
    )
    .unwrap();
    assert_eq!(early.helpers.len(), 1);
    assert_eq!(
        early.helpers.remove(0).debug_origins.to_owned_origins(),
        current.source_helpers[0].debug_origins
    );
    let wrong = crate::procedure_policy::PreparedUnit {
        inputs: Default::default(),
        executable_body: Vec::new(),
        abi: prepared.abi.clone(),
    };
    assert!(PreparedContribution::rebind(
        &artifact,
        &moved,
        &moved.bodies[0],
        &wrong,
        current.debug_origins,
        frozen.required_types()
    )
    .is_none());
}
