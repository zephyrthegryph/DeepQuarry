//! Independent bounded field-static-type oracle, original compiler owner + DB.
use dm_analysis::{checker_context::CheckerContext, checks::Severity};
use dm_tree::frontend::{build_with_config, FrontendConfig};
use std::{path::Path, sync::Arc};
#[path = "../../dm-analysis/examples/support/acquired_files.rs"]
mod acquired_files;
#[path = "../../dm-analysis/examples/support/reference_hierarchy.rs"]
mod reference_hierarchy;
use acquired_files::AcquiredFiles;
fn main() -> Result<(), Box<dyn std::error::Error>> {
    let project = std::env::args().nth(1).ok_or("expected project")?;
    let family = std::env::args()
        .nth(2)
        .unwrap_or_else(|| "field_access_static_type".into());
    if family != "field_access_static_type" {
        return Err("unsupported family".into());
    }
    let seed = reference_hierarchy::seed();
    let files = AcquiredFiles::default();
    let db = Arc::new(dmbc::query_db::QueryDb::default());
    let front = build_with_config(
        Path::new(&project),
        &files,
        &Default::default(),
        FrontendConfig {
            workers: 1,
            engine: Some(&seed),
            observer: None,
        },
    )
    .map_err(|e| format!("native frontend failed: {e:?}"))?
    .with_body_queries(db.clone());
    let archive = front.body_archive().ok_or("original archive unavailable")?;
    let tree = archive.tree();
    let profile = tree
        .checker_builtin_profile()
        .ok_or("checker profile unavailable")?;
    let context = CheckerContext::archived(&archive, db.as_ref(), tree, profile)?;
    let mut output = Vec::new();
    for (ordinal, _) in dm_analysis::checker_order::bodies(&front)? {
        let body = archive.parse(ordinal).map_err(|e| e.message)?;
        for row in context.fields_archived(&body, Severity::Warning)? {
            let original = archive.source_note_point(row.span.start)?;
            output.push(
                serde_json::json!({"family":row.family,"severity":"warning","file":original.path,
                "line":original.line,"expanded_column":original.byte_column,"message":row.message,
                "notes":row.notes.iter().map(|n|n.legacy_text()).collect::<Vec<_>>()}),
            );
        }
    }
    for row in output {
        println!("{row}");
    }
    Ok(())
}
