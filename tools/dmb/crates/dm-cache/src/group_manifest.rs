//! Atomic neutral compaction membership. Leaves never independently supersede.
use crate::CacheError;
use std::collections::BTreeSet;
const MAGIC: &[u8; 8] = b"DMCGRP01";
const HEADER: usize = 24;
const CHECKSUM: usize = 16;
pub(super) const MAX_GROUP_BYTES: usize = 64 * 1024 * 1024;
#[derive(Clone, Debug)]
pub(super) struct GroupManifest {
    pub id: u128,
    pub members: Vec<u128>,
    pub supersedes_segments: Vec<u128>,
    pub supersedes_groups: Vec<u128>,
}
impl GroupManifest {
    pub fn encode(
        members: &[u128],
        segments: &[u128],
        groups: &[u128],
    ) -> Result<(Self, Vec<u8>), CacheError> {
        check_order(members)?;
        check_order(segments)?;
        check_order(groups)?;
        if members.is_empty() {
            return Err(invalid("compaction group has no leaves"));
        }
        if members.iter().any(|id| segments.binary_search(id).is_ok()) {
            return Err(invalid("compaction group supersedes a member"));
        }
        let count = members
            .len()
            .checked_add(segments.len())
            .and_then(|n| n.checked_add(groups.len()))
            .ok_or_else(|| invalid("group count overflow"))?;
        let length = count
            .checked_mul(16)
            .and_then(|n| n.checked_add(HEADER + CHECKSUM))
            .ok_or_else(|| invalid("group extent overflow"))?;
        if length > MAX_GROUP_BYTES {
            return Err(invalid("group metadata exceeds bound"));
        }
        let mut bytes = Vec::with_capacity(length);
        bytes.extend_from_slice(MAGIC);
        bytes.extend_from_slice(&1u32.to_le_bytes());
        for ids in [members, segments, groups] {
            let count = u32::try_from(ids.len()).map_err(|_| invalid("group count overflow"))?;
            bytes.extend_from_slice(&count.to_le_bytes());
        }
        for id in members.iter().chain(segments).chain(groups) {
            bytes.extend_from_slice(&id.to_le_bytes());
        }
        let id = xxhash_rust::xxh3::xxh3_128(&bytes);
        if groups.binary_search(&id).is_ok() {
            return Err(invalid("group supersedes itself"));
        }
        bytes.extend_from_slice(&id.to_le_bytes());
        Ok((
            Self {
                id,
                members: members.to_vec(),
                supersedes_segments: segments.to_vec(),
                supersedes_groups: groups.to_vec(),
            },
            bytes,
        ))
    }
    pub fn decode(bytes: &[u8]) -> Result<Self, CacheError> {
        if bytes.len() < HEADER + CHECKSUM
            || bytes.len() > MAX_GROUP_BYTES
            || bytes.get(..8) != Some(MAGIC.as_slice())
        {
            return Err(invalid("invalid group header/extent"));
        }
        if u32::from_le_bytes(bytes[8..12].try_into().unwrap()) != 1 {
            return Err(invalid("unsupported group version"));
        }
        let counts = [12, 16, 20]
            .map(|at| u32::from_le_bytes(bytes[at..at + 4].try_into().unwrap()) as usize);
        let count = counts
            .iter()
            .try_fold(0usize, |n, c| n.checked_add(*c))
            .ok_or_else(|| invalid("group count overflow"))?;
        if count
            .checked_mul(16)
            .and_then(|n| n.checked_add(HEADER + CHECKSUM))
            != Some(bytes.len())
        {
            return Err(invalid("group count/extent differs"));
        }
        let end = bytes.len() - CHECKSUM;
        let id = u128::from_le_bytes(bytes[end..].try_into().unwrap());
        if xxhash_rust::xxh3::xxh3_128(&bytes[..end]) != id {
            return Err(invalid("group checksum differs"));
        }
        let mut offset = HEADER;
        let mut read = |count| {
            let result = bytes[offset..offset + count * 16]
                .chunks_exact(16)
                .map(|value| u128::from_le_bytes(value.try_into().unwrap()))
                .collect::<Vec<_>>();
            offset += count * 16;
            result
        };
        let members = read(counts[0]);
        let supersedes_segments = read(counts[1]);
        let supersedes_groups = read(counts[2]);
        for ids in [&members, &supersedes_segments, &supersedes_groups] {
            check_order(ids)?;
        }
        if members.is_empty()
            || supersedes_groups.binary_search(&id).is_ok()
            || members
                .iter()
                .any(|member| supersedes_segments.binary_search(member).is_ok())
        {
            return Err(invalid("invalid group membership"));
        }
        Ok(Self {
            id,
            members,
            supersedes_segments,
            supersedes_groups,
        })
    }
    pub fn complete(&self, healthy_segments: &BTreeSet<u128>) -> bool {
        self.members.iter().all(|id| healthy_segments.contains(id))
    }
}
fn check_order(ids: &[u128]) -> Result<(), CacheError> {
    if ids.windows(2).any(|pair| pair[0] >= pair[1]) {
        return Err(invalid("group IDs are not unique and ordered"));
    }
    Ok(())
}
fn invalid(reason: &str) -> CacheError {
    CacheError::Invalid(reason.into())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn exact_neutral_marker_bytes_and_extent_are_authenticated() {
        let (group, bytes) = GroupManifest::encode(&[11, 12], &[3, 4], &[2]).unwrap();
        let mut expected = b"DMCGRP01".to_vec();
        for value in [1u32, 2, 2, 1] {
            expected.extend_from_slice(&value.to_le_bytes());
        }
        for value in [11u128, 12, 3, 4, 2] {
            expected.extend_from_slice(&value.to_le_bytes());
        }
        expected.extend_from_slice(&xxhash_rust::xxh3::xxh3_128(&expected).to_le_bytes());
        assert_eq!(bytes, expected);
        let decoded = GroupManifest::decode(&bytes).unwrap();
        assert_eq!(decoded.id, group.id);
        assert_eq!(decoded.members, [11, 12]);
        for end in 0..bytes.len() {
            assert!(GroupManifest::decode(&bytes[..end]).is_err());
        }
        let mut corrupt = bytes.clone();
        corrupt[24] ^= 1;
        assert!(GroupManifest::decode(&corrupt).is_err());
        let mut trailing = bytes;
        trailing.push(0);
        assert!(GroupManifest::decode(&trailing).is_err());
        assert!(GroupManifest::encode(&[1, 1], &[], &[]).is_err());
        assert!(GroupManifest::encode(&[1], &[1], &[]).is_err());
        assert!(GroupManifest::encode(&[], &[], &[]).is_err());
    }
}
