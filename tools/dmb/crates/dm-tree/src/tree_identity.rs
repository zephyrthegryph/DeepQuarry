use super::*;
use xxhash_rust::xxh3::Xxh3;

// The declaration identity of a tree (v4): the engine prefix rows in order, then the authored rows as one digest per owner
// (that owner's rows in authored order, `owner_digest`, kept in its `TypeContribution`) and the authored order as the roster of
// (owner, row within owner) handles, then the field catalog. It names the same row sequence the v3 hash over every row named (the
// handles and the per-owner rows give the sequence back), but a request that changes one owner hashes that owner's rows and the
// handles, not every row again. The tag changed with the definition, so no v3 value is taken for a v4 one: every consumer keys on
// the value as an opaque revision (query revisions, class projections, the answer world), none persists a v3 value it would
// compare against.
const IDENTITY_TAG: &[u8] = b"dm-tree-v4\0";

#[cfg(test)]
pub(crate) fn declaration_identity(
    skeletons: &[Skeleton],
    fields: &[dm_ir::OpaqueFieldBase],
) -> u128 {
    declaration_identity_view(skeletons.into(), 0, fields)
}
/// The identity of a flat row sequence whose first `prefix` rows are the engine prefix (a build without retained declarations).
pub(crate) fn declaration_identity_view(
    rows: crate::skeleton_roster::SkeletonView<'_>,
    prefix: usize,
    fields: &[dm_ir::OpaqueFieldBase],
) -> u128 {
    let authored = flat_authored_digest(rows.slice(prefix..rows.len()));
    identity_of(rows.slice(0..prefix).iter(), authored, fields)
}
/// Byte sink of the identity rows: the streaming hasher, or a buffer hashed in one call (the same digest).
trait RowSink {
    fn update(&mut self, bytes: &[u8]);
}
impl RowSink for Xxh3 {
    fn update(&mut self, bytes: &[u8]) {
        Xxh3::update(self, bytes);
    }
}
impl RowSink for Vec<u8> {
    fn update(&mut self, bytes: &[u8]) {
        self.extend_from_slice(bytes);
    }
}
fn update_row(bytes: &mut impl RowSink, skeleton: &Skeleton, fingerprint: Option<u128>) {
    match skeleton {
        Skeleton::Type {
            path,
            explicit_parent,
        } => {
            bytes.update(&[0]);
            bytes.update(&path.bits().to_le_bytes());
            bytes.update(&[u8::from(explicit_parent.is_some())]);
            bytes.update(
                &explicit_parent
                    .map(SymbolId::bits)
                    .unwrap_or(0)
                    .to_le_bytes(),
            );
        }
        Skeleton::Member {
            owner,
            name,
            kind,
            mode,
            metadata,
            content,
        } => {
            bytes.update(&[1]);
            bytes.update(&owner.bits().to_le_bytes());
            bytes.update(&name.bits().to_le_bytes());
            bytes.update(&[*kind as u8]);
            bytes.update(&[*mode as u8]);
            bytes.update(&content.to_le_bytes());
            bytes.update(
                &fingerprint
                    .unwrap_or_else(|| metadata_fingerprint(metadata))
                    .to_le_bytes(),
            );
        }
    }
}
fn finish_identity(mut bytes: Xxh3, fields: &[dm_ir::OpaqueFieldBase]) -> u128 {
    let mut catalog = fields.iter().collect::<Vec<_>>();
    catalog.sort_by_key(|field| (field.owner, field.name));
    catalog.dedup();
    for field in catalog {
        let data = field.canonical_bytes();
        bytes.update(&(data.len() as u64).to_le_bytes());
        bytes.update(&data);
    }
    bytes.digest128()
}
/// The digest of one owner's authored rows, in authored order (each member row with its metadata fingerprint).
pub(crate) fn owner_digest(rows: &[crate::declaration_contributions::DeclarationRow]) -> u128 {
    let mut buffer: Vec<u8> = Vec::with_capacity(rows.len() * 64 + 16);
    buffer.update(b"owner\0");
    for row in rows {
        update_row(&mut buffer, &row.skeleton, Some(row.metadata_fingerprint()));
    }
    buffer.update(&(rows.len() as u64).to_le_bytes());
    xxhash_rust::xxh3::xxh3_128(&buffer)
}
/// The authored digest: the handle roster (authored order as owner and row within owner), then each owner's digest in owner order.
fn authored_digest(
    handles: impl ExactSizeIterator<Item = (SymbolId, u32)>,
    owners: impl ExactSizeIterator<Item = (SymbolId, u128)>,
) -> u128 {
    let mut buffer: Vec<u8> = Vec::with_capacity(handles.len() * 12 + owners.len() * 24 + 32);
    buffer.update(b"authored\0");
    buffer.update(&(handles.len() as u64).to_le_bytes());
    for (owner, row) in handles {
        buffer.update(&owner.bits().to_le_bytes());
        buffer.update(&row.to_le_bytes());
    }
    buffer.update(&(owners.len() as u64).to_le_bytes());
    for (owner, digest) in owners {
        buffer.update(&owner.bits().to_le_bytes());
        buffer.update(&digest.to_le_bytes());
    }
    xxhash_rust::xxh3::xxh3_128(&buffer)
}
/// `authored_digest` of retained declarations: the owners' kept digests, no row read.
pub(crate) fn indexed_authored_digest(index: &crate::declaration_contributions::KeyedDeclarations) -> u128 {
    authored_digest(
        index.roster().iter().map(|handle| (handle.owner, handle.row)),
        index.owners().map(|(owner, value)| (*owner, value.digest())),
    )
}
/// `authored_digest` of a flat authored row sequence (grouped here as `KeyedDeclarations::capture` groups it).
fn flat_authored_digest(rows: crate::skeleton_roster::SkeletonView<'_>) -> u128 {
    let mut grouped = std::collections::BTreeMap::<SymbolId, Vec<usize>>::new();
    let mut handles = Vec::with_capacity(rows.len());
    for (index, row) in rows.iter().enumerate() {
        let owner = match row {
            Skeleton::Type { path, .. } => *path,
            Skeleton::Member { owner, .. } => *owner,
        };
        let group = grouped.entry(owner).or_default();
        handles.push((owner, group.len() as u32));
        group.push(index);
    }
    let owners: Vec<(SymbolId, u128)> = grouped
        .into_iter()
        .map(|(owner, indices)| {
            let mut buffer: Vec<u8> = Vec::with_capacity(indices.len() * 64 + 16);
            buffer.update(b"owner\0");
            for &index in &indices {
                update_row(&mut buffer, &rows[index], None);
            }
            buffer.update(&(indices.len() as u64).to_le_bytes());
            (owner, xxhash_rust::xxh3::xxh3_128(&buffer))
        })
        .collect();
    authored_digest(handles.into_iter(), owners.into_iter())
}
fn identity_of<'a>(
    prefix: impl IntoIterator<Item = &'a Skeleton>,
    authored: u128,
    fields: &[dm_ir::OpaqueFieldBase],
) -> u128 {
    let mut bytes = Xxh3::new();
    bytes.update(IDENTITY_TAG);
    for row in prefix {
        update_row(&mut bytes, row, None);
    }
    bytes.update(b"\0authored");
    bytes.update(&authored.to_le_bytes());
    finish_identity(bytes, fields)
}
#[cfg(test)]
pub(crate) fn retained_declaration_identity(
    prefix: &[Skeleton],
    index: &crate::declaration_contributions::KeyedDeclarations,
    fields: &[dm_ir::OpaqueFieldBase],
) -> u128 {
    identity_of(prefix, indexed_authored_digest(index), fields)
}
pub(crate) fn retained_declaration_identity_view(
    prefix: crate::skeleton_roster::SkeletonView<'_>,
    index: &crate::declaration_contributions::KeyedDeclarations,
    fields: &[dm_ir::OpaqueFieldBase],
) -> u128 {
    identity_of(prefix.iter(), indexed_authored_digest(index), fields)
}
pub(crate) fn retained_projected_identity(
    parents: impl IntoIterator<Item = (SymbolId, Option<SymbolId>)>,
    index: &crate::declaration_contributions::KeyedDeclarations,
    fields: &[dm_ir::OpaqueFieldBase],
) -> u128 {
    let prefix: Vec<Skeleton> = parents
        .into_iter()
        .map(|(path, explicit_parent)| Skeleton::Type { path, explicit_parent })
        .collect();
    identity_of(&prefix, indexed_authored_digest(index), fields)
}
#[cfg(test)]
pub(crate) fn projected_declaration_identity(
    parents: impl IntoIterator<Item = (SymbolId, Option<SymbolId>)>,
    skeletons: &[Skeleton],
    fields: &[dm_ir::OpaqueFieldBase],
) -> u128 {
    let prefix: Vec<Skeleton> = parents
        .into_iter()
        .map(|(path, explicit_parent)| Skeleton::Type { path, explicit_parent })
        .collect();
    identity_of(&prefix, flat_authored_digest(skeletons.into()), fields)
}

