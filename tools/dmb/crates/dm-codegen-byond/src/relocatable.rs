//! Validated procedure sections. Local control flow is resolved once; table IDs
//! remain relocatable. Source origins belong to the caller's separate sidecar.
use crate::{link_proc, Item, Ledger, LinkError, Symbol, SymbolicProc, Table, ValueWord, Word};
use std::collections::{BTreeMap, BTreeSet};

const MAGIC: &[u8; 8] = b"DMPROC02";
const MAX_BYTES: usize = 16 * 1024 * 1024;
const MAX_WORDS: usize = 2 * 1024 * 1024;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum Encoding {
    Plain,
    Packed(u8),
}
#[derive(Clone, Debug, Eq, PartialEq)]
struct Relocation {
    offset: u32,
    symbol: u32,
    encoding: Encoding,
}

/// Private fields prevent an unvalidated section entering the materializer.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct PreparedProc {
    words: Vec<u32>,
    symbols: Vec<Symbol>,
    relocations: Vec<Relocation>,
    item_offsets: Vec<u32>,
    branch_slots: Vec<u32>,
}

impl PreparedProc {
    pub fn resident_bytes(&self) -> usize {
        self.words.capacity() * 4
            + self.item_offsets.capacity() * 4
            + self.branch_slots.capacity() * 4
            + self.relocations.capacity() * std::mem::size_of::<Relocation>()
            + self.symbols.capacity() * std::mem::size_of::<Symbol>()
            + self
                .symbols
                .iter()
                .map(|symbol| symbol.key.capacity())
                .sum::<usize>()
    }
    pub fn prepare(source: &SymbolicProc) -> Result<Self, LinkError> {
        let mut unique = BTreeSet::new();
        source.for_each_reference(|table, key| {
            unique.insert(Symbol::new(table, key));
        });
        let symbols: Vec<_> = unique.into_iter().collect();
        let mut ledger = Ledger::default();
        for symbol in &symbols {
            ledger.bind_alias(symbol.clone(), 0)?;
        }
        // This is the only instruction/control-flow validation on fresh code.
        let linked = link_proc(source, &ledger)?;
        let ids: BTreeMap<_, _> = symbols
            .iter()
            .enumerate()
            .map(|(i, s)| (s.clone(), i as u32))
            .collect();
        let mut packed = BTreeMap::new();
        let mut offset = 0usize;
        let mut item_offsets = Vec::with_capacity(source.items.len());
        let mut branch_slots = Vec::new();
        for item in &source.items {
            item_offsets.push(if matches!(item, Item::Instruction(_)) {
                offset as u32
            } else {
                u32::MAX
            });
            if let Item::Instruction(instruction) = item {
                offset += 1;
                for operand in &instruction.operands {
                    if matches!(operand, Word::Branch(_)) {
                        branch_slots.push(offset as u32);
                    }
                    let tag = match operand {
                        Word::Value(ValueWord::String(_)) => Some(6),
                        Word::Value(ValueWord::Resource(_)) => Some(12),
                        Word::Value(ValueWord::ClassPath { tag, .. }) => Some(*tag),
                        Word::Value(ValueWord::ProcPath(_)) => Some(38),
                        Word::Value(ValueWord::Instance(_)) => Some(41),
                        _ => None,
                    };
                    if let Some(tag) = tag {
                        packed.insert(offset, tag);
                    }
                    offset += operand.width();
                }
            }
        }
        let relocations = linked
            .relocations
            .into_iter()
            .map(|(offset, symbol)| Relocation {
                offset: offset as u32,
                symbol: ids[&symbol],
                encoding: packed
                    .get(&offset)
                    .copied()
                    .map_or(Encoding::Plain, Encoding::Packed),
            })
            .collect();
        let prepared = Self {
            words: linked.words,
            symbols,
            relocations,
            item_offsets,
            branch_slots,
        };
        prepared.validate()?;
        Ok(prepared)
    }

