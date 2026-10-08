use super::*;
use dm_ir::{ResolveQuery, ResolvedMeaning};
use std::{collections::BTreeMap, path::Path};
struct Source(&'static str);
impl dm_preprocess::SourceProvider for Source {
    fn read(&self, _: &Path) -> Result<String, String> {
        Ok(self.0.into())
    }
}
struct Host;
impl Resolver for Host {
    fn resolve(&self, query: ResolveQuery) -> ResolvedMeaning {
        ResolvedMeaning::Unsupported(query)
    }
}
struct NoParameters;
impl AbiPolicy for NoParameters {
    fn inputs(
        &self,
        _: UnitIdentity,
        metadata: &ProcedureMetadata,
        _: &SymbolTable,
        _: &SourceLocation,
    ) -> Result<ProcedureInputs, String> {
        if !metadata.signature.parameters.is_empty() || metadata.signature.variadic {
            return Err("no-parameter policy does not know parameter ABI".into());
        }
        Ok(ProcedureInputs::default())
    }
}
fn frontend(source: &'static str) -> ColdFrontend {
    dm_tree::frontend::build(
        Path::new("project.dme"),
        &Source(source),
        &BTreeMap::new(),
        1,
    )
    .unwrap()
}
#[path = "lowering_tests/memo_replay.rs"]
mod memo_replay;
#[path = "lowering_tests/semantics.rs"]
mod semantics;
