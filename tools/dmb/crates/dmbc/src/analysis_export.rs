//! Explicit executable analysis over the same current issued bodies as lowering.
use dm_tree::frontend::{BodyArena, ColdFrontend};
use std::io::Write;
pub(crate) fn write_bodies(
    frontend: &ColdFrontend,
    writer: &mut impl Write,
) -> Result<usize, Box<dyn std::error::Error>> {
    let arena = BodyArena::new_typed(frontend, |_| true);
    let mut count = 0;
    for occurrence in frontend.bodies.iter() {
        let body = arena
            .take_parsed(occurrence)
            .map_err(|error| error.message)?;
        match dm_analysis::typed_body_jsonl::write_jsonl(&body, writer) {
            Ok(_) => (),
            Err(dm_analysis::typed_body_jsonl::ExportError::NoTypedModel(error)) => {
                serde_json::to_writer(
                    &mut *writer,
                    &serde_json::json!({
                        "schema": dm_analysis::typed_body_jsonl::SCHEMA,
                        "row":"unsupported_body", "member":occurrence.member.0,
                        "declaration":occurrence.declaration.0,
                        "semantic_resolution_complete":false,"reason":error.to_string()
                    }),
                )?;
                writer.write_all(b"\n")?;
            }
            Err(error) => return Err(error.into()),
        }
        match dm_analysis::typed_body::lexical::analyze(frontend, &body, None) {
            Ok(lexical) => {
                dm_analysis::typed_body::lexical::jsonl::write_jsonl(&lexical, writer)?;
            }
            Err(error) => {
                serde_json::to_writer(
                    &mut *writer,
                    &serde_json::json!({
                        "schema":"dm-lexical-body-analysis-v1", "row":"unsupported_body",
                        "member":occurrence.member.0,"declaration":occurrence.declaration.0,
                        "semantic_resolution_complete":false,"reason":error.to_string()
                    }),
                )?;
                writer.write_all(b"\n")?;
            }
        }
        count += 1;
    }
    Ok(count)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::Path;
    struct Source;
    impl dm_preprocess::SourceProvider for Source {
        fn read(&self, _: &Path) -> Result<String, String> {
            Ok("/datum/x/proc/first(x)\n    var/y = x\n    return y\n/datum/x/proc/second(z)\n    return z\n".into())
        }
    }
    #[test]
    fn exports_each_current_body_with_explicit_resolution_status() {
        let frontend =
            dm_tree::frontend::build(Path::new("project.dme"), &Source, &Default::default(), 1)
                .unwrap();
        let mut bytes = Vec::new();
        assert_eq!(write_bodies(&frontend, &mut bytes).unwrap(), 2);
        let rows: Vec<serde_json::Value> = std::str::from_utf8(&bytes)
            .unwrap()
            .lines()
            .map(|line| serde_json::from_str(line).unwrap())
            .collect();
        assert!(rows
            .iter()
            .any(|row| row["schema"] == "dm-lexical-body-analysis-v1"));
        assert!(rows
            .iter()
            .filter(|row| row["schema"] == "dm-lexical-body-analysis-v1")
            .all(|row| row["semantic_resolution_complete"] != true));
    }
}
