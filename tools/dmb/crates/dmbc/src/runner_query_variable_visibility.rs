//! Whole-archive variable-visibility categories: one current native owner/Db.
use super::SourceSnapshot;
use std::{io, path::Path};
fn level(s: dm_analysis::check_policy::DiagnosticSeverity) -> &'static str {
    use dm_analysis::check_policy::DiagnosticSeverity as S;
    match s {
        S::Error => "error",
        S::Warning => "warning",
        S::Info => "info",
        S::Hint => "hint",
    }
}
fn point(p: &dm_tree::frontend::SourceNoteOrigin) -> serde_json::Value {
    serde_json::json!({"file":p.path,"line":p.line,"column":p.byte_column})
}
impl SourceSnapshot {
    pub(crate) fn write_native_configured_variable_visibility(
        &self,
        environment: &Path,
        explicit: Option<&Path>,
        tree: &dm_tree::SemanticTree,
        output: &mut impl io::Write,
    ) -> io::Result<()> {
        crate::daemon::control::checkpoint()?;
        let capture = self.named_policy_capture(tree)?;
        // ENV selection must be a source issued by this same compilation, not
        // an arbitrary sibling path that happens to select the captured config.
        if !environment.is_absolute() || capture.compiled_source_file(environment).is_none() {
            return Err(io::Error::other(
                "visibility environment is not an original compiled source",
            ));
        }
        let loaded = super::named_policy::configuration(capture, environment, explicit)?;
        let archive = capture.policy().archive();
        let resolver: &dyn dm_ir::Resolver = if let Some(receipt) = &self.diagnostic_declarations {
            if !receipt.authenticates(tree) || !self.matches_tree(tree) {
                return Err(io::Error::other("diagnostic visibility owner is foreign"));
            }
            // Same original immutable native builder owner, checker-only. No
            // reconstructed EngineHost or ABI/value-query admission is issued.
            tree
        } else {
            self.resolved
                .as_ref()
                .ok_or_else(|| {
                    io::Error::other(
                        "visibility needs original retained successful analysis EngineHost",
                    )
                })?
                .checker_resolver(tree)?
        };
        let host = archive.body_query_host().ok_or_else(|| {
            io::Error::other("visibility original compiler query graph unavailable")
        })?;
        let profile = tree
            .checker_builtin_profile()
            .ok_or_else(|| io::Error::other("visibility pinned builtin profile unavailable"))?;
        let context = dm_analysis::checker_context::CheckerContext::archived(
            archive, host, resolver, profile,
        )
        .map_err(io::Error::other)?;
        let found = context
            .variable_visibility_archived(&loaded.policy, || {
                crate::daemon::control::checkpoint().map_err(|e| e.to_string())
            })
            .map_err(io::Error::other)?;
        let coverage = dm_analysis::checks_variable_visibility::COVERAGE;
        let diagnostics=found.into_iter().map(|finding|{
            let d=finding.finding.diagnostic();
            serde_json::json!({"family":d.family,"registration_tag":finding.finding.registration_tag(),"severity":level(finding.severity),"origin":point(finding.finding.origin()),"expanded_span":[d.span.start,d.span.end],"expression_span":[d.expression_span.start,d.expression_span.end],"message":d.message,"notes":d.notes.iter().map(|note|serde_json::json!({"message":note.message,"source":note.source.as_ref().map(point)})).collect::<Vec<_>>()})
        }).collect::<Vec<_>>();
        serde_json::to_writer(&mut *output,&serde_json::json!({
            "row":"source_native_configured_variable_visibility","schema":"dm-session-source-query-v1",
            "semantic_revision":format!("{:032x}",tree.identity()),"source_revision":format!("{:032x}",self.source_revision),"policy_revision":format!("{:032x}",self.policy_revision.unwrap()),
            "environment":environment,"configuration":loaded.selected.path,"configuration_explicit":loaded.selected.explicit,"configuration_present":loaded.present,"configuration_schema":"complete_pinned_checker_schema",
            "declaration_profile":if self.diagnostic_declarations.is_some(){"native-diagnostic-inherited-variable-v1"}else{"strict-native-declarations"},"native_declaration_error_count":self.diagnostic_declarations.as_ref().map_or(0,|receipt|receipt.errors().len()),
            "producer_categories":coverage.producer_categories,"families":coverage.registered_tags,"untagged_companions":["variable_redeclaration"],"ordering":"parser_encounter_then_lexical_declarations_then_evaluated_checker_order","full_checker_parity":coverage.full_checker_parity,"all_source_contexts_supported":coverage.all_source_contexts_supported,"diagnostics":diagnostics,
        })).map_err(io::Error::other)?;
        output.write_all(b"\n")
    }
}
#[cfg(test)]
#[path = "runner_query_variable_visibility_tests.rs"]
mod tests;
