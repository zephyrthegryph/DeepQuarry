//! One resource-only allocation role in the EXISTING raw input-family ledger.
//! No query kind, semantic cache, cap or independent domain counter is added.
use super::*;
use dm_preprocess::source_arena_credit::{SourceArenaControlCredit,SourceArenaCredit,SourceArenaCreditOwner,SourceArenaWork};
use std::sync::atomic::{AtomicUsize,Ordering};
/// Only actual reservation size and a WEAK identity of the existing Admission.
/// No QueryDb, ledger or source/model owner is retained by an escaped SourceText.
pub(super) struct Allocation{
    bytes:AtomicUsize,
    domain:Weak<crate::query_db::raw_policy::Admission>,
    // Only actual origin payload/page-control bytes. This Allocation's Arc
    // and its Weak ledger row stay under existing source-family admission.
    origin_parent:Option<Arc<dm_syntax::SharedNativeReservation>>,
    read_group:std::sync::OnceLock<Arc<OriginalReadGroup>>,
}
impl Drop for Allocation {
    fn drop(&mut self) {
        if let Some(parent)=&self.origin_parent { parent.release(self.reserved_bytes()); }
        if self.is_retirable_path_fact() {
            if let Some(bank)=self.read_group.get() {
                bank.release_parts(self.reserved_bytes() + Self::metadata_bytes());
            }
        }
    }
}
fn parent_denied(message:&'static str)->io::Error{io::Error::new(io::ErrorKind::OutOfMemory,message)}

// Every native allocation is admitted under the existing raw input-family
// limit, well below this flag even on 32-bit hosts. A settled path-fact
// insertion is immutable except for exact last-owner refunds.
const RETIRABLE_PATH_FACTS: usize = 1 << (usize::BITS - 1);
const _: () = assert!(super::raw_policy::INPUT_BUDGET < RETIRABLE_PATH_FACTS);
impl Allocation {
    #[cfg(debug_assertions)]
    pub(super) fn is_origin_allocation(&self) -> bool { self.origin_parent.is_some() }

    pub(super) fn metadata_bytes() -> usize { std::mem::size_of::<Self>() + 2 * std::mem::size_of::<usize>() }

    pub(super) fn retained_bytes(&self) -> io::Result<usize> {
        Self::metadata_bytes().checked_add(self.reserved_bytes()).ok_or_else(oom)
    }

    pub(super) fn store_reserved_bytes(&self, bytes: usize) {
        assert!(bytes < RETIRABLE_PATH_FACTS && !self.is_retirable_path_fact());
        self.bytes.store(bytes, Ordering::Release);
    }

    fn is_retirable_path_fact(&self) -> bool {
        self.bytes.load(Ordering::Acquire) & RETIRABLE_PATH_FACTS != 0
    }

    fn same_domain(&self, domain: &Weak<crate::query_db::raw_policy::Admission>) -> bool {
        Weak::ptr_eq(&self.domain, domain)
    }
}

/// Path-fact insertion consumes its mutable credit and settles all temporary
/// nodes before the new immutable root escapes. Other arena credits never
/// enter this mode; nonnative fixture lenders keep their conservative grants.
pub(crate) fn seal_path_fact_control(credit: SourceArenaCredit) {
    if let Some(actual) = credit.owner().as_any().downcast_ref::<Allocation>() {
        assert!(actual.origin_parent.is_none(),"only ordinary path-fact credits can enter immutable node retirement");
        let previous = actual.bytes.fetch_or(RETIRABLE_PATH_FACTS, Ordering::AcqRel);
        debug_assert_eq!(previous & RETIRABLE_PATH_FACTS, 0);
    }
}

/// The path-fact owner invokes this only after destroying one exact node.
/// This monotone decrease cannot undercount a cached ledger upper; the next
/// existing exact sweep observes it. No ledger lock can recurse from Drop.
pub(crate) fn retire_path_fact_node(credit: &SourceArenaControlCredit, bytes: usize) {
    let Some(actual) = credit.owner().as_any().downcast_ref::<Allocation>() else { return; };
    let retired = actual.bytes.fetch_update(Ordering::AcqRel, Ordering::Acquire, |state| {
        if state & RETIRABLE_PATH_FACTS == 0 {
            return None;
        }
        let reserved = state & !RETIRABLE_PATH_FACTS;
        let remaining = reserved.checked_sub(bytes).expect("path fact node's unique reservation");
        Some(RETIRABLE_PATH_FACTS | remaining)
    }).is_ok();
    if retired {
        if let Some(bank)=actual.read_group.get() { bank.release_parts(bytes); }
    }
}
/// Concrete strong handles cover temporary ledger upgrades and registration
/// failure before an owner enters the public, erased credit handles.
pub(super) struct AllocationHandle(Option<Arc<Allocation>>);
impl AllocationHandle {
    pub(super) fn new(owner: Arc<Allocation>) -> Self {
        Self(Some(owner))
    }
    pub(super) fn arc(&self) -> &Arc<Allocation> {
        self.0.as_ref().expect("live native allocation handle")
    }
    fn into_credit(mut self) -> SourceArenaCredit {
        SourceArenaCredit::from_resource_owner(self.0.take().expect("live native allocation"))
    }
    fn register(mut self, ledger: &mut super::raw_input_credits::Ledger, admitted: usize) -> io::Result<SourceArenaCredit> {
        ledger.register_source_arena(self.arc(), admitted)?;
        Ok(SourceArenaCredit::from_resource_owner(self.0.take().expect("registered native allocation")))
    }
}
impl Drop for AllocationHandle {
    fn drop(&mut self) {
        if let Some(owner) = self.0.take() {
            owner.release();
        }
    }
}
impl SourceArenaCreditOwner for Allocation{
 fn as_any(&self)->&dyn std::any::Any{self}
 fn release(self: Arc<Self>) {
    // Every strong handle uses this path. Extraction relinquishes the Arc's
    // implicit Weak before payload drop. Explicit ledger Weak references
    // retain their control allocation independently.
    drop(Arc::into_inner(self));
 }

 fn reserved_bytes(&self)->usize{self.bytes.load(Ordering::Acquire) & !RETIRABLE_PATH_FACTS}
 fn visit_storage(&self,visit:&mut dyn FnMut(usize,usize)){visit(std::ptr::from_ref(self)as usize,Self::metadata_bytes())}
}
/// One ledger observation for independent immutable acquisition binding,
/// original identity and receipt credits from the SAME actual read donor.
/// These parts keep their own exact release lifetimes.
pub(super) struct OriginalReadGroup {
    parts: AtomicUsize,
    domain: Weak<super::super::Admission>,
}

impl OriginalReadGroup {
    fn new(domain: &Weak<super::super::Admission>) -> Self {
        Self { parts: AtomicUsize::new(0), domain:domain.clone() }
    }

    fn same_domain(&self, domain:&Weak<super::super::Admission>) -> bool {
        Weak::ptr_eq(&self.domain,domain)
    }

    pub(super) fn metadata_bytes() -> usize { std::mem::size_of::<Self>() + 2 * std::mem::size_of::<usize>() }
    pub(super) fn retained_bytes(&self) -> io::Result<usize> {
        self.parts.load(Ordering::Acquire).checked_add(Self::metadata_bytes()).ok_or_else(oom)
    }

    pub(super) fn add_admitted_parts(&self, bytes: usize) {
        // Every addition holds the one family gate and checked the charged
        // row upper bound. Last-part drops can only decrease the atomic.
        self.parts.fetch_add(bytes, Ordering::AcqRel);
    }

    fn release_parts(&self, bytes: usize) {
        let prior = self.parts.fetch_sub(bytes, Ordering::AcqRel);
        assert!(prior >= bytes, "one issued reservation part refund");
    }
}

impl SourceArenaCreditOwner for OriginalReadGroup {
    fn as_any(&self) -> &dyn std::any::Any { self }
    fn reserved_bytes(&self) -> usize { self.parts.load(Ordering::Acquire) }
    fn visit_storage(&self, visit: &mut dyn FnMut(usize, usize)) {
        visit(std::ptr::from_ref(self) as usize, Self::metadata_bytes());
    }
    fn release(self: Arc<Self>) { drop(Arc::into_inner(self)); }
}

#[derive(Clone, Copy, Eq, PartialEq)]
#[repr(usize)]
pub(super) enum ReadPartRole { Acquisition=0, TextPayload=1, TextControl=2 }

pub(super) struct OriginalReadPart {
    group: Arc<OriginalReadGroup>,
    encoded: usize,
}

impl OriginalReadPart {
    fn metadata_bytes() -> usize { std::mem::size_of::<Self>() + 2 * std::mem::size_of::<usize>() }
    const ROLE_SHIFT: u32 = usize::BITS - 2;
    const BYTE_MASK: usize = (1usize << Self::ROLE_SHIFT) - 1;

    fn new(group:Arc<OriginalReadGroup>, bytes:usize, role:ReadPartRole)->Self{
        debug_assert!(bytes<=Self::BYTE_MASK);
        Self{group,encoded:bytes|((role as usize)<<Self::ROLE_SHIFT)}
    }

    pub(super) fn group(&self) -> &Arc<OriginalReadGroup> { &self.group }
    pub(super) fn role(&self) -> ReadPartRole {
        match self.encoded >> Self::ROLE_SHIFT {
            0=>ReadPartRole::Acquisition,
            1=>ReadPartRole::TextPayload,
            2=>ReadPartRole::TextControl,
            _=>unreachable!("issued read part role"),
        }
    }
}

const _: () = assert!(super::raw_policy::INPUT_BUDGET <= OriginalReadPart::BYTE_MASK);

impl Drop for OriginalReadPart {
    fn drop(&mut self) {
        let released = self.reserved_bytes() + Self::metadata_bytes();
        let prior = self.group.parts.fetch_sub(released, Ordering::AcqRel);
        assert!(prior >= released, "one issued acquisition part refund");
    }
}

impl SourceArenaCreditOwner for OriginalReadPart {
    fn as_any(&self) -> &dyn std::any::Any { self }
    fn reserved_bytes(&self) -> usize { self.encoded & Self::BYTE_MASK }
    fn visit_storage(&self, visit: &mut dyn FnMut(usize, usize)) {
        visit(std::ptr::from_ref(self) as usize, Self::metadata_bytes());
        visit(Arc::as_ptr(&self.group) as usize, OriginalReadGroup::metadata_bytes());
    }
    fn release(self: Arc<Self>) {
        // No direct strong Arc/Weak is exposed. All aliases extract only the
        // last payload, after the child's physical Arc control is freed.
        drop(Arc::into_inner(self));
    }
}

fn split_read_parts<const N: usize>(
    ledger: &mut super::raw_input_credits::Ledger,
    donor: &Allocation,
    parts: [(usize, ReadPartRole); N],
    slot: Option<&dm_preprocess::source_arena_credit::OriginalReadGroupSlot>,
    admit_extra: impl FnOnce(&mut super::raw_input_credits::Ledger, usize) -> io::Result<()>,
) -> io::Result<[SourceArenaCredit; N]> {
    if donor.origin_parent.is_some() || !ledger.has_source_arena(donor) { return Err(wrong()); }
    // Both native lenders already hold the same-family ledger. No caller
    // enters this private recorder slot before acquiring that ledger.
    let mut slot = slot.map(|slot| slot.lock().map_err(|_| wrong())).transpose()?;
    let bank = slot.as_deref().and_then(Option::as_ref).map(|credit| {
        let group = credit.owner().as_any().downcast_ref::<OriginalReadGroup>().ok_or_else(wrong)?;
        if !group.same_domain(&donor.domain) { return Err(wrong()); }
        ledger.loan_original_read_group(group)
    }).transpose()?;
    let attached = donor.read_group.get();
    if attached.zip(bank.as_ref()).is_some_and(|(old, bank)| !Arc::ptr_eq(old, bank)) {
        return Err(wrong());
    }
    let existing = attached.or(bank.as_ref());
    let first = existing.is_none();
    let transfer = parts.iter().try_fold(if first { raw_input_credits::NODE } else { 0 }, |total, (bytes,_)| {
        total.checked_add(*bytes).ok_or_else(oom)
    })?;
    let remaining = donor.reserved_bytes().checked_sub(transfer).ok_or_else(oom)?;
    let part_metadata = N.checked_mul(OriginalReadPart::metadata_bytes()).ok_or_else(oom)?;
    let group_metadata = if first { OriginalReadGroup::metadata_bytes() } else { 0 };
    let extra = part_metadata.checked_add(group_metadata).ok_or_else(oom)?;
    let addition = transfer.checked_sub(if first { raw_input_credits::NODE } else { 0 })
        .and_then(|payload| payload.checked_add(part_metadata)).ok_or_else(oom)?;
    // Existing donor pays the actual payload and one new ledger node. No
    // group/part allocation or observable transfer occurs before admission.
    admit_extra(ledger, extra)?;
    let group = existing.map(Arc::clone)
        .unwrap_or_else(|| Arc::new(OriginalReadGroup::new(&donor.domain)));
    ledger.partition_original_read_group(donor, remaining, &group, first, addition)?;
    if attached.is_none() {
        assert!(donor.read_group.set(Arc::clone(&group)).is_ok(), "one mutable read donor");
    }
    if let Some(slot) = slot.as_deref_mut() {
        if slot.is_none() {
            let owner: Arc<dyn SourceArenaCreditOwner> = group.clone();
            *slot = Some(SourceArenaCredit::from_resource_owner(owner).into_control());
        }
    }
    Ok(parts.map(|(bytes,role)| SourceArenaCredit::from_resource_owner(Arc::new(
        OriginalReadPart::new(Arc::clone(&group),bytes,role),
    ))))
}

fn split_owned_allocations<const N: usize>(
    ledger: &mut super::raw_input_credits::Ledger,
    donor: &Allocation,
    sizes: [usize; N],
    mut admit_extra: impl FnMut(&mut super::raw_input_credits::Ledger,
        &dyn Fn(&super::raw_input_credits::Ledger) -> io::Result<usize>) -> io::Result<usize>,
) -> io::Result<[AllocationHandle; N]> {
    if donor.origin_parent.is_some() || !ledger.has_source_arena(donor) { return Err(wrong()); }
    let bookkeeping = N.checked_mul(raw_input_credits::NODE).ok_or_else(oom)?;
    let transfer = sizes.iter().try_fold(bookkeeping, |total, bytes| {
        total.checked_add(*bytes).ok_or_else(oom)
    })?;
    let remaining = donor.reserved_bytes().checked_sub(transfer).ok_or_else(oom)?;
    let extra = N.checked_mul(Allocation::metadata_bytes()).ok_or_else(oom)?;
    admit_extra(ledger, &|_| Ok(extra))?;
    let children = sizes.map(|bytes| AllocationHandle::new(Arc::new(Allocation {
        bytes: AtomicUsize::new(bytes), domain: donor.domain.clone(), origin_parent:None, read_group:Default::default(),
    })));
    let children_refs=children.each_ref().map(AllocationHandle::arc);
    let peak=admit_extra(ledger,&|ledger|extra.checked_add(ledger.projected_partition_storage(children_refs)?)
        .ok_or_else(oom))?;
    ledger.partition_source_arena(donor,remaining,children_refs,peak.checked_sub(extra).ok_or_else(oom)?)?;
    Ok(children)
}

fn split_owned_text(
    ledger: &mut super::raw_input_credits::Ledger,
    donor: &Allocation,
    capacity: usize,
    slot: Option<&dm_preprocess::source_arena_credit::OriginalReadGroupSlot>,
    admit_extra: impl FnOnce(&mut super::raw_input_credits::Ledger, usize) -> io::Result<()>,
) -> io::Result<(SourceArenaCredit, dm_preprocess::source_arena_credit::SourceArenaControlCredit)> {
    let [payload, backing] = split_read_parts(ledger, donor, [
        (capacity, ReadPartRole::TextPayload),
        (SourceText::source_arena_control_bytes()?, ReadPartRole::TextControl),
    ], slot, admit_extra)?;
    Ok((payload, backing.into_control()))
}

fn oom()->io::Error{io::Error::new(io::ErrorKind::OutOfMemory,"native source arena exceeds existing shared input-family allowance")}
fn no_source_room(_requested:usize,_ledger_live:usize,_remaining:Option<usize>)->io::Error{
 #[cfg(debug_assertions)]
 if std::env::var_os("DMB_ORIGINAL_TRACE_STAGES").is_some(){
  eprintln!("ORIGINAL_SOURCE_INPUT_LIMIT requested={_requested} source_ledger_reserved={_ledger_live} shared_input_headroom={_remaining:?}");
 }
 oom()
}
fn wrong()->io::Error{io::Error::new(io::ErrorKind::InvalidInput,"source arena credit was not issued in this native input family")}
fn allocation<'a>(db:&QueryDb,credit:&'a SourceArenaCredit)->io::Result<&'a Allocation>{
 let actual=credit.owner().as_any().downcast_ref::<Allocation>().ok_or_else(wrong)?;
 if actual.is_retirable_path_fact() || !actual.same_domain(&Arc::downgrade(&db.raw_policy.admission)){return Err(wrong())}Ok(actual)
}
pub(super) fn funded_parts(text:&SourceText,domain:Option<&Weak<crate::query_db::raw_policy::Admission>>)->(bool,bool){
 let Some(expected)=domain else{return(false,false)};
 let funded=|credit:Option<&dyn SourceArenaCreditOwner>, role| credit.is_some_and(|credit| {
  credit.as_any().downcast_ref::<Allocation>().is_some_and(|actual|actual.same_domain(expected))
   || credit.as_any().downcast_ref::<OriginalReadPart>().is_some_and(|part|
     part.role()==role && part.group.same_domain(expected))
 });
 let control=funded(text.source_arena_control_credit().map(|credit|credit.owner()),ReadPartRole::TextControl);
 let payload=funded(text.source_arena_payload_credit().map(|credit|credit.owner()),ReadPartRole::TextPayload);
 (control,payload)
}
impl QueryDb{
 /// Convert ONE actual same-family read reservation into the actual acquired
 /// source backing observations, atomically under the existing family gate.
 /// No gate is held across caller IO/decode/driver work. This is resource
 /// accounting only: the lease still requires its actual source issuer proof.
 pub(crate) fn adopt_original_raw_read(&self,credit:&mut SourceArenaCredit,source:&dm_preprocess::SourceAcquisitionLease)->io::Result<()>{
  let actual=allocation(self,credit)?;
  let _gate=self.raw_policy.gate.lock().unwrap_or_else(|e|e.into_inner());
  let mut ledger=self.raw_policy.workspace.raw_sources.lock().unwrap_or_else(|e|e.into_inner());
  if actual.origin_parent.is_some() || !ledger.has_source_arena(actual){return Err(wrong())}
  let reserved=actual.reserved_bytes();
  // Commit must not poll: actual exceptional bytes may already have escaped
  // into RecordingInputs. On an unexpected quota failure the ledger still
  // records all payloads and the reservation remains unchanged until cleanup.
  let _actual_delta=ledger.adopt_original_read(source,reserved)?;
  ledger.resize_arena(actual,0)?;
  // At success new row delta <= old reservation; total family charge cannot
  // increase, so neither new headroom admission nor post-commit IO is needed.
  Ok(())
 }
 fn admit_source_arena(&self,ledger:&mut super::raw_input_credits::Ledger,need:usize)->io::Result<()>{
  self.admit_source_arena_projected(ledger,&|_|Ok(need)).map(|_|())
 }
 fn admit_source_arena_projected(&self,ledger:&mut super::raw_input_credits::Ledger,
  project:&dyn Fn(&super::raw_input_credits::Ledger)->io::Result<usize>)->io::Result<usize>{
  if self.raw_policy.admission.source_arena_needs_census.swap(false,Ordering::AcqRel){ledger.invalidate_upper();}
  let (mut live,was_cached)=ledger.admission_charge()?;
  let mut need=project(ledger)?;
  let mut available=self.workspace_input_base_headroom_locked(live);
  if was_cached && available.as_ref().map_or(true,|room|need>*room){
   live=ledger.refresh_after_pressure()?;
   need=project(ledger)?;
   available=self.workspace_input_base_headroom_locked(live);
  }
  if available.as_ref().map_or(true, |&room| need > room) {
   #[cfg(debug_assertions)]
   if std::env::var_os("DMB_ORIGINAL_TRACE_STAGES").is_some() {
    ledger.trace_exact_admission_categories(live);
   }
  }
  let available=available.map_err(|_|no_source_room(need,live,None))?;
  if need>available{return Err(no_source_room(need,live,Some(available)))}
  Ok(need)
 }
}
impl QueryDb {
 /// Resource-only coverage for each exact live text backing in this input
 /// family. This does not approve a source view or cover fingerprint memory.
 /// The callback must only walk immutable storage and must not reenter the
 /// source family. The admitted text or clone must outlive the accounting use.
 pub(crate) fn with_funded_policy_source_text<T>(
  &self,
  walk: impl FnOnce(&mut dyn FnMut(&SourceText) -> (bool, bool)) -> io::Result<T>,
 ) -> io::Result<T> {
  self.checkpoint()?;
  let _gate = self.raw_policy.gate.lock().unwrap_or_else(|e| e.into_inner());
  let ledger = self.raw_policy.workspace.raw_sources.lock().unwrap_or_else(|e| e.into_inner());
  let domain = Arc::downgrade(&self.raw_policy.admission);
  walk(&mut |text| {
   let credit_live = |credit: &dyn SourceArenaCreditOwner, role, bytes| {
    if credit.reserved_bytes() < bytes { return false; }
    if let Some(actual) = credit.as_any().downcast_ref::<Allocation>() {
     return actual.same_domain(&domain) && !actual.is_retirable_path_fact()
      && ledger.has_source_arena(actual);
    }
    credit.as_any().downcast_ref::<OriginalReadPart>().is_some_and(|part| {
     part.role() == role && part.group.same_domain(&domain) && ledger.has_read_group(&part.group)
    })
   };
   // These flags reproduce the ledger's subtraction rule. If a nominally
   // funded part has no live owner, the backing observation cannot cover it.
   let (nominal_control, nominal_payload) = funded_parts(text, Some(&domain));
   let mut result = (false, false);
   text.visit_storage(|address, size, storage| {
    let observed = ledger.has_sealed_text_backing(address);
    let control_size = size.saturating_add(2 * std::mem::size_of::<usize>());
    let control = (observed && !nominal_control)
     || text.source_arena_control_credit().is_some_and(|credit| {
      credit_live(credit.owner(), ReadPartRole::TextControl, control_size)
     });
    let payload = match storage {
     dm_preprocess::SourceTextStorage::Original(owner) => ledger.has_original_text_payload(owner),
     dm_preprocess::SourceTextStorage::Transformed(value) => (observed && !nominal_payload)
      || text.source_arena_payload_credit().is_some_and(|credit| {
       credit_live(credit.owner(), ReadPartRole::TextPayload, value.capacity())
      }),
     dm_preprocess::SourceTextStorage::Reserved { committed, .. } => (observed && !nominal_payload)
      || text.source_arena_payload_credit().is_some_and(|credit| {
       credit_live(credit.owner(), ReadPartRole::TextPayload, committed)
      }),
    };
    result = (control, payload);
   });
   result
  })
 }
}

