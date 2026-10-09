//! Producer payload ownership; cloning aliases never copies asset bytes.
use byond_dmb::rsc::{NamedResource, NamedResourceView};
use std::{io, sync::Arc};
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NamedResourceInput {
    pub kind: u8,
    pub id: u32,
    pub timestamp: u32,
    pub source_timestamp: u32,
    pub declared_size: u32,
    pub name: Vec<u8>,
    data: Arc<[u8]>,
}
impl NamedResourceInput {
    pub fn from_shared_data(
        kind: u8,
        name: Vec<u8>,
        data: Arc<[u8]>,
        timestamp: u32,
        source_timestamp: u32,
    ) -> io::Result<Self> {
        let declared_size = u32::try_from(data.len()).map_err(|_| {
            io::Error::new(io::ErrorKind::InvalidInput, "RSC asset exceeds u32 size")
        })?;
        let id = byond_dmb::hash::nqcrc(u32::MAX, &data);
        Ok(Self {
            kind,
            id,
            timestamp,
            source_timestamp,
            declared_size,
            name,
            data,
        })
    }
    pub fn asset_bytes(&self) -> io::Result<&[u8]> {
        self.data.get(..self.declared_size as usize).ok_or_else(|| {
            io::Error::new(
                io::ErrorKind::InvalidData,
                "RSC declared size exceeds entry data",
            )
        })
    }
    pub fn content_id(&self) -> io::Result<u32> {
        Ok(byond_dmb::hash::nqcrc(u32::MAX, self.asset_bytes()?))
    }
    pub fn shared_data(&self) -> &Arc<[u8]> {
        &self.data
    }
    pub fn as_view(&self) -> NamedResourceView<'_> {
        NamedResourceView {
            kind: self.kind,
            id: self.id,
            timestamp: self.timestamp,
            source_timestamp: self.source_timestamp,
            declared_size: self.declared_size,
            name: &self.name,
            data: &self.data,
        }
    }
    /// Explicit compatibility conversion for mutable archive editing.
    pub fn to_owned_named(&self) -> NamedResource {
        NamedResource {
            kind: self.kind,
            id: self.id,
            timestamp: self.timestamp,
            source_timestamp: self.source_timestamp,
            declared_size: self.declared_size,
            name: self.name.clone(),
            data: self.data.to_vec(),
        }
    }
}
impl From<NamedResource> for NamedResourceInput {
    fn from(value: NamedResource) -> Self {
        Self {
            kind: value.kind,
            id: value.id,
            timestamp: value.timestamp,
            source_timestamp: value.source_timestamp,
            declared_size: value.declared_size,
            name: value.name,
            data: value.data.into(),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn shared_payload_and_alias_clones_keep_original_allocation_and_wire_bytes() {
        let source: Arc<[u8]> = Arc::from(&b"source payload"[..]);
        let input =
            NamedResourceInput::from_shared_data(6, b"a.png".to_vec(), Arc::clone(&source), 17, 23)
                .unwrap();
        let alias = input.clone();
        assert!(Arc::ptr_eq(&source, input.shared_data()));
        assert!(Arc::ptr_eq(&source, alias.shared_data()));
        let old = input.to_owned_named();
        let borrowed =
            byond_dmb::rsc::named_views_encoded(&[input.as_view(), alias.as_view()]).unwrap();
        let legacy = byond_dmb::rsc::named_archive_encoded(&[&old, &old]).unwrap();
        let mut exact = Vec::new();
        for _ in 0..2 {
            exact.extend_from_slice(
                &(17_u32 + input.name.len() as u32 + 1 + source.len() as u32).to_le_bytes(),
            );
            exact.extend_from_slice(&[1, 6]);
            for word in [input.id, 17, 23, source.len() as u32] {
                exact.extend_from_slice(&word.to_le_bytes());
            }
            exact.extend_from_slice(&input.name);
            exact.push(0);
            exact.extend_from_slice(&source);
        }
        assert_eq!(borrowed.bytes(), exact);
        assert_eq!(borrowed.bytes(), legacy.bytes());
        assert_eq!(borrowed.content_hash(), legacy.content_hash());
        assert!(Arc::ptr_eq(&source, input.shared_data()));
    }
}
