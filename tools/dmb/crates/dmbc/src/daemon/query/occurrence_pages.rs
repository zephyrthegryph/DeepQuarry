//! Client checks for bounded current-issuer occurrence pages.
use super::{QueryReply, SourceQuery};
use std::io;
fn invalid() -> io::Error {
    io::Error::new(
        io::ErrorKind::InvalidData,
        "invalid occurrence page envelope",
    )
}
fn number(row: &serde_json::Value, key: &str) -> io::Result<u32> {
    row[key]
        .as_u64()
        .and_then(|n| u32::try_from(n).ok())
        .ok_or_else(invalid)
}
pub(super) fn validate(row: &serde_json::Value, revision: Option<&str>) -> io::Result<()> {
    if row["schema"] != "dm-session-source-query-v1"
        || row["row"] != "source_occurrences_page"
        || row["source_revision"].as_str() != revision
        || revision.is_none()
        || row["complete"] != false
        || row["page_complete"] != true
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
    if row.get("next_cursor").is_none() {
        return Err(invalid());
    }
    let end = start.checked_add(returned).ok_or_else(invalid)?;
    if end < total {
        if row["next_cursor"].as_u64() != Some(u64::from(end)) {
            return Err(invalid());
        }
    } else if !row["next_cursor"].is_null() {
        return Err(invalid());
    }
    let items = row["items"].as_array().ok_or_else(invalid)?;
    if items.len() != returned as usize {
        return Err(invalid());
    }
    for (index, item) in items.iter().enumerate() {
        if item["schema"] != "dm-session-source-query-v1"
            || item["row"] != "source_occurrence"
            || item["source_revision"].as_str() != revision
            || item["occurrence"].as_u64() != Some(u64::from(start) + index as u64)
            || item["provenance_complete"] != false
        {
            return Err(invalid());
        }
    }
    Ok(())
}
pub(super) fn validate_requested(reply: &QueryReply, queries: &[SourceQuery]) -> io::Result<()> {
    let mut requested = queries.iter().filter_map(|query| match query {
        SourceQuery::OccurrencesPage { start, limit } => Some((*start, *limit)),
        _ => None,
    });
    for line in reply.jsonl.lines() {
        let row: serde_json::Value = serde_json::from_str(line).map_err(io::Error::other)?;
        if row["row"] == "source_occurrences_page" {
            let expected = requested.next().ok_or_else(invalid)?;
            if (number(&row, "start")?, number(&row, "limit")?) != expected {
                return Err(invalid());
            }
        }
    }
    if requested.next().is_some() {
        return Err(invalid());
    }
    Ok(())
}
