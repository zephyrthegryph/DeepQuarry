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
    let frontend = build(Path::new(&project), &Files, &Default::default(), 1)
        .map_err(|errors| format!("native frontend failed: {errors:?}"))?;
    let bodies = BodyArena::new_typed(&frontend, |_| true);
    for occurrence in frontend.bodies.iter() {
        bodies.with_parsed(occurrence, |body| -> Result<(), String> {
            let view = BodyView::new(&frontend, body)?;
            for diagnostic in view.ambiguous_not_bitwise(Severity::Warning) {
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
