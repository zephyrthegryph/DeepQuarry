//! Native policy executes inside the existing compiler session. Only findings
//! leave this boundary; raw-marker policy facts are captured before the frontend
//! is released, never reread from a changing worktree during a pinned query.
use super::SourceSnapshot;
use dm_analysis::{untyped_native, value_program::Values, value_schemas::Schemas};
use dm_tree::frontend::ColdFrontend;
use std::{io, path::Path};

pub(super) fn capture_schemas(frontend: &ColdFrontend) -> Result<Schemas, String> {
    let mut schemas = Schemas::default();
    for file in frontend.files.iter() {
        if file.captured {
            schemas.read_source(file.text.as_str())?;
        }
    }
    Ok(schemas)
}
pub(super) fn capture_policy_schemas(
    inputs: &dm_analysis::policy_inputs::PolicyInputs,
) -> Result<Schemas, String> {
    use dm_analysis::policy_inputs::{PolicyRole, TextView};
    let mut schemas = Schemas::default();
    for file in inputs
        .files()
        .filter(|file| file.role() == PolicyRole::DmSource)
    {
        schemas.read_source(
            file.view(TextView::AnalyzeRaw)
                .map_err(|error| error.to_string())?
                .as_str(),
        )?;
    }
    Ok(schemas)
}
impl SourceSnapshot {
    /// Explicitly bounded migration endpoint. Full Analyze admission/config and
    /// raw noncompiled workspace coverage are not represented by this fixture.
    pub(crate) fn write_native_untyped_fixture(
        &self,
        root: &Path,
        tree: &dm_tree::SemanticTree,
        output: &mut impl io::Write,
    ) -> io::Result<()> {
        crate::daemon::control::checkpoint()?;
        self.require_semantic_source_encoding()?;
        let archive = self
            .body_archive
            .as_ref()
            .filter(|a| a.matches_tree(tree))
            .ok_or_else(|| io::Error::other("current native policy archive unavailable"))?;
        // Bound synchronous migration work until policy jobs expose checkpoints
        // inside all equation extraction/SCC phases. Never silently truncate.
        if archive.len() > 128 {
            return Err(io::Error::other(
                "native untyped fixture exceeds 128-body migration budget",
            ));
        }
        let schemas = self
            .native_schema_markers
            .as_ref()
            .map_err(|error| io::Error::other(error.clone()))?;
        let input = self
            .native_value_input
            .as_ref()
            .ok_or_else(|| io::Error::other("native value query input unavailable"))?;
        let queries = self
            .native_value_queries
            .as_ref()
            .ok_or_else(|| io::Error::other("compiler value query graph unavailable"))?;
        let proof = input.obtain(queries.as_ref()).map_err(io::Error::other)?;
        let values = Values::from_archive_input(input, proof).map_err(io::Error::other)?;
        crate::daemon::control::checkpoint()?;
        let rows =
            untyped_native::archived_findings(archive, &values, schemas, root, &[], |_| false)
                .map_err(io::Error::other)?;
        crate::daemon::control::checkpoint()?;
        let rows: Vec<_> = rows
            .into_iter()
            .map(|row| {
                serde_json::json!({
                    "rule":row.rule.name(),"file":row.file,"line":row.line,
                    "message":row.message,"identity":row.identity
                })
            })
            .collect();
        let raw_marker_scope = if self.native_policy_inputs.is_some() {
            "explicit_captured_files"
        } else {
            "captured_compiled_sources"
        };
        let mut row = serde_json::json!({
            "row":"source_native_untyped_fixture","schema":"dm-session-source-query-v1","root":root,
            "source_revision":format!("{:032x}", self.source_revision),
            "semantic_revision":format!("{:032x}", tree.identity()),
            "full_policy_parity":false,"raw_marker_scope":raw_marker_scope,
            "admission":"raw_findings","findings":rows,
        });
        if let Some(policy) = self.policy_revision {
            row["policy_revision"] = format!("{policy:032x}").into();
        }
        serde_json::to_writer(&mut *output, &row).map_err(io::Error::other)?;
        output.write_all(b"\n")
    }
}
