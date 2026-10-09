//! Current packed type-value bindings, issued from certified relocation sites.
use crate::{Key, LinkTables, MobBindings, ProcedureImage, WireDomainError};
use dm_ir::{Relocation, RelocationEncoding, SymRef, SymbolId, SymbolicCode};
use std::sync::Arc;

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct TypePathPatch {
    offset: usize,
    words: [u32; 2],
}
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct TypePathAnswers(Arc<Vec<TypePathPatch>>);
impl TypePathAnswers {
    pub fn storage(&self) -> &Arc<Vec<TypePathPatch>> {
        &self.0
    }
}
/// This proof borrows exactly the input words it validated. Its constructor is
/// private; encoding cannot apply answers to another or mutated image.
pub struct BoundTypeWords<'a> {
    words: &'a [u32],
    patches: Vec<TypePathPatch>,
}
impl BoundTypeWords<'_> {
    pub fn is_empty(&self) -> bool {
        self.patches.is_empty()
    }
    pub fn matches(&self, answers: &TypePathAnswers) -> bool {
        self.patches == *answers.0
    }
    pub fn encode_with_answers(self) -> (ProcedureImage, TypePathAnswers) {
        let mut words = self.words.to_vec();
        for patch in &self.patches {
            words[patch.offset..patch.offset + 2].copy_from_slice(&patch.words);
        }
        (
            ProcedureImage {
                words: Arc::new(words),
            },
            TypePathAnswers(Arc::new(self.patches)),
        )
    }
}
pub fn bind_type_path_words<'a>(
    words: &'a [u32],
    code: &SymbolicCode,
    tables: &LinkTables,
    mobs: &MobBindings,
) -> Result<BoundTypeWords<'a>, WireDomainError> {
    let mut patches = Vec::new();
    // SymbolicCode's checked site constructor forbids all overlapping sites.
    // The fresh in-place writer below and this borrowed producer therefore read
    // identical certified pairs in the same first-error order.
    for site in code.relocations() {
        if let Some(patch) = resolve_site(words, site, tables, mobs)? {
            patches.push(patch);
        }
    }
    Ok(BoundTypeWords { words, patches })
}
pub(super) fn resolve_site(
    words: &[u32],
    site: Relocation,
    tables: &LinkTables,
    mobs: &MobBindings,
) -> Result<Option<TypePathPatch>, WireDomainError> {
    let tag = match site.encoding {
        RelocationEncoding::PackedValue24 {
            tag: tag @ (8 | 59),
        } => tag,
        _ => return Ok(None),
    };
    let SymRef::Type(path) = site.reference else {
        return Err(WireDomainError::InvalidSite(site.offset));
    };
    let class = tables
        .index(Key::Type(path))
        .ok_or(WireDomainError::MissingClass(path))?;
    let mob = if tag == 59 {
        if path != SymbolId::of("/client") {
            return Err(WireDomainError::UnsupportedClientPath(path));
        }
        0
    } else {
        *mobs.get(&path).ok_or(WireDomainError::MissingMob(path))?
    };
    if mob > 0x00ff_ffff {
        return Err(WireDomainError::MobIndexOverflow(mob));
    }
    let offset = site.offset as usize;
    let pair = words
        .get(
            offset
                ..offset
                    .checked_add(2)
                    .ok_or(WireDomainError::InvalidSite(site.offset))?,
        )
        .ok_or(WireDomainError::InvalidSite(site.offset))?;
    if pair != [u32::from(tag) | ((class >> 16) << 8), class & 0xffff] {
        return Err(WireDomainError::WrongClassBinding(site.offset));
    }
    Ok(Some(TypePathPatch {
        offset,
        words: [u32::from(tag) | ((mob >> 16) << 8), mob & 0xffff],
    }))
}
pub(super) fn apply(words: &mut [u32], patch: TypePathPatch) {
    words[patch.offset..patch.offset + 2].copy_from_slice(&patch.words);
}
#[cfg(test)]
mod tests {
    use super::*;
    use crate::{Entry, LinkInventory};
    use dm_ir::{Relocation, RelocationEncoding};
    #[test]
    fn borrowed_proof_matches_current_mob_map_and_rejects_mutated_base_pair() {
        let path = SymbolId::of("/mob/example");
        let tables = LinkTables::build(LinkInventory {
            fixed: vec![(Key::Type(path), 100)],
            entries: vec![Entry {
                key: Key::Type(path),
                content: b"type".to_vec().into(),
            }],
            spellings: vec![(path, Arc::from(&b"/mob/example"[..]))],
            ..Default::default()
        })
        .unwrap();
        let code = SymbolicCode::new(
            vec![0, 0, 0, 0, 8, 7],
            vec![
                Relocation {
                    offset: 0,
                    reference: SymRef::Type(path),
                    encoding: RelocationEncoding::PackedValue24 { tag: 8 },
                },
                Relocation {
                    offset: 2,
                    reference: SymRef::Type(path),
                    encoding: RelocationEncoding::PackedValue24 { tag: 32 },
                },
            ],
        )
        .unwrap();
        let base = code.link(|_| Some(100)).unwrap();
        let mobs = MobBindings::from([(path, 7)]);
        let (image, answers) = bind_type_path_words(&base, &code, &tables, &mobs)
            .unwrap()
            .encode_with_answers();
        assert_eq!(image.words.as_slice(), &[8, 7, 32, 100, 8, 7]);
        assert!(bind_type_path_words(&base, &code, &tables, &mobs)
            .unwrap()
            .matches(&answers));
        let changed = MobBindings::from([(path, 8)]);
        assert!(!bind_type_path_words(&base, &code, &tables, &changed)
            .unwrap()
            .matches(&answers));
        let mut wrong = base.clone();
        wrong[1] = 999;
        assert!(matches!(
            bind_type_path_words(&wrong, &code, &tables, &mobs),
            Err(WireDomainError::WrongClassBinding(0))
        ));
        let mut in_place = base;
        crate::admit_type_path_words(&mut in_place, &code, &tables, &changed).unwrap();
        assert_eq!(in_place, vec![8, 8, 32, 100, 8, 7]);
    }
}