impl QueryDb {
 /// Compute an accounting subtotal while the same source family is held.
 /// The callback is a storage walk only. No provider or query reentrancy.
 pub(crate) fn with_funded_origin_policy_pages<T>(&self, walk: impl FnOnce(&mut dyn FnMut(&dyn std::any::Any) -> bool) -> io::Result<T>) -> io::Result<T> {
  self.checkpoint()?;
  let _gate=self.raw_policy.gate.lock().unwrap_or_else(|e|e.into_inner());
  let ledger=self.raw_policy.workspace.raw_sources.lock().unwrap_or_else(|e|e.into_inner());
  let expected=self.body_charge.shared_reservation();
  walk(&mut |owner| {
   let Some(credit)=dm_preprocess::regions::physical_original_token_page_credit(owner) else{return false;};
   let Ok(actual)=allocation(self,credit) else{return false;};
   actual.origin_parent.as_ref().zip(expected).is_some_and(|(actual,expected)|Arc::ptr_eq(actual,expected))
       && ledger.has_source_arena(actual)
  })
 }

 fn reserve_source_arena(&self,bytes:usize,origin:bool)->io::Result<SourceArenaCredit>{
  self.checkpoint()?;let _gate=self.raw_policy.gate.lock().unwrap_or_else(|e|e.into_inner());
  let mut ledger=self.raw_policy.workspace.raw_sources.lock().unwrap_or_else(|e|e.into_inner());
  ledger.bind_source_arena(&self.raw_policy.admission)?;
  crate::daemon::control::checkpoint()?;
  let need=bytes.checked_add(Allocation::metadata_bytes()).ok_or_else(oom)?;
  self.admit_source_arena(&mut ledger,need)?;
  let parent=origin.then(||self.body_charge.shared_reservation().expect("production syntax parent"));
  let grant=parent.map(|parent|parent.provisional(bytes)).transpose().map_err(parent_denied)?;
  let actual=AllocationHandle::new(Arc::new(Allocation{
   bytes:AtomicUsize::new(bytes),domain:Arc::downgrade(&self.raw_policy.admission),
   origin_parent:parent.map(Arc::clone), read_group:Default::default(),
  }));
  // The concrete owner now refunds these bytes, even if registration refuses.
  if let Some(grant)=grant{grant.commit();}
  let peak=if ledger.projected_source_arena_storage(actual.arc())?==0{0}else{
   self.admit_source_arena_projected(&mut ledger,&|ledger|need.checked_add(
    ledger.projected_source_arena_storage(actual.arc())?).ok_or_else(oom))?
    .checked_sub(need).ok_or_else(oom)?
  };
  actual.register(&mut ledger,peak)
 }
}
impl SourceArenaWork for QueryDb{
 fn bank_original_path_fact(&self,credit:&mut SourceArenaCredit,slot:&std::sync::Mutex<Option<SourceArenaControlCredit>>)->io::Result<bool>{
  self.checkpoint()?;
  let actual=allocation(self,credit)?;
  if actual.origin_parent.is_some()||actual.read_group.get().is_some(){return Err(wrong());}
  // Only this recorder touches this slot. No code holding the family gate
  // enters it, including last-node cleanup.
  let mut bank=slot.lock().map_err(|_|wrong())?;
  let _gate=self.raw_policy.gate.lock().unwrap_or_else(|e|e.into_inner());
  let mut ledger=self.raw_policy.workspace.raw_sources.lock().unwrap_or_else(|e|e.into_inner());
  if !ledger.has_source_arena(actual){return Err(wrong());}
  let first=bank.is_none();
  let group=if let Some(bank)=bank.as_ref(){
   // Erased bank handles never expose an Arc. The ledger lends the exact
   // registered group from the same input family.
   let identity=bank.owner().as_any().downcast_ref::<OriginalReadGroup>().ok_or_else(wrong)?;
   ledger.loan_original_path_bank(identity)?
  }else{
   if self.raw_policy.admission.source_arena_needs_census.swap(false,Ordering::AcqRel){ledger.invalidate_upper();}
   let (mut live,cached)=ledger.admission_charge()?;
   let mut room=self.workspace_input_base_remaining_locked(live)?;
   let extra=OriginalReadGroup::metadata_bytes();
   if cached&&room.is_none_or(|room|room<extra){
    live=ledger.refresh_after_pressure()?;
    room=self.workspace_input_base_remaining_locked(live)?;
   }
   if room.is_none_or(|room|room<extra){return Ok(false);}
   Arc::new(OriginalReadGroup::new(&actual.domain))
  };
  ledger.transfer_original_path_bank(actual,&group,first)?;
  assert!(actual.read_group.set(Arc::clone(&group)).is_ok(),"one settled path grant");
  let prior=actual.bytes.fetch_or(RETIRABLE_PATH_FACTS,Ordering::AcqRel);
  debug_assert_eq!(prior&RETIRABLE_PATH_FACTS,0);
  if first{*bank=Some(SourceArenaCredit::from_resource_owner(group).into_control());}
  Ok(true)
 }
 fn reserve_original_origin_storage(&self,bytes:usize)->io::Result<SourceArenaCredit>{self.reserve_source_arena(bytes,true)}

