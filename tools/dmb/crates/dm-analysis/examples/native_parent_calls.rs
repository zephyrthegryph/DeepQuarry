//! Bounded independent checker oracle, not production runtime configuration.
use dm_analysis::{checker_order, checks::Severity, checks_parent_call};
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
        .unwrap_or_else(|| "proc_has_no_parent".into());
    if family != "proc_has_no_parent" {
        return Err("this bounded oracle supports only proc_has_no_parent".into());
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
    // Borrow the original compiler owner. Checker-qualified facts are immutable
    // resolver inputs; selecting them never decorates or clones the source tree.
    let resolver = frontend.snapshot.tree.as_ref();
    let profile = resolver
        .checker_builtin_profile()
        .ok_or("compiled hierarchy is incompatible with checker profile")?;
    let arena = BodyArena::new_typed(&frontend, |_| true);
    let mut output = Vec::new();
    for (_, occurrence) in checker_order::bodies(&frontend)? {
        arena.with_parsed(occurrence,|body|->Result<(),String> {
            let diagnostics=checks_parent_call::check_in_profile(&frontend,body,resolver,Some(profile),Severity::Error)?;
            for row in diagnostics {
                let location=frontend.source_export_mapping().ok_or("original mapping unavailable")?.original_note_origin(row.span.start)?;
                output.push(serde_json::json!({"family":row.family,"severity":"error","file":location.path,"line":location.line,
                    "expanded_column":location.byte_column,
                    "message":row.message,"notes":row.notes.iter().map(|note|note.legacy_text()).collect::<Vec<_>>()}));
            }
            Ok(())
        }).map_err(|e|e.message)??;
    }
    for row in output {
        println!("{row}");
    }
    Ok(())
}
