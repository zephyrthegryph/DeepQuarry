//! Resource-only credit for the native transformed source arena. No source,
//! token, EOF, declaration or semantic authorization is carried by this value.
use std::{any::Any,io,sync::Arc};
/// Host-private issuer implements this for one actual allocation reservation.
/// The native host verifies its own concrete owner and existing resource domain.
pub trait SourceArenaCreditOwner: Send + Sync {
    fn as_any(&self) -> &dyn Any;
    fn reserved_bytes(&self) -> usize;
    fn visit_storage(&self, visit: &mut dyn FnMut(usize, usize));

    /// Release one strong resource owner. An issuer with allocation-order
    /// requirements may extract its concrete Arc payload before dropping it.
    /// Every strong alias of that issuer must use the same release path.
    fn release(self: Arc<Self>) {
        drop(self);
    }
}

/// Move-only. SourceText retains this with its last physical backing owner;
/// cloning a SourceText aliases that backing, never duplicates this reservation.
pub struct SourceArenaCredit {
    owner: Option<Arc<dyn SourceArenaCreditOwner>>,
}

/// Immutable control-block credit. Clones pay no allocation and cannot be grown
/// or converted back into a mutable payload reservation.
#[derive(Clone)]
pub struct SourceArenaControlCredit {
    owner: Option<Arc<dyn SourceArenaCreditOwner>>,
}

impl SourceArenaControlCredit {
    pub fn reserved_bytes(&self) -> usize {
        self.owner().reserved_bytes()
    }
    pub fn owner(&self) -> &dyn SourceArenaCreditOwner {
        self.owner.as_deref().expect("live source arena control credit")
    }
    pub fn visit_storage(&self, visit: &mut dyn FnMut(usize, usize)) {
        self.owner().visit_storage(visit)
    }
}

impl Drop for SourceArenaControlCredit {
    fn drop(&mut self) {
        if let Some(owner) = self.owner.take() {
            owner.release();
        }
    }
}

impl SourceArenaCredit {
    pub fn control(&self) -> SourceArenaControlCredit {
        SourceArenaControlCredit { owner: self.owner.clone() }
    }
    pub fn into_control(mut self) -> SourceArenaControlCredit {
        SourceArenaControlCredit { owner: self.owner.take() }
    }
    pub fn from_resource_owner(owner: Arc<dyn SourceArenaCreditOwner>) -> Self {
        Self { owner: Some(owner) }
    }
    pub fn reserved_bytes(&self) -> usize {
        self.owner().reserved_bytes()
    }
    pub fn owner(&self) -> &dyn SourceArenaCreditOwner {
        self.owner.as_deref().expect("live source arena payload credit")
    }
    pub fn visit_storage(&self, visit: &mut dyn FnMut(usize, usize)) {
        self.owner().visit_storage(visit)
    }
}

impl Drop for SourceArenaCredit {
    fn drop(&mut self) {
        if let Some(owner) = self.owner.take() {
            owner.release();
        }
    }
}

type AcquisitionControls = (SourceArenaControlCredit, SourceArenaControlCredit);

/// One operation-local loan from the actual admitted read. Only the read
/// driver constructs it. Providers can request storage, never substitute bytes.
pub struct OriginalReadTextFunding<'a> {
    split: &'a dyn Fn(usize) -> io::Result<Option<(SourceArenaCredit, SourceArenaControlCredit)>>,
    exceptional: &'a dyn Fn(usize, usize) -> io::Result<Option<(SourceArenaCredit, SourceArenaControlCredit)>>,
    acquisition: &'a dyn Fn([usize; 2]) -> io::Result<Option<AcquisitionControls>>,
    receipt: &'a dyn Fn(&(dyn Any + Send + Sync)) -> io::Result<Option<SourceArenaControlCredit>>,
}

