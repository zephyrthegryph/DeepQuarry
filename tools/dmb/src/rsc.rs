//! Lossless reader and writer for the outer BYOND .rsc entry stream.
//!
//! The known wrapper (1) carries a named resource. Other wrappers are retained
//! as opaque payloads; interpreting them as named resources would corrupt output.
use std::io::{self, Read, Write};

// The outer format permits u32 lengths, but decoding stores each payload in a
// Vec. Reject implausibly large entries before reading or allocating them.
const MAX_ENTRY_SIZE: usize = 512 * 1024 * 1024;
const NAMED_HEADER_SIZE: usize = 17;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum ResourceKind {
    /// Text-like resources, including DMF skins and ordinary .txt files.
    Text,
    Midi,
    Sound,
    Dmi,
    Bmp,
    Png,
    Zip,
    Rsc,
    Jpeg,
    Gif,
    Font,
    Other(u8),
}

impl ResourceKind {
    pub fn from_byte(value: u8) -> Self {
        match value {
            0 => Self::Text,
            1 => Self::Midi,
            2 => Self::Sound,
            3 => Self::Dmi,
            5 => Self::Bmp,
            6 => Self::Png,
            9 => Self::Zip,
            10 => Self::Rsc,
            11 => Self::Jpeg,
            13 => Self::Gif,
            14 => Self::Font,
            other => Self::Other(other),
        }
    }
    pub fn as_byte(self) -> u8 {
        match self {
            Self::Text => 0,
            Self::Midi => 1,
            Self::Sound => 2,
            Self::Dmi => 3,
            Self::Bmp => 5,
            Self::Png => 6,
            Self::Zip => 9,
            Self::Rsc => 10,
            Self::Jpeg => 11,
            Self::Gif => 13,
            Self::Font => 14,
            Self::Other(other) => other,
        }
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NamedResource {
    pub kind: u8,
    pub id: u32,
    /// Timestamp of this cache record (Unix seconds).
    pub timestamp: u32,
    /// Timestamp of the imported source file (Unix seconds).
    pub source_timestamp: u32,
    /// Current asset byte count. RAD entries can retain unused trailing bytes.
    /// The resource ID hashes only this prefix.
    pub declared_size: u32,
    /// Raw filename bytes. RSC filenames are not guaranteed to be UTF-8.
    pub name: Vec<u8>,
    pub data: Vec<u8>,
}

impl NamedResource {
    pub fn resource_kind(&self) -> ResourceKind {
        ResourceKind::from_byte(self.kind)
    }
    /// Current asset bytes, excluding unused archive capacity.
    pub fn asset_bytes(&self) -> io::Result<&[u8]> {
        self.data.get(..self.declared_size as usize).ok_or_else(|| {
            io::Error::new(
                io::ErrorKind::InvalidData,
                "RSC declared size exceeds entry data",
            )
        })
    }

    /// Unused bytes retained after a resource is replaced in-place.
    pub fn trailing_bytes(&self) -> io::Result<&[u8]> {
        self.data.get(self.declared_size as usize..).ok_or_else(|| {
            io::Error::new(
                io::ErrorKind::InvalidData,
                "RSC declared size exceeds entry data",
            )
        })
    }

    /// Calculate the content-derived resource ID used by Dream Maker.
    pub fn content_id(&self) -> io::Result<u32> {
        Ok(crate::hash::nqcrc(u32::MAX, self.asset_bytes()?))
    }

    /// Replace the asset and discard any unused trailing archive bytes.
    pub fn set_asset_bytes(&mut self, data: Vec<u8>) -> io::Result<()> {
        let declared_size = u32::try_from(data.len()).map_err(|_| {
            io::Error::new(io::ErrorKind::InvalidInput, "RSC asset exceeds u32 size")
        })?;
        self.id = crate::hash::nqcrc(u32::MAX, &data);
        self.declared_size = declared_size;
        self.data = data;
        Ok(())
    }

    /// Build a resource with a content-derived ID and matching declared size.
    pub fn from_data(
        kind: u8,
        name: Vec<u8>,
        data: Vec<u8>,
        timestamp: u32,
        source_timestamp: u32,
    ) -> io::Result<Self> {
        let declared_size = u32::try_from(data.len()).map_err(|_| {
            io::Error::new(io::ErrorKind::InvalidInput, "RSC asset exceeds u32 size")
        })?;
        let id = crate::hash::nqcrc(u32::MAX, &data);
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
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum Entry {
    Named(NamedResource),
    Opaque { wrapper: u8, payload: Vec<u8> },
}

/// Recoverable metadata in a validity-zero slot. This remains deleted archive
/// capacity, not a live resource; validity and original bytes are unchanged.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct DeletedNamedResource<'a> {
    pub kind: u8,
    pub id: u32,
    pub timestamp: u32,
    pub source_timestamp: u32,
    pub name: &'a [u8],
    pub asset: &'a [u8],
    pub trailing: &'a [u8],
}
impl Entry {
    /// Inspect former named metadata only when its bounded asset prefix still
    /// matches the saved content ID. Arbitrary free-block remnants return None.
    pub fn deleted_named_resource(&self) -> Option<DeletedNamedResource<'_>> {
        let Self::Opaque {
            wrapper: 0,
            payload,
        } = self
        else {
            return None;
        };
        if payload.len() < NAMED_HEADER_SIZE + 2 {
            return None;
        }
        let end = payload[NAMED_HEADER_SIZE..]
            .iter()
            .position(|&byte| byte == 0)?
            + NAMED_HEADER_SIZE;
        if end == NAMED_HEADER_SIZE {
            return None;
        }
        let word = |at| u32::from_le_bytes(payload[at..at + 4].try_into().unwrap());
        let size = word(13) as usize;
        let start = end + 1;
        let asset = payload.get(start..start.checked_add(size)?)?;
        let id = word(1);
        if crate::hash::nqcrc(u32::MAX, asset) != id {
            return None;
        }
        Some(DeletedNamedResource {
            kind: payload[0],
            id,
            timestamp: word(5),
            source_timestamp: word(9),
            name: &payload[NAMED_HEADER_SIZE..end],
            asset,
            trailing: &payload[start + size..],
        })
    }
    pub fn wrapper(&self) -> u8 {
        match self {
            Self::Named(_) => 1,
            Self::Opaque { wrapper, .. } => *wrapper,
        }
    }
}

/// Reads one entry, or returns None only at a clean end of stream.
pub fn read_entry(reader: &mut impl Read) -> io::Result<Option<Entry>> {
    let mut first = [0u8; 1];
    if reader.read(&mut first)? == 0 {
        return Ok(None);
    }
    let mut length_bytes = [0u8; 4];
    length_bytes[0] = first[0];
    reader.read_exact(&mut length_bytes[1..])?;
    let length = u32::from_le_bytes(length_bytes) as usize;
    if length > MAX_ENTRY_SIZE {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            "RSC entry exceeds decode limit",
        ));
    }
    let mut wrapper = [0u8; 1];
    reader.read_exact(&mut wrapper)?;
    let mut payload = Vec::with_capacity(length.min(8192));
    let mut bounded = reader.take(length as u64);
    bounded.read_to_end(&mut payload)?;
    if payload.len() != length {
        return Err(io::Error::new(
            io::ErrorKind::UnexpectedEof,
            "truncated RSC entry",
        ));
    }
    if wrapper[0] != 1 {
        return Ok(Some(Entry::Opaque {
            wrapper: wrapper[0],
            payload,
        }));
    }
    if payload.len() < NAMED_HEADER_SIZE + 1 {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            "named RSC entry is shorter than its header",
        ));
    }
    let name_end = payload[NAMED_HEADER_SIZE..]
        .iter()
        .position(|&byte| byte == 0)
        .map(|relative| NAMED_HEADER_SIZE + relative)
        .ok_or_else(|| {
            io::Error::new(io::ErrorKind::InvalidData, "RSC name has no NUL terminator")
        })?;
    Ok(Some(Entry::Named(NamedResource {
        kind: payload[0],
        id: u32::from_le_bytes(payload[1..5].try_into().unwrap()),
        timestamp: u32::from_le_bytes(payload[5..9].try_into().unwrap()),
        source_timestamp: u32::from_le_bytes(payload[9..13].try_into().unwrap()),
        declared_size: u32::from_le_bytes(payload[13..17].try_into().unwrap()),
        name: payload[NAMED_HEADER_SIZE..name_end].to_vec(),
        data: payload[name_end + 1..].to_vec(),
    })))
}

