//! Serialization of coordinates already bound by the compiler's current query.
//! This DTO is not an artifact admission certificate and performs no parsing.
use super::*;
use dm_tree::frontend::{BodyOccurrence, SourceLocation};
use std::ops::Range;

pub struct BoundReference<'a> {
    pub name: SymbolId,
    pub spelling: Option<&'a str>,
    pub meaning: &'a SelectedMeaning,
    pub path: &'a [NodeStep],
    pub source: &'a SourceLocation,
    pub expanded_span: &'a Range<usize>,
}
#[derive(Clone, Copy, Debug, Default)]
pub struct SelectionCoverage {
    pub complete: bool,
    pub unavailable_coordinates: usize,
    pub unbound_selections: usize,
}
/// The caller must supply its opaque current query result after exact body-key
/// and resolver-read admission. Standalone authored facts use write_jsonl instead.
pub fn write_bound_jsonl<'a>(
    occurrence: &BodyOccurrence,
    rows: impl IntoIterator<Item = BoundReference<'a>>,
    coverage: SelectionCoverage,
    writer: &mut impl Write,
) -> Result<usize, String> {
    let mut count = 0;
    for row in rows {
        let mut value = reference_json(
            occurrence,
            row.name,
            row.spelling,
            row.meaning,
            row.path,
            row.expanded_span.start,
            row.expanded_span.end,
        );
        value["source"] = serde_json::json!({"file":row.source.semantic_path.as_ref(),"line":row.source.line,
            "span":[row.source.span.start,row.source.span.end],"encounter":row.source.encounter_ordinal,
            "include_occurrence":row.source.include_occurrence,"include_chain":row.source.include_chain.as_ref()});
        serde_json::to_writer(&mut *writer, &value).map_err(|error| error.to_string())?;
        writer.write_all(b"\n").map_err(|error| error.to_string())?;
        count += 1;
    }
    serde_json::to_writer(&mut *writer,&serde_json::json!({"schema":SCHEMA,"row":"selected_reference_summary",
        "member":occurrence.member.0,"declaration":occurrence.declaration.0,"references":count,
        "semantic_resolution_complete":coverage.complete,
        "coverage_policy":std::str::from_utf8(dm_ir::SELECTED_REFERENCES_POLICY).expect("ASCII policy"),
        "unavailable_coordinates":coverage.unavailable_coordinates,"unbound_selections":coverage.unbound_selections})).map_err(|error|error.to_string())?;
    writer.write_all(b"\n").map_err(|error| error.to_string())?;
    Ok(count)
}
