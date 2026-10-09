use super::*;
use crate::ExpressionToken;
use dm_syntax::{Span, TokenKind};

fn framed(bytes: &mut Vec<u8>, payload: &[u8]) {
    bytes.extend_from_slice(&(payload.len() as u64).to_le_bytes());
    bytes.extend_from_slice(payload);
}

#[test]
fn canonical_sinks_match_fixed_format_field_fixture_including_adjacency_and_arrays() {
    let plus = SymbolId::of("+");
    let expression = SymbolicExpression {
        tokens: [
            ExpressionToken {
                kind: TokenKind::Operator,
                text: plus,
                relative_span: Span::new(0, 1),
            },
            ExpressionToken {
                kind: TokenKind::Operator,
                text: plus,
                relative_span: Span::new(1, 2),
            },
            ExpressionToken {
                kind: TokenKind::Operator,
                text: plus,
                relative_span: Span::new(4, 5),
            },
        ]
        .into(),
    };
    let mut expression_bytes = b"dm-symbolic-expression-v1\0".to_vec();
    for adjacency in [0, 1, 2] {
        expression_bytes.extend_from_slice(&[adjacency, 5]);
        expression_bytes.extend_from_slice(&plus.bits().to_le_bytes());
    }
    assert_eq!(expression.canonical_bytes(), expression_bytes);
    assert_eq!(expression.canonical_len(), expression_bytes.len());
    let element = SymbolId::of("/obj/雪");
    let array = Arc::new(ArrayDeclaration {
        dimensions: [None, Some(expression.clone())].into(),
        element_type: Some(element),
    });
    let mut array_bytes = b"dm-array-declaration-v1\0".to_vec();
    array_bytes.push(1);
    array_bytes.extend_from_slice(&element.bits().to_le_bytes());
    array_bytes.extend_from_slice(&2u64.to_le_bytes());
    array_bytes.extend_from_slice(&[0, 1]);
    framed(&mut array_bytes, &expression_bytes);
    assert_eq!(array.canonical_bytes(), array_bytes);
    assert_eq!(array.canonical_len(), array_bytes.len());
    let procedure = ProcedureIdentity {
        owner: SymbolId::of("/"),
        name: SymbolId::of("雪"),
        verb: true,
        occurrence: 7,
    };
    let identity = ProcedureStaticIdentity {
        procedure,
        name: SymbolId::of("long_local_name"),
    };
    let write = InitializerWrite {
        target: InitializerTarget::ProcedureStatic(identity),
        lexical_owner: element,
        lexical_procedure: Some(procedure),
        value: InitializerValue::Expression(expression),
        declared_array: Some(array),
        declaration_flags: Some(0x12345678),
    };
    let mut identity_bytes = b"dm-procedure-static-identity-v1\0".to_vec();
    identity_bytes.extend_from_slice(&procedure.owner.bits().to_le_bytes());
    identity_bytes.extend_from_slice(&procedure.name.bits().to_le_bytes());
    identity_bytes.push(1);
    identity_bytes.extend_from_slice(&7u32.to_le_bytes());
    identity_bytes.extend_from_slice(&identity.name.bits().to_le_bytes());
    let mut expected = b"dm-initializer-write-v2\0".to_vec();
    expected.push(2);
    framed(&mut expected, &identity_bytes);
    expected.extend_from_slice(&element.bits().to_le_bytes());
    expected.push(1);
    expected.extend_from_slice(&procedure.owner.bits().to_le_bytes());
    expected.extend_from_slice(&procedure.name.bits().to_le_bytes());
    expected.push(1);
    expected.extend_from_slice(&7u32.to_le_bytes());
    expected.push(1);
    expected.extend_from_slice(&0x12345678u32.to_le_bytes());
    expected.push(1);
    framed(&mut expected, &array_bytes);
    expected.push(1);
    framed(&mut expected, &expression_bytes);
    assert_eq!(write.canonical_len(), expected.len());
    assert_eq!(write.canonical_bytes(), expected);
    let mut streamed = Vec::new();
    write.write_canonical(|chunk| streamed.extend_from_slice(chunk));
    assert_eq!(streamed, expected);
    let unit = InitializerUnit {
        scope: InitializerScope::Instance(element),
        writes: [write].into(),
    };
    let mut unit_bytes = b"dm-initializer-unit-v1\0".to_vec();
    unit_bytes.push(1);
    unit_bytes.extend_from_slice(&element.bits().to_le_bytes());
    unit_bytes.extend_from_slice(&1u64.to_le_bytes());
    framed(&mut unit_bytes, &expected);
    assert_eq!(unit.canonical_len(), unit_bytes.len());
    assert_eq!(unit.canonical_bytes(), unit_bytes);
}

#[test]
fn structural_lengths_equal_emitted_bytes_for_all_dimension_shapes() {
    let empty = SymbolicExpression {
        tokens: Arc::from([]),
    };
    let unicode = SymbolicExpression {
        tokens: [ExpressionToken {
            kind: TokenKind::String,
            text: SymbolId::of("雪\0binary"),
            relative_span: Span::new(0, 9),
        }]
        .into(),
    };
    for expression in [&empty, &unicode] {
        let mut length = 0;
        expression.write_canonical(|chunk| length += chunk.len());
        assert_eq!(expression.canonical_len(), length);
    }
    for dimensions in [
        vec![],
        vec![None],
        vec![Some(empty.clone())],
        vec![None, Some(unicode.clone()), Some(empty.clone()), None],
    ] {
        for element_type in [None, Some(SymbolId::of("/obj/雪"))] {
            let array = ArrayDeclaration {
                dimensions: dimensions.clone().into(),
                element_type,
            };
            let mut length = 0;
            array.write_canonical(|chunk| length += chunk.len());
            assert_eq!(array.canonical_len(), length);
            assert_eq!(array.canonical_len(), array.canonical_bytes().len());
        }
    }
}

#[path = "initializer_codec_absent_tests.rs"]
mod absent_tests;
