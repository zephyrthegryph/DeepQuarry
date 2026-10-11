//! Optional native-only publication evidence from the already admitted S0 owner.
use crate::{input_snapshot::InputSnapshot, publish::OutputPair};
use serde::{Deserialize, Serialize};
use std::{
    collections::BTreeMap,
    io::{self, Write},
    path::{Path, PathBuf},
};

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct NativePublicationProof {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub resource_journal_admission: Option<crate::resource_journal_coverage::ResourceJournalAdmission>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub target_configuration: Option<crate::pinned_target::ConfigurationReceipt>,
    pub schema_version: u32,
    pub kind: String,
    pub native_inputs_admitted: bool,
    pub shared_input_closure_complete: bool,
    pub pair_id: String,
    pub document: PathBuf,
    pub document_bytes: u64,
    pub document_xxh3_128: String,
    pub snapshot_bytes: u64,
    pub snapshot_xxh3_128: String,
}
#[derive(Serialize)]
struct Document<'a> {
    #[serde(skip_serializing_if = "Option::is_none")]
    resource_journal_admission: Option<&'a crate::resource_journal_coverage::ResourceJournalAdmission>,
    #[serde(skip_serializing_if = "Option::is_none")]
    target_configuration: Option<crate::pinned_target::ConfigurationReceipt>,
    schema_version: u32,
    kind: &'static str,
    scope: &'static str,
    pair_id: String,
    manifest: &'a Path,
    defines: &'a BTreeMap<String, String>,
    engine_identity: String,
    bootstrap_catalog: bool,
    // Preserve exact InputSnapshot serialization (including integer spellings),
    // rather than roundtripping through a generic JSON number representation.
    snapshot_json: &'a str,
}
#[cfg(test)]
fn encode(
    snapshot: &InputSnapshot,
    pair: &OutputPair,
    manifest: &Path,
    defines: &BTreeMap<String, String>,
    engine_identity: u128,
    bootstrap_catalog: bool,
) -> io::Result<(Vec<u8>, usize, u128)> {
    encode_with_resource_admission(snapshot, pair, manifest, defines, engine_identity, bootstrap_catalog, None)
}
fn encode_with_resource_admission(
    snapshot: &InputSnapshot, pair: &OutputPair, manifest: &Path,
    defines: &BTreeMap<String, String>, engine_identity: u128, bootstrap_catalog: bool,
    resource_journal_admission: Option<&crate::resource_journal_coverage::ResourceJournalAdmission>,
) -> io::Result<(Vec<u8>, usize, u128)> {
    let snapshot = serde_json::to_vec(snapshot).map_err(io::Error::other)?;
    let length = snapshot.len();
    let digest = xxhash_rust::xxh3::xxh3_128(&snapshot);
    let text = std::str::from_utf8(&snapshot).map_err(io::Error::other)?;
    let bytes = serde_json::to_vec(&Document {
        resource_journal_admission,
        target_configuration: crate::pinned_target::configuration(defines, engine_identity),
        schema_version: 1,
        kind: "native_publication_inputs",
        scope: "native admitted inputs only; BYOND access completeness is not issued",
        pair_id: pair.name(),
        manifest,
        defines,
        engine_identity: format!("{engine_identity:032x}"),
        bootstrap_catalog,
        snapshot_json: text,
    })
    .map_err(io::Error::other)?;
    Ok((bytes, length, digest))
}
/// Invoke only after successful installation; this function performs no input reads.
#[cfg(test)]
pub(crate) fn issue(
    snapshot: &InputSnapshot,
    pair: &OutputPair,
    manifest: &Path,
    defines: &BTreeMap<String, String>,
    engine_identity: u128,
    bootstrap_catalog: bool,
    store: &Path,
) -> io::Result<NativePublicationProof> {
    issue_with_resource_admission(snapshot, pair, manifest, defines, engine_identity, bootstrap_catalog, store, None)
}
pub(crate) fn issue_with_resource_admission(
    snapshot: &InputSnapshot, pair: &OutputPair, manifest: &Path,
    defines: &BTreeMap<String, String>, engine_identity: u128, bootstrap_catalog: bool,
    store: &Path, resource_journal_admission: Option<crate::resource_journal_coverage::ResourceJournalAdmission>,
) -> io::Result<NativePublicationProof> {
    let (bytes, snapshot_bytes, snapshot_digest) = encode_with_resource_admission(
        snapshot,
        pair,
        manifest,
        defines,
        engine_identity,
        bootstrap_catalog,
        resource_journal_admission.as_ref(),
    )?;
    let digest = xxhash_rust::xxh3::xxh3_128(&bytes);
    let directory = store.join("publication-proofs");
    std::fs::create_dir_all(&directory)?;
    let metadata = std::fs::symlink_metadata(&directory)?;
    if !metadata.is_dir() || metadata.file_type().is_symlink() {
        return Err(io::Error::other(
            "publication proof directory is not regular",
        ));
    }
    #[cfg(windows)]
    {
        use std::os::windows::fs::MetadataExt;
        if metadata.file_attributes() & 0x400 != 0 {
            return Err(io::Error::other(
                "publication proof directory is a reparse point",
            ));
        }
    }
    let document = directory.join(format!("{digest:032x}.json"));
    match std::fs::OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(&document)
    {
        Ok(mut file) => {
            let result = file.write_all(&bytes).and_then(|()| file.sync_all());
            drop(file);
            if result.is_err() {
                let _ = std::fs::remove_file(&document);
            }
            result?;
        }
        Err(error) if error.kind() == io::ErrorKind::AlreadyExists => {
            let metadata = std::fs::symlink_metadata(&document)?;
            if !metadata.is_file() || metadata.file_type().is_symlink() {
                return Err(io::Error::other(
                    "publication proof is not an owned regular file",
                ));
            }
            #[cfg(windows)]
            {
                use std::os::windows::fs::MetadataExt;
                if metadata.file_attributes() & 0x400 != 0 {
                    return Err(io::Error::other("publication proof is a reparse point"));
                }
            }
            if std::fs::read(&document)? != bytes {
                return Err(io::Error::other("publication proof identity collision"));
            }
        }
        Err(error) => return Err(error),
    }
    Ok(NativePublicationProof {
        resource_journal_admission,
        target_configuration: crate::pinned_target::configuration(defines, engine_identity),
        schema_version: 1,
        kind: "native_publication_inputs".into(),
        native_inputs_admitted: true,
        shared_input_closure_complete: false,
        pair_id: pair.name(),
        document: std::fs::canonicalize(document)?,
        document_bytes: bytes.len() as u64,
        document_xxh3_128: format!("{digest:032x}"),
        snapshot_bytes: snapshot_bytes as u64,
        snapshot_xxh3_128: format!("{snapshot_digest:032x}"),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn document_binds_partial_resource_admission_and_preserves_decline() {
        let snapshot = InputSnapshot::new(1);
        let pair = OutputPair::from_bytes(b"dmb", b"rsc");
        let defines = BTreeMap::new();
        let receipt = crate::resource_journal_coverage::ResourceJournalAdmission {
            schema_version: 1, physical_observed_demand_admitted: false,
            shared_input_closure_complete: false, coverage: None,
            decline_reason: Some("journal has no physical path authority".into()),
        };
        let ordinary = encode(&snapshot, &pair, Path::new("E:/probe.dme"), &defines, 7, false).unwrap();
        let issued = encode_with_resource_admission(&snapshot, &pair, Path::new("E:/probe.dme"),
            &defines, 7, false, Some(&receipt)).unwrap();
        assert_ne!(ordinary.0, issued.0);
        assert_eq!(ordinary.1, issued.1);
        assert_eq!(ordinary.2, issued.2);
        let document: serde_json::Value = serde_json::from_slice(&issued.0).unwrap();
        assert_eq!(document["resource_journal_admission"]["physical_observed_demand_admitted"], false);
        assert_eq!(document["resource_journal_admission"]["shared_input_closure_complete"], false);
        assert_eq!(document["resource_journal_admission"]["decline_reason"], receipt.decline_reason.unwrap());
    }

    #[test]
    fn issued_sidecar_reuses_exact_document_and_rejects_tampering() {
        let base = if cfg!(windows) {
            PathBuf::from("E:/dq-cache/dmb-publication-proof-tests")
        } else {
            std::env::temp_dir()
        };
        std::fs::create_dir_all(&base).unwrap();
        let store = base.join(format!(
            "{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        std::fs::create_dir(&store).unwrap();
        let snapshot = InputSnapshot::new(42);
        let pair = OutputPair::from_bytes(b"dmb", b"rsc");
        let defines = BTreeMap::new();
        let first = issue(
            &snapshot,
            &pair,
            Path::new("E:/probe.dme"),
            &defines,
            7,
            false,
            &store,
        )
        .unwrap();
        let second = issue(
            &snapshot,
            &pair,
            Path::new("E:/probe.dme"),
            &defines,
            7,
            false,
            &store,
        )
        .unwrap();
        assert_eq!(first.document, second.document);
        assert_eq!(first.pair_id, pair.name());
        assert!(first.native_inputs_admitted);
        assert!(!first.shared_input_closure_complete);
        let bytes = std::fs::read(&first.document).unwrap();
        assert_eq!(first.document_bytes, bytes.len() as u64);
        assert_eq!(
            first.document_xxh3_128,
            format!("{:032x}", xxhash_rust::xxh3::xxh3_128(&bytes))
        );
        std::fs::write(&first.document, b"tampered").unwrap();
        assert!(issue(
            &snapshot,
            &pair,
            Path::new("E:/probe.dme"),
            &defines,
            7,
            false,
            &store
        )
        .is_err());
        std::fs::remove_file(&first.document).unwrap();
        std::fs::remove_dir(store.join("publication-proofs")).unwrap();
        std::fs::remove_dir(store).unwrap();
    }

    #[test]
    fn document_binds_exact_snapshot_pair_and_configuration() {
        let snapshot = InputSnapshot::new(u128::MAX);
        let pair = OutputPair::from_bytes(b"dmb", b"rsc");
        let manifest = Path::new("E:/fixture/probe.dme");
        let mut defines = BTreeMap::from([("DM_VERSION".into(), "516".into())]);
        let (bytes, length, digest) =
            encode(&snapshot, &pair, manifest, &defines, 7, false).unwrap();
        let expected = serde_json::to_vec(&snapshot).unwrap();
        let document: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
        assert_eq!(
            document["snapshot_json"].as_str().unwrap().as_bytes(),
            expected
        );
        assert_eq!(length, expected.len());
        assert_eq!(digest, xxhash_rust::xxh3::xxh3_128(&expected));
        assert_eq!(document["pair_id"], pair.name());
        assert!(document["snapshot_json"]
            .as_str()
            .unwrap()
            .contains(&u128::MAX.to_string()));
        let changed_pair = OutputPair::from_bytes(b"changed", b"rsc");
        assert_ne!(
            bytes,
            encode(&snapshot, &changed_pair, manifest, &defines, 7, false)
                .unwrap()
                .0
        );
        defines.insert("TEST_DEFINES".into(), "1".into());
        assert_ne!(
            bytes,
            encode(&snapshot, &pair, manifest, &defines, 7, false)
                .unwrap()
                .0
        );
        assert_ne!(
            bytes,
            encode(
                &snapshot,
                &pair,
                Path::new("E:/other/probe.dme"),
                &BTreeMap::from([("DM_VERSION".into(), "516".into())]),
                7,
                false
            )
            .unwrap()
            .0
        );
    }
}
