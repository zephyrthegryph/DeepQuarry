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
pub(super) fn severity(value: DiagnosticSeverity) -> &'static str {
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
        self.require_semantic_source_encoding()?;
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
            "redefined_proc"=>DiagnosticSeverity::Hint,
            "call_arguments"|"filter_call"=>DiagnosticSeverity::Error,
            "catch_parameter_count"=>DiagnosticSeverity::Warning,
            "static_reference"=>DiagnosticSeverity::Error,
            "incompatible_directive" | "private_proc" | "protected_proc" | "must_call_parent" | "must_not_override" => DiagnosticSeverity::Error,
            "ambiguous_not_bitwise"
            | "ambiguous_in_lhs"
            | "invalid_set_value"
            | "invalid_lint_directive_value"
            | "unknown_linter_setting"
            | "unknown_setting"
            | "disabled_directive"
            | "sets_directive_twice"
            | "directive_at_definition"
            | "field_access_static_type"
            | "proc_call_static_type" => DiagnosticSeverity::Warning,
            "control_condition_static"
            | "set_has_no_effect"
            | "unreachable_code"
            | "loop_condition_determinate"
            | "if_condition_determinate"
            | "proc_has_no_parent"
            | "undefined_proc"
            | "undefined_variable"
            | "no_typehint_implicit_new" => DiagnosticSeverity::Error,
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
        if family=="call_arguments"{return self.write_original_call_arguments_using(ordinal,environment,tree,capture,&loaded,output)}
        if family=="filter_call"{return self.write_original_call_policy_using(ordinal,"filter_call",environment,tree,capture,&loaded,output)}
        if family=="static_reference"{return self.write_original_call_policy_using(ordinal,"static_reference",environment,tree,capture,&loaded,output)}
        if family=="catch_parameter_count"{return self.write_original_call_policy_using(ordinal,"catch_parameter_count",environment,tree,capture,&loaded,output)}
        if matches!(family,"private_proc"|"protected_proc"|"must_call_parent"|"must_not_override"|"redefined_proc"){return self.write_original_procedure_visibility_using(ordinal,family,environment,tree,capture,&loaded,output)}
        if family=="invalid_lint_directive_value"{return self.write_original_invalid_directive_using(ordinal,environment,tree,capture,&loaded,output)}
        let mut rows = Vec::new();
        // These original producers are UNTAGGED: arbitrary observation-name
        // map keys must not disable or re-severity their diagnostics.
        let tag = if matches!(family, "undefined_proc" | "undefined_variable" | "unknown_setting" | "directive_at_definition") {
            None
        } else {
            Some(family)
        };
        if let Some(level) = loaded.policy.register(tag, producer) {
            // Gather the complete findings/source rows before the first output
            // write below. Actual body IO must escape intact, before a partial
            // configured-checker envelope can reach the caller's output buffer.
            let body = archive
                .parse_checked(ordinal as usize)
                .map_err(|error| match error {
                    dm_tree::frontend::BodySyntaxFailure::Syntax(error) => io::Error::other(error.message),
                    dm_tree::frontend::BodySyntaxFailure::Operational(actual) => actual,
                })?;
            let found = match family {
                "proc_has_no_parent" | "undefined_proc" | "undefined_variable" | "field_access_static_type" | "no_typehint_implicit_new" | "proc_call_static_type" => {
                    let resolver = self.resolved.as_ref()
                        .ok_or_else(|| io::Error::other("semantic checker requires the retained successful compile/analysis EngineHost"))?
                        .checker_resolver(tree)?;
                    let host = archive.body_query_host()
                        .ok_or_else(|| io::Error::other("semantic checker compiler query graph unavailable"))?;
                    let profile = tree.checker_builtin_profile()
                        .ok_or_else(|| io::Error::other("compiled hierarchy incompatible with pinned checker builtin profile"))?;
                    let context = dm_analysis::checker_context::CheckerContext::archived(archive, host, resolver, profile)
                        .map_err(io::Error::other)?;
                    if family == "proc_has_no_parent" {match context.parent_archived_checked(&body,Severity::Error,&mut crate::daemon::control::checkpoint){Ok(rows)=>Ok(rows),Err(dm_analysis::policy_body_demand::PolicyFailure::Operational(actual))=>return Err(actual),Err(dm_analysis::policy_body_demand::PolicyFailure::Unsupported(message))=>Err(message.0)}}
                    else if family == "undefined_proc" { context.undefined_archived(&body, true) }
                    else if family == "undefined_variable" { context.variables_archived(&body, true) }
                    else if family == "no_typehint_implicit_new" {context.implicit_new_archived(&body,Severity::Error)}
                    else if family == "proc_call_static_type" {context.proc_static_archived(&body,Severity::Warning)}
                    else {context.fields_archived(&body,Severity::Warning)}
                }
                "ambiguous_not_bitwise" => {
                    dm_analysis::checks::archived_ambiguous_not_bitwise(&body, Severity::Error)
                }
                "ambiguous_in_lhs" => {
                    dm_analysis::checks_ambiguous_in::archived(&body, Severity::Error)
                }
                "unknown_linter_setting" => match dm_analysis::checks_unknown_linter_setting::archived_checked(&body,Severity::Warning,&mut crate::daemon::control::checkpoint){Ok(rows)=>Ok(rows),Err(dm_analysis::policy_body_demand::PolicyFailure::Operational(actual))=>return Err(actual),Err(dm_analysis::policy_body_demand::PolicyFailure::Unsupported(message))=>Err(message.0)},
                "unknown_setting" => match dm_analysis::checks_unknown_linter_setting::archived_ordinary_checked(&body,Severity::Warning,&mut crate::daemon::control::checkpoint){Ok(rows)=>Ok(rows),Err(dm_analysis::policy_body_demand::PolicyFailure::Operational(actual))=>return Err(actual),Err(dm_analysis::policy_body_demand::PolicyFailure::Unsupported(message))=>Err(message.0)},
                "incompatible_directive" | "disabled_directive" | "sets_directive_twice" | "directive_at_definition" => {let family=match family{"incompatible_directive"=>dm_analysis::checks_directive_binding::Family::Incompatible,"disabled_directive"=>dm_analysis::checks_directive_binding::Family::Disabled,"directive_at_definition"=>dm_analysis::checks_directive_binding::Family::AtDefinition,_=>dm_analysis::checks_directive_binding::Family::Duplicate};match dm_analysis::checks_directive_binding::archived_checked(&body,family,if family.name()=="incompatible_directive"{Severity::Error}else{Severity::Warning},&mut crate::daemon::control::checkpoint){Ok(rows)=>Ok(rows),Err(dm_analysis::policy_body_demand::PolicyFailure::Operational(actual))=>return Err(actual),Err(dm_analysis::policy_body_demand::PolicyFailure::Unsupported(message))=>Err(message.0)}},
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
                let origin = archive
                    .source_note_point(diagnostic.span.start)
                    .map_err(io::Error::other)?;
                rows.push(serde_json::json!({"family":diagnostic.family,"severity":severity(level),"file":origin.path,"line":origin.line,
                    "expanded_span":[diagnostic.span.start,diagnostic.span.end],"expression_span":[diagnostic.expression_span.start,diagnostic.expression_span.end],
                    "message":diagnostic.message,"notes":diagnostic.notes.iter().map(|note|note.legacy_text()).collect::<Vec<_>>() }));
            }
        }
        crate::daemon::control::checkpoint()?;
        serde_json::to_writer(&mut *output,&serde_json::json!({
            "row":"source_native_configured_checker","schema":"dm-session-source-query-v1",
            "semantic_revision":format!("{:032x}",tree.identity()),"source_revision":format!("{:032x}",self.source_revision),
            "policy_revision":format!("{:032x}",self.policy_revision.unwrap()),"ordinal":ordinal,"family":family,
            "environment":environment,"configuration":loaded.selected.path,"configuration_explicit":loaded.selected.explicit,
            "configuration_present":loaded.present,"configuration_schema":"complete_pinned_checker_schema",
            "full_checker_parity":false,"diagnostics":rows,
        })).map_err(io::Error::other)?;
        output.write_all(b"\n")?;crate::daemon::control::checkpoint()
    }
}
#[cfg(test)]
#[path = "runner_query_named_policy_tests.rs"]
mod tests;