/// Serialize borrowed resources into one exactly sized archive without cloning payloads.
pub fn named_archive_bytes(resources: &[&NamedResource]) -> io::Result<Vec<u8>> {
    let mut size = 0usize;
    for resource in resources {
        size = size.checked_add(named_entry_size(resource)?.checked_add(5)
            .ok_or_else(|| io::Error::new(io::ErrorKind::InvalidInput,"RSC archive too large"))?)
            .ok_or_else(|| io::Error::new(io::ErrorKind::InvalidInput,"RSC archive too large"))?;
    }
    let mut output = Vec::new();
    output.try_reserve_exact(size).map_err(|error| io::Error::new(io::ErrorKind::OutOfMemory,error))?;
    for resource in resources { write_named(&mut output,resource)?; }
    Ok(output)
}

fn named_entry_size(resource: &NamedResource) -> io::Result<usize> {
    if resource.name.contains(&0) { return Err(io::Error::new(io::ErrorKind::InvalidInput,"RSC name contains NUL")); }
    let size = NAMED_HEADER_SIZE.checked_add(resource.name.len()).and_then(|size| size.checked_add(1))
        .and_then(|size| size.checked_add(resource.data.len()))
        .ok_or_else(|| io::Error::new(io::ErrorKind::InvalidInput,"RSC entry is too large"))?;
    if size > MAX_ENTRY_SIZE { return Err(io::Error::new(io::ErrorKind::InvalidInput,"RSC entry is too large")); }
    Ok(size)
}

