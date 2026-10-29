//! Strict whole-archive visibility request/reply boundary; findings only.
use super::{QueryReply, QueryRequest, SourceQuery};
use serde_json::Value;
use std::{io, path::Path};
pub(super) fn reads_policy(q: &SourceQuery) -> bool {
    matches!(q, SourceQuery::NativeConfiguredVariableVisibility { .. })
}
fn invalid(s: &str) -> io::Error {
    io::Error::new(
        io::ErrorKind::InvalidData,
        format!("invalid configured visibility: {s}"),
    )
}
pub(super) fn validate_request(request: &QueryRequest) -> io::Result<()> {
    for q in &request.source_queries {
        if let SourceQuery::NativeConfiguredVariableVisibility {
            environment,
            configuration,
        } = q
        {
            if request.expected_policy_revision.is_none()
                || !environment.is_absolute()
                || configuration.as_ref().is_some_and(|p| !p.is_absolute())
            {
                return Err(io::Error::new(io::ErrorKind::InvalidInput,"whole-archive visibility needs exact captured-policy revision and caller-absolute config paths"));
            }
        }
    }
    Ok(())
}
fn exact(v: &Value, keys: &[&str]) -> io::Result<()> {
    let o = v.as_object().ok_or_else(|| invalid("object"))?;
    if o.len() != keys.len() || keys.iter().any(|k| !o.contains_key(*k)) {
        return Err(invalid("fields"));
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
fn point(v: &Value) -> io::Result<()> {
    exact(v, &["file", "line", "column"])?;
    if !v["file"]
        .as_str()
        .is_some_and(|p| Path::new(p).is_absolute())
        || !v["line"].as_u64().is_some_and(|n| n > 0)
        || !v["column"].as_u64().is_some_and(|n| n > 0)
    {
        return Err(invalid("point"));
    }
    Ok(())
}
pub(super) fn validate_requested(reply: &QueryReply, questions: &[SourceQuery]) -> io::Result<()> {
    let expected = questions
        .iter()
        .filter(|q| reads_policy(q))
        .collect::<Vec<_>>();
    let mut next = 0;
    for line in reply.jsonl.lines() {
        let row: Value = serde_json::from_str(line).map_err(|_| invalid("JSONL"))?;
        if row["row"] != "source_native_configured_variable_visibility" {
            continue;
        }
        let Some(SourceQuery::NativeConfiguredVariableVisibility {
            environment,
            configuration,
        }) = expected.get(next).copied()
        else {
            return Err(invalid("extra row"));
        };
        exact(
            &row,
            &[
                "row",
                "schema",
                "semantic_revision",
                "source_revision",
                "policy_revision",
                "environment",
                "configuration",
                "configuration_explicit",
                "configuration_present",
                "configuration_schema",
                "declaration_profile",
                "native_declaration_error_count",
                "producer_categories",
                "families",
                "untagged_companions",
                "ordering",
                "full_checker_parity",
                "all_source_contexts_supported",
                "diagnostics",
            ],
        )?;
        match (
            row["declaration_profile"].as_str(),
            row["native_declaration_error_count"].as_u64(),
        ) {
            (Some("strict-native-declarations"), Some(0)) => {}
            (Some("native-diagnostic-inherited-variable-v1"), Some(count)) if count > 0 => {}
            _ => return Err(invalid("declaration profile or error domain")),
        }
        let selected =
            dm_analysis::check_configuration::select(environment, configuration.as_deref());
        if row["schema"] != "dm-session-source-query-v1"
            || row["semantic_revision"].as_str() != Some(reply.revision.as_str())
            || reply.source_revision.is_none()
            || row["source_revision"].as_str() != reply.source_revision.as_deref()
            || reply.policy_revision.is_none()
            || row["policy_revision"].as_str() != reply.policy_revision.as_deref()
            || row["environment"] != serde_json::to_value(environment).map_err(io::Error::other)?
            || row["configuration"]
                != serde_json::to_value(&selected.path).map_err(io::Error::other)?
            || row["configuration_explicit"] != selected.explicit
            || !row["configuration_present"].is_boolean()
            || row["configuration_schema"] != "complete_pinned_checker_schema"
            || row["producer_categories"]
                != serde_json::json!(["parser_locals", "global_declarations", "evaluated_fields"])
            || row["families"] != serde_json::json!(["private_var", "protected_var", "final_var"])
            || row["untagged_companions"] != serde_json::json!(["variable_redeclaration"])
            || row["ordering"]
                != "parser_encounter_then_lexical_declarations_then_evaluated_checker_order"
            || row["full_checker_parity"] != false
            || row["all_source_contexts_supported"] != false
        {
            return Err(invalid("metadata or revision"));
        }
        let rows = row["diagnostics"]
            .as_array()
            .ok_or_else(|| invalid("diagnostics"))?;
        if rows.len() > 10_000 {
            return Err(invalid("finding admission"));
        }
        for d in rows {
            exact(
                d,
                &[
                    "family",
                    "registration_tag",
                    "severity",
                    "origin",
                    "expanded_span",
                    "expression_span",
                    "message",
                    "notes",
                ],
            )?;
            let family = d["family"].as_str().ok_or_else(|| invalid("family"))?;
            if match family {
                "private_var" | "protected_var" | "final_var" => d["registration_tag"] != family,
                "variable_redeclaration" => !d["registration_tag"].is_null(),
                _ => true,
            } {
                return Err(invalid("tag identity"));
            }
            if !matches!(
                d["severity"].as_str(),
                Some("error" | "warning" | "info" | "hint")
            ) || !text(&d["message"])
                || !span(&d["expanded_span"])
                || !span(&d["expression_span"])
            {
                return Err(invalid("diagnostic"));
            }
            point(&d["origin"])?;
            for note in d["notes"].as_array().ok_or_else(|| invalid("notes"))? {
                exact(note, &["message", "source"])?;
                if !text(&note["message"]) {
                    return Err(invalid("note message"));
                }
                point(&note["source"])?;
            }
        }
        next += 1;
    }
    if next != expected.len() {
        return Err(invalid("missing row"));
    }
    Ok(())
}
#[cfg(test)]
#[path = "variable_visibility_tests.rs"]
mod tests;
