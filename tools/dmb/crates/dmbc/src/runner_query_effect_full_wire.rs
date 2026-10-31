//! Exhausted target-window wire over the actual current compiler source scope.
use super::*;
impl SourceSnapshot{
 /// Exhausts both effect judgements over every original target while retaining
 /// only bounded report loans and one preadmitted final wire buffer. Other
 /// checker families and default/client selection remain separate consumers.
 pub(crate) fn write_native_effect_reports_exhausted(&self,input:&Arc<dm_analysis::checker_effects::EffectInput>,width:usize,target_window:usize,environment:&Path,explicit:Option<&Path>,tree:&dm_tree::SemanticTree,output:&mut impl io::Write)->io::Result<()>{
  self.with_effect_scope(input,environment,explicit,tree,|db,scope|self.write_native_effect_reports_scoped(input,width,target_window,environment,tree,db,scope,output))
 }
 fn write_native_effect_reports_scoped(&self,input:&Arc<dm_analysis::checker_effects::EffectInput>,width:usize,target_window:usize,environment:&Path,tree:&dm_tree::SemanticTree,db:&crate::query_db::QueryDb,scope:&PurityScope<'_>,output:&mut impl io::Write)->io::Result<()>{
  db.write_exhausted_effect_report_buffer(input,scope,width,target_window,|writer,reports|{
   writer.write_all(b"{\"row\":\"source_native_effect_reports\",\"schema\":\"dm-session-source-query-v1\",\"semantic_revision\":")?;
   serde_json::to_writer(&mut *writer,&Hex(tree.identity().into())).map_err(io::Error::from)?;writer.write_all(b",\"source_revision\":")?;serde_json::to_writer(&mut *writer,&Hex(self.source_revision)).map_err(io::Error::from)?;writer.write_all(b",\"policy_revision\":")?;serde_json::to_writer(&mut *writer,&Hex(self.policy_revision.ok_or_else(||io::Error::other("effect policy frame unavailable"))?)).map_err(io::Error::from)?;
   writer.write_all(b",\"environment\":")?;serde_json::to_writer(&mut *writer,environment).map_err(io::Error::from)?;writer.write_all(b",\"body_count\":")?;serde_json::to_writer(&mut *writer,&input.archive().len()).map_err(io::Error::from)?;writer.write_all(b",\"full_checker_parity\":false,\"effect_phase_order\":")?;serde_json::to_writer(&mut *writer,&dm_analysis::checker_effects::EFFECT_PHASE_ORDER).map_err(io::Error::from)?;writer.write_all(b",\"target_group_order_contract\":")?;serde_json::to_writer(&mut *writer,dm_analysis::checker_effects::TARGET_GROUP_ORDER_CONTRACT).map_err(io::Error::from)?;
   writer.write_all(b",\"configuration\":")?;serde_json::to_writer(&mut *writer,&scope.configuration().selected.path).map_err(io::Error::from)?;writer.write_all(b",\"configuration_explicit\":")?;serde_json::to_writer(&mut *writer,&scope.configuration().selected.explicit).map_err(io::Error::from)?;writer.write_all(b",\"configuration_present\":")?;serde_json::to_writer(&mut *writer,&scope.configuration().present).map_err(io::Error::from)?;writer.write_all(b",\"configuration_schema\":\"complete_pinned_checker_schema\",\"page_width\":")?;serde_json::to_writer(&mut *writer,&width).map_err(io::Error::from)?;writer.write_all(b",\"target_window\":")?;serde_json::to_writer(&mut *writer,&target_window).map_err(io::Error::from)?;writer.write_all(b",\"target_count\":")?;serde_json::to_writer(&mut *writer,&input.archive().callables().source_order().len()).map_err(io::Error::from)?;
   writer.write_all(b",\"diagnostics\":[")?;let mut first=true;reports.for_each_diagnostic(|phase,row|{if !first{writer.write_all(b",")?;}first=false;serde_json::to_writer(&mut *writer,&Row{phase,row}).map_err(io::Error::from)})?;
   writer.write_all(b"],\"effect_report_only\":true,\"target_windows_exhausted\":true}\n")
  },output)
 }
}

/// Each fragment recomputes the SAME final encoder (count+encode) and hashes its
/// complete bytes. Only the requested bounded intersection is retained here.
/// This trades recomputation for avoiding another semantic/output cache.
impl SourceSnapshot{pub(crate) fn write_native_effect_byte_request(&self,width:usize,target_window:usize,cursor:Option<crate::daemon::query::encoded_bytes::ByteCursor>,limit:usize,environment:&Path,explicit:Option<&Path>,tree:&dm_tree::SemanticTree,output:&mut impl io::Write)->io::Result<()>{
 use crate::daemon::query::encoded_bytes::{Buffer,Collector};
 let owner=self.effect_request_input(tree)?;let input=owner.input.as_ref().expect("sealed actual input");
 self.with_effect_scope(input,environment,explicit,tree,|db,scope|{
  let mut bytes=db.effect_byte_buffer(input,scope,width,limit)?;let mut collector=Collector::new(&mut bytes,cursor,limit,64*1024*1024)?;
  self.write_native_effect_reports_scoped(input,width,target_window,environment,tree,db,scope,&mut collector)?;let fragment=collector.finish()?;
  crate::daemon::control::checkpoint()?;scope.validate(db,input).map_err(io::Error::other)?;
  #[derive(serde::Serialize)]struct Page<'a>{row:&'static str,schema:&'static str,semantic_revision:Hex,source_revision:Hex,policy_revision:Hex,environment:&'a Path,configuration:&'a Path,configuration_explicit:bool,page_width:usize,target_window:usize,full_checker_parity:bool,effect_report_only:bool,byte_fragment_only:bool,output_format:&'static str,requested_cursor:Option<crate::daemon::query::encoded_bytes::ByteCursor>,limit:usize,fragment:crate::daemon::query::encoded_bytes::Fragment,bytes:&'a[u8]}
  let page=Page{row:"source_native_effect_report_bytes",schema:"dm-session-source-query-v1",semantic_revision:Hex(tree.identity().into()),source_revision:Hex(self.source_revision),policy_revision:Hex(self.policy_revision.ok_or_else(||io::Error::other("effect byte frame unissued"))?),environment,configuration:&scope.configuration().selected.path,configuration_explicit:scope.configuration().selected.explicit,page_width:width,target_window,full_checker_parity:false,effect_report_only:true,byte_fragment_only:true,output_format:"source_native_effect_reports_jsonl",requested_cursor:cursor,limit,fragment,bytes:bytes.bytes()};serde_json::to_writer(&mut *output,&page).map_err(io::Error::from)?;output.write_all(b"\n")?;crate::daemon::control::checkpoint()?;scope.validate(db,input).map_err(io::Error::other)
 })
}}
