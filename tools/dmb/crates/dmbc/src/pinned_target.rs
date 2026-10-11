//! Executable target admission; reusable frontend analysis remains caller configured.
use crate::request_failure::RequestFailure;
use std::collections::BTreeMap;

pub const DM_VERSION: &str = "516";
pub const DM_BUILD: &str = "1687";

#[derive(Clone, Debug, serde::Serialize, serde::Deserialize)]
pub struct ConfigurationReceipt {
    pub schema_version: u32,
    pub version: u32,
    pub build: u32,
    pub engine_template_sha256: String,
    pub effective_defines: BTreeMap<String, String>,
    pub implicit_predefines_complete: bool,
}
/// Called only by successful native publication, after the ordinary target gate.
pub(crate) fn configuration(
    defines: &BTreeMap<String, String>,
    engine_identity: u128,
) -> Option<ConfigurationReceipt> {
    use sha2::{Digest, Sha256};
    let engine = include_bytes!("../../../fixtures/native_template.bin");
    if engine_identity != xxhash_rust::xxh3::xxh3_128(engine)
        || defines.get("DM_VERSION").map(String::as_str) != Some(DM_VERSION)
        || defines.get("DM_BUILD").map(String::as_str) != Some(DM_BUILD)
    {
        return None;
    }
    Some(ConfigurationReceipt {
        schema_version: 1,
        version: 516,
        build: 1687,
        engine_template_sha256: format!("{:x}", Sha256::digest(engine)),
        effective_defines: defines.clone(),
        implicit_predefines_complete: false,
    })
}

/// Validate both supplied macros before adding either missing default.
/// A different macro must not select source for an ABI/catalog we do not support.
/// Values are exact preprocessor tokens, not evaluated caller expressions.
pub fn admit_defines(defines: &mut BTreeMap<String, String>) -> Result<(), RequestFailure> {
    for (name, expected) in [("DM_VERSION", DM_VERSION), ("DM_BUILD", DM_BUILD)] {
        if let Some(actual) = defines.get(name) {
            if actual != expected {
                return Err(RequestFailure::invalid_request(format!(
                    "native unsupported: pinned BYOND {DM_VERSION}.{DM_BUILD} requires {name}={expected}; requested {actual:?}"
                )));
            }
        }
    }
    for (name, expected) in [("DM_VERSION", DM_VERSION), ("DM_BUILD", DM_BUILD)] {
        defines
            .entry(name.into())
            .or_insert_with(|| expected.into());
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn configuration_receipt_requires_actual_engine_and_admitted_defines() {
        let mut defines = BTreeMap::new();
        let engine =
            xxhash_rust::xxh3::xxh3_128(include_bytes!("../../../fixtures/native_template.bin"));
        assert!(configuration(&defines, engine).is_none());
        admit_defines(&mut defines).unwrap();
        let receipt = configuration(&defines, engine).unwrap();
        assert_eq!(receipt.effective_defines, defines);
        assert_eq!(receipt.engine_template_sha256.len(), 64);
        assert!(!receipt.implicit_predefines_complete);
        assert!(configuration(&defines, engine ^ 1).is_none());
        defines.insert("DM_BUILD".into(), "9999".into());
        assert!(configuration(&defines, engine).is_none());
    }

    #[test]
    fn omitted_target_macros_receive_pinned_defaults_without_changing_other_defines() {
        let mut defines = BTreeMap::from([("FEATURE".into(), "enabled".into())]);
        admit_defines(&mut defines).unwrap();
        assert_eq!(defines.get("DM_VERSION").unwrap(), "516");
        assert_eq!(defines.get("DM_BUILD").unwrap(), "1687");
        assert_eq!(defines.get("FEATURE").unwrap(), "enabled");
        let admitted = defines.clone();
        admit_defines(&mut defines).unwrap();
        assert_eq!(defines, admitted);
    }

    #[test]
    fn caller_values_matching_the_pinned_target_are_preserved() {
        let mut defines = BTreeMap::from([
            ("DM_VERSION".into(), "516".into()),
            ("DM_BUILD".into(), "1687".into()),
        ]);
        let expected = defines.clone();
        admit_defines(&mut defines).unwrap();
        assert_eq!(defines, expected);
    }

    #[test]
    fn incompatible_or_empty_values_fail_as_unsupported_without_partial_mutation() {
        for (name, value) in [
            ("DM_VERSION", "515"),
            ("DM_BUILD", "9999"),
            ("DM_VERSION", ""),
            ("DM_BUILD", ""),
            ("DM_BUILD", "1"),
            ("DM_VERSION", "(516)"),
        ] {
            let mut defines = BTreeMap::from([(name.into(), value.into())]);
            let previous = defines.clone();
            let failure = admit_defines(&mut defines).unwrap_err();
            assert_eq!(failure.kind.exit_code(), 64);
            assert!(failure.message.contains(name));
            assert_eq!(defines, previous);
        }
    }
}