 fn split_original_acquisition_controls(&self, donor: &mut SourceArenaCredit, sizes: [usize; 2], slot: Option<&dm_preprocess::source_arena_credit::OriginalReadGroupSlot>)
     -> io::Result<Option<(dm_preprocess::source_arena_credit::SourceArenaControlCredit,
                          dm_preprocess::source_arena_credit::SourceArenaControlCredit)>> {
     self.checkpoint()?;
     let actual = allocation(self, donor)?;
     let _gate = self.raw_policy.gate.lock().unwrap_or_else(|e| e.into_inner());
     let mut ledger = self.raw_policy.workspace.raw_sources.lock().unwrap_or_else(|e| e.into_inner());
     let [binding, original] = split_read_parts(&mut ledger, actual, sizes.map(|bytes|(bytes,ReadPartRole::Acquisition)), slot,
         |ledger, extra| self.admit_source_arena(ledger, extra))?;
     Ok(Some((binding.into_control(), original.into_control())))
 }

 fn split_original_receipt(&self, donor: &mut SourceArenaCredit, receipt: &(dyn std::any::Any + Send + Sync), slot: Option<&dm_preprocess::source_arena_credit::OriginalReadGroupSlot>)
     -> io::Result<Option<dm_preprocess::source_arena_credit::SourceArenaControlCredit>> {
     self.checkpoint()?;
     let actual = allocation(self, donor)?;
     let _gate = self.raw_policy.gate.lock().unwrap_or_else(|e| e.into_inner());
     let mut ledger = self.raw_policy.workspace.raw_sources.lock().unwrap_or_else(|e| e.into_inner());
     let bytes = crate::input_snapshot::exact_open_receipt_charge(receipt)?;
     let [receipt] = split_read_parts(&mut ledger, actual, [(bytes,ReadPartRole::Acquisition)], slot,
         |ledger, extra| self.admit_source_arena(ledger, extra))?;
     Ok(Some(receipt.into_control()))
 }

