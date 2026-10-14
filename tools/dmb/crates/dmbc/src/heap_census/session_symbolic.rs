//! Immutable resident artifact owners, without fabricated current-source bindings.
#[path = "required_type_artifacts.rs"]
mod required_type_artifacts;
use super::*;
impl HeapCensus {
    pub(crate) fn shared_frozen_code(&mut self, code: &Arc<dm_codegen_byond::FrozenProc>) {
        self.frozen_code(code);
    }
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
        names: &Arc<Vec<String>>,
    ) {
        self.frozen_code(frozen);
        self.arc_object("helper.local_names", names);
        self.strings("session_symbolic.helpers", names);
    }
    pub(crate) fn retained_symbolic_ledger(
        &mut self,
        reads: &dm_session::Receipt<dm_ir::ResolveQuery, dm_ir::ResolvedMeaning, dm_ir::ReadDomain>,
        versions: &Arc<[(dm_ir::ReadDomain, u128)]>,
    ) {
        if self.receipt("session_symbolic.reads", reads) {
            for read in reads.iter() {
                super::resident_weight::answer(self, &read.answer);
            }
        }
        self.slice("session_symbolic.versions", versions, true);
    }
}
