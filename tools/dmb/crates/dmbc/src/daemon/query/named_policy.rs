//! Exact findings-only envelopes for explicitly captured native named policies.
use super::{QueryReply, QueryRequest, SourceQuery};
use serde_json::Value;
use std::io;
fn invalid(detail: &str) -> io::Error {
    io::Error::new(
        io::ErrorKind::InvalidData,
        format!("invalid native named-policy reply: {detail}"),
    )
}
fn is_named(q: &SourceQuery) -> bool {
    matches!(
        q,
        SourceQuery::NativeNamedRule { .. } | SourceQuery::NativeConfiguredChecker { .. }
    )
}
pub(super) fn reads_policy(q: &SourceQuery) -> bool {
    is_named(q)
}
pub(super) fn validate_request(request: &QueryRequest) -> io::Result<()> {
    for q in request.source_queries.iter().filter(|q| is_named(q)) {
        if request.expected_policy_revision.is_none() {
            return Err(io::Error::new(
                io::ErrorKind::InvalidInput,
                "named policies require their exact captured-policy revision",
            ));
        }
        let allowed = match q {
            SourceQuery::NativeNamedRule {
                root,
                lint,
                rule,
                configuration,
            } => {
                root.is_absolute()
                    && configuration.is_absolute()
                    && lint == "base_vars"
                    && rule == "records_data_only"
            }
            SourceQuery::NativeConfiguredChecker {
                family,
                environment,
                configuration,
                ..
            } => {
                environment.is_absolute()
                    && configuration.as_ref().is_none_or(|p| p.is_absolute())
                    && matches!(
                        family.as_str(),
                        "ambiguous_not_bitwise"
                            | "ambiguous_in_lhs"
                            | "invalid_set_value"
                            | "control_condition_static"
                            | "set_has_no_effect"
                            | "unreachable_code"
                            | "loop_condition_determinate"
                            | "if_condition_determinate"
                    )
            }
            _ => false,
        };
        if !allowed {
            return Err(io::Error::new(
                io::ErrorKind::InvalidInput,
                "unsupported native named-policy scope or family",
            ));
        }
    }
    Ok(())
}
fn exact(row: &Value, keys: &[&str]) -> io::Result<()> {
    let o = row.as_object().ok_or_else(|| invalid("not an object"))?;
    if o.len() != keys.len() || !keys.iter().all(|k| o.contains_key(*k)) {
        return Err(invalid("payload fields"));
    }
    Ok(())
}
fn text(v: &Value) -> bool {
    v.as_str().is_some_and(|s| !s.is_empty())
}
fn span(v: &Value) -> bool {
    v.as_array().is_some_and(|a| {
        a.len() == 2 && matches!((a[0].as_u64(),a[1].as_u64()),(Some(s),Some(e))if s<=e)
    })
}
pub(super) fn validate_requested(reply: &QueryReply, questions: &[SourceQuery]) -> io::Result<()> {
    let expected: Vec<_> = questions.iter().filter(|q| is_named(q)).collect();
    let mut next = 0;
    for line in reply.jsonl.lines() {
        let row: Value = serde_json::from_str(line).map_err(|_| invalid("JSONL"))?;
        if !matches!(
            row["row"].as_str(),
            Some("source_native_named_rule" | "source_native_configured_checker")
        ) {
            continue;
        }
        let question = expected
            .get(next)
            .ok_or_else(|| invalid("extra named row"))?;
        if row["schema"] != "dm-session-source-query-v1"
            || row["semantic_revision"].as_str() != Some(reply.revision.as_str())
            || reply.source_revision.is_none()
            || row["source_revision"].as_str() != reply.source_revision.as_deref()
            || reply.policy_revision.is_none()
            || row["policy_revision"].as_str() != reply.policy_revision.as_deref()
        {
            return Err(invalid("foreign revision"));
        }
        match question {
            SourceQuery::NativeNamedRule {
                root,
                lint,
                rule,
                configuration,
            } => {
                exact(
                    &row,
                    &[
                        "row",
                        "schema",
                        "semantic_revision",
                        "source_revision",
                        "policy_revision",
                        "root",
                        "lint",
                        "rule",
                        "configuration",
                        "coverage",
                        "admission",
                        "full_lint_parity",
                        "findings",
                    ],
                )?;
                if row["row"] != "source_native_named_rule"
                    || row["root"] != serde_json::to_value(root).map_err(io::Error::other)?
                    || row["lint"] != lint.as_str()
                    || row["rule"] != rule.as_str()
                    || row["configuration"]
                        != serde_json::to_value(configuration).map_err(io::Error::other)?
                    || row["coverage"] != "captured_compiled_declarations"
                    || row["admission"] != "raw_findings"
                    || row["full_lint_parity"] != false
                {
                    return Err(invalid("named-rule metadata"));
                }
                for finding in row["findings"]
                    .as_array()
                    .ok_or_else(|| invalid("findings"))?
                {
                    exact(finding, &["rule", "rel", "line", "msg", "key", "ident"])?;
                    if finding["rule"] != rule.as_str()
                        || !text(&finding["rel"])
                        || !finding["line"].as_u64().is_some_and(|n| n > 0)
                        || ["msg", "key", "ident"]
                            .iter()
                            .any(|key| finding[*key] != "")
                    {
                        return Err(invalid("record finding"));
                    }
                }
            }
            SourceQuery::NativeConfiguredChecker {
                ordinal,
                family,
                environment,
                configuration,
            } => {
                exact(
                    &row,
                    &[
                        "row",
                        "schema",
                        "semantic_revision",
                        "source_revision",
                        "policy_revision",
                        "ordinal",
                        "family",
                        "environment",
                        "configuration",
                        "configuration_explicit",
                        "configuration_present",
                        "configuration_schema",
                        "full_checker_parity",
                        "diagnostics",
                    ],
                )?;
                let selected =
                    dm_analysis::check_configuration::select(environment, configuration.as_deref());
                if row["row"] != "source_native_configured_checker"
                    || row["ordinal"] != *ordinal
                    || row["family"] != family.as_str()
                    || row["environment"]
                        != serde_json::to_value(environment).map_err(io::Error::other)?
                    || row["configuration"]
                        != serde_json::to_value(&selected.path).map_err(io::Error::other)?
                    || row["configuration_explicit"] != selected.explicit
                    || !row["configuration_present"].is_boolean()
                    || row["configuration_schema"] != "complete_pinned_checker_schema"
                    || row["full_checker_parity"] != false
                {
                    return Err(invalid("configured checker metadata"));
                }
                for d in row["diagnostics"]
                    .as_array()
                    .ok_or_else(|| invalid("diagnostics"))?
                {
                    exact(
                        d,
                        &[
                            "family",
                            "severity",
                            "file",
                            "line",
                            "expanded_span",
                            "expression_span",
                            "message",
                            "notes",
                        ],
                    )?;
                    if d["family"] != family.as_str()
                        || !matches!(
                            d["severity"].as_str(),
                            Some("error" | "warning" | "info" | "hint")
                        )
                        || !text(&d["file"])
                        || !text(&d["message"])
                        || !d["line"].as_u64().is_some_and(|n| n > 0)
                        || !span(&d["expanded_span"])
                        || !span(&d["expression_span"])
                        || !d["notes"]
                            .as_array()
                            .is_some_and(|notes| notes.iter().all(text))
                    {
                        return Err(invalid("configured checker diagnostic"));
                    }
                }
            }
            _ => return Err(invalid("unexpected question")),
        }
        next += 1;
    }
    if next != expected.len() {
        return Err(invalid("missing named rows"));
    }
    Ok(())
}
#[cfg(test)]
#[path = "named_policy_tests.rs"]
mod tests;
