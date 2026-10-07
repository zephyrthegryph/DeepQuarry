//! Formal shape policy, independent of physical argument/local table IDs.
//! Unsized [] declares a list parameter; it does not allocate a fresh list.
use crate::procedure_abi::AbiError;
use dm_ir::{Parameter, SymbolId};

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum FormalShape {
    Scalar { declared_type: Option<SymbolId> },
    UnsizedList { element_type: Option<SymbolId> },
}
pub fn formal_shape(parameter: &Parameter) -> Result<FormalShape, AbiError> {
    if parameter.flags & !2 != 0 {
        // Const is a lexical binding write constraint, not an argument type
        // bit. Other modifiers still need a separately certified policy.
        return Err(AbiError(
            "parameter declaration modifiers require lexical write-constraint policy".into(),
        ));
    }
    match &parameter.array {
        None => Ok(FormalShape::Scalar {
            declared_type: parameter.declared_type,
        }),
        Some(array) if array.dimensions.len() == 1 && array.dimensions[0].is_none() => {
            if parameter.declared_type != Some(SymbolId::of("/list")) {
                return Err(AbiError(
                    "unsized parameter array lacks certified list declared type".into(),
                ));
            }
            Ok(FormalShape::UnsizedList {
                element_type: array.element_type,
            })
        }
        Some(_) => Err(AbiError(
            "sized or mixed formal array allocation semantics are unsupported".into(),
        )),
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    use dm_ir::ArrayDeclaration;
    use std::sync::Arc;
    #[test]
    fn unsized_formal_retains_element_type_without_allocating_or_erasing_modifiers() {
        let mut parameter = Parameter {
            name: SymbolId::of("values"),
            declared_type: Some(SymbolId::of("/list")),
            list_element_type: None,
            flags: 0,
            array: Some(Arc::new(ArrayDeclaration {
                dimensions: Arc::from([None]),
                element_type: Some(SymbolId::of("/obj")),
            })),
            default: None,
            input_annotation: None,
            source_expression: None,
            relative_span: dm_syntax::Span::new(0, 8),
        };
        assert_eq!(
            formal_shape(&parameter).unwrap(),
            FormalShape::UnsizedList {
                element_type: Some(SymbolId::of("/obj"))
            }
        );
        parameter.flags = 2;
        assert!(formal_shape(&parameter).is_ok());
        parameter.flags = 1;
        assert!(formal_shape(&parameter).is_err());
        parameter.flags = 0;
        parameter.declared_type = None;
        assert!(formal_shape(&parameter).is_err());
    }
}
