//! A symbolic boundary between DM lowering and BYOND's indexed wire format.
//!
//! The final decoder rejects an instruction whose produced words do not match
//! the target ABI. Table references remain symbolic until link time.

use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, BTreeSet};
use std::fmt;

/// Linker identity of BYOND's global variable-list builtin. Kept distinct
/// from ordinary declarations and statics whose source name is `vars`.
pub const BUILTIN_GLOBAL_VARS_SYMBOL: &str = "@builtin/global.vars";

mod builtin_catalog;
pub use builtin_catalog::is_intrinsic_named_call;
pub mod encoder;
pub use encoder::{freeze_proc, FreezeError, FrozenProc, OperandEncoding, OperandSite};
pub mod initializer;
mod lower_diagnostics;
pub mod lower_resolver;
pub mod parameter_abi;
pub mod procedure_abi;
mod retained_capacity;
mod simple;
pub mod typed_scopes;
pub use lower_resolver::ProcedureInputs;
pub use simple::{
    compile_preparsed_lossless_with_resolver, compile_simple_proc,
    compile_simple_proc_with_bindings, compile_simple_proc_with_params,
    compile_simple_proc_with_resolver, compile_simple_proc_with_resolver_and_debug,
    compile_statement_view_with_resolver, compile_statement_view_with_resolver_and_references,
    compile_statement_view_with_resolver_and_references_at, compile_typed_scopes_with_resolver,
    compile_typed_statements_with_resolver, decode_constant_string_literal, nameof_reference,
    observe_reference_source_features, observe_reference_source_features_with_lexical_locals,
    typed_statement_view_supported, typed_statements_supported,
    typed_statements_supported_for_capture, ArgumentMetadata, DebugSourceProvider,
    DiagnosticAnchor, LowerBindings, LowerError, LowerErrorKind, LowerRelated, LowerSpan,
    ProcedureWarning, SharedLowerBindings, SimpleProc, SourceFeatures,
};

#[derive(Clone, Copy, Debug, Eq, PartialEq, Ord, PartialOrd, Hash, Serialize, Deserialize)]
pub enum Table {
    String,
    Class,
    Proc,
    Variable,
    List,
    Resource,
    Instance,
}

pub use dm_ir::{StringPayload, StringRoster, SymRef, SymbolId};

#[derive(Clone, Copy, Debug, Eq, PartialEq, Ord, PartialOrd, Hash, Serialize, Deserialize)]
pub struct LabelId(pub u32);

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum Word {
    Immediate(u32),
    SourceFile(u32),
    SourceLine(u32),
    Reference(SymRef),
    /// Absolute word offset within this procedure's code list.
    Branch(LabelId),
    Value(ValueWord),
    Variable(VariableWord),
}

/// BYOND's compound `V` operand. A number contains its IEEE-754 bit pattern;
/// string indices are relocated after the string ledger is frozen.
#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum NativePrimitiveType {
    List,
    Savefile,
}
impl NativePrimitiveType {
    pub fn from_path(path: &str) -> Option<Self> {
        match path {
            "/list" => Some(Self::List),
            "/savefile" => Some(Self::Savefile),
            _ => None,
        }
    }
    pub fn from_symbol(path: dm_ir::SymbolId) -> Option<Self> {
        [Self::List, Self::Savefile]
            .into_iter()
            .find(|kind| dm_ir::SymbolId::of(kind.path()) == path)
    }
    pub fn path(self) -> &'static str {
        match self {
            Self::List => "/list",
            Self::Savefile => "/savefile",
        }
    }
    pub fn tag(self) -> u8 {
        match self {
            Self::List => 40,
            Self::Savefile => 36,
        }
    }
}
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum ValueWord {
    Null,
    Number(u32),
    String(SymbolId),
    Resource(u128),
    FileType,
    /// Pinned native primitive: typed tag with zero payload, no class table row.
    PrimitiveType(NativePrimitiveType),
    ClassPath {
        path: SymbolId,
        tag: u8,
    },
    ProcPath(SymRef),
    /// A native modified-type instance, rather than a generated subtype.
    Instance(SymbolId),
}

/// BYOND's compound `v` operand. Field/global names use string-table IDs.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum VariableWord {
    Arg(u32),
    Local(u32),
    Src,
    Usr,
    World,
    Args,
    Caller,
    Callee,
    Null,
    Dot,
    Cache,
    CacheKey,
    CacheIndex,
    Field(SymbolId),
    StaticField(SymbolId),
    Initial(Box<VariableWord>),
    IsSaved(Box<VariableWord>),
    Global(SymRef),
    DynamicProc(SymbolId),
    StaticProc(SymRef),
    StaticVerb(SymRef),
    SetCache(Box<VariableWord>, Box<VariableWord>),
    DynamicVerb(SymbolId),
}

