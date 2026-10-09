use serde::{Deserialize, Serialize};
use std::io::{self, Read, Write};
const MAX_FRAME: usize = 4 * 1024 * 1024;
pub(super) const VERSION: u32 = 2;
#[derive(Serialize, Deserialize)]
pub(super) enum Request {
    Hello { version: u32, compiler: u128 },
    Retire,
    Build(crate::request::BuildRequest),
}
#[derive(Serialize, Deserialize)]
pub(super) enum Reply {
    Hello {
        version: u32,
        compiler: u128,
        retiring: bool,
    },
    Accepted,
    Completed(crate::request::BuildOutcome),
    Diagnostic {
        stdout: bool,
        bytes: Vec<u8>,
    },
    Rejected(crate::request_failure::RequestFailure),
    Retiring,
}
pub(super) fn send(stream: &mut impl Write, value: &impl Serialize) -> io::Result<()> {
    let bytes = serde_json::to_vec(value)?;
    if bytes.len() > MAX_FRAME {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            "daemon frame too large",
        ));
    }
    stream.write_all(&(bytes.len() as u32).to_le_bytes())?;
    stream.write_all(&bytes)?;
    stream.flush()
}
pub(super) fn receive<T: serde::de::DeserializeOwned>(stream: &mut impl Read) -> io::Result<T> {
    let mut length = [0; 4];
    stream.read_exact(&mut length)?;
    let length = u32::from_le_bytes(length) as usize;
    if length > MAX_FRAME {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            "daemon frame too large",
        ));
    }
    let mut bytes = vec![0; length];
    stream.read_exact(&mut bytes)?;
    serde_json::from_slice(&bytes).map_err(io::Error::other)
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn oversize_refused_before_allocation() {
        assert!(receive::<Request>(&mut &((MAX_FRAME + 1) as u32).to_le_bytes()[..]).is_err());
    }
    #[test]
    fn handshake_roundtrip() {
        let mut bytes = Vec::new();
        send(
            &mut bytes,
            &Request::Hello {
                version: VERSION,
                compiler: 42,
            },
        )
        .unwrap();
        assert!(matches!(
            receive::<Request>(&mut &bytes[..]).unwrap(),
            Request::Hello { compiler: 42, .. }
        ));
    }
    #[test]
    fn diagnostic_wire_preserves_non_utf8_and_newline_fragments() {
        let expected = vec![0xff, 0xce, 0xbb, b'\n', 0];
        let mut wire = Vec::new();
        send(
            &mut wire,
            &Reply::Diagnostic {
                stdout: true,
                bytes: expected.clone(),
            },
        )
        .unwrap();
        match receive::<Reply>(&mut &wire[..]).unwrap() {
            Reply::Diagnostic { stdout, bytes } => {
                assert!(stdout);
                assert_eq!(bytes, expected);
            }
            _ => panic!("wrong reply"),
        }
    }
    #[test]
    fn typed_rejection_preserves_source_exit_through_transport() {
        let failure =
            crate::request_failure::RequestFailure::source("code/test.dm:4:error: invalid source");
        let mut wire = Vec::new();
        send(&mut wire, &Reply::Rejected(failure.clone())).unwrap();
        match receive::<Reply>(&mut &wire[..]).unwrap() {
            Reply::Rejected(decoded) => {
                assert_eq!(decoded, failure);
                let error: Box<dyn std::error::Error> = decoded.into();
                assert_eq!(crate::request_failure::exit_code(error.as_ref()), 2);
                assert_eq!(error.to_string(), "code/test.dm:4:error: invalid source");
            }
            _ => panic!("wrong reply"),
        }
    }
}