impl OriginalReadTextFunding<'_> {
    pub(crate) fn split(&self, capacity: usize)
        -> io::Result<Option<(SourceArenaCredit, SourceArenaControlCredit)>>
    {
        (self.split)(capacity)
    }
    #[doc(hidden)]
    pub fn split_exceptional_bytes(&self, capacity: usize, control: usize)
        -> io::Result<Option<(SourceArenaCredit, SourceArenaControlCredit)>> {
        (self.exceptional)(capacity, control)
    }
    pub(crate) fn split_acquisition_controls(&self, sizes: [usize; 2])
        -> io::Result<Option<AcquisitionControls>>
    {
        (self.acquisition)(sizes)
    }
    pub(crate) fn split_receipt(&self, receipt: &(dyn Any + Send + Sync)) -> io::Result<Option<SourceArenaControlCredit>> {
        (self.receipt)(receipt)
    }

}

/// Borrowed operation lender. Retained credits must not retain this lender,
/// QueryDb, the source census, a source model or an independent budget manager.
/// Reserve the complete new allocation while old storage is still live. Shrink
/// only AFTER physical release. A failed allocation keeps its peak reservation
/// until credit drop, so cleanup cannot replace the original operational error.
pub trait SourceArenaWork:Send+Sync{
 /// Reserve actual physical-origin page/directory storage. The resulting
 /// credit grows or shrinks in place and never enters raw-read adoption.
 fn reserve_original_origin_storage(&self,bytes:usize)->io::Result<SourceArenaCredit>{self.reserve(bytes)}

 /// Optional exact geometry optimization. Ordinary/unqualified lenders
 /// preserve the existing representation. Native pressure declines only
 /// the extra staged grant, never an authored or operational error.
 fn try_grow_original_origin_storage(&self,_credit:&mut SourceArenaCredit,_extra:usize)->io::Result<bool>{Ok(false)}

 /// Partition an actual read grant into fresh String payload and backing credits.
 /// Providers without an owned transfer retain their existing allocation path.
 fn split_original_text(
    &self, _donor: &mut SourceArenaCredit, _capacity: usize,
 ) -> io::Result<Option<(SourceArenaCredit, SourceArenaControlCredit)>> {
    Ok(None)
 }

 /// Partition the fresh exceptional raw buffer and its immutable owner control.
 fn split_original_exceptional_bytes(
     &self, _donor: &mut SourceArenaCredit, _capacity: usize, _control: usize,
 ) -> io::Result<Option<(SourceArenaCredit, SourceArenaControlCredit)>> {
     Ok(None)
 }

 /// Partition the exact opened-read constructor's two fixed object layouts.
 fn split_original_acquisition_controls(
     &self, _donor: &mut SourceArenaCredit, _sizes: [usize; 2],
 ) -> io::Result<Option<(SourceArenaControlCredit, SourceArenaControlCredit)>> {
     Ok(None)
 }

 /// Transfer the pregrant for an actual exact opened-read receipt.
 fn split_original_receipt(
     &self, _donor: &mut SourceArenaCredit, _receipt: &(dyn Any + Send + Sync),
 ) -> io::Result<Option<SourceArenaControlCredit>> {
     Ok(None)
 }

 /// Maximum address range for the transformed source. Reserved addresses have
 /// no backing until the arena uses the existing reserve/grow methods to pay
 /// for each newly committed page. Hosts without this facility keep the String.
 fn transformed_source_address_limit(&self)->Option<usize>{None}
 /// Existing family bookkeeping pregrant for the actual maximum source/object
 /// observation count. No semantic authority or second budget is issued.
 fn original_read_bookkeeping_bytes(&self)->io::Result<usize>{Err(io::Error::new(io::ErrorKind::NotConnected,"host cannot fund Original read observations"))}
 /// Settle actual read allocations before the provider may return/fail after
 /// exceptional publication. Cleanup operation: do not checkpoint mid-commit.
 fn adopt_original_read(&self,_credit:&mut SourceArenaCredit,_source:&crate::SourceAcquisitionLease)->io::Result<()>{Err(io::Error::new(io::ErrorKind::NotConnected,"host cannot adopt Original read observations"))}
 /// Settle an already-funded immutable recorder path grant into one
 /// recorder-owned aggregate. Unsupported lenders keep their exact grant.
 fn bank_original_path_fact(&self,_credit:&mut SourceArenaCredit,_bank:&std::sync::Mutex<Option<SourceArenaControlCredit>>)->io::Result<bool>{Ok(false)}
 fn checkpoint(&self)->io::Result<()>;
 fn reserve(&self,bytes:usize)->io::Result<SourceArenaCredit>;
 fn grow(&self,credit:&mut SourceArenaCredit,extra:usize)->io::Result<()>;
 fn shrink(&self,credit:&mut SourceArenaCredit,bytes:usize)->io::Result<()>;
}

