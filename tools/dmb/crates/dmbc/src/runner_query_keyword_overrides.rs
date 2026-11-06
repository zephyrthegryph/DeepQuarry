//! Whole original keyword family, with one ephemeral fold and borrowed output.
use super::SourceSnapshot;
use dm_analysis::checks_keyword_overrides::{Findings,Finding,Point,DEFAULT_SEVERITY,REGISTRATION_TAG};
use serde::{Serialize,Serializer,ser::{SerializeSeq,SerializeStruct}};
use std::{fmt,io::{self,Write},path::Path};
struct EncodedNote<'a>(dm_analysis::checks_keyword_overrides::LegacyNote<'a>);
impl Serialize for EncodedNote<'_>{fn serialize<S:Serializer>(&self,s:S)->Result<S::Ok,S::Error>{s.collect_str(&self.0)}}
struct Notes<'a>{findings:&'a Findings<'a>,row:&'a Finding}
impl Serialize for Notes<'_>{fn serialize<S:Serializer>(&self,s:S)->Result<S::Ok,S::Error>{let mut seq=s.serialize_seq(Some(self.row.notes.len()))?;for note in &self.row.notes{seq.serialize_element(&EncodedNote(self.findings.legacy_note(self.row.point,note).map_err(serde::ser::Error::custom)?))?;}seq.end()}}
struct Row<'a>{findings:&'a Findings<'a>,row:&'a Finding,severity:&'static str}
impl Serialize for Row<'_>{fn serialize<S:Serializer>(&self,s:S)->Result<S::Ok,S::Error>{use serde::ser::Error;let point=self.findings.point(self.row.point).map_err(S::Error::custom)?;let(path,line,column)=point.coordinates();let span=match self.row.point{Point::Source(at)=>Some([at.start,at.end]),Point::Builtin=>None};let mut out=s.serialize_struct("KeywordOverrideDiagnostic",10)?;out.serialize_field("family",REGISTRATION_TAG)?;out.serialize_field("severity",self.severity)?;out.serialize_field("file",path)?;out.serialize_field("line",&line)?;out.serialize_field("column",&column)?;out.serialize_field("location_kind",if span.is_some(){"source"}else{"builtin"})?;out.serialize_field("expanded_span",&span)?;out.serialize_field("expression_span",&span)?;out.serialize_field("message",&self.row.message)?;out.serialize_field("notes",&Notes{findings:self.findings,row:self.row})?;out.end()}}
struct Rows<'a>{findings:&'a Findings<'a>,severity:&'static str,enabled:bool}
impl Serialize for Rows<'_>{fn serialize<S:Serializer>(&self,s:S)->Result<S::Ok,S::Error>{let mut out=s.serialize_seq(Some(if self.enabled{self.findings.rows().len()}else{0}))?;for row in self.findings.rows().iter().filter(|_|self.enabled){out.serialize_element(&Row{findings:self.findings,row,severity:self.severity})?;}out.end()}}
struct Revision(u128);impl fmt::Display for Revision{fn fmt(&self,f:&mut fmt::Formatter<'_>)->fmt::Result{write!(f,"{:032x}",self.0)}}impl Serialize for Revision{fn serialize<S:Serializer>(&self,s:S)->Result<S::Ok,S::Error>{s.collect_str(self)}}
#[derive(Serialize)]struct Envelope<'a>{row:&'static str,schema:&'static str,semantic_revision:Revision,source_revision:Revision,policy_revision:Revision,family:&'static str,environment:&'a Path,configuration:&'a Path,configuration_explicit:bool,configuration_present:bool,configuration_schema:&'static str,coverage:&'static str,body_count:usize,complete:bool,full_checker_parity:bool,declaration_profile:&'static str,native_declaration_error_count:usize,diagnostics:Rows<'a>}
impl SourceSnapshot{
 pub(crate) fn write_native_keyword_overrides(&self,environment:&Path,explicit:Option<&Path>,tree:&dm_tree::SemanticTree,output:&mut impl Write)->io::Result<()>{
  crate::daemon::control::checkpoint()?;let capture=self.named_policy_capture(tree)?;let loaded=super::named_policy::configuration(capture,environment,explicit)?;let archive=capture.policy().archive();let db=self.native_raw_queries.as_ref().ok_or_else(||io::Error::other("keyword fold requires actual source QueryDb"))?;let profile=tree.checker_builtin_profile().ok_or_else(||io::Error::other("keyword fold actual builtin profile absent"))?;
  let resolver:&dyn dm_ir::Resolver=if let Some(receipt)=&self.diagnostic_declarations{if !receipt.authenticates(tree)||!self.matches_tree(tree){return Err(io::Error::other("keyword diagnostic owner is foreign"))}tree}else{self.resolved.as_ref().ok_or_else(||io::Error::other("keyword fold requires actual retained semantic host"))?.checker_resolver(tree)?};
  let level=loaded.policy.register(Some(REGISTRATION_TAG),DEFAULT_SEVERITY);
  let deliver=|findings:&Findings<'_>|{
   if !findings.belongs_to(archive){return Err(io::Error::other("keyword fold returned foreign findings"))}for row in findings.rows(){findings.point(row.point).map_err(io::Error::other)?;for note in &row.notes{findings.point(note.point).map_err(io::Error::other)?;}}
   let rendered=Rows{findings,severity:super::named_policy::severity(level.unwrap_or(DEFAULT_SEVERITY)),enabled:level.is_some()};
   let envelope=Envelope{row:"source_native_keyword_override_checker",schema:"dm-session-source-query-v1",semantic_revision:Revision(tree.identity()),source_revision:Revision(self.source_revision),policy_revision:Revision(self.policy_revision.unwrap()),family:REGISTRATION_TAG,environment,configuration:&loaded.selected.path,configuration_explicit:loaded.selected.explicit,configuration_present:loaded.present,configuration_schema:"complete_pinned_checker_schema",coverage:"whole_original_archive",body_count:archive.len(),complete:true,full_checker_parity:false,declaration_profile:self.diagnostic_declarations.as_ref().map_or("strict-native-declarations",|r|r.profile()),native_declaration_error_count:self.diagnostic_declarations.as_ref().map_or(0,|r|r.errors().len()),diagnostics:rendered};
   // Configured suppression changes delivery, not source/owner authentication.
   serde_json::to_writer(&mut *output,&envelope).map_err(io::Error::from)?;output.write_all(b"\n")?;crate::daemon::control::checkpoint()?;self.named_policy_capture(tree)?;Ok(())
  };
  if let Some(owner)=self.native_effect_request_input.get().filter(|owner|owner.input().is_original_checker_source()){
   db.with_cached_original_keyword_overrides(owner.input(),resolver,||{crate::daemon::control::checkpoint()?;self.named_policy_capture(tree)?;Ok(())},deliver)
  }else{db.with_original_keyword_overrides(archive,resolver,profile,||{crate::daemon::control::checkpoint()?;self.named_policy_capture(tree)?;Ok(())},deliver)}
 }
}
