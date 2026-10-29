//! Configured control-policy union over one exact retained source owner.
//! The union is request-local: existing QueryDb syntax is reused, but borrowed
//! walk events never escape and no sibling cache requires invalidation/eviction.
use super::{named_policy, SourceSnapshot};
use dm_analysis::{check_policy::DiagnosticSeverity, checks_configured_control::Plan};
use std::{io, path::Path};
fn level(value: DiagnosticSeverity) -> &'static str {
    match value {
        DiagnosticSeverity::Error => "error",
        DiagnosticSeverity::Warning => "warning",
        DiagnosticSeverity::Info => "info",
        DiagnosticSeverity::Hint => "hint",
    }
}
impl SourceSnapshot {
    pub(crate) fn write_native_configured_control_batch(
        &self,
        ordinal: u32,
        families: &[String],
        environment: &Path,
        explicit: Option<&Path>,
        tree: &dm_tree::SemanticTree,
        output: &mut impl io::Write,
    ) -> io::Result<()> {
        crate::daemon::control::checkpoint()?;
        let capture = self.named_policy_capture(tree)?;
        // Parse exact captured configuration once, then select one pure union.
        let loaded = named_policy::configuration(capture, environment, explicit)?;
        let plan = Plan::new(families, &loaded.policy).map_err(io::Error::other)?;
        let archive = capture.policy().archive();
        if ordinal as usize >= archive.len() {
            return Err(io::Error::other("body ordinal unavailable"));
        }
        let mut diagnostics = Vec::new();
        if plan.enabled() {
            let body = archive
                .parse(ordinal as usize)
                .map_err(|error| io::Error::other(error.message))?;
            // Exactly one combined flow traversal, regardless of family count.
            for finding in plan.archived(&body).map_err(io::Error::other)? {
                crate::daemon::control::checkpoint()?;
                let d = finding.diagnostic;
                let origin = archive
                    .source_note_point(d.span.start)
                    .map_err(io::Error::other)?;
                diagnostics.push(serde_json::json!({"family":d.family,"severity":level(finding.severity),"file":origin.path,"line":origin.line,
                    "expanded_span":[d.span.start,d.span.end],"expression_span":[d.expression_span.start,d.expression_span.end],"message":d.message,"notes":d.notes.iter().map(|n|n.legacy_text()).collect::<Vec<_>>()}));
            }
        }
        serde_json::to_writer(&mut *output,&serde_json::json!({
            "row":"source_native_configured_control_batch","schema":"dm-session-source-query-v1",
            "semantic_revision":format!("{:032x}",tree.identity()),"source_revision":format!("{:032x}",self.source_revision),"policy_revision":format!("{:032x}",self.policy_revision.unwrap()),
            "ordinal":ordinal,"families":families,"environment":environment,"configuration":loaded.selected.path,"configuration_explicit":loaded.selected.explicit,"configuration_present":loaded.present,
            "configuration_schema":"complete_pinned_checker_schema","full_checker_parity":false,"ordering":"primary_control_event_order","flow_reuse":"request_local_union","diagnostics":diagnostics,
        })).map_err(io::Error::other)?;
        output.write_all(b"\n")
    }
}
#[cfg(test)]
#[path = "runner_query_control_batch_tests.rs"]
mod tests;
