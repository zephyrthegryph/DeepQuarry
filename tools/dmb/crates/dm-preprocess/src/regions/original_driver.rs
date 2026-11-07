//! The actual owned raw/macro/logical continuation. It never prepares a source,
//! rescans an expanded String, manufactures source EOF or grants model success.
//! The directive owner handles a real Hash event before this continuation may
//! pull again; callable parsing loans this same continuation synchronously.
use super::{environment::OriginalEnvironment,original_raw_inputs::{OriginalRawInputs,OriginalRawNoticeSink},original_output_queue::OriginalOutputQueue,original_macro_source::{OriginalBorrowedMacroSource,OriginalMacroHost},original_token_pump::{OriginalTokenPump,PumpEvent},original_conditional::Frame};
use crate::{SourceProvider,SourceAcquisitionLease,InitialEnvironment,macro_expansion::{OriginalMacroRows as Rows,OriginalMacroToken as Token,OriginalMacroOrigin as Origin,OriginalMacroNotice as MacroNotice,OriginalMacroDefinition as Definition}};
use dm_syntax::{SettingAdmission,SettingRootLease,NativeIndentTransition,NativeIndentEmission,NativeIndentNotice};
use std::{io,collections::BTreeMap,mem};

/// One output from the genuine indentation producer. A synthetic delimiter has
/// its saved actual token location; an empty input keeps the old nonphysical
/// default location explicit instead of inventing a physical line/column.
#[derive(Clone)]struct LogicalLocation{origin:Option<Origin>,trace:super::original_output_trace::OriginalOutputTrace}
pub(super) enum LogicalToken{Actual(Token<'static>),Delimiter{spelling:&'static str,location:Option<Origin>}}
pub(super) enum ConditionResult{Value(bool),DisabledAfterExpansion,SourceFailure(crate::macro_expansion::OriginalMacroText),SourceWarning(crate::macro_expansion::OriginalMacroText)}
pub(super) struct ConditionEvaluation{pub(super) last_input:Origin,pub(super) outcome:ConditionResult,pub(super) failure_at:Option<Origin>}
/// Productive definition result DATA; warning/history registration stays on
/// the same controller. FILE_DIR has ordinary replacement, only no warning.
pub(super) enum DefinitionInstallation{IgnoredDebugOutsideEnvironment,Installed{origin:Origin,replaced:bool,previous_name:Option<Origin>,warn_redefinition:bool}}
pub(super) struct Undefinition{pub(super) found:bool,pub(super) previous_name:Option<Origin>,pub(super) removed:Option<std::sync::Arc<super::environment::OriginalDefinitionProduct>>}
pub(super) enum NamedConditionResult{Completed,SourceFailure(crate::macro_expansion::OriginalMacroText)}
pub(super) enum DriverEvent{Token(LogicalToken),Directive{hash:Origin},MacroNotice(MacroNotice),IndentNotice{kind:NativeIndentNotice,location:Option<Origin>},ConditionalEof(super::original_conditional::Unterminated),NeedInput,ActualEnd,Stopped}
/// Fields are ordered so all physical payloads die before the fixed allowance.
/// Raw backings remain under their genuine acquisition/weak-ledger owners when
/// a frame retires; this allowance pays only the live controller's fixed bytes.
pub(super) struct RawSourceDriver{
 environment:OriginalEnvironment,inputs:OriginalRawInputs,pump:OriginalTokenPump,
 history_purpose:super::original_define_history::HistoryPurpose,
 queue:OriginalOutputQueue<'static>,conditionals:Rows<Frame>,
 held:Option<Token<'static>>,indent:NativeIndentTransition<LogicalLocation>,delivery:Option<super::original_output_trace::OriginalOutputTrace>,
 raw_end:bool,failed:bool,stopped:bool,env_file:Option<super::original_file_path::OriginalFilePath>,credit:SettingRootLease,
}
fn poll(a:&SettingAdmission<'_>)->io::Result<()>{a.checkpoint().map_err(|e|a.take_operational_error().unwrap_or(e))}
impl RawSourceDriver{
 pub(super) fn new(initial:InitialEnvironment,caller:&BTreeMap<String,String>,a:&SettingAdmission<'_>,factory:&mut dyn FnMut(crate::initial_environment::OriginalInitialDefinition<'_>,&SettingAdmission<'_>)->io::Result<Definition<'static>>)->io::Result<Self>{
  poll(a)?;let credit=a.reserve(mem::size_of::<Self>()).map_err(|e|a.take_operational_error().unwrap_or(e))?;
  let mut environment=OriginalEnvironment::new(a)?;environment.install_initial_definitions_using(initial,caller,a,factory)?;
  Ok(Self{environment,history_purpose:super::original_define_history::HistoryPurpose::Full,inputs:OriginalRawInputs::new(a)?,pump:OriginalTokenPump::new(a)?,queue:OriginalOutputQueue::new(a)?,conditionals:Rows::new(a)?,held:None,indent:NativeIndentTransition::original_0290(LogicalLocation{origin:None,trace:Default::default()}),delivery:None,raw_end:false,failed:false,stopped:false,env_file:None,credit})
 }
 /// The productive controller supplies the constructor's exact env_file
 /// spelling, matching pinned Preprocessor::new; no canonicalization guessed.
 pub(super) fn new_for_project(initial:InitialEnvironment,caller:&BTreeMap<String,String>,env_file:&std::path::Path,history_purpose:super::original_define_history::HistoryPurpose,a:&SettingAdmission<'_>,factory:&mut dyn FnMut(crate::initial_environment::OriginalInitialDefinition<'_>,&SettingAdmission<'_>)->io::Result<Definition<'static>>)->io::Result<Self>{
  let mut actual=Self::new(initial,caller,a,factory)?;actual.history_purpose=history_purpose;actual.env_file=Some(super::original_file_path::OriginalFilePath::new(env_file,a)?);Ok(actual)
 }
 /// #ifdef/__MAIN__ uses the nearest active physical file, not the macro
 /// definition/invocation occurrence. Ordinary defined() does not call this.
 pub(super) fn in_environment_using(&mut self,a:&SettingAdmission<'_>)->io::Result<bool>{
  self.check(a)?;let result=(||{let env=self.env_file.as_ref().ok_or_else(||io::Error::new(io::ErrorKind::Unsupported,"actual constructor environment file is unissued"))?;if !env.is_admitted_by(a){return Err(io::ErrorKind::InvalidInput.into())}Ok(self.inputs.current_physical_path(a)?.is_some_and(|path|path==env.path()))})();if result.is_err(){self.failed=true}result
 }
 pub(super) fn is_defined_using(&mut self,name:&str,a:&SettingAdmission<'_>)->io::Result<bool>{
  self.check(a)?;if name=="__MAIN__"{return self.in_environment_using(a)}let result=self.environment.read().actual_original_product(name).map(|actual|actual.is_some());if result.is_err(){self.failed=true}result
 }
 /// Adopt the SAME actual acquired input registered by the directive owner,
 /// with the spelling used by that actual source read. Private DATA only.
 pub(super) fn push_opened_at(&mut self,provider:&dyn SourceProvider,lease:SourceAcquisitionLease,occurrence:usize,path:&std::path::Path,a:&SettingAdmission<'_>)->io::Result<()>{
  self.check(a)?;if self.raw_end||self.stopped{return Err(io::ErrorKind::InvalidInput.into())}let result=self.inputs.push_opened_at(provider,lease,occurrence,self.pump.expansion_depth(),path,a);if result.is_err(){self.failed=true}result
 }
 fn check(&mut self,a:&SettingAdmission<'_>)->io::Result<()>{if self.failed{return Err(io::Error::new(io::ErrorKind::InvalidInput,"failed raw source continuation cannot resume or seal"))}let result=if !a.matches_lease_domain(&self.credit){Err(io::Error::new(io::ErrorKind::InvalidInput,"raw source continuation belongs to another admission"))}else{poll(a)};if result.is_err(){self.failed=true}result}
 pub(super) fn stop(&mut self){self.stopped=true;self.pump.stop()}
 /// Called only with the lease returned by the existing admitted read/adopt
 /// operation, and the occurrence installed by the actual directive owner.
 pub(super) fn push_opened(&mut self,provider:&dyn SourceProvider,lease:SourceAcquisitionLease,occurrence:usize,a:&SettingAdmission<'_>)->io::Result<()>{
  self.check(a)?;if self.raw_end||self.stopped{return Err(io::ErrorKind::InvalidInput.into())}
  let result=self.inputs.push_opened(provider,lease,occurrence,self.pump.expansion_depth(),a);if result.is_err(){self.failed=true}result
 }
 /// Actual physical read opens through the shared input-family kernel; no
 /// raw gate is retained during lexical/directive/formal work. Ok(false) is
 /// the issuer's recorded bounded negative read, never an unissued fallback.
 pub(super) fn read_and_push_using(&mut self,provider:&dyn SourceProvider,path:&std::path::Path,occurrence:usize,max_raw_bytes:usize,work:&dyn crate::source_arena_credit::SourceArenaWork,a:&SettingAdmission<'_>)->io::Result<bool>{
  self.check(a)?;if self.raw_end||self.stopped{return Err(io::ErrorKind::InvalidInput.into())}
  let result=(||{let Some(lease)=crate::source_arena_credit::read_original_source_using(provider,path,max_raw_bytes,work)?else{return Ok(false)};self.inputs.push_opened_at(provider,lease,occurrence,self.pump.expansion_depth(),path,a)?;Ok(true)})();if result.is_err(){self.failed=true}result
 }
 pub(super) fn next_logical_using(&mut self,provider:&dyn SourceProvider,notices:&mut dyn OriginalRawNoticeSink,host:&mut dyn OriginalMacroHost,a:&SettingAdmission<'_>)->io::Result<DriverEvent>{
  self.check(a)?;self.delivery=None;if self.stopped{return Ok(DriverEvent::Stopped)}let result=self.next_inner(provider,notices,host,a);if result.is_err(){self.failed=true}result
 }
 fn next_inner(&mut self,provider:&dyn SourceProvider,notices:&mut dyn OriginalRawNoticeSink,host:&mut dyn OriginalMacroHost,a:&SettingAdmission<'_>)->io::Result<DriverEvent>{
  loop{poll(a)?;
   // Drain every output/notice of the already processed raw token BEFORE
   // requesting another macro/source token. A long closing-brace run can pause
   // at any logical batch boundary without advancing the input frontier.
   if let Some(event)=self.indent.next_using(a)?{let trace=match &event{NativeIndentEmission::Notice{location,..}|NativeIndentEmission::Punctuation{location,..}|NativeIndentEmission::Keep{location}=>location.trace.clone()};self.delivery=Some(trace);return match event{
    NativeIndentEmission::Notice{kind,location}=>Ok(DriverEvent::IndentNotice{kind,location:location.origin}),
    NativeIndentEmission::Punctuation{spelling,location}=>Ok(DriverEvent::Token(LogicalToken::Delimiter{spelling,location:location.origin})),
    NativeIndentEmission::Keep{location}=>{let token=self.held.take().ok_or(io::ErrorKind::InvalidData)?;if location.origin!=Some(token.origin){return Err(io::ErrorKind::InvalidData.into())}Ok(DriverEvent::Token(LogicalToken::Actual(token)))},
   }}
   // Whitespace skipped by the SAME transition is physically retired only
   // after that transition has no remaining output; Keep already moved it.
   self.held.take();
   if self.raw_end{return Ok(DriverEvent::ActualEnd)}
   let mut source=OriginalBorrowedMacroSource{inputs:&mut self.inputs,environment:self.environment.read(),queue:&mut self.queue,provider,notices,host};
   match self.pump.next_using(&mut source,self.conditionals.as_slice(),a)?{
    PumpEvent::Token(token)=>{let trace=self.pump.take_delivery_trace()?;self.indent.begin_using(&token.value,LogicalLocation{origin:Some(token.origin),trace},a)?;self.held=Some(token);},
    PumpEvent::Directive{hash}=>return Ok(DriverEvent::Directive{hash}),
    PumpEvent::Notice(notice)=>return Ok(DriverEvent::MacroNotice(notice)),
    PumpEvent::NeedInput=>return Ok(DriverEvent::NeedInput),
    PumpEvent::Stopped=>{self.stopped=true;return Ok(DriverEvent::Stopped)},
    PumpEvent::ActualInputEnd=>{
     // Only the genuine exhausted raw/include/macro producer reaches this
     // branch. Drain one LIFO history/error event before ending indentation.
     if self.conditionals.len()!=0{let completed=self.pump.last_outer().ok_or(io::ErrorKind::InvalidData)?;let actual=super::original_conditional::pop_at_actual_eof_using(&mut self.conditionals,completed,a)?.ok_or(io::ErrorKind::InvalidData)?;return Ok(DriverEvent::ConditionalEof(actual))}
     self.raw_end=true;self.indent.end_input_using(a)?;
    },
   }
  }
 }
 /// The actual directive controller borrows this SAME cursor/raw stack. No
 /// expanded next(), new dictionary or physical-only definition scanner.
 pub(super) fn next_directive_raw_using(&mut self,provider:&dyn SourceProvider,notices:&mut dyn OriginalRawNoticeSink,host:&mut dyn OriginalMacroHost,a:&SettingAdmission<'_>)->io::Result<crate::macro_expansion::OriginalMacroRawStep<'static>>{
  self.check(a)?;let result=(||{let cursor=self.pump.cursor_for_directive()?;let mut source=OriginalBorrowedMacroSource{inputs:&mut self.inputs,environment:self.environment.read(),queue:&mut self.queue,provider,notices,host};cursor.next_undispatched_using(&mut source,a)})();if result.is_err(){self.failed=true}result
 }
 pub(super) fn finish_directive_using(&mut self,success:bool,provider:&dyn SourceProvider,notices:&mut dyn OriginalRawNoticeSink,host:&mut dyn OriginalMacroHost,a:&SettingAdmission<'_>)->io::Result<()>{
  self.check(a)?;let result={let mut source=OriginalBorrowedMacroSource{inputs:&mut self.inputs,environment:self.environment.read(),queue:&mut self.queue,provider,notices,host};self.pump.finish_directive(success,&mut source,a)};if result.is_err(){self.failed=true}result
 }
 pub(super) fn with_directive_source_using<T>(&mut self,provider:&dyn SourceProvider,notices:&mut dyn OriginalRawNoticeSink,host:&mut dyn OriginalMacroHost,a:&SettingAdmission<'_>,run:impl FnOnce(&mut crate::macro_expansion::OriginalMacroCursor<'static>,&mut OriginalBorrowedMacroSource<'_>)->io::Result<T>)->io::Result<T>{
  self.check(a)?;let result=(||{let cursor=self.pump.cursor_for_directive()?;let mut source=OriginalBorrowedMacroSource{inputs:&mut self.inputs,environment:self.environment.read(),queue:&mut self.queue,provider,notices,host};run(cursor,&mut source)})();if result.is_err(){self.failed=true}result
 }
 pub(super) fn directive_request_using(&mut self,provider:&dyn SourceProvider,notices:&mut dyn OriginalRawNoticeSink,host:&mut dyn OriginalMacroHost,a:&SettingAdmission<'_>,hint:&mut dyn FnMut(&mut RawSourceDriver,Origin,&'static str)->io::Result<()>)->io::Result<super::original_directive_dispatch::DirectiveRequest>{
  self.check(a)?;let result=super::original_directive_dispatch::read_using(self,provider,notices,host,a,hint);if result.is_err(){self.failed=true}result
 }
 pub(super) fn advance_define_using(&mut self,demand:&mut super::original_define_demand::OriginalDefineDemand,provider:&dyn SourceProvider,notices:&mut dyn OriginalRawNoticeSink,host:&mut dyn OriginalMacroHost,a:&SettingAdmission<'_>)->io::Result<super::original_define_demand::DefineDemandProgress>{
  self.with_directive_source_using(provider,notices,host,a,|cursor,source|demand.advance(cursor,source,a))
 }
 /// Definition tokens and docs move directly into the SAME current Binding.
 /// The separately funded native metadata mirror preserves genuine spelling;
 /// it is never consulted by the Original expansion cursor.
 pub(super) fn install_defined_using(&mut self,defined:crate::macro_expansion::OriginalDefinedMacro<'static>,provider:&dyn SourceProvider,origin:Option<super::DefinitionOrigin>,a:&SettingAdmission<'_>)->io::Result<DefinitionInstallation>{
  self.check(a)?;let result=(||{let crate::macro_expansion::OriginalDefinedMacro{name,definition,docs}=defined;let crate::macro_expansion::OriginalMacroValue::Ident{spelling:ref name_text,..}=name.value else{return Err(io::ErrorKind::InvalidData.into())};
   if name_text.get()=="DEBUG"&&!self.in_environment_using(a)?{return Ok(DefinitionInstallation::IgnoredDebugOutsideEnvironment)}
   let previous=self.environment.read().actual_original_product(name_text.get())?;let replaced=previous.is_some();let previous_name=previous.and_then(|p|p.definition_name()).map(|token|token.origin());let warn_redefinition=name_text.get()!="FILE_DIR";
   let mut mirror=crate::macro_expansion::OriginalMacroText::new(a)?;for token in definition.replacement.as_slice(){poll(a)?;let spelling=super::original_literal_owner::actual_grammar_spelling_using(token,provider,a)?;if !mirror.as_str().is_empty(){mirror.push_str(" ",a)?;}mirror.push_str(spelling.as_str(),a)?;}
   let name_origin=name.origin;let product=super::environment::OriginalDefinitionProduct::from_named_actual_product_using(name,definition,docs,origin,self.history_purpose,a)?;let name=product.definition_name().ok_or(io::ErrorKind::InvalidData)?.spelling();self.environment.insert_product_using(name,mirror.as_str(),None,std::sync::Arc::clone(&product),a)?;Ok(DefinitionInstallation::Installed{origin:name_origin,replaced,previous_name,warn_redefinition})})();if result.is_err(){self.failed=true}result
 }
 pub(super) fn undefine_using(&mut self,name:&str,a:&SettingAdmission<'_>)->io::Result<Undefinition>{
  self.check(a)?;let result=(||{let removed=self.environment.read().original_current_owner_using(name,a)?;let found=removed.is_some();let previous_name=removed.as_deref().and_then(|p|p.definition_name()).map(|t|t.origin());self.environment.remove_using(name,a)?;Ok(Undefinition{found,previous_name,removed})})();if result.is_err(){self.failed=true}result
 }
 pub(super) fn directive_disabled_using(&mut self,a:&SettingAdmission<'_>)->io::Result<bool>{self.check(a)?;let result=super::original_conditional::is_disabled_using(self.conditionals.as_slice(),a);if result.is_err(){self.failed=true}result}
 pub(super) fn begin_conditional_using(&mut self,directive:super::original_conditional::Directive,hash:Origin,a:&SettingAdmission<'_>)->io::Result<super::original_conditional::Action>{self.check(a)?;let result=super::original_conditional::begin_using(&mut self.conditionals,directive,hash,a);if result.is_err(){self.failed=true}result}
 pub(super) fn finish_conditional_using(&mut self,pending:super::original_conditional::Pending,outcome:super::original_conditional::Outcome,completed:Origin,a:&SettingAdmission<'_>)->io::Result<()>{self.check(a)?;let result=pending.finish_using(&mut self.conditionals,outcome,completed,a);if result.is_err(){self.failed=true}result}
 /// Same raw identifier + newline expectations, then actual nearest-file
 /// special case. Both reads occur even under an inactive parent, as old.
 pub(super) fn finish_named_condition_using(&mut self,pending:super::original_conditional::Pending,provider:&dyn SourceProvider,notices:&mut dyn OriginalRawNoticeSink,host:&mut dyn OriginalMacroHost,a:&SettingAdmission<'_>)->io::Result<NamedConditionResult>{
  self.check(a)?;let result=(||{if !matches!(pending.instruction(),super::original_conditional::Instruction::DefinedName{..}){return Err(io::ErrorKind::InvalidInput.into())}
   let read=|kind,pattern,self_:&mut RawSourceDriver,notices:&mut dyn OriginalRawNoticeSink,host:&mut dyn OriginalMacroHost|self_.with_directive_source_using(provider,notices,host,a,|cursor,source|super::original_directive_arguments::expect_using(cursor,source,kind,Some(pattern),a));
   let name=match read(super::original_directive_arguments::Expected::Identifier,"Token::Ident(define_name, _)",self,notices,host)?{super::original_directive_arguments::ExpectProgress::Token(token)=>token,super::original_directive_arguments::ExpectProgress::SourceFailure(message)=>{self.finish_conditional_using(pending,super::original_conditional::Outcome::InvalidRawName,self.pump.last_outer().ok_or(io::ErrorKind::InvalidData)?,a)?;return Ok(NamedConditionResult::SourceFailure(message))},super::original_directive_arguments::ExpectProgress::NeedInput=>return Err(io::ErrorKind::WouldBlock.into())};
   match read(super::original_directive_arguments::Expected::Newline,"Token::Punct(Punctuation::Newline)",self,notices,host)?{super::original_directive_arguments::ExpectProgress::Token(_)=>(),super::original_directive_arguments::ExpectProgress::SourceFailure(message)=>{self.finish_conditional_using(pending,super::original_conditional::Outcome::InvalidRawName,self.pump.last_outer().ok_or(io::ErrorKind::InvalidData)?,a)?;return Ok(NamedConditionResult::SourceFailure(message))},super::original_directive_arguments::ExpectProgress::NeedInput=>return Err(io::ErrorKind::WouldBlock.into())};
   let crate::macro_expansion::OriginalMacroValue::Ident{spelling,..}=&name.value else{return Err(io::ErrorKind::InvalidData.into())};let enabled=self.is_defined_using(spelling.get(),a)?;self.finish_conditional_using(pending,super::original_conditional::Outcome::Value(enabled),self.pump.last_outer().ok_or(io::ErrorKind::InvalidData)?,a)?;Ok(NamedConditionResult::Completed)
  })();if result.is_err(){self.failed=true}result
 }
 pub(super) fn evaluate_condition_using(&mut self,hash:Origin,provider:&dyn SourceProvider,notices:&mut dyn OriginalRawNoticeSink,host:&mut dyn OriginalMacroHost,a:&SettingAdmission<'_>,notice:&mut dyn FnMut(&mut RawSourceDriver,MacroNotice)->io::Result<()>)->io::Result<ConditionEvaluation>{self.evaluate_condition_with_directives_using(hash,provider,notices,host,a,notice,&mut|_,_|Err(io::Error::new(io::ErrorKind::Unsupported,"actual nested directive consumer is unissued")))}
 pub(super) fn evaluate_condition_with_directives_using(&mut self,hash:Origin,provider:&dyn SourceProvider,notices:&mut dyn OriginalRawNoticeSink,host:&mut dyn OriginalMacroHost,a:&SettingAdmission<'_>,notice:&mut dyn FnMut(&mut RawSourceDriver,MacroNotice)->io::Result<()>,directive:&mut dyn FnMut(&mut RawSourceDriver,Origin)->io::Result<()>)->io::Result<ConditionEvaluation>{
  self.check(a)?;let result=(||{
   let mut pump=super::original_conditional_pump::OriginalConditionPump::new(hash);
   loop{
    let progress=self.with_directive_source_using(provider,notices,host,a,|cursor,source|pump.advance(cursor,source,a))?;
    self.pump.record_conditional_outer(pump.last_input());
    match progress{
     super::original_conditional_pump::ConditionPumpProgress::Complete=>break,
     super::original_conditional_pump::ConditionPumpProgress::Notice(actual)=>notice(self,actual)?,
     super::original_conditional_pump::ConditionPumpProgress::NeedInput=>return Err(io::Error::new(io::ErrorKind::WouldBlock,"actual synchronous conditional source is unavailable")),
     super::original_conditional_pump::ConditionPumpProgress::Directive{hash}=>{self.pump.begin_nested_directive_using(a)?;directive(self,hash)?;},
    }
   }
   let completed=pump.into_completed()?;let last_input=completed.last_input();
   if super::original_conditional::is_disabled_using(self.conditionals.as_slice(),a)?{self.queue.discard_values();return Ok(ConditionEvaluation{last_input,outcome:ConditionResult::DisabledAfterExpansion,failure_at:None})}
   let mut tokens=super::original_condition_tokens::OriginalConditionTokens::new(&mut self.queue,provider,a,completed)?;let syntax=dm_syntax::parse_original_expression_demanded(&mut tokens,a)?;
   tokens.observe_notices_using(syntax.parsed().original_input_notices().ok_or_else(||io::Error::new(io::ErrorKind::Unsupported,"actual Original condition notice producer is unissued"))?,notices)?;
   if let Some(expected)=syntax.expected_delimiter(){let(message,at)=tokens.delimiter_failure_using(expected,hash)?;return Ok(ConditionEvaluation{last_input,outcome:ConditionResult::SourceFailure(message),failure_at:Some(at)})}
   if let Some(expected)=syntax.expected_term(){let(message,at)=tokens.failure_using(expected.token_span(),None,hash)?;return Ok(ConditionEvaluation{last_input,outcome:ConditionResult::SourceFailure(message),failure_at:Some(at)})}
   if let Some(expected)=syntax.parsed().original_input_failure(){let(message,at)=tokens.failure_using(expected.token_span(),Some(expected.expected()),hash)?;return Ok(ConditionEvaluation{last_input,outcome:ConditionResult::SourceFailure(message),failure_at:Some(at)})}

   // Native syntax recovery alone is not an old condition diagnostic receipt.
   // Refuse explicitly until the SAME parser branch/typed notice join exists.
   if !syntax.parsed().diagnostics.is_empty(){return Err(io::Error::new(io::ErrorKind::Unsupported,"actual Original malformed condition diagnostic branch is unissued"))}
   let expression=syntax.parsed().expr.as_ref().ok_or_else(||io::Error::new(io::ErrorKind::Unsupported,"actual Original empty condition diagnostic branch is unissued"))?;
   // defined() uses the current map without the nearest-file #ifdef exception.
   let macros=self.environment.read();
   let actual_host=std::cell::RefCell::new(host);
   let evaluated=super::original_condition_value::evaluate_with_debug_inputs_using(expression,&macros,a,Some(&mut|passed|actual_host.try_borrow_mut().map_err(|_|a.take_operational_error().unwrap_or_else(||io::Error::new(io::ErrorKind::InvalidInput,"actual condition host was re-entered")))?.condition_file_exists_using(hash,passed,provider,a)),syntax.parsed().original_constructor_facts(),Some(&mut|child,out|tokens.write_expression_debug_using(child,out,&mut|occurrence|actual_host.try_borrow_mut().map_err(|_|a.take_operational_error().unwrap_or_else(||io::Error::new(io::ErrorKind::InvalidInput,"actual condition Debug host was re-entered")))?.condition_debug_file_id_using(occurrence,a))))?;
   drop(tokens);
   let outcome=match evaluated{super::original_condition_value::Outcome::Value(value)=>ConditionResult::Value(value),super::original_condition_value::Outcome::SourceFailure(message)=>ConditionResult::SourceFailure(message),super::original_condition_value::Outcome::SourceWarning(message)=>ConditionResult::SourceWarning(message),super::original_condition_value::Outcome::Unissued(reason)=>return Err(io::Error::new(io::ErrorKind::Unsupported,reason))};
   let failure_at=matches!(&outcome,ConditionResult::SourceFailure(_)|ConditionResult::SourceWarning(_)).then_some(hash);Ok(ConditionEvaluation{last_input,outcome,failure_at})
  })();if result.is_err(){self.failed=true}result
 }
 pub(super) fn take_delivery_trace_using(&mut self,a:&SettingAdmission<'_>)->io::Result<super::original_output_trace::OriginalOutputTrace>{self.check(a)?;self.delivery.take().ok_or_else(||io::ErrorKind::InvalidInput.into())}
 pub(super) fn last_outer_using(&mut self,a:&SettingAdmission<'_>)->io::Result<Origin>{self.check(a)?;self.pump.last_outer().ok_or_else(||io::Error::new(io::ErrorKind::Unsupported,"actual outer reader has not issued a location"))}
 pub(super) fn capture_final_define_history_using(&mut self,history:&mut super::original_define_history::OriginalDefineHistory,a:&SettingAdmission<'_>)->io::Result<()>{self.check(a)?;let result=if history.is_full()!=(self.history_purpose==super::original_define_history::HistoryPurpose::Full){
  Err(io::Error::new(io::ErrorKind::InvalidInput,"macro product and define history have different purposes"))
 }else{self.environment.read().capture_history_using(history,a)};if result.is_err(){self.failed=true}result}
 pub(super) fn physical_row_using(&mut self,origin:Origin,lease:&SourceAcquisitionLease,provider:&dyn SourceProvider,a:&SettingAdmission<'_>)->io::Result<super::original_raw_inputs::OriginalPhysicalRow>{
  self.observe_physical_row_using(origin,lease,provider,None,a).map(super::original_raw_inputs::OriginalPhysicalRowObservation::into_row)
 }
 pub(super) fn observe_physical_row_using<'source>(&mut self,origin:Origin,lease:&'source SourceAcquisitionLease,provider:&'source dyn SourceProvider,prior:Option<&super::original_raw_inputs::OriginalPhysicalRowObservation<'_>>,a:&SettingAdmission<'_>)->io::Result<super::original_raw_inputs::OriginalPhysicalRowObservation<'source>>{
  self.check(a)?;let result=self.inputs.observe_physical_row_using(origin,lease,provider,prior,a);if result.is_err(){self.failed=true}result
 }

 pub(super) fn include_phantom_newline_using(&mut self,a:&SettingAdmission<'_>)->io::Result<()>{self.check(a)?;let origin=self.last_outer_using(a)?;self.queue.push(Token{value:crate::macro_expansion::OriginalMacroValue::Punct("\n"),origin,string_mode:dm_syntax::OriginalStringMode::Unknown,punctuation_close:false,lexical_frame:None,lexical_span:None,raw_spelling:None},a)}
 pub(super) fn current_location_using(&mut self,provider:&dyn SourceProvider,notices:&mut dyn OriginalRawNoticeSink,host:&mut dyn OriginalMacroHost,a:&SettingAdmission<'_>)->io::Result<super::original_current_location::OriginalCurrentLocation>{self.check(a)?;let result={let cursor=self.pump.cursor_for_location()?;let mut source=OriginalBorrowedMacroSource{inputs:&mut self.inputs,environment:self.environment.read(),queue:&mut self.queue,provider,notices,host};super::original_current_location::current_using(cursor,&mut source,a)};if result.is_err(){self.failed=true}result}
 pub(super) fn current_physical_path_using(&self,a:&SettingAdmission<'_>)->io::Result<Option<&std::path::Path>>{self.inputs.current_physical_path(a)}
 #[cfg(debug_assertions)]
 pub(super) fn trace_last_outer_origin(&self) -> Option<Origin> {
  self.pump.last_outer()
 }
 pub(super) fn decoded_offset_using(&self,occurrence:usize,lease:&SourceAcquisitionLease,raw:usize,a:&SettingAdmission<'_>)->io::Result<usize>{self.inputs.decoded_point_using(occurrence,lease,raw,a)}
 #[cfg(debug_assertions)]
 pub(super) fn trace_macro_reservations(&self) -> (usize, usize, usize) {
  self.environment.trace_reservations()
 }
 pub(super) fn into_final_environment_using(mut self,a:&SettingAdmission<'_>)->io::Result<super::environment::OriginalFinalMacros>{self.check(a)?;let Self{environment,..}=self;environment.into_final_macros_using(a)}
 pub(super) fn environment(&self)->&OriginalEnvironment{&self.environment}
 pub(super) fn environment_mut(&mut self)->&mut OriginalEnvironment{&mut self.environment}

}

#[cfg(test)]mod tests{
 use super::*;use std::{path::Path,sync::{Arc,atomic::{AtomicUsize,Ordering}}};
 use crate::macro_expansion::{OriginalMacroValue as V,OriginalMacroTextValue as _};
 struct File{raw:Vec<u8>,lease:SourceAcquisitionLease}
 impl File{fn new(raw:&str)->Self{Self{raw:raw.as_bytes().to_vec(),lease:SourceAcquisitionLease::from_raw_original_bytes(raw.as_bytes().to_vec(),17u64)}}}
 impl SourceProvider for File{
  fn initial_environment(&self)->InitialEnvironment{InitialEnvironment::OriginalChecker0290}
  fn read(&self,_:&Path)->Result<String,String>{panic!("actual raw driver must never use prepared/read fallback")}
  fn original_source_bytes<'a>(&'a self,lease:&'a SourceAcquisitionLease)->io::Result<Option<&'a[u8]>>{if !lease.same_original_acquisition(&self.lease){return Err(io::ErrorKind::InvalidInput.into())}Ok(Some(&self.raw))}
 }
 struct Notices{lexical:usize,numeric:usize}
 impl OriginalRawNoticeSink for Notices{
  fn lexical(&mut self,_:&super::super::OriginalLexicalFrameIdentity,_:usize,_:super::super::original_raw_points::OriginalRawPoint,_:super::super::original_raw_frame::OriginalRawNotice,_:&SettingAdmission<'_>)->io::Result<()>{self.lexical+=1;Ok(())}
  fn numeric(&mut self,_:&super::super::OriginalLexicalFrameIdentity,_:usize,_:super::super::original_raw_points::OriginalRawPoint,_:dm_syntax::OriginalLexicalNoticePoint,_:dm_syntax::numeric_form::OriginalNumberNotice<'_>,_:&SettingAdmission<'_>)->io::Result<()>{self.numeric+=1;Ok(())}
 }
 struct Host{ordinary:super::super::original_ordinary_output::OriginalOrdinaryOutput,fail:bool}
 impl Host{fn new(a:&SettingAdmission<'_>)->Self{Self{ordinary:super::super::original_ordinary_output::OriginalOrdinaryOutput::new(a).unwrap(),fail:false}}}
 impl OriginalMacroHost for Host{
  fn take_docs_for_define(&mut self,a:&SettingAdmission<'_>)->io::Result<crate::macro_expansion::OriginalMacroRows<crate::macro_expansion::OriginalMacroDoc<'static>>>{self.ordinary.take_docs_for_define(a)}

  fn before_identifier(&mut self,name:&str,origin:Origin,queue:&mut OriginalOutputQueue<'static>,a:&SettingAdmission<'_>)->io::Result<()>{if self.fail{return Err(io::Error::from_raw_os_error(1450))}self.ordinary.before_identifier(name,origin,queue,a)}
  fn ordinary_token(&mut self,token:Token<'static>,queue:&mut OriginalOutputQueue<'static>,a:&SettingAdmission<'_>)->io::Result<()>{self.ordinary.ordinary_token(token,queue,a)}
  fn direct_noncall_output(&mut self,token:&Token<'static>,a:&SettingAdmission<'_>)->io::Result<()>{self.ordinary.direct_noncall_output(token,a)}
  fn dynamic(&mut self,_:bool,_:Origin,_:Option<usize>,_:Option<Origin>,_:&SettingAdmission<'_>)->io::Result<Token<'static>>{panic!("fixture uses no dynamic macro")}
  fn invocation(&mut self,_:&str,_:Origin,_:&SettingAdmission<'_>)->io::Result<()>{Ok(())}
 }
 fn driver(a:&SettingAdmission<'_>)->RawSourceDriver{RawSourceDriver::new(InitialEnvironment::OriginalChecker0290,&BTreeMap::new(),a,&mut|input,a|super::super::original_token_factory::initial_definition_using(input,a,&mut|_|panic!("fixed defaults have no lexical notice"),&mut|_,_|panic!("fixed defaults have no numeric notice"))).unwrap()}
 fn rendered(token:LogicalToken)->String{match token{LogicalToken::Delimiter{spelling,..}=>spelling.into(),LogicalToken::Actual(token)=>match token.value{V::Ident{spelling,..}=>spelling.get().into(),V::Punct(p)=>p.into(),V::Int(n)=>n.to_string(),_=>panic!("fixture scalar kind")}}}
 #[test]fn same_raw_macro_indent_path_counts_logical_units_not_twelve_thousand_physical_blank_lines(){
  let used=Arc::new(AtomicUsize::new(0));let a=SettingAdmission::new(&used,16<<20,&||Ok(()));let text=format!("var/a=1\n{}var/b=2\n","\n".repeat(12000));let file=File::new(&text);let mut driver=driver(&a);driver.push_opened(&file,file.lease.clone(),0,&a).unwrap();let mut host=Host::new(&a);let mut notices=Notices{lexical:0,numeric:0};let mut output=Vec::new();
  loop{match driver.next_logical_using(&file,&mut notices,&mut host,&a).unwrap(){DriverEvent::Token(token)=>output.push(rendered(token)),DriverEvent::ActualEnd=>break,DriverEvent::NeedInput=>continue,_=>panic!("unexpected valid raw stream event")}}
  assert_eq!(output,["var","/","a","=","1",";","var","/","b","=","2",";"]);assert_eq!((notices.lexical,notices.numeric),(0,0));drop((driver,host));assert_eq!(used.load(Ordering::Acquire),0);
 }
 #[test]fn genuine_lazy_stop_never_reads_later_bad_quote_or_publishes_source_end(){
  let used=Arc::new(AtomicUsize::new(0));let a=SettingAdmission::new(&used,16<<20,&||Ok(()));let file=File::new("var/a=1\n\"unterminated");let mut driver=driver(&a);driver.push_opened(&file,file.lease.clone(),0,&a).unwrap();let mut host=Host::new(&a);let mut notices=Notices{lexical:0,numeric:0};let DriverEvent::Token(token)=driver.next_logical_using(&file,&mut notices,&mut host,&a).unwrap()else{panic!("real first token")};assert_eq!(rendered(token),"var");assert!(!driver.raw_end);assert_eq!(notices.lexical,0);driver.stop();assert!(matches!(driver.next_logical_using(&file,&mut notices,&mut host,&a).unwrap(),DriverEvent::Stopped));assert!(!driver.raw_end);assert_eq!(notices.lexical,0);drop((driver,host));assert_eq!(used.load(Ordering::Acquire),0);
 }
 #[test]fn first_real_host_io_poisons_same_controller_and_fresh_owner_can_recover(){
  let used=Arc::new(AtomicUsize::new(0));let a=SettingAdmission::new(&used,16<<20,&||Ok(()));let file=File::new("var/a=1\n");let mut source=driver(&a);source.push_opened(&file,file.lease.clone(),0,&a).unwrap();let mut host=Host::new(&a);host.fail=true;let mut notices=Notices{lexical:0,numeric:0};assert_eq!(source.next_logical_using(&file,&mut notices,&mut host,&a).err().unwrap().raw_os_error(),Some(1450));host.fail=false;assert_eq!(source.next_logical_using(&file,&mut notices,&mut host,&a).err().unwrap().kind(),io::ErrorKind::InvalidInput);assert!(!source.raw_end);drop(source);let mut source=driver(&a);source.push_opened(&file,file.lease.clone(),0,&a).unwrap();assert!(matches!(source.next_logical_using(&file,&mut notices,&mut host,&a).unwrap(),DriverEvent::Token(_)));drop((source,host));assert_eq!(used.load(Ordering::Acquire),0);
 }
 fn project_driver(project:&Path,a:&SettingAdmission<'_>)->RawSourceDriver{RawSourceDriver::new_for_project(InitialEnvironment::OriginalChecker0290,&BTreeMap::new(),project,super::super::original_define_history::HistoryPurpose::Full,a,&mut|input,a|super::super::original_token_factory::initial_definition_using(input,a,&mut|_|panic!("fixed default lexical notice"),&mut|_,_|panic!("fixed default numeric notice"))).unwrap()}
 struct Pair{root:File,child:File}
 impl SourceProvider for Pair{
  fn initial_environment(&self)->InitialEnvironment{InitialEnvironment::OriginalChecker0290}
  fn read(&self,_:&Path)->Result<String,String>{panic!("actual path fixture never prepares another source")}
  fn original_source_bytes<'a>(&'a self,lease:&'a SourceAcquisitionLease)->io::Result<Option<&'a[u8]>>{if lease.same_original_acquisition(&self.root.lease){Ok(Some(&self.root.raw))}else if lease.same_original_acquisition(&self.child.lease){Ok(Some(&self.child.raw))}else{Err(io::ErrorKind::InvalidInput.into())}}
 }
 #[test]fn actual_physical_file_context_returns_to_root_after_child_end_without_guessing_from_token_origin(){
  let used=Arc::new(AtomicUsize::new(0));let a=SettingAdmission::new(&used,32<<20,&||Ok(()));let files=Pair{root:File::new("root\n"),child:File::new("child\n")};let mut source=project_driver(Path::new("project.dme"),&a);source.push_opened_at(&files,files.root.lease.clone(),0,Path::new("project.dme"),&a).unwrap();assert!(source.is_defined_using("__MAIN__",&a).unwrap());assert!(!crate::MacroLookup::contains_key(source.environment.environment(),"__MAIN__"),"defined() uses only the ordinary map, never #ifdef's file special case");source.push_opened_at(&files,files.child.lease.clone(),1,Path::new("child.dm"),&a).unwrap();assert!(!source.is_defined_using("__MAIN__",&a).unwrap());
  let mut notices=Notices{lexical:0,numeric:0};let mut host=Host::new(&a);let mut child_seen=false;let mut returned=false;loop{let event=source.next_logical_using(&files,&mut notices,&mut host,&a).unwrap();if source.inputs.current_occurrence()==Some(0){assert!(source.in_environment_using(&a).unwrap());returned=true;break}match event{DriverEvent::Token(LogicalToken::Actual(Token{value:V::Ident{spelling,..},..}))if spelling.get()=="child"=>child_seen=true,DriverEvent::Token(_)|DriverEvent::NeedInput=>(),_=>panic!("must return from actual child before global end")}}
  assert!(child_seen&&returned);source.stop();assert!(!source.raw_end,"querying file context/pausing is not source EOF");assert_eq!((notices.lexical,notices.numeric),(0,0));drop((source,host));assert_eq!(used.load(Ordering::Acquire),0);
 }
 #[test]fn missing_actual_file_context_is_unissued_and_first_io_cannot_become_false_main(){
  let used=Arc::new(AtomicUsize::new(0));let a=SettingAdmission::new(&used,16<<20,&||Ok(()));let file=File::new("value\n");let mut source=project_driver(Path::new("project.dme"),&a);source.push_opened(&file,file.lease.clone(),0,&a).unwrap();assert_eq!(source.is_defined_using("__MAIN__",&a).unwrap_err().kind(),io::ErrorKind::Unsupported);assert_eq!(source.in_environment_using(&a).unwrap_err().kind(),io::ErrorKind::InvalidInput);drop(source);
  let mut source=project_driver(Path::new("project.dme"),&a);source.push_opened_at(&file,file.lease.clone(),0,Path::new("project.dme"),&a).unwrap();let first=||Err(io::Error::from_raw_os_error(1450));let failed=SettingAdmission::new(&used,16<<20,&first);assert_eq!(source.is_defined_using("__MAIN__",&failed).unwrap_err().raw_os_error(),Some(1450));assert_eq!(source.in_environment_using(&a).unwrap_err().kind(),io::ErrorKind::InvalidInput);drop(source);let mut fresh=project_driver(Path::new("project.dme"),&a);fresh.push_opened_at(&file,file.lease.clone(),0,Path::new("project.dme"),&a).unwrap();assert!(fresh.is_defined_using("__MAIN__",&a).unwrap());drop(fresh);assert_eq!(used.load(Ordering::Acquire),0);
 }


 #[test]fn actual_file_dir_redefinition_and_undef_restore_previous_stack_epoch(){
  use super::super::{original_directive_dispatch::DirectiveRequest as Request,original_conditional::Action};let used=Arc::new(AtomicUsize::new(0));let a=SettingAdmission::new(&used,32<<20,&||Ok(()));let file=File::new("#define FILE_DIR \"one\"\n#define FILE_DIR \"two\"\nFILE_DIR\n#undef FILE_DIR\n#ifdef FILE_DIR\nRESTORED\n#endif\nFILE_DIR\n");let mut source=project_driver(Path::new("project.dme"),&a);source.push_opened_at(&file,file.lease.clone(),0,Path::new("project.dme"),&a).unwrap();let mut host=Host::new(&a);let mut notices=Notices{lexical:0,numeric:0};let mut installed=0;let mut last_value=false;let mut ordinary_after_undef=false;
  loop{match source.next_logical_using(&file,&mut notices,&mut host,&a).unwrap(){DriverEvent::Directive{hash}=>{match source.directive_request_using(&file,&mut notices,&mut host,&a,&mut|_,_,_|panic!("valid definition has no hint")).unwrap(){Request::Define(defined)=>{match source.install_defined_using(defined,&file,None,&a).unwrap(){DefinitionInstallation::Installed{replaced,warn_redefinition,..}=>{assert_eq!(replaced,installed!=0);assert!(!warn_redefinition);installed+=1},_=>panic!("FILE_DIR must install as ordinary definition")}},Request::Undef{name}=>{let V::Ident{spelling,..}=&name.value else{panic!("actual undef name")};assert!(source.undefine_using(spelling.get(),&a).unwrap().found);assert!(source.is_defined_using("FILE_DIR",&a).unwrap());},Request::Conditional(command)=>match source.begin_conditional_using(command,hash,&a).unwrap(){Action::Done{..}=>(),Action::Evaluate{pending,..}=>assert!(matches!(source.finish_named_condition_using(pending,&file,&mut notices,&mut host,&a).unwrap(),NamedConditionResult::Completed)),_=>panic!("matched conditional")},_=>panic!("only define/undef/named conditional in fixture")};source.finish_directive_using(true,&file,&mut notices,&mut host,&a).unwrap();},DriverEvent::Token(LogicalToken::Actual(Token{value:V::String(text),..}))=>{if text.get()=="two"{last_value=true}else{assert_eq!(text.get(),"one");ordinary_after_undef=true}},DriverEvent::Token(LogicalToken::Actual(Token{value:V::Ident{spelling,..},..}))=>{assert_eq!(spelling.get(),"RESTORED")},DriverEvent::Token(_)|DriverEvent::NeedInput=>(),DriverEvent::ActualEnd=>break,_=>panic!("no source notice expected")}}
  assert_eq!(installed,2);assert!(last_value&&ordinary_after_undef);assert!(source.environment.environment().actual_original_product("FILE_DIR").unwrap().is_some(),"one remains restored after popping two");drop((source,host));assert_eq!(used.load(Ordering::Acquire),0);
 }
 #[test]fn actual_nested_source_main_checks_and_debug_definition_use_nearest_physical_file(){
  use super::super::{original_directive_dispatch::DirectiveRequest as Request,original_conditional::Action};let used=Arc::new(AtomicUsize::new(0));let a=SettingAdmission::new(&used,32<<20,&||Ok(()));let files=Pair{root:File::new("#define DEBUG 1\n#ifdef __MAIN__\nroot_yes\n#endif\n#include \"child.dm\"\nDEBUG\n"),child:File::new("#define DEBUG 2\n#ifndef __MAIN__\nchild_yes\n#endif\n")};let mut source=project_driver(Path::new("project.dme"),&a);source.push_opened_at(&files,files.root.lease.clone(),0,Path::new("project.dme"),&a).unwrap();let mut host=Host::new(&a);let mut notices=Notices{lexical:0,numeric:0};let(mut root,mut child,mut debug,mut ignored)=(false,false,false,false);
  loop{match source.next_logical_using(&files,&mut notices,&mut host,&a).unwrap(){DriverEvent::Directive{hash}=>{match source.directive_request_using(&files,&mut notices,&mut host,&a,&mut|_,_,_|panic!("valid definition has no hint")).unwrap(){Request::Define(defined)=>match source.install_defined_using(defined,&files,None,&a).unwrap(){DefinitionInstallation::IgnoredDebugOutsideEnvironment=>ignored=true,DefinitionInstallation::Installed{..}=>()},Request::Include{path}=>{assert!(matches!(&path.value,V::String(text)if text.get()=="child.dm"));source.push_opened_at(&files,files.child.lease.clone(),1,Path::new("child.dm"),&a).unwrap();},Request::Conditional(command)=>match source.begin_conditional_using(command,hash,&a).unwrap(){Action::Done{..}=>(),Action::Evaluate{pending,..}=>assert!(matches!(source.finish_named_condition_using(pending,&files,&mut notices,&mut host,&a).unwrap(),NamedConditionResult::Completed)),_=>panic!("matched conditional")},_=>panic!("only defined and named conditions in fixture")};source.finish_directive_using(true,&files,&mut notices,&mut host,&a).unwrap();},DriverEvent::Token(LogicalToken::Actual(Token{value:V::Ident{spelling,..},..}))=>{root|=spelling.get()=="root_yes";child|=spelling.get()=="child_yes"},DriverEvent::Token(LogicalToken::Actual(Token{value:V::Int(value),..}))=>{assert_eq!(value,1,"child DEBUG must not replace root's actual binding");debug=true},DriverEvent::Token(_)|DriverEvent::NeedInput=>(),DriverEvent::ActualEnd=>break,_=>panic!("no source notice expected")}}
  assert!(root&&child&&debug&&ignored);drop((source,host));assert_eq!(used.load(Ordering::Acquire),0);
 }

 #[test]fn actual_inactive_parent_still_expands_bad_arity_condition_before_global_queue_discard(){
  use super::super::{original_directive_dispatch::DirectiveRequest as Request,original_conditional::{Action,Instruction,Outcome}};
  let used=Arc::new(AtomicUsize::new(0));let a=SettingAdmission::new(&used,32<<20,&||Ok(()));let file=File::new("#define BAD(a,b) a\n#if 0\n#if BAD(1)\nvar/ignored=9\n#endif\n#endif\nvar/value=7\n");let mut source=driver(&a);source.push_opened(&file,file.lease.clone(),0,&a).unwrap();let mut host=Host::new(&a);let mut notices=Notices{lexical:0,numeric:0};let mut arity=0;let mut skipped=false;let mut value=false;
  loop{match source.next_logical_using(&file,&mut notices,&mut host,&a).unwrap(){
   DriverEvent::Directive{hash}=>{
    match source.directive_request_using(&file,&mut notices,&mut host,&a,&mut|_,_,_|panic!("valid macro definition has no hint")).unwrap(){
     Request::Define(defined)=>{source.install_defined_using(defined,&file,None,&a).unwrap();},
     Request::Conditional(command)=>match source.begin_conditional_using(command,hash,&a).unwrap(){
      Action::Done{..}=>(),
      Action::Evaluate{pending,..}=>{assert_eq!(pending.instruction(),Instruction::Expression);let evaluated=source.evaluate_condition_using(hash,&file,&mut notices,&mut host,&a,&mut|_,actual|{assert!(matches!(actual.kind,crate::macro_expansion::OriginalMacroNoticeKind::WrongArity));arity+=1;Ok(())}).unwrap();let outcome=match evaluated.outcome{ConditionResult::Value(value)=>Outcome::Value(value),ConditionResult::DisabledAfterExpansion=>{skipped=true;Outcome::DisabledAfterExpansion},ConditionResult::SourceFailure(_)|ConditionResult::SourceWarning(_)=>panic!("valid active condition has no constant judge error")};source.finish_conditional_using(pending,outcome,evaluated.last_input,&a).unwrap();},
      Action::SourceFailure{..}=>panic!("matched actual conditional stack"),
     },_=>panic!("fixture has only actual define/conditional directives"),
    }
    source.finish_directive_using(true,&file,&mut notices,&mut host,&a).unwrap();
   },
   DriverEvent::Token(LogicalToken::Actual(Token{value:V::Int(7),..}))=>value=true,
   DriverEvent::Token(LogicalToken::Actual(Token{value:V::Ident{spelling,..},..}))if spelling.get()=="ignored"=>panic!("inactive ordinary source cannot reach logical output"),
   DriverEvent::Token(_)=>(),DriverEvent::ActualEnd=>break,_=>panic!("unexpected valid outer stream event"),
  }}assert_eq!(arity,1);assert!(skipped&&value);assert!(source.conditionals.as_slice().is_empty());drop((source,host));assert_eq!(used.load(Ordering::Acquire),0);
 }



 #[test]fn actual_defined_main_expression_is_ordinary_map_while_ifdef_main_uses_current_file(){
  use super::super::{original_directive_dispatch::DirectiveRequest as Request,original_conditional::{Action,Instruction,Outcome}};let used=Arc::new(AtomicUsize::new(0));let a=SettingAdmission::new(&used,32<<20,&||Ok(()));let file=File::new("#if defined(__MAIN__)\nWRONG\n#endif\n#ifdef __MAIN__\nROOT\n#endif\n#if !defined(__MAIN__)\nEXPRESSION\n#endif\n");let mut source=project_driver(Path::new("project.dme"),&a);source.push_opened_at(&file,file.lease.clone(),0,Path::new("project.dme"),&a).unwrap();let mut notices=Notices{lexical:0,numeric:0};let mut host=Host::new(&a);let(mut root,mut expression)=(false,false);
  loop{match source.next_logical_using(&file,&mut notices,&mut host,&a).unwrap(){DriverEvent::Directive{hash}=>{let Request::Conditional(command)=source.directive_request_using(&file,&mut notices,&mut host,&a,&mut|_,_,_|panic!("no definition hint")).unwrap()else{panic!("conditional fixture")};match source.begin_conditional_using(command,hash,&a).unwrap(){Action::Done{..}=>(),Action::Evaluate{pending,..}=>match pending.instruction(){Instruction::DefinedName{..}=>assert!(matches!(source.finish_named_condition_using(pending,&file,&mut notices,&mut host,&a).unwrap(),NamedConditionResult::Completed)),Instruction::Expression=>{let actual=source.evaluate_condition_using(hash,&file,&mut notices,&mut host,&a,&mut|_,_|panic!("valid condition has no macro notice")).unwrap();let ConditionResult::Value(value)=actual.outcome else{panic!("valid top-level conditional must evaluate normally")};source.finish_conditional_using(pending,Outcome::Value(value),actual.last_input,&a).unwrap();}},_=>panic!("matched condition")};source.finish_directive_using(true,&file,&mut notices,&mut host,&a).unwrap();},DriverEvent::Token(LogicalToken::Actual(Token{value:V::Ident{spelling,..},..}))=>{assert_ne!(spelling.get(),"WRONG");root|=spelling.get()=="ROOT";expression|=spelling.get()=="EXPRESSION"},DriverEvent::Token(_)|DriverEvent::NeedInput=>(),DriverEvent::ActualEnd=>break,_=>panic!("valid fixture has no notices")}}
  assert!(root&&expression);drop((source,host));assert_eq!(used.load(Ordering::Acquire),0);
 }


 #[test]fn actual_emitted_macro_token_loans_its_captured_nested_trace_before_any_later_pull(){
  use super::super::original_directive_dispatch::DirectiveRequest as Request;let used=Arc::new(AtomicUsize::new(0));let a=SettingAdmission::new(&used,32<<20,&||Ok(()));let file=File::new("#define OUTER INNER\n#define INNER 7\nOUTER\n");let mut source=project_driver(Path::new("project.dme"),&a);source.push_opened_at(&file,file.lease.clone(),0,Path::new("project.dme"),&a).unwrap();let mut host=Host::new(&a);let mut notices=Notices{lexical:0,numeric:0};let mut captured=false;loop{match source.next_logical_using(&file,&mut notices,&mut host,&a).unwrap(){DriverEvent::Directive{..}=>{let Request::Define(defined)=source.directive_request_using(&file,&mut notices,&mut host,&a,&mut|_,_,_|panic!("valid define")).unwrap()else{panic!("fixture only defines")};source.install_defined_using(defined,&file,None,&a).unwrap();source.finish_directive_using(true,&file,&mut notices,&mut host,&a).unwrap();},DriverEvent::Token(LogicalToken::Actual(Token{value:V::Int(7),..}))=>{let trace=source.take_delivery_trace_using(&a).unwrap();let mut names=Vec::new();trace.visit_inner_to_outer_using(&a,|row|{assert!(row.definition.is_some());names.push(row.name.to_owned());Ok(())}).unwrap();assert_eq!(names,["INNER","OUTER"]);assert!(source.take_delivery_trace_using(&a).is_err());captured=true},DriverEvent::Token(_)|DriverEvent::NeedInput=>(),DriverEvent::ActualEnd=>break,_=>panic!("no notices expected")}}assert!(captured);drop((source,host));assert_eq!(used.load(Ordering::Acquire),0);
 }

 #[test]fn inactive_definition_stringify_is_drained_on_same_raw_cursor_without_becoming_a_directive(){
  use super::super::{original_directive_dispatch::DirectiveRequest as Request,original_conditional::{Action,Outcome}};
  let used=Arc::new(AtomicUsize::new(0));let a=SettingAdmission::new(&used,32<<20,&||Ok(()));let file=File::new("#if 0\n#define SKIP(x) #x #not_argument\n#endif\nvar/value=7\n");let mut source=driver(&a);source.push_opened(&file,file.lease.clone(),0,&a).unwrap();let mut host=Host::new(&a);let mut notices=Notices{lexical:0,numeric:0};let mut ignored=0;let mut value=false;
  loop{match source.next_logical_using(&file,&mut notices,&mut host,&a).unwrap(){
   DriverEvent::Directive{hash}=>{match source.directive_request_using(&file,&mut notices,&mut host,&a,&mut|_,_,_|panic!("disabled definition must not parse parameters or stringify")).unwrap(){
    Request::Ignored=>ignored+=1,
    Request::Conditional(command)=>match source.begin_conditional_using(command,hash,&a).unwrap(){Action::Done{..}=>(),Action::Evaluate{pending,..}=>{let actual=source.evaluate_condition_using(hash,&file,&mut notices,&mut host,&a,&mut|_,_|panic!("valid condition has no macro notice")).unwrap();let ConditionResult::Value(value)=actual.outcome else{panic!("active zero condition")};source.finish_conditional_using(pending,Outcome::Value(value),actual.last_input,&a).unwrap();},_=>panic!("matched conditional")},
    _=>panic!("disabled definition produces no installed macro or source failure"),
   };source.finish_directive_using(true,&file,&mut notices,&mut host,&a).unwrap();},
   DriverEvent::Token(LogicalToken::Actual(Token{value:V::Int(7),..}))=>value=true,
   DriverEvent::Token(_)=>(),DriverEvent::ActualEnd=>break,_=>panic!("disabled stringify cannot become an unknown directive or macro notice"),
  }}assert_eq!(ignored,1);assert!(value);assert!(!source.is_defined_using("SKIP",&a).unwrap());assert_eq!((notices.lexical,notices.numeric),(0,0));drop((source,host));assert_eq!(used.load(Ordering::Acquire),0);
 }

 #[test]fn actual_raw_end_delivers_each_unterminated_conditional_history_before_logical_end(){
  use super::super::{original_directive_dispatch::DirectiveRequest as Request,original_conditional::{Action,Outcome}};let used=Arc::new(AtomicUsize::new(0));let a=SettingAdmission::new(&used,32<<20,&||Ok(()));let file=File::new("#if 1\n#if 1\nvar/value=7\n");let mut source=driver(&a);source.push_opened(&file,file.lease.clone(),0,&a).unwrap();let mut host=Host::new(&a);let mut notices=Notices{lexical:0,numeric:0};let mut missing=Vec::new();let mut value=false;
  loop{match source.next_logical_using(&file,&mut notices,&mut host,&a).unwrap(){
   DriverEvent::Directive{hash}=>{let Request::Conditional(command)=source.directive_request_using(&file,&mut notices,&mut host,&a,&mut|_,_,_|panic!("no definition hint")).unwrap()else{panic!("conditional only")};let Action::Evaluate{pending,..}=source.begin_conditional_using(command,hash,&a).unwrap()else{panic!("if starts evaluation")};let actual=source.evaluate_condition_using(hash,&file,&mut notices,&mut host,&a,&mut|_,_|panic!("no macro notice")).unwrap();let ConditionResult::Value(value)=actual.outcome else{panic!("valid one")};source.finish_conditional_using(pending,Outcome::Value(value),actual.last_input,&a).unwrap();source.finish_directive_using(true,&file,&mut notices,&mut host,&a).unwrap();},
   DriverEvent::Token(LogicalToken::Actual(Token{value:V::Int(7),..}))=>{assert!(missing.is_empty());value=true},
   DriverEvent::ConditionalEof(actual)=>{assert!(value);assert_eq!(actual.message,"unterminated #if/#ifdef");assert!(actual.history.active);assert_eq!(actual.history.from,actual.origin);missing.push(actual.origin.line);},
   DriverEvent::Token(_)|DriverEvent::NeedInput=>(),DriverEvent::ActualEnd=>break,_=>panic!("no other source notice"),
  }}assert_eq!(missing,[2,1]);assert!(source.conditionals.as_slice().is_empty());drop((source,host));assert_eq!(used.load(Ordering::Acquire),0);
 }

 #[test]fn actual_stack_define_pop_preserves_values_and_real_invocation_positions_for_ordinary_and_file_dir(){
  use super::super::{original_directive_dispatch::DirectiveRequest as Request,original_conditional::Action};let used=Arc::new(AtomicUsize::new(0));let a=SettingAdmission::new(&used,32<<20,&||Ok(()));let file=File::new("#define A 1\n#define A 2\nA\n#undef A\nA\n#undef A\n#ifdef A\nWRONG\n#endif\n#define FILE_DIR \"one\"\n#define FILE_DIR \"two\"\nFILE_DIR\n#undef FILE_DIR\nFILE_DIR\n");let mut source=project_driver(Path::new("project.dme"),&a);source.push_opened_at(&file,file.lease.clone(),0,Path::new("project.dme"),&a).unwrap();let mut host=Host::new(&a);let mut notices=Notices{lexical:0,numeric:0};let mut values=Vec::new();
  loop{match source.next_logical_using(&file,&mut notices,&mut host,&a).unwrap(){
   DriverEvent::Directive{hash}=>{match source.directive_request_using(&file,&mut notices,&mut host,&a,&mut|_,_,_|panic!("valid definition")).unwrap(){Request::Define(defined)=>{source.install_defined_using(defined,&file,None,&a).unwrap();},Request::Undef{name}=>{let V::Ident{spelling,..}=&name.value else{panic!("name")};assert!(source.undefine_using(spelling.get(),&a).unwrap().found);},Request::Conditional(command)=>match source.begin_conditional_using(command,hash,&a).unwrap(){Action::Done{..}=>(),Action::Evaluate{pending,..}=>{source.finish_named_condition_using(pending,&file,&mut notices,&mut host,&a).unwrap();},_=>panic!("matched")},_=>panic!("actual fixture directive")};source.finish_directive_using(true,&file,&mut notices,&mut host,&a).unwrap();},
   DriverEvent::Token(LogicalToken::Actual(Token{value:V::Int(n),origin,..}))=>values.push((n.to_string(),origin.line,origin.byte_column)),
   DriverEvent::Token(LogicalToken::Actual(Token{value:V::String(text),origin,..}))=>values.push((text.get().to_owned(),origin.line,origin.byte_column)),
   DriverEvent::Token(LogicalToken::Actual(Token{value:V::Ident{spelling,..},..}))=>panic!("disabled WRONG cannot emit; got {}",spelling.get()),
   DriverEvent::Token(_)|DriverEvent::NeedInput=>(),DriverEvent::ActualEnd=>break,_=>panic!("no other notice"),
  }}assert_eq!(values,[("2".into(),3,Some(1)),("1".into(),5,Some(1)),("two".into(),12,Some(1)),("one".into(),14,Some(1))]);drop((source,host));assert_eq!(used.load(Ordering::Acquire),0);
 }

 #[test]
 fn actual_compact_macro_rows_preserve_issued_token_facts_and_leave_quoted_roster_wide(){
  use super::super::original_directive_dispatch::DirectiveRequest as Request;
  struct BorrowedActual<'a>(&'a File);
  impl SourceProvider for BorrowedActual<'_>{
   fn initial_environment(&self)->InitialEnvironment{InitialEnvironment::OriginalChecker0290}
   fn read(&self,_:&Path)->Result<String,String>{panic!("actual source loan only")}
   fn original_source_bytes<'a>(&'a self,lease:&'a SourceAcquisitionLease)->io::Result<Option<&'a[u8]>>{
    if !lease.same_original_acquisition(&self.0.lease){return Err(io::ErrorKind::InvalidInput.into())}
    Ok(Some(lease.source_text().as_bytes()))
   }
  }
  let used=Arc::new(AtomicUsize::new(0));let a=SettingAdmission::new(&used,32<<20,&||Ok(()));
  let file=File::new("#define COMPACT item:key item : key :: in 1.25 7\n#define WIDE \"quoted\"\nCOMPACT\nWIDE\n");
  let provider=BorrowedActual(&file);
  let mut source=driver(&a);source.push_opened(&provider,file.lease.clone(),0,&a).unwrap();
  let mut host=Host::new(&a);let mut notices=Notices{lexical:0,numeric:0};
  let mut installed=0;let mut emitted=Vec::new();
  loop{match source.next_logical_using(&provider,&mut notices,&mut host,&a).unwrap(){
   DriverEvent::Directive{..}=>{
    let Request::Define(defined)=source.directive_request_using(&provider,&mut notices,&mut host,&a,&mut|_,_,_|panic!("valid definitions")).unwrap()else{panic!("only definitions")};
    let V::Ident{spelling,..}=&defined.name.value else{panic!("actual definition name")};
    let name=spelling.get().to_owned();
    let original=defined.definition.replacement.as_slice().iter().map(|token|token.duplicate(&a).unwrap()).collect::<Vec<_>>();
    source.install_defined_using(defined,&provider,None,&a).unwrap();
    let retained=source.environment().environment().actual_original_product(&name).unwrap().unwrap();
    assert_eq!(retained.uses_compact_replacement(),name=="COMPACT");
    let decoded=retained.cloned_definition_using(&a).unwrap();
    assert_eq!(decoded.replacement.len(),original.len());
    if name=="COMPACT"{
     assert!(original.iter().any(|token|matches!(&token.value,V::Ident{spelling:crate::macro_expansion::OriginalMacroTextValue::Source(_),..})));
     assert!(original.iter().any(|token|matches!(token.value,V::Float(value)if value.to_bits()==1.25f32.to_bits())));
     assert!(original.iter().any(|token|matches!(token.value,V::Punct("::"))));
     assert!(original.iter().any(|token|matches!(token.value,V::Punct("in"))));
     assert_eq!(original.iter().filter(|token|matches!(token.value,V::Punct(":"))).count(),2);
    }
    for (before,after) in original.iter().zip(decoded.replacement.as_slice()){
     assert_eq!(before.origin,after.origin);assert_eq!(before.lexical_span,after.lexical_span);
     assert_eq!(before.punctuation_close,after.punctuation_close);assert_eq!(before.string_mode,after.string_mode);
     assert_eq!(before.raw_spelling(),after.raw_spelling());
     assert!(before.lexical_frame.as_ref().unwrap().same_frame(after.lexical_frame.as_ref().unwrap()));
     if let (V::Ident{spelling:crate::macro_expansion::OriginalMacroTextValue::Source(left),..},V::Ident{spelling:crate::macro_expansion::OriginalMacroTextValue::Source(right),..})=(&before.value,&after.value){assert!(left.same_retained_view(right));}
     if let (V::Float(left),V::Float(right))=(&before.value,&after.value){assert_eq!(left.to_bits(),right.to_bits());}
     if let V::Punct(left)=&before.value{
      assert!(matches!(&after.value,V::Punct(right)if left==right),"same issued punctuation {left}");
     }
     let mut left=crate::macro_expansion::OriginalMacroText::new(&a).unwrap();before.write_debug(&mut left,&a).unwrap();
     let mut right=crate::macro_expansion::OriginalMacroText::new(&a).unwrap();after.write_debug(&mut right,&a).unwrap();
     assert_eq!(left.as_str(),right.as_str());
    }
    installed+=1;source.finish_directive_using(true,&provider,&mut notices,&mut host,&a).unwrap();
   },
   DriverEvent::Token(LogicalToken::Actual(Token{value:V::Int(n),origin,..}))=>emitted.push((n,origin.line)),
   DriverEvent::Token(_)|DriverEvent::NeedInput=>(),DriverEvent::ActualEnd=>break,_=>panic!("no unexpected notices"),
  }}
  assert_eq!(installed,2);assert_eq!(emitted,[(7,3)]);
  drop((source,host));assert_eq!(used.load(Ordering::Acquire),0);
 }

 #[test]fn actual_authored_shadow_pop_restores_builtin_epoch_then_second_pop_removes_it(){
  use super::super::{original_directive_dispatch::DirectiveRequest as Request,original_conditional::Action};let used=Arc::new(AtomicUsize::new(0));let a=SettingAdmission::new(&used,32<<20,&||Ok(()));let file=File::new("TRUE\n#define TRUE 7\nTRUE\n#undef TRUE\nTRUE\n#undef TRUE\n#ifdef TRUE\nWRONG\n#endif\nTRUE\n");let mut source=driver(&a);source.push_opened(&file,file.lease.clone(),0,&a).unwrap();let mut host=Host::new(&a);let mut notices=Notices{lexical:0,numeric:0};let mut values=Vec::new();let mut final_name=false;
  loop{match source.next_logical_using(&file,&mut notices,&mut host,&a).unwrap(){DriverEvent::Directive{hash}=>{match source.directive_request_using(&file,&mut notices,&mut host,&a,&mut|_,_,_|panic!("valid definition")).unwrap(){Request::Define(defined)=>{source.install_defined_using(defined,&file,None,&a).unwrap();},Request::Undef{name}=>{let V::Ident{spelling,..}=&name.value else{panic!("name")};assert!(source.undefine_using(spelling.get(),&a).unwrap().found);},Request::Conditional(command)=>match source.begin_conditional_using(command,hash,&a).unwrap(){Action::Done{..}=>(),Action::Evaluate{pending,..}=>{source.finish_named_condition_using(pending,&file,&mut notices,&mut host,&a).unwrap();},_=>panic!("matched")},_=>panic!("actual fixture directive")};source.finish_directive_using(true,&file,&mut notices,&mut host,&a).unwrap();},DriverEvent::Token(LogicalToken::Actual(Token{value:V::Int(n),origin,..}))=>values.push((n,origin.line,origin.byte_column)),DriverEvent::Token(LogicalToken::Actual(Token{value:V::Ident{spelling,..},origin,..}))=>{assert_eq!(spelling.get(),"TRUE");assert_eq!((origin.line,origin.byte_column),(10,Some(1)));final_name=true},DriverEvent::Token(_)|DriverEvent::NeedInput=>(),DriverEvent::ActualEnd=>break,_=>panic!("no other notice")}}
  assert_eq!(values,[(1,1,Some(1)),(7,3,Some(1)),(1,5,Some(1))]);assert!(final_name);drop((source,host));assert_eq!(used.load(Ordering::Acquire),0);
 }

 #[test]fn actual_undef_moves_same_removed_epoch_to_history_and_finalization_keeps_remaining_stack(){
  use super::super::{original_directive_dispatch::DirectiveRequest as Request,original_define_history::{OriginalDefineHistory,OriginalDefineHistoryEnd}};let used=Arc::new(AtomicUsize::new(0));let a=SettingAdmission::new(&used,32<<20,&||Ok(()));let mut text=String::from("#define A 1\n#define A 2\n#undef A\nA\n");
  for _ in 0..132 { text.push_str("#define PAD 7\n#undef PAD\n"); }
  let acquired=File::new(&text);
  // The actual host borrows its admitted decoded backing directly for plain
  // UTF-8. Exercise that production representation, not File's duplicate raw Vec.
  struct SourceBacked<'a>(&'a File);
  impl SourceProvider for SourceBacked<'_>{
   fn read(&self,path:&Path)->Result<String,String>{self.0.read(path)}
   fn initial_environment(&self)->InitialEnvironment{self.0.initial_environment()}
   fn original_source_bytes<'a>(&'a self,lease:&'a SourceAcquisitionLease)->io::Result<Option<&'a[u8]>>{
    let Some(raw)=self.0.original_source_bytes(lease)? else{return Ok(None)};
    assert_eq!(raw,lease.source_text().as_bytes());
    Ok(Some(lease.source_text().as_bytes()))
   }
  }
  let file=SourceBacked(&acquired);
  let mut source=driver(&a);source.push_opened(&file,acquired.lease.clone(),0,&a).unwrap();let mut host=Host::new(&a);let mut notices=Notices{lexical:0,numeric:0};let mut history=OriginalDefineHistory::new(&a).unwrap();let mut restored=false;
  loop{match source.next_logical_using(&file,&mut notices,&mut host,&a).unwrap(){DriverEvent::Directive{..}=>{match source.directive_request_using(&file,&mut notices,&mut host,&a,&mut|_,_,_|panic!("no hint")).unwrap(){Request::Define(defined)=>{source.install_defined_using(defined,&file,None,&a).unwrap();},Request::Undef{name}=>{let V::Ident{spelling,..}=&name.value else{panic!("name")};let removed=source.undefine_using(spelling.get(),&a).unwrap().removed.unwrap();history.record_undef_using(spelling.get(),removed,source.last_outer_using(&a).unwrap(),&a).unwrap();},_=>panic!("only define and undef")};source.finish_directive_using(true,&file,&mut notices,&mut host,&a).unwrap();},DriverEvent::Token(LogicalToken::Actual(Token{value:V::Int(1),..}))=>restored=true,DriverEvent::Token(_)|DriverEvent::NeedInput=>(),DriverEvent::ActualEnd=>break,_=>panic!("no notice")}}
  assert!(restored);source.capture_final_define_history_using(&mut history,&a).unwrap();
  let mut all=history.entries();
  assert_eq!(all.next().unwrap().name,"A");
  for index in 0..132 {
   let row=all.next().unwrap();
   assert_eq!(row.name,"PAD");
   assert_eq!(row.defined_at.unwrap().line,5+2*index);
   assert!(matches!(row.end,OriginalDefineHistoryEnd::Undef(origin)if origin.line==6+2*index));
  }
  for (index,row) in all.enumerate() {
   assert!(matches!(row.end,OriginalDefineHistoryEnd::Final{ordinal}if ordinal==index+1));
  }
  assert!(history.is_finalized_by(&a));
  assert_eq!(history.capture_current_using(source.environment().environment(),&a).unwrap_err().kind(),io::ErrorKind::InvalidInput);
  let rows=history.entries().filter(|row|row.name=="A").collect::<Vec<_>>();assert_eq!(rows.len(),2);assert!(rows.iter().all(|row|row.product.definition_name().unwrap().uses_physical_storage()));assert_eq!(rows[0].defined_at.unwrap().line,2);assert!(matches!(rows[0].end,OriginalDefineHistoryEnd::Undef(origin)if origin.line==3&&origin.byte_column==Some(1)));assert_eq!(rows[1].defined_at.unwrap().line,1);assert!(matches!(rows[1].end,OriginalDefineHistoryEnd::Final{..}));assert!(history.entries().any(|row|row.name=="TRUE"&&row.defined_at.is_none()));drop((source,host));assert!(used.load(Ordering::Acquire)>0,"real epoch products and their source-frame leases remain retained by history");drop(rows);drop(history);assert_eq!(used.load(Ordering::Acquire),0);
 }

}