/// Write a named resource by reference, with identical framing to `write_entry`.
pub fn write_named(writer: &mut impl Write, resource: &NamedResource) -> io::Result<()> {
    writer.write_all(&(named_entry_size(resource)? as u32).to_le_bytes())?;
    writer.write_all(&[1,resource.kind])?;
    writer.write_all(&resource.id.to_le_bytes())?;
    writer.write_all(&resource.timestamp.to_le_bytes())?;
    writer.write_all(&resource.source_timestamp.to_le_bytes())?;
    writer.write_all(&resource.declared_size.to_le_bytes())?;
    writer.write_all(&resource.name)?;
    writer.write_all(&[0])?;
    writer.write_all(&resource.data)
}

pub fn write_entry(writer: &mut impl Write, entry: &Entry) -> io::Result<()> {
    match entry {
        Entry::Named(resource) => write_named(writer,resource),
        Entry::Opaque { wrapper,payload } => {
            if payload.len() > MAX_ENTRY_SIZE { return Err(io::Error::new(io::ErrorKind::InvalidInput,"RSC entry is too large")); }
            writer.write_all(&(payload.len() as u32).to_le_bytes())?;
            writer.write_all(&[*wrapper])?;
            writer.write_all(payload)
        }
    }
}

pub fn read_all(reader: &mut impl Read) -> io::Result<Vec<Entry>> {
    let mut entries = Vec::new();
    while let Some(entry) = read_entry(reader)? {
        entries.push(entry);
    }
    Ok(entries)
}

