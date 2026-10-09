//! Source-bound BYOND516 raw asset encoding policy.
//! Paired current-source evidence: phase0/resources/raw_payload_control.
use crate::capture::{CapturePolicy, EncodedResourceInput};
use crate::{ResourceInput, ResourceRequest};
use sha2::{Digest, Sha256};
use std::{io, sync::Arc};
/// These extensions have current-source/native-RSC byte equality controls.
/// Unsupported formats can still supply an explicit current-source encoder.
pub fn byond516_raw_policy() -> CapturePolicy {
    CapturePolicy {
        certified_raw_extensions: [
            "dmi", "png", "ogg", "ttf", "txt", "html", "css", "js", "json", "dmf", "gif", "wav",
            "mid", "mp3", "woff2", "webp", "mp4", "dm", "dms",
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
    encode_raw_shared(request, Arc::from(source), policy)
}
/// Encode a captured immutable source without duplicating its backing allocation.
pub fn encode_raw_shared(
    request: ResourceRequest,
    source: Arc<[u8]>,
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
    let digest = Sha256::digest(&source).into();
    Ok(EncodedResourceInput {
        source_digest: digest,
        input: ResourceInput {
            named: crate::NamedResourceInput::from_shared_data(
                crate::kind_for_name(&request.archive_name).as_byte(),
                request.archive_name.as_bytes().to_vec(),
                source,
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
    fn shared_raw_encoder_keeps_source_allocation() {
        let source: Arc<[u8]> = Arc::from(&b"raw shared payload"[..]);
        let encoded = encode_raw_shared(
            ResourceRequest {
                archive_name: "a.txt".into(),
                disk_path: "a.txt".into(),
            },
            Arc::clone(&source),
            &byond516_raw_policy(),
        )
        .unwrap();
        assert!(Arc::ptr_eq(&source, encoded.input.named.shared_data()));
        assert!(Arc::ptr_eq(
            &source,
            encoded.clone().input.named.shared_data()
        ));
    }
    #[test]
    fn additional_current_assets_match_native_payload_kind_and_id() {
        for (control, count) in [
            ("additional_raw_control", 6),
            ("browser_source_raw_control", 2),
            ("script_file_raw_control", 1),
        ] {
            let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
                .join("../../fixtures/phase0/resources")
                .join(control);
            let archive = std::fs::read(root.join("probe.rsc")).unwrap();
            let records = byond_dmb::rsc::read_all(&mut archive.as_slice()).unwrap();
            assert_eq!(records.len(), count);
            let policy = byond516_raw_policy();
            for record in records {
                let byond_dmb::rsc::Entry::Named(native) = record else {
                    panic!("opaque control resource")
                };
                let name = String::from_utf8(native.name.clone()).unwrap();
                let source = std::fs::read(root.join(&name)).unwrap();
                let encoded = encode_raw(
                    ResourceRequest {
                        archive_name: name.clone(),
                        disk_path: root.join(&name),
                    },
                    &source,
                    &policy,
                )
                .unwrap();
                assert_eq!(encoded.input.named.kind, native.kind, "{name}");
                assert_eq!(encoded.input.named.id, native.id, "{name}");
                assert_eq!(
                    encoded.input.named.asset_bytes().unwrap(),
                    native.asset_bytes().unwrap(),
                    "{name}"
                );
            }
        }
    }
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
            matches!(encode_raw(ResourceRequest {archive_name:"a.jpeg".into(),disk_path:"a.jpeg".into()},b"unknown",&policy),Err(error) if error.kind()==io::ErrorKind::Unsupported)
        );
    }
}
