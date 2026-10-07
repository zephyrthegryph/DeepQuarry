//! Neutral binary DTO framing. Domain callers validate private issuers and semantics.
//! DTOs must use explicit tagged enums/fields, not serde flatten, untagged or
//! conditionally omitted struct fields. No storage or compiler models live here.
use serde::{de::DeserializeOwned, Serialize};
use std::io::{self, Write};
const MAGIC: &[u8; 8] = b"DMWIRE01";
const HEADER: usize = 32;
pub const MAX_BYTES: usize = 32 * 1024 * 1024;
struct Bounded(Vec<u8>);
impl Write for Bounded {
    fn write(&mut self, bytes: &[u8]) -> io::Result<usize> {
        if bytes.len() > MAX_BYTES.saturating_sub(self.0.len()) {
            return Err(io::Error::other("wire payload exceeds bound"));
        }
        self.0.extend_from_slice(bytes);
        Ok(bytes.len())
    }
    fn flush(&mut self) -> io::Result<()> {
        Ok(())
    }
}
/// Measure the exact existing wire encoding without allocating its payload.
/// This does not raise the encoder's admission cap or authorize large records.
pub fn encoded_len<T: Serialize>(schema: u32, value: &T) -> Result<usize, String> {
    struct Counting(usize);
    impl Write for Counting {
        fn write(&mut self, bytes: &[u8]) -> io::Result<usize> {
            self.0 = self
                .0
                .checked_add(bytes.len())
                .ok_or_else(|| io::Error::other("wire length overflow"))?;
            Ok(bytes.len())
        }
        fn flush(&mut self) -> io::Result<()> {
            Ok(())
        }
    }
    let _ = schema; // Schema changes framing contents, not its fixed extent.
    let mut output = Counting(HEADER);
    bincode::serde::encode_into_std_write(value, &mut output, bincode::config::standard())
        .map_err(|error| error.to_string())?;
    Ok(output.0)
}
/// Encode standard little-endian varint serde data within the fixed payload cap.
pub fn encode<T: Serialize>(schema: u32, value: &T) -> Result<Vec<u8>, String> {
    let mut payload = Bounded(Vec::new());
    bincode::serde::encode_into_std_write(value, &mut payload, bincode::config::standard())
        .map_err(|error| error.to_string())?;
    let mut result = Vec::with_capacity(HEADER + payload.0.len());
    result.extend_from_slice(MAGIC);
    result.extend_from_slice(&schema.to_le_bytes());
    result.extend_from_slice(&(payload.0.len() as u32).to_le_bytes());
    result.extend_from_slice(&xxhash_rust::xxh3::xxh3_128(&payload.0).to_le_bytes());
    result.extend_from_slice(&payload.0);
    Ok(result)
}
/// Reject wrong schema, checksum, truncation, trailing bytes and oversize frames
/// before decoding. Bincode's independent byte-read budget is also enforced.
/// Domain DTOs must additionally bound recursive depth and decoded collection
/// counts; this generic byte codec does not claim a total heap-allocation cap.
pub fn decode<T: DeserializeOwned>(
    schema: u32,
    bytes: &[u8],
    max_bytes: usize,
) -> Result<T, String> {
    if bytes.len() < HEADER || bytes.get(..8) != Some(MAGIC.as_slice()) {
        return Err("invalid wire magic/header".into());
    }
    if u32::from_le_bytes(bytes[8..12].try_into().unwrap()) != schema {
        return Err("wire schema differs".into());
    }
    let length = u32::from_le_bytes(bytes[12..16].try_into().unwrap()) as usize;
    if length > MAX_BYTES || length > max_bytes || bytes.len() != HEADER + length {
        return Err("wire payload extent exceeds bound or differs".into());
    }
    let payload = &bytes[HEADER..];
    if u128::from_le_bytes(bytes[16..32].try_into().unwrap())
        != xxhash_rust::xxh3::xxh3_128(payload)
    {
        return Err("wire checksum differs".into());
    }
    let (value, consumed) = bincode::serde::decode_from_slice(
        payload,
        bincode::config::standard().with_limit::<{ MAX_BYTES }>(),
    )
    .map_err(|error| error.to_string())?;
    if consumed != payload.len() {
        return Err("wire trailing payload bytes".into());
    }
    Ok(value)
}
#[cfg(test)]
mod tests {
    use super::*;
    #[derive(Debug, PartialEq, serde::Serialize, serde::Deserialize)]
    struct Dto {
        bytes: Vec<u8>,
        number: u128,
        kind: Option<(u32, String)>,
    }
    #[test]
    fn compact_roundtrip_and_integrity_limits() {
        let dto = Dto {
            bytes: vec![255; 4096],
            number: u128::MAX,
            kind: Some((7, "exact".into())),
        };
        let bytes = encode(91, &dto).unwrap();
        assert_eq!(encoded_len(91, &dto).unwrap(), bytes.len());
        assert_eq!(encoded_len(92, &dto).unwrap(), bytes.len());
        assert!(bytes.len() < 4200);
        assert_eq!(decode::<Dto>(91, &bytes, MAX_BYTES).unwrap(), dto);
        assert!(decode::<Dto>(92, &bytes, MAX_BYTES).is_err());
        assert!(decode::<Dto>(91, &bytes, 10).is_err());
        for end in [0, 8, 31, bytes.len() - 1] {
            assert!(decode::<Dto>(91, &bytes[..end], MAX_BYTES).is_err());
        }
        let mut bad = bytes.clone();
        *bad.last_mut().unwrap() ^= 1;
        assert!(decode::<Dto>(91, &bad, MAX_BYTES).is_err());
        let mut trailing = bytes;
        trailing.push(0);
        assert!(decode::<Dto>(91, &trailing, MAX_BYTES).is_err());
    }
    #[test]
    fn encoded_payload_cap_and_decode_claim_are_bounded() {
        let oversized = vec![0u8; MAX_BYTES + 1];
        assert!(encoded_len(1, &oversized).unwrap() > MAX_BYTES + HEADER);
        assert!(encode(1, &oversized).is_err());
        let mut bytes = encode(1, &1u32).unwrap();
        bytes[12..16].copy_from_slice(&u32::MAX.to_le_bytes());
        assert!(decode::<u32>(1, &bytes, usize::MAX).is_err());
    }
}
