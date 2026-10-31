//! Current-operation control loan only. No source/result cache or authority.
use super::*;
use dq_analyze::captured_generator_budget::Budget;
use crate::runner_host::{workspace_capture::WorkspaceCapture,query_snapshot::workspace_native_guard::WorkspaceQueryScope};
#[derive(Clone)]pub(super) struct Frame{issuance:u64,evidence:u64,locator:(bool,u128),budget:Weak<Budget>,scope:Weak<WorkspaceQueryScope>,workspace:Weak<WorkspaceCapture>,capture:Weak<CapturedPolicyInputs>}
pub(super) struct Loan{pub locator:(bool,u128),pub budget:Arc<Budget>,pub scope:Arc<WorkspaceQueryScope>,pub workspace:Arc<WorkspaceCapture>,pub capture:Arc<CapturedPolicyInputs>}
pub(super) struct Guard<'a>{admission:&'a Admission}
impl Drop for Guard<'_>{fn drop(&mut self){self.admission.workspace_operation.lock().unwrap_or_else(|e|e.into_inner()).take();}}
impl Admission{
 pub(super) fn bind_workspace_operation<'a>(&'a self,budget:&Arc<Budget>,scope:&Arc<WorkspaceQueryScope>,workspace:&Arc<WorkspaceCapture>,capture:&Arc<CapturedPolicyInputs>)->io::Result<Guard<'a>>{
  crate::daemon::control::checkpoint()?;let mut current=self.workspace_operation.lock().unwrap_or_else(|e|e.into_inner());if current.is_some(){return Err(io::Error::new(io::ErrorKind::WouldBlock,"workspace operation control is already bound"))}
  let bytes=std::mem::size_of::<Frame>().checked_add(std::mem::size_of::<WorkspaceQueryScope>()).and_then(|n|n.checked_add(std::mem::size_of::<WorkspaceCapture>())).and_then(|n|n.checked_add(std::mem::size_of::<CapturedPolicyInputs>())).and_then(|n|n.checked_add(8*std::mem::size_of::<usize>())).ok_or_else(||{budget.deny();io::Error::new(io::ErrorKind::OutOfMemory,"workspace operation coordination overflow")})?;
  budget.charge(bytes).map_err(|message|io::Error::new(io::ErrorKind::OutOfMemory,message))?;
  let locator=super::reactive_read_policy::source_locator(capture)?;*current=Some(Frame{locator,issuance:workspace.issuance(),evidence:capture.semantic_source_evidence().key(),budget:Arc::downgrade(budget),scope:Arc::downgrade(scope),workspace:Arc::downgrade(workspace),capture:Arc::downgrade(capture)});Ok(Guard{admission:self})
 }
 pub(super) fn current_workspace_operation(&self,issuance:u64,evidence:u64)->io::Result<Loan>{
  crate::daemon::control::checkpoint()?;let current=self.workspace_operation.lock().unwrap_or_else(|e|e.into_inner());let frame=current.as_ref().ok_or_else(||io::Error::new(io::ErrorKind::NotConnected,"workspace query has no current operation control"))?;
  if frame.issuance!=issuance||frame.evidence!=evidence{return Err(io::Error::new(io::ErrorKind::InvalidData,"workspace operation locator/evidence differs"))}
  let missing=||io::Error::new(io::ErrorKind::NotConnected,"workspace operation owner expired");let loan=Loan{locator:frame.locator,budget:frame.budget.upgrade().ok_or_else(missing)?,scope:frame.scope.upgrade().ok_or_else(missing)?,workspace:frame.workspace.upgrade().ok_or_else(missing)?,capture:frame.capture.upgrade().ok_or_else(missing)?};
  if loan.workspace.issuance()!=issuance||loan.capture.semantic_source_evidence().key()!=evidence{return Err(io::Error::new(io::ErrorKind::InvalidData,"workspace operation actual frame differs"))}loan.budget.require().map_err(|message|io::Error::new(io::ErrorKind::OutOfMemory,message))?;Ok(loan)
 }
}
