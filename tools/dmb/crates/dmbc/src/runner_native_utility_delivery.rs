//! One sealed delivery wrapper over the actual codemod/fixture coordinators.
//! No parser, filesystem writer, source-currentness substitute or new cache.
use super::*;
use dq_analyze::native_codemod_fixture_wire::{Binding, Question, SourceFrame, OriginalCompleteness,RequestBinding};
use dm_preprocess::source_arena_credit::SourceArenaCredit;
use std::io::{self, Write};
type BoxError = Box<dyn std::error::Error>;
fn invalid(s:&'static str)->io::Error{io::Error::new(io::ErrorKind::InvalidData,s)}

pub(crate) enum UtilityCompleted {
    Metadata,
    Parity(crate::runner_host::native_parity::Completed),
    Codemod(crate::runner_host::native_codemod::Completed),
    Fixture(crate::runner_host::native_fixture::Completed),
}
impl UtilityCompleted {
    pub(crate) fn require_current(&self)->Result<(),BoxError>{
        match self{Self::Metadata=>{crate::daemon::control::checkpoint()?;Ok(())},Self::Codemod(done)=>done.require_current(),Self::Fixture(done)=>done.require_current(),Self::Parity(done)=>done.require_current()}
    }
    fn frame(&self)->Result<Option<SourceFrame>,BoxError>{
        self.require_current()?;
        Ok(match self{Self::Metadata=>None,Self::Codemod(done)=>Some(done.frame()?),Self::Fixture(done)=>Some(done.frame.clone()),Self::Parity(done)=>Some(done.frame_ref().clone())})
    }
    fn matches_question(&self,question:&Question)->bool{matches!((self,question),(Self::Metadata,Question::CodemodList)|(Self::Codemod(_),Question::Codemod{..})|(Self::Fixture(_),Question::Fixture{..})|(Self::Parity(_),Question::Parity{..}))}
    fn outcome(&self)->(i32,usize){match self{Self::Metadata=>(0,0),Self::Codemod(done)=>(done.exit,done.committed),Self::Fixture(done)=>(done.exit,done.committed),Self::Parity(done)=>(done.exit,done.committed)}}
    fn matches_frame(&self,observed:&Option<SourceFrame>)->Result<bool,BoxError>{
     self.require_current()?;match self{Self::Parity(done)=>Ok(observed.as_ref().is_some_and(|frame|match(frame,done.frame_ref()){(SourceFrame::Parity{checks:a,check_frames:b,callbacks:c,callback_frames:d},SourceFrame::Parity{checks:w,check_frames:x,callbacks:y,callback_frames:z})=>a==w&&b==x&&c==y&&d==z,_=>false})),_=>Ok(same_frame(&self.frame()?,observed))}
    }
}
fn same_frame(a:&Option<SourceFrame>,b:&Option<SourceFrame>)->bool{
    use SourceFrame::*;
    match(a,b){
        (None,None)=>true,
        (Some(Selected(a)),Some(Selected(b)))=>a==b,
        (Some(Model(a)),Some(Model(b)))=>a==b,
        (Some(Raw(a)),Some(Raw(b)))=>a==b,
        (Some(Semantic{semantic:a,source:b,completeness:c}),Some(Semantic{semantic:x,source:y,completeness:z}))=>a==x&&b==y&&matches!((c,z),(OriginalCompleteness::Complete,OriginalCompleteness::Complete)|(OriginalCompleteness::PrimaryPrefix,OriginalCompleteness::PrimaryPrefix)),
        _=>false,
    }
}
pub(crate) struct NativeCodemodFixtureReport {
    binding:Binding,
    requested:RequestBinding,
    frame:Option<SourceFrame>,
    exit:i32,
    committed:usize,
    stdout:crate::selected_report_spool::Verified,
    stderr:crate::selected_report_spool::Verified,
    context:crate::daemon::control::WorkerContext,
    // The true producer/inputs remain owned through both streams + terminal.
    completed:UtilityCompleted,
    _credit:SourceArenaCredit,
}
impl NativeCodemodFixtureReport {
    pub(crate) fn require_current(&self)->Result<(),BoxError>{
        self.context.checkpoint()?;self.binding.validate()?;if self.requested!=self.binding.fingerprint_using(&mut||self.context.checkpoint())?{return Err(invalid("utility request identity changed after pre-mutation binding").into())}
        self.completed.require_current()?;
        if !self.completed.matches_question(&self.binding.question)||self.completed.outcome()!=(self.exit,self.committed)||!self.completed.matches_frame(&self.frame)?{return Err(invalid("utility delivery differs from its actual completed producer").into())}
        Ok(())
    }
    pub(crate) fn into_delivery(self,deliver:impl FnOnce(Binding,RequestBinding,Option<SourceFrame>,i32,usize,crate::selected_report_spool::Verified,crate::selected_report_spool::Verified,&mut dyn FnMut()->Result<(),BoxError>)->Result<(),crate::daemon::selected_report_wire::SendFailure>)->Result<(),crate::daemon::selected_report_wire::SendFailure>{
        use crate::daemon::selected_report_wire::SendFailure;
        self.require_current().map_err(|first|SendFailure::BeforePublication(delivery_io_failure(self.committed,first)))?;
        let Self{binding,requested,frame,exit,committed,stdout,stderr,completed,context,_credit}=self;
        let mut current=||{context.checkpoint()?;completed.require_current()};
        let pending=deliver(binding,requested,frame,exit,committed,stdout,stderr,&mut current);
        drop(completed);drop(context);drop(_credit);
        pending.map_err(|actual|match actual{
            SendFailure::BeforePublication(first)=>SendFailure::BeforePublication(delivery_io_failure(committed,Box::new(first))),
            SendFailure::AfterPublication(first)=>SendFailure::AfterPublication(delivery_io_failure(committed,Box::new(first))),
        })
    }
    pub(crate) fn publish(self,out:&mut impl Write,err:&mut impl Write)->Result<i32,BoxError>{
        let committed=self.committed;
        self.require_current().map_err(|first|delivery_failure(committed,first))?;
        let Self{binding,requested,frame,exit,committed,stdout,stderr,completed,context,_credit}=self;
        let pending=(||{
            stderr.publish(err)?;stdout.publish(out)?;
            context.checkpoint()?;binding.validate()?;if requested!=binding.fingerprint_using(&mut||context.checkpoint())?{return Err(invalid("utility requested binding changed before final delivery").into())}completed.require_current()?;
            if !completed.matches_question(&binding.question)||completed.outcome()!=(exit,committed)||!completed.matches_frame(&frame)?{return Err(invalid("utility delivery changed after output").into())}
            Ok(exit)
        })();drop(completed);drop(context);drop(_credit);
        pending.map_err(|first|delivery_failure(committed,first))
    }
}
// Move, do not clone, the actual decoded binding. The caller's request owner
// remains alive until this pre-admitted report takes over the SAME buffers.
// Paths/strings/vectors are charged at their exposed capacities, not guessed
// from text length; SourceFrame variants contain only fixed scalar DATA, including parity case stream seals.
fn binding_bytes(binding:&Binding)->io::Result<usize>{
    let mut bytes=std::mem::size_of::<NativeCodemodFixtureReport>().checked_add(binding.root.capacity()).ok_or(io::ErrorKind::OutOfMemory)?;
    let mut add=|n|{bytes=bytes.checked_add(n).ok_or(io::ErrorKind::OutOfMemory)?;Ok::<(),io::Error>(())};
    match &binding.question{
        Question::Codemod{name,paths,..}=>{add(name.capacity())?;add(paths.capacity().checked_mul(std::mem::size_of::<String>()).ok_or(io::ErrorKind::OutOfMemory)?)?;for path in paths{add(path.capacity())?;}}
        Question::Fixture{lint,..}=>add(lint.capacity())?,
        Question::Parity{selectors,oracle,..}=>{add(selectors.capacity().checked_mul(std::mem::size_of::<String>()).ok_or(io::ErrorKind::OutOfMemory)?)?;for s in selectors{add(s.capacity())?;}add(oracle.image.capacity())?;add(oracle.sha256.capacity())?;},
        Question::CodemodList=>(),
    }
    Ok(bytes)
}
impl BuildHost {
    /// The daemon request/key keeps its shared binding. Copy only through the
    /// actual same-family helper and retain that construction credit until the
    /// owned stage adopts the SAME buffers in its report, or tears them down.
    pub(crate) fn stage_native_codemod_fixture_shared(&mut self,request:crate::request::BuildRequest,binding:std::sync::Arc<Binding>)->Result<NativeCodemodFixtureReport,BoxError>{
        let owned=crate::runner_host::native_utility_binding::clone_binding(binding.as_ref(),self.source_arena_work())?;
        let(owned,credit)=owned.into_parts();
        let pending=self.stage_native_codemod_fixture(request,owned);
        drop(credit);pending
    }
    pub(crate) fn stage_native_codemod_fixture(&mut self,request:crate::request::BuildRequest,binding:Binding)->Result<NativeCodemodFixtureReport,BoxError>{
        binding.validate()?;crate::daemon::control::checkpoint()?;
        let context=crate::daemon::control::WorkerContext::capture_for_checkpoints().filter(|_|crate::daemon::control::current_deadline().is_some()).ok_or_else(||invalid("utility delivery requires the actual request context/deadline"))?;
        let requested=binding.fingerprint_using(&mut||self.source_arena_work().checkpoint())?;
        let cache=request.cache_root.as_ref().ok_or_else(||invalid("utility delivery cache absent"))?;
        let credit=self.source_arena_work().reserve(binding_bytes(&binding)?)?;
        let mut stdout=crate::selected_report_spool::Stage::new(cache)?;
        let mut stderr=crate::selected_report_spool::Stage::new(cache)?;
        let completed=match &binding.question{
            Question::CodemodList=>{dq_analyze::codemod_spec::write_list(&mut stdout)?;UtilityCompleted::Metadata},
            Question::Codemod{..}=>UtilityCompleted::Codemod(crate::runner_host::native_codemod::run(&request,&binding,self,&mut stdout,&mut stderr)?),
            Question::Parity{..}=>UtilityCompleted::Parity(crate::runner_host::native_parity::run(&request,&binding,self,&mut stdout,&mut stderr)?),
            Question::Fixture{..}=>UtilityCompleted::Fixture(crate::runner_host::native_fixture::run(&request,&binding,self,&mut stdout,&mut stderr)?),
        };
        // An actual writer/formatter IO error above exits before ANY successful
        // terminal exists. Incomplete spools stay private and clean themselves.
        let(exit,committed)=completed.outcome();let pending=(||{
        completed.require_current()?;let frame=completed.frame()?;
        let stdout=stdout.seal_allow_empty()?.validate(crate::request_runner::schema_capture::drain)?.0;
        let stderr=stderr.seal_allow_empty()?.validate(crate::request_runner::schema_capture::drain)?.0;
        let report=NativeCodemodFixtureReport{binding,requested,frame,exit,committed,stdout,stderr,completed,context,_credit:credit};
        report.require_current()?;Ok(report)})();pending.map_err(|first|delivery_failure(committed,first))
    }
}

#[derive(Debug)]
pub(crate) struct DeliveryFailure{pub(crate) committed:usize,primary:BoxError}
impl std::fmt::Display for DeliveryFailure{fn fmt(&self,f:&mut std::fmt::Formatter<'_>)->std::fmt::Result{write!(f,"utility delivery failed after {} committed mutations: {}",self.committed,self.primary)}}
impl std::error::Error for DeliveryFailure{fn source(&self)->Option<&(dyn std::error::Error+'static)>{Some(self.primary.as_ref())}}
fn delivery_failure(committed:usize,first:BoxError)->BoxError{if committed==0{first}else{Box::new(DeliveryFailure{committed,primary:first})}}

/// A transport io::Error requires Send+Sync, while the actual producer's boxed
/// diagnostic need not be. Never stringify away its first operational channel:
/// move a plain IO error; otherwise transfer its exact raw OS code (or kind +
/// original IO text) into this Send+Sync adapter with truthful mutation detail.
#[derive(Debug)]struct DeliveryIoFailure{detail:String,primary:Option<io::Error>}
impl std::fmt::Display for DeliveryIoFailure{fn fmt(&self,f:&mut std::fmt::Formatter<'_>)->std::fmt::Result{f.write_str(&self.detail)}}
impl std::error::Error for DeliveryIoFailure{fn source(&self)->Option<&(dyn std::error::Error+'static)>{self.primary.as_ref().map(|e|e as &(dyn std::error::Error+'static))}}
fn delivery_io_failure(committed:usize,first:BoxError)->io::Error{
 let first=match first.downcast::<io::Error>(){
  Ok(actual)if committed==0=>return *actual,
  Ok(actual)=>{let detail=format!("utility delivery failed after {committed} committed mutations: {actual}");let kind=actual.kind();return io::Error::new(kind,DeliveryIoFailure{detail,primary:Some(*actual)})},
  Err(first)=>first,
 };
 let mut cursor:Option<&(dyn std::error::Error+'static)>=Some(first.as_ref());let mut primary=None;
 while let Some(actual)=cursor{
  if let Some(actual)=actual.downcast_ref::<io::Error>(){
   primary=Some(match actual.raw_os_error(){Some(code)=>io::Error::from_raw_os_error(code),None=>io::Error::new(actual.kind(),actual.to_string())});break
  }cursor=actual.source();
 }
 let detail=if committed==0{first.to_string()}else{format!("utility delivery failed after {committed} committed mutations: {first}")};
 let kind=primary.as_ref().map_or(io::ErrorKind::Other,io::Error::kind);io::Error::new(kind,DeliveryIoFailure{detail,primary})
}
#[cfg(test)]mod transfer_io_controls{
 use super::*;
 #[derive(Debug)]struct NotSend{_held:std::rc::Rc<()>,first:io::Error}
 impl std::fmt::Display for NotSend{fn fmt(&self,f:&mut std::fmt::Formatter<'_>)->std::fmt::Result{f.write_str("actual producer with non-Send diagnostic owner")}}
 impl std::error::Error for NotSend{fn source(&self)->Option<&(dyn std::error::Error+'static)>{Some(&self.first)}}
 #[test]fn utility_delivery_io_transfer_preserves_plain_and_nested_os_channels_and_mutation_truth(){
  let plain=delivery_io_failure(0,Box::new(io::Error::from_raw_os_error(1450)));assert_eq!(plain.raw_os_error(),Some(1450));
  let nested=delivery_io_failure(7,Box::new(NotSend{_held:std::rc::Rc::new(()),first:io::Error::from_raw_os_error(1450)}));assert!(nested.to_string().contains("7 committed mutations"));
  let mut cursor:Option<&(dyn std::error::Error+'static)>=Some(&nested);let mut actual=None;while let Some(error)=cursor{if let Some(code)=error.downcast_ref::<io::Error>().and_then(io::Error::raw_os_error){actual=Some(code);break}cursor=error.source();}assert_eq!(actual,Some(1450));
  let cancelled=delivery_io_failure(1,Box::new(NotSend{_held:std::rc::Rc::new(()),first:io::Error::new(io::ErrorKind::Interrupted,"actual cancelled producer")}));assert_eq!(cancelled.kind(),io::ErrorKind::Interrupted);assert!(cancelled.to_string().contains("1 committed mutations"));
 }
}
