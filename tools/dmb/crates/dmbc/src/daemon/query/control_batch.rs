//! Exact configured-control union request/reply boundary. This admission does
//! not claim full checker coverage or persistent cached flow summaries.
use super::{QueryReply, QueryRequest, SourceQuery};
use serde_json::Value;
use std::io;
pub(super) fn reads_policy(query: &SourceQuery) -> bool {
    matches!(query, SourceQuery::NativeConfiguredControlBatch { .. })
}
pub(super) fn validate_request(request: &QueryRequest) -> io::Result<()> {
    for query in &request.source_queries {
        if let SourceQuery::NativeConfiguredControlBatch {
            families,
            environment,
            configuration,
            ..
        } = query
        {
            if request.expected_policy_revision.is_none()
                || !environment.is_absolute()
                || configuration.as_ref().is_some_and(|p| !p.is_absolute())
            {
                return Err(io::Error::new(io::ErrorKind::InvalidInput,"control batches require exact captured-policy pin and caller-absolute configuration paths"));
            }
            dm_analysis::checks_configured_control::Plan::new(families, &Default::default())
                .map_err(|message| io::Error::new(io::ErrorKind::InvalidInput, message))?;
        }
    }
    Ok(())
}
fn invalid(why: &str) -> io::Error {
    io::Error::new(
        io::ErrorKind::InvalidData,
        format!("invalid configured control batch: {why}"),
    )
}
fn exact(row: &Value, keys: &[&str]) -> io::Result<()> {
    let object = row.as_object().ok_or_else(|| invalid("not an object"))?;
    if object.len() != keys.len() || keys.iter().any(|key| !object.contains_key(*key)) {
        return Err(invalid("payload fields"));
    }
    Ok(())
}
fn text(value: &Value) -> bool {
    value.as_str().is_some_and(|s| !s.is_empty())
}
fn span(value: &Value) -> bool {
    value.as_array().is_some_and(|v| {
        v.len() == 2 && matches!((v[0].as_u64(),v[1].as_u64()),(Some(s),Some(e))if s<=e)
    })
}
pub(super) fn validate_requested(reply: &QueryReply, questions: &[SourceQuery]) -> io::Result<()> {
    let expected: Vec<_> = questions.iter().filter(|q| reads_policy(q)).collect();
    let mut next = 0;
    for line in reply.jsonl.lines() {
        let row: Value = serde_json::from_str(line).map_err(|_| invalid("JSONL"))?;
        if row["row"] != "source_native_configured_control_batch" {
            continue;
        }
        let Some(SourceQuery::NativeConfiguredControlBatch {
            ordinal,
            families,
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
                "ordinal",
                "families",
                "environment",
                "configuration",
                "configuration_explicit",
                "configuration_present",
                "configuration_schema",
                "full_checker_parity",
                "ordering",
                "flow_reuse",
                "diagnostics",
            ],
        )?;
        let selected =
            dm_analysis::check_configuration::select(environment, configuration.as_deref());
        if row["schema"] != "dm-session-source-query-v1"
            || row["semantic_revision"].as_str() != Some(reply.revision.as_str())
            || reply.source_revision.is_none()
            || row["source_revision"].as_str() != reply.source_revision.as_deref()
            || reply.policy_revision.is_none()
            || row["policy_revision"].as_str() != reply.policy_revision.as_deref()
            || row["ordinal"] != *ordinal
            || row["families"] != serde_json::to_value(families).map_err(io::Error::other)?
            || row["environment"] != serde_json::to_value(environment).map_err(io::Error::other)?
            || row["configuration"]
                != serde_json::to_value(&selected.path).map_err(io::Error::other)?
            || row["configuration_explicit"] != selected.explicit
            || !row["configuration_present"].is_boolean()
            || row["configuration_schema"] != "complete_pinned_checker_schema"
            || row["full_checker_parity"] != false
            || row["ordering"] != "primary_control_event_order"
            || row["flow_reuse"] != "request_local_union"
        {
            return Err(invalid("metadata or revision"));
        }
        for diagnostic in row["diagnostics"]
            .as_array()
            .ok_or_else(|| invalid("diagnostics"))?
        {
            exact(
                diagnostic,
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
            if !diagnostic["family"]
                .as_str()
                .is_some_and(|name| families.iter().any(|selected| selected == name))
                || !matches!(
                    diagnostic["severity"].as_str(),
                    Some("error" | "warning" | "info" | "hint")
                )
                || !text(&diagnostic["file"])
                || !text(&diagnostic["message"])
                || !diagnostic["line"].as_u64().is_some_and(|n| n > 0)
                || !span(&diagnostic["expanded_span"])
                || !span(&diagnostic["expression_span"])
                || !diagnostic["notes"]
                    .as_array()
                    .is_some_and(|notes| notes.iter().all(text))
            {
                return Err(invalid("diagnostic"));
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
#[path = "control_batch_tests.rs"]
mod tests;
