//! Explicit migration oracle. This does not change any production checker gate.
use dm_analysis::checks::{BodyView, Severity};
use dm_tree::frontend::{build, BodyArena};
use std::path::Path;

struct Files;
impl dm_preprocess::SourceProvider for Files {
    fn read(&self, path: &Path) -> Result<String, String> {
        std::fs::read_to_string(path).map_err(|error| error.to_string())
    }
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let project = std::env::args().nth(1).ok_or("expected a .dme path")?;
    let family = std::env::args()
        .nth(2)
        .unwrap_or_else(|| "ambiguous_not_bitwise".into());
    if !matches!(
        family.as_str(),
        "ambiguous_not_bitwise" | "ambiguous_in_lhs" | "invalid_set_value"
    ) {
        return Err("unknown native checker family".into());
    }
    let frontend = build(Path::new(&project), &Files, &Default::default(), 1)
        .map_err(|errors| format!("native frontend failed: {errors:?}"))?;
    let bodies = BodyArena::new_typed(&frontend, |_| true);
    for (_, occurrence) in dm_analysis::checker_order::bodies(&frontend)? {
        bodies.with_parsed(occurrence, |body| -> Result<(), String> {
            let view = BodyView::new(&frontend, body)?;
            let diagnostics = match family.as_str() {
                "ambiguous_not_bitwise" => view.ambiguous_not_bitwise(Severity::Warning),
                "ambiguous_in_lhs" => view.ambiguous_in_lhs(Severity::Warning)?,
                "invalid_set_value" => dm_analysis::checks_invalid_set::check(&view, Severity::Warning)?,
                _ => unreachable!(),
            };
            for diagnostic in diagnostics {
                let source = view.location(&diagnostic).ok_or("diagnostic has no origin")?;
                println!("{}", serde_json::json!({
                    "family": diagnostic.family, "severity": "warning",
                    "file": source.path, "line": source.line,
                    // Expanded column is an explicit fixture observation, not
                    // an inverse macro-substitution/source provenance claim.
                    "expanded_column": frontend.expanded.text[..diagnostic.span.start]
                        .rsplit('\n').next().unwrap().chars().count() + 1,
                    "message": diagnostic.message,
                    "notes": diagnostic.notes.iter().map(|note| &note.message).collect::<Vec<_>>(),
                }));
            }
            Ok(())
        }).map_err(|error| error.message)??;
    }
    Ok(())
}
