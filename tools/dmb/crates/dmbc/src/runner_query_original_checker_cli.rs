//! Explicit nondefault pinned-text projection over the SAME whole native Checker.
//! No new parser, analysis model, query roster, diagnostic cache or oracle claim.
use super::{SourceSnapshot,OriginalThroughReaderDeclarations as Reader,OriginalThroughGraph as Graph,
 OriginalThroughKeywords as Keyword,OriginalDeclarationAndBody as Body};
use super::super::OriginalNoticeReplay;
use crate::selected_report_spool::{Stage,Verified};
use dm_analysis::{check_policy::{CheckerPolicy,DiagnosticSeverity},checks::{Diagnostic,Note}};
use dm_preprocess::source_arena_credit::{SourceArenaCredit,SourceArenaWork};
use dm_tree::frontend::{OriginalDiagnosticPoint,OriginalPreprocessNotice};
use dm_preprocess::regions::OriginalNoticeRegistration;
use std::{io::{self,Read,Write},path::Path};
fn invalid(s:&'static str)->io::Error{io::Error::new(io::ErrorKind::InvalidData,s)}
fn header(out:&mut impl Write,(path,line,column):(&Path,usize,usize),severity:DiagnosticSeverity,message:&str)->io::Result<()> {
 writeln!(out,"{}, line {line}, column {column}:",path.display())?;
 writeln!(out,"{}: {message}",super::super::named_policy::severity(severity))
}
fn diagnostic(out:&mut impl Write,at:(&Path,usize,usize),level:DiagnosticSeverity,row:&Diagnostic)->io::Result<()> {
 header(out,at,level,&row.message)?;
 for note in &row.notes{crate::daemon::control::checkpoint()?;legacy_note(out,note)?;}writeln!(out)
}
fn legacy_note(out:&mut impl Write,note:&Note)->io::Result<()> {
 // Same existing Note::legacy_text shape without allocating a cloned String.
 match &note.source{Some(source)=>writeln!(out,"- {}:{}: {}",source.line,source.byte_column,note.message),None=>writeln!(out,"- {}",note.message)}
}
fn notice_point<'a>(point:OriginalDiagnosticPoint<'a>)->(&'a Path,usize,usize){match point{
 OriginalDiagnosticPoint::Default=>(Path::new("(unknown)"),0,0),
 OriginalDiagnosticPoint::Builtins=>(Path::new("(builtins)"),1,1),
 OriginalDiagnosticPoint::Acquired{reported_path,line,byte_column,..}=>(reported_path,line,byte_column),
}}
#[derive(Clone,Copy,Default)]
pub(crate) struct DiagnosticCounts{pub(crate)hint:usize,pub(crate)info:usize,pub(crate)warning:usize,pub(crate)error:usize}
impl DiagnosticCounts{pub(crate) fn register(&mut self,level:DiagnosticSeverity)->io::Result<()>{let count=match level{DiagnosticSeverity::Hint=>&mut self.hint,DiagnosticSeverity::Info=>&mut self.info,DiagnosticSeverity::Warning=>&mut self.warning,DiagnosticSeverity::Error=>&mut self.error};*count=count.checked_add(1).ok_or_else(||invalid("Checker severity count overflow"))?;Ok(())}
 pub(crate)fn merge(&mut self,other:Self)->io::Result<()>{let next=Self{hint:self.hint.checked_add(other.hint).ok_or_else(||invalid("Checker severity count overflow"))?,info:self.info.checked_add(other.info).ok_or_else(||invalid("Checker severity count overflow"))?,warning:self.warning.checked_add(other.warning).ok_or_else(||invalid("Checker severity count overflow"))?,error:self.error.checked_add(other.error).ok_or_else(||invalid("Checker severity count overflow"))?};*self=next;Ok(())}
 pub(crate)fn write_json(self,out:&mut impl Write)->io::Result<()>{write!(out,"{{\"error\":{},\"hint\":{},\"info\":{},\"warning\":{}}}",self.error,self.hint,self.info,self.warning)}}
