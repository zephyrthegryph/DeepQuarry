//! Read-only endpoint metadata from the running compiler image.
//!
//! Supervisors use this exact descriptor instead of reproducing platform naming,
//! user identity or namespace hashing. It does not discover a live server: they
//! must still authenticate a connected pipe/socket and its protocol handshake.
use serde::Serialize;
use std::{ffi::OsStr, io};

pub const SCHEMA_VERSION: u32 = 1;
pub const ENDPOINT_SCHEME: &str = "compiler-generation-v1";

#[derive(Debug, Serialize)]
pub struct EndpointDescriptor {
    pub schema_version: u32,
    pub endpoint_scheme: &'static str,
    pub protocol_version: u32,
    /// Full image identity, in hexadecimal, avoiding JSON integer precision loss.
    pub compiler_identity: String,
    pub namespace: Option<String>,
    pub transport: &'static str,
    /// Build and query requests must connect to this exact compiler generation.
    pub generation_endpoint: String,
    /// Stable advisory discovery/retirement only; never a build fallback.
    pub discovery_endpoint: String,
}

pub fn current() -> io::Result<EndpointDescriptor> {
    let namespace = std::env::var_os("DMB_DAEMON_NAMESPACE");
    describe(super::compiler_identity()?, namespace.as_deref())
}

fn describe(compiler: u128, namespace: Option<&OsStr>) -> io::Result<EndpointDescriptor> {
    // The transport validates namespace spelling through its existing authority.
    let (generation_endpoint, discovery_endpoint) =
        super::transport::endpoint_addresses(compiler, namespace)?;
    Ok(EndpointDescriptor {
        schema_version: SCHEMA_VERSION,
        endpoint_scheme: ENDPOINT_SCHEME,
        protocol_version: super::protocol::VERSION,
        compiler_identity: format!("{compiler:032x}"),
        namespace: namespace.map(|value| value.to_str().expect("validated ASCII namespace").into()),
        transport: if cfg!(windows) {
            "windows-named-pipe"
        } else {
            "unix-socket"
        },
        generation_endpoint,
        discovery_endpoint,
    })
}

pub fn write_current(writer: &mut impl io::Write) -> io::Result<()> {
    let descriptor = current()?;
    serde_json::to_writer(&mut *writer, &descriptor).map_err(io::Error::other)?;
    writer.write_all(b"\n")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn endpoint_descriptor_default_and_scoped_addresses_use_exact_generation_authority() {
        let default = describe(1, None).unwrap();
        let scoped = describe(1, Some(OsStr::new("descriptor-test"))).unwrap();
        let replacement = describe(u128::MAX, Some(OsStr::new("descriptor-test"))).unwrap();
        assert_eq!(default.namespace, None);
        assert_eq!(scoped.namespace.as_deref(), Some("descriptor-test"));
        assert_eq!(
            default.compiler_identity,
            "00000000000000000000000000000001"
        );
        assert_eq!(default.protocol_version, super::super::protocol::VERSION);
        assert_eq!(default.endpoint_scheme, ENDPOINT_SCHEME);
        assert_ne!(default.generation_endpoint, default.discovery_endpoint);
        assert_ne!(default.generation_endpoint, scoped.generation_endpoint);
        assert_ne!(default.discovery_endpoint, scoped.discovery_endpoint);
        assert_ne!(scoped.generation_endpoint, replacement.generation_endpoint);
        assert_eq!(scoped.discovery_endpoint, replacement.discovery_endpoint);
        assert!(scoped.generation_endpoint.contains(&format!("g{:032x}", 1)));
        let json: serde_json::Value =
            serde_json::from_slice(&serde_json::to_vec(&scoped).unwrap()).unwrap();
        assert_eq!(json["compiler_identity"], scoped.compiler_identity);
        assert!(json.get("legacy_endpoint").is_none());
        #[cfg(unix)]
        {
            // Description must not create a directory for this unique namespace.
            let namespace = format!(
                "descriptor-{}-{:x}",
                std::process::id(),
                std::time::SystemTime::now()
                    .duration_since(std::time::UNIX_EPOCH)
                    .unwrap()
                    .as_nanos()
            );
            let metadata = describe(1, Some(OsStr::new(&namespace))).unwrap();
            assert!(!std::path::Path::new(&metadata.generation_endpoint)
                .parent()
                .unwrap()
                .exists());
            assert!(!std::path::Path::new(&metadata.discovery_endpoint)
                .parent()
                .unwrap()
                .exists());
        }
    }

    #[test]
    fn endpoint_descriptor_rejects_invalid_namespace_instead_of_legacy_fallback() {
        for namespace in ["", "../bad", "Upper", "space here"] {
            assert_eq!(
                describe(1, Some(OsStr::new(namespace))).unwrap_err().kind(),
                io::ErrorKind::InvalidInput
            );
        }
    }
}
