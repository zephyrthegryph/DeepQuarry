//! Current-operation control loan only. No source/result cache or authority.
use super::*;
use dq_analyze::captured_generator_budget::Budget;
use crate::runner_host::{workspace_capture::WorkspaceCapture,query_snapshot::workspace_native_guard::WorkspaceQueryScope};
#[derive(Clone)]pub(super) struct SemanticFrame{issuance:u64,evidence:u64,locator:(bool,u128),budget:Weak<Budget>,scope:Weak<WorkspaceQueryScope>,workspace:Weak<WorkspaceCapture>,capture:Weak<CapturedPolicyInputs>}
pub(super) struct Loan{pub locator:(bool,u128),pub budget:Arc<Budget>,pub scope:Arc<WorkspaceQueryScope>,pub workspace:Arc<WorkspaceCapture>,pub capture:Arc<CapturedPolicyInputs>}
pub(super) struct Guard<'a>{admission:&'a Admission}
impl Drop for Guard<'_>{fn drop(&mut self){self.admission.workspace_operation.lock().unwrap_or_else(|e|e.into_inner()).take();}}
impl Admission{
 pub(super) fn bind_workspace_operation<'a>(&'a self,budget:&Arc<Budget>,scope:&Arc<WorkspaceQueryScope>,workspace:&Arc<WorkspaceCapture>,capture:&Arc<CapturedPolicyInputs>)->io::Result<Guard<'a>>{
  crate::daemon::control::checkpoint()?;let mut current=self.workspace_operation.lock().unwrap_or_else(|e|e.into_inner());if current.is_some(){return Err(io::Error::new(io::ErrorKind::WouldBlock,"workspace operation control is already bound"))}
  let bytes=std::mem::size_of::<Frame>().checked_add(std::mem::size_of::<WorkspaceQueryScope>()).and_then(|n|n.checked_add(std::mem::size_of::<WorkspaceCapture>())).and_then(|n|n.checked_add(std::mem::size_of::<CapturedPolicyInputs>())).and_then(|n|n.checked_add(8*std::mem::size_of::<usize>())).ok_or_else(||{budget.deny();io::Error::new(io::ErrorKind::OutOfMemory,"workspace operation coordination overflow")})?;
  budget.charge(bytes).map_err(|message|io::Error::new(io::ErrorKind::OutOfMemory,message))?;
  let locator=super::reactive_read_policy::source_locator(capture)?;*current=Some(Frame::Semantic(SemanticFrame{locator,issuance:workspace.issuance(),evidence:capture.semantic_source_evidence().key(),budget:Arc::downgrade(budget),scope:Arc::downgrade(scope),workspace:Arc::downgrade(workspace),capture:Arc::downgrade(capture)}));Ok(Guard{admission:self})
 }
 pub(super) fn current_workspace_operation(&self,issuance:u64,evidence:u64)->io::Result<Loan>{
  crate::daemon::control::checkpoint()?;let current=self.workspace_operation.lock().unwrap_or_else(|e|e.into_inner());let frame=current.as_ref().ok_or_else(||io::Error::new(io::ErrorKind::NotConnected,"workspace query has no current operation control"))?;let Frame::Semantic(frame)=frame else{return Err(io::Error::new(io::ErrorKind::InvalidInput,"raw UI operation has no semantic control loan"))};
  if frame.issuance!=issuance||frame.evidence!=evidence{return Err(io::Error::new(io::ErrorKind::InvalidData,"workspace operation locator/evidence differs"))}
  let missing=||io::Error::new(io::ErrorKind::NotConnected,"workspace operation owner expired");let loan=Loan{locator:frame.locator,budget:frame.budget.upgrade().ok_or_else(missing)?,scope:frame.scope.upgrade().ok_or_else(missing)?,workspace:frame.workspace.upgrade().ok_or_else(missing)?,capture:frame.capture.upgrade().ok_or_else(missing)?};
  if loan.workspace.issuance()!=issuance||loan.capture.semantic_source_evidence().key()!=evidence{return Err(io::Error::new(io::ErrorKind::InvalidData,"workspace operation actual frame differs"))}loan.budget.require().map_err(|message|io::Error::new(io::ErrorKind::OutOfMemory,message))?;Ok(loan)
 }
}

