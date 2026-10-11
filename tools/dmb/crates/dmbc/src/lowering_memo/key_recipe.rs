//! Borrowed current key inputs; exact bytes remain the sole persisted format.
use std::{ops::Range, sync::Arc};
pub(super) const PREFIX: &[u8] = b"dmbc-procedure-memo-v28-nameof-current-reference\0";
pub(crate) struct CurrentKey<'a> {
    prefix: [u8; 41],
    pub metadata: &'a Arc<dm_ir::ProcedureMetadata>,
    source: &'a [u8],
    termination: u8,
    references: bool,
    selections: bool,
}
pub(crate) enum PreparedKey {
    Issued(Arc<[u8]>),
    Parsed(Vec<u8>),
}
impl PreparedKey {
    pub fn issued(prepared: &crate::procedure_policy::PreparedUnit) -> Option<Self> {
        Some(Self::Issued(prepared.canonical_metadata()?))
    }
    fn append(&self, key: &mut Vec<u8>) {
        match self {
            Self::Parsed(bytes) => key.extend_from_slice(bytes),
            Self::Issued(bytes) => {
                key.extend_from_slice(bytes);
                key.push(1);
                let transform = crate::procedure_policy::PreparedReplay::TRANSFORM;
                key.extend_from_slice(&(transform.len() as u64).to_le_bytes());
                key.extend_from_slice(transform);
            }
        }
    }
    fn matches(&self, bytes: &[u8]) -> bool {
        match self {
            Self::Parsed(expected) => bytes == expected,
            Self::Issued(expected) => {
                let Some(rest) = bytes.strip_prefix(expected.as_ref()) else {
                    return false;
                };
                let transform = crate::procedure_policy::PreparedReplay::TRANSFORM;
                rest.first() == Some(&1)
                    && rest.get(1..9) == Some(&(transform.len() as u64).to_le_bytes()[..])
                    && rest.get(9..) == Some(transform)
            }
        }
    }
}
pub(crate) struct KeyRecipe {
    pub metadata: Arc<dm_ir::ProcedureMetadata>,
    source: Range<usize>,
    tail: Range<usize>,
}
impl<'a> CurrentKey<'a> {
    #[cfg(test)]
    pub fn new(
        frontend: &'a dm_tree::frontend::ColdFrontend,
        body: &dm_tree::frontend::BodyOccurrence,
        policy: u128,
        references: bool,
        selections: bool,
    ) -> Option<Self> {
        let issued = frontend.body_input(body).ok()?;
        let identity = crate::lowering::source_identity_for_issued(frontend, &issued).ok()?;
        Self::from_issued(frontend, &issued, identity, policy, references, selections)
    }
    pub(crate) fn from_prepared(
        frontend: &'a dm_tree::frontend::ColdFrontend,
        row: &crate::lowering::PreparedBody<'a>,
        policy: u128,
        references: bool,
        selections: bool,
    ) -> Option<Self> {
        if !row.authenticates(frontend) { return None; }
        Self::from_issued(frontend, row.input(), row.source(), policy, references, selections)
    }
    fn from_issued(
        frontend: &'a dm_tree::frontend::ColdFrontend,
        issued: &dm_tree::frontend::IssuedBodyInput<'a>,
        identity: crate::lowering::SourceUnitIdentity,
        policy: u128,
        references: bool,
        selections: bool,
    ) -> Option<Self> {
        let body = issued.occurrence();
        let tree = &frontend.snapshot.tree;
        let member = tree.member(body.member)?;
        let mut prefix = [0; 41];
        prefix[..16].copy_from_slice(&policy.to_le_bytes());
        prefix[16..24].copy_from_slice(&identity.identity.owner.bits().to_le_bytes());
        prefix[24..32].copy_from_slice(&identity.identity.name.bits().to_le_bytes());
        prefix[32] = u8::from(identity.identity.namespace == crate::lowering::Namespace::Verb);
        prefix[33..41]
            .copy_from_slice(&u64::from(identity.identity.occurrence).to_le_bytes());
        Some(Self {
            prefix,
            metadata: member.metadata.procedure.as_ref()?,
            source: issued.source().as_bytes(),
            termination: issued.termination().canonical_tag(),
            references,
            selections,
        })
    }
    pub fn materialize(&self, prepared: &PreparedKey) -> Vec<u8> {
        let metadata = self.metadata.canonical_bytes();
        let mut key = PREFIX.to_vec();
        key.extend_from_slice(&self.prefix[..41]);
        for part in [metadata.as_slice(), self.source] {
            key.extend_from_slice(&(part.len() as u64).to_le_bytes());
            key.extend_from_slice(part);
        }
        key.push(self.termination);
        if self.references {
            key.push(0);
            key.extend_from_slice(dm_ir::SELECTED_REFERENCES_POLICY);
        }
        if self.selections {
            key.extend_from_slice(b"selected-facts-only-v1");
        }
        prepared.append(&mut key);
        key
    }
    pub fn matches(&self, key: &[u8], recipe: Option<&KeyRecipe>, prepared: &PreparedKey) -> bool {
        let Some(layout) = Layout::parse(key) else {
            return false;
        };
        if key.get(..PREFIX.len()) != Some(PREFIX)
            || key.get(PREFIX.len()..PREFIX.len() + 41) != Some(&self.prefix[..41])
            || key.get(layout.source.clone()) != Some(self.source)
        {
            return false;
        }
        let metadata_matches = recipe.map_or_else(
            || key.get(layout.metadata.clone()) == Some(self.metadata.canonical_bytes().as_slice()),
            |r| {
                (Arc::ptr_eq(&r.metadata, self.metadata)
                    || r.metadata == *self.metadata
                    || key.get(layout.metadata.clone())
                        == Some(self.metadata.canonical_bytes().as_slice()))
                    && r.source == layout.source
                    && r.tail == layout.tail
            },
        );
        let Some(mut tail) = key[layout.tail].strip_prefix(&[self.termination]) else {
            return false;
        };
        if self.references {
            let Some(rest) = tail
                .strip_prefix(&[0])
                .and_then(|rest| rest.strip_prefix(dm_ir::SELECTED_REFERENCES_POLICY))
            else {
                return false;
            };
            tail = rest;
        }
        if self.selections {
            let Some(rest) = tail.strip_prefix(b"selected-facts-only-v1") else {
                return false;
            };
            tail = rest;
        }
        metadata_matches && prepared.matches(tail)
    }
}
struct Layout {
    metadata: Range<usize>,
    source: Range<usize>,
    tail: Range<usize>,
}
impl Layout {
    fn parse(key: &[u8]) -> Option<Self> {
        let mut at = PREFIX.len().checked_add(41)?;
        fn part(key: &[u8], at: &mut usize) -> Option<Range<usize>> {
            let len = usize::try_from(u64::from_le_bytes(
                key.get(*at..at.checked_add(8)?)?.try_into().ok()?,
            ))
            .ok()?;
            let start = at.checked_add(8)?;
            let end = start.checked_add(len)?;
            key.get(start..end)?;
            *at = end;
            Some(start..end)
        }
        let metadata = part(key, &mut at)?;
        let source = part(key, &mut at)?;
        Some(Self {
            metadata,
            source,
            tail: at..key.len(),
        })
    }
}
impl KeyRecipe {
    /// Compare the producer's existing source slice, without constructing a key.
    pub(crate) fn source_matches(&self, key: &[u8], source: &[u8]) -> bool {
        key.get(self.source.clone()) == Some(source)
    }

    pub fn new(key: &[u8], metadata: Arc<dm_ir::ProcedureMetadata>) -> Option<Self> {
        let layout = Layout::parse(key)?;
        if key.get(..PREFIX.len()) != Some(PREFIX)
            || key.get(layout.metadata) != Some(metadata.canonical_bytes().as_slice())
        {
            return None;
        }
        Some(Self {
            metadata,
            source: layout.source,
            tail: layout.tail,
        })
    }
}

#[cfg(test)]
#[path = "key_recipe_tests.rs"]
mod tests;
