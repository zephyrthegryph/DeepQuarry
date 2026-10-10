//! Executable target admission; reusable frontend analysis remains caller configured.
use crate::request_failure::RequestFailure;
use std::collections::BTreeMap;

pub const DM_VERSION: &str = "516";
pub const DM_BUILD: &str = "1687";

/// Validate both supplied macros before adding either missing default.
/// A different macro must not select source for an ABI/catalog we do not support.
/// Values are exact preprocessor tokens, not evaluated caller expressions.
pub fn admit_defines(defines: &mut BTreeMap<String, String>) -> Result<(), RequestFailure> {
    for (name, expected) in [("DM_VERSION", DM_VERSION), ("DM_BUILD", DM_BUILD)] {
        if let Some(actual) = defines.get(name) {
            if actual != expected {
                return Err(RequestFailure::internal(format!(
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
            assert_eq!(failure.kind.exit_code(), 70);
            assert!(failure.message.contains(name));
            assert_eq!(defines, previous);
        }
    }
}
