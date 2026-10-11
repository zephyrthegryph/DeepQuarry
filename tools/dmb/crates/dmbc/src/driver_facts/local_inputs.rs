//! Sealed current local inputs borrowed from the admitted ABI batch owner.
use crate::lowering::*;
use crate::procedure_policy::PreparedUnit;
use dm_tree::frontend::ColdFrontend;
#[cfg(test)]
#[path = "local_inputs_tests.rs"]
mod tests;
/// This is request-local authority, not a persisted body/source cache. Only the
/// frozen production policy issues it after admitting the complete current ABI
/// graph/member roster. Current body issuance and source binding stay separate.
pub struct LocalInputRoster<'a> {
    frontend: &'a ColdFrontend,
    units: &'a crate::driver_facts::PreparedAbiUnits,
}
impl<'a> LocalInputRoster<'a> {
    pub(super) fn from_admitted(
        frontend: &'a ColdFrontend,
        units: &'a crate::driver_facts::PreparedAbiUnits,
    ) -> Self {
        Self { frontend, units }
    }
    pub(crate) fn metadata(
        &self,
        row: &PreparedBody<'_>,
    ) -> Option<&std::sync::Arc<dm_ir::ProcedureMetadata>> {
        if !row.authenticates(self.frontend) {
            return None;
        }
        self.frontend
            .snapshot
            .tree
            .member(row.body().member)?
            .metadata
            .procedure
            .as_ref()
    }
    pub(crate) fn graph(&self) -> Option<&std::sync::Arc<dm_tree::frontend::CallableAbiGraph>> {
        self.frontend
            .callable_roster()
            .ok()?
            .abi()
            .map(|abi| abi.graph())
    }
    pub(crate) fn prepared(&self, row: &PreparedBody<'_>) -> Option<PreparedUnit> {
        if !row.authenticates(self.frontend) {
            return None;
        }
        let member = row.body().member;
        let ordinal = self.frontend.callable_roster().ok()?.ordinal(member)?;
        let (issued_member, unit) = self.units.entries().get(ordinal)?;
        if *issued_member != member {
            return None;
        }
        crate::procedure_policy::PreparedReplay::from_unit(unit)
            .map(crate::procedure_policy::PreparedReplay::into_view)
    }
}