    pub fn word_count(&self) -> usize {
        self.words.len()
    }
    /// Insert current source locations without reconstructing symbolic code.
    /// Targets land before inserted debug instructions, including label targets.
    pub fn materialize_with_debug(
        &self,
        ledger: &Ledger,
        marks: &[crate::debug::StatementOrigin],
        mut resolve: impl FnMut(usize) -> Option<(u32, u32)>,
    ) -> Result<Vec<u32>, LinkError> {
        let mut debug = BTreeMap::new();
        let mut previous = None;
        for mark in marks {
            if previous.is_some_and(|index| index >= mark.code_item) || mark.end < mark.start {
                return Err(invalid("invalid statement anchor"));
            }
            let offset = *self
                .item_offsets
                .get(mark.code_item)
                .ok_or_else(|| invalid("statement anchor outside section"))?;
            if offset == u32::MAX {
                return Err(invalid("statement anchor targets label"));
            }
            if let Some((file, line)) = resolve(mark.start) {
                if line == 0 {
                    return Err(invalid("invalid debug line"));
                }
                debug.insert(offset as usize, (file, line));
            }
            previous = Some(mark.code_item);
        }
        let words = self.materialize(ledger)?;
        if debug.is_empty() {
            return Ok(words);
        }
        let extra = debug
            .len()
            .checked_mul(4)
            .ok_or(LinkError::OffsetOverflow)?;
        let length = words
            .len()
            .checked_add(extra)
            .filter(|n| *n <= MAX_WORDS)
            .ok_or(LinkError::OffsetOverflow)?;
        let mut before = Vec::with_capacity(words.len() + 1);
        let mut shift = 0usize;
        for offset in 0..=words.len() {
            before.push(shift);
            if debug.contains_key(&offset) {
                shift += 4;
            }
        }
        let branches: BTreeSet<_> = self
            .branch_slots
            .iter()
            .map(|slot| *slot as usize)
            .collect();
        let mut result = Vec::with_capacity(length);
        for (offset, word) in words.into_iter().enumerate() {
            if let Some((file, line)) = debug.get(&offset) {
                result.extend([
                    byond_dmb::bytecode::opcode::DBG_FILE,
                    *file,
                    byond_dmb::bytecode::opcode::DBG_LINE,
                    *line,
                ]);
            }
            if branches.contains(&offset) {
                let target = word as usize;
                let delta = *before
                    .get(target)
                    .ok_or_else(|| invalid("branch target outside section"))?;
                result.push(u32::try_from(target + delta).map_err(|_| LinkError::OffsetOverflow)?);
            } else {
                result.push(word);
            }
        }
        Ok(result)
    }
    pub fn for_each_reference(&self, mut visit: impl FnMut(Table, &str)) {
        for symbol in &self.symbols {
            visit(symbol.table, &symbol.key);
        }
    }
    /// No symbolic-tree traversal, decoder, or local-branch resolution occurs.
    pub fn materialize(&self, ledger: &Ledger) -> Result<Vec<u32>, LinkError> {
        let ids: Result<Vec<_>, _> = self
            .symbols
            .iter()
            .map(|symbol| {
                ledger
                    .id(symbol)
                    .ok_or_else(|| LinkError::MissingSymbol(symbol.clone()))
            })
            .collect();
        let ids = ids?;
        let mut words = self.words.clone();
        for relocation in &self.relocations {
            let id = ids[relocation.symbol as usize];
            let at = relocation.offset as usize;
            match relocation.encoding {
                Encoding::Plain => words[at] = id,
                Encoding::Packed(tag) => {
                    if id > 0x00ff_ffff {
                        return Err(LinkError::TooManyRecords(
                            self.symbols[relocation.symbol as usize].table,
                        ));
                    }
                    words[at] = u32::from(tag) | ((id >> 16) << 8);
                    words[at + 1] = id & 0xffff;
                }
            }
        }
        Ok(words)
    }