#[cfg(test)]
pub(super) fn visibility_test_fixture(source: &str, checker: Option<&[u8]>) -> SourceSnapshot {
    tests::semantic_snapshot_primary(source, checker, true)
}

#[cfg(test)]
pub(super) fn visibility_test_fixture_result(
    source: &str,
    checker: Option<&[u8]>,
) -> Result<SourceSnapshot, Vec<dm_tree::frontend::Diagnostic>> {
    tests::semantic_snapshot_primary_result(source, checker, true)
}

// Original invalid-value messages are serialized by borrow.
// This avoids copying a potentially large Debug String into serde_json::Value.
struct OriginalInvalidRows<'a>{rows:Option<&'a dm_analysis::checker_original_expression_debug::OriginalDiagnosticRows>,archive:&'a dm_tree::frontend::BodyArchive,level:Option<DiagnosticSeverity>}
impl serde::Serialize for OriginalInvalidRows<'_>{fn serialize<S:serde::Serializer>(&self,serializer:S)->Result<S::Ok,S::Error>{use serde::ser::SerializeSeq;let count=self.rows.map_or(0,|rows|rows.iter().len());let mut seq=serializer.serialize_seq(Some(count))?;if let Some(rows)=self.rows{for row in rows.iter(){seq.serialize_element(&OriginalInvalidRow{row,archive:self.archive,level:self.level.ok_or_else(||serde::ser::Error::custom("invalid-value row has no configured severity"))?})?;}}seq.end()}}
struct OriginalInvalidRow<'a>{row:&'a dm_analysis::checks::Diagnostic,archive:&'a dm_tree::frontend::BodyArchive,level:DiagnosticSeverity}
impl serde::Serialize for OriginalInvalidRow<'_>{fn serialize<S:serde::Serializer>(&self,serializer:S)->Result<S::Ok,S::Error>{use serde::ser::SerializeStruct;let row=self.row;let origin=self.archive.source_note_point(row.span.start).map_err(serde::ser::Error::custom)?;let mut state=serializer.serialize_struct("ConfiguredDiagnostic",8)?;state.serialize_field("expanded_span",&[row.span.start,row.span.end])?;state.serialize_field("expression_span",&[row.expression_span.start,row.expression_span.end])?;state.serialize_field("family",row.family)?;state.serialize_field("file",&origin.path)?;state.serialize_field("line",&origin.line)?;state.serialize_field("message",&row.message)?;state.serialize_field("notes",&[]as&[&str])?;state.serialize_field("severity",severity(self.level))?;state.end()}}
#[derive(serde::Serialize)]
struct OriginalInvalidEnvelope<'a>{configuration:&'a Path,configuration_explicit:bool,configuration_present:bool,configuration_schema:&'static str,diagnostics:OriginalInvalidRows<'a>,environment:&'a Path,family:&'static str,full_checker_parity:bool,ordinal:u32,policy_revision:String,row:&'static str,schema:&'static str,semantic_revision:String,source_revision:String}
impl SourceSnapshot{
 // Source-bound configured family. This grants no complete-checker parity.
 fn write_original_invalid_directive_using(&self,ordinal:u32,environment:&Path,tree:&dm_tree::SemanticTree,capture:&CapturedPolicyInputs,loaded:&config::Loaded,output:&mut impl io::Write)->io::Result<()>{
  let archive=capture.policy().archive();let level=loaded.policy.register(Some("invalid_lint_directive_value"),DiagnosticSeverity::Warning);
  let rows=if let Some(_)=level{let body=archive.parse_checked(ordinal as usize).map_err(|error|match error{dm_tree::frontend::BodySyntaxFailure::Syntax(error)=>io::Error::other(error.message),dm_tree::frontend::BodySyntaxFailure::Operational(actual)=>actual})?;
   let rows=dm_analysis::checks_directive_binding::archived_value_checked(&body,Severity::Warning,&mut crate::daemon::control::checkpoint).map_err(|error|match error{dm_analysis::policy_body_demand::PolicyFailure::Operational(actual)=>actual,dm_analysis::policy_body_demand::PolicyFailure::Unsupported(message)=>io::Error::other(message.0)})?;
   for row in rows.iter(){crate::daemon::control::checkpoint()?;archive.source_note_point(row.span.start).map_err(io::Error::other)?;if !row.notes.is_empty(){return Err(io::Error::other("invalid-value projection unexpectedly acquired notes"))}}Some(rows)
  }else{None};
  crate::daemon::control::checkpoint()?;
  let envelope=OriginalInvalidEnvelope{configuration:&loaded.selected.path,configuration_explicit:loaded.selected.explicit,configuration_present:loaded.present,configuration_schema:"complete_pinned_checker_schema",diagnostics:OriginalInvalidRows{rows:rows.as_ref(),archive,level},environment,family:"invalid_lint_directive_value",full_checker_parity:false,ordinal,policy_revision:format!("{:032x}",self.policy_revision.ok_or_else(||io::Error::other("invalid-value policy revision unavailable"))?),row:"source_native_configured_checker",schema:"dm-session-source-query-v1",semantic_revision:format!("{:032x}",tree.identity()),source_revision:format!("{:032x}",self.source_revision)};
  serde_json::to_writer(&mut *output,&envelope).map_err(io::Error::other)?;output.write_all(b"\n")?;crate::daemon::control::checkpoint()
 }
}

