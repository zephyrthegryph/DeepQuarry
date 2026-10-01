//! BYOND instruction boundary decoder. Operands remain as exact wire words.
use std::collections::HashMap;
use std::sync::OnceLock;

/// Named opcodes generated from the authoritative instruction registry.
pub mod opcode {
    include!(concat!(env!("OUT_DIR"), "/opcodes_generated.rs"));
}

/// Opcodes whose first fixed word is an absolute branch destination.
pub fn is_branch_opcode(opcode: u32) -> bool {
    matches!(
        opcode,
        0xf | 0x10
            | 0x11
            | 0x25
            | 0xb2
            | 0xb3
            | 0xf8
            | 0xf9
            | 0xfa
            | 0xfd
            | 0xff
            | 0x12c
            | 0x12e
            | 0x12f
            | 0x13d
            | 0x13e
    )
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct Instruction {
    pub offset: usize,
    pub opcode: u32,
    pub name: &'static str,
    /// Raw operand words in source order, including nested operand encodings.
    pub operands: Vec<u32>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum Operand {
    Word(u32),
    Value(crate::operands::Value),
    Variable(crate::operands::Variable),
    Switch {
        cases: Vec<(crate::operands::Value, u32)>,
        default: u32,
    },
    PickSwitch {
        cases: Vec<(u32, u32)>,
        default: u32,
    },
    RangeSwitch {
        ranges: Vec<(crate::operands::Value, crate::operands::Value, u32)>,
        exact: Vec<(crate::operands::Value, u32)>,
        default: u32,
    },
    PickProb(Vec<u32>),
}

impl Instruction {
    /// Absolute word offsets selected by this instruction's control flow.
    pub fn branch_targets(&self) -> Result<Vec<u32>, DecodeError> {
        Ok(self
            .branch_target_word_offsets()?
            .into_iter()
            .map(|at| self.operands[at - self.offset - 1])
            .collect())
    }

    /// Absolute positions of destination words in the encoded instruction.
    /// Counts, switch keys and probability thresholds are never destinations.
    /// This preserves their identity when relocating already encoded branches.
    pub fn branch_target_word_offsets(&self) -> Result<Vec<usize>, DecodeError> {
        let operands = self.typed_operands()?;
        let mut targets = Vec::new();
        if is_branch_opcode(self.opcode) {
            if let Some(Operand::Word(_)) = operands.first() {
                targets.push(self.offset + 1);
            }
        }
        let mut at = self.offset + 1;
        for operand in operands {
            match operand {
                Operand::Word(_) => at += 1,
                Operand::Value(value) => at += value.encode().len(),
                Operand::Variable(variable) => at += variable.encode().len(),
                Operand::Switch { cases, .. } => {
                    at += 1;
                    for (value, _) in cases {
                        at += value.encode().len();
                        targets.push(at);
                        at += 1;
                    }
                    targets.push(at);
                    at += 1;
                }
                Operand::PickSwitch { cases, .. } => {
                    at += 1;
                    for _ in cases {
                        at += 1; // cumulative probability threshold
                        targets.push(at);
                        at += 1;
                    }
                    targets.push(at);
                    at += 1;
                }
                Operand::RangeSwitch { ranges, exact, .. } => {
                    at += 1;
                    for (lower, upper, _) in ranges {
                        at += lower.encode().len() + upper.encode().len();
                        targets.push(at);
                        at += 1;
                    }
                    at += 1;
                    for (value, _) in exact {
                        at += value.encode().len();
                        targets.push(at);
                        at += 1;
                    }
                    targets.push(at);
                    at += 1;
                }
                Operand::PickProb(values) => {
                    at += 1;
                    targets.extend(at..at + values.len());
                    at += values.len();
                }
            }
        }
        Ok(targets)
    }

    pub fn typed_operands(&self) -> Result<Vec<Operand>, DecodeError> {
        let descriptor = descriptors().get(&self.opcode).ok_or_else(|| DecodeError {
            offset: 0,
            reason: format!("unknown opcode {:#x}", self.opcode),
        })?;
        let mut reader = Decoder {
            words: &self.operands,
            at: 0,
        };
        let mut operands = Vec::new();
        for kind in descriptor.operands.chars() {
            operands.push(reader.operand(kind)?);
        }
        if reader.at != self.operands.len() {
            return Err(DecodeError {
                offset: reader.at,
                reason: "trailing operand words".into(),
            });
        }
        Ok(operands)
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct DecodeError {
    pub offset: usize,
    pub reason: String,
}

#[derive(Clone, Copy)]
struct Descriptor {
    name: &'static str,
    operands: &'static str,
}

fn descriptors() -> &'static HashMap<u32, Descriptor> {
    static TABLE: OnceLock<HashMap<u32, Descriptor>> = OnceLock::new();
    TABLE.get_or_init(|| {
        let mut table = HashMap::new();
        for line in include_str!("opcodes.txt").lines() {
            if line.starts_with('#') || line.is_empty() {
                continue;
            }
            let mut fields = line.split_ascii_whitespace();
            let opcode = u32::from_str_radix(fields.next().unwrap(), 16).unwrap();
            let name = fields.next().unwrap();
            let operands = fields.next().unwrap();
            table.insert(
                opcode,
                Descriptor {
                    name,
                    operands: if operands == "-" { "" } else { operands },
                },
            );
        }
        table
    })
}

struct Decoder<'a> {
    words: &'a [u32],
    at: usize,
}

impl Decoder<'_> {
    fn word(&mut self) -> Result<u32, DecodeError> {
        let value = self
            .words
            .get(self.at)
            .copied()
            .ok_or_else(|| DecodeError {
                offset: self.at,
                reason: "truncated operand".into(),
            })?;
        self.at += 1;
        Ok(value)
    }

    fn value(&mut self) -> Result<crate::operands::Value, DecodeError> {
        let (value, consumed) =
            crate::operands::Value::decode(&self.words[self.at..]).map_err(|mut error| {
                error.offset += self.at;
                error
            })?;
        if value.encode() != self.words[self.at..self.at + consumed] {
            return Err(DecodeError {
                offset: self.at,
                reason: "value re-encoding changed words".into(),
            });
        }
        self.at += consumed;
        Ok(value)
    }

    fn variable(&mut self) -> Result<crate::operands::Variable, DecodeError> {
        let (variable, consumed) = crate::operands::Variable::decode(&self.words[self.at..])
            .map_err(|mut error| {
                error.offset += self.at;
                error
            })?;
        if variable.encode() != self.words[self.at..self.at + consumed] {
            return Err(DecodeError {
                offset: self.at,
                reason: "variable re-encoding changed words".into(),
            });
        }
        self.at += consumed;
        Ok(variable)
    }

    fn operand(&mut self, kind: char) -> Result<Operand, DecodeError> {
        Ok(match kind {
            'u' => Operand::Word(self.word()?),
            'v' => Operand::Variable(self.variable()?),
            'V' => Operand::Value(self.value()?),
            'S' => {
                let count = self.word()?;
                let mut cases = Vec::new();
                for _ in 0..count {
                    cases.push((self.value()?, self.word()?));
                }
                Operand::Switch {
                    cases,
                    default: self.word()?,
                }
            }
            'P' => {
                let count = self.word()?;
                let mut cases = Vec::new();
                for _ in 0..count {
                    cases.push((self.word()?, self.word()?));
                }
                Operand::PickSwitch {
                    cases,
                    default: self.word()?,
                }
            }
            'R' => {
                let count = self.word()?;
                let mut ranges = Vec::new();
                for _ in 0..count {
                    ranges.push((self.value()?, self.value()?, self.word()?));
                }
                let count = self.word()?;
                let mut exact = Vec::new();
                for _ in 0..count {
                    exact.push((self.value()?, self.word()?));
                }
                Operand::RangeSwitch {
                    ranges,
                    exact,
                    default: self.word()?,
                }
            }
            'Q' => {
                let count = self.word()?;
                let mut words = Vec::new();
                for _ in 0..count {
                    words.push(self.word()?);
                }
                Operand::PickProb(words)
            }
            _ => unreachable!("opcode table has invalid operand kind"),
        })
    }
}

pub fn decode(words: &[u32]) -> Result<Vec<Instruction>, DecodeError> {
    let mut reader = Decoder { words, at: 0 };
    let mut instructions = Vec::new();
    while reader.at < words.len() {
        let offset = reader.at;
        let opcode = reader.word()?;
        let descriptor = descriptors().get(&opcode).ok_or_else(|| DecodeError {
            offset,
            reason: format!("unknown opcode {opcode:#x}"),
        })?;
        for kind in descriptor.operands.chars() {
            reader.operand(kind)?;
        }
        instructions.push(Instruction {
            offset,
            opcode,
            name: descriptor.name,
            operands: words[offset + 1..reader.at].to_vec(),
        });
    }
    Ok(instructions)
}

pub fn encode(instructions: &[Instruction]) -> Vec<u32> {
    let mut words = Vec::new();
    for instruction in instructions {
        words.push(instruction.opcode);
        words.extend_from_slice(&instruction.operands);
    }
    words
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn instruction_round_trip() {
        let words = [0x50, 42, 0x33, 0xffda, 2, 0x17c, 4, 0];
        let decoded = decode(&words).unwrap();
        assert_eq!(encode(&decoded), words);
        assert_eq!(decoded[1].operands, [0xffda, 2]);
        assert_eq!(
            decoded[1].typed_operands().unwrap(),
            vec![Operand::Variable(crate::operands::Variable::Local(2))]
        );
        assert_eq!(decoded[2].typed_operands().unwrap(), vec![Operand::Word(4)]);
    }

    #[test]
    fn unknown_opcode_is_an_error() {
        assert_eq!(decode(&[0xffff_ffff]).unwrap_err().offset, 0);
    }
    #[test]
    fn destination_word_positions_exclude_matching_keys_and_thresholds() {
        for (opcode, operands, positions) in [
            (0x78, vec![2, 6, 5, 5, 42, 0, 5, 5, 5], vec![104, 108, 109]),
            (0x79, vec![2, 5, 5, 5, 5, 5], vec![103, 105, 106]),
            (
                0x7a,
                vec![1, 6, 5, 42, 0, 5, 5, 1, 6, 5, 5, 5],
                vec![107, 111, 112],
            ),
            (0xb1, vec![2, 5, 5], vec![102, 103]),
            (0xfd, vec![5, 0xffd9, 0], vec![101]),
            (0x50, vec![5], vec![]),
        ] {
            let instruction = Instruction {
                offset: 100,
                opcode,
                name: "test",
                operands,
            };
            assert_eq!(instruction.branch_target_word_offsets().unwrap(), positions);
            assert_eq!(
                instruction.branch_targets().unwrap(),
                vec![5; positions.len()]
            );
        }
    }
    #[test]
    fn branch_targets_include_range_and_probability_tables_only() {
        let words = [
            0xfd, 12, 0xffd9, 0, 0x25, 12, 0xb1, 2, 12, 13, 0x50, 12, 0x12, 0,
        ];
        let instructions = decode(&words).unwrap();
        assert_eq!(instructions[0].branch_targets().unwrap(), [12]);
        assert_eq!(instructions[1].branch_targets().unwrap(), [12]);
        assert_eq!(instructions[2].branch_targets().unwrap(), [12, 13]);
        assert!(instructions[3].branch_targets().unwrap().is_empty());
    }
    #[test]
    fn json_encode_flags_keeps_argument_count_inside_instruction() {
        // Paired native json_encode(data, flags). The count word 2 must not
        // be mistaken for a second opcode (Format).
        let words = [0x33, 0xffd9, 0, 0x33, 0xffd9, 1, 0x167, 2, 0x12, 0];
        let decoded = decode(&words).unwrap();
        assert_eq!(decoded.len(), 5);
        assert_eq!(decoded[2].name, "JsonEncodeFlags");
        assert_eq!(decoded[2].operands, [2]);
        assert_eq!(decoded[2].typed_operands().unwrap(), vec![Operand::Word(2)]);
        assert_eq!(decoded[3].name, "Ret");
        assert_eq!(encode(&decoded), words);
    }

    #[test]
    fn v516_spatial_and_associative_builtins_have_verified_shapes() {
        let words = [
            0x180, 2, 0x17f, 3, 0x181, 0x186, 0x187, 0x188, 0x189, 0x18a, 0x18b, 0x18c,
        ];
        let decoded = decode(&words).unwrap();
        assert_eq!(encode(&decoded), words);
        assert_eq!(decoded[0].typed_operands().unwrap(), vec![Operand::Word(2)]);
        assert_eq!(decoded[1].typed_operands().unwrap(), vec![Operand::Word(3)]);
        assert!(decoded[2..].iter().all(|item| item.operands.is_empty()));
    }

    #[test]
    fn named_opcodes_match_runtime_descriptor_table() {
        use opcode::*;
        for (id, name) in [
            (END, "End"),
            (TEST, "Test"),
            (NOT, "Not"),
            (JMP, "Jmp"),
            (JNZ, "Jnz"),
            (JZ, "Jz"),
            (RET, "Ret"),
            (CALL, "Call"),
            (GET_VAR, "GetVar"),
            (SET_VAR, "SetVar"),
            (SET_VAR_EXPR, "SetVarExpr"),
            (TEQ, "Teq"),
            (TNE, "Tne"),
            (TL, "Tl"),
            (TG, "Tg"),
            (TLE, "Tle"),
            (TGE, "Tge"),
            (UNARY_NEG, "UnaryNeg"),
            (ADD, "Add"),
            (SUB, "Sub"),
            (MUL, "Mul"),
            (DIV, "Div"),
            (MOD, "Mod"),
            (PUSH_INT, "PushInt"),
            (POP, "Pop"),
            (PUSH_VAL, "PushVal"),
            (JMP_LOOP, "JmpLoop"),
        ] {
            assert_eq!(descriptors().get(&id).unwrap().name, name);
        }
    }
}