/// One operation-local read owner in the SAME existing input-family. No family
/// gate spans provider IO, decoding, source-stack or parser callbacks. Its peak
/// reservation disappears only after acquired() registers actual weak owners.
struct ReadFunding{credit:SourceArenaCredit,raw:Option<usize>,planned:bool,new_source:bool,delivered:bool,text_factory_used:bool,receipt_funding_used:bool,acquisition_funding_used:bool,owned_text_allowed:bool,exceptional_allowed:bool}
struct OriginalReadFunding<'a>{work:&'a dyn SourceArenaWork,max:usize,state:std::cell::RefCell<ReadFunding>,first:std::cell::RefCell<Option<io::Error>>}
impl<'a>OriginalReadFunding<'a>{
 fn new(work:&'a dyn SourceArenaWork,max:usize)->io::Result<Self>{let bookkeeping=work.original_read_bookkeeping_bytes()?;Ok(Self{work,max,state:std::cell::RefCell::new(ReadFunding{credit:work.reserve(bookkeeping)?,raw:None,planned:false,new_source:false,delivered:false,text_factory_used:false,receipt_funding_used:false,acquisition_funding_used:false,owned_text_allowed:false,exceptional_allowed:false}),first:std::cell::RefCell::new(None)})}
 /// A provider cannot replace/swallow a host callback's first actual error or
 /// relabel resource NotFound as source absence. Placeholder never escapes.
 fn callback<T>(&self,run:impl FnOnce()->io::Result<T>)->io::Result<T>{if self.first.borrow().is_some(){return Err(io::ErrorKind::Other.into())}match run(){Ok(value)=>Ok(value),Err(actual)=>{*self.first.borrow_mut()=Some(actual);Err(io::ErrorKind::Other.into())}}}
 fn before_read(&self,capacity:usize)->io::Result<()>{self.callback(||{let mut state=self.state.borrow_mut();if state.raw.is_some()||capacity>self.max{return Err(io::Error::new(io::ErrorKind::InvalidInput,"Original raw provider repeated/exceeded actual preallocation"))}self.work.grow(&mut state.credit,capacity)?;state.raw=Some(capacity);Ok(())})}
 fn before_decode(&self,plan:crate::OriginalRawAllocationPlan<'_>)->io::Result<()>{self.callback(||{let mut state=self.state.borrow_mut();if state.planned{return Err(io::Error::new(io::ErrorKind::InvalidInput,"Original raw provider repeated decode allocation plan"))}if plan.needs_decode(){if state.raw!=Some(plan.capacity())||plan.original().len()>plan.capacity(){return Err(io::Error::new(io::ErrorKind::InvalidInput,"Original decode plan differs from SAME admitted raw buffer"))}if !plan.exceptional()&&plan.decoded_bytes()!=0{return Err(io::Error::new(io::ErrorKind::InvalidInput,"UTF8 move plan claims a second decoded buffer"))}let bytes=plan.constructor_bytes().checked_add(plan.decoded_bytes()).ok_or(io::ErrorKind::OutOfMemory)?;self.work.grow(&mut state.credit,bytes)?;}else if state.raw.is_some()||plan.capacity()!=0||plan.constructor_bytes()!=0||plan.decoded_bytes()!=0{return Err(io::Error::new(io::ErrorKind::InvalidInput,"prepaid Original subject plan attempts new backing allocation"))}state.planned=true;state.new_source=plan.needs_decode();state.owned_text_allowed=plan.needs_decode()&&!plan.exceptional();state.exceptional_allowed=plan.needs_decode()&&plan.exceptional();Ok(())})}
 fn split_text(&self, capacity: usize) -> io::Result<Option<(SourceArenaCredit, SourceArenaControlCredit)>> {
    self.callback(|| {
        let mut state = self.state.borrow_mut();
        if !state.planned || !state.owned_text_allowed || state.delivered
            || state.text_factory_used || state.raw != Some(capacity)
        {
            return Err(io::Error::new(io::ErrorKind::InvalidInput,
                "owned source backing differs from the admitted fresh read"));
        }
        state.text_factory_used = true;
        self.work.split_original_text(&mut state.credit, capacity)
    })
 }
 fn split_exceptional_bytes(&self, capacity: usize, control: usize)
     -> io::Result<Option<(SourceArenaCredit, SourceArenaControlCredit)>> {
     self.callback(|| {
         let mut state = self.state.borrow_mut();
         if !state.planned || !state.exceptional_allowed || state.delivered
             || state.text_factory_used || state.raw != Some(capacity)
         {
             return Err(io::Error::new(io::ErrorKind::InvalidInput,
                 "exceptional raw backing differs from the admitted fresh read"));
         }
         state.text_factory_used = true;
         self.work.split_original_exceptional_bytes(&mut state.credit, capacity, control)
     })
 }
 fn split_acquisition_controls(&self, sizes: [usize; 2]) -> io::Result<Option<AcquisitionControls>> {
     self.callback(|| {
         let mut state = self.state.borrow_mut();
         if !state.planned || !state.owned_text_allowed || state.delivered
             || state.acquisition_funding_used || state.receipt_funding_used
         {
             return Err(io::Error::new(io::ErrorKind::InvalidInput,
                 "acquisition funding requires the admitted exact plain UTF-8 read"));
         }
         state.acquisition_funding_used = true;
         self.work.split_original_acquisition_controls(&mut state.credit, sizes)
     })
 }
 fn split_receipt(&self, receipt: &(dyn Any + Send + Sync)) -> io::Result<Option<SourceArenaControlCredit>> {
     self.callback(|| {
         let mut state = self.state.borrow_mut();
         if !state.planned || !state.owned_text_allowed || state.delivered || state.receipt_funding_used {
             return Err(io::Error::new(io::ErrorKind::InvalidInput,
                 "receipt funding requires the admitted exact plain UTF-8 read"));
         }
         state.receipt_funding_used = true;
         self.work.split_original_receipt(&mut state.credit, receipt)
     })
 }
 fn acquired(&self,source:&crate::SourceAcquisitionLease)->io::Result<()>{
  if self.first.borrow().is_some(){
   // Exceptional provider publication must still be registered at the SAME
   // weak source ledger before returning the already-owned first failure.
   // adopt_original_read is a cleanup commit: it registers physical owners
   // before any denial and cannot replace this prior operational error.
   let mut state=self.state.borrow_mut();if state.planned&&state.new_source&&!state.delivered{let cleanup=self.work.adopt_original_read(&mut state.credit,source);state.delivered=true;match cleanup{Ok(())=>(),Err(_later)=>()}}return Err(io::ErrorKind::Other.into())
  }
  self.callback(||{let mut state=self.state.borrow_mut();if !state.planned||state.delivered{return Err(io::Error::new(io::ErrorKind::InvalidInput,"Original provider delivered outside its actual allocation plan"))}let new_source=state.new_source;state.delivered=true;if new_source{self.work.adopt_original_read(&mut state.credit,source)?;}Ok(())})}
 fn finish<T>(&self,result:io::Result<T>)->io::Result<T>{if let Some(actual)=self.first.borrow_mut().take(){return Err(actual)}result}
 fn require_delivery(&self,expected:bool)->io::Result<()>{let state=self.state.borrow();if state.delivered!=expected||!expected&&(state.raw.is_some()||state.planned){return Err(io::Error::new(io::ErrorKind::InvalidInput,"Original provider result differs from actual admitted/delivered state"))}Ok(())}
}
pub fn read_original_source_using(provider:&dyn crate::SourceProvider,path:&std::path::Path,max_bytes:usize,work:&dyn SourceArenaWork)->io::Result<Option<crate::SourceAcquisitionLease>>{
 let funding=OriginalReadFunding::new(work,max_bytes)?;let pending=provider.original_raw_source_admitted(path,max_bytes,&mut|size|funding.before_read(size),&mut|plan|funding.before_decode(plan),&mut|source|funding.acquired(source));let result=funding.finish(pending)?;funding.require_delivery(result.is_some())?;Ok(result)
}
/// Same funding/first-error/adoption protocol, adding ONLY the actual reader
/// decision before payload. Explicit suppression cannot pay read/decode quota
/// and cannot stand in for source absence, a source acquisition or raw EOF.
pub fn read_original_source_open_using(provider:&dyn crate::SourceProvider,path:&std::path::Path,max_bytes:usize,work:&dyn SourceArenaWork,after_open:&mut dyn FnMut()->io::Result<crate::OriginalRawOpenDecision>)->io::Result<crate::OriginalRawReadOutcome>{
 let funding=OriginalReadFunding::new(work,max_bytes)?;let decision=std::cell::Cell::new(None);
 let fund_text = OriginalReadTextFunding {
     split: &|capacity| funding.split_text(capacity),
     exceptional: &|capacity, control| funding.split_exceptional_bytes(capacity, control),
     acquisition: &|sizes| funding.split_acquisition_controls(sizes),
     receipt: &|receipt| funding.split_receipt(receipt),
 };
 let pending=provider.original_raw_source_open_owned_admitted(path,max_bytes,work,&mut||funding.callback(||{if decision.get().is_some(){return Err(io::Error::new(io::ErrorKind::InvalidData,"Original reader repeated after-open decision"))}let actual=after_open()?;decision.set(Some(actual));Ok(actual)}),&mut|size|{if decision.get()!=Some(crate::OriginalRawOpenDecision::Read){return funding.callback(||Err(io::Error::new(io::ErrorKind::InvalidData,"payload allocation before actual read decision")))}funding.before_read(size)},&mut|plan|{if decision.get()!=Some(crate::OriginalRawOpenDecision::Read){return funding.callback(||Err(io::Error::new(io::ErrorKind::InvalidData,"decode before actual read decision")))}funding.before_decode(plan)},&fund_text,&mut|source|{if decision.get()!=Some(crate::OriginalRawOpenDecision::Read){return funding.callback(||Err(io::Error::new(io::ErrorKind::InvalidData,"acquisition before actual read decision")))}funding.acquired(source)});
 let result=funding.finish(pending)?;let valid=match &result{crate::OriginalRawReadOutcome::Acquired(_)=>decision.get()==Some(crate::OriginalRawOpenDecision::Read),crate::OriginalRawReadOutcome::Suppressed=>decision.get()==Some(crate::OriginalRawOpenDecision::Suppress),crate::OriginalRawReadOutcome::Absent|crate::OriginalRawReadOutcome::SourceOpenFailed(_)=>decision.get().is_none()};if !valid{return Err(io::Error::new(io::ErrorKind::InvalidData,"Original result does not belong to its actual reader decision"))}funding.require_delivery(matches!(&result,crate::OriginalRawReadOutcome::Acquired(_)))?;Ok(result)
}

#[cfg(test)]mod open_funding_tests{
 use super::*;use std::{cell::Cell,sync::atomic::{AtomicUsize,Ordering},path::Path};
 struct Credit{bytes:AtomicUsize,live:Arc<AtomicUsize>}
 impl Drop for Credit{fn drop(&mut self){self.live.fetch_sub(self.bytes.load(Ordering::Acquire),Ordering::AcqRel);}}
 impl SourceArenaCreditOwner for Credit{fn as_any(&self)->&dyn Any{self}fn reserved_bytes(&self)->usize{self.bytes.load(Ordering::Acquire)}fn visit_storage(&self,_:&mut dyn FnMut(usize,usize)){}}
 struct Work{live:Arc<AtomicUsize>,limit:usize}
 impl Work{fn new(limit:usize)->Self{Self{live:Arc::new(AtomicUsize::new(0)),limit}}fn charge(&self,n:usize)->io::Result<()>{self.live.fetch_update(Ordering::AcqRel,Ordering::Acquire,|v|v.checked_add(n).filter(|n|*n<=self.limit)).map(|_|()).map_err(|_|io::ErrorKind::OutOfMemory.into())}}
 impl SourceArenaWork for Work{
  fn checkpoint(&self)->io::Result<()>{Ok(())}fn original_read_bookkeeping_bytes(&self)->io::Result<usize>{Ok(16)}
  fn reserve(&self,n:usize)->io::Result<SourceArenaCredit>{self.charge(n)?;Ok(SourceArenaCredit::from_resource_owner(Arc::new(Credit{bytes:AtomicUsize::new(n),live:self.live.clone()})))}
  fn grow(&self,c:&mut SourceArenaCredit,n:usize)->io::Result<()>{let owner=c.owner().as_any().downcast_ref::<Credit>().ok_or(io::ErrorKind::InvalidInput)?;if !Arc::ptr_eq(&owner.live,&self.live){return Err(io::ErrorKind::InvalidInput.into())}self.charge(n)?;owner.bytes.fetch_add(n,Ordering::AcqRel);Ok(())}
  fn shrink(&self,c:&mut SourceArenaCredit,n:usize)->io::Result<()>{let owner=c.owner().as_any().downcast_ref::<Credit>().ok_or(io::ErrorKind::InvalidInput)?;owner.bytes.fetch_update(Ordering::AcqRel,Ordering::Acquire,|v|v.checked_sub(n)).map_err(|_|io::ErrorKind::InvalidInput)?;self.live.fetch_sub(n,Ordering::AcqRel);Ok(())}
 }
 enum Mode{Suppress,SwallowOpenError,WithoutOpen,ReadAfterSuppress,Prepaid}
 struct Provider{calls:Cell<usize>,mode:Mode,source:crate::SourceAcquisitionLease}
 impl Provider{fn new(mode:Mode)->Self{Self{calls:Cell::new(0),mode,source:crate::SourceAcquisitionLease::from_raw_original_bytes(b"x".to_vec(),17u64)}}}
 impl crate::SourceProvider for Provider{
  fn read(&self,_:&Path)->Result<String,String>{panic!("funding protocol never selects another source read")}
  fn original_raw_source_open_admitted(&self,_:&Path,_:usize,_:&dyn SourceArenaWork,opened:&mut dyn FnMut()->io::Result<crate::OriginalRawOpenDecision>,before_read:&mut dyn FnMut(usize)->io::Result<()>,before_decode:&mut dyn FnMut(crate::OriginalRawAllocationPlan<'_>)->io::Result<()>,acquired:&mut dyn FnMut(&crate::SourceAcquisitionLease)->io::Result<()>)->io::Result<crate::OriginalRawReadOutcome>{self.calls.set(self.calls.get()+1);match self.mode{Mode::Suppress=>{assert_eq!(opened()?,crate::OriginalRawOpenDecision::Suppress);Ok(crate::OriginalRawReadOutcome::Suppressed)},Mode::SwallowOpenError=>{assert!(opened().is_err());Ok(crate::OriginalRawReadOutcome::SourceOpenFailed(io::ErrorKind::NotFound.into()))},Mode::WithoutOpen=>Ok(crate::OriginalRawReadOutcome::Suppressed),Mode::ReadAfterSuppress=>{assert_eq!(opened()?,crate::OriginalRawOpenDecision::Suppress);assert!(before_read(8).is_err());Ok(crate::OriginalRawReadOutcome::Suppressed)},Mode::Prepaid=>{assert_eq!(opened()?,crate::OriginalRawOpenDecision::Read);before_decode(crate::OriginalRawAllocationPlan::new(&[],0,0,0,false,false))?;acquired(&self.source)?;Ok(crate::OriginalRawReadOutcome::Acquired(self.source.clone()))}}}
 }
 #[test]fn exact_suppression_has_no_payload_decode_or_acquisition_charge_and_releases_bookkeeping(){let work=Work::new(16);let provider=Provider::new(Mode::Suppress);assert!(matches!(read_original_source_open_using(&provider,Path::new("source.dm"),0,&work,&mut||Ok(crate::OriginalRawOpenDecision::Suppress)).unwrap(),crate::OriginalRawReadOutcome::Suppressed));assert_eq!(provider.calls.get(),1);assert_eq!(work.live.load(Ordering::Acquire),0);}
 #[test]fn actual_open_callback_io_survives_a_provider_attempt_to_relabel_it_as_not_found(){let work=Work::new(16);let provider=Provider::new(Mode::SwallowOpenError);assert_eq!(read_original_source_open_using(&provider,Path::new("source.dm"),0,&work,&mut||Err(io::Error::from_raw_os_error(1450))).err().unwrap().raw_os_error(),Some(1450));assert_eq!(work.live.load(Ordering::Acquire),0);}
 #[test]fn resource_bookkeeping_refusal_precedes_actual_provider_open(){let work=Work::new(0);let provider=Provider::new(Mode::Suppress);assert_eq!(read_original_source_open_using(&provider,Path::new("source.dm"),0,&work,&mut||panic!("no provider open after quota")).err().unwrap().kind(),io::ErrorKind::OutOfMemory);assert_eq!(provider.calls.get(),0);assert_eq!(work.live.load(Ordering::Acquire),0);}
 #[test]fn fake_suppression_and_payload_after_suppression_cannot_issue_results(){for mode in [Mode::WithoutOpen,Mode::ReadAfterSuppress]{let work=Work::new(64);let provider=Provider::new(mode);assert_eq!(read_original_source_open_using(&provider,Path::new("source.dm"),64,&work,&mut||Ok(crate::OriginalRawOpenDecision::Suppress)).err().unwrap().kind(),io::ErrorKind::InvalidData);assert_eq!(work.live.load(Ordering::Acquire),0);}}
 #[test]fn real_prepaid_subject_decision_still_requires_same_decode_and_acquired_protocol(){let work=Work::new(16);let provider=Provider::new(Mode::Prepaid);let crate::OriginalRawReadOutcome::Acquired(source)=read_original_source_open_using(&provider,Path::new("captured-subject"),1,&work,&mut||Ok(crate::OriginalRawOpenDecision::Read)).unwrap()else{panic!("actual prepaid subject")};assert!(source.same_original_acquisition(&provider.source));assert_eq!(work.live.load(Ordering::Acquire),0);}
}

#[cfg(test)]
mod release_dispatch_tests {
    use super::*;
    use std::sync::Mutex;

    struct Probe(Arc<Mutex<Vec<&'static str>>>);

    impl SourceArenaCreditOwner for Probe {
        fn as_any(&self) -> &dyn Any { self }
        fn reserved_bytes(&self) -> usize { 31 }
        fn visit_storage(&self, _: &mut dyn FnMut(usize, usize)) {}
        fn release(self: Arc<Self>) {
            if let Some(payload) = Arc::into_inner(self) {
                payload.0.lock().unwrap().push("arc released");
                drop(payload);
            }
        }
    }

    impl Drop for Probe {
        fn drop(&mut self) {
            self.0.lock().unwrap().push("payload dropped");
        }
    }

    #[test]
    fn payload_credit_dispatches_release_before_concrete_payload_drop() {
        let events = Arc::new(Mutex::new(Vec::new()));
        let payload = SourceArenaCredit::from_resource_owner(Arc::new(Probe(events.clone())));
        drop(payload);
        assert_eq!(*events.lock().unwrap(), ["arc released", "payload dropped"]);
    }

    #[test]
    fn converted_control_alias_preserves_identity_and_releases_last() {
        let events = Arc::new(Mutex::new(Vec::new()));
        let owner = Arc::new(Probe(events.clone()));
        let weak = Arc::downgrade(&owner);
        let payload = SourceArenaCredit::from_resource_owner(owner);
        let alias = payload.control();
        let identity = alias.owner().as_any().downcast_ref::<Probe>().unwrap() as *const Probe;
        let converted = payload.into_control();
        assert_eq!(weak.strong_count(), 2);
        assert_eq!(converted.owner().as_any().downcast_ref::<Probe>().unwrap() as *const Probe, identity);
        assert_eq!(converted.reserved_bytes(), 31);
        drop(alias);
        assert!(events.lock().unwrap().is_empty());
        drop(converted);
        assert_eq!(weak.strong_count(), 0);
        assert_eq!(*events.lock().unwrap(), ["arc released", "payload dropped"]);
        assert_eq!(std::mem::size_of::<SourceArenaCredit>(), std::mem::size_of::<Arc<dyn SourceArenaCreditOwner>>());
        assert_eq!(std::mem::size_of::<SourceArenaControlCredit>(), std::mem::size_of::<Arc<dyn SourceArenaCreditOwner>>());
    }
}
