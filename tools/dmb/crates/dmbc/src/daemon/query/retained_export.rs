//! Export selectors already issued by a retained session, never a cold build.
//! The format deliberately differs from the full source/executable analysis export.
//! Consumers must require the finished footer: a stale/evicted snapshot or broken
//! transport may leave an explicitly incomplete stream. Pins never auto-refresh.
//! CLI: `query REQUEST.json --export-jsonl --max-items 2000000 --max-pages 20000`.
//! Defaults remain 524288 rows/4096 pages; maxima are 16777216/131072.
//! Output stays streamed in <=512 KiB frames, <=128 rows/page, with a 300s watchdog.
use super::{Catalog, QueryRequest, TraversalLimits, VisitControl};
use std::io::{self, Read, Write};
use std::time::Instant;
const SCHEMA: &str = "dm-session-retained-export-v1";
const SCOPE: &str = "semantic type facts, authored member metadata, captured engine intrinsic selectors, current parser-issued source occurrences, and source body contexts";

/// Aggregate streaming quotas; frame/page sizes and the watchdog remain fixed.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct ExportLimits {
    pub max_items: u32,
    pub max_pages: u32,
}
impl Default for ExportLimits {
    fn default() -> Self {
        Self {
            max_items: 524288,
            max_pages: 4096,
        }
    }
}
impl ExportLimits {
    pub fn validate(self) -> io::Result<Self> {
        if !(1..=16777216).contains(&self.max_items) || !(1..=131072).contains(&self.max_pages) {
            return Err(io::Error::new(
                io::ErrorKind::InvalidInput,
                "export quotas require items 1..16777216 and pages 1..131072",
            ));
        }
        Ok(self)
    }
}
pub fn run_export_file(
    path: &std::path::Path,
    limits: ExportLimits,
) -> Result<(), Box<dyn std::error::Error>> {
    let limits = limits.validate()?;
    let mut bytes = Vec::new();
    std::fs::File::open(path)?
        .take((super::super::MAX_REQUEST + 1) as u64)
        .read_to_end(&mut bytes)?;
    if bytes.len() > super::super::MAX_REQUEST {
        return Err("query request file exceeds 64 KiB".into());
    }
    let request: QueryRequest = serde_json::from_slice(&bytes)?;
    let mut output = io::BufWriter::new(io::stdout().lock());
    export_with_limits(&request, &mut output, limits, super::super::execute)?;
    output.flush()?;
    Ok(())
}
fn emit(output: &mut impl Write, row: &serde_json::Value) -> io::Result<()> {
    serde_json::to_writer(&mut *output, row)?;
    output.write_all(b"\n")
}
#[cfg(test)]
fn export_with(
    request: &QueryRequest,
    output: &mut impl Write,
    execute: impl FnMut(QueryRequest) -> Result<super::super::QueryReply, Box<dyn std::error::Error>>,
) -> Result<(), Box<dyn std::error::Error>> {
    export_with_limits(request, output, ExportLimits::default(), execute)
}
fn export_with_limits(
    request: &QueryRequest,
    output: &mut impl Write,
    aggregate: ExportLimits,
    mut execute: impl FnMut(
        QueryRequest,
    ) -> Result<super::super::QueryReply, Box<dyn std::error::Error>>,
) -> Result<(), Box<dyn std::error::Error>> {
    let aggregate = aggregate.validate()?;
    if request.expected_revision.is_none()
        || request.expected_source_revision.is_none()
        || !request.queries.is_empty()
        || !request.source_queries.is_empty()
    {
        return Err(io::Error::new(
            io::ErrorKind::InvalidInput,
            "retained export requires both revision pins and empty query rosters",
        )
        .into());
    }
    request.validate()?;
    let began = Instant::now();
    let mut pages = 0;
    let mut items = 0;
    emit(
        output,
        &serde_json::json!({"schema":SCHEMA,"row":"retained_export",
                        "compiler_version":env!("CARGO_PKG_VERSION"),"query_schema":"dm-session-query-v2",
                        "semantic_revision":request.expected_revision,"source_revision":request.expected_source_revision,
                        "aggregate_max_items":aggregate.max_items,"aggregate_max_pages":aggregate.max_pages,"frame_max_bytes":524288,"page_max_items":128,"watchdog_seconds":300,
                        "item_scope":SCOPE,"complete":false,"executable_facts_included":false,
                        "full_member_metadata_included":true,"source_body_contexts_included":true,"resolved_references_included":false,
                        "source_locations_included":true,"source_span_precision":"logical_line","provenance_complete":false}),
    )?;
    for catalog in [
        Catalog::Types,
        Catalog::Members,
        Catalog::Intrinsics,
        Catalog::Occurrences,
        Catalog::BodyContexts,
    ] {
        let limits = TraversalLimits {
            max_pages: aggregate.max_pages.saturating_sub(pages),
            max_items: aggregate.max_items.saturating_sub(items),
            ..Default::default()
        };
        let result = super::visit_catalog_with(
            request,
            catalog,
            limits,
            || {
                if began.elapsed() >= limits.elapsed {
                    Err(io::Error::new(
                        io::ErrorKind::TimedOut,
                        "retained export elapsed limit reached",
                    ))
                } else {
                    Ok(())
                }
            },
            |item| {
                if item["row"] == "source_occurrence" {
                    // Preserve the original full-analysis occurrence row while
                    // the source query API retains its established target object.
                    let mut row = item.clone();
                    row["row"] = "occurrence".into();
                    let target_key = row["target_key"].take();
                    row["target"] = target_key;
                    row.as_object_mut()
                        .expect("validated source row")
                        .remove("target_key");
                    emit(output, &row)?;
                } else {
                    emit(output, item)?;
                }
                Ok(VisitControl::Continue)
            },
            &mut execute,
        )?;
        pages += result.pages;
        items += result.visited;
        emit(
            output,
            &serde_json::json!({"schema":SCHEMA,"row":"retained_roster_complete",
            "semantic_revision":result.revision,"source_revision":result.source_revision,
            "roster":match catalog {Catalog::Types=>"types",Catalog::Members=>"members",
                Catalog::Intrinsics=>"intrinsics",Catalog::Occurrences=>"occurrences",Catalog::BodyContexts=>"body_contexts"},
            "total":result.total,"pages":result.pages,"roster_finished":result.roster_finished,
            "intrinsic_inventory_complete":result.intrinsic_inventory_complete,
            "hierarchy_certified":result.hierarchy_certified,"complete":false}),
        )?;
    }
    emit(
        output,
        &serde_json::json!({"schema":SCHEMA,"row":"retained_export_finished",
        "semantic_revision":request.expected_revision,"source_revision":request.expected_source_revision,
        "compiler_version":env!("CARGO_PKG_VERSION"),"query_schema":"dm-session-query-v2",
        "item_scope":SCOPE,"items":items,"pages":pages,"rosters_finished":true,"complete":false}),
    )?;
    Ok(())
}

#[cfg(test)]
#[path = "retained_export_tests.rs"]
mod tests;