fn preprocess_notice(out:&mut impl Write,notice:OriginalPreprocessNotice<'_>,policy:&CheckerPolicy,counts:&mut DiagnosticCounts)->io::Result<usize>{
 crate::daemon::control::checkpoint()?;
 use dm_preprocess::regions::OriginalNoticeSeverity as S;
 let default=match notice.severity{S::Error=>DiagnosticSeverity::Error,S::Warning=>DiagnosticSeverity::Warning,S::Hint=>DiagnosticSeverity::Hint};
 let Some(level)=policy.register(notice.error_type,default)else{return Ok(0)};
 counts.register(level)?;if !dm_analysis::check_policy::cli_printed(level){return Ok(0)}
 let at=notice_point(notice.point);header(out,at,level,notice.message)?;
 for note in notice.notes{crate::daemon::control::checkpoint()?;let(point,message)=note.map_err(invalid)?;let next=notice_point(point);
  if next==at{writeln!(out,"- {message}")?}else if next.0==at.0{writeln!(out,"- {}:{}: {message}",next.1,next.2)?}else{writeln!(out,"- {}:{}:{}: {message}",next.0.display(),next.1,next.2)?}
 }writeln!(out)?;Ok(1)
}
/// Merge two genuine ordered registrations, never source-anchor positions or
/// producer-wallclock order. Hidden rows are authenticated before policy drops
/// them. The actual notice owners remain borrowed through final scope checks.
fn flush_preprocess<'a,I:Iterator<Item=Result<OriginalPreprocessNotice<'a>,&'static str>>>(out:&mut impl Write,rows:&mut std::iter::Peekable<I>,until:Option<&OriginalNoticeRegistration>,previous:&mut Option<OriginalNoticeRegistration>,policy:&CheckerPolicy,counts:&mut DiagnosticCounts)->io::Result<usize>{
 let mut count=0usize;
 loop{
  crate::daemon::control::checkpoint()?;
  let Some(next)=rows.peek()else{break};
  let next=next.as_ref().map_err(|error|invalid(*error))?;
  let registration=next.registration.ok_or_else(||io::Error::new(io::ErrorKind::Unsupported,"actual preprocess registration chronology is unissued"))?;
  if let Some(previous)=previous.as_ref(){if previous.compare_same_source(registration)?==std::cmp::Ordering::Greater{return Err(invalid("actual preprocess registration order moved backwards"))}}
  if let Some(until)=until{if registration.compare_same_source(until)?==std::cmp::Ordering::Greater{break}}
  *previous=Some(registration.clone());
  let row=rows.next().expect("actual peeked row remains in this iterator").map_err(invalid)?;
  count=count.checked_add(preprocess_notice(out,row,policy,counts)?).ok_or_else(||invalid("checker notice count overflow"))?;
 }
 Ok(count)
}
fn body_diagnostic(out:&mut impl Write,input:&dm_analysis::checker_effects::EffectInput,row:&dm_analysis::checker_effects::OriginalBodyDiagnostic,level:DiagnosticSeverity)->io::Result<()>{
 use dm_analysis::checker_effects::OriginalDiagnosticLocation as L;
 let point=match row.location(){L::Expanded=>Some(input.archive().borrowed_source_note_point(row.diagnostic().span.start).map_err(io::Error::other)?),L::Reader(at)=>Some(input.archive().source_mapping().borrow_stored_original_reported_point(at).map_err(io::Error::other)?),L::ParserSynthetic=>None};
 let at=point.as_ref().map_or((Path::new("(unknown)"),0,0),|p|p.reported_coordinates());diagnostic(out,at,level,row.diagnostic())
}
fn compact_body_text(input:&dm_analysis::checker_effects::EffectInput,row:&dm_analysis::checker_effects::OriginalBodyDiagnostic,level:DiagnosticSeverity,mut out:&mut dyn Write)->io::Result<()>{body_diagnostic(&mut out,input,row,level)}
fn row(out:&mut impl Write,input:&dm_analysis::checker_effects::EffectInput,value:Reader<'_>,level:DiagnosticSeverity)->io::Result<()> {
 match value{
  Reader::Declaration(finding)=>{let at=finding.borrowed_reported_point().map_err(io::Error::other)?;diagnostic(out,at.coordinates(),level,finding.diagnostic())}
  Reader::Semantic(Graph::Source(Keyword::Source(Body::Declaration(finding))))=>{let point=input.archive().borrowed_source_note_point(finding.diagnostic().span.start).map_err(io::Error::other)?;diagnostic(out,point.reported_coordinates(),level,finding.diagnostic())}
  Reader::Semantic(Graph::Source(Keyword::Source(Body::Body{row,..})))=>body_diagnostic(out,input,row,level),
  Reader::Semantic(Graph::Source(Keyword::Keyword{findings,row}))=>{let point=findings.point(row.point).map_err(io::Error::other)?;header(out,point.coordinates(),level,&row.message)?;
   for note in &row.notes{crate::daemon::control::checkpoint()?;writeln!(out,"- {}",findings.legacy_note(row.point,note).map_err(io::Error::other)?)?;}writeln!(out)
  }
  Reader::Semantic(Graph::Graph(finding))=>{
   if finding.phase()==dm_analysis::checker_effects::ProducedPhase::BodyImmediate{return Err(invalid("immediate effect is not final Checker graph output"))}
   let point=input.archive().borrowed_source_note_point(finding.diagnostic.span.start).map_err(io::Error::other)?;diagnostic(out,point.reported_coordinates(),level,&finding.diagnostic)
  }
 }
}
/// Only the successful real full ordered traversal below constructs this value.
/// It is current-producer scope evidence, NOT independently established parity.
pub(crate) struct Transcript{
 stderr:Option<Verified>,pub(crate) counts:DiagnosticCounts,pub(crate) emitted:usize,pub(crate) visited_bodies:usize,
 pub(crate) semantic:u128,pub(crate) source:u128,pub(crate) policy:u128,
 _credit:SourceArenaCredit,
}
impl Transcript{pub(crate) fn publish(self,out:&mut impl Write)->io::Result<()>{match self.stderr{Some(stream)=>stream.publish(out),None=>out.flush()}}}
impl SourceSnapshot{
 pub(crate) fn stage_original_checker_cli(&self,environment:&Path,explicit:Option<&Path>,cache:&Path,inputs:&crate::request_runner::checker_capture::Inputs)->io::Result<Transcript>{
  self.require_analysis_context(Some(crate::policy_request::AnalysisContext::OriginalChecker0290))?;
  let mapping=self.source_mapping.as_ref().ok_or_else(||invalid("Checker source mapping absent"))?;inputs.require_binding(environment,mapping,self.tree.identity(),self.source_revision)?;
  let owner=self.original_checker_request_input(&self.tree)?;
  let input=dm_analysis::checker_effects::EffectInput::original_checker_source_with_current_bodies(
   std::sync::Arc::clone(owner.input().archive()),owner.input().profile(),
   self.diagnostic_declarations.as_ref().ok_or_else(||invalid("Checker declaration receipt absent"))?,
   self.native_raw_queries.as_deref().ok_or_else(||invalid("Checker query owner absent"))?,
  ).map_err(io::Error::other)?;
  let input=&input;
  self.with_effect_scope(input,environment,explicit,&self.tree,|db,scope|{
   let credit=SourceArenaWork::reserve(db,16384usize.checked_add(2*std::mem::size_of::<Stage>()+std::mem::size_of::<DiagnosticCounts>()+std::mem::size_of::<usize>()).and_then(|n|n.checked_add(std::mem::size_of::<Transcript>())).ok_or_else(||invalid("checker stage control width overflow"))?)?;
   let mut stage=Stage::new(cache)?;
   let notices=match &self.original_notice_replay{
    OriginalNoticeReplay::Retained(owner)=>{if self.source_mapping.as_ref().is_none_or(|mapping|!owner.matches_mapping(mapping)){return Err(invalid("Checker notices belong to another actual source mapping"))}owner.borrow()},
    OriginalNoticeReplay::Released=>return Err(io::Error::new(io::ErrorKind::NotConnected,"Checker notice owner pressure-released; reprepare required")),
    OriginalNoticeReplay::Ordinary=>return Err(io::Error::new(io::ErrorKind::Unsupported,"native Checker lacks its actual Original notice owner")),
   };
   let mut preprocess_rows=notices.iter().peekable();let mut previous_preprocess=None;let mut previous_reader:Option<OriginalNoticeRegistration>=None;let mut reader_phase_closed=false;let mut emitted=0usize;let mut counts=DiagnosticCounts::default();
   let mut head_row=|value:Reader<'_>,level:DiagnosticSeverity|{
    // Count genuine registered rows before the unchanged text visibility gate.
    // Hidden rows do not borrow display data or alter the visible causal merge.
    counts.register(level)?;if !dm_analysis::check_policy::cli_printed(level){return Ok(())}
    let extra=if let Reader::Declaration(finding)=&value{
     if reader_phase_closed{return Err(invalid("reader registration appeared after semantic Checker phase"))}
     let registration=finding.reader_registration().map_err(io::Error::other)?;
     if let Some(previous)=&previous_reader{if previous.compare_same_source(&registration)?==std::cmp::Ordering::Greater{return Err(invalid("actual reader registration order moved backwards"))}}
     previous_reader=Some(registration.clone());
     flush_preprocess(&mut stage,&mut preprocess_rows,Some(&registration),&mut previous_preprocess,scope.policy(),&mut counts)?
    }else{reader_phase_closed=true;flush_preprocess(&mut stage,&mut preprocess_rows,None,&mut previous_preprocess,scope.policy(),&mut counts)?};
    emitted=emitted.checked_add(extra).ok_or_else(||invalid("Checker diagnostic count overflow"))?;
    row(&mut stage,input,value,level)?;emitted=emitted.checked_add(1).ok_or_else(||invalid("Checker diagnostic count overflow"))?;Ok(())
   };
   // SAME registered reader/global producers; real registration chronology.
   let checkpoint=crate::daemon::control::checkpoint;
   db.visit_original_reader_declarations(input,&checkpoint,|finding|{
    let default=finding.original_fixed_level().ok_or_else(||invalid("original reader diagnostic lacks genuine default severity"))?;
    if let Some(level)=scope.policy().register(finding.registration_tag(),default){head_row(Reader::Declaration(finding),level)?;}Ok(())
   })?;
   db.with_original_declarations(input,self.tree.as_ref(),&checkpoint,|findings|{for finding in findings.rows(){checkpoint()?;if let Some(level)=scope.policy().register(finding.registration_tag(),finding.default_severity()){head_row(Reader::Semantic(Graph::Source(Keyword::Source(Body::Declaration(finding)))),level)?;}}Ok(())})?;
   drop(head_row);
   // Remaining PP rows precede later visible semantic rows, or occur at end
   // when none exist. This is the prior visitor's same visible ordering.
   emitted=emitted.checked_add(flush_preprocess(&mut stage,&mut preprocess_rows,None,&mut previous_preprocess,scope.policy(),&mut counts)?).ok_or_else(||invalid("Checker diagnostic count overflow"))?;
   let tail=std::cell::RefCell::new((Stage::new(cache)?,DiagnosticCounts::default(),0usize));
   let(prelude,body,body_counts,body_emitted,completed)=db.with_archived_compact_cli_report_completed(
    input,scope,dm_analysis::checker_order::ARCHIVED_CHUNK_WIDTH,cache,compact_body_text,
    |findings|{
     use dm_analysis::checks_keyword_overrides::{DEFAULT_SEVERITY,REGISTRATION_TAG};
     if let Some(level)=scope.policy().register(Some(REGISTRATION_TAG),DEFAULT_SEVERITY){for finding in findings.rows(){checkpoint()?;let mut tail=tail.borrow_mut();tail.1.register(level)?;if dm_analysis::check_policy::cli_printed(level){row(&mut tail.0,input,Reader::Semantic(Graph::Source(Keyword::Keyword{findings,row:finding})),level)?;tail.2=tail.2.checked_add(1).ok_or_else(||invalid("Checker diagnostic count overflow"))?;}}}Ok(())
    },
    |finding|{let level=finding.severity;let mut tail=tail.borrow_mut();tail.1.register(level)?;if dm_analysis::check_policy::cli_printed(level){row(&mut tail.0,input,Reader::Semantic(Graph::Graph(finding)),level)?;tail.2=tail.2.checked_add(1).ok_or_else(||invalid("Checker diagnostic count overflow"))?;}Ok(())},
   )?;
   let visited_bodies=completed.body_count_for(input)?;
   let(tail,tail_counts,tail_emitted)=tail.into_inner();counts.merge(body_counts)?;counts.merge(tail_counts)?;
   emitted=emitted.checked_add(body_emitted).and_then(|n|n.checked_add(tail_emitted)).ok_or_else(||invalid("Checker diagnostic count overflow"))?;
   if stage.length().checked_add(prelude.length()).and_then(|n|n.checked_add(body.length())).and_then(|n|n.checked_add(tail.length())).is_none_or(|n|n>dq_analyze::selected_exclusions_wire::MAX_STREAM){return Err(io::Error::new(io::ErrorKind::OutOfMemory,"Checker registered transcript exceeds existing stream bound"))}
   prelude.publish(&mut stage)?;body.publish(&mut stage)?;
   if tail.length()!=0{let(tail,())=tail.seal()?.validate(|stream|{io::copy(stream,&mut io::sink()).map(|_|())})?;tail.publish(&mut stage)?;}
   let stderr=if stage.length()==0{None}else{let(sealed,())=stage.seal()?.validate(|stream|{let mut scratch=[0u8;8192];loop{crate::daemon::control::checkpoint()?;let count=stream.read(&mut scratch)?;if count==0{break}}Ok(())})?;Some(sealed)};
   scope.validate(db,input).map_err(io::Error::other)?;inputs.require_binding(environment,mapping,self.tree.identity(),self.source_revision)?;
   Ok(Transcript{stderr,counts,emitted,visited_bodies,semantic:self.tree.identity(),source:self.source_revision,policy:self.policy_revision.ok_or_else(||invalid("Checker policy revision absent"))?,_credit:credit})
  })
 }
}
#[cfg(test)]mod formatting_controls{
 use super::*;
 #[test]fn checker_text_keeps_pinned_location_message_note_and_blank_line_shape(){
  let mut out=Vec::new();header(&mut out,(Path::new("code/example.dm"),3,7),DiagnosticSeverity::Warning,"actual message").unwrap();
  legacy_note(&mut out,&Note{message:"(builtins):1:1: previous definition".into(),source:None}).unwrap();writeln!(out).unwrap();
  assert_eq!(out,b"code/example.dm, line 3, column 7:\nwarning: actual message\n- (builtins):1:1: previous definition\n\n");
 }
 #[test]fn checker_default_and_builtin_notice_coordinates_keep_reference_file_registry_sentinels(){
  assert_eq!(notice_point(OriginalDiagnosticPoint::Default),(Path::new("(unknown)"),0,0));assert_eq!(notice_point(OriginalDiagnosticPoint::Builtins),(Path::new("(builtins)"),1,1));
 }
 #[test]fn checker_text_returns_first_real_output_io_unchanged(){struct Failed;impl Write for Failed{fn write(&mut self,_:&[u8])->io::Result<usize>{Err(io::Error::from_raw_os_error(1450))}fn flush(&mut self)->io::Result<()>{panic!("no flush after first output failure")}}
  assert_eq!(header(&mut Failed,(Path::new("actual.dm"),1,1),DiagnosticSeverity::Error,"message").unwrap_err().raw_os_error(),Some(1450));
 }
}

