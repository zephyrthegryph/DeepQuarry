//! Explicit operand contracts corroborated by the pinned 516.1687 engine image.
//! Numeric classification preserves differences; it does not license equivalent
//! opcodes or infer meanings of other fixed words from their widths.
use super::*;

fn native_code(path: &[u8]) -> Vec<crate::bytecode::Instruction> {
    let dmb =
        crate::dmb::Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    // Native wrapper names retain explicit /proc/ markers. Use the same exact
    // canonical path and owning-class rank selection as structural comparison.
    let id = ranked_proc_by_path(&dmb, path, 0)
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
    for opcode in [0xde, 0x106, 0x110, 0x115, 0x12b] {
        assert_eq!(fixed_word_role(opcode, 0), FixedWordRole::Scalar);
        assert_eq!(fixed_word_role(opcode, 1), FixedWordRole::Opaque);
    }
    // Receiver grammar remains independent of the proved argument-count role.
    // An extra fixed word must not gain scalar authority.
    assert_eq!(fixed_word_role(0x106, 1), FixedWordRole::Opaque);
    assert_eq!(fixed_word_role(0x110, 1), FixedWordRole::Opaque);
    assert!(!contextual_fixed_word_is_scalar(0xc1, 1, &[1, 1, 64]));
    assert_eq!(fixed_word_role(0x30, 1), FixedWordRole::ProcedureId);
    assert!(!fixed_word_is_scalar(0xdead, 0));
}

#[test]
fn pinned_icon_insert_and_map_colors_counts_remain_exact_scalars() {
    for (path, opcode, expected) in [
        (b"/icon/Insert".as_slice(), 0x106, vec![7]),
        (b"/icon/MapColors".as_slice(), 0x110, vec![4, 5, 12, 20]),
    ] {
        let instructions: Vec<_> = native_code(path)
            .into_iter()
            .filter(|item| item.opcode == opcode)
            .collect();
        let counts: Vec<_> = instructions.iter().map(|item| item.operands[0]).collect();
        assert_eq!(counts, expected);
        let code = native_code(path);
        for instruction in instructions {
            // Pinned dmasm 6cec0e9 declares (arg_count: u32, var: Variable).
            // The template receiver is Field(43); it is not CallPath opcode43.
            assert_eq!(instruction.operands.len(), 2);
            assert_eq!(
                instruction.typed_operands().unwrap(),
                vec![
                    crate::bytecode::Operand::Word(instruction.operands[0]),
                    crate::bytecode::Operand::Variable(crate::operands::Variable::Field(43)),
                ]
            );
            let following = code
                .iter()
                .find(|item| item.offset == instruction.offset + 3)
                .expect("receiver must end immediately before the following Pop");
            assert_eq!(following.opcode, 0x51);
            assert!(following.operands.is_empty());
            assert_eq!(fixed_word_role(opcode, 0), FixedWordRole::Scalar);
            assert_eq!(fixed_word_role(opcode, 1), FixedWordRole::Opaque);
            assert!(contextual_fixed_word_is_scalar(
                opcode,
                0,
                &instruction.operands
            ));
        }
    }
}