 fn split_original_exceptional_bytes(&self, donor: &mut SourceArenaCredit, capacity: usize, control: usize)
     -> io::Result<Option<(SourceArenaCredit, dm_preprocess::source_arena_credit::SourceArenaControlCredit)>> {
     self.checkpoint()?;
     let actual = allocation(self, donor)?;
     let _gate = self.raw_policy.gate.lock().unwrap_or_else(|e| e.into_inner());
     let mut ledger = self.raw_policy.workspace.raw_sources.lock().unwrap_or_else(|e| e.into_inner());
     if control != dm_resources::SharedBytes::owner_allocation_bytes() {
         return Err(wrong());
     }
     let [payload, control] = split_owned_allocations(&mut ledger, actual, [capacity, control],
         |ledger, project| self.admit_source_arena_projected(ledger, project))?;
     Ok(Some((payload.into_credit(), control.into_credit().into_control())))
 }

 fn split_original_text(&self, donor: &mut SourceArenaCredit, capacity: usize, slot: Option<&dm_preprocess::source_arena_credit::OriginalReadGroupSlot>)
     -> io::Result<Option<(SourceArenaCredit, dm_preprocess::source_arena_credit::SourceArenaControlCredit)>> {
     self.checkpoint()?;
     let actual = allocation(self, donor)?;
     let _gate = self.raw_policy.gate.lock().unwrap_or_else(|e| e.into_inner());
     let mut ledger = self.raw_policy.workspace.raw_sources.lock().unwrap_or_else(|e| e.into_inner());
     split_owned_text(&mut ledger, actual, capacity, slot,
         |ledger, extra| self.admit_source_arena(ledger, extra)).map(Some)
 }

 fn transformed_source_address_limit(&self)->Option<usize>{
  cfg!(all(target_pointer_width="64",any(windows,unix))).then_some(super::raw_policy::INPUT_BUDGET)
 }
 fn original_read_bookkeeping_bytes(&self)->io::Result<usize>{6usize.checked_mul(raw_input_credits::NODE).ok_or_else(oom)}
 fn adopt_original_read(&self,credit:&mut SourceArenaCredit,source:&dm_preprocess::SourceAcquisitionLease)->io::Result<()>{self.adopt_original_raw_read(credit,source)}
 fn checkpoint(&self)->io::Result<()>{crate::daemon::control::checkpoint()}
 fn reserve(&self,bytes:usize)->io::Result<SourceArenaCredit>{self.reserve_source_arena(bytes,false)}
 fn grow(&self,credit:&mut SourceArenaCredit,extra:usize)->io::Result<()>{
  self.checkpoint()?;let actual=allocation(self,credit)?;
  let _gate=self.raw_policy.gate.lock().unwrap_or_else(|e|e.into_inner());let mut ledger=self.raw_policy.workspace.raw_sources.lock().unwrap_or_else(|e|e.into_inner());
  if !ledger.has_source_arena(actual){return Err(wrong())}if extra==0{return Ok(())}
  crate::daemon::control::checkpoint()?;
  let next=actual.reserved_bytes().checked_add(extra).ok_or_else(oom)?;
  self.admit_source_arena(&mut ledger,extra)?;
  let grant=actual.origin_parent.as_ref().map(|parent|parent.provisional(extra)).transpose().map_err(parent_denied)?;
  ledger.resize_arena(actual,next)?;
  if let Some(grant)=grant{grant.commit();}
  Ok(())
 }
 fn try_grow_original_origin_storage(&self, credit:&mut SourceArenaCredit, extra:usize)->io::Result<bool>{
  self.checkpoint()?;
  let actual=allocation(self,credit)?;
  let parent=actual.origin_parent.as_ref().ok_or_else(wrong)?;
  let _gate=self.raw_policy.gate.lock().unwrap_or_else(|e|e.into_inner());
  let mut ledger=self.raw_policy.workspace.raw_sources.lock().unwrap_or_else(|e|e.into_inner());
  if !ledger.has_source_arena(actual){return Err(wrong());}
  if self.raw_policy.admission.source_arena_needs_census.swap(false,Ordering::AcqRel){ledger.invalidate_upper();}
  let (mut live,cached)=ledger.admission_charge()?;
  let mut room=self.workspace_input_base_remaining_locked(live)?;
  if cached&&room.is_none_or(|room|extra>room){
   live=ledger.refresh_after_pressure()?;
   room=self.workspace_input_base_remaining_locked(live)?;
  }
  if room.is_none_or(|room|extra>room){return Ok(false);}
  let next=actual.reserved_bytes().checked_add(extra).ok_or_else(oom)?;
  let Ok(grant)=parent.provisional(extra) else{return Ok(false);};
  ledger.resize_arena(actual,next)?;
  grant.commit();
  Ok(true)
 }
 fn shrink(&self,credit:&mut SourceArenaCredit,bytes:usize)->io::Result<()>{
  // Releasing known freed storage never polls a new cancellation/error over the
  // first allocation failure. It still verifies the SAME private issuer/row.
  let actual=allocation(self,credit)?;let _gate=self.raw_policy.gate.lock().unwrap_or_else(|e|e.into_inner());let mut ledger=self.raw_policy.workspace.raw_sources.lock().unwrap_or_else(|e|e.into_inner());
  let next=actual.reserved_bytes().checked_sub(bytes).ok_or_else(wrong)?;
  ledger.resize_arena(actual,next)?;
  if let Some(parent)=&actual.origin_parent{parent.release(bytes);}
  Ok(())
 }
}