impl SourceSnapshot{
 fn write_original_procedure_visibility_using(&self,ordinal:u32,family:&str,environment:&Path,tree:&dm_tree::SemanticTree,capture:&CapturedPolicyInputs,loaded:&config::Loaded,output:&mut impl io::Write)->io::Result<()>{
  fn encoded(finding:dm_analysis::checks_proc_visibility::Finding<'_>,level:DiagnosticSeverity,definition:bool)->io::Result<serde_json::Value>{let row=finding.diagnostic();let point=finding.reported_point().map_err(io::Error::other)?;let(path,line,column)=point.coordinates();let synthetic=finding.is_parser_synthetic();let mut value=serde_json::json!({"family":row.family,"severity":severity(level),"file":path,"line":line,"column":column,"location_kind":if synthetic{"parser_synthetic"}else{"source"},"expanded_span":if synthetic{None}else{Some([row.span.start,row.span.end])},"expression_span":if synthetic{None}else{Some([row.expression_span.start,row.expression_span.end])},"message":row.message,"notes":row.notes.iter().map(|note|note.legacy_text()).collect::<Vec<_>>() });if definition{value.as_object_mut().unwrap().insert("registration_tag".into(),serde_json::json!(finding.registration_tag()));}Ok(value)}
  let archive=capture.policy().archive();let definition=family=="redefined_proc";let mut rows=Vec::new();
  if definition&&loaded.policy.register(None,DiagnosticSeverity::Error).is_some(){if let Some(receipt)=&self.diagnostic_declarations{let structural=dm_analysis::checks_proc_visibility::declaration_redeclaration_checked(archive,ordinal as usize,receipt,&crate::daemon::control::checkpoint).map_err(|failure|match failure{dm_analysis::policy_body_demand::PolicyFailure::Operational(actual)=>actual,dm_analysis::policy_body_demand::PolicyFailure::Unsupported(reason)=>io::Error::other(reason.0)})?;for finding in structural.iter(){rows.push(encoded(finding,DiagnosticSeverity::Error,true)?);}}}
// The shared syntax finding has only Disabled/Warning/Error; the actual
// producer Hint and configured final level remain DiagnosticSeverity below.
if let Some(level)=loaded.policy.register(Some(family),if definition{DiagnosticSeverity::Hint}else{DiagnosticSeverity::Error}){
   let body=archive.parse_checked(ordinal as usize).map_err(|failure|match failure{dm_tree::frontend::BodySyntaxFailure::Operational(actual)=>actual,dm_tree::frontend::BodySyntaxFailure::Syntax(error)=>io::Error::other(error.message)})?;let resolver:&dyn dm_ir::Resolver=if let Some(receipt)=&self.diagnostic_declarations{if !receipt.authenticates(tree)||!self.matches_tree(tree){return Err(io::Error::other("procedure diagnostic owner is foreign"))}tree}else{self.resolved.as_ref().ok_or_else(||io::Error::other("procedure visibility requires retained semantic EngineHost"))?.checker_resolver(tree)?};let profile=tree.checker_builtin_profile().ok_or_else(||io::Error::other("procedure visibility requires actual pinned builtin profile"))?;let selected=match family{"private_proc"=>dm_analysis::checks_proc_visibility::Family::Private,"protected_proc"=>dm_analysis::checks_proc_visibility::Family::Protected,"must_call_parent"=>dm_analysis::checks_proc_visibility::Family::MustCallParent,"must_not_override"=>dm_analysis::checks_proc_visibility::Family::MustNotOverride,"redefined_proc"=>dm_analysis::checks_proc_visibility::Family::Redefined,_=>return Err(io::Error::other("procedure directive role differs"))};let found=dm_analysis::checks_proc_visibility::archived_checked(archive,&body,resolver,profile,selected,if definition{Severity::Warning}else{Severity::Error},&crate::daemon::control::checkpoint).map_err(|failure|match failure{dm_analysis::policy_body_demand::PolicyFailure::Operational(actual)=>actual,dm_analysis::policy_body_demand::PolicyFailure::Unsupported(reason)=>io::Error::other(reason.0)})?;
   for finding in found.iter(){crate::daemon::control::checkpoint()?;rows.push(encoded(finding,level,definition)?);}

  }
  crate::daemon::control::checkpoint()?;let mut envelope=serde_json::json!({"row":"source_native_configured_checker","schema":"dm-session-source-query-v1","semantic_revision":format!("{:032x}",tree.identity()),"source_revision":format!("{:032x}",self.source_revision),"policy_revision":format!("{:032x}",self.policy_revision.unwrap()),"ordinal":ordinal,"family":family,"environment":environment,"configuration":loaded.selected.path,"configuration_explicit":loaded.selected.explicit,"configuration_present":loaded.present,"configuration_schema":"complete_pinned_checker_schema","full_checker_parity":false,"diagnostics":rows,"declaration_profile":self.diagnostic_declarations.as_ref().map_or("strict-native-declarations",|receipt|receipt.profile()),"native_declaration_error_count":self.diagnostic_declarations.as_ref().map_or(0,|receipt|receipt.errors().len())});if definition{envelope.as_object_mut().unwrap().insert("untagged_companions".into(),serde_json::json!(["procedure_redeclaration"]));}serde_json::to_writer(&mut *output,&envelope).map_err(io::Error::other)?;output.write_all(b"\n")?;crate::daemon::control::checkpoint()
 }
}
