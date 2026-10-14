//! Shared raw-byte memo variant framing.
const ENVELOPE_MAGIC: &[u8; 8] = b"DMCVAR01";
/// Raw byte framing avoids JSON's numeric expansion of nested byte vectors.
pub fn encode_variants(variants: &[Vec<u8>]) -> Result<Vec<u8>, String> {
    let count = u32::try_from(variants.len()).map_err(|_| "cache variant count overflow")?;
    let size = variants
        .iter()
        .try_fold(12usize, |size, value| {
            size.checked_add(8)?.checked_add(value.len())
        })
        .ok_or("cache envelope overflow")?;
    let mut bytes = Vec::with_capacity(size);
    bytes.extend_from_slice(ENVELOPE_MAGIC);
    bytes.extend_from_slice(&count.to_le_bytes());
    for variant in variants {
        bytes.extend_from_slice(&(variant.len() as u64).to_le_bytes());
        bytes.extend_from_slice(variant);
    }
    Ok(bytes)
}
pub fn decode_variants(bytes: &[u8]) -> Result<Vec<&[u8]>, String> {
    if bytes.get(..8) != Some(ENVELOPE_MAGIC.as_slice()) {
        return Err("invalid cache envelope header/size".into());
    }
    let count = u32::from_le_bytes(
        bytes
            .get(8..12)
            .ok_or("truncated cache envelope")?
            .try_into()
            .unwrap(),
    );
    // Each variant needs at least its length prefix. Validate against the actual
    // frame before allocating; population has no arbitrary variant ceiling.
    if count as usize > bytes.len().saturating_sub(12) / 8 {
        return Err("cache variant count exceeds frame".into());
    }
    let mut offset = 12usize;
    let mut variants = Vec::with_capacity(count as usize);
    for _ in 0..count {
        let length_end = offset.checked_add(8).ok_or("cache envelope overflow")?;
        let length = u64::from_le_bytes(
            bytes
                .get(offset..length_end)
                .ok_or("truncated cache length")?
                .try_into()
                .unwrap(),
        );
        offset = length_end;
        let end = offset
            .checked_add(usize::try_from(length).map_err(|_| "cache length overflow")?)
            .ok_or("cache range overflow")?;
        variants.push(bytes.get(offset..end).ok_or("truncated cache payload")?);
        offset = end;
    }
    if offset != bytes.len() {
        return Err("trailing cache envelope bytes".into());
    }
    Ok(variants)
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn binary_envelope_retains_raw_bytes_and_rejects_truncation_lengths_and_trailing_data() {
        let variants = vec![vec![0, 255, 7, 128], vec![3; 1024]];
        let bytes = encode_variants(&variants).unwrap();
        assert_eq!(bytes.len(), 12 + 16 + 1028);
        assert_eq!(
            decode_variants(&bytes).unwrap(),
            variants.iter().map(Vec::as_slice).collect::<Vec<_>>()
        );
        for length in 0..bytes.len() {
            assert!(decode_variants(&bytes[..length]).is_err());
        }
        let mut invalid = bytes.clone();
        invalid[12..20].copy_from_slice(&u64::MAX.to_le_bytes());
        assert!(decode_variants(&invalid).is_err());
        let mut trailing = bytes.clone();
        trailing.push(0);
        assert!(decode_variants(&trailing).is_err());
        let many = vec![Vec::new(); 5];
        let encoded = encode_variants(&many).unwrap();
        assert_eq!(decode_variants(&encoded).unwrap().len(), 5);
        let mut invalid_count = encoded;
        invalid_count[8..12].copy_from_slice(&u32::MAX.to_le_bytes());
        assert!(decode_variants(&invalid_count).is_err());
    }
}
