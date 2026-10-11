//! Explicit operand contracts corroborated by the pinned 516.1687 engine image.
//! Numeric classification preserves differences; it does not license equivalent
//! opcodes or infer meanings of other fixed words from their widths.
use super::*;

fn native_code(path: &[u8]) -> Vec<crate::bytecode::Instruction> {
    let dmb =
        crate::dmb::Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let id = dmb
        .procs
        .iter()
        .position(|proc| dmb.string(proc.strings[0]) == Some(path))
        .unwrap_or_else(|| {
            panic!(
                "missing pinned engine procedure {}",
                String::from_utf8_lossy(path)
            )
        });
    crate::bytecode::decode(dmb.proc_code_words(id).unwrap()).unwrap()
}

#[test]
fn native_icon_constructor_counts_and_filter_modes_are_scalar_not_table_ids() {
    for (path, count) in [
        (b"/icon/New".as_slice(), 5),
        (b"/icon/operator:=".as_slice(), 1),
    ] {
        let instruction = native_code(path)
            .into_iter()
            .find(|item| item.opcode == 0xde)
            .unwrap_or_else(|| panic!("missing IconNew in {}", String::from_utf8_lossy(path)));
        assert_eq!(instruction.operands, vec![count]);
        assert!(contextual_fixed_word_is_scalar(
            0xde,
            0,
            &instruction.operands
        ));
        assert!(!fixed_word_is_scalar(0xde, 1));
    }
    let turns: Vec<_> = native_code(b"/icon/Turn")
        .into_iter()
        .filter(|item| item.opcode == 0xdf)
        .collect();
    assert_eq!(turns.len(), 2);
    assert_eq!(
        turns
            .iter()
            .map(|item| item.operands[0])
            .collect::<Vec<_>>(),
        vec![9, 5]
    );
    for instruction in turns {
        let operands = instruction.typed_operands().unwrap();
        assert!(matches!(
            &operands[..],
            [
                crate::bytecode::Operand::Word(_),
                crate::bytecode::Operand::Variable(_)
            ]
        ));
        assert!(fixed_word_is_scalar(0xdf, 0));
        assert!(!fixed_word_is_scalar(0xdf, 1));
    }
}

#[test]
fn explicit_count_roles_preserve_unknown_receivers_and_unproved_input_radius() {
    for opcode in [0xde, 0x115, 0x12b] {
        assert_eq!(fixed_word_role(opcode, 0), FixedWordRole::Scalar);
        assert_eq!(fixed_word_role(opcode, 1), FixedWordRole::Opaque);
    }
    // These receiver-bearing instructions still need independent decoder-shape
    // evidence; their operand widths alone cannot establish semantic coverage.
    assert_eq!(fixed_word_role(0x106, 0), FixedWordRole::Opaque);
    assert_eq!(fixed_word_role(0x110, 0), FixedWordRole::Opaque);
    assert!(!contextual_fixed_word_is_scalar(0xc1, 1, &[1, 0, 64]));
    assert_eq!(fixed_word_role(0x30, 1), FixedWordRole::ProcedureId);
    assert!(!fixed_word_is_scalar(0xdead, 0));
}
