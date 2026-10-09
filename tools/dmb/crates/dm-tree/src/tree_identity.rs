use super::*;
use xxhash_rust::xxh3::Xxh3;

pub(crate) fn declaration_identity(
    skeletons: &[Skeleton],
    fields: &[dm_ir::OpaqueFieldBase],
) -> u128 {
    let mut bytes = Xxh3::new();
    bytes.update(b"dm-tree-v3\0");
    for skeleton in skeletons {
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
                bytes.update(&metadata_fingerprint(metadata).to_le_bytes());
            }
        }
    }
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
