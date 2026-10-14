//! Actual shared full initializer input ownership, deduplicated by Arc address.
use super::*;
impl HeapCensus {
    pub(super) fn shared_initializer_write(
        &mut self,
        owner: &str,
        write: &Arc<dm_ir::InitializerWrite>,
    ) {
        if !self.arc_object(owner, write) {
            return;
        }
        match &write.value {
            dm_ir::InitializerValue::Expression(expr) => self.expression(owner, expr),
            dm_ir::InitializerValue::ArrayAllocation(array) => self.array(owner, array),
            dm_ir::InitializerValue::NoAuthoredValue => (),
        }
        if let Some(array) = &write.declared_array {
            self.array(owner, array);
        }
    }
}
