//! Neutral binary DTO framing. Domain callers validate private issuers and semantics.
//! DTOs must use explicit tagged enums/fields, not serde flatten, untagged or
//! conditionally omitted struct fields. No storage or compiler models live here.
use serde::{de::DeserializeOwned, Deserialize, Serialize};
use std::io::{self, Write};
const MAGIC: &[u8; 8] = b"DMWIRE01";
const HEADER: usize = 32;
// The fixed framing represents its payload length as u32, not a cache budget.
pub const MAX_BYTES: usize = u32::MAX as usize;
struct Bounded(Vec<u8>, usize);
impl Write for Bounded {
    fn write(&mut self, bytes: &[u8]) -> io::Result<usize> {
        if bytes.len() > self.1.saturating_sub(self.0.len()) {
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
    encode_bounded(schema, value, MAX_BYTES + HEADER)
}
/// Apply a smaller complete-frame bound without changing the shared wire format.
/// The writer enforces the bound while encoding, before extending its buffer.
pub fn encode_bounded<T: Serialize>(
    schema: u32,
    value: &T,
    frame_bytes: usize,
) -> Result<Vec<u8>, String> {
    let payload_limit = frame_bytes
        .checked_sub(HEADER)
        .ok_or("wire frame bound is smaller than its header")?
        .min(MAX_BYTES);
    let mut payload = Bounded(vec![0; HEADER], HEADER + payload_limit);
    bincode::serde::encode_into_std_write(value, &mut payload, bincode::config::standard())
        .map_err(|error| error.to_string())?;
    let length = payload.0.len() - HEADER;
    let checksum = xxhash_rust::xxh3::xxh3_128(&payload.0[HEADER..]);
    payload.0[..8].copy_from_slice(MAGIC);
    payload.0[8..12].copy_from_slice(&schema.to_le_bytes());
    payload.0[12..16].copy_from_slice(&(length as u32).to_le_bytes());
    payload.0[16..32].copy_from_slice(&checksum.to_le_bytes());
    Ok(payload.0)
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
    let payload = checked_payload(schema, bytes, max_bytes)?;
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
/// Decode borrowed strings/bytes directly from an immutable validated frame.
/// Sequence containers and domain types may still require owned allocations.
pub fn decode_borrowed<'a, T: Deserialize<'a>>(
    schema: u32,
    bytes: &'a [u8],
    max_bytes: usize,
) -> Result<T, String> {
    let payload = checked_payload(schema, bytes, max_bytes)?;
    let (value, consumed) = bincode::serde::borrow_decode_from_slice(
        payload,
        bincode::config::standard().with_limit::<{ MAX_BYTES }>(),
    )
    .map_err(|error| error.to_string())?;
    if consumed != payload.len() {
        return Err("wire trailing payload bytes".into());
    }
    Ok(value)
}
fn checked_payload(schema: u32, bytes: &[u8], max_bytes: usize) -> Result<&[u8], String> {
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
    Ok(payload)
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
        let oversized = vec![0u8; 1025];
        assert!(encoded_len(1, &oversized).unwrap() > 1024 + HEADER);
        assert!(encode_bounded(1, &oversized, 1024 + HEADER).is_err());
        let mut bytes = encode(1, &1u32).unwrap();
        bytes[12..16].copy_from_slice(&u32::MAX.to_le_bytes());
        assert!(decode::<u32>(1, &bytes, usize::MAX).is_err());
    }
    #[test]
    fn bounded_wire_frames_preserve_bytes_and_enforce_exact_limit() {
        let value = vec![173u8; 1024];
        let bytes = encode(17, &value).unwrap();
        assert_eq!(encode_bounded(17, &value, bytes.len()).unwrap(), bytes);
        assert!(encode_bounded(17, &value, bytes.len() - 1).is_err());
        assert!(encode_bounded(17, &value, HEADER - 1).is_err());
        assert_eq!(decode::<Vec<u8>>(17, &bytes, MAX_BYTES).unwrap(), value);
    }
    #[test]
    fn borrowed_decoder_shares_framing_checks_and_source_storage() {
        #[derive(Deserialize)]
        struct Borrowed<'a> {
            #[serde(borrow)]
            bytes: std::borrow::Cow<'a, [u8]>,
            #[serde(borrow)]
            text: std::borrow::Cow<'a, str>,
        }
        let bytes = encode(19, &(vec![0u8, 128, 255], "Ω exact".to_owned())).unwrap();
        let value: Borrowed = decode_borrowed(19, &bytes, bytes.len()).unwrap();
        assert!(matches!(value.bytes, std::borrow::Cow::Borrowed(_)));
        assert!(matches!(value.text, std::borrow::Cow::Borrowed(_)));
        assert_eq!(value.bytes.as_ref(), [0, 128, 255]);
        assert_eq!(value.text, "Ω exact");
        assert!(decode_borrowed::<Borrowed>(20, &bytes, bytes.len()).is_err());
        assert!(decode_borrowed::<Borrowed>(19, &bytes, 0).is_err());
        for length in [0, 8, 31, bytes.len() - 1] {
            assert!(decode_borrowed::<Borrowed>(19, &bytes[..length], bytes.len()).is_err());
        }
        let mut corrupt = bytes.clone();
        *corrupt.last_mut().unwrap() ^= 1;
        assert!(decode_borrowed::<Borrowed>(19, &corrupt, corrupt.len()).is_err());
        let mut trailing = bytes;
        trailing.push(0);
        assert!(decode_borrowed::<Borrowed>(19, &trailing, trailing.len()).is_err());
    }
}
