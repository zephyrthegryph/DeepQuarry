//! Source-bound BYOND516 raw asset encoding policy.
//! Paired current-source evidence: phase0/resources/raw_payload_control.
use crate::capture::{CapturePolicy, EncodedResourceInput};
use crate::{ResourceInput, ResourceRequest};
use sha2::{Digest, Sha256};
use std::io;
/// These extensions have current-source/native-RSC byte equality controls.
/// Unsupported formats can still supply an explicit current-source encoder.
pub fn byond516_raw_policy() -> CapturePolicy {
    CapturePolicy {
        certified_raw_extensions: [
            "dmi", "png", "ogg", "ttf", "txt", "html", "css", "js", "json", "dmf",
        ]
        .into_iter()
        .map(str::to_owned)
        .collect(),
    }
}
/// Encode only the supplied bytes. No hidden file reads or archive hints.
pub fn encode_raw(
    request: ResourceRequest,
    source: &[u8],
    policy: &CapturePolicy,
) -> io::Result<EncodedResourceInput> {
    crate::validate_archive_name(&request.archive_name)?;
    let extension = std::path::Path::new(&request.archive_name)
        .extension()
        .and_then(|value| value.to_str())
        .unwrap_or("")
        .to_ascii_lowercase();
    if !policy.certified_raw_extensions.contains(&extension) {
        return Err(io::Error::new(
            io::ErrorKind::Unsupported,
            "asset extension lacks a certified raw encoder",
        ));
    }
    let digest = Sha256::digest(source).into();
    Ok(EncodedResourceInput {
        source_digest: digest,
        input: ResourceInput {
            named: byond_dmb::rsc::NamedResource::from_data(
                crate::kind_for_name(&request.archive_name).as_byte(),
                request.archive_name.as_bytes().to_vec(),
                source.to_vec(),
                0,
                0,
            )?,
            archive_name: request.archive_name,
            disk_path: request.disk_path,
            content_digest: digest,
        },
    })
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn source_bound_encoder_preserves_kind_and_payload() {
        let policy = byond516_raw_policy();
        for (name, kind) in [
            ("a.dmi", 3),
            ("a.png", 6),
            ("a.ogg", 2),
            ("a.ttf", 14),
            ("a.txt", 0),
        ] {
            let output = encode_raw(
                ResourceRequest {
                    archive_name: name.into(),
                    disk_path: name.into(),
                },
                b"captured bytes",
                &policy,
            )
            .unwrap();
            assert_eq!(output.input.named.kind, kind);
            assert_eq!(output.input.named.asset_bytes().unwrap(), b"captured bytes");
            assert_eq!(output.source_digest, output.input.content_digest);
        }
        assert!(
            matches!(encode_raw(ResourceRequest {archive_name:"a.wav".into(),disk_path:"a.wav".into()},b"unknown",&policy),Err(error) if error.kind()==io::ErrorKind::Unsupported)
        );
    }
}