pub(crate) fn metadata_fingerprint(metadata: &MemberMetadata) -> u128 {
    let mut bytes = Xxh3::new();
    bytes.update(&[u8::from(metadata.inherited_opaque.is_some())]);
    if let Some(base) = &metadata.inherited_opaque {
        bytes.update(&base.canonical_bytes());
    }
    for symbol in [
        metadata.declared_type,
        metadata.list_element_type,
        metadata.display_name,
    ] {
        bytes.update(&[u8::from(symbol.is_some())]);
        bytes.update(&symbol.map(SymbolId::bits).unwrap_or(0).to_le_bytes());
    }
    bytes.update(&[u8::from(metadata.array.is_some())]);
    if let Some(array) = &metadata.array {
        let data = array.canonical_bytes();
        bytes.update(&(data.len() as u64).to_le_bytes());
        bytes.update(&data);
    }
    bytes.update(&[u8::from(metadata.procedure.is_some())]);
    if let Some(procedure) = &metadata.procedure {
        let value = procedure.canonical_bytes();
        bytes.update(&(value.len() as u64).to_le_bytes());
        bytes.update(&value);
    }
    bytes.update(&[u8::from(metadata.declared_initializer.is_some())]);
    if let Some(initializer) = &metadata.declared_initializer {
        let data = initializer.canonical_bytes();
        bytes.update(&(data.len() as u64).to_le_bytes());
        bytes.update(&data);
    }
    bytes.update(&[u8::from(metadata.initializer.is_some())]);
    if let Some(initializer) = &metadata.initializer {
        let data = initializer.canonical_bytes();
        bytes.update(&(data.len() as u64).to_le_bytes());
        bytes.update(&data);
    }
    bytes.update(&[u8::from(metadata.resolved_constant.is_some())]);
    if let Some(value) = &metadata.resolved_constant {
        let data = value.canonical_bytes();
        bytes.update(&(data.len() as u64).to_le_bytes());
        bytes.update(&data);
    }
    bytes.update(&metadata.flags.to_le_bytes());
    bytes.update(&metadata.canonical);
    bytes.digest128()
}

#[cfg(test)]
mod tests;
