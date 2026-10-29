//! Complete `base_vars/records_data_only` rule over native declarations.
//!
//! This is one complete named rule, NOT the complete `base_vars` lint. Other
//! base-vars rules, notes, baselines, ALLOW validation and CLI presentation stay
//! with Analyze. No production dispatch is switched by this module.
use crate::{
    base_var_declarations::record_procedures,
    policy_inputs::{PolicyInputs, PolicyRole, TextView},
    untyped::Unsupported,
};
use std::path::Path;

pub const LINT: &str = "base_vars";
pub const RULE: &str = "records_data_only";

/// The existing Analyze Site fields. This hard-banned statement rule has empty
/// message, ceiling key and declaration identity, exactly as typed_sites emits.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct Finding {
    pub rule: String,
    pub rel: String,
    pub line: u32,
    pub msg: String,
    pub key: String,
    pub ident: String,
}

fn relative(root: &Path, path: &Path) -> String {
    // Report-only filesystem equivalence. Keep original provider/origin keys;
    // only the shared safe ordinary-DOS/verbatim comparison may unify paths.
    dm_preprocess::regions::relative_filesystem_path(path, root)
        .as_deref()
        .unwrap_or(path)
        .to_string_lossy()
        .replace('\\', "/")
}

/// Scan all authored record methods in this admitted compiler model.
///
/// `accessor_prefixes` is the resolved `record_accessor_prefixes` scope value.
/// The host must parse it from this request's captured configuration and include
/// the resolved value in the policy query key. A config edit rejudges this rule,
/// without requiring another DM parse. This function does not parse TOML or
/// pretend an arbitrary caller-supplied list proves filesystem/config coverage.
///
/// Legacy typed_sites applies neither path exemptions nor ALLOW checks to this
/// particular rule, including hidden/test files. Do not add either here. Scope
/// inventory completeness and baseline judgement are host responsibilities.
pub fn findings(
    inputs: &PolicyInputs,
    root: &Path,
    accessor_prefixes: &[String],
) -> Result<Vec<Finding>, Unsupported> {
    let archive = inputs.archive();
    let mut findings = Vec::new();
    for row in record_procedures(archive, root)? {
        let name = archive
            .tree()
            .symbols()
            .text(row.name)
            .ok_or_else(|| Unsupported("record rule callable name unavailable".into()))?;
        if accessor_prefixes
            .iter()
            .any(|prefix| name.starts_with(prefix.as_str()))
        {
            continue;
        }
        let file = inputs
            .file(&row.source.path)
            .ok_or_else(|| Unsupported("record rule source is not captured".into()))?;
        if !file.is_compiled() || file.role() != PolicyRole::DmSource {
            return Err(Unsupported(
                "record rule origin is not an admitted compiled source".into(),
            ));
        }
        // The raw view is necessary for the source-line presentation/fingerprint
        // contract. Never silently substitute the compiler's different decoder.
        let raw = file
            .view(TextView::AnalyzeRaw)
            .map_err(|error| Unsupported(format!("record rule raw input: {error}")))?;
        let line = file
            .analyze_display_line(row.source.line)
            .map_err(|error| Unsupported(format!("record rule source line: {error}")))?;
        if line == 0 || line > raw.as_str().split('\n').count() {
            return Err(Unsupported(
                "record rule source line is absent from the captured raw view".into(),
            ));
        }
        findings.push(Finding {
            rule: RULE.into(),
            rel: relative(root, &row.source.path),
            line: line
                .try_into()
                .map_err(|_| Unsupported("record rule line exceeds Analyze Site range".into()))?,
            msg: String::new(),
            key: String::new(),
            ident: String::new(),
        });
    }
    Ok(findings)
}

#[cfg(test)]
#[path = "records_data_only_tests.rs"]
mod tests;
