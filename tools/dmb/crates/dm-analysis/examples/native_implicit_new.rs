//! Exact implicit-new missing-hint cohort over original-owner native events.
use dm_analysis::{checker_context::CheckerContext, checker_order, checks::Severity};
use dm_tree::frontend::{build_with_config, BodyArena, FrontendConfig};
use std::path::Path;
#[path = "support/acquired_files.rs"]
mod acquired_files;
#[path = "support/reference_hierarchy.rs"]
mod reference_hierarchy;
use acquired_files::AcquiredFiles;
fn main() -> Result<(), Box<dyn std::error::Error>> {
    let project = std::env::args().nth(1).ok_or("expected .dme")?;
    let family = std::env::args()
        .nth(2)
        .unwrap_or_else(|| "no_typehint_implicit_new".into());
    if family != "no_typehint_implicit_new" {
        return Err("this bounded oracle supports only no_typehint_implicit_new routing".into());
    }
    let seed = reference_hierarchy::seed();
    let files = AcquiredFiles::default();
    let frontend = build_with_config(
        Path::new(&project),
        &files,
        &Default::default(),
        FrontendConfig {
            workers: 1,
            engine: Some(&seed),
            observer: None,
        },
    )
    .map_err(|e| format!("native frontend failed: {e:?}"))?;
    let resolver = frontend.snapshot.tree.as_ref();
    let profile = resolver
        .checker_builtin_profile()
        .ok_or("compiled hierarchy is incompatible with checker profile")?;
    let context = CheckerContext::live(&frontend, resolver, profile)?;
    let arena = BodyArena::new_typed(&frontend, |_| true);
    let mut output = Vec::new();
    for (_, occurrence) in checker_order::bodies(&frontend)? {
        arena.with_parsed(occurrence,|body|->Result<(),String> {
            for row in context.implicit_new_live(&frontend,body,Severity::Error)? {
                let source=frontend.source_export_mapping().ok_or("original mapping unavailable")?.source_note_point(row.span.start)?;
                output.push(serde_json::json!({"family":row.family,"severity":"error","file":source.path,"line":source.line,
                    "expanded_column":source.byte_column,
                    "message":row.message,"notes":row.notes.iter().map(|n|n.legacy_text()).collect::<Vec<_>>()}));
            }
            Ok(())
        }).map_err(|e|e.message)??;
    }
    for row in output {
        println!("{row}");
    }
    Ok(())
}
