//! Independent legacy byte envelopes for omitted metadata and other target tags.
use crate::{
    ArrayDeclaration, InitializerScope, InitializerTarget, InitializerUnit, InitializerValue,
    InitializerWrite, SymbolId, SymbolicExpression,
};
use std::sync::Arc;

fn append_symbol(bytes: &mut Vec<u8>, symbol: SymbolId) {
    bytes.extend_from_slice(&symbol.bits().to_le_bytes());
}
fn frame(bytes: &mut Vec<u8>, payload: &[u8]) {
    bytes.extend_from_slice(&(payload.len() as u64).to_le_bytes());
    bytes.extend_from_slice(payload);
}
fn assert_write(write: &InitializerWrite, expected: &[u8]) {
    assert_eq!(write.canonical_bytes(), expected);
    assert_eq!(write.canonical_len(), expected.len());
    let mut streamed = Vec::new();
    write.write_canonical(|chunk| streamed.extend_from_slice(chunk));
    assert_eq!(streamed, expected);
}
fn omitted_write(target: InitializerTarget, owner: SymbolId) -> InitializerWrite {
    InitializerWrite {
        source_site: crate::InitializerSite::Declaration,
        target,
        lexical_owner: owner,
        lexical_procedure: None,
        value: InitializerValue::NoAuthoredValue,
        declared_array: None,
        declaration_flags: None,
    }
}

#[test]
fn shared_and_instance_targets_preserve_omitted_metadata_legacy_bytes() {
    let slot = SymbolId::of("slot");
    let declaring = SymbolId::of("/obj/base");
    let receiver = SymbolId::of("/obj/child");
    let name = SymbolId::of("value");
    let lexical = SymbolId::of("/obj/lexical");
    for (target, tag, first, second) in [
        (
            InitializerTarget::Shared {
                slot,
                owner: declaring,
                name,
            },
            0,
            slot,
            declaring,
        ),
        (
            InitializerTarget::Instance {
                declaring_owner: declaring,
                receiver_owner: receiver,
                name,
            },
            1,
            declaring,
            receiver,
        ),
    ] {
        let write = omitted_write(target, lexical);
        let mut expected = b"dm-initializer-write-v3\0".to_vec();
        expected.push(1);
        expected.push(tag);
        for symbol in [first, second, name, lexical] {
            append_symbol(&mut expected, symbol);
        }
        // No lexical procedure, no flags, no declared shape, no authored value.
        expected.extend_from_slice(&[0, 0, 0, 0]);
        assert_write(&write, &expected);
        let unit = InitializerUnit {
            scope: InitializerScope::Global,
            writes: [write].into(),
        };
        let mut unit_bytes = b"dm-initializer-unit-v1\0".to_vec();
        unit_bytes.push(0);
        unit_bytes.extend_from_slice(&1u64.to_le_bytes());
        frame(&mut unit_bytes, &expected);
        let mut streamed = Vec::new();
        unit.write_canonical(|chunk| streamed.extend_from_slice(chunk));
        assert_eq!(unit.canonical_bytes(), unit_bytes);
        assert_eq!(unit.canonical_len(), unit_bytes.len());
        assert_eq!(streamed, unit_bytes);
    }
}

#[test]
fn authored_zero_flags_and_unsized_array_are_distinct_from_absent_fields() {
    let owner = SymbolId::of("/");
    let slot = SymbolId::of("slot");
    let name = SymbolId::of("array");
    let array = Arc::new(ArrayDeclaration {
        element_type: None,
        dimensions: [None].into(),
    });
    let mut array_bytes = b"dm-array-declaration-v1\0".to_vec();
    array_bytes.push(0);
    array_bytes.extend_from_slice(&0u64.to_le_bytes());
    array_bytes.extend_from_slice(&1u64.to_le_bytes());
    array_bytes.push(0);
    assert_eq!(array.canonical_bytes(), array_bytes);
    assert_eq!(array.canonical_len(), array_bytes.len());
    let mut streamed_array = Vec::new();
    array.write_canonical(|chunk| streamed_array.extend_from_slice(chunk));
    assert_eq!(streamed_array, array_bytes);
    let mut write = omitted_write(InitializerTarget::Shared { slot, owner, name }, owner);
    write.declaration_flags = Some(0);
    write.value = InitializerValue::ArrayAllocation(array);
    let mut expected = b"dm-initializer-write-v3\0".to_vec();
    expected.push(1);
    expected.push(0);
    for symbol in [slot, owner, name, owner] {
        append_symbol(&mut expected, symbol);
    }
    expected.extend_from_slice(&[0, 1]);
    expected.extend_from_slice(&0u32.to_le_bytes());
    expected.extend_from_slice(&[0, 2]);
    frame(&mut expected, &array_bytes);
    assert_write(&write, &expected);
    write.declaration_flags = None;
    assert_ne!(write.canonical_bytes(), expected);
}

#[test]
fn empty_expression_and_empty_global_unit_keep_domain_headers_and_counts() {
    let expression = SymbolicExpression { tokens: [].into() };
    let expected = b"dm-symbolic-expression-v1\0";
    let mut streamed = Vec::new();
    expression.write_canonical(|chunk| streamed.extend_from_slice(chunk));
    assert_eq!(expression.canonical_bytes(), expected);
    assert_eq!(expression.canonical_len(), expected.len());
    assert_eq!(streamed, expected);
    let unit = InitializerUnit {
        scope: InitializerScope::Global,
        writes: [].into(),
    };
    let mut expected = b"dm-initializer-unit-v1\0".to_vec();
    expected.push(0);
    expected.extend_from_slice(&0u64.to_le_bytes());
    let mut streamed = Vec::new();
    unit.write_canonical(|chunk| streamed.extend_from_slice(chunk));
    assert_eq!(unit.canonical_bytes(), expected);
    assert_eq!(unit.canonical_len(), expected.len());
    assert_eq!(streamed, expected);
}
