//! Export selectors already issued by a retained session, never a cold build.
//! The format deliberately differs from the full source/executable analysis export.
//! Consumers must require the finished footer: a stale/evicted snapshot or broken
//! transport may leave an explicitly incomplete stream. Pins never auto-refresh.
use super::{Catalog, QueryRequest, TraversalLimits, VisitControl};
use std::io::{self, Read, Write};
use std::time::Instant;
const SCHEMA: &str = "dm-session-retained-export-v1";
const SCOPE: &str = "semantic type selectors, authored member selectors, captured engine intrinsic selectors, and current parser-issued source occurrences";

pub fn run_export_file(path: &std::path::Path) -> Result<(), Box<dyn std::error::Error>> {
    let mut bytes = Vec::new();
    std::fs::File::open(path)?
        .take((super::super::MAX_REQUEST + 1) as u64)
        .read_to_end(&mut bytes)?;
    if bytes.len() > super::super::MAX_REQUEST {
        return Err("query request file exceeds 64 KiB".into());
    }
    let request: QueryRequest = serde_json::from_slice(&bytes)?;
    let mut output = io::BufWriter::new(io::stdout().lock());
    export_with(&request, &mut output, super::super::execute)?;
    output.flush()?;
    Ok(())
}
fn emit(output: &mut impl Write, row: &serde_json::Value) -> io::Result<()> {
    serde_json::to_writer(&mut *output, row)?;
    output.write_all(b"\n")
}
fn export_with(
    request: &QueryRequest,
    output: &mut impl Write,
    mut execute: impl FnMut(
        QueryRequest,
    ) -> Result<super::super::QueryReply, Box<dyn std::error::Error>>,
) -> Result<(), Box<dyn std::error::Error>> {
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
                        "item_scope":SCOPE,"complete":false,"executable_facts_included":false,
                        "full_member_metadata_included":false,"resolved_references_included":false,
                        "provenance_complete":false}),
    )?;
    for catalog in [
        Catalog::Types,
        Catalog::Members,
        Catalog::Intrinsics,
        Catalog::Occurrences,
    ] {
        let limits = TraversalLimits {
            max_pages: 4096 - pages,
            max_items: 524288 - items,
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
                emit(output, item)?;
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
                Catalog::Intrinsics=>"intrinsics",Catalog::Occurrences=>"occurrences"},
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