impl Word {
    fn for_each_reference(&self, visit: &mut impl FnMut(SymRef)) {
        match self {
            Self::Reference(reference) => visit(*reference),
            Self::SourceFile(origin) => visit(SymRef::SourceFile(*origin)),
            Self::SourceLine(origin) => visit(SymRef::SourceLine(*origin)),
            Self::Value(ValueWord::String(id)) => visit(SymRef::String(*id)),
            Self::Value(ValueWord::Resource(content)) => visit(SymRef::Resource(*content)),
            Self::Value(ValueWord::ClassPath { path, .. }) => visit(SymRef::Type(*path)),
            Self::Value(ValueWord::ProcPath(reference)) => visit(*reference),
            Self::Value(ValueWord::Instance(id)) => visit(SymRef::Instance(*id)),
            Self::Variable(variable) => variable.for_each_reference(visit),
            _ => {}
        }
    }

    fn width(&self) -> usize {
        match self {
            Word::Value(ValueWord::Number(_)) => 3,
            Word::Value(_) => 2,
            Word::Variable(variable) => variable.width(),
            _ => 1,
        }
    }
}

impl VariableWord {
    fn for_each_reference(&self, visit: &mut impl FnMut(SymRef)) {
        match self {
            Self::Field(id)
            | Self::StaticField(id)
            | Self::DynamicProc(id)
            | Self::DynamicVerb(id) => visit(SymRef::String(*id)),
            Self::Global(reference) | Self::StaticProc(reference) | Self::StaticVerb(reference) => {
                visit(*reference)
            }
            Self::Initial(variable) | Self::IsSaved(variable) => variable.for_each_reference(visit),
            Self::SetCache(a, b) => {
                a.for_each_reference(visit);
                b.for_each_reference(visit);
            }
            _ => {}
        }
    }

    fn width(&self) -> usize {
        match self {
            Self::Arg(_)
            | Self::Local(_)
            | Self::Global(_)
            | Self::DynamicProc(_)
            | Self::DynamicVerb(_)
            | Self::StaticProc(_)
            | Self::StaticVerb(_)
            | Self::StaticField(_) => 2,
            Self::SetCache(a, b) => 1 + a.width() + b.width(),
            Self::Initial(variable) | Self::IsSaved(variable) => 1 + variable.width(),
            _ => 1,
        }
    }
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct Instruction {
    pub opcode: u32,
    pub operands: Vec<Word>,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum Item {
    Label(LabelId),
    Instruction(Instruction),
}

#[derive(Clone, Debug, Default, Eq, PartialEq, Serialize, Deserialize)]
pub struct SymbolicProc {
    pub items: Vec<Item>,
}

impl SymbolicProc {
    /// Visit every external table symbol used by this procedure. Duplicate
    /// references are retained so callers can choose their own deduplication.
    pub fn for_each_reference(&self, mut visit: impl FnMut(SymRef)) {
        for item in &self.items {
            if let Item::Instruction(instruction) = item {
                for operand in &instruction.operands {
                    operand.for_each_reference(&mut visit);
                }
            }
        }
    }
}

/// Explicit fixture/client wire IDs, keyed by the same typed references as production.
/// Production canonical linking lives in dm-link; this contains no spelling binder.
#[derive(Clone, Debug, Default, Eq, PartialEq)]
pub struct Ledger {
    ids: BTreeMap<SymRef, u32>,
    occupied_ids: BTreeSet<(Table, u32)>,
}
impl Table {
    pub fn of_reference(reference: SymRef) -> Option<Self> {
        use dm_ir::RelocationKind as K;
        Some(match reference.kind() {
            K::String => Self::String,
            K::Type => Self::Class,
            K::Procedure => Self::Proc,
            K::Variable => Self::Variable,
            K::List => Self::List,
            K::Resource => Self::Resource,
            K::Instance => Self::Instance,
            K::SourceLine => return None,
        })
    }
}
impl Ledger {
    pub fn bind_alias(&mut self, reference: SymRef, id: u32) -> Result<(), LinkError> {
        if self.ids.contains_key(&reference) {
            return Err(LinkError::DuplicateSymbol(reference));
        }
        self.ids.insert(reference, id);
        Ok(())
    }
    pub fn bind(&mut self, reference: SymRef, id: u32) -> Result<(), LinkError> {
        let table = Table::of_reference(reference).ok_or(LinkError::InvalidReference(reference))?;
        if self.ids.contains_key(&reference) {
            return Err(LinkError::DuplicateSymbol(reference));
        }
        if !self.occupied_ids.insert((table, id)) {
            return Err(LinkError::DuplicateId { table, id });
        }
        self.ids.insert(reference, id);
        Ok(())
    }
    pub fn assign(
        &mut self,
        table: Table,
        references: impl IntoIterator<Item = SymRef>,
    ) -> Result<(), LinkError> {
        let references: Vec<_> = references.into_iter().collect();
        let mut seen = BTreeSet::new();
        for &reference in &references {
            if Table::of_reference(reference) != Some(table) {
                return Err(LinkError::InvalidReference(reference));
            }
            if self.ids.contains_key(&reference) || !seen.insert(reference) {
                return Err(LinkError::DuplicateSymbol(reference));
            }
        }
        let next = self
            .ids
            .iter()
            .filter(|(reference, _)| Table::of_reference(**reference) == Some(table))
            .map(|(_, id)| *id)
            .max()
            .map_or(0, |id| u64::from(id) + 1);
        // Validate all output IDs before mutation.
        if next + references.len() as u64 > u64::from(u32::MAX) + 1 {
            return Err(LinkError::TooManyRecords(table));
        }
        for (offset, reference) in references.into_iter().enumerate() {
            let id = u32::try_from(next + offset as u64)
                .map_err(|_| LinkError::TooManyRecords(table))?;
            self.ids.insert(reference, id);
            self.occupied_ids.insert((table, id));
        }
        Ok(())
    }
    pub fn id(&self, reference: &SymRef) -> Option<u32> {
        self.ids.get(reference).copied()
    }
}
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum LinkError {
    DuplicateSymbol(SymRef),
    DuplicateId {
        table: Table,
        id: u32,
    },
    TooManyRecords(Table),
    DuplicateLabel(LabelId),
    MissingLabel(LabelId),
    InvalidLabel(LabelId),
    MissingSymbol(SymRef),
    InvalidReference(SymRef),
    ReferenceKind {
        expected: dm_ir::RelocationKind,
        actual: dm_ir::RelocationKind,
    },
    OffsetOverflow,
    MissingDebugOrigin(u32),
    Decode(String),
    InstructionBoundary {
        expected: usize,
        decoded: usize,
    },
    BranchOperandIsNotTarget {
        offset: usize,
    },
}
impl fmt::Display for LinkError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{self:?}")
    }
}
impl std::error::Error for LinkError {}
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct LinkedProc {
    pub words: Vec<u32>,
    pub labels: Vec<Option<u32>>,
    pub relocations: Vec<(usize, SymRef)>,
}
pub fn link_proc(proc: &SymbolicProc, ledger: &Ledger) -> Result<LinkedProc, LinkError> {
    encoder::link(proc, |reference| ledger.id(&reference))
}

