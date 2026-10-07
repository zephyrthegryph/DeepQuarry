//! Shared BYOND operand emission. The semantic binder never chooses wire IDs.
use crate::{
    Item, LinkError, LinkedProc, Symbol, SymbolicProc, Table, ValueWord, VariableWord, Word,
};
pub use dm_ir::RelocationEncoding as OperandEncoding;
use dm_ir::{RelocationKind, SymRef, SymbolicCode};
use std::collections::BTreeMap;
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct OperandSite {
    pub offset: u32,
    pub kind: RelocationKind,
    pub encoding: OperandEncoding,
}
fn kind(table: Table) -> RelocationKind {
    match table {
        Table::String => RelocationKind::String,
        Table::Class => RelocationKind::Type,
        Table::Proc => RelocationKind::Procedure,
        Table::Variable => RelocationKind::Variable,
        Table::List => RelocationKind::List,
        Table::Resource => RelocationKind::Resource,
        Table::Instance => RelocationKind::Instance,
    }
}
impl OperandSite {
    fn direct(offset: usize, table: Table) -> Result<Self, LinkError> {
        Ok(Self {
            offset: u32::try_from(offset).map_err(|_| LinkError::OffsetOverflow)?,
            kind: kind(table),
            encoding: OperandEncoding::Direct,
        })
    }
    fn packed(offset: usize, table: Table, tag: u8) -> Result<Self, LinkError> {
        Ok(Self {
            encoding: OperandEncoding::PackedValue24 { tag },
            ..Self::direct(offset, table)?
        })
    }
}
pub(crate) struct EncodedProc {
    pub linked: LinkedProc,
    pub sites: Vec<OperandSite>,
}
/// Frozen ABI words and the encoder-issued operand ledger. `code().link()`
/// consumes the same typed encoding, including two-word packed values.
pub struct FrozenProc {
    code: SymbolicCode,
    sites: Vec<OperandSite>,
    labels: BTreeMap<String, u32>,
}
impl FrozenProc {
    pub fn code(&self) -> &SymbolicCode {
        &self.code
    }
    pub fn sites(&self) -> &[OperandSite] {
        &self.sites
    }
    pub fn labels(&self) -> &BTreeMap<String, u32> {
        &self.labels
    }
}
#[derive(Debug)]
pub enum FreezeError {
    Abi(LinkError),
    Binder { symbol: Symbol, message: String },
    Relocation(dm_ir::RelocationError),
}
impl std::fmt::Display for FreezeError {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(formatter, "{self:?}")
    }
}
impl std::error::Error for FreezeError {}
/// Freeze already-lowered operands. The caller supplies semantic identities for
/// every existing symbol, including static slots and procedure/verb occurrences;
/// this boundary does not perform resolution or manufacture those identities.
pub fn freeze_proc(
    proc: &SymbolicProc,
    mut bind: impl FnMut(&Symbol) -> Result<SymRef, String>,
) -> Result<FrozenProc, FreezeError> {
    let encoded = encode(proc, &mut |_| Ok(0)).map_err(FreezeError::Abi)?;
    let mut words = encoded.linked.words;
    let mut relocations = Vec::with_capacity(encoded.sites.len());
    for ((_, symbol), site) in encoded.linked.relocations.iter().zip(&encoded.sites) {
        let reference = bind(symbol).map_err(|message| FreezeError::Binder {
            symbol: symbol.clone(),
            message,
        })?;
        if reference.kind() != site.kind {
            return Err(FreezeError::Relocation(
                dm_ir::RelocationError::KindMismatch {
                    offset: site.offset,
                    expected: site.kind,
                    actual: reference.kind(),
                },
            ));
        }
        words[site.offset as usize] = 0;
        if matches!(site.encoding, OperandEncoding::PackedValue24 { .. }) {
            words[site.offset as usize + 1] = 0;
        }
        relocations.push(dm_ir::Relocation {
            offset: site.offset,
            reference,
            encoding: site.encoding,
        });
    }
    let code = SymbolicCode::new(words, relocations).map_err(FreezeError::Relocation)?;
    code.validate_encoded_sites(
        &encoded
            .sites
            .iter()
            .map(|s| (s.offset, s.kind, s.encoding))
            .collect::<Vec<_>>(),
    )
    .map_err(FreezeError::Relocation)?;
    Ok(FrozenProc {
        code,
        sites: encoded.sites,
        labels: encoded.linked.labels,
    })
}
pub(crate) fn encode(
    proc: &SymbolicProc,
    resolve: &mut impl FnMut(&Symbol) -> Result<u32, LinkError>,
) -> Result<EncodedProc, LinkError> {
    let mut labels = BTreeMap::new();
    let mut offset = 0usize;
    for item in &proc.items {
        match item {
            Item::Label(label) => {
                let at = u32::try_from(offset).map_err(|_| LinkError::OffsetOverflow)?;
                if labels.insert(label.clone(), at).is_some() {
                    return Err(LinkError::DuplicateLabel(label.clone()));
                }
            }
            Item::Instruction(instruction) => {
                offset = offset
                    .checked_add(1 + instruction.operands.iter().map(Word::width).sum::<usize>())
                    .ok_or(LinkError::OffsetOverflow)?;
            }
        }
    }
    let mut words = Vec::with_capacity(offset);
    let mut relocations = Vec::new();
    let mut sites = Vec::new();
    let mut branch_slots = Vec::new();
    let mut starts = Vec::new();
    for item in &proc.items {
        if let Item::Instruction(instruction) = item {
            starts.push(words.len());
            words.push(instruction.opcode);
            for operand in &instruction.operands {
                let slot = words.len();
                match operand {
                    Word::Immediate(value) => words.push(*value),
                    Word::Reference(symbol) => {
                        relocations.push((slot, symbol.clone()));
                        sites.push(OperandSite::direct(slot, symbol.table)?);
                        words.push(resolve(symbol)?);
                    }
                    Word::Branch(label) => {
                        branch_slots.push(slot);
                        words.push(
                            *labels
                                .get(label)
                                .ok_or_else(|| LinkError::MissingLabel(label.clone()))?,
                        );
                    }
                    Word::Value(ValueWord::Null) => words.extend([0, 0]),
                    Word::Value(ValueWord::Number(bits)) => {
                        words.extend([0x2a, bits >> 16, bits & 0xffff]);
                    }
                    Word::Value(ValueWord::String(key)) => {
                        let symbol = Symbol::new(Table::String, key);
                        let id = resolve(&symbol)?;
                        if id > 0x00ff_ffff {
                            return Err(LinkError::TooManyRecords(Table::String));
                        }
                        sites.push(OperandSite::packed(slot, symbol.table, 6)?);
                        relocations.push((slot, symbol));
                        words.extend([6 | ((id >> 16) << 8), id & 0xffff]);
                    }
                    Word::Value(ValueWord::Resource(key)) => {
                        let symbol = Symbol::new(Table::Resource, key);
                        let id = resolve(&symbol)?;
                        if id > 0x00ff_ffff {
                            return Err(LinkError::TooManyRecords(Table::Resource));
                        }
                        sites.push(OperandSite::packed(slot, symbol.table, 12)?);
                        relocations.push((slot, symbol));
                        words.extend([12 | ((id >> 16) << 8), id & 0xffff]);
                    }
                    Word::Value(ValueWord::FileType) => words.extend([39, 0]),
                    Word::Value(ValueWord::ClassPath { path, tag }) => {
                        let symbol = Symbol::new(Table::Class, path);
                        let id = resolve(&symbol)?;
                        if id > 0x00ff_ffff {
                            return Err(LinkError::TooManyRecords(Table::Class));
                        }
                        sites.push(OperandSite::packed(slot, symbol.table, *tag)?);
                        relocations.push((slot, symbol));
                        words.extend([u32::from(*tag) | ((id >> 16) << 8), id & 0xffff]);
                    }
                    Word::Value(ValueWord::Instance(path)) => {
                        let symbol = Symbol::new(Table::Instance, path);
                        let id = resolve(&symbol)?;
                        if id > 0x00ff_ffff {
                            return Err(LinkError::TooManyRecords(Table::Instance));
                        }
                        sites.push(OperandSite::packed(slot, symbol.table, 41)?);
                        relocations.push((slot, symbol));
                        words.extend([41 | ((id >> 16) << 8), id & 0xffff]);
                    }
                    Word::Value(ValueWord::ProcPath(path)) => {
                        let symbol = Symbol::new(Table::Proc, path);
                        let id = resolve(&symbol)?;
                        if id > 0x00ff_ffff {
                            return Err(LinkError::TooManyRecords(Table::Proc));
                        }
                        sites.push(OperandSite::packed(slot, symbol.table, 38)?);
                        relocations.push((slot, symbol));
                        words.extend([38 | ((id >> 16) << 8), id & 0xffff]);
                    }
                    Word::Variable(variable) => encode_variable(
                        variable,
                        resolve,
                        &mut words,
                        &mut relocations,
                        &mut sites,
                    )?,
                }
            }
        }
    }
    let decoded = byond_dmb::bytecode::decode(&words)
        .map_err(|error| LinkError::Decode(format!("{error:?}")))?;
    for (expected, instruction) in starts.into_iter().zip(decoded.iter()) {
        if expected != instruction.offset {
            return Err(LinkError::InstructionBoundary {
                expected,
                decoded: instruction.offset,
            });
        }
    }
    if decoded.len()
        != proc
            .items
            .iter()
            .filter(|item| matches!(item, Item::Instruction(_)))
            .count()
    {
        return Err(LinkError::Decode(
            "decoded instruction count differs".into(),
        ));
    }
    let mut legal_slots = Vec::new();
    for instruction in &decoded {
        legal_slots.extend(
            instruction
                .branch_target_word_offsets()
                .map_err(|error| LinkError::Decode(format!("{error:?}")))?,
        );
    }
    for slot in branch_slots {
        if !legal_slots.contains(&slot) {
            return Err(LinkError::BranchOperandIsNotTarget { offset: slot });
        }
    }
    Ok(EncodedProc {
        linked: LinkedProc {
            words,
            labels,
            relocations,
        },
        sites,
    })
}

