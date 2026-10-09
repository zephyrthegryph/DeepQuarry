//! Final VM value domains are distinct from declaration/class table domains.
//! Only certified relocations are interpreted; retained template code and values
//! already emitted in their native domain must never be scanned or rewritten.
use crate::LinkTables;
use dm_ir::{SymbolId, SymbolicCode};
use std::collections::HashMap;

pub type MobBindings = HashMap<SymbolId, u32>;

#[derive(Debug, PartialEq, Eq)]
pub enum WireDomainError {
    MissingClass(SymbolId),
    MissingMob(SymbolId),
    InvalidSite(u32),
    WrongClassBinding(u32),
    MobIndexOverflow(u32),
    UnsupportedClientPath(SymbolId),
}

/// Admit class-symbolic type values to their actual VM domains. Input
/// words must still carry the certified class binding. The final output visitor
/// remains mandatory after this admission and all other mutable writer stages.
pub fn admit_type_path_words(
    words: &mut [u32],
    code: &SymbolicCode,
    tables: &LinkTables,
    mobs: &MobBindings,
) -> Result<(), WireDomainError> {
    for site in code.relocations() {
        if let Some(patch) = crate::type_path_binding::resolve_site(words, site, tables, mobs)? {
            crate::type_path_binding::apply(words, patch);
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{Key, LinkInventory};
    use dm_ir::{Relocation, RelocationEncoding, SymRef};

    #[test]
    fn root_client_path_has_singleton_payload_without_rewriting_other_class_values() {
        let path = SymbolId::of("/client");
        let tables = LinkTables::build(LinkInventory {
            fixed: vec![(Key::Type(path), 9)],
            spellings: vec![(path, std::sync::Arc::from(b"/client".as_slice()))],
            entries: vec![crate::Entry {
                key: Key::Type(path),
                content: std::sync::Arc::<[u8]>::from(b"client".as_slice()).into(),
            }],
            ..Default::default()
        })
        .unwrap();
        let code = SymbolicCode::new(
            vec![0, 0, 0, 0, 59, 0],
            vec![
                Relocation {
                    offset: 0,
                    reference: SymRef::Type(path),
                    encoding: RelocationEncoding::PackedValue24 { tag: 59 },
                },
                Relocation {
                    offset: 2,
                    reference: SymRef::Type(path),
                    encoding: RelocationEncoding::PackedValue24 { tag: 32 },
                },
            ],
        )
        .unwrap();
        let mut words = code.link(|_| Some(9)).unwrap();
        admit_type_path_words(&mut words, &code, &tables, &HashMap::new()).unwrap();
        assert_eq!(words, [59, 0, 32, 9, 59, 0]);
    }

    #[test]
    fn mob_path_domain_is_distinct_from_same_symbol_class_and_retained_values() {
        let path = SymbolId::of("/mob/example");
        let tables = LinkTables::build(LinkInventory {
            fixed: vec![(Key::Type(path), 100)],
            spellings: vec![(path, std::sync::Arc::from(b"/mob/example".as_slice()))],
            entries: vec![crate::Entry {
                key: Key::Type(path),
                content: std::sync::Arc::<[u8]>::from(b"mob".as_slice()).into(),
            }],
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
                    encoding: RelocationEncoding::PackedValue24 { tag: 9 },
                },
            ],
        )
        .unwrap();
        let original = code.link(|_| Some(100)).unwrap();
        let mut words = original.clone();
        let mobs = HashMap::from([(path, 7)]);
        admit_type_path_words(&mut words, &code, &tables, &mobs).unwrap();
        assert_eq!(words, [8, 7, 9, 100, 8, 7]);
        // Frozen class-domain image remains unchanged; already-native raw mob
        // values with no relocation were never visited or double-remapped.
        assert_eq!(original, [8, 100, 9, 100, 8, 7]);
        assert_eq!(
            admit_type_path_words(&mut words, &code, &tables, &mobs),
            Err(WireDomainError::WrongClassBinding(0))
        );
        assert_eq!(
            admit_type_path_words(&mut original.clone(), &code, &tables, &HashMap::new()),
            Err(WireDomainError::MissingMob(path))
        );
        assert_eq!(
            admit_type_path_words(
                &mut original.clone(),
                &code,
                &tables,
                &HashMap::from([(path, 0x0100_0000)])
            ),
            Err(WireDomainError::MobIndexOverflow(0x0100_0000))
        );
        assert_eq!(
            admit_type_path_words(&mut [], &code, &tables, &mobs),
            Err(WireDomainError::InvalidSite(0))
        );
    }
}