#[cfg(test)]mod actual_native_arena_resource_tests{
 use super::*;
 fn live(db:&QueryDb)->usize{db.raw_source_input_charge_locked().unwrap()}
 #[test]fn actual_existing_input_family_rejects_foreign_growth_and_denial_preserves_credit(){
  let own=QueryDb::default();let other=QueryDb::default();let baseline=live(&own);let mut credit=SourceArenaWork::reserve(&own,32).unwrap();let held=live(&own);
  assert!(held>=baseline+32);assert_eq!(SourceArenaWork::grow(&other,&mut credit,1).unwrap_err().kind(),io::ErrorKind::InvalidInput);assert_eq!(SourceArenaWork::shrink(&other,&mut credit,1).unwrap_err().kind(),io::ErrorKind::InvalidInput);assert_eq!(live(&own),held);
  SourceArenaWork::grow(&own,&mut credit,7).unwrap();assert_eq!(credit.reserved_bytes(),39);assert_eq!(live(&own),held+7);
  assert_eq!(SourceArenaWork::grow(&own,&mut credit,usize::MAX).unwrap_err().kind(),io::ErrorKind::OutOfMemory);assert_eq!(credit.reserved_bytes(),39);assert_eq!(live(&own),held+7);
  SourceArenaWork::shrink(&own,&mut credit,7).unwrap();assert_eq!(live(&own),held);drop(credit);assert_eq!(live(&own),baseline);
  assert_eq!(SourceArenaWork::reserve(&own,256*1024*1024).err().unwrap().kind(),io::ErrorKind::OutOfMemory);assert_eq!(live(&own),baseline,"denial did not publish a partial reservation or raise the actual family cap");
 }
 fn arena_table_bytes(db:&QueryDb)->usize{
  db.raw_policy.workspace.raw_sources.lock().unwrap().source_arena_storage()
 }
 #[test]fn actual_source_text_payload_and_last_weak_control_are_counted_by_same_native_family(){
  let db=QueryDb::default();let baseline=live(&db);let text=String::from("native arena owner");let pointer=text.as_ptr();let capacity=text.capacity();let metadata=SourceText::source_arena_control_bytes().unwrap();let payload=SourceArenaWork::reserve(&db,capacity).unwrap();let control=SourceArenaWork::reserve(&db,metadata).unwrap().into_control();
  let source=SourceText::from_source_arena(text,payload,control).unwrap();assert_eq!(source.as_str().as_ptr(),pointer);let view=source.checked_view(1..source.len()).unwrap();let weak=source.downgrade();let full=live(&db);drop(source);assert_eq!(live(&db),full);drop(view);assert!(weak.upgrade().is_none());
  assert_eq!(live(&db),baseline+arena_table_bytes(&db)+Allocation::metadata_bytes()+metadata,"physical String reservation ended, real weak-control reservation survived");drop(weak);assert_eq!(live(&db),baseline);
 }
 #[test]fn escaped_source_and_weak_alias_do_not_keep_the_query_db_or_source_payload_alive(){let db=Arc::new(QueryDb::default());let db_weak=Arc::downgrade(&db);let text=String::from("escaped actual arena");let capacity=text.capacity();let source=SourceText::from_source_arena(text,SourceArenaWork::reserve(db.as_ref(),capacity).unwrap(),SourceArenaWork::reserve(db.as_ref(),SourceText::source_arena_control_bytes().unwrap()).unwrap().into_control()).unwrap();let weak=source.downgrade();drop(db);assert!(db_weak.upgrade().is_none(),"resource credit must not retain QueryDb/ledger/model");assert_eq!(source.as_str(),"escaped actual arena");drop(source);assert!(weak.upgrade().is_none());let mut controls=0;weak.visit_derived_resource_storage(|_,bytes|controls+=bytes);assert!(controls>0,"last weak still owns its actual fixed resource metadata, without source content");drop(weak);}
}

#[cfg(test)]mod actual_original_raw_read_adoption_tests{
 use super::*;use crate::input_snapshot::{RecordingInputs,FileSystemInputs};
 fn live(db:&QueryDb)->usize{db.raw_source_input_charge_locked().unwrap()}

 #[test]
 fn actual_shared_family_holds_only_settled_fact_grants_across_real_snapshot_aliases() {
  let db=QueryDb::default();
  let baseline=live(&db);
  let root=crate::test_scratch::dir("native-original-avl-settled-family");
  let inputs=RecordingInputs::new(FileSystemInputs,0)
   .with_initial_environment(dm_preprocess::InitialEnvironment::OriginalChecker0290);
  let mut prefix=None;
  for index in 0..24 {
   let path=root.join(format!("actual-{index:02}.dm"));
   std::fs::write(&path,b"/datum/probe\n").unwrap();
   let result=dm_preprocess::source_arena_credit::read_original_source_open_using(
    &inputs,&path,1024,&db,&mut || Ok(dm_preprocess::OriginalRawOpenDecision::Read),
   ).unwrap();
   let dm_preprocess::OriginalRawReadOutcome::Acquired(source)=result else { panic!("actual acquired file") };
   drop(source);
   let snapshot=inputs.snapshot().unwrap();
   if index==0 {
    let mut storage=std::collections::BTreeMap::new();
    snapshot.visit_original_open_storage(|address,_,capacity| { storage.insert(address,capacity); });
    assert_eq!(live(&db)-baseline,storage.values().sum::<usize>()+2*raw_input_credits::NODE,
     "one open and one payload fact own exact key/node buffers and a real ledger row per grant");
   }
   if index==7 { prefix=Some((snapshot,live(&db))); }
  }
  let (prefix,prefix_charge)=prefix.unwrap();
  assert!(live(&db)>prefix_charge);
  drop(inputs);
  assert_eq!(live(&db),prefix_charge,"later disjoint fact grants die with the final snapshot");
  assert!(prefix.restat(&FileSystemInputs).unwrap().unchanged());
  drop(prefix);
  assert_eq!(live(&db),baseline);
 }

 #[test]fn actual_bom_bytes_remain_weakly_funded_after_frame_failure_and_drop_only_with_recording_inputs(){
  let db=QueryDb::default();let baseline=live(&db);let root=crate::test_scratch::dir("native-raw-read-adoption-bom");let path=root.join("original.dm");let raw=b"\xef\xbb\xbfactual original\x80";std::fs::write(&path,raw).unwrap();let inputs=RecordingInputs::new(FileSystemInputs,0).with_initial_environment(dm_preprocess::InitialEnvironment::OriginalChecker0290);
  let lease=dm_preprocess::source_arena_credit::read_original_source_using(&inputs,&path,1024,&db).unwrap().unwrap();let full=live(&db);assert!(full>baseline+raw.len());drop(lease);let exceptional_only=live(&db);assert!(exceptional_only<full);assert!(exceptional_only>=baseline+raw.len(),"actual RecordingInputs still retains exceptional SharedBytes after frame/result failure");drop(inputs);assert_eq!(live(&db),baseline);
 }
 #[test]fn actual_foreign_domain_denial_keeps_credit_and_same_db_atomic_adoption_recovers(){
  let db=QueryDb::default();let other=QueryDb::default();let baseline=live(&db);let root=crate::test_scratch::dir("native-raw-read-adoption-foreign");let path=root.join("actual.dm");std::fs::write(&path,b"/datum/probe\n").unwrap();let inputs=RecordingInputs::new(FileSystemInputs,0).with_initial_environment(dm_preprocess::InitialEnvironment::OriginalChecker0290);let mut temporary=SourceArenaWork::reserve(&db,16*1024).unwrap();let lease=inputs.read_raw_source(&path,1024,None,|_,_,_|Ok(())).unwrap().unwrap();assert_eq!(other.adopt_original_raw_read(&mut temporary,&lease).unwrap_err().kind(),io::ErrorKind::InvalidInput);assert_eq!(temporary.reserved_bytes(),16*1024);db.adopt_original_raw_read(&mut temporary,&lease).unwrap();assert_eq!(temporary.reserved_bytes(),0);drop(temporary);assert!(live(&db)>baseline);drop(lease);drop(inputs);assert_eq!(live(&db),baseline);
 }
 #[test]fn actual_surprise_payload_denial_still_records_exceptional_original_and_preserves_temporary_credit(){
  let db=QueryDb::default();let baseline=live(&db);let root=crate::test_scratch::dir("native-raw-read-adoption-underfunded");let path=root.join("actual.dm");let mut bytes=vec![0xef,0xbb,0xbf];bytes.extend(std::iter::repeat(b'x').take(8192));std::fs::write(&path,&bytes).unwrap();let inputs=RecordingInputs::new(FileSystemInputs,0).with_initial_environment(dm_preprocess::InitialEnvironment::OriginalChecker0290);let mut temporary=SourceArenaWork::reserve(&db,6*raw_input_credits::NODE).unwrap();let lease=inputs.read_raw_source(&path,16*1024,None,|_,_,_|Ok(())).unwrap().unwrap();assert_eq!(db.adopt_original_raw_read(&mut temporary,&lease).unwrap_err().kind(),io::ErrorKind::OutOfMemory);assert_eq!(temporary.reserved_bytes(),6*raw_input_credits::NODE);drop(temporary);drop(lease);assert!(live(&db)>=baseline+bytes.len(),"denial cannot refund actual escaped exceptional backing");drop(inputs);assert_eq!(live(&db),baseline);
 }
}

