//! Immutable resident artifact owners, without fabricated current-source bindings.
#[path = "required_type_artifacts.rs"]
mod required_type_artifacts;
use super::*;
impl HeapCensus {
    pub(crate) fn retained_symbolic_procedure(
        &mut self,
        frozen: &Arc<dm_codegen_byond::FrozenProc>,
        frame: &Arc<crate::symbolic::FrozenFrame>,
        abi: &Option<Arc<crate::procedure_policy::PreparedAbi>>,
    ) {
        self.frozen_code(frozen);
        self.frozen_frame("session_symbolic.frame", frame);
        if let Some(abi) = abi {
            self.abi(abi);
        }
    }
    pub(crate) fn retained_symbolic_helper(
        &mut self,
        frozen: &Arc<dm_codegen_byond::FrozenProc>,
        names: &Vec<String>,
    ) {
        self.frozen_code(frozen);
        self.strings("session_symbolic.helpers", names);
    }
    pub(crate) fn retained_symbolic_ledger(
        &mut self,
        reads: &Arc<[crate::lowering_memo::ResolverRead]>,
        versions: &Arc<[(dm_ir::ReadDomain, u128)]>,
    ) {
        if self.slice("session_symbolic.reads", reads, true) {
            for read in reads.iter() {
                super::resident_weight::answer(self, &read.answer);
            }
        }
        self.slice("session_symbolic.versions", versions, true);
    }
}
