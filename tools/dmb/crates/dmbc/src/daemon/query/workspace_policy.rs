//! Strict paged raw findings for an immutable prepared policy frame.
use super::{QueryReply, QueryRequest, SourceQuery};
use serde_json::Value;
use std::{io, path::Path};
fn invalid(s: &str) -> io::Error {
    io::Error::new(
        io::ErrorKind::InvalidData,
        format!("native workspace policy: {s}"),
    )
}
fn exact(row: &Value, names: &[&str]) -> io::Result<()> {
    let fields = row.as_object().ok_or_else(|| invalid("expected object"))?;
    if fields.len() != names.len() || names.iter().any(|name| !fields.contains_key(*name)) {
        return Err(invalid("extra/missing fields"));
    }
    Ok(())
}
fn text<'a>(row: &'a Value, name: &str, nonempty: bool) -> io::Result<&'a str> {
    row[name]
        .as_str()
        .filter(|s| !nonempty || !s.is_empty())
        .ok_or_else(|| invalid("invalid text"))
}
fn number(row: &Value, name: &str) -> io::Result<usize> {
    row[name]
        .as_u64()
        .and_then(|n| usize::try_from(n).ok())
        .ok_or_else(|| invalid("invalid page number"))
}
pub(super) fn reads_policy(q: &SourceQuery) -> bool {
    matches!(q, SourceQuery::NativeWorkspaceRawPolicy { .. })
}
pub(super) fn validate_request(request: &QueryRequest) -> io::Result<()> {
    for question in &request.source_queries {
        if let SourceQuery::NativeWorkspaceRawPolicy {
            root,
            configuration,
            lints,
            limit,
            ..
        } = question
        {
            if !root.is_absolute()
                || !configuration.is_absolute()
                || request.expected_policy_revision.is_none()
                || !(1..=128).contains(limit)
                || lints.is_empty()
                || lints.len() > dq_analyze::captured_raw_policy::RAW_FILE_LINTS.len()
                || lints.iter().any(|name| {
                    !dq_analyze::captured_raw_policy::RAW_FILE_LINTS.contains(&name.as_str())
                })
                || lints
                    .iter()
                    .collect::<std::collections::BTreeSet<_>>()
                    .len()
                    != lints.len()
            {
                return Err(io::Error::new(io::ErrorKind::InvalidInput,"workspace query requires exact policy pin, absolute paths, unique admitted raw lints and limit1..128"));
            }
        }
    }
    Ok(())
}
pub(super) fn validate_requested(reply: &QueryReply, questions: &[SourceQuery]) -> io::Result<()> {
    let wanted = questions
        .iter()
        .filter_map(|q| match q {
            SourceQuery::NativeWorkspaceRawPolicy {
                root,
                configuration,
                lints,
                cursor,
                limit,
            } => Some((root, configuration, lints, cursor, limit)),
            _ => None,
        })
        .collect::<Vec<_>>();
    let mut observed = 0;
    for line in reply.jsonl.lines() {
        let row: Value = serde_json::from_str(line).map_err(|_| invalid("invalid JSONL"))?;
        if row["row"] != "source_native_workspace_raw_policy" {
            continue;
        }
        let (root, configuration, lints, cursor, limit) = wanted
            .get(observed)
            .ok_or_else(|| invalid("unrequested page"))?;
        exact(
            &row,
            &[
                "row",
                "schema",
                "source_revision",
                "policy_revision",
                "semantic_revision",
                "snapshot_as_of",
                "root",
                "configuration",
                "recursive_roots",
                "requested_lints",
                "lint_whitelist",
                "scope",
                "full_policy_parity",
                "baseline_applied",
                "admission",
                "configuration_scope",
                "aggregate_id",
                "offset",
                "count",
                "total_items",
                "next_cursor",
                "items",
            ],
        )?;
        if row["schema"] != "dm-session-source-query-v1"
            || row["snapshot_as_of"] != "policy_revision"
            || reply.policy_revision.is_none()
            || row["policy_revision"].as_str() != reply.policy_revision.as_deref()
            || reply.source_revision.is_none()
            || row["source_revision"].as_str() != reply.source_revision.as_deref()
            || row["semantic_revision"].as_str() != Some(reply.revision.as_str())
            || row["root"] != serde_json::to_value(root).map_err(io::Error::other)?
            || row["configuration"]
                != serde_json::to_value(configuration).map_err(io::Error::other)?
            || row["requested_lints"] != serde_json::to_value(lints).map_err(io::Error::other)?
            || row["lint_whitelist"]
                != serde_json::to_value(dq_analyze::captured_raw_policy::RAW_FILE_LINTS)
                    .map_err(io::Error::other)?
            || row["scope"] != "typed_discovery_raw_files"
            || row["full_policy_parity"] != false
            || row["baseline_applied"] != false
            || row["admission"] != "raw_findings"
            || !matches!(
                row["configuration_scope"].as_str(),
                Some("captured_configuration_bytes" | "proven_missing_configuration")
            )
        {
            return Err(invalid("policy/request scope mismatch"));
        }
        let roots = row["recursive_roots"]
            .as_array()
            .ok_or_else(|| invalid("invalid recursive roots"))?;
        if roots.is_empty()
            || roots.iter().any(|r| {
                r.as_str()
                    .is_none_or(|s| !Path::new(s).is_absolute() || !Path::new(s).starts_with(root))
            })
        {
            return Err(invalid("recursive roots outside contract"));
        }
        let aggregate = text(&row, "aggregate_id", true)?;
        if aggregate.len() > 128 {
            return Err(invalid("aggregate ID exceeds schema bound"));
        }
        let offset = number(&row, "offset")?;
        let count = number(&row, "count")?;
        let total = number(&row, "total_items")?;
        let end = offset
            .checked_add(count)
            .ok_or_else(|| invalid("page offset overflow"))?;
        if offset != cursor.as_ref().map_or(0, |c| c.offset())
            || cursor
                .as_ref()
                .is_some_and(|c| c.aggregate_id() != aggregate)
            || count > **limit
            || end > total
            || (count == 0 && offset < total)
        {
            return Err(invalid("page progress/cursor mismatch"));
        }
        let items = row["items"]
            .as_array()
            .ok_or_else(|| invalid("invalid page records"))?;
        if items.len() != count {
            return Err(invalid("page item count mismatch"));
        }
        if end < total {
            let next: crate::query_db::WorkspaceCursor =
                serde_json::from_value(row["next_cursor"].clone())
                    .map_err(|_| invalid("missing continuation"))?;
            if next.offset() != end || next.aggregate_id() != aggregate {
                return Err(invalid("continuation not next exact page"));
            }
        } else if !row["next_cursor"].is_null() {
            return Err(invalid("unexpected terminal continuation"));
        }
        for item in items {
            let lint = text(item, "lint", true)?;
            if !lints.iter().any(|n| n == lint) {
                return Err(invalid("unrequested lint record"));
            }
            let meta = dq_analyze::captured_raw_policy::metadata(lint)
                .ok_or_else(|| invalid("unknown raw lint"))?;
            match text(item, "kind", true)? {
                "site" => {
                    exact(item, &["lint", "kind", "site"])?;
                    let s = &item["site"];
                    exact(s, &["rule", "rel", "line", "msg", "key", "ident"])?;
                    if meta.rule(text(s, "rule", true)?).is_none() {
                        return Err(invalid("unknown site rule"));
                    }
                    for name in ["rel", "msg", "key", "ident"] {
                        text(s, name, name == "rel")?;
                    }
                    if number(s, "line")? == 0 || number(s, "line")? > u32::MAX as usize {
                        return Err(invalid("invalid site line"));
                    }
                }
                "allow" => {
                    exact(item, &["lint", "kind", "allow"])?;
                    let a = &item["allow"];
                    exact(a, &["rel", "line", "name", "code"])?;
                    text(a, "rel", true)?;
                    text(a, "code", false)?;
                    if !meta.allow.contains(&text(a, "name", true)?)
                        || number(a, "line")? == 0
                        || number(a, "line")? > u32::MAX as usize
                    {
                        return Err(invalid("invalid used annotation"));
                    }
                }
                "note" => {
                    exact(item, &["lint", "kind", "text"])?;
                    text(item, "text", false)?;
                }
                _ => return Err(invalid("unknown finding record")),
            }
        }
        observed += 1;
    }
    if observed != wanted.len() {
        return Err(invalid("missing requested page"));
    }
    Ok(())
}
#[cfg(test)]
#[path = "workspace_policy_tests.rs"]
mod tests;
