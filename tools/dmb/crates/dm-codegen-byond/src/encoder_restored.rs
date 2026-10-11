//! Independent encoded artifact shape checks; no compiler-issued certificate persists.
use super::*;
use byond_dmb::{
    bytecode::Operand,
    operands::{Value, Variable},
};
use std::collections::{BTreeMap, BTreeSet};

enum Site {
    Scalar,
    Typed(RelocationKind, OperandEncoding),
    Primitive(RelocationKind, OperandEncoding),
}
pub(super) fn validate(
    code: &SymbolicCode,
    labels: &[Option<u32>],
) -> Result<RestoredInstructionFacts, String> {
    let words = code.link(|_| Some(0)).map_err(|e| format!("{e:?}"))?;
    let decoded = byond_dmb::bytecode::decode(&words).map_err(|e| format!("{e:?}"))?;
    let starts: BTreeSet<_> = decoded.iter().map(|i| i.offset as u32).collect();
    if labels
        .iter()
        .flatten()
        .any(|at| !starts.contains(at) && *at as usize != words.len())
    {
        return Err("invalid restored label roster".into());
    }
    let mut sites = BTreeMap::new();
    let mut facts = RestoredInstructionFacts {
        external: false,
        debug: false,
    };
    for instruction in &decoded {
        use byond_dmb::bytecode::opcode;
        facts.external |= matches!(instruction.opcode, opcode::LOAD_EXT | opcode::CALL_EXT);
        facts.debug |= matches!(instruction.opcode, opcode::DBG_FILE | opcode::DBG_LINE);
        if instruction
            .branch_targets()
            .map_err(|e| format!("{e:?}"))?
            .iter()
            .any(|at| !starts.contains(at) && *at as usize != words.len())
        {
            return Err("restored branch target is not an instruction".into());
        }
        let branches: BTreeSet<_> = instruction
            .branch_target_word_offsets()
            .map_err(|e| format!("{e:?}"))?
            .into_iter()
            .collect();
        let mut at = instruction.offset + 1;
        for operand in instruction.typed_operands().map_err(|e| format!("{e:?}"))? {
            match operand {
                Operand::Word(_) => {
                    if !branches.contains(&at) {
                        let site = match instruction.opcode {
                            0x84 => Site::Typed(RelocationKind::String, OperandEncoding::Direct),
                            0x85 => {
                                Site::Typed(RelocationKind::SourceLine, OperandEncoding::Direct)
                            }
                            _ => Site::Scalar,
                        };
                        sites.insert(at as u32, site);
                    }
                    at += 1;
                }
                Operand::Value(value) => at += value_site(&value, at, &mut sites),
                Operand::Variable(value) => at += variable_sites(&value, at, &mut sites),
                Operand::Switch { cases, .. } => {
                    at += 1;
                    for (value, _) in cases {
                        at += value_site(&value, at, &mut sites) + 1;
                    }
                    at += 1;
                }
                Operand::RangeSwitch { ranges, exact, .. } => {
                    at += 1;
                    for (a, b, _) in ranges {
                        at += value_site(&a, at, &mut sites);
                        at += value_site(&b, at, &mut sites) + 1;
                    }
                    at += 1;
                    for (value, _) in exact {
                        at += value_site(&value, at, &mut sites) + 1;
                    }
                    at += 1;
                }
                Operand::PickSwitch { cases, .. } => at += 2 + cases.len() * 2,
                Operand::PickProb(values) => at += 1 + values.len(),
            }
        }
    }
    for relocation in code.relocations() {
        match sites.remove(&relocation.offset) {
            Some(Site::Typed(kind, encoding) | Site::Primitive(kind, encoding))
                if kind == relocation.reference.kind() && encoding == relocation.encoding =>
            {
                ()
            }
            Some(Site::Scalar) if relocation.encoding == OperandEncoding::Direct => (),
            _ => return Err("restored relocation is not a compatible operand site".into()),
        }
    }
    if sites.values().any(|site| matches!(site, Site::Typed(..))) {
        return Err("restored semantic operand has no relocation".into());
    }
    Ok(facts)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{Instruction, Item, LabelId, SymbolicProc, Word};
    use dm_ir::{Relocation, SymbolId};

    #[test]
    fn restore_preserves_canonical_code_and_end_labels() {
        let source = SymbolicProc {
            items: vec![
                Item::Instruction(Instruction {
                    opcode: 0x84,
                    operands: vec![Word::SourceFile(0)],
                }),
                Item::Instruction(Instruction {
                    opcode: 0x85,
                    operands: vec![Word::SourceLine(0)],
                }),
                Item::Instruction(Instruction {
                    opcode: 0xf,
                    operands: vec![Word::Branch(LabelId(0))],
                }),
                Item::Label(LabelId(0)),
            ],
        };
        let frozen = freeze_proc(&source).unwrap();
        let restored =
            FrozenProc::restore(frozen.code().clone(), frozen.labels().to_vec()).unwrap();
        assert_eq!(
            restored.code().canonical_bytes(),
            frozen.code().canonical_bytes()
        );
        assert_eq!(restored.labels(), frozen.labels());
        assert_eq!(
            restored.sites().collect::<Vec<_>>(),
            frozen.sites().collect::<Vec<_>>()
        );
    }

    #[test]
    fn restored_instruction_facts_match_owned_and_shared_validated_boundaries() {
        use byond_dmb::bytecode::opcode;
        for external in [false, true] {
            let mut items = vec![Item::Instruction(Instruction {
                opcode: opcode::PUSH_INT,
                operands: vec![Word::Immediate(opcode::LOAD_EXT)],
            })];
            if external {
                items.push(Item::Instruction(Instruction {
                    opcode: opcode::LOAD_EXT,
                    operands: vec![],
                }));
                items.push(Item::Instruction(Instruction {
                    opcode: opcode::CALL_EXT,
                    operands: vec![Word::Immediate(0)],
                }));
                items.push(Item::Instruction(Instruction {
                    opcode: opcode::DBG_LINE,
                    operands: vec![Word::SourceLine(0)],
                }));
            }
            let fresh = freeze_proc(&SymbolicProc { items }).unwrap();
            let mut bytes = vec![255];
            for word in fresh.code().word_iter() {
                bytes.extend_from_slice(&word.to_le_bytes());
            }
            let end = bytes.len();
            let shared = dm_ir::WordStorage::shared(std::sync::Arc::new(bytes), 1..end).unwrap();
            let shared =
                SymbolicCode::from_word_storage(shared, fresh.code().relocations().collect())
                    .unwrap();
            let (owned, owned_facts) = FrozenProc::restore_with_instruction_facts(
                fresh.code().clone(),
                fresh.labels().to_vec(),
            )
            .unwrap();
            let (mapped, mapped_facts) =
                FrozenProc::restore_with_instruction_facts(shared, fresh.labels().to_vec())
                    .unwrap();
            assert_eq!(owned_facts, mapped_facts);
            assert_eq!(owned_facts.external(), external);
            assert_eq!(owned_facts.debug(), external);
            assert_eq!(
                owned.code().canonical_bytes(),
                mapped.code().canonical_bytes()
            );
            // Existing traversal is an independent oracle for flags; immediate
            // opcode-looking words cannot masquerade as instructions.
            let linked = owned.code().link(|_| Some(0)).unwrap();
            let mut expected = (false, false);
            byond_dmb::bytecode::visit_instructions(
                &linked,
                |instruction| {
                    expected.0 |= matches!(instruction.opcode, opcode::LOAD_EXT | opcode::CALL_EXT);
                    expected.1 |= matches!(instruction.opcode, opcode::DBG_FILE | opcode::DBG_LINE);
                },
                |_| {},
            )
            .unwrap();
            assert_eq!((owned_facts.external(), owned_facts.debug()), expected);
        }
    }
    #[test]
    fn restore_rejects_relocation_in_opcode_or_branch_target() {
        for offset in [0, 1] {
            let code = SymbolicCode::new(
                vec![if offset == 0 { 0 } else { 0xf }, 0],
                vec![Relocation {
                    offset,
                    reference: SymRef::String(SymbolId::of("unlicensed")),
                    encoding: OperandEncoding::Direct,
                }],
            )
            .unwrap();
            assert!(FrozenProc::restore(code, Vec::new()).is_err());
        }
    }

    #[test]
    fn restore_rejects_wrong_debug_operand_kind() {
        let code = SymbolicCode::new(
            vec![0x85, 0],
            vec![Relocation {
                offset: 1,
                reference: SymRef::String(SymbolId::of("not-a-line")),
                encoding: OperandEncoding::Direct,
            }],
        )
        .unwrap();
        assert!(FrozenProc::restore(code, Vec::new()).is_err());
    }
}
fn value_site(value: &Value, at: usize, sites: &mut BTreeMap<u32, Site>) -> usize {
    use byond_dmb::operands::ValueKind::*;
    let kind = match value.kind() {
        String => Some(RelocationKind::String),
        Resource => Some(RelocationKind::Resource),
        ProcPath => Some(RelocationKind::Procedure),
        InstanceTypePath => Some(RelocationKind::Instance),
        MobPath | MovablePath | AtomPath | AreaPath | DatumPath | SavefilePath | FilePath
        | ListPath | ClientPath | ImagePath | BuiltinPath => Some(RelocationKind::Type),
        _ => None,
    };
    if let Some(kind) = kind {
        let encoding = OperandEncoding::PackedValue24 { tag: value.tag() };
        let primitive =
            matches!(value.kind(), FilePath | ListPath | SavefilePath) && value.id() == 0;
        sites.insert(
            at as u32,
            if primitive {
                Site::Primitive(kind, encoding)
            } else {
                Site::Typed(kind, encoding)
            },
        );
    }
    value.encode().len()
}
fn variable_sites(value: &Variable, at: usize, sites: &mut BTreeMap<u32, Site>) -> usize {
    use Variable::*;
    let direct = |sites: &mut BTreeMap<u32, Site>, offset, kind| {
        sites.insert(offset as u32, Site::Typed(kind, OperandEncoding::Direct));
    };
    match value {
        Field(_) => direct(sites, at, RelocationKind::String),
        DynamicProc(_) | DynamicVerb(_) => direct(sites, at + 1, RelocationKind::String),
        Global(_) => direct(sites, at + 1, RelocationKind::Variable),
        StaticProc(_) | StaticVerb(_) => direct(sites, at + 1, RelocationKind::Procedure),
        Initial(v) | IsSaved(v) => {
            variable_sites(v, at + 1, sites);
        }
        SetCache(a, b) => {
            variable_sites(a, at + 1, sites);
            variable_sites(b, at + 1 + a.encode().len(), sites);
        }
        _ => (),
    }
    value.encode().len()
}
