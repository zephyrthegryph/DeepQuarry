//! Domain-version tokens as content digests.
//!
//! A token certifies one exact input state (a name's local declarations and its parent's token, an owner's ancestry, a
//! name's storage inventory answer, a procedure's static roster). It is the xxh3-128 of a canonical encoding of that
//! state under a domain tag and the artifact key, so equal inputs give equal tokens in every session and every
//! restart, and different inputs give different tokens (up to the digest width). The processes used to issue them from a
//! counter, which made two sessions with identical declarations hold unequal tokens and nothing shareable. Semantics:
//! `tools/dmb/doc/incremental_core.md`, "Domain-version tokens are content digests".
use xxhash_rust::xxh3::Xxh3;

/// Incremental canonical encoder. Every variable-length part is length-prefixed and every optional part carries a
/// presence byte, so two different states can never produce the same byte stream.
pub(crate) struct TokenDigest(Xxh3);
impl TokenDigest {
    pub(crate) fn new(tag: &[u8]) -> Self {
        let mut hash = Xxh3::new();
        hash.update(&(tag.len() as u64).to_le_bytes());
        hash.update(tag);
        Self(hash)
    }
    pub(crate) fn u8(&mut self, value: u8) -> &mut Self {
        self.0.update(&[value]);
        self
    }
    pub(crate) fn bool(&mut self, value: bool) -> &mut Self {
        self.u8(u8::from(value))
    }
    pub(crate) fn u32(&mut self, value: u32) -> &mut Self {
        self.0.update(&value.to_le_bytes());
        self
    }
    pub(crate) fn u64(&mut self, value: u64) -> &mut Self {
        self.0.update(&value.to_le_bytes());
        self
    }
    pub(crate) fn u128(&mut self, value: u128) -> &mut Self {
        self.0.update(&value.to_le_bytes());
        self
    }
    pub(crate) fn opt_u128(&mut self, value: Option<u128>) -> &mut Self {
        self.bool(value.is_some());
        self.u128(value.unwrap_or(0))
    }
    pub(crate) fn bytes(&mut self, value: &[u8]) -> &mut Self {
        self.u64(value.len() as u64);
        self.0.update(value);
        self
    }
    pub(crate) fn symbol(&mut self, value: crate::SymbolId) -> &mut Self {
        self.u64(value.bits())
    }
    pub(crate) fn opt_symbol(&mut self, value: Option<crate::SymbolId>) -> &mut Self {
        self.bool(value.is_some());
        self.u64(value.map_or(0, crate::SymbolId::bits))
    }
    pub(crate) fn len(&mut self, count: usize) -> &mut Self {
        self.u64(count as u64)
    }
    pub(crate) fn finish(&self) -> u128 {
        self.0.digest128()
    }
}

pub(crate) fn kind_byte(kind: crate::MemberKind) -> u8 {
    match kind {
        crate::MemberKind::Var => 0,
        crate::MemberKind::Proc => 1,
        crate::MemberKind::Verb => 2,
    }
}
pub(crate) fn definition_byte(mode: crate::DefinitionMode) -> u8 {
    match mode {
        crate::DefinitionMode::Declare => 0,
        crate::DefinitionMode::Override => 1,
        crate::DefinitionMode::Reopen => 2,
        crate::DefinitionMode::Implicit => 3,
    }
}
pub(crate) fn intrinsic(digest: &mut TokenDigest, member: &crate::IntrinsicMember) {
    digest
        .symbol(member.owner)
        .symbol(member.name)
        .u8(kind_byte(member.kind))
        .opt_symbol(member.shared_owner)
        .bool(member.instance_storage_proven);
}