#[cfg(test)]mod json_count_controls{use super::*;#[test]fn registered_counts_keep_hidden_hints_without_text_or_visibility_reclassification(){let mut counts=DiagnosticCounts::default();for level in[DiagnosticSeverity::Hint,DiagnosticSeverity::Info,DiagnosticSeverity::Warning,DiagnosticSeverity::Error]{counts.register(level).unwrap();}let mut bytes=Vec::new();counts.write_json(&mut bytes).unwrap();assert_eq!(bytes,b"{\"error\":1,\"hint\":1,\"info\":1,\"warning\":1}");assert!(!dm_analysis::check_policy::cli_printed(DiagnosticSeverity::Hint));assert!(dm_analysis::check_policy::cli_printed(DiagnosticSeverity::Info));}
#[test]fn actual_json_count_output_preserves_first_io_and_count_overflow(){struct Fail;impl Write for Fail{fn write(&mut self,_:&[u8])->io::Result<usize>{Err(io::Error::from_raw_os_error(1450))}fn flush(&mut self)->io::Result<()>{panic!("no flush after first JSON write error")}}let counts=DiagnosticCounts::default();assert_eq!(counts.write_json(&mut Fail).unwrap_err().raw_os_error(),Some(1450));let mut full=DiagnosticCounts{hint:usize::MAX,..Default::default()};assert!(full.register(DiagnosticSeverity::Hint).is_err());assert_eq!(full.hint,usize::MAX);}}