pub fn write_all(writer: &mut impl Write, entries: &[Entry]) -> io::Result<()> {
    for entry in entries {
        write_entry(writer, entry)?;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    #[test]
    fn native_incremental_archive_splits_deleted_capacity_into_asset_remnants() {
        let load = |mut bytes: &[u8]| read_all(&mut bytes).unwrap();
        let initial_bytes = include_bytes!("../fixtures/rsc_incremental/initial.rsc");
        let initial = load(initial_bytes);
        let grown = load(include_bytes!("../fixtures/rsc_incremental/grown.rsc"));
        let removed = load(include_bytes!("../fixtures/rsc_incremental/removed.rsc"));
        let shrunk = load(include_bytes!("../fixtures/rsc_incremental/shrunk.rsc"));
        let reused_bytes = include_bytes!("../fixtures/rsc_incremental/reused.rsc");
        let reused = load(reused_bytes);
        assert_eq!(initial.len(), 2);
        assert_eq!(grown.len(), 3);
        assert_eq!(grown[0].deleted_named_resource().unwrap().name, b"a.txt");
        assert_eq!(grown, removed); // Removing a source reference does not purge cached entries.
        let Entry::Named(small) = &shrunk[2] else {
            panic!("live a.txt");
        };
        assert_eq!(small.asset_bytes().unwrap(), vec![b'D'; 40]);
        assert_eq!(small.trailing_bytes().unwrap(), vec![b'C'; 460]);
        assert_eq!(reused.len(), 4);
        let Entry::Opaque {
            wrapper: 0,
            payload,
        } = &reused[1]
        else {
            panic!("split free capacity");
        };
        assert_eq!(payload.len(), 65);
        assert_eq!(payload.as_slice(), &initial_bytes[83..148]);
        assert!(reused[1].deleted_named_resource().is_none());
        let mut roundtrip = Vec::new();
        write_all(&mut roundtrip, &reused).unwrap();
        assert_eq!(roundtrip.as_slice(), reused_bytes);
    }
    #[test]
    fn deleted_slots_recover_metadata_without_becoming_live_resources() {
        let original = include_bytes!("../fixtures/deleted_slots.rsc");
        let entries = read_all(&mut original.as_slice()).unwrap();
        assert_eq!(entries.len(), 2);
        assert!(entries[0].deleted_named_resource().is_none());
        let former = entries[1].deleted_named_resource().unwrap();
        assert_eq!(former.name, b"icons/obj/closets/decals/closet.dmi");
        assert_eq!(former.kind, 3);
        assert_eq!(former.asset.len(), 3084);
        assert_eq!(crate::hash::nqcrc(u32::MAX, former.asset), former.id);
        assert!(former.trailing.is_empty());
        assert!(entries
            .iter()
            .all(|entry| matches!(entry, Entry::Opaque { wrapper: 0, .. })));
        let mut encoded = Vec::new();
        write_all(&mut encoded, &entries).unwrap();
        assert_eq!(encoded.as_slice(), original);
        let mut corrupted = entries[1].clone();
        if let Entry::Opaque { payload, .. } = &mut corrupted {
            *payload.last_mut().unwrap() ^= 1;
        }
        assert!(corrupted.deleted_named_resource().is_none());
        for len in 0..18 {
            assert!(Entry::Opaque {
                wrapper: 0,
                payload: vec![0; len]
            }
            .deleted_named_resource()
            .is_none());
        }
    }
    use super::*;
    #[test]
    fn observed_resource_kind_codes_round_trip() {
        for code in [0, 1, 2, 3, 5, 6, 9, 10, 11, 13, 14, 255] {
            assert_eq!(ResourceKind::from_byte(code).as_byte(), code);
        }
    }

    #[test]
    fn named_and_opaque_round_trip() {
        let entries = vec![
            Entry::Named(NamedResource {
                kind: 3,
                id: 0x1234_5678,
                timestamp: 0x0403_0201,
                source_timestamp: 0x0807_0605,
                declared_size: 17,
                name: b"icons/example.dmi".to_vec(),
                data: vec![10, 20, 30],
            }),
            Entry::Opaque {
                wrapper: 0,
                payload: vec![0, 1, 0xff],
            },
        ];
        let mut bytes = Vec::new();
        write_all(&mut bytes, &entries).unwrap();
        assert_eq!(read_all(&mut bytes.as_slice()).unwrap(), entries);
    }

    #[test]
    fn truncated_entry_is_an_error() {
        let bytes = [4, 0, 0, 0, 0, 1];
        assert_eq!(
            read_entry(&mut bytes.as_slice()).unwrap_err().kind(),
            io::ErrorKind::UnexpectedEof
        );
    }

    #[test]
    fn oversized_entry_is_rejected_before_payload_read() {
        let length = (MAX_ENTRY_SIZE as u32 + 1).to_le_bytes();
        assert_eq!(
            read_entry(&mut length.as_slice()).unwrap_err().kind(),
            io::ErrorKind::InvalidData
        );
    }

    #[test]
    fn invalid_name_does_not_write_a_partial_entry() {
        let entry = Entry::Named(NamedResource {
            kind: 6,
            id: 1,
            timestamp: 0,
            source_timestamp: 0,
            declared_size: 0,
            name: b"bad\0name".to_vec(),
            data: vec![],
        });
        let mut bytes = Vec::new();
        assert_eq!(
            write_entry(&mut bytes, &entry).unwrap_err().kind(),
            io::ErrorKind::InvalidInput
        );
        assert!(bytes.is_empty());
    }

    #[test]
    fn generated_resource_id_tracks_content() {
        let resource =
            NamedResource::from_data(6, b"icon.png".to_vec(), b"a".to_vec(), 0, 0).unwrap();
        assert_eq!(resource.id, resource.content_id().unwrap());
        assert_eq!(resource.declared_size, 1);
    }

    #[test]
    fn unused_trailing_bytes_are_excluded_from_id() {
        let mut resource =
            NamedResource::from_data(3, b"icon.dmi".to_vec(), b"abc".to_vec(), 0, 0).unwrap();
        resource.data.extend_from_slice(b"stale bytes");
        assert_eq!(resource.content_id().unwrap(), resource.id);
        assert_eq!(resource.asset_bytes().unwrap(), b"abc");
        assert_eq!(resource.trailing_bytes().unwrap(), b"stale bytes");
        resource.set_asset_bytes(b"new".to_vec()).unwrap();
        assert_eq!(resource.asset_bytes().unwrap(), b"new");
        assert!(resource.trailing_bytes().unwrap().is_empty());
        assert_eq!(resource.content_id().unwrap(), resource.id);
    }
}
