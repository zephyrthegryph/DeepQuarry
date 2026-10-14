//! Direct typed BYOND operand emission. Only final linking chooses wire IDs.
use crate::{Item, LinkError, LinkedProc, SymbolicProc, Table, ValueWord, VariableWord, Word};
pub use dm_ir::RelocationEncoding as OperandEncoding;
#[path = "encoder_src_cache.rs"]
mod src_cache;
use dm_ir::{Relocation, RelocationKind, SymRef, SymbolicCode};

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct OperandSite {
    pub offset: u32,
    pub kind: RelocationKind,
    pub encoding: OperandEncoding,
}
/// Facts privately issued only by a successful independent restore validator.
/// They describe decoded instruction boundaries, never semantic/source authority.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct RestoredInstructionFacts {
    external: bool,
    debug: bool,
    referenced_argument_prefix: u32,
}
impl RestoredInstructionFacts {
    pub fn external(&self) -> bool {
        self.external
    }
    pub fn debug(&self) -> bool {
        self.debug
    }
}
pub struct FrozenProc {
    code: std::sync::Arc<SymbolicCode>,
    labels: Vec<Option<u32>>,
    referenced_argument_prefix: u32,
}
impl FrozenProc {
    /// Restore persisted encoded code through the independent decoder grammar.
    /// Semantic reference authority remains the caller's current-source duty.
    pub fn restore(code: SymbolicCode, labels: Vec<Option<u32>>) -> Result<Self, String> {
        Self::restore_with_instruction_facts(code, labels).map(|(code, _)| code)
    }
    /// Return boundary facts from the SAME grammar/site/label validation. No
    /// facts escape when any validation fails; nothing is trusted from disk.
    pub fn restore_with_instruction_facts(
        code: SymbolicCode,
        labels: Vec<Option<u32>>,
    ) -> Result<(Self, RestoredInstructionFacts), String> {
        let facts = restored::validate(&code, &labels)?;
        Ok((
            Self {
                code: std::sync::Arc::new(code),
                labels,
                referenced_argument_prefix: facts.referenced_argument_prefix,
            },
            facts,
        ))
    }
    pub fn code(&self) -> &SymbolicCode {
        &self.code
    }
    pub fn shared_code(&self) -> std::sync::Arc<SymbolicCode> {
        std::sync::Arc::clone(&self.code)
    }
    /// Allocation-free operand roster derived from independently validated code.
    /// Emission visits increasing word offsets; canonical relocation storage
    /// preserves that order after the mandatory independent site check.
    pub fn sites(
        &self,
    ) -> impl ExactSizeIterator<Item = OperandSite> + DoubleEndedIterator + std::iter::FusedIterator + '_
    {
        self.code.relocations().map(|relocation| OperandSite {
            offset: relocation.offset,
            kind: relocation.reference.kind(),
            encoding: relocation.encoding,
        })
    }
    pub fn labels(&self) -> &[Option<u32>] {
        &self.labels
    }
    pub fn referenced_argument_prefix(&self) -> u32 {
        self.referenced_argument_prefix
    }
    /// Actual owned backing, for logical retention accounting only.
    pub fn label_storage_capacity(&self) -> usize {
        self.labels.capacity()
    }
}
#[path = "encoder_restored.rs"]
mod restored;
#[derive(Debug)]
pub enum FreezeError {
    Abi(LinkError),
    Relocation(dm_ir::RelocationError),
}
impl std::fmt::Display for FreezeError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{self:?}")
    }
}
impl std::error::Error for FreezeError {}
#[derive(Clone, Copy, Debug)]
pub enum FreezeStage {
    Encoding,
    DecodeValidation,
    SymbolicConstruction,
    SiteValidation,
}

