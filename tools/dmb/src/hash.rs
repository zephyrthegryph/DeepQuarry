//! BYOND string/resource checksums and native hub password encoding.
pub fn nqcrc(mut state: u32, bytes: &[u8]) -> u32 {
    // Eight independent lookups replace the byte-at-a-time dependency chain.
    // Big-endian reads are explicit and require no alignment or unsafe access.
    let mut blocks = bytes.chunks_exact(8);
    for block in &mut blocks {
        let head = state ^ u32::from_be_bytes([block[0], block[1], block[2], block[3]]);
        state = CRC_TABLES[7][(head >> 24) as usize]
            ^ CRC_TABLES[6][((head >> 16) & 255) as usize]
            ^ CRC_TABLES[5][((head >> 8) & 255) as usize]
            ^ CRC_TABLES[4][(head & 255) as usize]
            ^ CRC_TABLES[3][block[4] as usize]
            ^ CRC_TABLES[2][block[5] as usize]
            ^ CRC_TABLES[1][block[6] as usize]
            ^ CRC_TABLES[0][block[7] as usize];
    }
    for &byte in blocks.remainder() {
        state = (state << 8) ^ CRC_TABLES[0][((state >> 24) as u8 ^ byte) as usize];
    }
    state
}

static CRC_TABLES: [[u32; 256]; 8] = crc_tables();
const fn crc_tables() -> [[u32; 256]; 8] {
    let mut tables = [[0; 256]; 8];
    let mut index = 0;
    while index < 256 {
        let mut value = (index as u32) << 24;
        let mut bit = 0;
        while bit < 8 {
            value = (value << 1) ^ if value & 0x8000_0000 != 0 { 0xaf } else { 0 };
            bit += 1;
        }
        tables[0][index] = value;
        index += 1;
    }
    // The derived tables need the complete base table, including higher indices.
    let mut depth = 1;
    while depth < 8 {
        index = 0;
        while index < 256 {
            let value = tables[depth - 1][index];
            tables[depth][index] = (value << 8) ^ tables[0][(value >> 24) as usize];
            index += 1;
        }
        depth += 1;
    }
    tables
}

/// Dream Maker's text-valued world.hub_password transformation.
/// Native 516 uses UTF-8 bytes and lowercase hexadecimal MD5 text in both stages.
pub fn hub_password_hash(password: &[u8]) -> String {
    let inner = format!("{:x}", md5::compute(password));
    let mut outer = Vec::with_capacity(3 + password.len() + inner.len());
    outer.extend_from_slice(b"hub");
    outer.extend_from_slice(password);
    outer.extend_from_slice(inner.as_bytes());
    format!("X{:x}", md5::compute(&outer))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn resource_id_example() {
        assert_eq!(nqcrc(u32::MAX, b""), u32::MAX);
        assert_eq!(nqcrc(u32::MAX, b"abc"), 0xa4b0_41b4);
    }

    #[test]
    fn wide_crc_matches_independent_bits_and_streaming_at_unaligned_boundaries() {
        fn reference(mut state: u32, bytes: &[u8]) -> u32 {
            for &byte in bytes {
                state ^= u32::from(byte) << 24;
                for _ in 0..8 {
                    state = (state << 1) ^ if state & 0x8000_0000 != 0 { 0xaf } else { 0 };
                }
            }
            state
        }
        let data: Vec<_> = (0..8200).map(|i| ((i * 73 + i / 7) & 255) as u8).collect();
        for length in (0..129).chain([511, 512, 513, 4096, 8193]) {
            for offset in 0..7 {
                let bytes = &data[offset..offset + length];
                for seed in [0, u32::MAX, 0x1234_5678] {
                    let expected = reference(seed, bytes);
                    assert_eq!(nqcrc(seed, bytes), expected);
                    for split in 0..length.min(17) {
                        assert_eq!(
                            nqcrc(nqcrc(seed, &bytes[..split]), &bytes[split..]),
                            expected
                        );
                    }
                }
            }
        }
    }
}
