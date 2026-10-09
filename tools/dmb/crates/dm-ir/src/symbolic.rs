//! Relocatable procedure words. Only the linker writes BYOND table indexes.

use crate::SymbolId;
use std::collections::{HashMap, HashSet};

#[derive(
    Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Hash, serde::Serialize, serde::Deserialize,
)]
pub enum SymRef {
    ProcedureStatic(crate::ProcedureStaticIdentity),
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
    /// Non-callable argument-source companion, owned structurally by its proc.
    ArgumentSource {
        owner: SymbolId,
        name: SymbolId,
        verb: bool,
        occurrence: u32,
        argument: u32,
    },
    /// Modified-type instance-table entry; this is not its underlying class.
    Instance(SymbolId),
    /// Shared/global/static slot supplied by the resolver, not a field name.
    VariableSlot(SymbolId),
    /// The builtin global.vars slot is not a declaration whose name is vars.
    BuiltinGlobalVars,
    /// Current occurrence supplies file spelling for this origin ordinal.
    SourceFile(u32),
    /// Absolute line supplied by the current occurrence, addressed by origin ordinal.
    SourceLine(u32),
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
            Self::Proc { .. } | Self::Verb { .. } | Self::ArgumentSource { .. } => {
                RelocationKind::Procedure
            }
            Self::Var { .. }
            | Self::VariableSlot(_)
            | Self::BuiltinGlobalVars
            | Self::ProcedureStatic(_) => RelocationKind::Variable,
            Self::ConstantList(_) => RelocationKind::List,
            Self::Resource(_) => RelocationKind::Resource,
            Self::Instance(_) => RelocationKind::Instance,
            Self::LineDelta(_) | Self::SourceLine(_) => RelocationKind::SourceLine,
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum RelocationEncoding {
    Direct,
    PackedValue24 { tag: u8 },
}
impl RelocationEncoding {
    fn width(self) -> u32 {
        match self {
            Self::Direct => 1,
            Self::PackedValue24 { .. } => 2,
        }
    }
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Relocation {
    pub offset: u32,
    pub reference: SymRef,
    pub encoding: RelocationEncoding,
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
    EncodingMismatch(u32),
    PackedValueOverflow {
        offset: u32,
        value: u32,
    },
}

impl SymbolicCode {
    pub fn new(words: Vec<u32>, mut relocations: Vec<Relocation>) -> Result<Self, RelocationError> {
        u32::try_from(words.len()).map_err(|_| RelocationError::WordCountOverflow)?;
        // A checked interval proof eliminates covered-word storage only when
        // encounter order is already canonical and every interval is disjoint.
        // Failed proofs use the original validation order, including overflow.
        let canonical = relocations
            .iter()
            .try_fold(0, |end, relocation| {
                if relocation.offset < end {
                    None
                } else {
                    relocation.offset.checked_add(relocation.encoding.width())
                }
            })
            .is_some();
        let mut seen = (!canonical).then(HashSet::new);
        for relocation in &relocations {
            for delta in 0..relocation.encoding.width() {
                let at = relocation
                    .offset
                    .checked_add(delta)
                    .ok_or(RelocationError::OutOfBounds(relocation.offset))?;
                let word = words
                    .get(at as usize)
                    .ok_or(RelocationError::OutOfBounds(at))?;
                if seen.as_mut().is_some_and(|seen| !seen.insert(at)) {
                    return Err(RelocationError::Duplicate(at));
                }
                if *word != 0 {
                    return Err(RelocationError::NonzeroPlaceholder(at));
                }
            }
        }
        if !canonical {
            relocations.sort_unstable_by_key(|relocation| relocation.offset);
        }
        Ok(Self { words, relocations })
    }

    /// Require an exact relocation ledger from the typed operand encoder. This
    /// rejects omitted references, refs on immediates/opcode tags, duplicate ABI
    /// sites, and table-kind substitutions before any output index is assigned.
    /// `new` alone validates storage; it cannot infer an ABI from raw integers.
    pub fn validate_sites(&self, sites: &[(u32, RelocationKind)]) -> Result<(), RelocationError> {
        self.validate_encoded_sites_iter(
            sites
                .iter()
                .map(|&(offset, kind)| (offset, kind, RelocationEncoding::Direct)),
        )
    }
    pub fn validate_encoded_sites(
        &self,
        sites: &[(u32, RelocationKind, RelocationEncoding)],
    ) -> Result<(), RelocationError> {
        self.validate_encoded_sites_iter(sites.iter().copied())
    }

