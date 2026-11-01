//! Exact findings-only envelopes for explicitly captured native named policies.
use super::{QueryReply, QueryRequest, SourceQuery};
use serde_json::Value;
use std::io;
fn invalid(detail: &str) -> io::Error {
    io::Error::new(
        io::ErrorKind::InvalidData,
        format!("invalid native named-policy reply: {detail}"),
    )
}
fn is_named(q: &SourceQuery) -> bool {
    matches!(
        q,
        SourceQuery::NativeNamedRule { .. } | SourceQuery::NativeConfiguredChecker { .. } | SourceQuery::NativeKeywordOverrides{..}
    )
}
pub(super) fn reads_policy(q: &SourceQuery) -> bool {
    is_named(q)
}
pub(super) fn validate_request(request: &QueryRequest) -> io::Result<()> {
    for q in request.source_queries.iter().filter(|q| is_named(q)) {
        if request.expected_policy_revision.is_none() {
            return Err(io::Error::new(
                io::ErrorKind::InvalidInput,
                "named policies require their exact captured-policy revision",
            ));
        }
        let allowed = match q {
            SourceQuery::NativeNamedRule {
                root,
                lint,
                rule,
                configuration,
            } => {
                root.is_absolute()
                    && configuration.is_absolute()
                    && lint == "base_vars"
                    && rule == "records_data_only"
            }
            SourceQuery::NativeConfiguredChecker {
                family,
                environment,
                configuration,
                ..
            } => {
                environment.is_absolute()
                    && configuration.as_ref().is_none_or(|p| p.is_absolute())
                    && matches!(
                        family.as_str(),
                        "ambiguous_not_bitwise"
                            | "ambiguous_in_lhs"
                            | "invalid_set_value"
                            | "invalid_lint_directive_value"
                            | "directive_at_definition"
                            | "unknown_linter_setting"
                            | "unknown_setting"
                            | "incompatible_directive"
                            | "disabled_directive"
                            | "sets_directive_twice"
                            | "control_condition_static"
                            | "set_has_no_effect"
                            | "unreachable_code"
                            | "loop_condition_determinate"
                            | "if_condition_determinate"
                            | "proc_has_no_parent"
                            | "undefined_proc"
                            | "undefined_variable"
                            | "field_access_static_type"
                            | "no_typehint_implicit_new"
                            | "proc_call_static_type" | "private_proc" | "protected_proc" | "must_call_parent" | "must_not_override" | "redefined_proc" | "call_arguments"
                    )
            }
            SourceQuery::NativeKeywordOverrides{environment,configuration}=>environment.is_absolute()&&configuration.as_ref().is_none_or(|p|p.is_absolute()),
            _ => false,
        };
        if !allowed {
            return Err(io::Error::new(
                io::ErrorKind::InvalidInput,
                "unsupported native named-policy scope or family",
            ));
        }
    }
    Ok(())
}
fn exact(row: &Value, keys: &[&str]) -> io::Result<()> {
    let o = row.as_object().ok_or_else(|| invalid("not an object"))?;
    if o.len() != keys.len() || !keys.iter().all(|k| o.contains_key(*k)) {
        return Err(invalid("payload fields"));
    }
    Ok(())
}
fn text(v: &Value) -> bool {
    v.as_str().is_some_and(|s| !s.is_empty())
}
fn span(v: &Value) -> bool {
    v.as_array().is_some_and(|a| {
        a.len() == 2 && matches!((a[0].as_u64(),a[1].as_u64()),(Some(s),Some(e))if s<=e)
    })
}
pub(super) fn validate_requested(reply: &QueryReply, questions: &[SourceQuery]) -> io::Result<()> {
    let expected: Vec<_> = questions.iter().filter(|q| is_named(q)).collect();
    let mut next = 0;
    for line in reply.jsonl.lines() {
        let row: Value = serde_json::from_str(line).map_err(|_| invalid("JSONL"))?;
        if !matches!(
            row["row"].as_str(),
            Some("source_native_named_rule" | "source_native_configured_checker" | "source_native_keyword_override_checker")
        ) {
            continue;
        }
        let question = expected
            .get(next)
            .ok_or_else(|| invalid("extra named row"))?;
        if row["schema"] != "dm-session-source-query-v1"
            || row["semantic_revision"].as_str() != Some(reply.revision.as_str())
            || reply.source_revision.is_none()
            || row["source_revision"].as_str() != reply.source_revision.as_deref()
            || reply.policy_revision.is_none()
            || row["policy_revision"].as_str() != reply.policy_revision.as_deref()
        {
            return Err(invalid("foreign revision"));
        }
        match question {
            SourceQuery::NativeNamedRule {
                root,
                lint,
                rule,
                configuration,
            } => {
                exact(
                    &row,
                    &[
                        "row",
                        "schema",
                        "semantic_revision",
                        "source_revision",
                        "policy_revision",
                        "root",
                        "lint",
                        "rule",
                        "configuration",
                        "coverage",
                        "admission",
                        "full_lint_parity",
                        "findings",
                    ],
                )?;
                if row["row"] != "source_native_named_rule"
                    || row["root"] != serde_json::to_value(root).map_err(io::Error::other)?
                    || row["lint"] != lint.as_str()
                    || row["rule"] != rule.as_str()
                    || row["configuration"]
                        != serde_json::to_value(configuration).map_err(io::Error::other)?
                    || row["coverage"] != "captured_compiled_declarations"
                    || row["admission"] != "raw_findings"
                    || row["full_lint_parity"] != false
                {
                    return Err(invalid("named-rule metadata"));
                }
                for finding in row["findings"]
                    .as_array()
                    .ok_or_else(|| invalid("findings"))?
                {
                    exact(finding, &["rule", "rel", "line", "msg", "key", "ident"])?;
                    if finding["rule"] != rule.as_str()
                        || !text(&finding["rel"])
                        || !finding["line"].as_u64().is_some_and(|n| n > 0)
                        || ["msg", "key", "ident"]
                            .iter()
                            .any(|key| finding[*key] != "")
                    {
                        return Err(invalid("record finding"));
                    }
                }
            }
            SourceQuery::NativeConfiguredChecker {
                ordinal,
                family,
                environment,
                configuration,
            } => {
                let access=matches!(family.as_str(),"private_proc"|"protected_proc"|"must_call_parent"|"must_not_override"|"redefined_proc"|"call_arguments");
                let mut keys=vec!["row","schema","semantic_revision","source_revision","policy_revision","ordinal","family","environment","configuration","configuration_explicit","configuration_present","configuration_schema","full_checker_parity","diagnostics"];
                if access{keys.extend(["declaration_profile","native_declaration_error_count"]);}if family=="redefined_proc"{keys.push("untagged_companions");}
                exact(&row,&keys)?;
                if access {match(row["declaration_profile"].as_str(),row["native_declaration_error_count"].as_u64()){
                  (Some("strict-native-declarations"),Some(0))=>{},
                  (Some("native-diagnostic-inherited-variable-v1"),Some(_))=>{},
                  (Some("native-diagnostic-source-declarations-v2"|"native-diagnostic-procedure-versions-v3"),Some(count)) if count>0=>{},
                  _=>return Err(invalid("procedure declaration profile")),
                }}
                if family=="redefined_proc"&&row["untagged_companions"]!=serde_json::json!(["procedure_redeclaration"]){return Err(invalid("redefined procedure companion contract"))}
                let selected =
                    dm_analysis::check_configuration::select(environment, configuration.as_deref());
                if row["row"] != "source_native_configured_checker"
                    || row["ordinal"] != *ordinal
                    || row["family"] != family.as_str()
                    || row["environment"]
                        != serde_json::to_value(environment).map_err(io::Error::other)?
                    || row["configuration"]
                        != serde_json::to_value(&selected.path).map_err(io::Error::other)?
                    || row["configuration_explicit"] != selected.explicit
                    || !row["configuration_present"].is_boolean()
                    || row["configuration_schema"] != "complete_pinned_checker_schema"
                    || row["full_checker_parity"] != false
                {
                    return Err(invalid("configured checker metadata"));
                }
                for d in row["diagnostics"]
                    .as_array()
                    .ok_or_else(|| invalid("diagnostics"))?
                {
                    let access=matches!(family.as_str(),"private_proc"|"protected_proc"|"must_call_parent"|"must_not_override"|"redefined_proc"|"call_arguments");
                    if family=="redefined_proc"{exact(d,&["family","severity","file","line","column","location_kind","expanded_span","expression_span","message","notes","registration_tag"])?;}else if access{exact(d,&["family","severity","file","line","column","location_kind","expanded_span","expression_span","message","notes"])?;}else{
                    exact(
                        d,
                        &[
                            "family",
                            "severity",
                            "file",
                            "line",
                            "expanded_span",
                            "expression_span",
                            "message",
                            "notes",
                        ],
                    )?;
                    }
                    let synthetic=matches!(family.as_str(),"private_proc"|"protected_proc"|"call_arguments")&&d["location_kind"]=="parser_synthetic";
                    let valid_location=if synthetic{d["file"]=="(unknown)"&&d["line"]==0&&d["column"]==0&&d["expanded_span"].is_null()&&d["expression_span"].is_null()}else{(!access||(d["location_kind"]=="source"&&d["column"].as_u64().is_some_and(|n|n>0)))&&d["line"].as_u64().is_some_and(|n|n>0)&&span(&d["expanded_span"])&&span(&d["expression_span"])};
                    let structural=family=="redefined_proc"&&d["family"]=="procedure_redeclaration"&&d["registration_tag"].is_null()&&d["severity"]=="error";
                    let tagged=family!="call_arguments"&&d["family"]==family.as_str()&&(family!="redefined_proc"||d["registration_tag"]==family.as_str());
                    let argument=family=="call_arguments"&&matches!(d["family"].as_str(),Some("bad_keyword_argument"|"non_keyword_after_keyword"))&&d["severity"]=="error";
                    if !(structural||tagged||argument)
                        || !matches!(
                            d["severity"].as_str(),
                            Some("error" | "warning" | "info" | "hint")
                        )
                        || !text(&d["file"])
                        || !text(&d["message"])
                        || !valid_location
                        || !d["notes"]
                            .as_array()
                            .is_some_and(|notes| notes.iter().all(text))
                    {
                        return Err(invalid("configured checker diagnostic"));
                    }
                }
            }
            SourceQuery::NativeKeywordOverrides{environment,configuration}=>{
                exact(&row,&["row","schema","semantic_revision","source_revision","policy_revision","family","environment","configuration","configuration_explicit","configuration_present","configuration_schema","coverage","body_count","complete","full_checker_parity","declaration_profile","native_declaration_error_count","diagnostics"])?;
                let selected=dm_analysis::check_configuration::select(environment,configuration.as_deref());
                if row["row"]!="source_native_keyword_override_checker"||row["family"]!="override_missing_keyword_arg"||row["environment"]!=serde_json::to_value(environment).map_err(io::Error::other)?||row["configuration"]!=serde_json::to_value(&selected.path).map_err(io::Error::other)?||row["configuration_explicit"]!=selected.explicit||!row["configuration_present"].is_boolean()||row["configuration_schema"]!="complete_pinned_checker_schema"||row["coverage"]!="whole_original_archive"||row["body_count"].as_u64().is_none()||row["complete"]!=true||row["full_checker_parity"]!=false{return Err(invalid("whole keyword metadata"))}
                match(row["declaration_profile"].as_str(),row["native_declaration_error_count"].as_u64()){(Some("strict-native-declarations"),Some(0))|(Some("native-diagnostic-inherited-variable-v1"),Some(_))=>{},(Some("native-diagnostic-source-declarations-v2"|"native-diagnostic-procedure-versions-v3"),Some(n))if n>0=>{},_=>return Err(invalid("keyword declaration profile"))}
                for d in row["diagnostics"].as_array().ok_or_else(||invalid("keyword diagnostics"))?{exact(d,&["family","severity","file","line","column","location_kind","expanded_span","expression_span","message","notes"])?;let location=match d["location_kind"].as_str(){Some("source")=>text(&d["file"])&&d["line"].as_u64().is_some_and(|n|n>0)&&d["column"].as_u64().is_some_and(|n|n>0)&&span(&d["expanded_span"])&&span(&d["expression_span"]),Some("builtin")=>d["file"]=="(builtins)"&&d["line"]==1&&d["column"]==1&&d["expanded_span"].is_null()&&d["expression_span"].is_null(),_=>false};if d["family"]!="override_missing_keyword_arg"||!matches!(d["severity"].as_str(),Some("error"|"warning"|"info"|"hint"))||!location||!text(&d["message"])||!d["notes"].as_array().is_some_and(|n|n.iter().all(text)){return Err(invalid("keyword diagnostic"))}}
            }
            _ => return Err(invalid("unexpected question")),
        }
        next += 1;
    }
    if next != expected.len() {
        return Err(invalid("missing named rows"));
    }
    Ok(())
}
#[cfg(test)]
#[path = "named_policy_tests.rs"]
mod tests;
