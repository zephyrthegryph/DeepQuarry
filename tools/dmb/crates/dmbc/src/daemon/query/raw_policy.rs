//! Strict result envelopes for the explicit captured-file raw policy cohort.
use super::{QueryReply, QueryRequest, SourceQuery};
use serde_json::Value;
use std::io;
fn invalid(why: &str) -> io::Error {
    io::Error::new(
        io::ErrorKind::InvalidData,
        format!("native raw-policy result: {why}"),
    )
}
fn exact(row: &Value, keys: &[&str]) -> io::Result<()> {
    let object = row.as_object().ok_or_else(|| invalid("expected object"))?;
    if object.len() != keys.len() || keys.iter().any(|key| !object.contains_key(*key)) {
        return Err(invalid("unexpected/missing fields"));
    }
    Ok(())
}
fn text(row: &Value, key: &str, nonempty: bool) -> io::Result<()> {
    if row[key].as_str().is_none_or(|s| nonempty && s.is_empty()) {
        return Err(invalid("invalid text field"));
    }
    Ok(())
}
pub(super) fn reads_policy(query: &SourceQuery) -> bool {
    matches!(query, SourceQuery::NativeRawPolicyFixture { .. })
}
pub(super) fn validate_request(request: &QueryRequest) -> io::Result<()> {
    for question in &request.source_queries {
        if let SourceQuery::NativeRawPolicyFixture {
            root,
            configuration,
            lints,
        } = question
        {
            if !root.is_absolute()
                || !configuration.is_absolute()
                || request.expected_policy_revision.is_none()
                || lints.is_empty()
                || lints.len() > dq_analyze::captured_raw_policy::RAW_FILE_LINTS.len()
                || lints.iter().any(|name| {
                    !dq_analyze::captured_raw_policy::RAW_FILE_LINTS.contains(&name.as_str())
                })
            {
                return Err(io::Error::new(io::ErrorKind::InvalidInput,"raw policy requires absolute captured paths, exact policy pin and admitted lint names"));
            }
            if lints
                .iter()
                .collect::<std::collections::BTreeSet<_>>()
                .len()
                != lints.len()
            {
                return Err(io::Error::new(
                    io::ErrorKind::InvalidInput,
                    "raw policy lint list has duplicates",
                ));
            }
        }
    }
    Ok(())
}
pub(super) fn validate_requested(reply: &QueryReply, questions: &[SourceQuery]) -> io::Result<()> {
    let expected = questions
        .iter()
        .filter_map(|question| match question {
            SourceQuery::NativeRawPolicyFixture {
                root,
                configuration,
                lints,
            } => Some((root, configuration, lints)),
            _ => None,
        })
        .collect::<Vec<_>>();
    let mut observed = 0;
    for line in reply.jsonl.lines() {
        let row: Value = serde_json::from_str(line).map_err(|_| invalid("malformed JSONL"))?;
        if row["row"] != "source_native_raw_policy_fixture" {
            continue;
        }
        let (root, configuration, lints) = expected
            .get(observed)
            .ok_or_else(|| invalid("unexpected raw-policy row"))?;
        exact(
            &row,
            &[
                "row",
                "schema",
                "source_revision",
                "policy_revision",
                "semantic_revision",
                "root",
                "configuration",
                "requested_lints",
                "lint_whitelist",
                "scope",
                "full_policy_parity",
                "baseline_applied",
                "admission",
                "configuration_scope",
                "results",
                "fixture_limits",
            ],
        )?;
        if reply.policy_revision.is_none()
            || row["policy_revision"].as_str() != reply.policy_revision.as_deref()
            || reply.source_revision.is_none()
            || row["source_revision"].as_str() != reply.source_revision.as_deref()
            || row["semantic_revision"].as_str() != Some(reply.revision.as_str())
            || row["schema"] != "dm-session-source-query-v1"
            || row["root"] != serde_json::to_value(root).map_err(io::Error::other)?
            || row["configuration"]
                != serde_json::to_value(configuration).map_err(io::Error::other)?
            || row["requested_lints"] != serde_json::to_value(lints).map_err(io::Error::other)?
            || row["lint_whitelist"]
                != serde_json::to_value(dq_analyze::captured_raw_policy::RAW_FILE_LINTS)
                    .map_err(io::Error::other)?
            || row["fixture_limits"]
                != serde_json::json!({
                "per_file_bytes":dq_analyze::captured_raw_policy::MAX_FIXTURE_FILE_BYTES,
                "total_bytes":dq_analyze::captured_raw_policy::MAX_FIXTURE_TOTAL_BYTES,
                "sites":dq_analyze::captured_raw_policy::MAX_FIXTURE_SITES,
                "contract":"fixture_admission_not_cpu_or_rss"})
            || row["scope"] != "explicit_captured_files"
            || row["full_policy_parity"] != false
            || row["baseline_applied"] != false
            || row["admission"] != "raw_findings"
            || !matches!(
                row["configuration_scope"].as_str(),
                Some("captured_configuration_bytes" | "proven_missing_configuration")
            )
        {
            return Err(invalid("scope/request/revision mismatch"));
        }
        let results = row["results"]
            .as_array()
            .ok_or_else(|| invalid("results must be an array"))?;
        let wanted = dq_analyze::captured_raw_policy::RAW_FILE_LINTS
            .iter()
            .filter(|name| lints.iter().any(|requested| requested == **name))
            .collect::<Vec<_>>();
        if wanted.len() != results.len() {
            return Err(invalid("lint results missing or extra"));
        }
        for (result, name) in results.iter().zip(wanted) {
            exact(result, &["name", "sites", "allow_used", "notes"])?;
            if result["name"] != *name {
                return Err(invalid("lint result order/name"));
            }
            let meta = dq_analyze::captured_raw_policy::metadata(name)
                .ok_or_else(|| invalid("unsupported lint"))?;
            for site in result["sites"]
                .as_array()
                .ok_or_else(|| invalid("sites must be an array"))?
            {
                exact(site, &["rule", "rel", "line", "msg", "key", "ident"])?;
                for key in ["rule", "rel", "msg", "key", "ident"] {
                    text(site, key, matches!(key, "rule" | "rel"))?;
                }
                if site["line"]
                    .as_u64()
                    .is_none_or(|n| n == 0 || n > u32::MAX as u64)
                    || meta.rule(site["rule"].as_str().unwrap()).is_none()
                {
                    return Err(invalid("invalid site rule/line"));
                }
            }
            for usage in result["allow_used"]
                .as_array()
                .ok_or_else(|| invalid("allow_used must be an array"))?
            {
                exact(usage, &["rel", "line", "name", "code"])?;
                for key in ["rel", "name", "code"] {
                    text(usage, key, key != "code")?;
                }
                if usage["line"]
                    .as_u64()
                    .is_none_or(|n| n == 0 || n > u32::MAX as u64)
                    || !meta.allow.contains(&usage["name"].as_str().unwrap())
                {
                    return Err(invalid("invalid ALLOW name/line"));
                }
            }
            if result["notes"]
                .as_array()
                .is_none_or(|notes| notes.iter().any(|note| !note.is_string()))
            {
                return Err(invalid("invalid notes"));
            }
        }
        observed += 1;
    }
    if observed != expected.len() {
        return Err(invalid("missing raw-policy row"));
    }
    Ok(())
}

#[cfg(test)]
#[path = "raw_policy_tests.rs"]
mod tests;
