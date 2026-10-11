//! Shared static-receipt backing, counted without cloning declaration buffers.
use super::HeapCensus;
impl HeapCensus {
    pub(super) fn static_receipt(
        &mut self,
        receipt: &std::sync::Arc<dm_tree::frontend::IssuedStaticPlan>,
    ) {
        if self.arc_object("startup.static_receipts", receipt) {
            self.arc_text("startup.static_source", receipt.source());
            if let Some(payload) = receipt.retained_relative_payload() {
                if self.arc_object("startup.relative_plan", payload) {
                    self.arc_text("startup.static_source", payload.source());
                    self.static_plan(payload.plan());
                }
            }
        }
    }
    pub(super) fn static_plan(
        &mut self,
        procedure: &dm_tree::procedure_statics::StaticPlan,
    ) -> usize {
        self.vec_payload("startup", &procedure.declarations);
        self.vec_payload("startup", &procedure.origins);
        self.items("startup.executable_bodies", &procedure.executable_body);
        for declaration in &procedure.declarations {
            self.slice("startup.lexical_locals", &declaration.lexical_locals, true);
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
        self.symbol_table_storage("startup.symbols", &procedure.symbols)
    }
}
