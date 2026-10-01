//! Typed forms of the two compound bytecode operands.
//!
//! The wire representation remains available so callers can preserve unusual
//! tag bits and construct instructions without losing compiler details.
use crate::bytecode::DecodeError;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct Value {
    pub tag_word: u32,
    pub data_word: u32,
    pub extra_word: Option<u32>,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum ValueKind {
    Null,
    String,
    MobPath,
    MovablePath,
    AtomPath,
    AreaPath,
    Resource,
    DatumPath,
    SavefilePath,
    ProcPath,
    FilePath,
    ListPath,
    InstanceTypePath,
    Number,
    ClientPath,
    /// Placeholder for a non-constant value constructed by the class initializer.
    HiddenInitializer,
    ImagePath,
    GlobalVars,
    /// Class-table paths for BYOND 516 builtin alist, vector and callee types.
    BuiltinPath,
    Other(u8),
}

impl Value {
    pub fn tag(&self) -> u8 {
        self.tag_word as u8
    }

    /// The 24-bit payload ID is split between the tag's upper byte and data
    /// word. Its target depends on the tag and the containing record.
    pub fn id(&self) -> u32 {
        ((self.tag_word & 0xff00) << 8) | (self.data_word & 0xffff)
    }

    pub fn number_bits(&self) -> Option<u32> {
        (self.tag() == 0x2a)
            .then(|| ((self.data_word & 0xffff) << 16) | self.extra_word.unwrap_or(0))
    }

    pub fn kind(&self) -> ValueKind {
        ValueKind::from_tag(self.tag())
    }
}

impl ValueKind {
    pub fn from_tag(tag: u8) -> Self {
        match tag {
            0 => ValueKind::Null,
            6 => ValueKind::String,
            8 => ValueKind::MobPath,
            9 => ValueKind::MovablePath,
            10 => ValueKind::AtomPath,
            11 => ValueKind::AreaPath,
            12 => ValueKind::Resource,
            32 => ValueKind::DatumPath,
            36 => ValueKind::SavefilePath,
            38 => ValueKind::ProcPath,
            39 => ValueKind::FilePath,
            40 => ValueKind::ListPath,
            41 => ValueKind::InstanceTypePath,
            42 => ValueKind::Number,
            59 => ValueKind::ClientPath,
            62 => ValueKind::HiddenInitializer,
            63 => ValueKind::ImagePath,
            82 => ValueKind::GlobalVars,
            89 => ValueKind::BuiltinPath,
            other => ValueKind::Other(other),
        }
    }
}

impl Value {
    pub fn decode(words: &[u32]) -> Result<(Self, usize), DecodeError> {
        if words.len() < 2 {
            return Err(DecodeError {
                offset: words.len(),
                reason: "truncated value".into(),
            });
        }
        let extra_word = if words[0] & 0xff == 0x2a {
            Some(*words.get(2).ok_or_else(|| DecodeError {
                offset: 2,
                reason: "truncated number".into(),
            })?)
        } else {
            None
        };
        Ok((
            Self {
                tag_word: words[0],
                data_word: words[1],
                extra_word,
            },
            if extra_word.is_some() { 3 } else { 2 },
        ))
    }

    pub fn encode(&self) -> Vec<u32> {
        let mut words = vec![self.tag_word, self.data_word];
        if let Some(extra) = self.extra_word {
            words.push(extra);
        }
        words
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum Variable {
    Field(u32),
    Usr,
    Src,
    Args,
    Dot,
    Cache,
    CacheKey,
    CacheIndex,
    World,
    Caller,
    Callee,
    Null,
    Arg(u32),
    Local(u32),
    Global(u32),
    SetCache(Box<Variable>, Box<Variable>),
    Initial(Box<Variable>),
    IsSaved(Box<Variable>),
    DynamicProc(u32),
    DynamicVerb(u32),
    StaticProc(u32),
    StaticVerb(u32),
}

impl Variable {
    pub fn decode(words: &[u32]) -> Result<(Self, usize), DecodeError> {
        fn parse(words: &[u32], at: &mut usize, depth: usize) -> Result<Variable, DecodeError> {
            if depth > 32 {
                return Err(DecodeError {
                    offset: *at,
                    reason: "variable nesting exceeds 32".into(),
                });
            }
            let word = *words.get(*at).ok_or_else(|| DecodeError {
                offset: *at,
                reason: "truncated variable".into(),
            })?;
            *at += 1;
            let mut next = || {
                let value = *words.get(*at).ok_or_else(|| DecodeError {
                    offset: *at,
                    reason: "truncated variable ID".into(),
                })?;
                *at += 1;
                Ok(value)
            };
            Ok(match word {
                0xffcd => Variable::Usr,
                0xffce => Variable::Src,
                0xffcf => Variable::Args,
                0xffd0 => Variable::Dot,
                0xffd8 => Variable::Cache,
                0xffe3 => Variable::CacheKey,
                0xffe4 => Variable::CacheIndex,
                0xffe5 => Variable::World,
                0xffe6 => Variable::Null,
                0xfff0 => Variable::Caller,
                0xfff1 => Variable::Callee,
                0xffd9 => Variable::Arg(next()?),
                0xffda => Variable::Local(next()?),
                0xffdb => Variable::Global(next()?),
                0xffdd => Variable::DynamicProc(next()?),
                0xffde => Variable::DynamicVerb(next()?),
                0xffdf => Variable::StaticProc(next()?),
                0xffe0 => Variable::StaticVerb(next()?),
                0xffdc => {
                    let lhs = parse(words, at, depth + 1)?;
                    let rhs = parse(words, at, depth + 1)?;
                    Variable::SetCache(Box::new(lhs), Box::new(rhs))
                }
                0xffe7 => Variable::Initial(Box::new(parse(words, at, depth + 1)?)),
                0xffe8 => Variable::IsSaved(Box::new(parse(words, at, depth + 1)?)),
                n if (0xffcd..=0xfff1).contains(&n) => {
                    return Err(DecodeError {
                        offset: *at - 1,
                        reason: format!("unknown variable modifier {word:#x}"),
                    })
                }
                _ => Variable::Field(word),
            })
        }
        let mut at = 0;
        let variable = parse(words, &mut at, 0)?;
        Ok((variable, at))
    }

    pub fn encode(&self) -> Vec<u32> {
        match self {
            Self::Field(id) => vec![*id],
            Self::Usr => vec![0xffcd],
            Self::Src => vec![0xffce],
            Self::Args => vec![0xffcf],
            Self::Dot => vec![0xffd0],
            Self::Cache => vec![0xffd8],
            Self::CacheKey => vec![0xffe3],
            Self::CacheIndex => vec![0xffe4],
            Self::World => vec![0xffe5],
            Self::Caller => vec![0xfff0],
            Self::Callee => vec![0xfff1],
            Self::Null => vec![0xffe6],
            Self::Arg(id) => vec![0xffd9, *id],
            Self::Local(id) => vec![0xffda, *id],
            Self::Global(id) => vec![0xffdb, *id],
            Self::DynamicProc(id) => vec![0xffdd, *id],
            Self::DynamicVerb(id) => vec![0xffde, *id],
            Self::StaticProc(id) => vec![0xffdf, *id],
            Self::StaticVerb(id) => vec![0xffe0, *id],
            Self::SetCache(lhs, rhs) => {
                let mut words = vec![0xffdc];
                words.extend(lhs.encode());
                words.extend(rhs.encode());
                words
            }
            Self::Initial(value) => {
                let mut words = vec![0xffe7];
                words.extend(value.encode());
                words
            }
            Self::IsSaved(value) => {
                let mut words = vec![0xffe8];
                words.extend(value.encode());
                words
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn reserved_intrinsic_slots_are_not_fields() {
        // Native getter dispatch: 10131055 subtracts FFCD, bounds at 0x24.
        // Native setter dispatch: 10130a12 bounds at 0x22. FFED..FFEF are
        // therefore intrinsic dispatch slots, even without a named decoder.
        for word in [0xffed, 0xffee, 0xffef] {
            assert!(Variable::decode(&[word]).is_err(), "reserved {word:#x}");
        }
        assert_eq!(
            Variable::decode(&[0xfff2]).unwrap(),
            (Variable::Field(0xfff2), 1)
        );
    }
    #[test]
    fn call_frame_references_are_intrinsics_not_string_fields() {
        for (word, reference) in [(0xfff0, Variable::Caller), (0xfff1, Variable::Callee)] {
            assert_eq!(Variable::decode(&[word]).unwrap(), (reference.clone(), 1));
            assert_eq!(reference.encode(), [word]);
            let nested = Variable::SetCache(Box::new(reference), Box::new(Variable::Field(7)));
            assert_eq!(Variable::decode(&nested.encode()).unwrap().0, nested);
        }
    }
    #[test]
    fn variable_round_trip() {
        // Native readers dispatch only FFCD..FFF1 as intrinsic candidates.
        // FFF8 remains a valid string ID, not the interpreter's Eval scratch.
        assert_eq!(
            Variable::decode(&[0xfff8]).unwrap(),
            (Variable::Field(0xfff8), 1)
        );
        let words = [0xffdc, 0xffce, 0xffd9, 3];
        let (variable, length) = Variable::decode(&words).unwrap();
        assert_eq!(length, words.len());
        assert_eq!(variable.encode(), words);
    }
    #[test]
    fn value_round_trip() {
        let words = [0x102a, 0x3f80, 0];
        let (value, length) = Value::decode(&words).unwrap();
        assert_eq!(length, 3);
        assert_eq!(value.encode(), words);
        assert_eq!(value.kind(), ValueKind::Number);
    }
}
