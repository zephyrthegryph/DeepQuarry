//! Captured-only named-rule/configured-checker endpoints. Findings only, never
//! an exported/reparsed semantic model. This module is wired by the companion
//! draft; unsupported scope or configuration authority is an explicit error.
use super::SourceSnapshot;
use crate::runner_host::policy_capture::CapturedPolicyInputs;
use dm_analysis::{
    check_configuration as config, check_policy::DiagnosticSeverity, checks::Severity,
};
use std::{io, path::Path, sync::Arc};

pub(super) fn configuration(
    captured: &CapturedPolicyInputs,
    environment: &Path,
    explicit: Option<&Path>,
) -> io::Result<config::Loaded> {
    if !environment.is_absolute() || explicit.is_some_and(|path| !path.is_absolute()) {
        return Err(io::Error::new(
            io::ErrorKind::InvalidInput,
            "checker configuration paths must be caller-absolute",
        ));
    }
    let selection = config::select(environment, explicit);
    let read = match captured.configuration_bytes(&selection.path)? {
        Some(bytes) if bytes.len() <= 1024*1024 => config::CapturedRead::Bytes(bytes),
        Some(_) => return Err(io::Error::other("checker configuration exceeds 1 MiB migration input budget")),
        None if !selection.explicit => config::CapturedRead::AutodetectAbsent,
        // Generic optional-missing capture proves absence, not the reference's
        // exact explicit read-failure cause; do not fabricate that diagnostic.
        None => return Err(io::Error::other("explicit checker configuration is captured absent; read-failure diagnostic contract unavailable")),
    };
    config::load(
        &selection,
        config::Capture {
            path: &selection.path,
            read,
        },
    )
    .map_err(io::Error::other)
}
fn severity(value: DiagnosticSeverity) -> &'static str {
    match value {
        DiagnosticSeverity::Error => "error",
        DiagnosticSeverity::Warning => "warning",
        DiagnosticSeverity::Info => "info",
        DiagnosticSeverity::Hint => "hint",
    }
}
impl SourceSnapshot {
    pub(super) fn named_policy_capture(
        &self,
        tree: &dm_tree::SemanticTree,
    ) -> io::Result<&CapturedPolicyInputs> {
        let capture = self
            .native_policy_inputs
            .as_ref()
            .filter(|capture| {
                capture.policy_revision() == self.policy_revision && self.policy_revision.is_some()
            })
            .ok_or_else(|| {
                io::Error::other("named policy needs an explicitly bound captured-policy revision")
            })?;
        if !capture.policy().archive().matches_tree(tree)
            || !self
                .body_archive
                .as_ref()
                .is_some_and(|archive| Arc::ptr_eq(archive, capture.policy().archive()))
        {
            return Err(io::Error::other("named policy archive issuance is foreign"));
        }
        Ok(capture)
    }
    pub(crate) fn write_native_named_rule(
        &self,
        root: &Path,
        lint: &str,
        rule: &str,
        scopes: &Path,
        tree: &dm_tree::SemanticTree,
        output: &mut impl io::Write,
    ) -> io::Result<()> {
        crate::daemon::control::checkpoint()?;
        if (lint, rule) != ("base_vars", "records_data_only")
            || !root.is_absolute()
            || !scopes.is_absolute()
        {
            return Err(io::Error::other(
                "unsupported native named rule or nonabsolute scope",
            ));
        }
        let capture = self.named_policy_capture(tree)?;
        if capture.policy().archive().len() > 4096 {
            return Err(io::Error::other(
                "named-rule migration budget exceeds 4096 authored bodies",
            ));
        }
        let prefixes = match capture.configuration_bytes(scopes)? {
            Some(bytes) if bytes.len() <= 1024 * 1024 => {
                dm_analysis::analyze_scope_config::record_accessor_prefixes(bytes)?
            }
            Some(_) => {
                return Err(io::Error::other(
                    "Analyze configuration exceeds 1 MiB migration input budget",
                ))
            }
            // Analyze Scopes::load falls back to an empty scope on a missing file.
            None => Vec::new(),
        };
        let findings = dm_analysis::records_data_only::findings(capture.policy(), root, &prefixes)
            .map_err(io::Error::other)?;
        let findings:Vec<_>=findings.into_iter().map(|row|serde_json::json!({"rule":row.rule,"rel":row.rel,"line":row.line,"msg":row.msg,"key":row.key,"ident":row.ident})).collect();
        crate::daemon::control::checkpoint()?;
        serde_json::to_writer(&mut *output,&serde_json::json!({
            "row":"source_native_named_rule","schema":"dm-session-source-query-v1",
            "semantic_revision":format!("{:032x}",tree.identity()),"source_revision":format!("{:032x}",self.source_revision),
            "policy_revision":format!("{:032x}",self.policy_revision.unwrap()),"root":root,"lint":lint,"rule":rule,
            "configuration":scopes,"coverage":"captured_compiled_declarations","admission":"raw_findings",
            "full_lint_parity":false,"findings":findings,
        })).map_err(io::Error::other)?;
        output.write_all(b"\n")
    }
    pub(crate) fn write_native_configured_checker(
        &self,
        ordinal: u32,
        family: &str,
        environment: &Path,
        explicit: Option<&Path>,
        tree: &dm_tree::SemanticTree,
        output: &mut impl io::Write,
    ) -> io::Result<()> {
        crate::daemon::control::checkpoint()?;
        let producer = match family {
            "ambiguous_not_bitwise" | "ambiguous_in_lhs" | "invalid_set_value" => {
                DiagnosticSeverity::Warning
            }
            "control_condition_static"
            | "set_has_no_effect"
            | "unreachable_code"
            | "loop_condition_determinate"
            | "if_condition_determinate"
            | "proc_has_no_parent"
            | "undefined_proc" => DiagnosticSeverity::Error,
            _ => {
                return Err(io::Error::other(
                    "unsupported native configured-checker family",
                ))
            }
        };
        let capture = self.named_policy_capture(tree)?;
        let loaded = configuration(capture, environment, explicit)?;
        let archive = capture.policy().archive();
        if ordinal as usize >= archive.len() {
            return Err(io::Error::other("body ordinal unavailable"));
        }
        let mut rows = Vec::new();
        // The old undefined-proc producer is UNTAGGED: arbitrary diagnostic
        // map keys named undefined_proc must not disable or re-severity it.
        let tag = if family == "undefined_proc" {
            None
        } else {
            Some(family)
        };
        if let Some(level) = loaded.policy.register(tag, producer) {
            let body = archive
                .parse(ordinal as usize)
                .map_err(|error| io::Error::other(error.message))?;
            let found = match family {
                "proc_has_no_parent" | "undefined_proc" => {
                    let resolver = self.resolved.as_ref()
                        .ok_or_else(|| io::Error::other("semantic checker requires the retained successful compile/analysis EngineHost"))?
                        .checker_resolver(tree)?;
                    let host = archive.body_query_host()
                        .ok_or_else(|| io::Error::other("semantic checker compiler query graph unavailable"))?;
                    let profile = tree.checker_builtin_profile()
                        .ok_or_else(|| io::Error::other("compiled hierarchy incompatible with pinned checker builtin profile"))?;
                    let context = dm_analysis::checker_context::CheckerContext::archived(archive, host, resolver, profile)
                        .map_err(io::Error::other)?;
                    if family == "proc_has_no_parent" { context.parent_archived(&body, Severity::Error) }
                    else { context.undefined_archived(&body, true) }
                }
                "ambiguous_not_bitwise" => {
                    dm_analysis::checks::archived_ambiguous_not_bitwise(&body, Severity::Error)
                }
                "ambiguous_in_lhs" => {
                    dm_analysis::checks_ambiguous_in::archived(&body, Severity::Error)
                }
                "invalid_set_value" => {
                    dm_analysis::checks_invalid_set::archived(&body, Severity::Error)
                }
                "control_condition_static" => {
                    dm_analysis::checks_control_static::archived(&body, Severity::Error)
                }
                "set_has_no_effect" => {
                    dm_analysis::checks_set_no_effect::archived(&body, Severity::Error)
                }
                other => dm_analysis::checks_flow::archived(
                    &body,
                    match other {
                        "unreachable_code" => dm_analysis::checks_flow::Family::Unreachable,
                        "loop_condition_determinate" => {
                            dm_analysis::checks_flow::Family::LoopDeterminate
                        }
                        _ => dm_analysis::checks_flow::Family::IfDeterminate,
                    },
                    Severity::Error,
                ),
            }
            .map_err(io::Error::other)?;
            for diagnostic in found {
                crate::daemon::control::checkpoint()?;
                let origin = body
                    .location(diagnostic.span.start)
                    .ok_or_else(|| io::Error::other("checker diagnostic origin unavailable"))?;
                rows.push(serde_json::json!({"family":diagnostic.family,"severity":severity(level),"file":origin.path,"line":origin.line,
                    "expanded_span":[diagnostic.span.start,diagnostic.span.end],"expression_span":[diagnostic.expression_span.start,diagnostic.expression_span.end],
                    "message":diagnostic.message,"notes":diagnostic.notes.iter().map(|note|&note.message).collect::<Vec<_>>() }));
            }
        }
        serde_json::to_writer(&mut *output,&serde_json::json!({
            "row":"source_native_configured_checker","schema":"dm-session-source-query-v1",
            "semantic_revision":format!("{:032x}",tree.identity()),"source_revision":format!("{:032x}",self.source_revision),
            "policy_revision":format!("{:032x}",self.policy_revision.unwrap()),"ordinal":ordinal,"family":family,
            "environment":environment,"configuration":loaded.selected.path,"configuration_explicit":loaded.selected.explicit,
            "configuration_present":loaded.present,"configuration_schema":"complete_pinned_checker_schema",
            "full_checker_parity":false,"diagnostics":rows,
        })).map_err(io::Error::other)?;
        output.write_all(b"\n")
    }
}
#[cfg(test)]
#[path = "runner_query_named_policy_tests.rs"]
mod tests;