#[derive(Clone)]pub(super) enum Frame{Semantic(SemanticFrame),UiRaw(UiFrame),Handlers(HandlerFrame)}
#[derive(Clone)]pub(super) struct UiFrame{proof:Weak<super::workspace::UiInputProof>,budget:Weak<Budget>,workspace:Weak<WorkspaceCapture>,source:Weak<crate::runner_host::workspace_capture::RawSourceIdentity>,queries:Weak<QueryDb>}
pub(super) struct UiLoan{pub proof:Arc<super::workspace::UiInputProof>,pub budget:Arc<Budget>,pub workspace:Arc<WorkspaceCapture>,pub source:Arc<crate::runner_host::workspace_capture::RawSourceIdentity>,pub queries:Arc<QueryDb>}
impl Admission{
 pub(super) fn bind_ui_operation<'a>(&'a self,budget:&Arc<Budget>,workspace:&Arc<WorkspaceCapture>,guard:&crate::runner_host::query_snapshot::workspace_native_guard::NativeReadGuard<'_>,proof:&Arc<super::workspace::UiInputProof>)->io::Result<Guard<'a>>{
  crate::daemon::control::checkpoint()?;let(source,queries)=guard.ui_raw_operation_owner(workspace)?;proof.require_owner(workspace)?;let mut slot=self.workspace_operation.lock().unwrap_or_else(|e|e.into_inner());if slot.is_some(){return Err(io::Error::new(io::ErrorKind::WouldBlock,"workspace operation control is already bound"))}budget.charge(std::mem::size_of::<Frame>()+std::mem::size_of::<WorkspaceCapture>()+8*std::mem::size_of::<usize>()).map_err(|m|io::Error::new(io::ErrorKind::OutOfMemory,m))?;*slot=Some(Frame::UiRaw(UiFrame{proof:Arc::downgrade(proof),budget:Arc::downgrade(budget),workspace:Arc::downgrade(workspace),source:Arc::downgrade(&source),queries:Arc::downgrade(&queries)}));Ok(Guard{admission:self})
 }
 pub(super) fn current_ui_operation(&self)->io::Result<UiLoan>{
  crate::daemon::control::checkpoint()?;let slot=self.workspace_operation.lock().unwrap_or_else(|e|e.into_inner());let Some(Frame::UiRaw(frame))=slot.as_ref()else{return Err(io::Error::new(io::ErrorKind::InvalidInput,"UI child has no current sealed raw operation"))};let expired=||io::Error::new(io::ErrorKind::NotConnected,"UI raw operation owner expired");let loan=UiLoan{proof:frame.proof.upgrade().ok_or_else(expired)?,budget:frame.budget.upgrade().ok_or_else(expired)?,workspace:frame.workspace.upgrade().ok_or_else(expired)?,source:frame.source.upgrade().ok_or_else(expired)?,queries:frame.queries.upgrade().ok_or_else(expired)?};crate::runner_host::query_snapshot::workspace_native_guard::NativeReadGuard::raw_owned(&loan.workspace,&loan.source,&loan.queries)?;if !loan.source.purpose().is_ui(){return Err(io::Error::new(io::ErrorKind::InvalidInput,"UI child cannot borrow another raw purpose"))}loan.proof.require_published(&loan.workspace)?;loan.budget.require().map_err(|m|io::Error::new(io::ErrorKind::OutOfMemory,m))?;Ok(loan)
 }
}

impl Admission{pub(super) fn ui_operation_is_bound(&self)->bool{matches!(self.workspace_operation.lock().unwrap_or_else(|e|e.into_inner()).as_ref(),Some(Frame::UiRaw(_)))}}