fn encode_variable(
    variable: &VariableWord,
    resolve: &mut impl FnMut(&Symbol) -> Result<u32, LinkError>,
    words: &mut Vec<u32>,
    relocations: &mut Vec<(usize, Symbol)>,
    sites: &mut Vec<OperandSite>,
) -> Result<(), LinkError> {
    match variable {
        VariableWord::Arg(id) => words.extend([0xffd9, *id]),
        VariableWord::Local(id) => words.extend([0xffda, *id]),
        VariableWord::Src => words.push(0xffce),
        VariableWord::Usr => words.push(0xffcd),
        VariableWord::World => words.push(0xffe5),
        VariableWord::Args => words.push(0xffcf),
        VariableWord::Null => words.push(0xffe6),
        VariableWord::Dot => words.push(0xffd0),
        VariableWord::Cache => words.push(0xffd8),
        VariableWord::CacheKey => words.push(0xffe3),
        VariableWord::CacheIndex => words.push(0xffe4),
        VariableWord::Field(key)
        | VariableWord::StaticField(key)
        | VariableWord::Global(key)
        | VariableWord::DynamicProc(key) => {
            let table = if matches!(variable, VariableWord::Global(_)) {
                Table::Variable
            } else {
                Table::String
            };
            let symbol = Symbol::new(table, key);
            let id = resolve(&symbol)?;
            if matches!(variable, VariableWord::Global(_)) {
                words.push(0xffdb);
            }
            if matches!(variable, VariableWord::DynamicProc(_)) {
                words.push(0xffdd);
            }
            if matches!(variable, VariableWord::StaticField(_)) {
                words.push(0xffe7);
            }
            sites.push(OperandSite::direct(words.len(), symbol.table)?);
            relocations.push((words.len(), symbol));
            words.push(id);
        }
        VariableWord::StaticProc(path) | VariableWord::StaticVerb(path) => {
            let symbol = Symbol::new(Table::Proc, path);
            let id = resolve(&symbol)?;
            words.push(if matches!(variable, VariableWord::StaticVerb(_)) {
                0xffe0
            } else {
                0xffdf
            });
            sites.push(OperandSite::direct(words.len(), symbol.table)?);
            relocations.push((words.len(), symbol));
            words.push(id);
        }
        VariableWord::SetCache(a, b) => {
            words.push(0xffdc);
            encode_variable(a, resolve, words, relocations, sites)?;
            encode_variable(b, resolve, words, relocations, sites)?;
        }
        VariableWord::Initial(variable) => {
            words.push(0xffe7);
            encode_variable(variable, resolve, words, relocations, sites)?;
        }
        VariableWord::IsSaved(variable) => {
            words.push(0xffe8);
            encode_variable(variable, resolve, words, relocations, sites)?;
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{Instruction, Ledger};

    #[test]
    fn packed_and_nested_operands_match_existing_linked_abi() {
        let proc = SymbolicProc {
            items: vec![
                Item::Instruction(Instruction {
                    opcode: byond_dmb::bytecode::opcode::PUSH_VAL,
                    operands: vec![Word::Value(ValueWord::String("text".into()))],
                }),
                Item::Instruction(Instruction {
                    opcode: 0x29,
                    operands: vec![
                        Word::Variable(VariableWord::SetCache(
                            Box::new(VariableWord::Arg(0)),
                            Box::new(VariableWord::StaticProc("/proc/x".into())),
                        )),
                        Word::Immediate(0),
                    ],
                }),
                Item::Instruction(Instruction {
                    opcode: 0xf,
                    operands: vec![Word::Branch("end".into())],
                }),
                Item::Label("end".into()),
                Item::Instruction(Instruction {
                    opcode: 0,
                    operands: vec![],
                }),
            ],
        };
        let mut ledger = Ledger::default();
        ledger
            .bind(Symbol::new(Table::String, "text"), 0x123456)
            .unwrap();
        ledger
            .bind(Symbol::new(Table::Proc, "/proc/x"), 17)
            .unwrap();
        let expected = crate::link_proc(&proc, &ledger).unwrap();
        let frozen = freeze_proc(&proc, |symbol| {
            Ok(match symbol.table {
                Table::String => SymRef::String(dm_ir::SymbolId::of(&symbol.key)),
                Table::Proc => SymRef::Proc {
                    owner: dm_ir::SymbolId::of("/"),
                    name: dm_ir::SymbolId::of("x"),
                    occurrence: 0,
                },
                _ => unreachable!(),
            })
        })
        .unwrap();
        assert_eq!(
            frozen
                .code()
                .link(|reference| Some(match reference {
                    SymRef::String(_) => 0x123456,
                    SymRef::Proc { .. } => 17,
                    _ => unreachable!(),
                }))
                .unwrap(),
            expected.words
        );
        assert_eq!(frozen.labels(), &expected.labels);
        assert!(frozen
            .sites()
            .iter()
            .any(|site| matches!(site.encoding, OperandEncoding::PackedValue24 { .. })));
        assert!(matches!(
            freeze_proc(&proc, |_| Ok(SymRef::BuiltinGlobalVars)),
            Err(FreezeError::Relocation(
                dm_ir::RelocationError::KindMismatch { .. }
            ))
        ));
    }
}
