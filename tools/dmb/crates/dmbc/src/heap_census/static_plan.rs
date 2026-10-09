//! Shared static-receipt backing, counted without cloning declaration buffers.
use super::HeapCensus;
impl HeapCensus {
    pub(super) fn static_plan(&mut self, procedure: &dm_tree::procedure_statics::StaticPlan) {
        self.vec_payload("startup", &procedure.declarations);
        self.vec_payload("startup", &procedure.origins);
        self.items("startup.executable_bodies", &procedure.executable_body);
        for declaration in &procedure.declarations {
            match &declaration.initializer {
                dm_ir::InitializerValue::Expression(expression) => {
                    self.expression("startup", expression)
                }
                dm_ir::InitializerValue::ArrayAllocation(array) => self.array("startup", array),
                dm_ir::InitializerValue::NoAuthoredValue => (),
            }
            if let Some(array) = &declaration.declared_array {
                self.array("startup", array);
            }
        }
    }
}
