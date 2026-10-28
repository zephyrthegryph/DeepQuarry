//! One immutable locator allocation, with an exact raw procedure-key suffix.
//! The store owns the full locator; records and local certificates clone its owner
//! and retain the suffix offset. Neither the locator nor the raw key is a hash-only
//! identity, and changing the procedure identity never changes the raw key bytes.
use super::{Arc, UnitIdentity};
use std::ops::Deref;
#[derive(Clone, Debug)]
pub(super) struct SharedKey {
    owner: Arc<[u8]>,
    start: usize,
}
impl From<Arc<[u8]>> for SharedKey {
    fn from(owner: Arc<[u8]>) -> Self {
        Self { owner, start: 0 }
    }
}
impl From<Vec<u8>> for SharedKey {
    fn from(bytes: Vec<u8>) -> Self {
        Arc::<[u8]>::from(bytes).into()
    }
}
impl Deref for SharedKey {
    type Target = [u8];
    fn deref(&self) -> &[u8] {
        &self.owner[self.start..]
    }
}
impl AsRef<[u8]> for SharedKey {
    fn as_ref(&self) -> &[u8] {
        self
    }
}
impl PartialEq for SharedKey {
    fn eq(&self, other: &Self) -> bool {
        self.as_ref() == other.as_ref()
    }
}
impl Eq for SharedKey {}
impl SharedKey {
    pub(super) fn for_locator(&self, identity: UnitIdentity) -> Self {
        let prefix = crate::symbolic::shared_procedure_code::key(identity, None);
        if self.start == prefix.len() && self.owner[..self.start] == prefix {
            return self.clone();
        }
        let start = prefix.len();
        let mut bytes = prefix;
        bytes.extend_from_slice(self);
        Self {
            owner: bytes.into(),
            start,
        }
    }
    pub(super) fn owner(&self) -> &Arc<[u8]> {
        &self.owner
    }
    pub(super) fn same_backing(&self, other: &Self) -> bool {
        self.start == other.start && Arc::ptr_eq(&self.owner, &other.owner)
    }
    pub(super) fn raw_owner(&self) -> Arc<[u8]> {
        // Only the existing noncompact RichIR fallback requires a standalone Arc.
        // Published symbolic records keep the shared suffix instead. A raw source
        // key already has the required shape and is reused without copying.
        if self.start == 0 {
            Arc::clone(&self.owner)
        } else {
            Arc::from(self.as_ref())
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn identity() -> UnitIdentity {
        UnitIdentity {
            owner: dm_ir::SymbolId::of("/datum/shared_key_probe"),
            name: dm_ir::SymbolId::of("check"),
            namespace: crate::lowering::Namespace::Proc,
            occurrence: 0,
        }
    }

    #[test]
    fn exact_locator_reuses_owner_and_identity_changes_preserve_raw_bytes() {
        let raw: SharedKey = b"exact body\0with binary tail".to_vec().into();
        let base = identity();
        let located = raw.for_locator(base);
        assert_eq!(located.as_ref(), raw.as_ref());
        assert_eq!(
            located.owner().as_ref(),
            super::super::symbolic_publication::locator(base, &raw)
        );
        assert!(located.for_locator(base).same_backing(&located));
        for changed in [
            UnitIdentity {
                owner: dm_ir::SymbolId::of("/datum/other"),
                ..base
            },
            UnitIdentity {
                name: dm_ir::SymbolId::of("other"),
                ..base
            },
            UnitIdentity {
                namespace: crate::lowering::Namespace::Verb,
                ..base
            },
            UnitIdentity {
                occurrence: 1,
                ..base
            },
        ] {
            let rebound = located.for_locator(changed);
            assert_eq!(rebound.as_ref(), raw.as_ref());
            assert_eq!(
                rebound.owner().as_ref(),
                super::super::symbolic_publication::locator(changed, &raw)
            );
            assert!(!rebound.same_backing(&located));
        }
        assert!(Arc::ptr_eq(&raw.raw_owner(), raw.owner()));
        assert_eq!(located.raw_owner().as_ref(), raw.as_ref());
    }

    #[test]
    fn empty_raw_key_is_an_exact_empty_suffix_not_the_locator_prefix() {
        let raw: SharedKey = Vec::new().into();
        let located = raw.for_locator(identity());
        assert!(located.is_empty());
        assert!(!located.owner().is_empty());
        assert!(located.for_locator(identity()).same_backing(&located));
    }
}
