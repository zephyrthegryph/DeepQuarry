//! Revision-pinned semantic roster pages, independent of source snapshots.
use super::{QueryReply, QueryRequest, SourceQuery};
use std::io::{self, Write};
fn invalid() -> io::Error {
    io::Error::new(io::ErrorKind::InvalidData, "invalid semantic roster page")
}
pub(super) fn is_semantic(query: &SourceQuery) -> bool {
    matches!(
        query,
        SourceQuery::SemanticTypesPage { .. }
            | SourceQuery::SemanticMembersPage { .. }
            | SourceQuery::SemanticIntrinsicMembersPage { .. }
    )
}
fn parts(query: &SourceQuery) -> Option<(&'static str, u32, u32)> {
    match query {
        SourceQuery::SemanticTypesPage { start, limit } => {
            Some(("semantic_types_page", *start, *limit))
        }
        SourceQuery::SemanticMembersPage { start, limit } => {
            Some(("semantic_members_page", *start, *limit))
        }
        SourceQuery::SemanticIntrinsicMembersPage { start, limit } => {
            Some(("semantic_intrinsic_members_page", *start, *limit))
        }
        _ => None,
    }
}
pub(super) fn validate_request(request: &QueryRequest) -> io::Result<()> {
    for query in &request.source_queries {
        if let Some((_, _, limit)) = parts(query) {
            if request.expected_revision.is_none() || !(1..=128).contains(&limit) {
                return Err(io::Error::new(
                    io::ErrorKind::InvalidInput,
                    "semantic pages require a revision pin and limit 1..128",
                ));
            }
        }
    }
    Ok(())
}
pub(super) fn write(
    query: &SourceQuery,
    tree: &dm_tree::SemanticTree,
    writer: &mut impl Write,
) -> io::Result<bool> {
    let Some((kind, start, limit)) = parts(query) else {
        return Ok(false);
    };
    let roster = if kind == "semantic_types_page" {
        dm_analysis::tree_export::SemanticRoster::Types
    } else if kind == "semantic_members_page" {
        dm_analysis::tree_export::SemanticRoster::Members
    } else {
        dm_analysis::tree_export::SemanticRoster::Intrinsics
    };
    dm_analysis::tree_export::write_roster_page(tree, roster, start, limit, writer)
        .map_err(io::Error::other)?;
    Ok(true)
}
fn number(row: &serde_json::Value, key: &str) -> io::Result<u32> {
    row[key]
        .as_u64()
        .and_then(|value| value.try_into().ok())
        .ok_or_else(invalid)
}
pub(super) fn validate(row: &serde_json::Value, revision: &str) -> io::Result<()> {
    let types = row["row"] == "semantic_types_page";
    let intrinsic = row["row"] == "semantic_intrinsic_members_page";
    if (!types && !intrinsic && row["row"] != "semantic_members_page")
        || row["schema"] != "dm-session-semantic-page-v1"
        || row["revision"].as_str() != Some(revision)
        || row["complete"] != false
        || row["page_complete"] != true
    {
        return Err(invalid());
    }
    if row["roster_scope"]
        != if types {
            "semantic_type_nodes"
        } else if intrinsic {
            "captured_engine_intrinsics"
        } else {
            "authored_member_nodes"
        }
        || row["engine_intrinsic_members_included"] != intrinsic
        || row["inherited_effective_members_included"] != false
        || row["intrinsic_inventory_complete"].as_bool().is_none()
        || row["hierarchy_certified"].as_bool().is_none()
    {
        return Err(invalid());
    }
    let (start, limit, total, returned) = (
        number(row, "start")?,
        number(row, "limit")?,
        number(row, "total")?,
        number(row, "returned")?,
    );
    if !(1..=128).contains(&limit) || start > total || returned != limit.min(total - start) {
        return Err(invalid());
    }
    let end = start.checked_add(returned).ok_or_else(invalid)?;
    if row.get("next_cursor").is_none()
        || (end < total && row["next_cursor"].as_u64() != Some(end.into()))
        || (end == total && !row["next_cursor"].is_null())
    {
        return Err(invalid());
    }
    let items = row["items"].as_array().ok_or_else(invalid)?;
    if items.len() != returned as usize {
        return Err(invalid());
    }
    for (index, item) in items.iter().enumerate() {
        if item["ordinal"].as_u64() != Some(start as u64 + index as u64)
            || item["row"]
                != if types {
                    "type"
                } else if intrinsic {
                    "intrinsic_member"
                } else {
                    "member"
                }
            || item["id"].as_str().is_none()
        {
            return Err(invalid());
        }
        if intrinsic {
            for field in ["owner_symbol", "name_symbol"] {
                let symbol = item[field].as_str().ok_or_else(invalid)?;
                if symbol.len() != 16 || !symbol.bytes().all(|byte| byte.is_ascii_hexdigit()) {
                    return Err(invalid());
                }
            }
            if !matches!(item["kind"].as_str(), Some("var" | "proc" | "verb")) {
                return Err(invalid());
            }
            let instance = item["instance_storage_proven"]
                .as_bool()
                .ok_or_else(invalid)?;
            let shared = item["shared_owner"].as_str();
            let status = if shared.is_some() {
                "shared"
            } else if instance {
                "instance"
            } else {
                "unknown"
            };
            let name_known = item["name_spelling_known"].as_bool().ok_or_else(invalid)?;
            if name_known != item["name"].as_str().is_some()
                || (!name_known && !item["name"].is_null())
                || (instance && item["kind"] != "var")
                || item["provenance"] != "captured_engine_intrinsic_inventory"
                || item["source_provenance_available"] != false
                || item.get("shared_owner").is_none()
                || (!item["shared_owner"].is_null() && shared.is_none())
                || (shared.is_some() && instance)
                || item["storage_status"] != status
            {
                return Err(invalid());
            }
        }
    }
    Ok(())
}
pub(super) fn validate_requested(reply: &QueryReply, queries: &[SourceQuery]) -> io::Result<()> {
    let mut requested = queries.iter().filter_map(parts);
    for line in reply.jsonl.lines() {
        let row: serde_json::Value = serde_json::from_str(line).map_err(io::Error::other)?;
        if row["row"] == "semantic_types_page"
            || row["row"] == "semantic_members_page"
            || row["row"] == "semantic_intrinsic_members_page"
        {
            let (kind, start, limit) = requested.next().ok_or_else(invalid)?;
            if row["row"] != kind
                || number(&row, "start")? != start
                || number(&row, "limit")? != limit
            {
                return Err(invalid());
            }
        }
    }
    if requested.next().is_some() {
        return Err(invalid());
    }
    Ok(())
}
#[cfg(test)]
mod tests;