    fn validate(&self) -> Result<(), LinkError> {
        if self.words.len() > MAX_WORDS
            || self.item_offsets.len() > MAX_WORDS
            || self.branch_slots.len() > MAX_WORDS
            || self.symbols.len() > MAX_WORDS
            || self.relocations.len() > MAX_WORDS
        {
            return Err(invalid("section exceeds limits"));
        }
        let decoded =
            byond_dmb::bytecode::decode(&self.words).map_err(|e| invalid(&format!("{e:?}")))?;
        let starts: BTreeSet<_> = decoded
            .iter()
            .map(|instruction| instruction.offset)
            .collect();
        let legal_branches: BTreeSet<_> = decoded
            .iter()
            .map(|instruction| {
                instruction
                    .branch_target_word_offsets()
                    .map_err(|e| invalid(&format!("{e:?}")))
            })
            .collect::<Result<Vec<_>, _>>()?
            .into_iter()
            .flatten()
            .collect();
        let mut seen_branches = BTreeSet::new();
        for slot in &self.branch_slots {
            let slot = *slot as usize;
            if !legal_branches.contains(&slot)
                || !seen_branches.insert(slot)
                || self.words[slot] as usize > self.words.len()
            {
                return Err(invalid("invalid branch sidecar"));
            }
        }
        for offset in &self.item_offsets {
            if *offset != u32::MAX && !starts.contains(&(*offset as usize)) {
                return Err(invalid("invalid item offset"));
            }
        }
        let mut slots = BTreeSet::new();
        for relocation in &self.relocations {
            let at = relocation.offset as usize;
            if relocation.symbol as usize >= self.symbols.len()
                || at >= self.words.len()
                || !slots.insert(at)
            {
                return Err(invalid("invalid relocation"));
            }
            if starts.contains(&at) {
                return Err(invalid("relocation targets opcode"));
            }
            if let Encoding::Packed(tag) = relocation.encoding {
                if at + 1 >= self.words.len()
                    || self.words[at] != u32::from(tag)
                    || self.words[at + 1] != 0
                    || !slots.insert(at + 1)
                {
                    return Err(invalid("invalid packed relocation"));
                }
            } else if self.words[at] != 0 {
                return Err(invalid("nonzero relocation placeholder"));
            }
        }
        Ok(())
    }

    /// Versioned flat codec; decoded sections are validated before use.
    pub fn encode(&self) -> Result<Vec<u8>, LinkError> {
        let mut bytes = MAGIC.to_vec();
        put(&mut bytes, self.words.len() as u32);
        put(&mut bytes, self.symbols.len() as u32);
        put(&mut bytes, self.relocations.len() as u32);
        put(&mut bytes, self.item_offsets.len() as u32);
        put(&mut bytes, self.branch_slots.len() as u32);
        for word in &self.words {
            put(&mut bytes, *word);
        }
        for symbol in &self.symbols {
            bytes.push(table_byte(symbol.table));
            put(&mut bytes, symbol.key.len() as u32);
            bytes.extend_from_slice(symbol.key.as_bytes());
        }
        for relocation in &self.relocations {
            put(&mut bytes, relocation.offset);
            put(&mut bytes, relocation.symbol);
            bytes.push(match relocation.encoding {
                Encoding::Plain => 0,
                Encoding::Packed(_) => 1,
            });
            bytes.push(match relocation.encoding {
                Encoding::Plain => 0,
                Encoding::Packed(tag) => tag,
            });
        }
        for offset in &self.item_offsets {
            put(&mut bytes, *offset);
        }
        for slot in &self.branch_slots {
            put(&mut bytes, *slot);
        }
        if bytes.len() > MAX_BYTES {
            return Err(invalid("encoded section exceeds limit"));
        }
        Ok(bytes)
    }
    pub fn decode(bytes: &[u8]) -> Result<Self, LinkError> {
        if bytes.len() > MAX_BYTES || bytes.get(..8) != Some(MAGIC.as_slice()) {
            return Err(invalid("invalid section header"));
        }
        let mut cursor = Cursor { bytes, at: 8 };
        let nw = cursor.count()?;
        let ns = cursor.count()?;
        let nr = cursor.count()?;
        let ni = cursor.count()?;
        let nb = cursor.count()?;
        // Counts cannot induce allocations larger than their encoded input.
        if nw > cursor.remaining() / 4
            || ns > cursor.remaining() / 5
            || nr > cursor.remaining() / 10
        {
            return Err(invalid("truncated section counts"));
        }
        let mut words = Vec::with_capacity(nw);
        for _ in 0..nw {
            words.push(cursor.u32()?);
        }
        let mut symbols = Vec::with_capacity(ns);
        let mut seen = BTreeSet::new();
        for _ in 0..ns {
            let table = byte_table(cursor.byte()?)?;
            let length = cursor.u32()? as usize;
            let key = std::str::from_utf8(cursor.take(length)?)
                .map_err(|_| invalid("invalid symbol UTF-8"))?
                .to_owned();
            let symbol = Symbol::new(table, key);
            if !seen.insert(symbol.clone()) {
                return Err(invalid("duplicate symbol"));
            }
            symbols.push(symbol);
        }
        let mut relocations = Vec::with_capacity(nr);
        for _ in 0..nr {
            let offset = cursor.u32()?;
            let symbol = cursor.u32()?;
            let kind = cursor.byte()?;
            let tag = cursor.byte()?;
            let encoding = match (kind, tag) {
                (0, 0) => Encoding::Plain,
                (1, tag) => Encoding::Packed(tag),
                _ => return Err(invalid("invalid relocation encoding")),
            };
            relocations.push(Relocation {
                offset,
                symbol,
                encoding,
            });
        }
        let mut item_offsets = Vec::with_capacity(ni);
        for _ in 0..ni {
            item_offsets.push(cursor.u32()?);
        }
        let mut branch_slots = Vec::with_capacity(nb);
        for _ in 0..nb {
            branch_slots.push(cursor.u32()?);
        }
        if cursor.remaining() != 0 {
            return Err(invalid("trailing section bytes"));
        }
        let section = Self {
            words,
            symbols,
            relocations,
            item_offsets,
            branch_slots,
        };
        section.validate()?;
        Ok(section)
    }
}

