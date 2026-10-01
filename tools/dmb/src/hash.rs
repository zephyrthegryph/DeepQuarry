//! BYOND string/resource checksums and native hub password encoding.
use std::sync::OnceLock;

pub fn nqcrc(mut state: u32, bytes: &[u8]) -> u32 {
    static TABLE: OnceLock<[u32; 256]> = OnceLock::new();
    let table = TABLE.get_or_init(|| {
        let mut values = [0; 256];
        for (index, entry) in values.iter_mut().enumerate() {
            let mut value = (index as u32) << 24;
            for _ in 0..8 {
                value = (value << 1) ^ if value & 0x8000_0000 != 0 { 0xaf } else { 0 };
            }
            *entry = value;
        }
        values
    });
    for &byte in bytes {
        state = (state << 8) ^ table[((state >> 24) as u8 ^ byte) as usize];
    }
    state
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
}
