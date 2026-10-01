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
mod simple;
pub mod debug;
pub mod dependencies;
pub use dependencies::{capture_binding_reads, BindingFact, BindingWitness, FactValue};
pub use simple::{
    compile_simple_proc, compile_simple_proc_with_bindings, compile_simple_proc_with_params,
    decode_constant_string_literal, nameof_reference, ArgumentMetadata, LowerBindings, LowerError,
    SharedLowerBindings, SimpleProc,
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

#[derive(Clone, Debug, Eq, PartialEq, Ord, PartialOrd, Hash, Serialize, Deserialize)]
pub struct Symbol {
    pub table: Table,
    /// Semantic linker key. It must not contain a Salsa intern ID.
    pub key: String,
}

impl Symbol {
    pub fn new(table: Table, key: impl Into<String>) -> Self {
        Self {
            table,
            key: key.into(),
        }
    }
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum Word {
    Immediate(u32),
    Reference(Symbol),
    /// Absolute word offset within this procedure's code list.
    Branch(String),
    Value(ValueWord),
    Variable(VariableWord),
}

/// BYOND's compound `V` operand. A number contains its IEEE-754 bit pattern;
/// string indices are relocated after the string ledger is frozen.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum ValueWord {
    Null,
    Number(u32),
    String(String),
    Resource(String),
    FileType,
    ClassPath { path: String, tag: u8 },
    ProcPath(String),
    /// A native modified-type instance, rather than a generated subtype.
    Instance(String),
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
    Field(String),
    StaticField(String),
    Initial(Box<VariableWord>),
    IsSaved(Box<VariableWord>),
    Global(String),
    DynamicProc(String),
    StaticProc(String),
    StaticVerb(String),
    SetCache(Box<VariableWord>, Box<VariableWord>),
}

impl Word {
    fn for_each_reference(&self, visit: &mut impl FnMut(Table, &str)) {
        match self {
            Self::Reference(symbol) => visit(symbol.table, &symbol.key),
            Self::Value(ValueWord::String(key)) => visit(Table::String, key),
            Self::Value(ValueWord::Resource(key)) => visit(Table::Resource, key),
            Self::Value(ValueWord::ClassPath { path, .. }) => visit(Table::Class, path),
            Self::Value(ValueWord::ProcPath(path)) => visit(Table::Proc, path),
            Self::Value(ValueWord::Instance(path)) => visit(Table::Instance, path),
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
    fn for_each_reference(&self, visit: &mut impl FnMut(Table, &str)) {
        match self {
            Self::Field(key) | Self::StaticField(key) | Self::DynamicProc(key) => {
                visit(Table::String, key)
            }
            Self::Global(key) => visit(Table::Variable, key),
            Self::StaticProc(path) | Self::StaticVerb(path) => visit(Table::Proc, path),
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
    Label(String),
    Instruction(Instruction),
}

#[derive(Clone, Debug, Default, Eq, PartialEq, Serialize, Deserialize)]
pub struct SymbolicProc {
    pub items: Vec<Item>,
}

impl SymbolicProc {
    /// Visit every external table symbol used by this procedure. Duplicate
    /// references are retained so callers can choose their own deduplication.
    pub fn for_each_reference(&self, mut visit: impl FnMut(Table, &str)) {
        for item in &self.items {
            if let Item::Instruction(instruction) = item {
                for operand in &instruction.operands {
                    operand.for_each_reference(&mut visit);
                }
            }
        }
    }
}

#[derive(Clone, Debug, Default, Eq, PartialEq)]
pub struct Ledger {
    ids: BTreeMap<Symbol, u32>,
    occupied_ids: BTreeSet<(Table, u32)>,
}

impl Ledger {
    /// Bind another spelling for an already allocated table payload. Callers
    /// must explicitly identify aliases; ordinary allocations use `bind`.
    pub fn bind_alias(&mut self, symbol: Symbol, id: u32) -> Result<(), LinkError> {
        if self.ids.contains_key(&symbol) {
            return Err(LinkError::DuplicateSymbol(symbol));
        }
        self.ids.insert(symbol, id);
        Ok(())
    }
    /// Bind an externally allocated table ID (for example from a native DMB
    /// scaffold). Existing IDs may have gaps; callers own their exact order.
    pub fn bind(&mut self, symbol: Symbol, id: u32) -> Result<(), LinkError> {
        if self.ids.contains_key(&symbol) {
            return Err(LinkError::DuplicateSymbol(symbol));
        }
        if self.occupied_ids.contains(&(symbol.table, id)) {
            return Err(LinkError::DuplicateId {
                table: symbol.table,
                id,
            });
        }
        self.occupied_ids.insert((symbol.table, id));
        self.ids.insert(symbol, id);
        Ok(())
    }
    /// Assign IDs in caller-provided serialized table order, never interner or
    /// hash-map iteration order. A separate ordered list is required per table.
    pub fn assign(
        &mut self,
        table: Table,
        ordered_keys: impl IntoIterator<Item = String>,
    ) -> Result<(), LinkError> {
        let keys: Vec<_> = ordered_keys.into_iter().collect();
        let mut seen = std::collections::BTreeSet::new();
        for key in &keys {
            let symbol = Symbol::new(table, key.clone());
            if self.ids.contains_key(&symbol) || !seen.insert(symbol.clone()) {
                return Err(LinkError::DuplicateSymbol(symbol));
            }
        }
        let mut next = self
            .ids
            .iter()
            .filter(|(symbol, _)| symbol.table == table)
            .map(|(_, id)| *id)
            .max()
            .map_or(0, |id| id as usize + 1);
        for key in keys {
            let id = u32::try_from(next).map_err(|_| LinkError::TooManyRecords(table))?;
            let symbol = Symbol::new(table, key);
            self.ids.insert(symbol, id);
            self.occupied_ids.insert((table, id));
            next += 1;
        }
        Ok(())
    }

    pub fn id(&self, symbol: &Symbol) -> Option<u32> {
        self.ids.get(symbol).copied()
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum LinkError {
    DuplicateSymbol(Symbol),
    DuplicateId { table: Table, id: u32 },
    TooManyRecords(Table),
    DuplicateLabel(String),
    MissingLabel(String),
    MissingSymbol(Symbol),
    OffsetOverflow,
    Decode(String),
    InstructionBoundary { expected: usize, decoded: usize },
    BranchOperandIsNotTarget { offset: usize },
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
    pub labels: BTreeMap<String, u32>,
    /// Word positions containing external table IDs. Used by the layout index
    /// to decide which serialized records depend on a table reordering.
    pub relocations: Vec<(usize, Symbol)>,
}

pub fn link_proc(proc: &SymbolicProc, ledger: &Ledger) -> Result<LinkedProc, LinkError> {
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
                        words.push(
                            ledger
                                .id(symbol)
                                .ok_or_else(|| LinkError::MissingSymbol(symbol.clone()))?,
                        );
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
                        let id = ledger
                            .id(&symbol)
                            .ok_or_else(|| LinkError::MissingSymbol(symbol.clone()))?;
                        if id > 0x00ff_ffff {
                            return Err(LinkError::TooManyRecords(Table::String));
                        }
                        relocations.push((slot, symbol));
                        words.extend([6 | ((id >> 16) << 8), id & 0xffff]);
                    }
                    Word::Value(ValueWord::Resource(key)) => {
                        let symbol = Symbol::new(Table::Resource, key);
                        let id = ledger
                            .id(&symbol)
                            .ok_or_else(|| LinkError::MissingSymbol(symbol.clone()))?;
                        if id > 0x00ff_ffff {
                            return Err(LinkError::TooManyRecords(Table::Resource));
                        }
                        relocations.push((slot, symbol));
                        words.extend([12 | ((id >> 16) << 8), id & 0xffff]);
                    }
                    Word::Value(ValueWord::FileType) => words.extend([39, 0]),
                    Word::Value(ValueWord::ClassPath { path, tag }) => {
                        let symbol = Symbol::new(Table::Class, path);
                        let id = ledger
                            .id(&symbol)
                            .ok_or_else(|| LinkError::MissingSymbol(symbol.clone()))?;
                        if id > 0x00ff_ffff {
                            return Err(LinkError::TooManyRecords(Table::Class));
                        }
                        relocations.push((slot, symbol));
                        words.extend([u32::from(*tag) | ((id >> 16) << 8), id & 0xffff]);
                    }
                    Word::Value(ValueWord::Instance(path)) => {
                        let symbol = Symbol::new(Table::Instance, path);
                        let id = ledger
                            .id(&symbol)
                            .ok_or_else(|| LinkError::MissingSymbol(symbol.clone()))?;
                        if id > 0x00ff_ffff {
                            return Err(LinkError::TooManyRecords(Table::Instance));
                        }
                        relocations.push((slot, symbol));
                        words.extend([41 | ((id >> 16) << 8), id & 0xffff]);
                    }
                    Word::Value(ValueWord::ProcPath(path)) => {
                        let symbol = Symbol::new(Table::Proc, path);
                        let id = ledger
                            .id(&symbol)
                            .ok_or_else(|| LinkError::MissingSymbol(symbol.clone()))?;
                        if id > 0x00ff_ffff {
                            return Err(LinkError::TooManyRecords(Table::Proc));
                        }
                        relocations.push((slot, symbol));
                        words.extend([38 | ((id >> 16) << 8), id & 0xffff]);
                    }
                    Word::Variable(variable) => {
                        encode_variable(variable, ledger, &mut words, &mut relocations)?
                    }
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
    Ok(LinkedProc {
        words,
        labels,
        relocations,
    })
}

fn encode_variable(
    variable: &VariableWord,
    ledger: &Ledger,
    words: &mut Vec<u32>,
    relocations: &mut Vec<(usize, Symbol)>,
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
            let id = ledger
                .id(&symbol)
                .ok_or_else(|| LinkError::MissingSymbol(symbol.clone()))?;
            if matches!(variable, VariableWord::Global(_)) {
                words.push(0xffdb);
            }
            if matches!(variable, VariableWord::DynamicProc(_)) {
                words.push(0xffdd);
            }
            if matches!(variable, VariableWord::StaticField(_)) {
                words.push(0xffe7);
            }
            relocations.push((words.len(), symbol));
            words.push(id);
        }
        VariableWord::StaticProc(path) | VariableWord::StaticVerb(path) => {
            let symbol = Symbol::new(Table::Proc, path);
            let id = ledger
                .id(&symbol)
                .ok_or_else(|| LinkError::MissingSymbol(symbol.clone()))?;
            words.push(if matches!(variable, VariableWord::StaticVerb(_)) { 0xffe0 } else { 0xffdf });
            relocations.push((words.len(), symbol));
            words.push(id);
        }
        VariableWord::SetCache(a, b) => {
            words.push(0xffdc);
            encode_variable(a, ledger, words, relocations)?;
            encode_variable(b, ledger, words, relocations)?;
        }
        VariableWord::Initial(variable) => {
            words.push(0xffe7);
            encode_variable(variable, ledger, words, relocations)?;
        }
        VariableWord::IsSaved(variable) => {
            words.push(0xffe8);
            encode_variable(variable, ledger, words, relocations)?;
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn table_ids_follow_explicit_order() {
        let mut ledger = Ledger::default();
        ledger
            .assign(Table::String, ["z".into(), "a".into()])
            .unwrap();
        assert_eq!(ledger.id(&Symbol::new(Table::String, "z")), Some(0));
        assert_eq!(ledger.id(&Symbol::new(Table::String, "a")), Some(1));
        assert!(matches!(
            ledger.assign(Table::String, ["z".into()]),
            Err(LinkError::DuplicateSymbol(_))
        ));
    }

    #[test]
    fn duplicate_ids_are_checked_within_each_table_after_assign_and_bind() {
        let mut ledger = Ledger::default();
        ledger
            .assign(Table::String, ["first".into(), "second".into()])
            .unwrap();
        assert!(matches!(
            ledger.bind(Symbol::new(Table::String, "third"), 1),
            Err(LinkError::DuplicateId {
                table: Table::String,
                id: 1
            })
        ));
        ledger
            .bind(Symbol::new(Table::Variable, "first"), 1)
            .unwrap();
        ledger.bind(Symbol::new(Table::String, "third"), 4).unwrap();
        assert!(matches!(
            ledger.bind(Symbol::new(Table::String, "fourth"), 4),
            Err(LinkError::DuplicateId {
                table: Table::String,
                id: 4
            })
        ));
        ledger.assign(Table::String, ["fifth".into()]).unwrap();
        assert_eq!(ledger.id(&Symbol::new(Table::String, "fifth")), Some(5));
    }

    #[test]
    fn symbolic_proc_visits_nested_external_references() {
        let proc = SymbolicProc {
            items: vec![Item::Instruction(Instruction {
                opcode: 0,
                operands: vec![
                    Word::Reference(Symbol::new(Table::Proc, "/proc/direct")),
                    Word::Value(ValueWord::ProcPath("/proc/path".into())),
                    Word::Value(ValueWord::ClassPath {
                        path: "/datum/example".into(),
                        tag: 32,
                    }),
                    Word::Value(ValueWord::String("text".into())),
                    Word::Value(ValueWord::Resource("file.dmi".into())),
                    Word::Variable(VariableWord::SetCache(
                        Box::new(VariableWord::Initial(Box::new(VariableWord::Global(
                            "global_name".into(),
                        )))),
                        Box::new(VariableWord::IsSaved(Box::new(VariableWord::DynamicProc(
                            "method_name".into(),
                        )))),
                    )),
                    Word::Variable(VariableWord::StaticProc(
                        "/datum/example/proc/method".into(),
                    )),
                ],
            })],
        };
        let mut actual = Vec::new();
        proc.for_each_reference(|table, key| actual.push((table, key.to_owned())));
        assert_eq!(
            actual,
            [
                (Table::Proc, "/proc/direct"),
                (Table::Proc, "/proc/path"),
                (Table::Class, "/datum/example"),
                (Table::String, "text"),
                (Table::Resource, "file.dmi"),
                (Table::Variable, "global_name"),
                (Table::String, "method_name"),
                (Table::Proc, "/datum/example/proc/method"),
            ]
            .map(|(table, key)| (table, key.to_owned()))
        );
    }

    #[test]
    fn static_proc_selector_links_by_procedure_id() {
        let path = "/datum/example/proc/method";
        let proc = SymbolicProc {
            items: vec![Item::Instruction(Instruction {
                opcode: 0x29,
                operands: vec![
                    Word::Variable(VariableWord::SetCache(
                        Box::new(VariableWord::Arg(0)),
                        Box::new(VariableWord::StaticProc(path.into())),
                    )),
                    Word::Immediate(0),
                ],
            })],
        };
        let mut ledger = Ledger::default();
        ledger.bind(Symbol::new(Table::Proc, path), 17).unwrap();
        let linked = link_proc(&proc, &ledger).unwrap();
        assert_eq!(linked.words, [0x29, 0xffdc, 0xffd9, 0, 0xffdf, 17, 0]);
        assert_eq!(
            linked.relocations,
            vec![(5, Symbol::new(Table::Proc, path))]
        );
    }

    #[test]
    fn branch_label_relocates_after_instruction_size() {
        // Native jump opcode 0xf has a one-word absolute destination.
        let proc = SymbolicProc {
            items: vec![
                Item::Instruction(Instruction {
                    opcode: 0xf,
                    operands: vec![Word::Branch("end".into())],
                }),
                Item::Label("end".into()),
                Item::Instruction(Instruction {
                    opcode: 0x0,
                    operands: vec![],
                }),
            ],
        };
        let linked = link_proc(&proc, &Ledger::default()).unwrap();
        assert_eq!(linked.words[1], 2);
        assert_eq!(linked.labels["end"], 2);
    }

    #[test]
    fn missing_symbol_is_a_link_error() {
        let proc = SymbolicProc {
            items: vec![Item::Instruction(Instruction {
                opcode: 0x0,
                operands: vec![Word::Reference(Symbol::new(Table::String, "x"))],
            })],
        };
        assert!(matches!(
            link_proc(&proc, &Ledger::default()),
            Err(LinkError::MissingSymbol(_))
        ));
    }

    #[test]
    fn symbolic_lowering_round_trips_through_disk_encoding() {
        let ast = dm_syntax::parse("/proc/test(obj/O)\n    return O.child.name\n");
        let proc = compile_simple_proc_with_params(&ast.items[0].children, &["O".into()]).unwrap();
        let encoded = serde_json::to_vec(&proc).unwrap();
        let restored: SimpleProc = serde_json::from_slice(&encoded).unwrap();
        assert_eq!(restored, proc);
        assert_eq!(restored.code, proc.code);

        let mut bindings = LowerBindings::default();
        bindings.parameters.push("O".into());
        bindings.fields.insert("child".into());
        bindings
            .field_types
            .insert("child".into(), "/datum/child".into());
        bindings.globals.insert("shared".into());
        bindings
            .global_types
            .insert("shared".into(), "/datum/shared".into());
        let encoded = serde_json::to_vec(&bindings).unwrap();
        let restored: LowerBindings = serde_json::from_slice(&encoded).unwrap();
        assert_eq!(restored, bindings);
    }
}