pub fn freeze_proc(proc: &SymbolicProc) -> Result<FrozenProc, FreezeError> {
    freeze_proc_observed(proc, |_| ())
}
/// References are resolver-issued before this boundary. This traversal emits
/// zero placeholders and typed relocation sites together; there is no text
/// ledger, binder, rewrite, relocation-sort or placeholder-clearing pass.
pub fn freeze_proc_observed<G>(
    proc: &SymbolicProc,
    mut observe: impl FnMut(FreezeStage) -> G,
) -> Result<FrozenProc, FreezeError> {
    let encoding_guard = observe(FreezeStage::Encoding);
    let (labels, word_count) = label_offsets(proc).map_err(FreezeError::Abi)?;
    let mut emission = Emission {
        words: Vec::with_capacity(word_count),
        ..Default::default()
    };
    let mut starts = Vec::with_capacity(proc.items.len());
    let mut branches = Vec::new();
    let mut receiver = src_cache::SrcCache::default();
    for item in &proc.items {
        receiver.begin(item);
        if let Item::Instruction(instruction) = item {
            starts.push(emission.words.len());
            emission.words.push(instruction.opcode);
            for operand in &instruction.operands {
                match operand {
                    Word::Immediate(value) => emission.words.push(*value),
                    Word::SourceFile(origin) | Word::SourceLine(origin) => {
                        let file = matches!(operand, Word::SourceFile(_));
                        let expected = if file { 0x84 } else { 0x85 };
                        if instruction.opcode != expected || instruction.operands.len() != 1 {
                            return Err(FreezeError::Abi(LinkError::Decode(
                                "debug source operand used outside its DBG instruction".into(),
                            )));
                        }
                        let reference = if file {
                            SymRef::SourceFile(*origin)
                        } else {
                            SymRef::SourceLine(*origin)
                        };
                        emission
                            .reference(reference, reference.kind(), OperandEncoding::Direct)
                            .map_err(FreezeError::Abi)?;
                    }
                    Word::Reference(reference) => emission
                        .reference(*reference, reference.kind(), OperandEncoding::Direct)
                        .map_err(FreezeError::Abi)?,
                    Word::Branch(label) => {
                        branches.push(emission.words.len());
                        let at = labels
                            .get(label.0 as usize)
                            .and_then(|offset| *offset)
                            .ok_or(FreezeError::Abi(LinkError::MissingLabel(*label)))?;
                        emission.words.push(at);
                    }
                    Word::Value(value) => emission.value(value).map_err(FreezeError::Abi)?,
                    Word::Variable(variable) => emission
                        .variable(receiver.variable(variable, instruction.opcode))
                        .map_err(FreezeError::Abi)?,
                }
            }
        }
    }
    drop(encoding_guard);
    {
        let _guard = observe(FreezeStage::DecodeValidation);
        validate_instructions(&emission.words, &starts, &branches).map_err(FreezeError::Abi)?;
    }
    let code = {
        let _guard = observe(FreezeStage::SymbolicConstruction);
        SymbolicCode::new(emission.words, emission.relocations).map_err(FreezeError::Relocation)?
    };
    {
        let _guard = observe(FreezeStage::SiteValidation);
        code.validate_encoded_sites_iter(
            emission
                .sites
                .iter()
                .map(|site| (site.offset, site.kind, site.encoding)),
        )
        .map_err(FreezeError::Relocation)?;
    }
    Ok(FrozenProc {
        code: std::sync::Arc::new(code),
        labels,
        referenced_argument_prefix: emission.referenced_argument_prefix,
    })
}