#[cfg(test)]mod actual_original_constructor_resource_tests{
 use super::*;use crate::input_snapshot::{RecordingInputs,FileSystemInputs};
 #[test]fn actual_reissued_bindings_dedup_shared_original_but_keep_distinct_receipt_and_path_lifetimes(){
  let db=QueryDb::default();let baseline=db.raw_source_input_charge_locked().unwrap();let root=crate::test_scratch::dir("native-raw-reissue-metadata");let path=root.join("actual.dm");std::fs::write(&path,b"/datum/original\n").unwrap();let first=RecordingInputs::new(FileSystemInputs,0).with_initial_environment(dm_preprocess::InitialEnvironment::OriginalChecker0290);let lease=dm_preprocess::source_arena_credit::read_original_source_using(&first,&path,1024,&db).unwrap().unwrap();let first_charge=db.raw_source_input_charge_locked().unwrap();
  let second=RecordingInputs::new(FileSystemInputs,0).with_initial_environment(dm_preprocess::InitialEnvironment::OriginalChecker0290);let reissued=second.read_raw_source(&path,1024,Some(&lease),|_,_,new|{assert!(!new);Ok(())}).unwrap().unwrap();assert!(reissued.same_original_acquisition(&lease));let mut credit=SourceArenaWork::reserve(&db,16*1024).unwrap();db.adopt_original_raw_read(&mut credit,&reissued).unwrap();drop(credit);let both=db.raw_source_input_charge_locked().unwrap();assert!(both>first_charge);drop(lease);drop(first);let only_reissued=db.raw_source_input_charge_locked().unwrap();assert!(only_reissued<both);assert!(only_reissued>baseline);drop(reissued);drop(second);assert_eq!(db.raw_source_input_charge_locked().unwrap(),baseline);
 }
}

/// A resource-only synchronous loan from the ACTUAL held family gate/ledger.
/// The Mutex coordinates this borrowed ledger; it is not a new budget/counter.
struct HeldSourceState<'a>{ledger:&'a mut super::raw_input_credits::Ledger,domain:&'a Arc<crate::query_db::raw_policy::Admission>,budget:&'a dq_analyze::captured_generator_budget::Budget}
struct HeldSourceWork<'a>{state:std::sync::Mutex<HeldSourceState<'a>>}
impl<'a> HeldSourceWork<'a>{
 fn lock<'s>(&'s self)->io::Result<std::sync::MutexGuard<'s,HeldSourceState<'a>>>{self.state.lock().map_err(|_|io::Error::new(io::ErrorKind::InvalidData,"held source resource loan poisoned"))}
 fn actual<'credit>(state:&HeldSourceState<'_>,credit:&'credit SourceArenaCredit)->io::Result<&'credit Allocation>{let actual=credit.owner().as_any().downcast_ref::<Allocation>().ok_or_else(wrong)?;if actual.origin_parent.is_some() || actual.is_retirable_path_fact() || !actual.same_domain(&Arc::downgrade(state.domain))||!state.ledger.has_source_arena(actual){return Err(wrong())}Ok(actual)}
}
impl SourceArenaWork for HeldSourceWork<'_>{
 fn split_original_acquisition_controls(&self, donor: &mut SourceArenaCredit, sizes: [usize; 2], slot: Option<&dm_preprocess::source_arena_credit::OriginalReadGroupSlot>)
     -> io::Result<Option<(dm_preprocess::source_arena_credit::SourceArenaControlCredit,
                          dm_preprocess::source_arena_credit::SourceArenaControlCredit)>> {
     self.checkpoint()?;
     let mut state = self.lock()?;
     let actual = Self::actual(&state, donor)?;
     let budget = state.budget;
     let [binding, original] = split_read_parts(&mut *state.ledger, actual, sizes.map(|bytes|(bytes,ReadPartRole::Acquisition)), slot,
         |_, extra| budget.charge(extra).map_err(|_| oom()))?;
     Ok(Some((binding.into_control(), original.into_control())))
 }

 fn split_original_receipt(&self, donor: &mut SourceArenaCredit, receipt: &(dyn std::any::Any + Send + Sync), slot: Option<&dm_preprocess::source_arena_credit::OriginalReadGroupSlot>)
     -> io::Result<Option<dm_preprocess::source_arena_credit::SourceArenaControlCredit>> {
     self.checkpoint()?;
     let mut state = self.lock()?;
     let actual = Self::actual(&state, donor)?;
     let budget = state.budget;
     let bytes = crate::input_snapshot::exact_open_receipt_charge(receipt)?;
     let [receipt] = split_read_parts(&mut *state.ledger, actual, [(bytes,ReadPartRole::Acquisition)], slot,
         |_, extra| budget.charge(extra).map_err(|_| oom()))?;
     Ok(Some(receipt.into_control()))
 }

 fn split_original_exceptional_bytes(&self, donor: &mut SourceArenaCredit, capacity: usize, control: usize)
     -> io::Result<Option<(SourceArenaCredit, dm_preprocess::source_arena_credit::SourceArenaControlCredit)>> {
     self.checkpoint()?;
     let mut state = self.lock()?;
     let actual = Self::actual(&state, donor)?;
     let budget = state.budget;
     if control != dm_resources::SharedBytes::owner_allocation_bytes() {
         return Err(wrong());
     }
     let mut previous=0usize;
     let [payload, control] = split_owned_allocations(&mut *state.ledger, actual, [capacity, control],
         |ledger, project| {
             let peak=project(ledger)?;
             budget.charge(peak.checked_sub(previous).ok_or_else(oom)?).map_err(|_|oom())?;
             previous=peak;
             Ok(peak)
         })?;
     Ok(Some((payload.into_credit(), control.into_credit().into_control())))
 }

 fn split_original_text(&self, donor: &mut SourceArenaCredit, capacity: usize, slot: Option<&dm_preprocess::source_arena_credit::OriginalReadGroupSlot>)
     -> io::Result<Option<(SourceArenaCredit, dm_preprocess::source_arena_credit::SourceArenaControlCredit)>> {
     self.checkpoint()?;
     let mut state = self.lock()?;
     let actual = Self::actual(&state, donor)?;
     let budget = state.budget;
     split_owned_text(&mut *state.ledger, actual, capacity, slot,
         |_, extra| budget.charge(extra).map_err(|_| oom())).map(Some)
 }

 fn original_read_bookkeeping_bytes(&self)->io::Result<usize>{6usize.checked_mul(raw_input_credits::NODE).ok_or_else(oom)}
 fn checkpoint(&self)->io::Result<()>{let state=self.lock()?;if state.budget.denied(){return Err(oom())}drop(state);crate::daemon::control::checkpoint()}
 fn reserve(&self,bytes:usize)->io::Result<SourceArenaCredit>{
  self.checkpoint()?;let mut state=self.lock()?;
  let needed=bytes.checked_add(Allocation::metadata_bytes()).ok_or_else(||{state.budget.deny();oom()})?;
  state.budget.charge(needed).map_err(|_|oom())?;
  let actual=AllocationHandle::new(Arc::new(Allocation{bytes:AtomicUsize::new(bytes),
   domain:Arc::downgrade(state.domain),origin_parent:None,read_group:Default::default()}));
  let peak=state.ledger.projected_source_arena_storage(actual.arc())?;
  state.budget.charge(peak).map_err(|_|oom())?;
  actual.register(state.ledger,peak)
 }
 fn grow(&self,credit:&mut SourceArenaCredit,extra:usize)->io::Result<()>{self.checkpoint()?;let mut state=self.lock()?;let actual=Self::actual(&state,credit)?;let next=charge_allocation_growth(actual,state.budget,extra)?;state.ledger.resize_arena(actual,next)}
 fn shrink(&self,credit:&mut SourceArenaCredit,bytes:usize)->io::Result<()>{let mut state=self.lock()?;let actual=Self::actual(&state,credit)?;let next=actual.reserved_bytes().checked_sub(bytes).ok_or_else(wrong)?;state.ledger.resize_arena(actual,next)}
 fn adopt_original_read(&self,credit:&mut SourceArenaCredit,source:&dm_preprocess::SourceAcquisitionLease)->io::Result<()>{let mut state=self.lock()?;let actual=Self::actual(&state,credit)?;let reserved=actual.reserved_bytes();state.ledger.adopt_original_read(source,reserved)?;state.ledger.resize_arena(actual,0)}
}
/// Only RawInputCredits can lend its own actual mutable ledger and operation
/// budget. Bind verifies the existing native domain before any provider IO.
pub(super) fn with_held_source_work<R>(db:&QueryDb,ledger:&mut super::raw_input_credits::Ledger,budget:&dq_analyze::captured_generator_budget::Budget,consume:impl FnOnce(&dyn SourceArenaWork)->io::Result<R>)->io::Result<R>{ledger.bind_source_arena(&db.raw_policy.admission)?;let work=HeldSourceWork{state:std::sync::Mutex::new(HeldSourceState{ledger,domain:&db.raw_policy.admission,budget})};consume(&work)}

