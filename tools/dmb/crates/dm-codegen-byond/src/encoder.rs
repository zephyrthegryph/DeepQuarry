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
    debug_relocations: Vec<dm_ir::Relocation>,
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
/// Natural bounded freeze stages; callers may return a scope guard. The
/// encoder owns scope boundaries and all paths share the same implementation.
#[derive(Clone, Copy, Debug)]
pub enum FreezeStage {
    Encoding,
    DecodeValidation,
    Binding,
    SymbolicConstruction,
    SiteValidation,
}

pub fn freeze_proc(
    proc: &SymbolicProc,
    bind: impl FnMut(&Symbol) -> Result<SymRef, String>,
) -> Result<FrozenProc, FreezeError> {
    freeze_proc_observed(proc, bind, |_| ())
}

pub fn freeze_proc_observed<G>(
    proc: &SymbolicProc,
    mut bind: impl FnMut(&Symbol) -> Result<SymRef, String>,
    mut observe: impl FnMut(FreezeStage) -> G,
) -> Result<FrozenProc, FreezeError> {
    let encoded = encode_internal_observed(proc, &mut |_| Ok(0), true, &mut observe)
        .map_err(FreezeError::Abi)?;
    let binding_guard = observe(FreezeStage::Binding);
    let mut words = encoded.linked.words;
    let mut relocations = encoded.debug_relocations.clone();
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
    relocations.sort_by_key(|site| site.offset);
    drop(binding_guard);
    let code = {
        let _guard = observe(FreezeStage::SymbolicConstruction);
        SymbolicCode::new(words, relocations).map_err(FreezeError::Relocation)?
    };
    let site_guard = observe(FreezeStage::SiteValidation);
    code.validate_encoded_sites(
        &encoded
            .sites
            .iter()
            .map(|s| (s.offset, s.kind, s.encoding))
            .collect::<Vec<_>>(),
    )
    .map_err(FreezeError::Relocation)?;
    drop(site_guard);
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
    encode_internal(proc, resolve, false)
}
fn encode_internal(
    proc: &SymbolicProc,
    resolve: &mut impl FnMut(&Symbol) -> Result<u32, LinkError>,
    allow_debug: bool,
) -> Result<EncodedProc, LinkError> {
    encode_internal_observed(proc, resolve, allow_debug, &mut |_| ())
}
fn encode_internal_observed<G>(
    proc: &SymbolicProc,
    resolve: &mut impl FnMut(&Symbol) -> Result<u32, LinkError>,
    allow_debug: bool,
    observe: &mut impl FnMut(FreezeStage) -> G,
) -> Result<EncodedProc, LinkError> {
    let encoding_guard = observe(FreezeStage::Encoding);
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
    let mut debug_sites = Vec::new();
    let mut debug_relocations = Vec::new();
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
                    Word::SourceFile(origin) | Word::SourceLine(origin) => {
                        let expected = if matches!(operand, Word::SourceFile(_)) {
                            0x84
                        } else {
                            0x85
                        };
                        if instruction.opcode != expected || instruction.operands.len() != 1 {
                            return Err(LinkError::Decode(
                                "debug source operand used outside its DBG instruction".into(),
                            ));
                        }
                        if !allow_debug {
                            return Err(LinkError::MissingDebugOrigin(*origin));
                        }
                        let reference = match operand {
                            Word::SourceFile(id) => SymRef::SourceFile(*id),
                            Word::SourceLine(id) => SymRef::SourceLine(*id),
                            _ => unreachable!(),
                        };
                        let offset = u32::try_from(slot).map_err(|_| LinkError::OffsetOverflow)?;
                        debug_sites.push(OperandSite {
                            offset,
                            kind: reference.kind(),
                            encoding: OperandEncoding::Direct,
                        });
                        debug_relocations.push(dm_ir::Relocation {
                            offset,
                            reference,
                            encoding: OperandEncoding::Direct,
                        });
                        words.push(0);
                    }
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
                    Word::Value(ValueWord::PrimitiveType(kind)) => {
                        words.extend([u32::from(kind.tag()), 0])
                    }
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
    drop(encoding_guard);
    let decode_guard = observe(FreezeStage::DecodeValidation);
    let mut decoded_offsets = Vec::with_capacity(starts.len());
    let mut legal_slots = Vec::new();
    byond_dmb::bytecode::visit_instructions(
        &words,
        |instruction| decoded_offsets.push(instruction.offset),
        |slot| legal_slots.push(slot),
    )
    .map_err(|error| LinkError::Decode(format!("{error:?}")))?;
    for (&expected, &decoded) in starts.iter().zip(&decoded_offsets) {
        if expected != decoded {
            return Err(LinkError::InstructionBoundary { expected, decoded });
        }
    }
    if decoded_offsets.len() != starts.len() {
        return Err(LinkError::Decode(
            "decoded instruction count differs".into(),
        ));
    }
    // Membership only: sorting does not affect emitted words or error order.
    legal_slots.sort_unstable();
    for slot in branch_slots {
        if legal_slots.binary_search(&slot).is_err() {
            return Err(LinkError::BranchOperandIsNotTarget { offset: slot });
        }
    }
    drop(decoded_offsets);
    drop(decode_guard);
    sites.extend(debug_sites);
    Ok(EncodedProc {
        linked: LinkedProc {
            words,
            labels,
            relocations,
        },
        sites,
        debug_relocations,
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
        VariableWord::Caller => words.push(0xfff0),
        VariableWord::Callee => words.push(0xfff1),
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
    fn debug_origins_are_typed_relocatable_and_branch_safe() {
        let proc = SymbolicProc {
            items: vec![
                Item::Label("again".into()),
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
                    operands: vec![Word::Branch("again".into())],
                }),
            ],
        };
        assert!(matches!(
            encode(&proc, &mut |_| Ok(0)),
            Err(LinkError::MissingDebugOrigin(0))
        ));
        let frozen = freeze_proc(&proc, |_| Err("no table references".into())).unwrap();
        let before = frozen.code().canonical_bytes();
        let first = frozen
            .code()
            .link(|reference| match reference {
                SymRef::SourceFile(0) => Some(9),
                SymRef::SourceLine(0) => Some(100),
                _ => None,
            })
            .unwrap();
        let moved = frozen
            .code()
            .link(|reference| match reference {
                SymRef::SourceFile(0) => Some(19),
                SymRef::SourceLine(0) => Some(7),
                _ => None,
            })
            .unwrap();
        assert_eq!(first, vec![0x84, 9, 0x85, 100, 0xf, 0]);
        assert_eq!(moved, vec![0x84, 19, 0x85, 7, 0xf, 0]);
        assert_eq!(frozen.code().canonical_bytes(), before);
        assert_eq!(byond_dmb::bytecode::decode(&moved).unwrap().len(), 3);
        assert!(frozen.code().link(|_| None).is_err());
    }

    #[test]
    fn list_primitive_has_zero_payload_without_type_relocation() {
        let proc = SymbolicProc {
            items: vec![
                Item::Instruction(Instruction {
                    opcode: 0x60,
                    operands: vec![Word::Value(ValueWord::PrimitiveType(
                        crate::NativePrimitiveType::List,
                    ))],
                }),
                Item::Instruction(Instruction {
                    opcode: 1,
                    operands: vec![Word::Immediate(0)],
                }),
                Item::Instruction(Instruction {
                    opcode: 0,
                    operands: vec![],
                }),
            ],
        };
        let encoded = encode(&proc, &mut |_| {
            panic!("primitive must not require an output table binding")
        })
        .unwrap();
        assert_eq!(encoded.linked.words, [0x60, 40, 0, 1, 0, 0]);
        assert!(encoded.sites.is_empty());
    }
    #[test]
    fn savefile_primitive_has_zero_payload_without_type_relocation() {
        let proc = SymbolicProc {
            items: vec![
                Item::Instruction(Instruction {
                    opcode: 0x60,
                    operands: vec![Word::Value(ValueWord::PrimitiveType(
                        crate::NativePrimitiveType::Savefile,
                    ))],
                }),
                Item::Instruction(Instruction {
                    opcode: 1,
                    operands: vec![Word::Immediate(0)],
                }),
                Item::Instruction(Instruction {
                    opcode: 0,
                    operands: vec![],
                }),
            ],
        };
        let encoded = encode(&proc, &mut |_| {
            panic!("primitive must not require an output table binding")
        })
        .unwrap();
        assert_eq!(encoded.linked.words, [0x60, 36, 0, 1, 0, 0]);
        assert!(encoded.sites.is_empty());
        assert_eq!(crate::NativePrimitiveType::from_path("/alist"), None);
        assert_eq!(crate::NativePrimitiveType::from_path("/world"), None);
    }
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
    #[test]
    fn freeze_observer_balances_scopes_and_preserves_wire_content_on_decode_failure() {
        use std::{cell::RefCell, rc::Rc};
        type Events = Rc<RefCell<Vec<(bool, &'static str)>>>;
        struct Guard(Events, &'static str);
        impl Drop for Guard {
            fn drop(&mut self) {
                self.0.borrow_mut().push((false, self.1));
            }
        }
        let observer = |events: Events| {
            move |stage| {
                let name = match stage {
                    FreezeStage::Encoding => "encoding",
                    FreezeStage::DecodeValidation => "decode",
                    FreezeStage::Binding => "binding",
                    FreezeStage::SymbolicConstruction => "construction",
                    FreezeStage::SiteValidation => "sites",
                };
                events.borrow_mut().push((true, name));
                Guard(Rc::clone(&events), name)
            }
        };
        let proc = SymbolicProc {
            items: vec![
                Item::Instruction(Instruction {
                    opcode: 0x60,
                    operands: vec![Word::Value(ValueWord::String("payload".into()))],
                }),
                Item::Instruction(Instruction {
                    opcode: 0,
                    operands: vec![],
                }),
            ],
        };
        let bind = |symbol: &Symbol| Ok(SymRef::String(dm_ir::SymbolId::of(&symbol.key)));
        let expected = freeze_proc(&proc, bind).unwrap();
        let events = Events::default();
        let observed = freeze_proc_observed(&proc, bind, observer(Rc::clone(&events))).unwrap();
        assert_eq!(
            observed.code().canonical_bytes(),
            expected.code().canonical_bytes()
        );
        assert_eq!(observed.sites(), expected.sites());
        assert_eq!(observed.labels(), expected.labels());
        assert_eq!(
            *events.borrow(),
            ["encoding", "decode", "binding", "construction", "sites"]
                .into_iter()
                .flat_map(|stage| [(true, stage), (false, stage)])
                .collect::<Vec<_>>()
        );

        // PUSH_VAL without its packed operands reaches the independent decoder
        // and fails there, before binding or symbolic construction can run.
        let malformed = SymbolicProc {
            items: vec![Item::Instruction(Instruction {
                opcode: 0x60,
                operands: vec![],
            })],
        };
        let events = Events::default();
        let error = freeze_proc_observed(&malformed, bind, observer(Rc::clone(&events)))
            .err()
            .expect("malformed bytecode must fail");
        assert!(matches!(error, FreezeError::Abi(LinkError::Decode(_))));
        assert_eq!(
            *events.borrow(),
            vec![
                (true, "encoding"),
                (false, "encoding"),
                (true, "decode"),
                (false, "decode")
            ]
        );
    }
}
