//! Standalone callbacks: genuine callback inputs and results, never CHECK/model completion.
use super::{BuildHost,NativeCheckSelection,FullRegistryCheckOptions};
use std::{io::{self,Write},error::Error,sync::Arc};
use dm_preprocess::source_arena_credit::{SourceArenaCredit,SourceArenaWork};
pub(crate) struct StandaloneSelftestReport{
 pub(crate) inputs:crate::input_snapshot::InputSnapshot,
 pub(crate) report:crate::selected_report_spool::Verified,
 pub(crate) plan:Arc<NativeCheckSelection>,
 pub(crate) queries:Arc<crate::query_db::QueryDb>,
 pub(crate) _credit:SourceArenaCredit,
}
impl StandaloneSelftestReport{
 pub(crate) fn require_current(&self)->Result<(),Box<dyn Error>>{
  crate::request_runner::runner_freshness::require_native_callback_inputs_current(&self.inputs)?;
  crate::daemon::control::checkpoint()?;Ok(())
 }
}
impl BuildHost{
 pub(crate) fn stage_standalone_native_selftests(&mut self,request:crate::request::BuildRequest,selectors:&[String],caller:Option<std::path::PathBuf>)->Result<StandaloneSelftestReport,Box<dyn Error>>{
  super::full_registry_check::with_full_registry_check_context(request.command,request.timeout_seconds,||{
   let(root,cache)=Self::native_registry_check_paths(&request)?;
   let options=FullRegistryCheckOptions{unused:false,..Default::default()};
   let mut plan=super::prepare_native_registered_check_selection(selectors,options,self.source_arena_work())?;
   Arc::get_mut(&mut plan).ok_or_else(||io::Error::other("fresh standalone plan already aliased"))?.enable_native_selftests(caller,self.source_arena_work())?;
   // No Source/Model/Original frontend is acquired for the outer operation.
   let recording=crate::input_snapshot::RecordingInputs::new(crate::input_snapshot::FileSystemInputs,0);
   // Reuse the existing actual raw-family metadata/read lender and current
   // headroom. Its gate is released before nested fixture callbacks execute.
   self.query_db().with_baseline_input_refresh(|budget,lender|recording.validate_standalone_selftest_configuration(&root,self.query_db().as_ref(),budget,lender))?;
   let pending=self.prepare_native_selftests_mode(&plan,&recording,&cache,&root,true)?;
   let inputs=pending.finish_standalone(&plan,recording)?;
   let queries=Arc::clone(self.query_db());
   let metadata=cache.as_os_str().len().checked_mul(32).and_then(|n|n.checked_add(std::mem::size_of::<StandaloneSelftestReport>())).and_then(|n|n.checked_add(16384)).ok_or_else(||io::Error::from(io::ErrorKind::OutOfMemory))?;
   let credit=queries.reserve(metadata)?;
   let mut stage=crate::selected_report_spool::Stage::new(&cache)?;
   let actual=plan.native_selftest_result()?.ok_or_else(||io::Error::new(io::ErrorKind::InvalidData,"standalone callbacks did not complete"))?;
   actual.write_standalone(&mut stage)?;
   let(report,())=stage.seal()?.validate(|input|{io::copy(input,&mut io::sink())?;Ok(())})?;
   let completed=StandaloneSelftestReport{inputs,report,plan,queries,_credit:credit};
   completed.require_current()?;Ok(completed)
  })
 }
}

impl StandaloneSelftestReport{
 fn publish(self,out:&mut impl Write)->Result<bool,Box<dyn Error>>{
  self.require_current()?;let clean=self.plan.native_selftest_result()?.ok_or_else(||io::Error::other("missing actual standalone callback result"))?.failed()==0;
  self.report.publish(out)?;
  crate::request_runner::runner_freshness::require_native_callback_inputs_current(&self.inputs)?;crate::daemon::control::checkpoint()?;Ok(clean)
 }
}
impl BuildHost{
 pub fn write_standalone_selftests(&mut self,request:crate::request::BuildRequest,selectors:&[String],caller:Option<std::path::PathBuf>,out:&mut impl Write)->Result<bool,Box<dyn Error>>{
  super::full_registry_check::with_full_registry_check_context(request.command,request.timeout_seconds,||self.stage_standalone_native_selftests(request,selectors,caller)?.publish(out))
 }
}