fn invalid(reason: &str) -> LinkError {
    LinkError::Decode(reason.to_owned())
}
fn put(bytes: &mut Vec<u8>, value: u32) {
    bytes.extend_from_slice(&value.to_le_bytes());
}
fn table_byte(table: Table) -> u8 {
    match table {
        Table::String => 0,
        Table::Class => 1,
        Table::Proc => 2,
        Table::Variable => 3,
        Table::List => 4,
        Table::Resource => 5,
        Table::Instance => 6,
    }
}
fn byte_table(byte: u8) -> Result<Table, LinkError> {
    Ok(match byte {
        0 => Table::String,
        1 => Table::Class,
        2 => Table::Proc,
        3 => Table::Variable,
        4 => Table::List,
        5 => Table::Resource,
        6 => Table::Instance,
        _ => return Err(invalid("invalid table")),
    })
}
struct Cursor<'a> {
    bytes: &'a [u8],
    at: usize,
}
impl Cursor<'_> {
    fn remaining(&self) -> usize {
        self.bytes.len() - self.at
    }
    fn take(&mut self, n: usize) -> Result<&[u8], LinkError> {
        let end = self
            .at
            .checked_add(n)
            .filter(|end| *end <= self.bytes.len())
            .ok_or_else(|| invalid("truncated section"))?;
        let value = &self.bytes[self.at..end];
        self.at = end;
        Ok(value)
    }
    fn byte(&mut self) -> Result<u8, LinkError> {
        Ok(self.take(1)?[0])
    }
    fn u32(&mut self) -> Result<u32, LinkError> {
        let b = self.take(4)?;
        Ok(u32::from_le_bytes([b[0], b[1], b[2], b[3]]))
    }
    fn count(&mut self) -> Result<usize, LinkError> {
        let n = self.u32()? as usize;
        if n > MAX_WORDS {
            Err(invalid("count exceeds limit"))
        } else {
            Ok(n)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{Instruction, VariableWord};
    fn instruction(opcode: u32, operands: Vec<Word>) -> Item {
        Item::Instruction(Instruction { opcode, operands })
    }
    #[test]
    fn current_debug_origins_match_symbolic_linker_with_forward_and_backward_jumps() {
        use crate::debug::{ResolvedStatementOrigin, StatementOrigin};
        let code = SymbolicProc {
            items: vec![
                Item::Label("start".into()),
                instruction(0xf, vec![Word::Branch("end".into())]),
                instruction(0x50, vec![Word::Immediate(7)]),
                instruction(0x51, vec![]),
                Item::Label("end".into()),
                instruction(0xf, vec![Word::Branch("start".into())]),
                instruction(0, vec![]),
            ],
        };
        let marks = vec![
            StatementOrigin {
                code_item: 1,
                start: 0,
                end: 4,
            },
            StatementOrigin {
                code_item: 5,
                start: 20,
                end: 24,
            },
        ];
        let simple = crate::SimpleProc {
            code: code.clone(),
            statement_origins: marks.clone(),
            ..Default::default()
        };
        let prepared =
            PreparedProc::decode(&PreparedProc::prepare(&code).unwrap().encode().unwrap()).unwrap();
        for moved_line in [1, 150] {
            let mut ledger = Ledger::default();
            ledger
                .bind(Symbol::new(Table::String, "moved.dm"), 0x12345)
                .unwrap();
            let debug = crate::debug::with_statement_debug(&simple, |offset| {
                Some(ResolvedStatementOrigin {
                    file: "moved.dm".into(),
                    line: moved_line + offset as u32,
                })
            })
            .unwrap();
            let expected = link_proc(&debug, &ledger).unwrap().words;
            assert_eq!(
                prepared
                    .materialize_with_debug(&ledger, &marks, |offset| Some((
                        0x12345,
                        moved_line + offset as u32
                    )))
                    .unwrap(),
                expected
            );
        }
    }
    #[test]
    fn prepared_sections_match_linker_under_table_reassignment() {
        let proc = SymbolicProc {
            items: vec![
                instruction(0x60, vec![Word::Value(ValueWord::String("message".into()))]),
                instruction(
                    byond_dmb::bytecode::opcode::SET_VAR,
                    vec![Word::Variable(VariableWord::Global("destination".into()))],
                ),
                instruction(0xf, vec![Word::Branch("done".into())]),
                instruction(
                    0x60,
                    vec![Word::Value(ValueWord::ClassPath {
                        path: "/datum/probe".into(),
                        tag: 32,
                    })],
                ),
                instruction(0x51, vec![]),
                Item::Label("done".into()),
                instruction(0, vec![]),
            ],
        };
        let prepared = PreparedProc::prepare(&proc).unwrap();
        let decoded = PreparedProc::decode(&prepared.encode().unwrap()).unwrap();
        assert_eq!(prepared, decoded);
        for base in [0, 0x12345, 0xff_fff0] {
            let mut ledger = Ledger::default();
            ledger
                .bind(Symbol::new(Table::String, "message"), base)
                .unwrap();
            ledger
                .bind(Symbol::new(Table::Variable, "destination"), base + 1)
                .unwrap();
            ledger
                .bind(Symbol::new(Table::Class, "/datum/probe"), base + 2)
                .unwrap();
            assert_eq!(
                decoded.materialize(&ledger).unwrap(),
                link_proc(&proc, &ledger).unwrap().words
            );
        }
        let mut missing = Ledger::default();
        missing
            .bind(Symbol::new(Table::String, "message"), 0x100_0000)
            .unwrap();
        missing
            .bind(Symbol::new(Table::Variable, "destination"), 0)
            .unwrap();
        missing
            .bind(Symbol::new(Table::Class, "/datum/probe"), 0)
            .unwrap();
        assert!(matches!(
            prepared.materialize(&missing),
            Err(LinkError::TooManyRecords(Table::String))
        ));
    }
    #[test]
    fn codec_rejects_truncation_and_invalid_relocation() {
        let proc = SymbolicProc {
            items: vec![
                instruction(0x60, vec![Word::Value(ValueWord::String("x".into()))]),
                instruction(0, vec![]),
            ],
        };
        let section = PreparedProc::prepare(&proc).unwrap();
        let bytes = section.encode().unwrap();
        for end in 0..bytes.len() {
            assert!(PreparedProc::decode(&bytes[..end]).is_err());
        }
        let mut invalid = section.clone();
        invalid.relocations[0].offset = 0;
        assert!(PreparedProc::decode(&invalid.encode().unwrap()).is_err());
        let mut trailing = bytes;
        trailing.push(0);
        assert!(PreparedProc::decode(&trailing).is_err());
    }
}
