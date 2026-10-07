//! Relocatable procedure words. Only the linker writes BYOND table indexes.

use crate::SymbolId;
use std::collections::{HashMap, HashSet};

#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub enum SymRef {
    String(SymbolId),
    Type(SymbolId),
    Proc {
        owner: SymbolId,
        name: SymbolId,
        occurrence: u32,
    },
    Var {
        owner: SymbolId,
        name: SymbolId,
    },
    /// Procedure namespace is preserved independently from verb namespace.
    Verb {
        owner: SymbolId,
        name: SymbolId,
        occurrence: u32,
    },
    /// Modified-type instance-table entry; this is not its underlying class.
    Instance(SymbolId),
    /// Shared/global/static slot supplied by the resolver, not a field name.
    VariableSlot(SymbolId),
    /// The builtin global.vars slot is not a declaration whose name is vars.
    BuiltinGlobalVars,
    /// Current occurrence supplies file spelling for this origin ordinal.
    SourceFile(u32),
    ConstantList(u128),
    Resource(u128),
    /// Relative to the procedure's first source line. The current occurrence
    /// supplies the base; cached code never stores an absolute source line.
    LineDelta(u32),
}

/// Expected ABI operand table class. Literal tag words are not relocation sites.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum RelocationKind {
    String,
    Type,
    Procedure,
    Variable,
    List,
    Resource,
    Instance,
    SourceLine,
}
impl SymRef {
    pub const fn kind(self) -> RelocationKind {
        match self {
            Self::String(_) | Self::SourceFile(_) => RelocationKind::String,
            Self::Type(_) => RelocationKind::Type,
            Self::Proc { .. } | Self::Verb { .. } => RelocationKind::Procedure,
            Self::Var { .. } | Self::VariableSlot(_) | Self::BuiltinGlobalVars => {
                RelocationKind::Variable
            }
            Self::ConstantList(_) => RelocationKind::List,
            Self::Resource(_) => RelocationKind::Resource,
            Self::Instance(_) => RelocationKind::Instance,
            Self::LineDelta(_) => RelocationKind::SourceLine,
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Relocation {
    pub offset: u32,
    pub reference: SymRef,
}

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct SymbolicCode {
    words: Vec<u32>,
    relocations: Vec<Relocation>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum RelocationError {
    WordCountOverflow,
    OutOfBounds(u32),
    DuplicateSite(u32),
    MissingSite(u32),
    MissingRelocation(u32),
    KindMismatch {
        offset: u32,
        expected: RelocationKind,
        actual: RelocationKind,
    },
    Duplicate(u32),
    NonzeroPlaceholder(u32),
    Unresolved(SymRef),
}

impl SymbolicCode {
    pub fn new(words: Vec<u32>, mut relocations: Vec<Relocation>) -> Result<Self, RelocationError> {
        u32::try_from(words.len()).map_err(|_| RelocationError::WordCountOverflow)?;
        let mut seen = HashSet::new();
        for relocation in &relocations {
            let word = words
                .get(relocation.offset as usize)
                .ok_or(RelocationError::OutOfBounds(relocation.offset))?;
            if !seen.insert(relocation.offset) {
                return Err(RelocationError::Duplicate(relocation.offset));
            }
            if *word != 0 {
                return Err(RelocationError::NonzeroPlaceholder(relocation.offset));
            }
        }
        relocations.sort_unstable_by_key(|relocation| relocation.offset);
        Ok(Self { words, relocations })
    }

    /// Require an exact relocation ledger from the typed operand encoder. This
    /// rejects omitted references, refs on immediates/opcode tags, duplicate ABI
    /// sites, and table-kind substitutions before any output index is assigned.
    /// `new` alone validates storage; it cannot infer an ABI from raw integers.
    pub fn validate_sites(&self, sites: &[(u32, RelocationKind)]) -> Result<(), RelocationError> {
        let mut expected = HashMap::new();
        for &(offset, kind) in sites {
            if self.words.get(offset as usize).is_none() {
                return Err(RelocationError::OutOfBounds(offset));
            }
            if expected.insert(offset, kind).is_some() {
                return Err(RelocationError::DuplicateSite(offset));
            }
        }
        for relocation in &self.relocations {
            let kind = expected
                .remove(&relocation.offset)
                .ok_or(RelocationError::MissingSite(relocation.offset))?;
            let actual = relocation.reference.kind();
            if kind != actual {
                return Err(RelocationError::KindMismatch {
                    offset: relocation.offset,
                    expected: kind,
                    actual,
                });
            }
        }
        if let Some(offset) = expected.keys().min() {
            return Err(RelocationError::MissingRelocation(*offset));
        }
        Ok(())
    }
    /// Stable content identity with explicit fields, never Debug, pointer values,
    /// arena IDs or worker enumeration. Relocations are already in offset order.
    pub fn fingerprint(&self) -> u128 {
        let mut bytes = Vec::new();
        bytes.extend_from_slice(b"dm-symbolic-code-v1\0");
        bytes.extend_from_slice(&(self.words.len() as u64).to_le_bytes());
        for word in &self.words {
            bytes.extend_from_slice(&word.to_le_bytes())
        }
        bytes.extend_from_slice(&(self.relocations.len() as u64).to_le_bytes());
        for relocation in &self.relocations {
            bytes.extend_from_slice(&relocation.offset.to_le_bytes());
            encode_reference(&mut bytes, relocation.reference);
        }
        xxhash_rust::xxh3::xxh3_128(&bytes)
    }

    pub fn words(&self) -> &[u32] {
        &self.words
    }

    pub fn relocations(&self) -> &[Relocation] {
        &self.relocations
    }

    /// Resolve into a private image, leaving shared symbolic code unchanged on
    /// both success and failure. Resolution order is canonical word-offset order.
    pub fn link(
        &self,
        mut resolve: impl FnMut(SymRef) -> Option<u32>,
    ) -> Result<Vec<u32>, RelocationError> {
        let mut linked = self.words.clone();
        for relocation in &self.relocations {
            linked[relocation.offset as usize] = resolve(relocation.reference)
                .ok_or(RelocationError::Unresolved(relocation.reference))?;
        }
        Ok(linked)
    }
}

fn encode_reference(bytes: &mut Vec<u8>, reference: SymRef) {
    match reference {
        SymRef::String(symbol) => {
            bytes.push(0);
            bytes.extend_from_slice(&symbol.bits().to_le_bytes())
        }
        SymRef::Type(symbol) => {
            bytes.push(1);
            bytes.extend_from_slice(&symbol.bits().to_le_bytes())
        }
        SymRef::Proc {
            owner,
            name,
            occurrence,
        }
        | SymRef::Verb {
            owner,
            name,
            occurrence,
        } => {
            bytes.push(if matches!(reference, SymRef::Proc { .. }) {
                2
            } else {
                3
            });
            bytes.extend_from_slice(&owner.bits().to_le_bytes());
            bytes.extend_from_slice(&name.bits().to_le_bytes());
            bytes.extend_from_slice(&occurrence.to_le_bytes())
        }
        SymRef::Var { owner, name } => {
            bytes.push(4);
            bytes.extend_from_slice(&owner.bits().to_le_bytes());
            bytes.extend_from_slice(&name.bits().to_le_bytes())
        }
        SymRef::VariableSlot(symbol) => {
            bytes.push(5);
            bytes.extend_from_slice(&symbol.bits().to_le_bytes())
        }
        SymRef::BuiltinGlobalVars => bytes.push(6),
        SymRef::Instance(symbol) => {
            bytes.push(7);
            bytes.extend_from_slice(&symbol.bits().to_le_bytes())
        }
        SymRef::SourceFile(origin) => {
            bytes.push(8);
            bytes.extend_from_slice(&origin.to_le_bytes())
        }
        SymRef::ConstantList(content) => {
            bytes.push(9);
            bytes.extend_from_slice(&content.to_le_bytes())
        }
        SymRef::Resource(content) => {
            bytes.push(10);
            bytes.extend_from_slice(&content.to_le_bytes())
        }
        SymRef::LineDelta(delta) => {
            bytes.push(11);
            bytes.extend_from_slice(&delta.to_le_bytes())
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn typed_operand_sites_require_exact_reference_kinds() {
        let code = SymbolicCode::new(
            vec![42, 0],
            vec![Relocation {
                offset: 1,
                reference: SymRef::BuiltinGlobalVars,
            }],
        )
        .unwrap();
        assert_eq!(
            code.validate_sites(&[(1, RelocationKind::Variable)]),
            Ok(())
        );
        assert_eq!(
            code.validate_sites(&[]),
            Err(RelocationError::MissingSite(1))
        );
        assert_eq!(
            code.validate_sites(&[(1, RelocationKind::String)]),
            Err(RelocationError::KindMismatch {
                offset: 1,
                expected: RelocationKind::String,
                actual: RelocationKind::Variable
            })
        );
        assert_eq!(
            code.validate_sites(&[(1, RelocationKind::Variable), (1, RelocationKind::Variable)]),
            Err(RelocationError::DuplicateSite(1))
        );
        assert_eq!(
            code.validate_sites(&[(2, RelocationKind::Variable)]),
            Err(RelocationError::OutOfBounds(2))
        );
        assert_eq!(
            SymbolicCode::new(vec![0], vec![])
                .unwrap()
                .validate_sites(&[(0, RelocationKind::String)]),
            Err(RelocationError::MissingRelocation(0))
        );
    }

    #[test]
    fn fingerprints_preserve_namespace_and_canonicalize_site_order() {
        let owner = SymbolId::of("/datum/a");
        let name = SymbolId::of("read");
        let proc = SymRef::Proc {
            owner,
            name,
            occurrence: 0,
        };
        let verb = SymRef::Verb {
            owner,
            name,
            occurrence: 0,
        };
        let one = |reference| {
            SymbolicCode::new(
                vec![0],
                vec![Relocation {
                    offset: 0,
                    reference,
                }],
            )
            .unwrap()
            .fingerprint()
        };
        assert_ne!(one(proc), one(verb));
        assert_ne!(one(SymRef::Type(owner)), one(SymRef::Instance(owner)));
        assert_ne!(
            one(SymRef::BuiltinGlobalVars),
            one(SymRef::VariableSlot(SymbolId::of("vars")))
        );
        let a = Relocation {
            offset: 0,
            reference: proc,
        };
        let b = Relocation {
            offset: 1,
            reference: SymRef::String(name),
        };
        assert_eq!(
            SymbolicCode::new(vec![0, 0], vec![a, b])
                .unwrap()
                .fingerprint(),
            SymbolicCode::new(vec![0, 0], vec![b, a])
                .unwrap()
                .fingerprint()
        );
    }

    #[test]
    fn linking_separate_table_assignments_never_mutates_shared_words() {
        let symbol = SymRef::String(SymbolId::of("text"));
        let code = SymbolicCode::new(
            vec![99, 0, 0],
            vec![
                Relocation {
                    offset: 2,
                    reference: SymRef::LineDelta(4),
                },
                Relocation {
                    offset: 1,
                    reference: symbol,
                },
            ],
        )
        .unwrap();
        assert_eq!(
            code.link(|reference| Some(match reference {
                SymRef::String(_) => 7,
                SymRef::LineDelta(line) => 20 + line,
                _ => unreachable!(),
            }))
            .unwrap(),
            vec![99, 7, 24]
        );
        assert_eq!(
            code.link(|_| None),
            Err(RelocationError::Unresolved(symbol))
        );
        assert_eq!(code.link(|_| Some(3)).unwrap(), vec![99, 3, 3]);
        assert_eq!(code.words(), [99, 0, 0]);
    }

    #[test]
    fn malformed_relocation_tables_are_rejected_before_linking() {
        let relocation = Relocation {
            offset: 0,
            reference: SymRef::LineDelta(0),
        };
        assert_eq!(
            SymbolicCode::new(vec![], vec![relocation]),
            Err(RelocationError::OutOfBounds(0))
        );
        assert_eq!(
            SymbolicCode::new(vec![0], vec![relocation, relocation]),
            Err(RelocationError::Duplicate(0))
        );
        assert_eq!(
            SymbolicCode::new(vec![1], vec![relocation]),
            Err(RelocationError::NonzeroPlaceholder(0))
        );
    }
}
