//! Captured Analyze configuration for one migrated named rule, without I/O.
//! Uses Analyze's TOML 0.8 grammar and its exact strings() selection: absent,
//! non-array or non-string list entries have the same empty/filter behavior.
//! This is not validation or execution of the other lint scopes/rules.
use std::io;

pub fn record_accessor_prefixes(bytes: &[u8]) -> io::Result<Vec<String>> {
    // Scopes::load uses read_to_string and returns Scopes::default on every
    // read error, including invalid UTF-8. Captured bytes retain that distinction
    // without a second read; do not repair them through AnalyzeRaw's lossy view.
    let Ok(text) = std::str::from_utf8(bytes) else {
        return Ok(Vec::new());
    };
    let value: toml_analyze::Value = text.parse().map_err(|error| {
        io::Error::new(
            io::ErrorKind::InvalidData,
            format!("lint_scopes.toml: {error}"),
        )
    })?;
    Ok(value
        .get("lint")
        .and_then(|v| v.as_table())
        .and_then(|v| v.get("base_vars"))
        .and_then(|v| v.get("lists"))
        .and_then(|v| v.as_table())
        .and_then(|v| v.get("record_accessor_prefixes"))
        .and_then(|v| v.as_array())
        .map(|values| {
            values
                .iter()
                .filter_map(|v| v.as_str().map(str::to_owned))
                .collect()
        })
        .unwrap_or_default())
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn exact_scope_list_and_analyze_filtering_semantics() {
        assert_eq!(
            record_accessor_prefixes(
                b"[lint.base_vars.lists]\nrecord_accessor_prefixes=['set_','get_',3]\n"
            )
            .unwrap(),
            ["set_", "get_"]
        );
        for input in [
            b"".as_slice(),
            b"lint=1",
            b"[lint.base_vars.lists]\nrecord_accessor_prefixes=3",
        ] {
            assert!(record_accessor_prefixes(input).unwrap().is_empty());
        }
    }
    #[test]
    fn unreadable_utf8_defaults_but_readable_malformed_toml_remains_an_error() {
        assert!(record_accessor_prefixes(b"# bad \xff").unwrap().is_empty());
        assert!(record_accessor_prefixes(b"[unrelated]\nx=[").is_err());
    }
}
