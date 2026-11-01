//! Actual current workspace issuer for the unique check_grep multi-file policy.
//! No finite capture promotion, ordinary PolicyInputs cast, source reread/cache,
//! parser or retained model. Returned rows are callback-local owned policy data.
use super::*;
use dq_analyze::{captured_generator_budget::Budget,captured_reactive_reads::Failure};
use dq_analyze::lints::check_grep::native as policy;
use std::cell::RefCell;
struct Scratch{budget:Arc<Budget>,complete:bool}
impl Scratch{fn new(root:&Arc<Budget>)->Result<Self,Failure>{Ok(Self{budget:Budget::scoped_temporaries(root).map_err(oom)?,complete:false})}}
impl Drop for Scratch{fn drop(&mut self){if !self.complete{self.budget.keep_failed_scratch()}}}
fn oom(message:impl Into<String>)->Failure{Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,message.into()))}
fn reserve(budget:&Budget,bytes:Option<usize>)->Result<(),Failure>{let bytes=bytes.ok_or_else(||{budget.deny();oom("check_grep host metadata overflow")})?;budget.charge(bytes).map_err(oom)}
fn push<T>(budget:&Budget,rows:&mut Vec<T>,value:T)->Result<(),Failure>{if rows.len()==rows.capacity(){let wanted=rows.capacity().checked_mul(2).and_then(|n|n.checked_add(1)).ok_or_else(||oom("check_grep row count overflow"))?;let capacity=wanted.checked_mul(4).ok_or_else(||oom("check_grep row capacity overflow"))?;reserve(budget,capacity.checked_mul(std::mem::size_of::<T>()).and_then(|n|n.checked_add(128)))?;rows.try_reserve_exact(wanted-rows.len()).map_err(|error|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,error)))?;if rows.capacity()>capacity{budget.deny();return Err(oom("check_grep actual row capacity exceeds admitted overlap"))}}rows.push(value);Ok(())}
struct FilePositions{relative:String,positions:policy::Positions}
#[derive(Clone,Copy)]struct Plan{file:usize,ordinal:usize}
struct Source<'reader,'capture,'scope>{reader:&'reader WorkspaceCodeReader<'capture,'scope>,config:&'reader Config,scope:&'reader Scope,archive:&'reader dm_tree::frontend::BodyArchive,evidence:&'reader crate::input_snapshot::SemanticSourceEvidence,positions:RefCell<Option<Vec<FilePositions>>>}
impl Source<'_,'_,'_>{
 fn require(&self)->Result<(),Failure>{self.reader.require_check_grep_archive(self.archive)?;self.evidence.check(self.archive.source_mapping())?;Ok(())}
 fn prepare(&self,requests:&[policy::SemanticRequest])->Result<(),Failure>{
  self.require()?;if self.positions.borrow().is_some(){return Err("check_grep semantic preparation repeated".into())}
  if requests.windows(2).any(|pair|pair[0].relative>=pair[1].relative){return Err("check_grep semantic requests are not uniquely ordered".into())}
  let root=self.reader.budget();let mut temporary=Scratch::new(root)?;let scratch=&temporary.budget;
  let mut owners=std::collections::BTreeSet::new();
  if !self.reader.for_each_check_grep_file(self.config,true,&mut|relative,views|{policy::observe_tracked_slot_owners(relative,views,scratch,&crate::daemon::control::checkpoint,&mut owners)?;Ok(true)})?{return Err("check_grep tracked declaration traversal stopped".into())}
  let mut plans=Vec::new();let mut output=Vec::new();let mut path_peak=0;
  for request in requests{reserve(root,request.relative.len().checked_mul(4).and_then(|n|n.checked_add(128)))?;let relative=request.relative.clone();push(root,&mut output,FilePositions{relative,positions:policy::Positions::default()})?;}
  // One original callable pass; selected scalar jobs are then grouped by file.
  // No per-file whole-archive walk or copied callable/type index is retained.
  for(ordinal,occurrence)in self.archive.occurrences().iter().enumerate(){
   self.require()?;let point=self.archive.callable_header_source().reported_point(occurrence.member)?;let(path,_,_)=point.reported_coordinates();
   let peak=path.as_os_str().len().checked_add(self.reader.root().as_os_str().len()).and_then(|n|n.checked_mul(128)).and_then(|n|n.checked_add(4096)).ok_or_else(||oom("check_grep requested body path overflow"))?;
   if peak>path_peak{reserve(scratch,Some(peak-path_peak))?;path_peak=peak;}
   let relative=dq_analyze::util::rel_slash(path,self.reader.root());
   let Ok(file)=requests.binary_search_by(|request|request.relative.as_str().cmp(&relative))else{continue};
   // Resolver answer backing retires with its own sibling scratch after this
   // selection. It must not accumulate once per body on the phase root.
   let mut selection=Scratch::new(root)?;let selected=policy::is_effective_body(self.archive,ordinal,&selection.budget)?;selection.complete=true;drop(selection);
   if selected{push(scratch,&mut plans,Plan{file,ordinal})?;}
  }
  plans.sort_unstable_by_key(|plan|(plan.file,plan.ordinal));
  let mut cursor=0usize;let mut next_file=0usize;
  if !self.reader.for_each_check_grep_file(self.config,false,&mut|relative,views|{
   let Ok(file)=requests.binary_search_by(|request|request.relative.as_str().cmp(relative))else{return Ok(true)};
   if file!=next_file{return Err("check_grep requested semantic file repeats or changes order".into())}next_file+=1;
   policy::with_source_file(views,&mut|source|{
    while cursor<plans.len()&&plans[cursor].file==file{
     self.require()?;let plan=plans[cursor];let mut body_scratch=Scratch::new(root)?;
     let body=self.archive.parse_checked(plan.ordinal).map_err(|failure|match failure{dm_tree::frontend::BodySyntaxFailure::Operational(actual)=>Failure::Operational(actual),dm_tree::frontend::BodySyntaxFailure::Syntax(error)=>Failure::Unsupported(error.message)})?;
     policy::body_positions(self.archive,&body,self.reader.root(),source,&owners,requests[file].slot_mutation,requests[file].non_client_holder,&body_scratch.budget,root,&crate::daemon::control::checkpoint,&mut output[file].positions)?;
     drop(body);body_scratch.complete=true;drop(body_scratch);cursor+=1;
    }
    Ok(())
   })?;Ok(true)
  })?{return Err("check_grep semantic file traversal stopped".into())}
  if next_file!=requests.len()||cursor!=plans.len(){return Err("check_grep semantic preparation omitted a requested file/body".into())}
  drop(plans);drop(owners);temporary.complete=true;drop(temporary);self.require()?;
  *self.positions.borrow_mut()=Some(output);Ok(())
 }
}
impl policy::Inputs for Source<'_,'_,'_>{
 fn scope(&self)->&dq_analyze::scopes::LintScope{self.scope.report_scope()}
 fn budget(&self)->&Arc<Budget>{self.reader.budget()}
 fn checkpoint(&self)->io::Result<()>{self.require().map_err(|failure|match failure{Failure::Operational(actual)=>actual,Failure::Unsupported(message)=>io::Error::other(message)})}
 fn files(&self,include_exempt:bool,visit:&mut dyn FnMut(&dq_analyze::tree::SourceFile)->Result<(),Failure>)->Result<(),Failure>{self.require()?;if !self.reader.for_each_check_grep_file(self.config,include_exempt,&mut|_,views|{policy::with_source_file(views,visit)?;Ok(true)})?{return Err("check_grep original file traversal stopped".into())}self.require()}
 fn fixed(&self,which:policy::Fixed,visit:&mut dyn FnMut(Option<&[u8]>)->Result<(),Failure>)->Result<(),Failure>{self.require()?;self.reader.with_check_grep_fixed(which,|bytes|visit(bytes))?;self.require()}
 fn dmes(&self,visit:&mut dyn FnMut(&str,&[u8])->Result<(),Failure>)->Result<(),Failure>{self.require()?;self.reader.for_each_check_grep_dme(visit)?;self.require()}
 fn jsx(&self,visit:&mut dyn FnMut(&str)->Result<(),Failure>)->Result<(),Failure>{self.require()?;let(_,names)=self.reader.check_grep_names()?;let mut peak=0;for path in names{self.require()?;let wanted=path.as_os_str().len().checked_add(self.reader.root().as_os_str().len()).and_then(|n|n.checked_mul(16)).and_then(|n|n.checked_add(1024)).ok_or_else(||oom("check_grep JSX path overflow"))?;if wanted>peak{reserve(self.reader.budget(),Some(wanted-peak))?;peak=wanted;}let relative=dq_analyze::util::rel_slash(path,self.reader.root());if !policy::is_jsx_name(&relative){return Err("check_grep JSX name differs from typed selection".into())}visit(&relative)?;}self.require()}
 fn prepare_positions(&self,requests:&[policy::SemanticRequest])->Result<(),Failure>{self.prepare(requests)}
 fn positions(&self,file:&dq_analyze::tree::SourceFile,which:policy::Semantic,visit:&mut dyn FnMut(&std::collections::BTreeSet<(usize,usize)>)->Result<(),Failure>)->Result<(),Failure>{self.require()?;{let rows=self.positions.borrow();let rows=rows.as_ref().ok_or("check_grep semantic source preparation was omitted")?;let index=rows.binary_search_by(|row|row.relative.as_str().cmp(&file.rel)).map_err(|_|Failure::Unsupported("check_grep semantic request was not prepared for this actual file".into()))?;visit(match which{policy::Semantic::SlotMutation=>&rows[index].positions.slots,policy::Semantic::NonClientHolder=>&rows[index].positions.holders})?;}self.require()}
}
fn judge_using<R>(reader:&WorkspaceCodeReader<'_,'_>,archive:&dm_tree::frontend::BodyArchive,evidence:&crate::input_snapshot::SemanticSourceEvidence,consume:impl FnOnce(&policy::Output,&Arc<Budget>)->Result<R,Failure>)->Result<R,Failure>{
   reader.require_check_grep_archive(archive)?;evidence.check(archive.source_mapping())?;let(configuration,bytes)=reader.configuration();let _=configuration;
   reserve(reader.budget(),bytes.map_or(Some(8192),|bytes|bytes.len().checked_mul(32).and_then(|n|n.checked_add(8192))))?;
   let config=Config::capture(match bytes{Some(bytes)=>Configuration::Captured(bytes),None=>Configuration::ProvenMissing})?;
   let scope=config.check_grep_scope()?;reserve(reader.budget(),Some(scope.budget_charge()))?;
   let source=Source{reader,config:&config,scope:&scope,archive,evidence,positions:RefCell::new(None)};
   let output=policy::judge(&source)?;source.require()?;let pending=consume(&output,reader.budget());
   if matches!(&pending,Err(Failure::Operational(_))){return pending}source.require()?;pending
}
impl QueryDb{
 /// Actual complete policy under the SAME reader root budget/current guard.
 /// Consumer must free encoded buffers before callback return; no source,
 /// Budget or operation scope may be cached by this internal loan.
 pub(crate) fn with_workspace_check_grep<R>(&self,capture:&Arc<WorkspaceCapture>,guard:&NativeReadGuard<'_>,archive:&dm_tree::frontend::BodyArchive,evidence:&crate::input_snapshot::SemanticSourceEvidence,consume:impl FnOnce(&policy::Output,&Arc<Budget>)->Result<R,Failure>)->Result<R,Failure>{self.with_workspace_code_pages(capture,guard,|reader|judge_using(reader,archive,evidence,consume))}
 #[cfg(test)]pub(crate) fn with_workspace_check_grep_limit<R>(&self,capture:&Arc<WorkspaceCapture>,guard:&NativeReadGuard<'_>,archive:&dm_tree::frontend::BodyArchive,evidence:&crate::input_snapshot::SemanticSourceEvidence,limit:usize,consume:impl FnOnce(&policy::Output,&Arc<Budget>)->Result<R,Failure>)->Result<R,Failure>{let _gate=self.raw_policy.gate.lock().unwrap_or_else(|error|error.into_inner());self.with_workspace_code_pages_limit_locked(capture,guard,Some(limit),|reader|judge_using(reader,archive,evidence,consume))}
}
