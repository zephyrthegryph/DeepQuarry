//! Short-lived borrow adapter, not another macro environment or input manager.
//! DirectivePass mutates its SAME binding map between pulls; a pull borrows that
//! map plus the actual raw stack/output queue and returns owned token DATA.
use super::{environment::MacroEnvironment,original_raw_inputs::{OriginalRawInputs,OriginalRawNoticeSink},original_output_queue::OriginalOutputQueue};
use crate::{SourceProvider,macro_expansion::{OriginalMacroSource as Source,OriginalMacroDefinition as Definition,OriginalMacroRawStep as RawStep,OriginalMacroToken as Token,OriginalMacroOrigin as Origin}};
use dm_syntax::SettingAdmission;use std::io;
/// Implemented by the actual directive/trace owner. Callbacks receive genuine
/// current source-stack state; no span/path equality substitutes for a receipt.
pub(super) trait OriginalMacroHost{
 /// Native expression Debug borrows actual Context registration DATA; never
 /// infer FileId from acquisition/occurrence count or a caller number.
 fn condition_debug_file_id_using(&mut self,_occurrence:usize,_a:&SettingAdmission<'_>)->io::Result<u32>{Err(io::Error::new(io::ErrorKind::Unsupported,"actual semantic file registry loan is unissued"))}

 /// Saved condition-start file context; this is a metadata-only actual host
 /// question, never an eager payload read or a source/model grant.
 fn condition_file_exists_using(&mut self,_at:Origin,_passed:&str,_provider:&dyn SourceProvider,_a:&SettingAdmission<'_>)->io::Result<super::original_condition_value::FileExistsResult>{Err(io::Error::new(io::ErrorKind::Unsupported,"actual Original condition file-context host is unissued"))}

 /// Move the actual accumulated ordinary-output docs at active #define.
 /// A host without this owner cannot substitute a fabricated empty list.
 fn take_docs_for_define(&mut self,_a:&SettingAdmission<'_>)->io::Result<crate::macro_expansion::OriginalMacroRows<crate::macro_expansion::OriginalMacroDoc<'static>>>{Err(io::Error::new(io::ErrorKind::Unsupported,"actual pending definition docs owner is unissued"))}

 fn before_identifier(&mut self,name:&str,origin:Origin,queue:&mut OriginalOutputQueue<'static>,a:&SettingAdmission<'_>)->io::Result<()>;
 /// SAME old generic real_next branch: accumulate following docs; update
 /// interpolation depth; flush pending docs before nonwhitespace output.
 fn ordinary_token(&mut self,token:Token<'static>,queue:&mut OriginalOutputQueue<'static>,a:&SettingAdmission<'_>)->io::Result<()>;
 /// Direct second token of a noncall bypasses generic docs/lookup processing.
 fn direct_noncall_output(&mut self,token:&Token<'static>,a:&SettingAdmission<'_>)->io::Result<()>;
 fn dynamic(&mut self,file:bool,invocation:Origin,current_occurrence:Option<usize>,last_input:Option<Origin>,a:&SettingAdmission<'_>)->io::Result<Token<'static>>;
 fn invocation(&mut self,name:&str,origin:Origin,a:&SettingAdmission<'_>)->io::Result<()>;
 fn expansion_pushed(&mut self,_name:&str,_origin:Origin,_depth:usize,_definition_name:Option<Origin>,_a:&SettingAdmission<'_>)->io::Result<()>{Ok(())}
 fn expansion_popped(&mut self,_depth:usize,_a:&SettingAdmission<'_>)->io::Result<()>{Ok(())}

}
pub(super) struct OriginalBorrowedMacroSource<'a>{
 pub(super) inputs:&'a mut OriginalRawInputs,
 pub(super) environment:&'a MacroEnvironment,
 pub(super) queue:&'a mut OriginalOutputQueue<'static>,
 pub(super) provider:&'a dyn SourceProvider,
 pub(super) notices:&'a mut dyn OriginalRawNoticeSink,
 pub(super) host:&'a mut dyn OriginalMacroHost,
}
impl Source<'static> for OriginalBorrowedMacroSource<'_>{
 fn physical_input_precedes(&self,depth:usize)->bool{self.inputs.frame_precedes_expansion(depth)}
 fn take_physical_stack_change(&mut self)->bool{self.inputs.take_stack_change()}

 fn before_identifier(&mut self,name:&str,origin:Origin,a:&SettingAdmission<'_>)->io::Result<()>{self.host.before_identifier(name,origin,self.queue,a)}
 fn direct_noncall_output(&mut self,token:&Token<'static>,a:&SettingAdmission<'_>)->io::Result<()>{self.host.direct_noncall_output(token,a)}
 fn next_raw(&mut self,a:&SettingAdmission<'_>)->io::Result<RawStep<'static>>{self.inputs.next_using(self.provider,a,self.notices)}
 fn lookup(&mut self,name:&str,a:&SettingAdmission<'_>)->io::Result<Option<Definition<'static>>>{
  a.checkpoint().map_err(|e|a.take_operational_error().unwrap_or(e))?;
  self.environment.actual_original_product(name)?.map(|actual|actual.cloned_definition_using(a)).transpose()
 }
 fn preserves_defined_operand(&self)->bool{self.queue.preserves_defined_operand()}
 fn include_depth(&self)->usize{self.inputs.depth()}
 fn dynamic(&mut self,file:bool,origin:Origin,a:&SettingAdmission<'_>)->io::Result<Token<'static>>{self.host.dynamic(file,origin,self.inputs.current_occurrence(),self.inputs.last_input(),a)}
 fn invocation(&mut self,name:&str,origin:Origin,a:&SettingAdmission<'_>)->io::Result<()>{self.host.invocation(name,origin,a)}
 fn expansion_pushed(&mut self,name:&str,origin:Origin,depth:usize,a:&SettingAdmission<'_>)->io::Result<()>{let actual=self.environment.actual_original_product(name)?;let definition_name=actual.and_then(|actual|actual.definition_name()).map(|token|token.origin());self.queue.trace_pushed_using(name,origin,depth,definition_name,actual.and_then(|actual|actual.projected_definition()),a)?;self.host.expansion_pushed(name,origin,depth,definition_name,a)}
 fn expansion_popped(&mut self,depth:usize,a:&SettingAdmission<'_>)->io::Result<()>{self.queue.trace_popped_using(depth,a)?;self.host.expansion_popped(depth,a)}

}
