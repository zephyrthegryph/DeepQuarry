//! Strict paged raw findings for an immutable prepared policy frame.
use super::{QueryReply, QueryRequest, SourceQuery};
use serde_json::Value;
use std::{io, path::Path};
fn invalid(s: &str) -> io::Error {
    io::Error::new(
        io::ErrorKind::InvalidData,
        format!("native workspace policy: {s}"),
    )
}
fn exact(row: &Value, names: &[&str]) -> io::Result<()> {
    let fields = row.as_object().ok_or_else(|| invalid("expected object"))?;
    if fields.len() != names.len() || names.iter().any(|name| !fields.contains_key(*name)) {
        return Err(invalid("extra/missing fields"));
    }
    Ok(())
}
fn text<'a>(row: &'a Value, name: &str, nonempty: bool) -> io::Result<&'a str> {
    row[name]
        .as_str()
        .filter(|s| !nonempty || !s.is_empty())
        .ok_or_else(|| invalid("invalid text"))
}
fn number(row: &Value, name: &str) -> io::Result<usize> {
    row[name]
        .as_u64()
        .and_then(|n| usize::try_from(n).ok())
        .ok_or_else(|| invalid("invalid page number"))
}
/// Shape-only serde visitors. No interpreted scope payload is retained here.
/// Escaped strings use serde_json's one reusable token scratch; unescaped
/// strings are borrowed directly from the already-captured JSON projection.
#[derive(Clone,Copy)]enum ScopeShape{Strings,Lists,Tables,Table,Ceilings,String,Integer}
impl<'de> serde::de::DeserializeSeed<'de> for ScopeShape{
 type Value=();
 fn deserialize<D:serde::Deserializer<'de>>(self,deserializer:D)->Result<(),D::Error>{match self{
  Self::Strings=>deserializer.deserialize_seq(ScopeStrings),
  Self::Lists|Self::Tables|Self::Table|Self::Ceilings=>deserializer.deserialize_map(ScopeMap(self)),
  Self::String=>deserializer.deserialize_str(ScopeString),
  Self::Integer=>deserializer.deserialize_i64(ScopeInteger),
 }}
}
struct ScopeString;
impl<'de> serde::de::Visitor<'de> for ScopeString{
 type Value=();fn expecting(&self,f:&mut std::fmt::Formatter<'_>)->std::fmt::Result{f.write_str("an interpreted scope string")}
 fn visit_str<E:serde::de::Error>(self,_:&str)->Result<(),E>{Ok(())}
}
struct ScopeInteger;
impl<'de> serde::de::Visitor<'de> for ScopeInteger{
 type Value=();fn expecting(&self,f:&mut std::fmt::Formatter<'_>)->std::fmt::Result{f.write_str("an interpreted scope i64 ceiling")}
 fn visit_i64<E:serde::de::Error>(self,_:i64)->Result<(),E>{Ok(())}
 fn visit_u64<E:serde::de::Error>(self,value:u64)->Result<(),E>{i64::try_from(value).map(|_|()).map_err(|_|E::invalid_value(serde::de::Unexpected::Unsigned(value),&self))}
}
struct ScopeStrings;
impl<'de> serde::de::Visitor<'de> for ScopeStrings{
 type Value=();fn expecting(&self,f:&mut std::fmt::Formatter<'_>)->std::fmt::Result{f.write_str("an interpreted scope string list")}
 fn visit_seq<A:serde::de::SeqAccess<'de>>(self,mut sequence:A)->Result<(),A::Error>{while sequence.next_element_seed(ScopeShape::String)?.is_some(){}Ok(())}
}
struct ScopeMap(ScopeShape);
impl<'de> serde::de::Visitor<'de> for ScopeMap{
 type Value=();fn expecting(&self,f:&mut std::fmt::Formatter<'_>)->std::fmt::Result{f.write_str("an interpreted scope map")}
 fn visit_map<A:serde::de::MapAccess<'de>>(self,mut map:A)->Result<(),A::Error>{
  let value=match self.0{ScopeShape::Lists=>ScopeShape::Strings,ScopeShape::Tables=>ScopeShape::Table,ScopeShape::Table=>ScopeShape::String,ScopeShape::Ceilings=>ScopeShape::Integer,_=>return Err(serde::de::Error::custom("invalid internal scope map shape"))};
  while map.next_key_seed(ScopeShape::String)?.is_some(){map.next_value_seed(value)?;}Ok(())
 }
}
struct ScopeTuple;
struct NoExtraScopePart;
impl<'de> serde::de::DeserializeSeed<'de> for NoExtraScopePart{
 type Value=();fn deserialize<D:serde::Deserializer<'de>>(self,_:D)->Result<(),D::Error>{Err(serde::de::Error::custom("extra interpreted scope tuple field"))}
}
impl<'de> serde::de::Visitor<'de> for ScopeTuple{
 type Value=();fn expecting(&self,f:&mut std::fmt::Formatter<'_>)->std::fmt::Result{f.write_str("exactly seven interpreted scope fields")}
 fn visit_seq<A:serde::de::SeqAccess<'de>>(self,mut sequence:A)->Result<(),A::Error>{
  for(index,shape)in [ScopeShape::Strings,ScopeShape::Strings,ScopeShape::Strings,ScopeShape::Lists,ScopeShape::Tables,ScopeShape::Ceilings,ScopeShape::Strings].into_iter().enumerate(){if sequence.next_element_seed(shape)?.is_none(){return Err(serde::de::Error::invalid_length(index,&self))}}
  // Reject an eighth value before traversing even a deeply nested payload.
  let _:Option<()>=sequence.next_element_seed(NoExtraScopePart)?;Ok(())
 }
}
/// Existing outer DOM only: scalar capacity census plus the already-established
/// conservative standard-map node envelope. No rows or strings are copied.
/// This does not qualify the preexisting outer JSON parser as a hard RSS bound.
fn report_value_backing(value:&Value)->Option<usize>{match value{
 Value::String(text)=>Some(text.capacity()),
 Value::Array(rows)=>rows.iter().try_fold(rows.capacity().checked_mul(std::mem::size_of::<Value>())?,|n,value|n.checked_add(report_value_backing(value)?)),
 Value::Object(rows)=>rows.iter().try_fold(rows.len().checked_mul(1024usize.checked_add(std::mem::size_of::<String>())?.checked_add(std::mem::size_of::<Value>())?)?,|n,(key,value)|n.checked_add(key.capacity())?.checked_add(report_value_backing(value)?)),
 _=>Some(0),
}}
fn scope_projection(text:&str,outer_live:usize)->io::Result<()> {
 // serde_json reuses ONE Vec for escaped-token decoding. Decoded UTF8 cannot
 // exceed the encoded projection, and amortized Vec growth is covered by 2x.
 // No per-element Value/Vec/map/String owner is constructed by these visitors.
 let scratch=text.len().checked_mul(2).and_then(|n|n.checked_add(1024));
 if scratch.and_then(|n|outer_live.checked_add(n)).is_none_or(|n|n>crate::query_db::QueryDb::workspace_raw_report_reserve()){
  return Err(io::Error::new(io::ErrorKind::OutOfMemory,"interpreted scope validation exceeds existing report allowance"))
 }
 let mut deserializer=serde_json::Deserializer::from_str(text);
 serde::Deserializer::deserialize_tuple(&mut deserializer,7,ScopeTuple).map_err(|_|invalid("invalid interpreted scope JSON"))?;
 deserializer.end().map_err(|_|invalid("trailing interpreted scope JSON"))
}

pub(super) fn reads_policy(q: &SourceQuery) -> bool {
    matches!(q, SourceQuery::NativeWorkspaceRawPolicy { .. }|SourceQuery::NativeWorkspaceRawReportPage{..}|SourceQuery::NativeWorkspaceHygieneReportPage{..})
}
pub(super) fn validate_request(request: &QueryRequest) -> io::Result<()> {
    for question in &request.source_queries {
        if let SourceQuery::NativeWorkspaceHygieneReportPage{root,configuration,lints,limit,..}=question{if !root.is_absolute()||!configuration.is_absolute()||request.expected_policy_revision.is_none()||!(1..=128).contains(limit)||lints.len()!=1||lints[0]!="sys/hygiene"{return Err(invalid("exact completed Hygiene domain request required"))}continue;}
        if let SourceQuery::NativeWorkspaceSysReportPage{root,configuration,lints,limit,..}=question{if !root.is_absolute()||!configuration.is_absolute()||request.expected_policy_revision.is_none()||!(1..=128).contains(limit)||lints.len()!=1||!["sys/resolvers","sys/tables","system_boundary"].contains(&lints[0].as_str()){return Err(invalid("exact completed Sys-family domain request required"))}continue;}
        if let SourceQuery::NativeWorkspaceCheckGrepReportPage{root,configuration,lints,limit,..}=question{if !root.is_absolute()||!configuration.is_absolute()||request.expected_policy_revision.is_none()||!(1..=128).contains(limit)||lints.len()!=1||lints[0]!="check_grep"{return Err(invalid("exact completed CheckGrep domain request required"))}continue;}
        if let SourceQuery::NativeWorkspaceCheckGrepBaselineReportPage{root,configuration,lints,limit,..}=question{if !root.is_absolute()||!configuration.is_absolute()||request.expected_policy_revision.is_none()||!(1..=128).contains(limit)||lints.len()!=1||lints[0]!="check_grep"{return Err(invalid("exact completed CheckGrep domain request required"))}continue;}
        if let SourceQuery::NativeWorkspaceSemanticReportPage{root,configuration,lints,limit,..}=question{if !root.is_absolute()||!configuration.is_absolute()||request.expected_policy_revision.is_none()||!(1..=128).contains(limit)||lints.len()!=1||!matches!(lints[0].as_str(),"sem/reads"|"untracked_inputs"|"setter_publishes"|"sys/dx_reactive"|"lifeforms"|"decl"|"init"|"base_vars"|"requirement_bool"|"player_link"|"untyped_member"|"weak_raw_read"|"rel_write_undeclared"|"untyped"|"stored_refs"|"engine_layering"){return Err(invalid("exact completed semantic domain request required"))}continue;}
        if let SourceQuery::NativeWorkspacePolicyReportPage{root,configuration,lints,limit,..}=question{if !root.is_absolute()||!configuration.is_absolute()||request.expected_policy_revision.is_none()||!(1..=128).contains(limit)||lints.len()!=1||dq_analyze::workspace_fold_policy::Policy::from_name(&lints[0]).is_none(){return Err(invalid("exact completed policy domain request required"))}continue;}
        if let SourceQuery::NativeWorkspaceRawTreeReportPage{root,configuration,lints,limit,..}=question{if !root.is_absolute()||!configuration.is_absolute()||request.expected_policy_revision.is_none()||!(1..=128).contains(limit)||lints.len()!=1||dq_analyze::captured_raw_tree_pages::Policy::from_name(&lints[0]).is_none(){return Err(invalid("exact completed raw tree domain request required"))}continue;}
        if let SourceQuery::NativeWorkspaceKeysReportPage{root,configuration,lints,limit,..}=question{if !root.is_absolute()||!configuration.is_absolute()||request.expected_policy_revision.is_none()||!(1..=128).contains(limit)||lints.len()!=1||lints[0]!="sem/keys"{return Err(invalid("exact completed Keys domain request required"))}continue;}
        if let SourceQuery::NativeWorkspaceRawPolicy {
            root,
            configuration,
            lints,
            limit,
            ..
        } | SourceQuery::NativeWorkspaceRawReportPage{root,configuration,lints,limit,..} = question
        {
            if !root.is_absolute()
                || !configuration.is_absolute()
                || request.expected_policy_revision.is_none()
                || !(1..=128).contains(limit)
                || lints.is_empty()
                || lints.len() > dq_analyze::captured_raw_policy::RAW_FILE_LINTS.len()
                || lints.iter().any(|name| {
                    !dq_analyze::captured_raw_policy::RAW_FILE_LINTS.contains(&name.as_str())
                })
                || lints
                    .iter()
                    .collect::<std::collections::BTreeSet<_>>()
                    .len()
                    != lints.len()
            {
                return Err(io::Error::new(io::ErrorKind::InvalidInput,"workspace query requires exact policy pin, absolute paths, unique admitted raw lints and limit1..128"));
            }
        }
    }
    Ok(())
}
pub(super) fn validate_requested(reply: &QueryReply, questions: &[SourceQuery]) -> io::Result<()> {
    if reply.jsonl.len()>super::MAX_OUTPUT{return Err(invalid("workspace report exceeds existing wire bound"))}
    let wanted = questions
        .iter()
        .filter_map(|q| match q {
            SourceQuery::NativeWorkspaceRawPolicy {
                root,
                configuration,
                lints,
                cursor,
                limit,
            } | SourceQuery::NativeWorkspaceRawReportPage{root,configuration,lints,cursor,limit} | SourceQuery::NativeWorkspaceHygieneReportPage{root,configuration,lints,cursor,limit} | SourceQuery::NativeWorkspaceSysReportPage{root,configuration,lints,cursor,limit} | SourceQuery::NativeWorkspaceSemanticReportPage{root,configuration,lints,cursor,limit} | SourceQuery::NativeWorkspaceRawTreeReportPage{root,configuration,lints,cursor,limit} | SourceQuery::NativeWorkspacePolicyReportPage{root,configuration,lints,cursor,limit} | SourceQuery::NativeWorkspaceKeysReportPage{root,configuration,lints,cursor,limit} | SourceQuery::NativeWorkspaceCheckGrepReportPage{root,configuration,lints,cursor,limit} | SourceQuery::NativeWorkspaceCheckGrepBaselineReportPage{root,configuration,lints,cursor,limit} => Some((root, configuration, lints, cursor, limit,matches!(q,SourceQuery::NativeWorkspaceRawReportPage{..}),matches!(q,SourceQuery::NativeWorkspaceHygieneReportPage{..}),matches!(q,SourceQuery::NativeWorkspaceSysReportPage{..}),matches!(q,SourceQuery::NativeWorkspaceKeysReportPage{..}),matches!(q,SourceQuery::NativeWorkspaceCheckGrepReportPage{..}),matches!(q,SourceQuery::NativeWorkspaceCheckGrepBaselineReportPage{..}),matches!(q,SourceQuery::NativeWorkspaceSemanticReportPage{..}),matches!(q,SourceQuery::NativeWorkspaceRawTreeReportPage{..}),matches!(q,SourceQuery::NativeWorkspacePolicyReportPage{..}))),
            _ => None,
        })
        .collect::<Vec<_>>();
    let mut observed = 0;
    for line in reply.jsonl.lines() {
        let row: Value = serde_json::from_str(line).map_err(|_| invalid("invalid JSONL"))?;
        if row["row"] != "source_native_workspace_raw_policy" && row["row"] != "source_native_workspace_raw_report" && row["row"]!="source_native_workspace_hygiene_report" && row["row"]!="source_native_workspace_policy_report" && row["row"]!="source_native_workspace_raw_tree_report" && row["row"]!="source_native_workspace_sys_report" && row["row"]!="source_native_workspace_semantic_report" && row["row"]!="source_native_workspace_keys_report" && row["row"]!="source_native_workspace_check_grep_report" && row["row"]!="source_native_workspace_check_grep_baseline_report" {
            continue;
        }
        let (root, configuration, lints, cursor, limit,complete,hygiene,sys,keys,grep,bgrep,semantic,raw_tree,complete_policy) = wanted
            .get(observed)
            .ok_or_else(|| invalid("unrequested page"))?;
        if *complete_policy&&(lints.len()!=1||dq_analyze::workspace_fold_policy::Policy::from_name(&lints[0]).is_none()){return Err(invalid("complete policy request differs from actual issuer"))}
        if *raw_tree&&(lints.len()!=1||dq_analyze::captured_raw_tree_pages::Policy::from_name(&lints[0]).is_none()){return Err(invalid("raw tree request differs from actual issuer"))}
        if *hygiene&&(lints.len()!=1||lints[0]!="sys/hygiene"){return Err(invalid("Hygiene request names differ from actual issuer"))}
        if *sys&&(lints.len()!=1||!["sys/resolvers","sys/tables","system_boundary"].contains(&lints[0].as_str())){return Err(invalid("Sys request name differs from actual issuer"))}
        if *semantic&&(lints.len()!=1||!matches!(lints[0].as_str(),"sem/reads"|"untracked_inputs"|"setter_publishes"|"sys/dx_reactive"|"lifeforms"|"decl"|"init"|"base_vars"|"requirement_bool"|"player_link"|"untyped_member"|"weak_raw_read"|"rel_write_undeclared"|"untyped"|"stored_refs"|"engine_layering")){return Err(invalid("semantic request differs from actual issuer"))}
        if *keys&&(lints.len()!=1||lints[0]!="sem/keys"){return Err(invalid("Keys request name differs from actual issuer"))}
        if (*grep||*bgrep)&&(lints.len()!=1||lints[0]!="check_grep"||(*grep&&row["macro_ceiling"].as_i64().filter(|n|*n>=0).is_none())){return Err(invalid("CheckGrep request or actual macro ceiling differs"))}
        let allowed_keys=[
                "row",
                "schema",
                "source_revision",
                "policy_revision",
                "semantic_revision",
                "snapshot_as_of",
                "root",
                "configuration",
                "recursive_roots",
                "requested_lints",
                "lint_whitelist",
                "scope",
                "full_policy_parity",
                "baseline_applied",
                "admission",
                "configuration_scope",
                "aggregate_id",
                "offset",
                "count",
                "total_items",
                "next_cursor",
                "items",
                "policy_scopes","macro_ceiling",
            ];exact(&row,if *grep{&allowed_keys[..]}else{&allowed_keys[..allowed_keys.len()-1]})?;
        if row["schema"] != "dm-session-source-query-v1"
            || row["snapshot_as_of"] != "policy_revision"
            || reply.policy_revision.is_none()
            || row["policy_revision"].as_str() != reply.policy_revision.as_deref()
            || reply.source_revision.is_none()
            || row["source_revision"].as_str() != reply.source_revision.as_deref()
            || row["semantic_revision"].as_str() != Some(reply.revision.as_str())
            || row["root"] != serde_json::to_value(root).map_err(io::Error::other)?
            || row["configuration"]
                != serde_json::to_value(configuration).map_err(io::Error::other)?
            || row["requested_lints"] != serde_json::to_value(lints).map_err(io::Error::other)?
            || row["lint_whitelist"]
                != (if *complete_policy||*raw_tree||*hygiene||*sys||*keys||*semantic||*grep||*bgrep{serde_json::to_value([lints[0].as_str()])}else{serde_json::to_value(dq_analyze::captured_raw_policy::RAW_FILE_LINTS)})
                    .map_err(io::Error::other)?
            || row["scope"] != if *bgrep{"typed_discovery_complete_check_grep_baseline"}else if *grep{"typed_discovery_complete_check_grep"}else if *complete_policy{"typed_discovery_complete_policy"}else if *raw_tree{"typed_discovery_complete_raw_tree"}else if *semantic{"typed_discovery_complete_semantic"}else if *keys{"typed_discovery_complete_keys"}else if *hygiene{"typed_discovery_complete_hygiene"}else if *sys{"typed_discovery_complete_sys_family"}else{"typed_discovery_raw_files"}
            || row["full_policy_parity"] != false
            || row["baseline_applied"] != false
            || row["admission"] != if *bgrep{"complete_selected_check_grep_baseline_findings"}else if *grep{"complete_selected_check_grep_findings"}else if *complete_policy{"complete_selected_policy_findings"}else if *raw_tree{"complete_selected_raw_tree_findings"}else if *semantic{"complete_selected_semantic_findings"}else if *keys{"complete_selected_keys_findings"}else if *hygiene{"complete_selected_hygiene_findings"}else if *sys{"complete_selected_sys_findings"}else if *complete{"complete_selected_raw_policy_findings"}else{"raw_findings"}
            || row["row"] != if *bgrep{"source_native_workspace_check_grep_baseline_report"}else if *grep{"source_native_workspace_check_grep_report"}else if *complete_policy{"source_native_workspace_policy_report"}else if *raw_tree{"source_native_workspace_raw_tree_report"}else if *semantic{"source_native_workspace_semantic_report"}else if *keys{"source_native_workspace_keys_report"}else if *hygiene{"source_native_workspace_hygiene_report"}else if *sys{"source_native_workspace_sys_report"}else if *complete{"source_native_workspace_raw_report"}else{"source_native_workspace_raw_policy"}
            || !matches!(
                row["configuration_scope"].as_str(),
                Some("captured_configuration_bytes" | "proven_missing_configuration")
            )
        {
            return Err(invalid("policy/request scope mismatch"));
        }
        let scopes=row["policy_scopes"].as_array().ok_or_else(||invalid("missing interpreted policy scopes"))?;
        let raw_order;let folded_order;let ordered:&[&str]=if *complete_policy||*raw_tree||*hygiene||*sys||*keys||*semantic||*grep||*bgrep{folded_order=[lints.first().ok_or_else(||invalid("folded name absent"))?.as_str()];&folded_order}else{raw_order=dq_analyze::captured_raw_file::ordered_names(lints).map_err(|_|invalid("unadmitted policy scope names"))?;&raw_order};
        if scopes.len()!=ordered.len(){return Err(invalid("interpreted policy scope count mismatch"))}
        let outer_live=reply.jsonl.capacity().checked_add(std::mem::size_of::<Value>()).and_then(|n|n.checked_add(report_value_backing(&row)?)).and_then(|n|n.checked_add(16*1024)).ok_or_else(||io::Error::new(io::ErrorKind::OutOfMemory,"workspace report validation accounting overflow"))?;
        for(scope,name)in scopes.iter().zip(ordered){
            let fields=scope.as_array().filter(|fields|fields.len()==2).ok_or_else(||invalid("invalid interpreted policy scope row"))?;
            if fields[0].as_str()!=Some(*name){return Err(invalid("foreign or unordered interpreted scope"))}
            let text=fields[1].as_str().ok_or_else(||invalid("missing interpreted scope JSON"))?;
            scope_projection(text,outer_live)?;
        }
        let roots = row["recursive_roots"]
            .as_array()
            .ok_or_else(|| invalid("invalid recursive roots"))?;
        if roots.is_empty()
            || roots.iter().any(|r| {
                r.as_str()
                    .is_none_or(|s| !Path::new(s).is_absolute() || !Path::new(s).starts_with(root))
            })
        {
            return Err(invalid("recursive roots outside contract"));
        }
        let aggregate = text(&row, "aggregate_id", true)?;
        if aggregate.len() > 128 {
            return Err(invalid("aggregate ID exceeds schema bound"));
        }
        let offset = number(&row, "offset")?;
        let count = number(&row, "count")?;
        let total = number(&row, "total_items")?;
        let end = offset
            .checked_add(count)
            .ok_or_else(|| invalid("page offset overflow"))?;
        if offset != cursor.as_ref().map_or(0, |c| c.offset())
            || cursor
                .as_ref()
                .is_some_and(|c| c.aggregate_id() != aggregate)
            || count > **limit
            || end > total
            || (count == 0 && offset < total)
        {
            return Err(invalid("page progress/cursor mismatch"));
        }
        let items = row["items"]
            .as_array()
            .ok_or_else(|| invalid("invalid page records"))?;
        if items.len() != count {
            return Err(invalid("page item count mismatch"));
        }
        if end < total {
            let next: crate::query_db::WorkspaceCursor =
                serde_json::from_value(row["next_cursor"].clone())
                    .map_err(|_| invalid("missing continuation"))?;
            if next.offset() != end || next.aggregate_id() != aggregate {
                return Err(invalid("continuation not next exact page"));
            }
        } else if !row["next_cursor"].is_null() {
            return Err(invalid("unexpected terminal continuation"));
        }
        for item in items {
            let lint = text(item, "lint", true)?;
            if !lints.iter().any(|n| n == lint) {
                return Err(invalid("unrequested lint record"));
            }
            let meta=if *complete_policy{dq_analyze::workspace_fold_policy::Policy::from_name(lint).ok_or_else(||invalid("unissued complete policy metadata"))?.metadata()}else if *raw_tree{dq_analyze::captured_raw_tree_pages::Policy::from_name(lint).ok_or_else(||invalid("unissued raw tree metadata"))?.metadata()}else if *grep||*bgrep{dq_analyze::lints::check_grep::native::metadata()}else if *semantic{match lint{"lifeforms"=>dq_analyze::lifeforms_policy::metadata(),"sys/dx_reactive"=>dq_analyze::sys_reactive_policy::metadata(),"sem/reads"=>dq_analyze::sem_reads_policy::metadata(),"untracked_inputs"=>dq_analyze::untracked_inputs_policy::metadata(),"setter_publishes"=>dq_analyze::setter_publication_policy::metadata(),"decl"=>dq_analyze::captured_decl_pages::metadata(),"init"=>dq_analyze::captured_init_pages::metadata(),"base_vars"=>dq_analyze::captured_base_vars_pages::metadata(),"requirement_bool"=>dq_analyze::captured_requirement_bool_pages::metadata(),"player_link"=>dq_analyze::player_link_policy::metadata(),"untyped_member"=>dq_analyze::untyped_member_policy::metadata(),"weak_raw_read"=>dq_analyze::weak_relation_policy::metadata(),"rel_write_undeclared"=>dq_analyze::rel_write_policy::metadata(),"untyped"=>dq_analyze::untyped_policy_metadata::metadata(),"stored_refs"=>dq_analyze::stored_refs_policy::metadata(),"engine_layering"=>dq_analyze::engine_layering_policy::metadata(),_=>return Err(invalid("unissued semantic metadata"))}}else if *keys{dq_analyze::keys_policy::metadata()}else if *hygiene{dq_analyze::captured_sys_hygiene_pages::metadata()}else if *sys{match lint{"sys/resolvers"=>dq_analyze::captured_sys_resolvers_pages::metadata(),"sys/tables"=>dq_analyze::captured_sys_tables_pages::metadata(),"system_boundary"=>dq_analyze::captured_system_boundary_pages::metadata(),_=>return Err(invalid("unissued Sys metadata"))}}else{dq_analyze::captured_raw_policy::metadata(lint).ok_or_else(||invalid("unknown raw lint"))?};
            match text(item, "kind", true)? {
                "doc_block"=>{
                    if !*raw_tree||lint!="doc_snippets"{return Err(invalid("unissued doc block role"))}exact(item,&["lint","kind","block"])?;let block=&item["block"];exact(block,&["kind","rel","first"])?;let kind=text(block,"kind",true)?;if !matches!(kind,"complete"|"fragment"|"before")||!dq_analyze::doc_snippets_policy::is_doc_path(text(block,"rel",true)?){return Err(invalid("invalid original doc block summary"))}text(block,"first",false)?;
                }
                "doc_complete"=>{if !*raw_tree||lint!="doc_snippets"{return Err(invalid("unissued doc completion role"))}exact(item,&["lint","kind","count"])?;number(item,"count")?;}
                "hard_site" => {
                    if !(*keys||*semantic||(*complete_policy&&dq_analyze::workspace_fold_policy::Policy::from_name(lint).is_some_and(|p|p.message_only()))||(*raw_tree&&dq_analyze::captured_raw_tree_pages::Policy::from_name(lint).is_some_and(|p|p.message_only())))||!matches!(meta.policy,dq_analyze::lint::Policy::Hard){return Err(invalid("unissued message-only finding"))}
                    exact(item,&["lint","kind","site"])?;
                    let site=&item["site"];exact(site,&["rule","rel","line","msg","key","ident"])?;
                    if meta.rule(text(site,"rule",true)?).is_none(){return Err(invalid("unknown hard site rule"))}
                    for name in ["rel","msg","key","ident"]{text(site,name,matches!(name,"rel"|"msg"))?;}
                    if number(site,"line")?==0||number(site,"line")?>u32::MAX as usize{return Err(invalid("invalid hard site line"))}
                }
                "site" => {
                    if *keys||(*semantic&&matches!(meta.policy,dq_analyze::lint::Policy::Hard))||(*complete_policy&&dq_analyze::workspace_fold_policy::Policy::from_name(lint).is_some_and(|p|p.message_only()))||(*raw_tree&&dq_analyze::captured_raw_tree_pages::Policy::from_name(lint).is_some_and(|p|p.message_only())){return Err(invalid("actual Hard family must use its message-only report contract"))}
                    exact(item, &["lint", "kind", "site", "source_text"])?;
                    let message_only=(*grep||*bgrep)&&item["site"]["msg"].as_str().is_some_and(|s|!s.is_empty());if message_only{if !item["source_text"].is_null(){return Err(invalid("CheckGrep message row must not claim an unused source-text observation"))}}else{text(item,"source_text",false)?;}
                    let s = &item["site"];
                    exact(s, &["rule", "rel", "line", "msg", "key", "ident"])?;
                    if meta.rule(text(s, "rule", true)?).is_none() {
                        return Err(invalid("unknown site rule"));
                    }
                    for name in ["rel", "msg", "key", "ident"] {
                        text(s, name, name == "rel")?;
                    }
                    let global=*sys&&lint=="system_boundary"&&matches!(s["rule"].as_str(),Some("B5"|"B7"))&&s["msg"].as_str().is_some_and(|s|!s.is_empty())&&s["key"].as_str().is_some_and(|s|!s.is_empty())&&item["source_text"]=="";
                    if (number(s, "line")? == 0&&!global) || number(s, "line")? > u32::MAX as usize {
                        return Err(invalid("invalid site line"));
                    }
                }
                "allow" => {
                    exact(item, &["lint", "kind", "allow", "source_digest"])?;
                    let digest=text(item,"source_digest",true)?;
                    if digest.len()!=40||!digest.bytes().all(|byte|byte.is_ascii_digit()||(0x61..=0x66).contains(&byte)){return Err(invalid("invalid captured whole-file digest"))}
                    let a = &item["allow"];
                    exact(a, &["rel", "line", "name", "code"])?;
                    text(a, "rel", true)?;
                    text(a, "code", false)?;
                    let used_name=text(a,"name",true)?;let permitted=if *raw_tree{dq_analyze::captured_raw_tree_pages::Policy::from_name(lint).is_some_and(|policy|policy.permits_used_allow(used_name))}else{meta.allow.contains(&used_name)};
                    if !permitted
                        || number(a, "line")? == 0
                        || number(a, "line")? > u32::MAX as usize
                    {
                        return Err(invalid("invalid used annotation"));
                    }
                }
                "note" => {
                    if *hygiene||*sys||*keys||(*semantic&&lint!="base_vars")||(*complete_policy&&!dq_analyze::workspace_fold_policy::Policy::from_name(lint).is_some_and(|p|p.emits_notes())){return Err(invalid("notes are not issued by this report role"))}
                    exact(item, &["lint", "kind", "text"])?;
                    text(item, "text", false)?;
                }
                _ => return Err(invalid("unknown finding record")),
            }
        }
        observed += 1;
    }
    if observed != wanted.len() {
        return Err(invalid("missing requested page"));
    }
    Ok(())
}
#[cfg(test)]
#[path = "workspace_policy_tests.rs"]
mod tests;
