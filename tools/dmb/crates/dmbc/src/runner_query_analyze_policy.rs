//! Explicit analyze-policy fixture admission over the already captured native request.
//! No filesystem reads, parser/model construction or baseline mutation occurs here.
use super::SourceSnapshot;
// A source feature accidentally enabled by another dependency must not quietly
// re-link the retired frontend into the native host.
const _: () = assert!(
    !dq_analyze::LEGACY_SEMANTICS_ENABLED,
    "native compiler host requires dq-analyze without legacy-sem"
);
use dq_analyze::captured_policy_metadata::LINTS;
use std::{io, path::Path, sync::Arc};
impl SourceSnapshot {
    pub(crate) fn write_native_analyze_policy_fixture(
        &self,
        root: &Path,
        configuration: &Path,
        lints: &[String],
        tree: &dm_tree::SemanticTree,
        output: &mut impl io::Write,
    ) -> io::Result<()> {
        crate::daemon::control::checkpoint()?;
        // Acquired-byte encoding proof is required even before a warm cache hit.
        self.require_semantic_source_encoding()?;
        self.named_policy_capture(tree)?;
        if !root.is_absolute() || !configuration.is_absolute() {
            return Err(io::Error::new(
                io::ErrorKind::InvalidInput,
                "analyze-policy paths must be caller-absolute",
            ));
        }
        if !self.matches_tree(tree) {
            return Err(io::Error::other("analyze policy semantic snapshot differs"));
        }
        let pin = self.policy_revision.ok_or_else(|| {
            io::Error::other("analyze policy requires an explicitly bound captured policy revision")
        })?;
        let captured = self
            .native_policy_inputs
            .as_ref()
            .ok_or_else(|| io::Error::other("analyze policy inputs unavailable"))?;
        if captured.policy_revision() != Some(pin) {
            return Err(io::Error::other(
                "analyze policy receipt differs from snapshot",
            ));
        }
        let bytes = captured.configuration_bytes(configuration)?;
        let queries = self
            .native_raw_queries
            .as_ref()
            .ok_or_else(|| io::Error::other("compiler analyze-policy query graph unavailable"))?;
        let input = queries.raw_cohort(Arc::clone(captured), root, configuration)?;
        let results = queries.analyze_fixture_findings(&input, lints)?;
        results.validate_for(&input)?;
        let results = results.runs;
        crate::daemon::control::checkpoint()?;
        let results=results.into_iter().map(|run|serde_json::json!({"name":run.name,"sites":run.run.sites,"allow_used":run.allow_used,"notes":run.run.notes})).collect::<Vec<_>>();
        // Write only after the complete admitted cohort succeeds; never emit
        // a partial/clean row after an unsupported or cancelled policy.
        serde_json::to_writer(&mut *output,&serde_json::json!({
            "row":"source_native_analyze_policy_fixture","schema":"dm-session-source-query-v1",
            "source_revision":format!("{:032x}",self.source_revision),"policy_revision":format!("{pin:032x}"),
            "semantic_revision":format!("{:032x}",tree.identity()),"root":root,"configuration":configuration,
            "requested_lints":lints,"lint_whitelist":LINTS,"scope":"explicit_captured_files",
            "full_policy_parity":false,"baseline_applied":false,"admission":"native_semantic_findings",
            "configuration_scope":if bytes.is_some(){"captured_configuration_bytes"}else{"proven_missing_configuration"},
            "fixture_limits":{"per_file_bytes":dq_analyze::captured_raw_policy::MAX_FIXTURE_FILE_BYTES,
                "total_bytes":dq_analyze::captured_raw_policy::MAX_FIXTURE_TOTAL_BYTES,
                "sites":dq_analyze::captured_raw_policy::MAX_FIXTURE_SITES,
                "contract":"fixture_admission_not_cpu_or_rss"},
            "results":results,
        })).map_err(io::Error::other)?;
        output.write_all(b"\n")
    }
}