    /// Validate a borrowed ledger in its encounter order without materializing
    /// a temporary tuple vector. The slice API uses this same validation path.
    pub fn validate_encoded_sites_iter(
        &self,
        sites: impl IntoIterator<Item = (u32, RelocationKind, RelocationEncoding)>,
    ) -> Result<(), RelocationError> {
        let mut expected = HashMap::new();
        let mut covered = HashSet::new();
        for (offset, kind, encoding) in sites {
            for delta in 0..encoding.width() {
                let at = offset
                    .checked_add(delta)
                    .ok_or(RelocationError::OutOfBounds(offset))?;
                if self.words.get(at as usize).is_none() {
                    return Err(RelocationError::OutOfBounds(at));
                }
                if !covered.insert(at) {
                    return Err(RelocationError::DuplicateSite(at));
                }
            }
            if expected.insert(offset, (kind, encoding)).is_some() {
                return Err(RelocationError::DuplicateSite(offset));
            }
        }
        for relocation in &self.relocations {
            let (kind, encoding) = expected
                .remove(&relocation.offset)
                .ok_or(RelocationError::MissingSite(relocation.offset))?;
            let actual = relocation.reference.kind();
            if encoding != relocation.encoding {
                return Err(RelocationError::EncodingMismatch(relocation.offset));
            }
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
    pub fn canonical_bytes(&self) -> Vec<u8> {
        let mut bytes = Vec::new();
        self.write_canonical(|chunk| bytes.extend_from_slice(chunk));
        bytes
    }
    /// Exact encoded length through the same codec, without allocating bytes.
    pub fn canonical_len(&self) -> usize {
        let mut length = 0usize;
        self.write_canonical(|chunk| {
            length = length
                .checked_add(chunk.len())
                .expect("canonical code length exceeds usize");
        });
        length
    }
    fn write_canonical(&self, mut bytes: impl FnMut(&[u8])) {
        bytes(b"dm-symbolic-code-v2\0");
        bytes(&(self.words.len() as u64).to_le_bytes());
        for word in &self.words {
            bytes(&word.to_le_bytes())
        }
        bytes(&(self.relocations.len() as u64).to_le_bytes());
        for relocation in &self.relocations {
            bytes(&relocation.offset.to_le_bytes());
            match relocation.encoding {
                RelocationEncoding::Direct => bytes(&[0]),
                RelocationEncoding::PackedValue24 { tag } => {
                    bytes(&[1]);
                    bytes(&[tag]);
                }
            }
            encode_reference(&mut bytes, relocation.reference);
        }
    }

    pub fn fingerprint(&self) -> u128 {
        xxhash_rust::xxh3::xxh3_128(&self.canonical_bytes())
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
            let value = resolve(relocation.reference)
                .ok_or(RelocationError::Unresolved(relocation.reference))?;
            let at = relocation.offset as usize;
            match relocation.encoding {
                RelocationEncoding::Direct => linked[at] = value,
                RelocationEncoding::PackedValue24 { tag } => {
                    if value > 0x00ff_ffff {
                        return Err(RelocationError::PackedValueOverflow {
                            offset: relocation.offset,
                            value,
                        });
                    }
                    linked[at] = u32::from(tag) | ((value >> 16) << 8);
                    linked[at + 1] = value & 0xffff;
                }
            }
        }
        Ok(linked)
    }
}

fn encode_reference(bytes: &mut impl FnMut(&[u8]), reference: SymRef) {
    match reference {
        SymRef::String(symbol) => {
            bytes(&[0]);
            bytes(&symbol.bits().to_le_bytes())
        }
        SymRef::Type(symbol) => {
            bytes(&[1]);
            bytes(&symbol.bits().to_le_bytes())
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
            bytes(&[if matches!(reference, SymRef::Proc { .. }) {
                2
            } else {
                3
            }]);
            bytes(&owner.bits().to_le_bytes());
            bytes(&name.bits().to_le_bytes());
            bytes(&occurrence.to_le_bytes())
        }
        SymRef::ArgumentSource {
            owner,
            name,
            verb,
            occurrence,
            argument,
        } => {
            bytes(&[13]);
            bytes(&owner.bits().to_le_bytes());
            bytes(&name.bits().to_le_bytes());
            bytes(&[u8::from(verb)]);
            bytes(&occurrence.to_le_bytes());
            bytes(&argument.to_le_bytes());
        }
        SymRef::Var { owner, name } => {
            bytes(&[4]);
            bytes(&owner.bits().to_le_bytes());
            bytes(&name.bits().to_le_bytes())
        }
        SymRef::ProcedureStatic(identity) => {
            bytes(&[14]);
            identity.write_canonical(bytes);
        }
        SymRef::VariableSlot(symbol) => {
            bytes(&[5]);
            bytes(&symbol.bits().to_le_bytes())
        }
        SymRef::BuiltinGlobalVars => bytes(&[6]),
        SymRef::Instance(symbol) => {
            bytes(&[7]);
            bytes(&symbol.bits().to_le_bytes())
        }
        SymRef::SourceFile(origin) => {
            bytes(&[8]);
            bytes(&origin.to_le_bytes())
        }
        SymRef::ConstantList(content) => {
            bytes(&[9]);
            bytes(&content.to_le_bytes())
        }
        SymRef::Resource(content) => {
            bytes(&[10]);
            bytes(&content.to_le_bytes())
        }
        SymRef::SourceLine(origin) => {
            bytes(&[12]);
            bytes(&origin.to_le_bytes())
        }
        SymRef::LineDelta(delta) => {
            bytes(&[11]);
            bytes(&delta.to_le_bytes())
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn canonical_count_uses_exact_codec_for_every_reference_and_encoding() {
        let owner = SymbolId::of("/datum/sample");
        let name = SymbolId::of("sample");
        let procedure = crate::ProcedureIdentity {
            owner,
            name,
            verb: true,
            occurrence: 17,
        };
        let refs = [
            SymRef::String(name),
            SymRef::Type(owner),
            SymRef::Proc {
                owner,
                name,
                occurrence: 7,
            },
            SymRef::Verb {
                owner,
                name,
                occurrence: 8,
            },
            SymRef::Var { owner, name },
            SymRef::ArgumentSource {
                owner,
                name,
                verb: true,
                occurrence: 9,
                argument: 3,
            },
            SymRef::ProcedureStatic(crate::ProcedureStaticIdentity { procedure, name }),
            SymRef::VariableSlot(name),
            SymRef::BuiltinGlobalVars,
            SymRef::Instance(owner),
            SymRef::SourceFile(15),
            SymRef::SourceLine(42),
            SymRef::LineDelta(13),
            SymRef::ConstantList(71),
            SymRef::Resource(93),
        ];
        for reference in refs {
            for encoding in [
                RelocationEncoding::Direct,
                RelocationEncoding::PackedValue24 { tag: 6 },
            ] {
                let code = SymbolicCode::new(
                    vec![0; encoding.width() as usize],
                    vec![Relocation {
                        offset: 0,
                        reference,
                        encoding,
                    }],
                )
                .unwrap();
                let bytes = code.canonical_bytes();
                assert_eq!(code.canonical_len(), bytes.len());
                assert_eq!(code.fingerprint(), xxhash_rust::xxh3::xxh3_128(&bytes));
            }
        }
        let code = SymbolicCode::new(
            vec![0],
            vec![Relocation {
                offset: 0,
                reference: SymRef::BuiltinGlobalVars,
                encoding: RelocationEncoding::Direct,
            }],
        )
        .unwrap();
        let mut expected = b"dm-symbolic-code-v2\0".to_vec();
        expected.extend_from_slice(&1u64.to_le_bytes());
        expected.extend_from_slice(&0u32.to_le_bytes());
        expected.extend_from_slice(&1u64.to_le_bytes());
        expected.extend_from_slice(&0u32.to_le_bytes());
        expected.extend_from_slice(&[0, 6]);
        assert_eq!(code.canonical_bytes(), expected);
    }
    // Retain the original storage validator as an independent error-order oracle.
    fn original_storage_validation(
        words: Vec<u32>,
        mut relocations: Vec<Relocation>,
    ) -> Result<SymbolicCode, RelocationError> {
        u32::try_from(words.len()).map_err(|_| RelocationError::WordCountOverflow)?;
        let mut seen = HashSet::new();
        for relocation in &relocations {
            for delta in 0..relocation.encoding.width() {
                let at = relocation
                    .offset
                    .checked_add(delta)
                    .ok_or(RelocationError::OutOfBounds(relocation.offset))?;
                let word = words
                    .get(at as usize)
                    .ok_or(RelocationError::OutOfBounds(at))?;
                if !seen.insert(at) {
                    return Err(RelocationError::Duplicate(at));
                }
                if *word != 0 {
                    return Err(RelocationError::NonzeroPlaceholder(at));
                }
            }
        }
        relocations.sort_unstable_by_key(|relocation| relocation.offset);
        Ok(SymbolicCode { words, relocations })
    }

    #[test]
    fn canonical_storage_fast_path_preserves_generic_errors_and_content() {
        let direct = RelocationEncoding::Direct;
        let packed = RelocationEncoding::PackedValue24 { tag: 6 };
        let site = |offset, encoding| Relocation {
            offset,
            reference: SymRef::String(SymbolId::of("text")),
            encoding,
        };
        let cases = [
            (vec![], vec![], None),
            (vec![0; 4], vec![site(0, packed), site(2, packed)], None),
            (vec![0; 4], vec![site(3, direct), site(0, packed)], None),
            (
                vec![0; 4],
                vec![site(0, packed), site(1, direct)],
                Some(RelocationError::Duplicate(1)),
            ),
            (
                vec![0; 4],
                vec![site(1, direct), site(0, packed)],
                Some(RelocationError::Duplicate(1)),
            ),
            (
                vec![1],
                vec![site(0, direct)],
                Some(RelocationError::NonzeroPlaceholder(0)),
            ),
            (
                vec![0, 1],
                vec![site(0, packed)],
                Some(RelocationError::NonzeroPlaceholder(1)),
            ),
            (
                vec![0],
                vec![site(0, packed)],
                Some(RelocationError::OutOfBounds(1)),
            ),
            (
                vec![0; 4],
                vec![site(u32::MAX, packed)],
                Some(RelocationError::OutOfBounds(u32::MAX)),
            ),
            (
                vec![1; 4],
                vec![site(0, direct), site(u32::MAX, packed)],
                Some(RelocationError::NonzeroPlaceholder(0)),
            ),
            (
                vec![1; 4],
                vec![site(4, direct), site(0, direct)],
                Some(RelocationError::OutOfBounds(4)),
            ),
        ];
        for (words, relocations, expected_error) in cases {
            let expected = original_storage_validation(words.clone(), relocations.clone());
            assert_eq!(expected.as_ref().err(), expected_error.as_ref());
            assert_eq!(SymbolicCode::new(words, relocations), expected);
        }
        // Both interval widths, both encounter orders, overlaps, out-of-bounds
        // and competing nonzero/duplicate failures, independent of golden cases.
        for bits in 0..16 {
            let words: Vec<_> = (0..4).map(|at| (bits >> at) & 1).collect();
            for left in 0..6 {
                for right in 0..6 {
                    for encoding in [direct, packed] {
                        let relocations = vec![site(left, encoding), site(right, packed)];
                        assert_eq!(
                            SymbolicCode::new(words.clone(), relocations.clone()),
                            original_storage_validation(words.clone(), relocations)
                        );
                    }
                }
            }
        }
    }

    #[test]
    fn borrowed_site_ledgers_preserve_unsorted_validation_and_error_precedence() {
        let packed = RelocationEncoding::PackedValue24 { tag: 6 };
        let direct = RelocationEncoding::Direct;
        let code = SymbolicCode::new(
            vec![0; 6],
            vec![
                Relocation {
                    offset: 3,
                    reference: SymRef::BuiltinGlobalVars,
                    encoding: direct,
                },
                Relocation {
                    offset: 0,
                    reference: SymRef::String(SymbolId::of("text")),
                    encoding: packed,
                },
            ],
        )
        .unwrap();
        let string = RelocationKind::String;
        let variable = RelocationKind::Variable;
        let fixtures = [
            (vec![(3, variable, direct), (0, string, packed)], Ok(())),
            (
                vec![
                    (3, string, direct),
                    (0, variable, packed),
                    (6, string, direct),
                ],
                Err(RelocationError::OutOfBounds(6)),
            ),
            (
                vec![(0, string, packed), (1, variable, direct)],
                Err(RelocationError::DuplicateSite(1)),
            ),
            (
                vec![(3, variable, direct)],
                Err(RelocationError::MissingSite(0)),
            ),
            (
                vec![(3, string, direct), (0, variable, packed)],
                Err(RelocationError::KindMismatch {
                    offset: 0,
                    expected: variable,
                    actual: string,
                }),
            ),
            (
                vec![(3, variable, direct), (0, string, direct)],
                Err(RelocationError::EncodingMismatch(0)),
            ),
            (
                vec![
                    (5, string, direct),
                    (3, variable, direct),
                    (2, string, direct),
                    (0, string, packed),
                ],
                Err(RelocationError::MissingRelocation(2)),
            ),
        ];
        for (sites, expected) in fixtures {
            assert_eq!(code.validate_encoded_sites(&sites), expected);
            assert_eq!(
                code.validate_encoded_sites_iter(sites.iter().copied()),
                expected
            );
        }
    }

    #[test]
    fn packed_values_validate_both_words_encoding_and_range() {
        let reference = SymRef::String(SymbolId::of("text"));
        let relocation = Relocation {
            offset: 0,
            reference,
            encoding: RelocationEncoding::PackedValue24 { tag: 6 },
        };
        assert_eq!(
            SymbolicCode::new(vec![0], vec![relocation]),
            Err(RelocationError::OutOfBounds(1))
        );
        assert_eq!(
            SymbolicCode::new(vec![0, 1], vec![relocation]),
            Err(RelocationError::NonzeroPlaceholder(1))
        );
        let overlapping = Relocation {
            offset: 1,
            reference,
            encoding: RelocationEncoding::Direct,
        };
        assert_eq!(
            SymbolicCode::new(vec![0, 0], vec![relocation, overlapping]),
            Err(RelocationError::Duplicate(1))
        );
        let code = SymbolicCode::new(vec![0, 0], vec![relocation]).unwrap();
        assert_eq!(
            code.validate_encoded_sites(&[(
                0,
                RelocationKind::String,
                RelocationEncoding::PackedValue24 { tag: 12 }
            )]),
            Err(RelocationError::EncodingMismatch(0))
        );
        assert_eq!(code.link(|_| Some(0x123456)).unwrap(), [0x1206, 0x3456]);
        assert_eq!(
            code.link(|_| Some(0x1000000)),
            Err(RelocationError::PackedValueOverflow {
                offset: 0,
                value: 0x1000000
            })
        );
        assert_eq!(code.words(), [0, 0]);
        let different_tag = SymbolicCode::new(
            vec![0, 0],
            vec![Relocation {
                encoding: RelocationEncoding::PackedValue24 { tag: 12 },
                ..relocation
            }],
        )
        .unwrap();
        assert_ne!(code.fingerprint(), different_tag.fingerprint());
    }

    #[test]
    fn typed_operand_sites_require_exact_reference_kinds() {
        let code = SymbolicCode::new(
            vec![42, 0],
            vec![Relocation {
                offset: 1,
                encoding: RelocationEncoding::Direct,
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
                    encoding: RelocationEncoding::Direct,
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
            encoding: RelocationEncoding::Direct,
            reference: proc,
        };
        let b = Relocation {
            offset: 1,
            encoding: RelocationEncoding::Direct,
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
                    encoding: RelocationEncoding::Direct,
                    reference: SymRef::LineDelta(4),
                },
                Relocation {
                    offset: 1,
                    encoding: RelocationEncoding::Direct,
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
            encoding: RelocationEncoding::Direct,
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