#[cfg(test)]
mod tests {
    use super::*;
    fn string(value: &str) -> SymRef {
        SymRef::String(SymbolId::of(value))
    }
    #[test]
    fn table_ids_follow_explicit_order() {
        let mut ledger = Ledger::default();
        ledger
            .assign(Table::String, [string("z"), string("a")])
            .unwrap();
        assert_eq!(ledger.id(&string("z")), Some(0));
        assert_eq!(ledger.id(&string("a")), Some(1));
        assert!(matches!(
            ledger.assign(Table::String, [string("z")]),
            Err(LinkError::DuplicateSymbol(_))
        ));
    }
    #[test]
    fn duplicate_ids_are_checked_in_each_typed_table() {
        let mut ledger = Ledger::default();
        ledger
            .assign(Table::String, [string("first"), string("second")])
            .unwrap();
        assert!(matches!(
            ledger.bind(string("third"), 1),
            Err(LinkError::DuplicateId { .. })
        ));
        ledger
            .bind(SymRef::VariableSlot(SymbolId::of("first")), 1)
            .unwrap();
        ledger.bind(string("third"), 4).unwrap();
        ledger.assign(Table::String, [string("fifth")]).unwrap();
        assert_eq!(ledger.id(&string("fifth")), Some(5));
    }
    #[test]
    fn reference_traversal_keeps_typed_identity_and_debug_origins() {
        let slot = SymRef::VariableSlot(SymbolId::of("global"));
        let proc = SymbolicProc {
            items: vec![Item::Instruction(Instruction {
                opcode: 0,
                operands: vec![
                    Word::Reference(string("direct")),
                    Word::SourceFile(3),
                    Word::Value(ValueWord::Resource(123)),
                    Word::Variable(VariableWord::Initial(Box::new(VariableWord::Global(slot)))),
                ],
            })],
        };
        let mut refs = Vec::new();
        proc.for_each_reference(|reference| refs.push(reference));
        assert_eq!(
            refs,
            [
                string("direct"),
                SymRef::SourceFile(3),
                SymRef::Resource(123),
                slot
            ]
        );
    }
    #[test]
    fn typed_proc_roundtrips_without_text_binder() {
        let proc = SymbolicProc {
            items: vec![
                Item::Label(LabelId(0)),
                Item::Instruction(Instruction {
                    opcode: 0xf,
                    operands: vec![Word::Branch(LabelId(0))],
                }),
            ],
        };
        let bytes = serde_json::to_vec(&proc).unwrap();
        assert_eq!(
            serde_json::from_slice::<SymbolicProc>(&bytes).unwrap(),
            proc
        );
        assert_eq!(
            link_proc(&proc, &Ledger::default()).unwrap().words,
            [0xf, 0]
        );
    }
}

#[cfg(test)]
#[path = "parameter_scope_tests.rs"]
mod parameter_scope_tests;
