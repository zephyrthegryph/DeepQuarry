//! Validate migration-only policy findings against the exact request roster.
//! These envelopes never assert whole-policy parity and never carry a model.
use super::{QueryReply, SourceQuery};
use serde_json::Value;
use std::io;

pub(super) fn validate_requested(reply: &QueryReply, requested: &[SourceQuery]) -> io::Result<()> {
    let expected: Vec<_> = requested
        .iter()
        .filter(|q| {
            matches!(
                q,
                SourceQuery::NativeUntypedFixture { .. } | SourceQuery::NativeCheckerFixture { .. }
            )
        })
        .collect();
    if reply.source_query_count != requested.len() {
        return Err(invalid("source request count"));
    }
    let mut observed = 0;
    for line in reply.jsonl.lines() {
        let row: Value = serde_json::from_str(line).map_err(|_| invalid("malformed JSONL"))?;
        if !matches!(
            row["row"].as_str(),
            Some("source_native_untyped_fixture" | "source_native_checker_fixture")
        ) {
            continue;
        }
        let question = expected
            .get(observed)
            .ok_or_else(|| invalid("unexpected extra native row"))?;
        if row["schema"] != "dm-session-source-query-v1"
            || reply.source_revision.is_none()
            || row["source_revision"].as_str() != reply.source_revision.as_deref()
            || row["semantic_revision"].as_str() != Some(reply.revision.as_str())
        {
            return Err(invalid("schema or revision"));
        }
        match question {
            SourceQuery::NativeUntypedFixture { root } => {
                exact(
                    &row,
                    &[
                        "row",
                        "schema",
                        "source_revision",
                        "semantic_revision",
                        "root",
                        "full_policy_parity",
                        "raw_marker_scope",
                        "admission",
                        "findings",
                    ],
                )?;
                if row["row"] != "source_native_untyped_fixture"
                    || row["root"] != serde_json::to_value(root).map_err(io::Error::other)?
                    || row["full_policy_parity"] != false
                    || row["raw_marker_scope"] != "captured_compiled_sources"
                    || row["admission"] != "raw_findings"
                {
                    return Err(invalid("untyped request metadata"));
                }
                for finding in array(&row["findings"])? {
                    validate_untyped(finding)?;
                }
            }
            SourceQuery::NativeCheckerFixture { ordinal, severity } => {
                exact(
                    &row,
                    &[
                        "row",
                        "schema",
                        "source_revision",
                        "semantic_revision",
                        "ordinal",
                        "family",
                        "policy",
                        "full_checker_parity",
                        "diagnostics",
                    ],
                )?;
                if row["row"] != "source_native_checker_fixture"
                    || row["ordinal"].as_u64() != Some(u64::from(*ordinal))
                    || row["family"] != "ambiguous_not_bitwise"
                    || row["policy"].as_str() != Some(severity.as_str())
                    || !matches!(severity.as_str(), "disabled" | "warning" | "error")
                    || row["full_checker_parity"] != false
                {
                    return Err(invalid("checker request metadata"));
                }
                let diagnostics = array(&row["diagnostics"])?;
                if severity == "disabled" && !diagnostics.is_empty() {
                    return Err(invalid("disabled checker findings"));
                }
                for diagnostic in diagnostics {
                    validate_checker(diagnostic, severity)?;
                }
            }
            _ => unreachable!(),
        }
        observed += 1;
    }
    if observed != expected.len() {
        return Err(invalid("missing native rows"));
    }
    Ok(())
}

fn validate_untyped(row: &Value) -> io::Result<()> {
    exact(row, &["rule", "file", "line", "message", "identity"])?;
    if !matches!(row["rule"].as_str(), Some("typed" | "call" | "schema"))
        || !text(&row["file"])
        || !text(&row["message"])
        || !text(&row["identity"])
        || !positive(&row["line"])
    {
        return Err(invalid("untyped finding"));
    }
    Ok(())
}

fn validate_checker(row: &Value, severity: &str) -> io::Result<()> {
    exact(
        row,
        &[
            "family",
            "severity",
            "expanded_span",
            "expression_span",
            "file",
            "line",
            "include_occurrence",
            "include_chain",
            "message",
            "notes",
        ],
    )?;
    if row["family"] != "ambiguous_not_bitwise"
        || row["severity"].as_str() != Some(severity)
        || !span(&row["expanded_span"])
        || !span(&row["expression_span"])
        || !text(&row["file"])
        || !positive(&row["line"])
        || !text(&row["message"])
        || row["include_occurrence"].as_u64().is_none()
        || !array(&row["include_chain"])?
            .iter()
            .all(|v| v.as_u64().is_some())
        || !array(&row["notes"])?.iter().all(text)
    {
        return Err(invalid("checker diagnostic"));
    }
    Ok(())
}

fn exact(row: &Value, keys: &[&str]) -> io::Result<()> {
    let object = row
        .as_object()
        .ok_or_else(|| invalid("row is not an object"))?;
    if object.len() != keys.len() || !keys.iter().all(|key| object.contains_key(*key)) {
        return Err(invalid("unexpected or missing payload fields"));
    }
    Ok(())
}
fn array(value: &Value) -> io::Result<&[Value]> {
    value
        .as_array()
        .map(Vec::as_slice)
        .ok_or_else(|| invalid("finding array"))
}
fn text(value: &Value) -> bool {
    value.as_str().is_some_and(|s| !s.is_empty())
}
fn positive(value: &Value) -> bool {
    value.as_u64().is_some_and(|v| v > 0)
}
fn span(value: &Value) -> bool {
    value.as_array().is_some_and(|a| {
        a.len() == 2
            && matches!((a[0].as_u64(), a[1].as_u64()), (Some(start), Some(end)) if start <= end)
    })
}
fn invalid(reason: &str) -> io::Error {
    io::Error::new(
        io::ErrorKind::InvalidData,
        format!("invalid requested native policy reply: {reason}"),
    )
}

#[cfg(test)]
#[path = "native_policy_tests.rs"]
mod tests;
