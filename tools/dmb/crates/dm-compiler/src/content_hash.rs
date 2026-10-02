//! Stream canonical MessagePack into a digest without an intermediate byte tree.
use serde::Serialize;
use sha2::{Digest, Sha256};
use std::io::{self, Write};

struct HashSink(Sha256);
impl Write for HashSink {
    fn write(&mut self, bytes: &[u8]) -> io::Result<usize> {
        self.0.update(bytes);
        Ok(bytes.len())
    }
    fn flush(&mut self) -> io::Result<()> { Ok(()) }
}

/// Same bytes as `rmp_serde::to_vec`, including the caller's domain prefix.
pub(crate) fn compact<T: Serialize + ?Sized>(domain: &[u8], value: &T) -> Option<[u8; 32]> {
    let mut sink = HashSink(Sha256::new());
    sink.0.update(domain);
    value.serialize(&mut rmp_serde::Serializer::new(&mut sink)).ok()?;
    Some(sink.0.finalize().into())
}

/// Same bytes as `rmp_serde::to_vec_named`; callers retain their existing schema.
pub(crate) fn named<T: Serialize + ?Sized>(domain: &[u8], value: &T) -> Option<[u8; 32]> {
    let mut sink = HashSink(Sha256::new());
    sink.0.update(domain);
    value.serialize(&mut rmp_serde::Serializer::new(&mut sink).with_struct_map()).ok()?;
    Some(sink.0.finalize().into())
}

pub(crate) fn text(digest: [u8; 32]) -> String {
    use std::fmt::Write;
    let mut output = String::with_capacity(64);
    for byte in digest { let _ = write!(output, "{byte:02x}"); }
    output
}