fn label_offsets(proc: &SymbolicProc) -> Result<(Vec<Option<u32>>, usize), LinkError> {
    let mut count = 0;
    for item in &proc.items {
        if let Item::Label(label) = item {
            let index = usize::try_from(label.0).map_err(|_| LinkError::OffsetOverflow)?;
            // Labels are dense procedure-local IDs. An externally forged sparse
            // maximum must not turn a small input into a massive allocation.
            if index >= proc.items.len() {
                return Err(LinkError::InvalidLabel(*label));
            }
            count = count.max(index + 1);
        }
    }
    let mut labels = vec![None; count];
    let mut offset = 0usize;
    let mut receiver = src_cache::SrcCache::default();
    for item in &proc.items {
        receiver.begin(item);
        match item {
            Item::Label(label) => {
                let at = u32::try_from(offset).map_err(|_| LinkError::OffsetOverflow)?;
                if labels[label.0 as usize].replace(at).is_some() {
                    return Err(LinkError::DuplicateLabel(*label));
                }
            }
            Item::Instruction(instruction) => {
                offset = offset.checked_add(1).ok_or(LinkError::OffsetOverflow)?;
                for operand in &instruction.operands {
                    let width = match operand {
                        Word::Variable(variable) => {
                            receiver.variable(variable, instruction.opcode).width()
                        }
                        _ => operand.width(),
                    };
                    offset = offset.checked_add(width).ok_or(LinkError::OffsetOverflow)?;
                }
                u32::try_from(offset).map_err(|_| LinkError::OffsetOverflow)?;
            }
        }
    }
    Ok((labels, offset))
}
#[derive(Default)]
struct Emission {
    words: Vec<u32>,
    relocations: Vec<Relocation>,
    sites: Vec<OperandSite>,
    referenced_argument_prefix: u32,
}
impl Emission {
    fn reference(
        &mut self,
        reference: SymRef,
        expected: RelocationKind,
        encoding: OperandEncoding,
    ) -> Result<(), LinkError> {
        if reference.kind() != expected {
            return Err(LinkError::ReferenceKind {
                expected,
                actual: reference.kind(),
            });
        }
        let offset = u32::try_from(self.words.len()).map_err(|_| LinkError::OffsetOverflow)?;
        self.sites.push(OperandSite {
            offset,
            kind: expected,
            encoding,
        });
        self.relocations.push(Relocation {
            offset,
            reference,
            encoding,
        });
        self.words.push(0);
        if matches!(encoding, OperandEncoding::PackedValue24 { .. }) {
            self.words.push(0);
        }
        Ok(())
    }
    fn packed(
        &mut self,
        reference: SymRef,
        expected: RelocationKind,
        tag: u8,
    ) -> Result<(), LinkError> {
        self.reference(reference, expected, OperandEncoding::PackedValue24 { tag })
    }
    fn value(&mut self, value: &ValueWord) -> Result<(), LinkError> {
        match value {
            ValueWord::Null => self.words.extend([0, 0]),
            ValueWord::Number(bits) => self.words.extend([0x2a, bits >> 16, bits & 0xffff]),
            ValueWord::String(id) => self.packed(SymRef::String(*id), RelocationKind::String, 6)?,
            ValueWord::Resource(content) => {
                self.packed(SymRef::Resource(*content), RelocationKind::Resource, 12)?
            }
            ValueWord::ClassPath { path, tag } => {
                self.packed(SymRef::Type(*path), RelocationKind::Type, *tag)?
            }
            ValueWord::Instance(id) => {
                self.packed(SymRef::Instance(*id), RelocationKind::Instance, 41)?
            }
            ValueWord::ProcPath(reference) => {
                self.packed(*reference, RelocationKind::Procedure, 38)?
            }
            ValueWord::FileType => self.words.extend([39, 0]),
            ValueWord::PrimitiveType(kind) => self.words.extend([u32::from(kind.tag()), 0]),
        }
        Ok(())
    }
    fn variable(&mut self, variable: &VariableWord) -> Result<(), LinkError> {
        match variable {
            VariableWord::Arg(id) => {
                self.referenced_argument_prefix = self
                    .referenced_argument_prefix
                    .max(id.checked_add(1).ok_or(LinkError::OffsetOverflow)?);
                self.words.extend([0xffd9, *id]);
            }
            VariableWord::Local(id) => self.words.extend([0xffda, *id]),
            VariableWord::Src => self.words.push(0xffce),
            VariableWord::Usr => self.words.push(0xffcd),
            VariableWord::World => self.words.push(0xffe5),
            VariableWord::Args => self.words.push(0xffcf),
            VariableWord::Caller => self.words.push(0xfff0),
            VariableWord::Callee => self.words.push(0xfff1),
            VariableWord::Null => self.words.push(0xffe6),
            VariableWord::Dot => self.words.push(0xffd0),
            VariableWord::Cache => self.words.push(0xffd8),
            VariableWord::CacheKey => self.words.push(0xffe3),
            VariableWord::CacheIndex => self.words.push(0xffe4),
            VariableWord::Field(id) => self.reference(
                SymRef::String(*id),
                RelocationKind::String,
                OperandEncoding::Direct,
            )?,
            VariableWord::StaticField(id)
            | VariableWord::DynamicProc(id)
            | VariableWord::DynamicVerb(id) => {
                self.words
                    .push(if matches!(variable, VariableWord::StaticField(_)) {
                        0xffe7
                    } else if matches!(variable, VariableWord::DynamicVerb(_)) {
                        0xffde
                    } else {
                        0xffdd
                    });
                self.reference(
                    SymRef::String(*id),
                    RelocationKind::String,
                    OperandEncoding::Direct,
                )?;
            }
            VariableWord::Global(reference) => {
                self.words.push(0xffdb);
                self.reference(
                    *reference,
                    RelocationKind::Variable,
                    OperandEncoding::Direct,
                )?;
            }
            VariableWord::StaticProc(reference) | VariableWord::StaticVerb(reference) => {
                self.words
                    .push(if matches!(variable, VariableWord::StaticVerb(_)) {
                        0xffe0
                    } else {
                        0xffdf
                    });
                self.reference(
                    *reference,
                    RelocationKind::Procedure,
                    OperandEncoding::Direct,
                )?;
            }
            VariableWord::SetCache(a, b) => {
                self.words.push(0xffdc);
                self.variable(a)?;
                self.variable(b)?;
            }
            VariableWord::Initial(value) => {
                self.words.push(0xffe7);
                self.variable(value)?;
            }
            VariableWord::IsSaved(value) => {
                self.words.push(0xffe8);
                self.variable(value)?;
            }
        }
        Ok(())
    }
}
fn validate_instructions(
    words: &[u32],
    starts: &[usize],
    branches: &[usize],
) -> Result<(), LinkError> {
    let mut decoded_offsets = Vec::with_capacity(starts.len());
    let mut legal_slots = Vec::new();
    byond_dmb::bytecode::visit_instructions(
        words,
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
    legal_slots.sort_unstable();
    for &slot in branches {
        if legal_slots.binary_search(&slot).is_err() {
            return Err(LinkError::BranchOperandIsNotTarget { offset: slot });
        }
    }
    Ok(())
}
pub(crate) fn link(
    proc: &SymbolicProc,
    resolve: impl FnMut(SymRef) -> Option<u32>,
) -> Result<LinkedProc, LinkError> {
    let frozen = freeze_proc(proc).map_err(|error| match error {
        FreezeError::Abi(error) => error,
        FreezeError::Relocation(error) => LinkError::Decode(format!("{error:?}")),
    })?;
    let words = frozen.code.link(resolve).map_err(|error| match error {
        dm_ir::RelocationError::Unresolved(reference) => match reference {
            SymRef::SourceFile(origin) | SymRef::SourceLine(origin) => {
                LinkError::MissingDebugOrigin(origin)
            }
            _ => LinkError::MissingSymbol(reference),
        },
        dm_ir::RelocationError::PackedValueOverflow { offset, .. } => {
            let reference = frozen
                .code
                .relocations()
                .iter()
                .find(|relocation| relocation.offset == offset)
                .unwrap()
                .reference;
            LinkError::TooManyRecords(Table::of_reference(reference).unwrap())
        }
        _ => LinkError::Decode(format!("{error:?}")),
    })?;
    let relocations = frozen
        .code
        .relocations()
        .iter()
        .map(|site| (site.offset as usize, site.reference))
        .collect();
    Ok(LinkedProc {
        words,
        labels: frozen.labels,
        relocations,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{Instruction, LabelId, Ledger, SymbolId};
    fn instruction(opcode: u32, operands: Vec<Word>) -> Item {
        Item::Instruction(Instruction { opcode, operands })
    }
    #[test]
    fn referenced_formal_prefix_is_issued_by_typed_fresh_and_restored_operands() {
        for (variable, expected) in [
            (VariableWord::Arg(0), 1),
            (VariableWord::Arg(2), 3),
            (VariableWord::Args, 0),
        ] {
            let frozen = freeze_proc(&SymbolicProc {
                items: vec![instruction(
                    byond_dmb::bytecode::opcode::GET_VAR,
                    vec![Word::Variable(variable)],
                )],
            })
            .unwrap();
            assert_eq!(frozen.referenced_argument_prefix(), expected);
            let restored =
                FrozenProc::restore(frozen.code().clone(), frozen.labels().to_vec()).unwrap();
            assert_eq!(restored.referenced_argument_prefix(), expected);
        }
        assert!(
            freeze_proc(&SymbolicProc {
                items: vec![instruction(
                    byond_dmb::bytecode::opcode::GET_VAR,
                    vec![Word::Variable(VariableWord::Arg(u32::MAX))]
                )]
            })
            .is_err()
        );
    }
    #[test]
    fn frozen_shared_code_clones_share_immutable_word_and_relocation_owners() {
        let frozen = freeze_proc(&SymbolicProc {
            items: vec![instruction(0, vec![])],
        })
        .unwrap();
        let first = frozen.shared_code();
        let second = frozen.shared_code();
        assert!(std::sync::Arc::ptr_eq(&first, &second));
        assert!(std::ptr::eq(first.as_ref(), frozen.code()));
        assert_eq!(first.canonical_len(), first.canonical_bytes().len());
        drop(frozen);
        assert_eq!(first.words().as_ref(), [0]);
        assert!(second.relocations().is_empty());
    }
    #[test]
    fn debug_origins_and_numeric_branch_labels_are_direct_relocations() {
        let proc = SymbolicProc {
            items: vec![
                instruction(0x84, vec![Word::SourceFile(0)]),
                instruction(0x85, vec![Word::SourceLine(0)]),
                instruction(0xf, vec![Word::Branch(LabelId(0))]),
                Item::Label(LabelId(0)),
                instruction(0, vec![]),
            ],
        };
        let frozen = freeze_proc(&proc).unwrap();
        assert_eq!(
            frozen
                .code()
                .relocations()
                .iter()
                .map(|site| site.reference)
                .collect::<Vec<_>>(),
            [SymRef::SourceFile(0), SymRef::SourceLine(0)]
        );
        assert_eq!(
            frozen.code().words().as_ref(),
            [0x84, 0, 0x85, 0, 0xf, 6, 0]
        );
        assert_eq!(frozen.labels(), [Some(6)]);
        assert_eq!(
            frozen
                .code()
                .link(|reference| match reference {
                    SymRef::SourceFile(_) => Some(10),
                    SymRef::SourceLine(_) => Some(20),
                    _ => None,
                })
                .unwrap(),
            [0x84, 10, 0x85, 20, 0xf, 6, 0]
        );
    }
    #[test]
    fn packed_values_and_nested_selectors_emit_typed_sites_in_word_order() {
        let text = SymbolId::of("payload");
        let field = SymbolId::of("field");
        let proc = SymbolicProc {
            items: vec![
                instruction(0x60, vec![Word::Value(ValueWord::String(text))]),
                instruction(
                    0x33,
                    vec![Word::Variable(VariableWord::Initial(Box::new(
                        VariableWord::Field(field),
                    )))],
                ),
                instruction(0, vec![]),
            ],
        };
        let frozen = freeze_proc(&proc).unwrap();
        assert_eq!(
            frozen.code().words().as_ref(),
            [0x60, 0, 0, 0x33, 0xffe7, 0, 0]
        );
        assert_eq!(
            frozen.code().relocation(0).unwrap(),
            Relocation {
                offset: 1,
                reference: SymRef::String(text),
                encoding: OperandEncoding::PackedValue24 { tag: 6 }
            }
        );
        assert_eq!(frozen.code().relocation(1).unwrap().offset, 5);
        let mut sites = frozen.sites();
        assert_eq!(sites.len(), 2);
        assert_eq!(
            sites.next(),
            Some(OperandSite {
                offset: 1,
                kind: SymRef::String(text).kind(),
                encoding: OperandEncoding::PackedValue24 { tag: 6 },
            })
        );
        assert_eq!(sites.len(), 1);
        assert_eq!(
            sites.next_back(),
            Some(OperandSite {
                offset: 5,
                kind: SymRef::String(field).kind(),
                encoding: OperandEncoding::Direct,
            })
        );
        assert_eq!(sites.next(), None);

        assert_eq!(
            frozen.code().link(|_| Some(0x123456)).unwrap(),
            [0x60, 0x1206, 0x3456, 0x33, 0xffe7, 0x123456, 0]
        );
    }
    #[test]
    fn wrong_typed_reference_kind_is_rejected_before_linking() {
        let proc = SymbolicProc {
            items: vec![instruction(
                0x33,
                vec![Word::Variable(VariableWord::Global(SymRef::String(
                    SymbolId::of("bad"),
                )))],
            )],
        };
        assert!(matches!(
            freeze_proc(&proc),
            Err(FreezeError::Abi(LinkError::ReferenceKind { .. }))
        ));
    }
    #[test]
    fn procedure_namespace_and_mob_path_tag_remain_in_typed_relocations() {
        let owner = SymbolId::of("/mob/example");
        let name = SymbolId::of("call");
        let reference = SymRef::Verb {
            owner,
            name,
            occurrence: 3,
        };
        let proc = SymbolicProc {
            items: vec![
                instruction(0x60, vec![Word::Value(ValueWord::ProcPath(reference))]),
                instruction(
                    0x60,
                    vec![Word::Value(ValueWord::ClassPath {
                        path: owner,
                        tag: 8,
                    })],
                ),
                instruction(0, vec![]),
            ],
        };
        let frozen = freeze_proc(&proc).unwrap();
        assert_eq!(frozen.code().relocation(0).unwrap().reference, reference);
        assert_eq!(
            frozen.code().relocation(1).unwrap(),
            Relocation {
                offset: 4,
                reference: SymRef::Type(owner),
                encoding: OperandEncoding::PackedValue24 { tag: 8 },
            }
        );
    }
    #[test]
    fn number_and_native_primitive_values_need_no_relocations() {
        let bits = 1.5_f32.to_bits();
        let proc = SymbolicProc {
            items: vec![
                instruction(0x60, vec![Word::Value(ValueWord::Number(bits))]),
                instruction(
                    0x60,
                    vec![Word::Value(ValueWord::PrimitiveType(
                        crate::NativePrimitiveType::List,
                    ))],
                ),
                instruction(0, vec![]),
            ],
        };
        let frozen = freeze_proc(&proc).unwrap();
        assert_eq!(
            frozen.code().words().as_ref(),
            [0x60, 0x2a, bits >> 16, bits & 0xffff, 0x60, 40, 0, 0]
        );
        assert!(frozen.code().relocations().is_empty());
    }
    #[test]
    fn missing_label_and_debug_origin_are_reported_explicitly() {
        let branch = SymbolicProc {
            items: vec![instruction(0xf, vec![Word::Branch(LabelId(0))])],
        };
        assert!(matches!(
            freeze_proc(&branch),
            Err(FreezeError::Abi(LinkError::MissingLabel(LabelId(0))))
        ));
        let debug = SymbolicProc {
            items: vec![
                instruction(0x84, vec![Word::SourceFile(7)]),
                instruction(0, vec![]),
            ],
        };
        assert!(matches!(
            crate::link_proc(&debug, &Ledger::default()),
            Err(LinkError::MissingDebugOrigin(7))
        ));
    }
    #[test]
    fn malformed_instruction_and_illegal_branch_operand_are_rejected() {
        let malformed = SymbolicProc {
            items: vec![instruction(0, vec![Word::Immediate(1)])],
        };
        assert!(freeze_proc(&malformed).is_err());
        let branch = SymbolicProc {
            items: vec![
                instruction(0x60, vec![Word::Branch(LabelId(0)), Word::Immediate(0)]),
                Item::Label(LabelId(0)),
                instruction(0, vec![]),
            ],
        };
        assert!(matches!(
            freeze_proc(&branch),
            Err(FreezeError::Abi(LinkError::BranchOperandIsNotTarget { .. }))
        ));
    }
    #[test]
    fn sparse_and_duplicate_numeric_labels_are_rejected() {
        let sparse = SymbolicProc {
            items: vec![Item::Label(LabelId(u32::MAX))],
        };
        assert!(matches!(
            freeze_proc(&sparse),
            Err(FreezeError::Abi(LinkError::InvalidLabel(_)))
        ));
        let duplicate = SymbolicProc {
            items: vec![Item::Label(LabelId(0)), Item::Label(LabelId(0))],
        };
        assert!(matches!(
            freeze_proc(&duplicate),
            Err(FreezeError::Abi(LinkError::DuplicateLabel(_)))
        ));
    }
    #[test]
    fn packed_limit_is_checked_by_final_typed_linking() {
        let id = SymbolId::of("text");
        let proc = SymbolicProc {
            items: vec![
                instruction(0x60, vec![Word::Value(ValueWord::String(id))]),
                instruction(0, vec![]),
            ],
        };
        let mut ledger = Ledger::default();
        ledger.bind(SymRef::String(id), 0x1000000).unwrap();
        assert!(matches!(
            crate::link_proc(&proc, &ledger),
            Err(LinkError::TooManyRecords(Table::String))
        ));
    }
    #[test]
    fn observation_does_not_change_frozen_code_or_relocation_sites() {
        let proc = SymbolicProc {
            items: vec![instruction(0, vec![])],
        };
        let mut observed = Vec::new();
        let direct = freeze_proc(&proc).unwrap();
        let measured = freeze_proc_observed(&proc, |stage| observed.push(stage)).unwrap();
        assert_eq!(direct.code(), measured.code());
        assert_eq!(
            direct.sites().collect::<Vec<_>>(),
            measured.sites().collect::<Vec<_>>()
        );
        assert_eq!(observed.len(), 4);
    }
}
