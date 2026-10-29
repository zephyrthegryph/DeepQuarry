//! Explicit migration oracle. This does not change any production checker gate.
use dm_analysis::checks::{BodyView, Severity};
use dm_tree::frontend::{build, BodyArena};
use std::path::Path;

#[path = "support/acquired_files.rs"]
mod acquired_files;
use acquired_files::AcquiredFiles;
fn main() -> Result<(), Box<dyn std::error::Error>> {
    let project = std::env::args().nth(1).ok_or("expected a .dme path")?;
    let family = std::env::args()
        .nth(2)
        .unwrap_or_else(|| "ambiguous_not_bitwise".into());
    if !matches!(
        family.as_str(),
        "ambiguous_not_bitwise"
            | "ambiguous_in_lhs"
            | "invalid_set_value"
            | "control_condition_static"
            | "unreachable_code"
            | "loop_condition_determinate"
            | "if_condition_determinate"
            | "set_has_no_effect"
            | "control_policies"
    ) {
        return Err("unknown native checker family".into());
    }
    let files = AcquiredFiles::default();
    let frontend = build(Path::new(&project), &files, &Default::default(), 1)
        .map_err(|errors| format!("native frontend failed: {errors:?}"))?;
    let bodies = BodyArena::new_typed(&frontend, |_| true);
    let mut output = Vec::new();
    for (_, occurrence) in dm_analysis::checker_order::bodies(&frontend)? {
        bodies.with_parsed(occurrence, |body| -> Result<(), String> {
            let view = BodyView::new(&frontend, body)?;
            let diagnostics = match family.as_str() {
                "control_policies" => dm_analysis::checks_control_policies::check(&view, &[
                    (dm_analysis::checks_control_policies::Family::Static,Severity::Error),
                    (dm_analysis::checks_control_policies::Family::Unreachable,Severity::Error),
                    (dm_analysis::checks_control_policies::Family::LoopDeterminate,Severity::Error),
                    (dm_analysis::checks_control_policies::Family::IfDeterminate,Severity::Error),
                    (dm_analysis::checks_control_policies::Family::SettingPlacement,Severity::Error),
                ])?,
                "ambiguous_not_bitwise" => view.ambiguous_not_bitwise(Severity::Warning),
                "ambiguous_in_lhs" => view.ambiguous_in_lhs(Severity::Warning)?,
                "invalid_set_value" => dm_analysis::checks_invalid_set::check(&view, Severity::Warning)?,
                "control_condition_static" => dm_analysis::checks_control_static::check(&view, Severity::Error)?,
                "unreachable_code" => dm_analysis::checks_flow::check(&view, dm_analysis::checks_flow::Family::Unreachable, Severity::Error)?,
                "loop_condition_determinate" => dm_analysis::checks_flow::check(&view, dm_analysis::checks_flow::Family::LoopDeterminate, Severity::Error)?,
                "if_condition_determinate" => dm_analysis::checks_flow::check(&view, dm_analysis::checks_flow::Family::IfDeterminate, Severity::Error)?,
                "set_has_no_effect" => dm_analysis::checks_set_no_effect::check(&view, Severity::Error)?,
                _ => unreachable!(),
            };
            for diagnostic in diagnostics {
                let source=frontend.source_export_mapping().ok_or("original mapping unavailable")?.source_note_point(diagnostic.span.start)?;
                output.push( serde_json::json!({
                    "family": diagnostic.family, "severity": match diagnostic.severity { Severity::Warning => "warning", Severity::Error => "error", Severity::Disabled => return Err("disabled diagnostic was emitted".into()) },
                    "file": source.path, "line": source.line,
                    // Historical key, authenticated ORIGINAL UTF8 byte column.
                    "expanded_column": source.byte_column,
                    "message": diagnostic.message,
                    "notes": diagnostic.notes.iter().map(|note|note.legacy_text()).collect::<Vec<_>>(),
                }));
            }
            Ok(())
        }).map_err(|error| error.message)??;
    }
    for row in output {
        println!("{row}");
    }
    Ok(())
}
