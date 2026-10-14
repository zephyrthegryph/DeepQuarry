//! Validate one bounded source answer carrying previously issued selected JSONL.
use std::io;
pub(super) fn validate(row: &serde_json::Value, revision: Option<&str>) -> io::Result<()> {
    let invalid = || {
        io::Error::new(
            io::ErrorKind::InvalidData,
            "invalid selected-reference source envelope",
        )
    };
    if revision.is_none()
        || row["schema"] != "dm-session-source-query-v1"
        || row["row"] != "source_selected_references"
        || row["source_revision"].as_str() != revision
        || row["complete"] != false
    {
        return Err(invalid());
    }
    let ordinal = row["occurrence"]
        .as_u64()
        .filter(|value| *value <= u64::from(u32::MAX))
        .ok_or_else(invalid)?;
    let text = row["captured_jsonl"].as_str().ok_or_else(invalid)?;
    let mut references = 0u64;
    let mut summary = false;
    for line in text.lines() {
        let value: serde_json::Value = serde_json::from_str(line).map_err(io::Error::other)?;
        if summary
            || value["schema"] != dm_analysis::typed_body::selected::SCHEMA
            || value["declaration"].as_u64() != Some(ordinal)
        {
            return Err(invalid());
        }
        match value["row"].as_str() {
            Some("selected_reference") => references += 1,
            Some("selected_reference_summary")
                if value["semantic_resolution_complete"] == false
                    && value["references"].as_u64() == Some(references) =>
            {
                summary = true
            }
            _ => return Err(invalid()),
        }
    }
    if !summary {
        return Err(invalid());
    }
    Ok(())
}