/// Resource-only loan issued INSIDE the genuine report's already-held family
/// gate. No reserve/grow call reenters that gate and no new counter is minted.
struct ReportOutputWork<'a>{allocation:&'a Allocation,budget:&'a dq_analyze::captured_generator_budget::Budget}
impl dq_analyze::policy_finish::admitted::Work for ReportOutputWork<'_>{
 fn checkpoint(&self)->io::Result<()>{if self.budget.denied(){return Err(oom())}crate::daemon::control::checkpoint()}
 fn reserve(&self,bytes:usize)->io::Result<()>{self.checkpoint()?;let next=charge_allocation_growth(self.allocation,self.budget,bytes)?;self.allocation.store_reserved_bytes(next);Ok(())}
 fn overflow(&self)->io::Error{self.budget.deny();oom()}
}
impl QueryDb{
 /// Called only from the actual current/failed report callback while that
 /// producer holds raw_policy.gate. The private native allocation downcast and
 /// SAME admission identity reject unrelated/custom/foreign resource owners.
 pub(crate) fn with_report_output_work_locked<R>(&self,credit:&dm_preprocess::source_arena_credit::SourceArenaControlCredit,budget:&dq_analyze::captured_generator_budget::Budget,consume:impl FnOnce(&dyn dq_analyze::policy_finish::admitted::Work)->io::Result<R>)->io::Result<R>{
  let actual=credit.owner().as_any().downcast_ref::<Allocation>().ok_or_else(wrong)?;if !actual.same_domain(&Arc::downgrade(&self.raw_policy.admission)){return Err(wrong())}
  self.raw_policy.admission.source_arena_needs_census.store(true,Ordering::Release);
  let work=ReportOutputWork{allocation:actual,budget};let value=consume(&work);match value{Err(first)=>Err(first),Ok(value)=>{dq_analyze::policy_finish::admitted::Work::checkpoint(&work)?;Ok(value)}}
 }
}

impl QueryDb{pub(crate) fn source_input_admission_bytes(&self)->io::Result<usize>{let _gate=self.raw_policy.gate.try_lock().map_err(|_|io::Error::new(io::ErrorKind::WouldBlock,"input family is already borrowed"))?;self.raw_source_input_charge_locked()}}

fn charge_allocation_growth(actual:&Allocation,budget:&dq_analyze::captured_generator_budget::Budget,extra:usize)->io::Result<usize>{let next=actual.reserved_bytes().checked_add(extra).ok_or_else(||{budget.deny();oom()})?;budget.charge(extra).map_err(|_|oom())?;Ok(next)}

#[cfg(test)]
mod owned_text_partition_tests {
    use super::*;

    #[test]
    fn typed_arena_partition_funds_actual_overlap_before_changing_donor() {
        let db = QueryDb::default();
        let donor = SourceArenaWork::reserve(&db, 4096).unwrap();
        let other: Vec<_> = (1..32).map(|_| SourceArenaWork::reserve(&db, 1).unwrap()).collect();
        let owner = allocation(&db, &donor).unwrap();
        let _gate = db.raw_policy.gate.lock().unwrap();
        let mut ledger = db.raw_policy.workspace.raw_sources.lock().unwrap();
        let before = ledger.refresh().unwrap();
        let old_storage = ledger.source_arena_storage();
        let child_metadata = 2 * Allocation::metadata_bytes();
        let mut expected_peak = None;
        let denied = split_owned_allocations(&mut ledger, owner, [128, 64], |ledger, projection| {
            let bytes = projection(ledger)?;
            assert_eq!(ledger.source_arena_storage(), old_storage);
            assert_eq!(owner.reserved_bytes(), 4096);
            if bytes == child_metadata { return Ok(bytes); }
            assert!(bytes > child_metadata);
            expected_peak = Some(bytes);
            Err(io::Error::from_raw_os_error(1450))
        });
        assert_eq!(denied.err().unwrap().raw_os_error(), Some(1450));
        assert_eq!(ledger.refresh().unwrap(), before);
        assert_eq!(ledger.source_arena_storage(), old_storage);
        assert_eq!(owner.reserved_bytes(), 4096);
        let children = split_owned_allocations(&mut ledger, owner, [128, 64], |ledger, projection| {
            let bytes = projection(ledger)?;
            assert_eq!(ledger.source_arena_storage(), old_storage);
            assert_eq!(owner.reserved_bytes(), 4096);
            assert!(bytes == child_metadata || Some(bytes) == expected_peak);
            Ok(bytes)
        }).unwrap();
        for child in &children { assert!(ledger.has_source_arena(child.arc())); }
        let added = ledger.source_arena_storage() - old_storage;
        assert_eq!(Some(added + child_metadata), expected_peak);
        assert_eq!(owner.reserved_bytes(), 4096 - 128 - 64 - 2 * raw_input_credits::NODE);
        assert_eq!(ledger.refresh().unwrap(), before + added + child_metadata - 2 * raw_input_credits::NODE);
        drop(children);
        assert!(ledger.refresh().unwrap() < before + added + child_metadata);
        drop(ledger);
        drop(_gate);
        drop((other, donor));
    }

    #[test]
    fn partition_moves_donor_funding_and_rejects_insufficient_or_foreign_grants() {
        let db = QueryDb::default();
        let foreign = QueryDb::default();
        let capacity = 127;
        let control = SourceText::source_arena_control_bytes().unwrap();
        let transferred = capacity + control + raw_input_credits::NODE;
        let remaining = 4 * raw_input_credits::NODE + 512;
        let mut donor = SourceArenaWork::reserve(&db, transferred + remaining).unwrap();
        let before = db.source_input_admission_bytes().unwrap();
        let wrong = SourceArenaWork::split_original_text(&foreign, &mut donor, capacity, None).err().unwrap();
        assert_eq!(wrong.kind(), io::ErrorKind::InvalidInput);
        let short = SourceArenaWork::split_original_text(&db, &mut donor, transferred + remaining, None).err().unwrap();
        assert_eq!(short.kind(), io::ErrorKind::OutOfMemory);
        assert_eq!(donor.reserved_bytes(), transferred + remaining);
        assert_eq!(db.source_input_admission_bytes().unwrap(), before);

        let (payload, backing) = SourceArenaWork::split_original_text(&db, &mut donor, capacity, None).unwrap().unwrap();
        assert_eq!(donor.reserved_bytes(), remaining);
        assert_eq!(payload.reserved_bytes(), capacity);
        assert_eq!(backing.reserved_bytes(), control);
        assert_eq!(db.source_input_admission_bytes().unwrap(), before + OriginalReadGroup::metadata_bytes() + 2 * OriginalReadPart::metadata_bytes());
        drop(payload);
        drop(backing);
        let held = db.source_input_admission_bytes().unwrap();
        assert_eq!(held, before - capacity - control + OriginalReadGroup::metadata_bytes());
    }
}

#[cfg(test)]
mod receipt_transfer_tests {
    use super::*;
    use crate::input_snapshot::{FileSystemInputs, RecordingInputs};
    use dm_preprocess::{InitialEnvironment, OriginalRawOpenDecision, OriginalRawReadOutcome};
    use dm_preprocess::source_acquisition::AcquisitionStorage;
    use dm_preprocess::source_arena_credit::read_original_source_open_using;

    #[test]
    fn actual_opened_reads_share_only_one_recorder_group_with_independent_lifetimes() {
        let db = QueryDb::default();
        let baseline = db.source_input_admission_bytes().unwrap();
        let root = crate::test_scratch::dir("native-read-group-recorder");
        let first = root.join("first.dm");
        let second = root.join("second.dm");
        std::fs::write(&first, b"/datum/first").unwrap();
        std::fs::write(&second, b"/datum/second").unwrap();
        let recorder = || RecordingInputs::new(FileSystemInputs, 0)
            .with_initial_environment(InitialEnvironment::OriginalChecker0290);
        let read = |inputs: &RecordingInputs<FileSystemInputs>, path: &std::path::Path| {
            let OriginalRawReadOutcome::Acquired(lease) = read_original_source_open_using(
                inputs, path, 1024, &db, &mut || Ok(OriginalRawOpenDecision::Read),
            ).unwrap() else { panic!("actual exact read") };
            lease
        };
        let group = |lease: &dm_preprocess::SourceAcquisitionLease| {
            let mut result = None;
            lease.visit_weak_resource_objects(|weak| {
                if let Some(credit) = weak.receipt_control_credit() {
                    let part = credit.owner().as_any().downcast_ref::<OriginalReadPart>().unwrap();
                    result = Some(Arc::as_ptr(part.group()));
                }
            });
            result.unwrap()
        };
        let inputs = recorder();
        let other = recorder();
        let one = read(&inputs, &first);
        let two = read(&inputs, &second);
        let isolated = read(&other, &first);
        assert_eq!(group(&one), group(&two));
        assert_ne!(group(&one), group(&isolated));
        let before = db.source_input_admission_bytes().unwrap();
        let escaped = two.source_text().clone();
        drop(one);
        assert!(db.source_input_admission_bytes().unwrap() < before);
        drop(two);
        drop(isolated);
        drop(other);
        drop(inputs);
        assert!(db.source_input_admission_bytes().unwrap() > baseline);
        assert_eq!(escaped.as_str(), "/datum/second");
        drop(escaped);
        assert_eq!(db.source_input_admission_bytes().unwrap(), baseline);
    }