#[derive(Clone)]pub(super) struct HandlerFrame{capture:Weak<crate::input_snapshot::HandlerPreparedCapture>,proof:Weak<crate::request_runner::runner_freshness::HandlerPolicyAdmission>,queries:Weak<QueryDb>,budget:Weak<Budget>,issuance:u64}
pub(super) struct HandlerLoan{pub capture:Arc<crate::input_snapshot::HandlerPreparedCapture>,pub proof:Arc<crate::request_runner::runner_freshness::HandlerPolicyAdmission>,pub queries:Arc<QueryDb>,pub budget:Arc<Budget>}
impl Admission{
 pub(super) fn bind_handlers_operation<'a>(&'a self,budget:&Arc<Budget>,capture:&Arc<crate::input_snapshot::HandlerPreparedCapture>,proof:&Arc<crate::request_runner::runner_freshness::HandlerPolicyAdmission>,queries:&Arc<QueryDb>)->io::Result<Guard<'a>>{
  crate::daemon::control::checkpoint()?;capture.require_bound()?;if !Arc::ptr_eq(capture,proof.capture())||!capture.uses_queries(queries){return Err(io::Error::new(io::ErrorKind::InvalidInput,"handler operation has another actual partial admission/query owner"))}
  let mut slot=self.workspace_operation.lock().unwrap_or_else(|e|e.into_inner());if slot.is_some(){return Err(io::Error::new(io::ErrorKind::WouldBlock,"handler operation cannot replace another active family operation"))}
  budget.charge(std::mem::size_of::<Frame>()+std::mem::size_of::<crate::input_snapshot::HandlerPreparedCapture>()+std::mem::size_of::<crate::request_runner::runner_freshness::HandlerPolicyAdmission>()+std::mem::size_of::<Budget>()+8*std::mem::size_of::<usize>()).map_err(|m|io::Error::new(io::ErrorKind::OutOfMemory,m))?;
  *slot=Some(Frame::Handlers(HandlerFrame{capture:Arc::downgrade(capture),proof:Arc::downgrade(proof),queries:Arc::downgrade(queries),budget:Arc::downgrade(budget),issuance:capture.issuance()}));Ok(Guard{admission:self})
 }
 pub(super) fn current_handlers_operation(&self,issuance:u64)->io::Result<HandlerLoan>{
  crate::daemon::control::checkpoint()?;let slot=self.workspace_operation.lock().unwrap_or_else(|e|e.into_inner());let Some(Frame::Handlers(frame))=slot.as_ref()else{return Err(io::Error::new(io::ErrorKind::InvalidInput,"handler child has no current sealed partial operation"))};if frame.issuance!=issuance{return Err(io::Error::new(io::ErrorKind::InvalidInput,"handler child actual issuance differs"))}
  let expired=||io::Error::new(io::ErrorKind::NotConnected,"handler active operation owner expired");let loan=HandlerLoan{capture:frame.capture.upgrade().ok_or_else(expired)?,proof:frame.proof.upgrade().ok_or_else(expired)?,queries:frame.queries.upgrade().ok_or_else(expired)?,budget:frame.budget.upgrade().ok_or_else(expired)?};
  if loan.capture.issuance()!=issuance||!Arc::ptr_eq(&loan.capture,loan.proof.capture())||!loan.capture.uses_queries(&loan.queries){return Err(io::Error::new(io::ErrorKind::InvalidData,"handler active operation actual owner differs"))}loan.capture.require_bound()?;loan.budget.require().map_err(|m|io::Error::new(io::ErrorKind::OutOfMemory,m))?;Ok(loan)
 }
 pub(super) fn handlers_operation_is_bound(&self)->bool{matches!(self.workspace_operation.lock().unwrap_or_else(|e|e.into_inner()).as_ref(),Some(Frame::Handlers(_)))}
}
