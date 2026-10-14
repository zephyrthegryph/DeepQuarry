//! Fragment protocol tests; the whole-scope producer remains the parity oracle.
use super::*;
use crate::{SimpleProc, StringPayload, SymbolId, SymbolicProc, ValueWord};

fn continuation(items: Vec<Item>) -> ResolverProc {
    ResolverProc {
        modified_instances: BTreeMap::new(),
        procedure_values: BTreeMap::new(),
        procedure_statics: BTreeMap::new(),
        procedure: SimpleProc {
            code: SymbolicProc { items },
            ..Default::default()
        },
        slots: BTreeMap::new(),
        resources: BTreeMap::new(),
        instances: BTreeMap::new(),
    }
}
fn instruction(opcode: u32, operands: Vec<Word>) -> Item {
    Item::Instruction(Instruction { opcode, operands })
}
fn literal_fragment(text: &'static str) -> AssignmentFragment {
    let mut code = continuation(vec![
        instruction(0x84, vec![Word::SourceFile(0)]),
        instruction(0x85, vec![Word::SourceLine(0)]),
        instruction(
            opcode::PUSH_VAL,
            vec![Word::Value(ValueWord::String(SymbolId::of(text)))],
        ),
    ]);
    code.procedure
        .strings
        .push(StringPayload::new(text.as_bytes()));
    AssignmentFragment::certify(code).unwrap()
}
#[test]
fn ordered_roster_and_current_debug_are_not_fragment_history() {
    let result = assemble_continuations(
        [
            literal_fragment("same"),
            literal_fragment("later"),
            literal_fragment("same"),
        ],
        true,
    )
    .unwrap();
    assert_eq!(
        result
            .procedure
            .strings
            .iter()
            .map(|p| p.id)
            .collect::<Vec<_>>(),
        [SymbolId::of("same"), SymbolId::of("later")]
    );
    let sources = result
        .procedure
        .code
        .items
        .iter()
        .filter_map(|item| {
            let Item::Instruction(ins) = item else {
                return None;
            };
            match ins.operands.as_slice() {
                [Word::SourceLine(origin)] => Some(*origin),
                _ => None,
            }
        })
        .collect::<Vec<_>>();
    assert_eq!(sources, [0, 1, 2, 0]);
    assert!(
        matches!(result.procedure.code.items.last(), Some(Item::Instruction(ins))
        if ins.opcode == opcode::END && ins.operands.is_empty())
    );
    assert_eq!(
        result
            .procedure
            .code
            .items
            .iter()
            .filter(|item| matches!(item,Item::Instruction(ins) if ins.opcode == opcode::END))
            .count(),
        1
    );
}
#[test]
fn dense_local_branches_are_rebased_without_cross_fragment_targets() {
    let branch = || {
        AssignmentFragment::certify(continuation(vec![
            instruction(0x0f, vec![Word::Branch(LabelId(1))]),
            Item::Label(LabelId(0)),
            instruction(0x0f, vec![Word::Branch(LabelId(0))]),
            Item::Label(LabelId(1)),
        ]))
        .unwrap()
    };
    let result = assemble_continuations([branch(), branch()], false).unwrap();
    let definitions = result
        .procedure
        .code
        .items
        .iter()
        .filter_map(|item| match item {
            Item::Label(label) => Some(label.0),
            _ => None,
        })
        .collect::<Vec<_>>();
    assert_eq!(definitions, [0, 1, 2, 3]);
    let targets = result
        .procedure
        .code
        .items
        .iter()
        .filter_map(|item| {
            let Item::Instruction(ins) = item else {
                return None;
            };
            match ins.operands.as_slice() {
                [Word::Branch(label)] => Some(label.0),
                _ => None,
            }
        })
        .collect::<Vec<_>>();
    assert_eq!(targets, [1, 0, 3, 2]);
}
#[test]
fn certificate_rejects_frames_epilogues_and_open_label_sets() {
    for op in [opcode::END, opcode::RET] {
        assert!(AssignmentFragment::certify(continuation(vec![instruction(op, vec![])])).is_err());
    }
    let mut framed = continuation(Vec::new());
    framed.procedure.local_count = 1;
    assert!(AssignmentFragment::certify(framed).is_err());
    assert!(AssignmentFragment::certify(continuation(vec![instruction(
        0x0f,
        vec![Word::Branch(LabelId(0))]
    ),]))
    .is_err());
    assert!(AssignmentFragment::certify(continuation(vec![Item::Label(LabelId(1))])).is_err());
    assert!(AssignmentFragment::certify(continuation(vec![instruction(
        0x85,
        vec![Word::SourceLine(1)]
    ),]))
    .is_err());
}
#[test]
fn unequal_exact_resolver_sidecars_cannot_be_silently_merged() {
    let make = |owner| {
        let mut code = continuation(Vec::new());
        code.slots.insert(
            SymRef::VariableSlot(SymbolId::of("slot")),
            ResolvedSlot {
                symbol: SymbolId::of("slot"),
                owner: SymbolId::of(owner),
                name: SymbolId::of("value"),
            },
        );
        AssignmentFragment::certify(code).unwrap()
    };
    assert!(assemble_continuations([make("/a"), make("/b")], false).is_err());
    assert!(assemble_continuations([make("/a"), make("/a")], false).is_ok());
}