    #[test]
    fn recorder_read_group_slot_rejects_foreign_ledger_without_donor_mutation() {
        let db = QueryDb::default();
        let foreign = QueryDb::default();
        let slot = dm_preprocess::source_arena_credit::OriginalReadGroupSlot::default();
        let mut one = SourceArenaWork::reserve(&db, 4096).unwrap();
        let mut two = SourceArenaWork::reserve(&foreign, 4096).unwrap();
        let parts = SourceArenaWork::split_original_text(&db, &mut one, 32, Some(&slot)).unwrap().unwrap();
        let before = foreign.source_input_admission_bytes().unwrap();
        let error = SourceArenaWork::split_original_text(&foreign, &mut two, 32, Some(&slot)).err().unwrap();
        assert_eq!(error.kind(), io::ErrorKind::InvalidInput);
        assert_eq!(two.reserved_bytes(), 4096);
        assert_eq!(foreign.source_input_admission_bytes().unwrap(), before);
        drop(parts);
    }

    #[test]
    fn actual_opened_receipt_moves_exact_donor_bytes_and_rejects_short_or_foreign_grants() {
        let db = QueryDb::default();
        let foreign = QueryDb::default();
        let root = crate::test_scratch::dir("native-owned-receipt");
        let path = root.join("source.dm");
        std::fs::write(&path, b"/datum/owned_receipt
").unwrap();
        let inputs = RecordingInputs::new(FileSystemInputs, 0)
            .with_initial_environment(InitialEnvironment::OriginalChecker0290);
        let OriginalRawReadOutcome::Acquired(lease) = read_original_source_open_using(
            &inputs, &path, 1024, &db, &mut || Ok(OriginalRawOpenDecision::Read),
        ).unwrap() else { panic!("actual exact opened receipt") };
        let mut expected = None;
        lease.visit_storage(|storage| {
            let AcquisitionStorage::Receipt { value, .. } = storage else { return };
            let bytes = crate::input_snapshot::exact_open_receipt_charge(value).unwrap();
            assert!(expected.replace(bytes).is_none());
            let transferred = bytes + raw_input_credits::NODE;
            let mut short = SourceArenaWork::reserve(&db, transferred - 1).unwrap();
            let mut donor = SourceArenaWork::reserve(&db, transferred + 31).unwrap();
            let before = db.source_input_admission_bytes().unwrap();
            assert_eq!(SourceArenaWork::split_original_receipt(&db, &mut short, value, None).err().unwrap().kind(),
                io::ErrorKind::OutOfMemory);
            assert_eq!(SourceArenaWork::split_original_receipt(&foreign, &mut donor, value, None).err().unwrap().kind(),
                io::ErrorKind::InvalidInput);
            assert_eq!(short.reserved_bytes(), transferred - 1);
            assert_eq!(donor.reserved_bytes(), transferred + 31);
            assert_eq!(db.source_input_admission_bytes().unwrap(), before);

            let moved = SourceArenaWork::split_original_receipt(&db, &mut donor, value, None).unwrap().unwrap();
            assert_eq!(moved.reserved_bytes(), bytes);
            assert_eq!(donor.reserved_bytes(), 31);
            assert_eq!(db.source_input_admission_bytes().unwrap(), before + OriginalReadGroup::metadata_bytes() + OriginalReadPart::metadata_bytes());
            drop(moved);
            assert_eq!(db.source_input_admission_bytes().unwrap(), before - bytes + OriginalReadGroup::metadata_bytes());
        });
        let expected = expected.unwrap();
        let mut funded_receipts = 0;
        lease.visit_weak_resource_objects(|observation| {
            if let Some(credit) = observation.receipt_control_credit() {
                funded_receipts += 1;
                assert_eq!(credit.reserved_bytes(), expected);
            }
        });
        assert_eq!(funded_receipts, 1);
    }
}

#[cfg(test)]
mod acquisition_control_identity_tests {
    use super::*;
    use crate::input_snapshot::{FileSystemInputs, RecordingInputs};
    use dm_preprocess::source_arena_credit::read_original_source_open_using;
    use dm_preprocess::{InitialEnvironment, OriginalRawOpenDecision, OriginalRawReadOutcome};

    #[test]
    fn actual_opened_weak_identities_hold_independent_constructor_credits() {
        let db = QueryDb::default();
        let baseline = db.source_input_admission_bytes().unwrap();
        let root = crate::test_scratch::dir("native-owned-acquisition-identities");
        let path = root.join("source.dm");
        std::fs::write(&path, b"/datum/owned_weak_identities
").unwrap();
        let inputs = RecordingInputs::new(FileSystemInputs, 0)
            .with_initial_environment(InitialEnvironment::OriginalChecker0290);
        let OriginalRawReadOutcome::Acquired(lease) = read_original_source_open_using(
            &inputs, &path, 1024, &db, &mut || Ok(OriginalRawOpenDecision::Read),
        ).unwrap() else { panic!("actual exact opened source") };
        let mut charge = [0; 3];
        let mut group = None;
        let mut controls = 0;
        lease.visit_weak_resource_objects(|observation| {
            let credit = observation.control_credit().unwrap();
            charge[usize::from(observation.resource_key().0)] = credit.reserved_bytes();
            let issued = credit.owner().as_any().downcast_ref::<OriginalReadPart>().unwrap();
            let actual = Arc::as_ptr(issued.group());
            assert_eq!(*group.get_or_insert(actual), actual);
            controls += 1;
        });
        assert_eq!(controls, 3, "binding, original identity and receipt use one actual group");
        let binding = lease.identity();
        let original = lease.original_identity();
        drop(lease);
        drop(inputs);
        assert!(!binding.is_alive());

        let fixed = OriginalReadGroup::metadata_bytes() + raw_input_credits::NODE;
        let part = OriginalReadPart::metadata_bytes();
        let held = db.source_input_admission_bytes().unwrap();
        assert_eq!(held, baseline + charge[0] + charge[1] + fixed + 2 * part);
        assert!(fixed + 2 * part < 2 * (Allocation::metadata_bytes() + raw_input_credits::NODE));
        drop(binding);
        assert_eq!(db.source_input_admission_bytes().unwrap(), baseline + charge[1] + fixed + part);
        drop(original);
        assert_eq!(db.source_input_admission_bytes().unwrap(), baseline);
    }
}

#[cfg(test)]
mod native_origin_parent_tests {
    use super::*;
    #[test]
    fn actual_parent_admission_counts_syntax_and_origin_in_both_directions() {
        let db=QueryDb::with_shared_native_limit(4096);
        let parent=db.body_charge.shared_reservation().unwrap();
        let baseline=parent.reserved_bytes();
        let remaining=4096-baseline;
        let reserve_syntax=|bytes|dm_syntax::SettingRootLease::reserve(&db.body_charge,super::super::body_syntax::BUDGET,bytes);
        let syntax=reserve_syntax(remaining-128).unwrap();
        let mut source=SourceArenaWork::reserve_original_origin_storage(&db,128).unwrap();
        assert_eq!(parent.reserved_bytes(),4096);
        assert!(SourceArenaWork::grow(&db,&mut source,1).is_err());
        assert!(reserve_syntax(1).is_err());
        assert_eq!(source.reserved_bytes(),128);
        let ordinary=SourceArenaWork::reserve(&db,128).unwrap();
        db.body_charge.add_soft_estimate(1024);
        assert_eq!(parent.reserved_bytes(),4096);
        db.body_charge.release_soft_estimate(1024);
        drop(ordinary);
        drop(syntax);
        SourceArenaWork::grow(&db,&mut source,remaining-128).unwrap();
        assert!(reserve_syntax(1).is_err(),"origin occupancy must deny real syntax while its local cap has room");
        SourceArenaWork::shrink(&db,&mut source,64).unwrap();
        let recovered=reserve_syntax(64).unwrap();
        drop((source,recovered));
        assert_eq!(parent.reserved_bytes(),baseline);
    }
}