// Actual parser-only reporting over the separate syntax/recorder purpose.
struct ParserRows<'a>{formals:Vec<dm_tree::frontend::OriginalParserFormalNotice<'a>>,bodies:Vec<dm_tree::frontend::OriginalCommittedBodyDiagnostic<'a>>,_credit:SourceArenaCredit}
fn parser_rows<'a>(front:&'a dm_tree::frontend::DiagnosticFrontend,work:&dyn SourceArenaWork)->io::Result<ParserRows<'a>>{
 let source=front.parse_only_syntax_source()?;let mut n=0usize;source.visit_formal_notices(&crate::daemon::control::checkpoint,&mut|_|{n=n.checked_add(1).ok_or(io::ErrorKind::OutOfMemory)?;Ok(())})?;let(_,bad)=source.body_counts()?;
 let bytes=n.checked_mul(4*std::mem::size_of::<dm_tree::frontend::OriginalParserFormalNotice<'_>>()).and_then(|n|n.checked_add(bad.checked_mul(4*std::mem::size_of::<dm_tree::frontend::OriginalCommittedBodyDiagnostic<'_>>())?)).and_then(|n|n.checked_add(std::mem::size_of::<ParserRows<'_>>())).ok_or(io::ErrorKind::OutOfMemory)?;
 let credit=work.reserve(bytes)?;let mut formals=Vec::new();let mut bodies=Vec::new();formals.try_reserve_exact(n).map_err(|actual|io::Error::new(io::ErrorKind::OutOfMemory,actual))?;bodies.try_reserve_exact(bad).map_err(|actual|io::Error::new(io::ErrorKind::OutOfMemory,actual))?;
 if formals.capacity()>n.saturating_mul(4)||bodies.capacity()>bad.saturating_mul(4){return Err(io::ErrorKind::OutOfMemory.into())}
 source.visit_formal_notices(&crate::daemon::control::checkpoint,&mut|row|{if formals.len()==n{return Err(invalid("parser formal row inventory grew"))}formals.push(row);Ok(())})?;
 front.visit_parse_only_body_diagnostics(&crate::daemon::control::checkpoint,&mut|row|{if bodies.len()==bad{return Err(invalid("parser BODY row inventory grew"))}bodies.push(row);Ok(())})?;if formals.len()!=n||bodies.len()!=bad{return Err(invalid("parser diagnostic inventory differs"))}Ok(ParserRows{formals,bodies,_credit:credit})
}
struct ParserFormatIo<'a,W>{out:&'a mut W,first:Option<io::Error>}
impl<W:Write>std::fmt::Write for ParserFormatIo<'_,W>{fn write_str(&mut self,text:&str)->std::fmt::Result{if self.first.is_some(){return Err(std::fmt::Error)}match self.out.write_all(text.as_bytes()){Ok(())=>Ok(()),Err(actual)=>{self.first=Some(actual);Err(std::fmt::Error)}}}}
fn parser_formal(out:&mut impl Write,row:&dm_tree::frontend::OriginalParserFormalNotice<'_>,level:DiagnosticSeverity)->io::Result<()>{let(path,line,column)=row.point.reported_coordinates();writeln!(out,"{}, line {line}, column {column}:",path.display())?;write!(out,"{}: ",super::super::named_policy::severity(level))?;let mut fmt=ParserFormatIo{out,first:None};let result=row.notice.write_message(row.value,&mut fmt);if let Some(actual)=fmt.first{return Err(actual)}result.map_err(|_|invalid("actual formal message rendering failed"))?;writeln!(fmt.out,"\n")}
fn parser_reader(previous:&mut Option<OriginalNoticeRegistration>,next:&OriginalNoticeRegistration)->io::Result<()>{if let Some(previous)=previous.as_ref(){if previous.compare_same_source(next)?==std::cmp::Ordering::Greater{return Err(invalid("parser report registration moved backwards"))}}*previous=Some(next.clone());Ok(())}
fn parser_flush_formals<'a,'b,I:Iterator<Item=Result<OriginalPreprocessNotice<'b>,&'static str>>>(out:&mut impl Write,formals:&mut std::iter::Peekable<std::slice::Iter<'a,dm_tree::frontend::OriginalParserFormalNotice<'b>>>,until:&OriginalNoticeRegistration,preprocess:&mut std::iter::Peekable<I>,previous_pp:&mut Option<OriginalNoticeRegistration>,previous_reader:&mut Option<OriginalNoticeRegistration>,policy:&CheckerPolicy,counts:&mut DiagnosticCounts,emitted:&mut usize)->io::Result<()>{
 while let Some(next)=formals.peek(){crate::daemon::control::checkpoint()?;if next.registration.compare_same_source(until)?==std::cmp::Ordering::Greater{break}let row=formals.next().expect("actual peeked formal row");parser_reader(previous_reader,row.registration)?;*emitted=emitted.checked_add(flush_preprocess(out,preprocess,Some(row.registration),previous_pp,policy,counts)?).ok_or(io::ErrorKind::OutOfMemory)?;let(tag,level)=row.notice.registration();let default=match level{dm_tree::OriginalFormalNoticeLevel::Error=>DiagnosticSeverity::Error,dm_tree::OriginalFormalNoticeLevel::Warning=>DiagnosticSeverity::Warning,dm_tree::OriginalFormalNoticeLevel::Hint=>DiagnosticSeverity::Hint};if let Some(level)=policy.register(tag,default){counts.register(level)?;if dm_analysis::check_policy::cli_printed(level){parser_formal(out,row,level)?;*emitted=emitted.checked_add(1).ok_or(io::ErrorKind::OutOfMemory)?;}}}Ok(())
}
pub(crate)struct ParserTranscript{stderr:Option<Verified>,pub(crate)counts:DiagnosticCounts,pub(crate)emitted:usize,pub(crate)good:usize,pub(crate)bad:usize,pub(crate)fatal:bool,pub(crate)semantic:u128,pub(crate)source:u128,pub(crate)policy:u128,_credit:SourceArenaCredit}
impl ParserTranscript{pub(crate)fn publish(self,out:&mut impl Write)->io::Result<()>{match self.stderr{Some(stream)=>stream.publish(out),None=>out.flush()}}}
impl crate::runner_host::BuildHost{
 pub(crate)fn stage_parse_only_cli(&self,prepared:&crate::request_runner::ParseOnlySyntaxPrepared,environment:&Path,explicit:Option<&Path>,cache:&Path)->io::Result<ParserTranscript>{
  crate::daemon::control::checkpoint()?;prepared.inputs.require_parse_only_binding(environment,&prepared.frontend)?;let source=prepared.frontend.parse_only_syntax_source()?;let view=source.source_view()?;let(good,bad)=source.body_counts()?;
  // Unsupported finalization families are not silently dropped from a parser
  // transcript. The existing parent/constant renderer is still a separate gate.
  if view.receipt().errors().iter().any(|error|!matches!(error,dm_tree::TreeError::Duplicate{kind:dm_tree::MemberKind::Proc|dm_tree::MemberKind::Verb,..}|dm_tree::TreeError::OriginalMissingParent{..})){return Err(io::Error::new(io::ErrorKind::Unsupported,"parser finalization outcome is not yet issued for this source"))}
  let db=self.query_db();let policy=super::super::named_policy::configuration(&prepared.policy,environment,explicit)?;
  let credit=SourceArenaWork::reserve(db.as_ref(),16384usize.checked_add(std::mem::size_of::<Stage>()).and_then(|n|n.checked_add(std::mem::size_of::<ParserTranscript>())).ok_or(io::ErrorKind::OutOfMemory)?)?;
  let rows=parser_rows(&prepared.frontend,db.as_ref())?;let notices=view.original_preprocess_notices().ok_or_else(||invalid("parse-only actual preprocess notice owner absent"))?;let mut preprocess=notices.iter().peekable();let mut formals=rows.formals.iter().peekable();let mut bodies=rows.bodies.iter().peekable();let mut previous_pp=None;let mut previous_reader=None;let mut emitted=0usize;let mut counts=DiagnosticCounts::default();let mut stage=Stage::new(cache)?;
  db.visit_parser_declaration_rows(&source,|event|{
   use dm_analysis::checks_proc_visibility::ParserDeclarationEvent as E;
   match event{
    E::Commit{ordinal,registration}=>{parser_flush_formals(&mut stage,&mut formals,&registration,&mut preprocess,&mut previous_pp,&mut previous_reader,&policy.policy,&mut counts,&mut emitted)?;
     let occurrence=view.archive().occurrences().get(ordinal).ok_or_else(||invalid("actual parser declaration occurrence absent"))?;
     while let Some(next)=bodies.peek(){if next.header().start!=occurrence.expanded_span.start{break}let row=bodies.next().expect("actual peeked BODY row");if row.reader_registration().compare_same_source(&registration)?!=std::cmp::Ordering::Equal{return Err(invalid("actual BODY diagnostic differs from its declaration commit"))}parser_reader(&mut previous_reader,row.reader_registration())?;emitted=emitted.checked_add(flush_preprocess(&mut stage,&mut preprocess,Some(row.reader_registration()),&mut previous_pp,&policy.policy,&mut counts)?).ok_or(io::ErrorKind::OutOfMemory)?;if let Some(level)=policy.policy.register(None,DiagnosticSeverity::Error){counts.register(level)?;if dm_analysis::check_policy::cli_printed(level){header(&mut stage,row.point().reported_coordinates(),level,&row.native().message)?;writeln!(&mut stage)?;emitted=emitted.checked_add(1).ok_or(io::ErrorKind::OutOfMemory)?;}}}
     parser_reader(&mut previous_reader,&registration)?;
    },
    E::Diagnostic(finding)=>{let registration=finding.reader_registration().map_err(io::Error::other)?;parser_reader(&mut previous_reader,&registration)?;emitted=emitted.checked_add(flush_preprocess(&mut stage,&mut preprocess,Some(&registration),&mut previous_pp,&policy.policy,&mut counts)?).ok_or(io::ErrorKind::OutOfMemory)?;let default=finding.original_fixed_level().unwrap_or(DiagnosticSeverity::Error);if let Some(level)=policy.policy.register(finding.registration_tag(),default){counts.register(level)?;if dm_analysis::check_policy::cli_printed(level){diagnostic(&mut stage,finding.borrowed_reported_point().map_err(io::Error::other)?.coordinates(),level,finding.diagnostic())?;emitted=emitted.checked_add(1).ok_or(io::ErrorKind::OutOfMemory)?;}}}
   }Ok(())
  })?;
  let end=source.reader_frontier_registration()?;
  parser_flush_formals(&mut stage,&mut formals,&end,&mut preprocess,&mut previous_pp,&mut previous_reader,&policy.policy,&mut counts,&mut emitted)?;if formals.next().is_some()||bodies.next().is_some(){return Err(invalid("actual parser report left diagnostic registrations unconsumed"))}parser_reader(&mut previous_reader,&end)?;
  emitted=emitted.checked_add(flush_preprocess(&mut stage,&mut preprocess,None,&mut previous_pp,&policy.policy,&mut counts)?).ok_or(io::ErrorKind::OutOfMemory)?;
  let settings=std::sync::Arc::clone(db)as std::sync::Arc<dyn dm_tree::frontend::SettingExpressionQueries>;let fatal=prepared.frontend.parse_only_fatal_report(&settings).map_err(|failure|match failure{dm_tree::frontend::FrontendBuildFailure::Operational(actual)=>actual,other=>io::Error::new(io::ErrorKind::Unsupported,other.to_string())})?;
  if let Some(fatal)=&fatal{let fatal=dm_tree::frontend::original_fatal_preparation_outcome(fatal).ok_or_else(||invalid("actual typed parser fatal outcome absent"))?;if let Some(level)=policy.policy.register(None,DiagnosticSeverity::Error){counts.register(level)?;if dm_analysis::check_policy::cli_printed(level){header(&mut stage,fatal.location(),level,fatal.message())?;fatal.write_notes(&mut stage)?;writeln!(&mut stage)?;emitted=emitted.checked_add(1).ok_or(io::ErrorKind::OutOfMemory)?;}}}else if source.is_fatal(){return Err(invalid("actual fatal prefix omitted its typed error"))}
  if bad!=0{let total=good.checked_add(bad).ok_or(io::ErrorKind::OutOfMemory)?;let percent=good.checked_mul(100).ok_or(io::ErrorKind::OutOfMemory)?/total;writeln!(&mut stage,"parsed {good}/{total} proc bodies ({percent}%)")?;}
  db.visit_parser_parent_rows(&source,|finding|{let default=finding.original_fixed_level().unwrap_or(DiagnosticSeverity::Error);if let Some(level)=policy.policy.register(finding.registration_tag(),default){counts.register(level)?;if dm_analysis::check_policy::cli_printed(level){diagnostic(&mut stage,finding.borrowed_reported_point().map_err(io::Error::other)?.coordinates(),level,finding.diagnostic())?;emitted=emitted.checked_add(1).ok_or(io::ErrorKind::OutOfMemory)?;}}Ok(())})?;
  let stderr=if stage.length()==0{None}else{let(sealed,())=stage.seal()?.validate(|stream|{let mut scratch=[0u8;8192];loop{crate::daemon::control::checkpoint()?;let n=stream.read(&mut scratch)?;if n==0{break}}Ok(())})?;Some(sealed)};
  prepared.inputs.require_parse_only_binding(environment,&prepared.frontend)?;Ok(ParserTranscript{stderr,counts,emitted,good,bad,fatal:source.is_fatal(),semantic:view.tree().identity(),source:view.source_revision(),policy:prepared.policy.policy_revision().ok_or_else(||invalid("actual parser policy revision absent"))?,_credit:credit})
 }
}
