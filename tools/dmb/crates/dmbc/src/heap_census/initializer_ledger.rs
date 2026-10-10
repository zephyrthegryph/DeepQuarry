//! Current classified initializer ownership, with shared input backing deduplicated.
use super::*;
use crate::initializer_policy::{ClassifiedInitializers, DefaultValue, RuntimeValue};
impl HeapCensus {
    pub(crate) fn initializer_ledger(&mut self, classified: &ClassifiedInitializers) {
        let owner = "initializer_ledger";
        if self.vec_payload(owner, &classified.accepted) {
            for accepted in classified.accepted.iter().flatten() {
                accepted.visit(|value| super::initializer_artifacts::classification(self, value));
            }
        }
        if self.vec_payload(owner, &classified.writes) {
            for fact in &classified.writes {
                match &fact.write.value {
                    dm_ir::InitializerValue::Expression(expression) => {
                        self.expression(owner, expression)
                    }
                    dm_ir::InitializerValue::ArrayAllocation(array) => self.array(owner, array),
                    dm_ir::InitializerValue::NoAuthoredValue => (),
                }
                if let Some(array) = &fact.write.declared_array {
                    self.array(owner, array);
                }
                match &fact.default {
                    DefaultValue::Transform(_) => {}
                    DefaultValue::Scalar(value) => self.semantic_value(owner, value),
                    DefaultValue::InitializerExpression { canonical, .. } => {
                        self.slice(owner, canonical, true);
                    }
                }
                match &fact.runtime_value {
                    Some(RuntimeValue::Expression(expression)) => {
                        let owner = "initializer_ledger.runtime_ast";
                        if self.arc_object(owner, expression) {
                            self.typed_expression(owner, expression);
                        }
                    }
                    Some(RuntimeValue::SizedArray(dimensions)) => {
                        self.slice(owner, dimensions, true);
                    }
                    None => (),
                }
            }
        }
        if self.vec_payload(owner, &classified.groups) {
            for group in &classified.groups {
                self.vec_payload(owner, &group.writes);
            }
        }
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn ledger_aliases_deduplicate_inline_owners_and_nested_runtime_heap() {
        use crate::initializer_policy::{ClassifiedWrite, RuntimeGroup};
        let classified = ClassifiedInitializers {
            accepted: Vec::new(),
            writes: vec![ClassifiedWrite {
                source_ordinal: 0,
                write: dm_ir::InitializerWrite {
                    target: dm_ir::InitializerTarget::Shared {
                        owner: dm_ir::SymbolId::of("/"),
                        name: dm_ir::SymbolId::of("value"),
                        slot: dm_ir::SymbolId::of("/value"),
                    },
                    lexical_owner: dm_ir::SymbolId::of("/"),
                    lexical_procedure: None,
                    declaration_flags: Some(0),
                    declared_array: None,
                    value: dm_ir::InitializerValue::NoAuthoredValue,
                },
                default: DefaultValue::Scalar(dm_ir::SemanticValue::Null),
                phase: None,
                runtime_value: Some(RuntimeValue::Expression(Arc::new(
                    dm_syntax::parse_expression("list(1,2)").expr.unwrap(),
                ))),
            }],
            groups: vec![RuntimeGroup {
                receiver: None,
                writes: vec![0],
            }],
        };
        let mut one = HeapCensus::new("one");
        one.initializer_ledger(&classified);
        let expected = one.finish().unique_known_capacity_bytes;
        let mut two = HeapCensus::new("two");
        two.initializer_ledger(&classified);
        two.initializer_ledger(&classified);
        let report = two.finish();
        assert_eq!(report.unique_known_capacity_bytes, expected);
        assert!(report
            .owners
            .iter()
            .any(|row| row.owner == "initializer_ledger.runtime_ast"
                && row.unique_known_capacity_bytes > 0));
        assert!(report.owners.iter().any(|row| row.shared_encounters > 0));
    }
}
