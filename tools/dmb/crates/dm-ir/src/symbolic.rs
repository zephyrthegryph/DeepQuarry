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
    words: crate::WordStorage,
    sites: Box<[PackedSite]>,
    references: Box<[SymRef]>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
struct PackedSite {
    offset: u32,
    payload: u32,
    descriptor: u32,
}
const _: () = assert!(std::mem::size_of::<PackedSite>() == 12);
impl PackedSite {
    fn decode(self, references: &[SymRef]) -> Relocation {
        let reference = match self.descriptor >> 16 {
            0 => references[self.payload as usize],
            1 => SymRef::SourceFile(self.payload),
            2 => SymRef::SourceLine(self.payload),
            3 => SymRef::LineDelta(self.payload),
            _ => unreachable!("private validated relocation descriptor"),
        };
        let encoding = if self.descriptor & 0x100 == 0 {
            RelocationEncoding::Direct
        } else {
            RelocationEncoding::PackedValue24 {
                tag: self.descriptor as u8,
            }
        };
        Relocation {
            offset: self.offset,
            reference,
            encoding,
        }
    }
}
/// Borrowed allocation-free view yielding exact public relocation values.
#[derive(Clone)]
pub struct RelocationView<'a> {
    sites: std::slice::Iter<'a, PackedSite>,
    references: &'a [SymRef],
}
impl RelocationView<'_> {
    pub fn is_empty(&self) -> bool {
        self.sites.len() == 0
    }
    pub fn iter(&self) -> Self {
        self.clone()
    }
}
impl Iterator for RelocationView<'_> {
    type Item = Relocation;
    fn next(&mut self) -> Option<Self::Item> {
        self.sites.next().map(|site| site.decode(self.references))
    }
    fn size_hint(&self) -> (usize, Option<usize>) {
        self.sites.size_hint()
    }
}
impl DoubleEndedIterator for RelocationView<'_> {
    fn next_back(&mut self) -> Option<Self::Item> {
        self.sites
            .next_back()
            .map(|site| site.decode(self.references))
    }
}
impl ExactSizeIterator for RelocationView<'_> {}
impl std::iter::FusedIterator for RelocationView<'_> {}

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
    pub fn new(words: Vec<u32>, relocations: Vec<Relocation>) -> Result<Self, RelocationError> {
        Self::from_word_storage(crate::WordStorage::Owned(words), relocations)
    }
    /// Validate the SAME symbolic storage invariants over owned or shared bytes.
    /// Borrowed backing never certifies opcode shape or semantic reference facts.
    pub fn from_word_storage(
        words: crate::WordStorage,
        mut relocations: Vec<Relocation>,
    ) -> Result<Self, RelocationError> {
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
                    .word_at(at as usize)
                    .ok_or(RelocationError::OutOfBounds(at))?;
                if seen.as_mut().is_some_and(|seen| !seen.insert(at)) {
                    return Err(RelocationError::Duplicate(at));
                }
                if word != 0 {
                    return Err(RelocationError::NonzeroPlaceholder(at));
                }
            }
        }
        if !canonical {
            relocations.sort_unstable_by_key(|relocation| relocation.offset);
        }
        Ok(Self::compact(words, relocations))
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
                if self.words.word_at(at as usize).is_none() {
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
        for relocation in self.relocations() {
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
        for word in self.words.iter() {
            bytes(&word.to_le_bytes())
        }
        bytes(&(self.sites.len() as u64).to_le_bytes());
        for relocation in self.relocations() {
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

    /// Compatibility slice view. Shared little-endian backing materializes only
    /// when a slice is explicitly requested; current consumers should use the
    /// allocation-free word_len/word_at/word_iter boundary where possible.
    pub fn words(&self) -> std::borrow::Cow<'_, [u32]> {
        match self.words.owned_slice() {
            Some(words) => std::borrow::Cow::Borrowed(words),
            None => std::borrow::Cow::Owned(self.words.to_vec()),
        }
    }
    pub fn word_len(&self) -> usize {
        self.words.len()
    }
    pub fn word_at(&self, at: usize) -> Option<u32> {
        self.words.word_at(at)
    }
    pub fn word_iter(&self) -> crate::WordIter<'_> {
        self.words.iter()
    }
    pub fn visit_shared_word_heap_storage(
        &self,
        visit: impl FnMut(usize, usize, usize),
    ) -> Option<bool> {
        self.words.visit_shared_heap_storage(visit)
    }
    pub fn word_storage(&self) -> crate::WordStorageView {
        self.words.storage()
    }

    pub fn relocations(&self) -> RelocationView<'_> {
        RelocationView {
            sites: self.sites.iter(),
            references: &self.references,
        }
    }
    pub fn relocation(&self, index: usize) -> Option<Relocation> {
        self.sites
            .get(index)
            .map(|site| site.decode(&self.references))
    }
    /// Word vector capacity and exact compact-site allocation length.
    pub fn storage_capacities(&self) -> (usize, usize) {
        let capacity = match self.words.storage() {
            crate::WordStorageView::Owned { capacity_bytes, .. } => capacity_bytes / 4,
            crate::WordStorageView::Shared { .. } => 0,
        };
        (capacity, self.sites.len())
    }
    /// Exact retained buffers; no expanded relocation array is materialized.
    pub fn visit_storage(&self, mut visitor: impl FnMut(usize, usize, usize)) {
        if let crate::WordStorageView::Owned {
            address,
            length_bytes,
            capacity_bytes,
        } = self.words.storage()
        {
            visitor(address, length_bytes, capacity_bytes);
        }
        visitor(
            self.sites.as_ptr() as usize,
            self.sites.len() * 12,
            self.sites.len() * 12,
        );
        visitor(
            self.references.as_ptr() as usize,
            self.references.len() * std::mem::size_of::<SymRef>(),
            self.references.len() * std::mem::size_of::<SymRef>(),
        );
    }
    pub fn reference_count(&self) -> usize {
        self.references.len()
    }
    fn compact(words: crate::WordStorage, relocations: Vec<Relocation>) -> Self {
        let mut references = Vec::new();
        let mut indexes = HashMap::new();
        let sites = relocations
            .into_iter()
            .map(|relocation| {
                let (kind, payload) = match relocation.reference {
                    SymRef::SourceFile(value) => (1, value),
                    SymRef::SourceLine(value) => (2, value),
                    SymRef::LineDelta(value) => (3, value),
                    reference => (
                        0,
                        *indexes.entry(reference).or_insert_with(|| {
                            let index = u32::try_from(references.len())
                                .expect("reference count bounded by validated words");
                            references.push(reference);
                            index
                        }),
                    ),
                };
                let encoding = match relocation.encoding {
                    RelocationEncoding::Direct => 0,
                    RelocationEncoding::PackedValue24 { tag } => 0x100 | u32::from(tag),
                };
                PackedSite {
                    offset: relocation.offset,
                    payload,
                    descriptor: (kind << 16) | encoding,
                }
            })
            .collect::<Vec<_>>()
            .into_boxed_slice();
        Self {
            words,
            sites,
            references: references.into_boxed_slice(),
        }
    }

    /// Resolve into a private image, leaving shared symbolic code unchanged on
    /// both success and failure. Resolution order is canonical word-offset order.
    pub fn link(
        &self,
        mut resolve: impl FnMut(SymRef) -> Option<u32>,
    ) -> Result<Vec<u32>, RelocationError> {
        let mut linked = self.words.to_vec();
        for relocation in self.relocations() {
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
mod tests;
