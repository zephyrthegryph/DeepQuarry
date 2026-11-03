//! Frozen independent pinned0290 lexer token-value conversion (GPL-3.0).
//! Selected source bytes preserved; current native codec is never called.
fn from_latin1(bytes: &[u8]) -> String {
    let non_ascii = bytes.iter().filter(|&&i| i > 0x7f).count();
    let mut output = String::with_capacity(bytes.len() + non_ascii);
    for &byte in bytes.iter() {
        output.push(byte as char);
    }
    output
}

/// Convert the input bytes to a `String` attempting UTF-8 or falling back to Latin-1.
pub fn from_utf8_or_latin1(bytes: Vec<u8>) -> String {
    match String::from_utf8(bytes) {
        Ok(v) => v,
        Err(e) => from_latin1(e.as_bytes()),
    }
}

