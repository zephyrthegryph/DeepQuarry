//! Weak resource census in the existing raw input family. Never content reuse/source authority.
//! Only existing SourceText/Arc payload storage and immutable capture metadata are observed.
use super::*;use dq_analyze::captured_generator_budget::Budget;use dm_preprocess::{SourceAcquisitionLease,SourceText,SourceTextStorage,WeakSourceText};use crate::runner_host::workspace_capture::RawSourceIdentity;
pub(super) const NODE:usize=256;const FIXED:usize=4096;
type ResourceKey=(u8,usize);
enum Observation{Acquisition(dm_preprocess::source_acquisition::WeakAcquisitionObject),Text(WeakSourceText,Option<Weak<super::super::Admission>>),Arena(Weak<super::source_arena::Allocation>),Original(Weak<str>),Bytes(Weak<SharedBytesOwner>),Capture(Weak<WorkspaceCapture>,usize),Derived(Weak<crate::input_snapshot::DerivedPreflight>),RecorderMetadata(Weak<()>,usize),Handlers(Weak<crate::input_snapshot::HandlerStructuralSubject>)}
impl Observation{
 fn live(&self)->bool{match self{Self::Acquisition(w)=>w.is_alive(),Self::Text(w,_)=>w.upgrade().is_some(),Self::Arena(w)=>w.strong_count()!=0,Self::Original(w)=>w.strong_count()!=0,Self::Bytes(w)=>w.strong_count()!=0,Self::Capture(w,_)=>w.strong_count()!=0,Self::Derived(w)=>w.strong_count()!=0,Self::Handlers(w)=>w.strong_count()!=0,Self::RecorderMetadata(w,_)=>w.strong_count()!=0}}
 fn bytes(&self)->io::Result<Option<usize>>{let add=|a:usize,b:usize|a.checked_add(b).ok_or_else(oom);match self{
 Self::Acquisition(w)=>{let mut n=0usize;let mut failed=false;let live=w.visit_live_storage(|storage|{use dm_preprocess::source_acquisition::AcquisitionStorage as S;let add=match storage{S::Object{bytes,..}=>bytes.checked_add(2*std::mem::size_of::<usize>()),S::Receipt{bytes,value,..}=>{let base=bytes.checked_add(2*std::mem::size_of::<usize>());if let Some((path,fact,_))=crate::input_snapshot::recorded_source_receipt_storage(value){base.and_then(|n|n.checked_add(path.capacity())).and_then(|n|n.checked_add(fact.capacity()))}else{None}},S::Source(_)=>None};match add{Some(bytes)=>n=bytes,None=>failed=true}});if failed{Err(oom())}else{Ok(live.then_some(n))}},
 Self::Arena(w)=>w.upgrade().map(|owner|owner.retained_bytes()).transpose(),
 Self::Text(w,domain)=>{let Some(text)=w.upgrade()else{return Ok(None)};let(control,payload)=super::source_arena::funded_parts(&text,domain.as_ref());let mut n=0usize;let mut failed=false;text.visit_storage(|_,bytes,storage|{let base=if control{Some(0)}else{bytes.checked_add(2*std::mem::size_of::<usize>())};let next=base.and_then(|v|match storage{SourceTextStorage::Original(_)=>Some(v),SourceTextStorage::Transformed(s)=>if payload{Some(v)}else{v.checked_add(s.capacity())}});match next{Some(v)=>n=v,None=>failed=true}});text.visit_fingerprint_storage(|_,_,capacity|{match n.checked_add(capacity){Some(v)=>n=v,None=>failed=true}});if failed{Err(oom())}else{Ok(Some(n))}},
 Self::Original(w)=>match w.upgrade(){Some(text)=>Ok(Some(text.len().checked_add(2*std::mem::size_of::<usize>()).ok_or_else(oom)?)),None=>Ok(None)},
 Self::Bytes(w)=>{let Some(bytes)=w.upgrade()else{return Ok(None)};add(std::mem::size_of::<SharedBytesOwner>()+2*std::mem::size_of::<usize>(),bytes.bytes().capacity()).map(Some)},
 Self::Capture(w,n)=>Ok((w.strong_count()!=0).then_some(*n)),Self::Derived(w)=>w.upgrade().map(|owner|owner.input_retained_charge()).transpose(),Self::Handlers(w)=>w.upgrade().map(|owner|owner.input_retained_charge()).transpose(),Self::RecorderMetadata(w,bytes)=>Ok((w.strong_count()!=0).then_some(*bytes))}}
}
struct Row{owner:Observation,bytes:usize}
#[derive(Default)]pub(super) struct Ledger{rows:BTreeMap<ResourceKey,Row>,arena_domain:Option<Weak<super::super::Admission>>}
impl Ledger{
 /// Actual retained resource storage, not the conservative admission total.
 /// Diagnostic-only; do not refresh/prune or keep strong source owners here.
 /// A dead Weak still physically retains its fixed Arc allocation until pruned.
 fn census(&self,c:&mut crate::heap_census::HeapCensus){
  let owner="query_snapshot.raw_source_inputs";
  c.collection_entries::<(ResourceKey,Row)>(owner,&self.rows as*const _ as usize,self.rows.len());
  for row in self.rows.values(){match &row.owner{
   Observation::Arena(weak)=>{let bytes=super::source_arena::Allocation::metadata_bytes();c.exposed_buffer("query_snapshot.raw_source_inputs.arena_credit",weak.as_ptr()as usize,if weak.strong_count()!=0{bytes}else{0},bytes);},
   Observation::Acquisition(w)=>{w.visit_control_storage(|ptr,logical,capacity|{c.exposed_buffer("raw_source_inputs.acquisition",ptr,logical,capacity);});w.visit_live_storage(|storage|{if let dm_preprocess::source_acquisition::AcquisitionStorage::Receipt{value,..}=storage{if let Some((path,fact,issuer))=crate::input_snapshot::recorded_source_receipt_storage(value){c.path("raw_source_inputs.receipt_paths",path);c.path("raw_source_inputs.receipt_paths",fact);c.arc_object("raw_source_inputs.issuer",issuer);}}});},
   Observation::Text(weak,_)=>c.weak_source_text_resource("query_snapshot.raw_source_inputs.source",weak),
   Observation::Original(weak)=>{let live=weak.strong_count()!=0;c.exposed_buffer("query_snapshot.raw_source_inputs.original",weak.as_ptr()as*const u8 as usize,if live{row.bytes}else{0},row.bytes);},
   Observation::Bytes(weak)=>{let metadata=std::mem::size_of::<SharedBytesOwner>()+2*std::mem::size_of::<usize>();if weak.strong_count()!=0{if let Some(bytes)=weak.upgrade(){c.exposed_buffer("query_snapshot.raw_source_inputs.bytes",weak.as_ptr()as usize,metadata,metadata);c.exposed_buffer("query_snapshot.raw_source_inputs.bytes",bytes.bytes().as_ptr()as usize,bytes.bytes().len(),bytes.bytes().capacity());continue}}c.exposed_buffer("query_snapshot.raw_source_inputs.bytes",weak.as_ptr()as usize,0,metadata);},
   Observation::RecorderMetadata(weak,_)=>{let fixed=2*std::mem::size_of::<usize>();c.exposed_buffer("query_snapshot.raw_source_inputs.recorder_metadata_issuer",weak.as_ptr()as usize,if weak.strong_count()!=0{fixed}else{0},fixed);c.unknown("query_snapshot.raw_source_inputs.recorder_metadata","typed recorder path/listing/node admission is a conservative resource bound; private mutable snapshot backing is not reported as heap payload");},
   Observation::Derived(weak)=>{if let Some(owner)=weak.upgrade(){owner.census(c);}else{let bytes=std::mem::size_of::<crate::input_snapshot::DerivedPreflight>()+2*std::mem::size_of::<usize>();c.exposed_buffer("query_snapshot.raw_source_inputs.derived_weak",weak.as_ptr()as usize,0,bytes);}},
   Observation::Handlers(weak)=>{if let Some(subject)=weak.upgrade(){subject.census(c);}else{let bytes=std::mem::size_of::<crate::input_snapshot::HandlerStructuralSubject>()+2*std::mem::size_of::<usize>();c.exposed_buffer("query_snapshot.handlers_preflight_weak",weak.as_ptr()as usize,0,bytes);}},
   Observation::Capture(weak,_)=>{if weak.strong_count()!=0{if let Some(capture)=weak.upgrade(){capture.census(c);continue}}let bytes=std::mem::size_of::<WorkspaceCapture>();c.exposed_buffer("query_snapshot.raw_source_inputs.capture_weak",weak.as_ptr()as usize,0,bytes);},
  }}
  c.unknown(owner,"raw input-family reservations and conservative map-node envelopes are admission bounds, not heap payload; exposed source capacities and resource-credit metadata are deduplicated; allocator rounding and private BTree nodes remain unknown");
 }
 pub(super) fn bind_source_arena(&mut self,owner:&Arc<super::super::Admission>)->io::Result<()>{let weak=Arc::downgrade(owner);if self.arena_domain.as_ref().is_some_and(|old|!Weak::ptr_eq(old,&weak)){return Err(io::Error::new(io::ErrorKind::InvalidInput,"raw input resource domain changed"))}self.arena_domain=Some(weak);Ok(())}
 pub(super) fn register_source_arena(&mut self,owner:&Arc<super::source_arena::Allocation>)->io::Result<()>{let key=(6,Arc::as_ptr(owner)as usize);if self.rows.contains_key(&key){return Err(io::Error::new(io::ErrorKind::InvalidInput,"arena allocation resource identity collision"))}let bytes=owner.retained_bytes()?;self.rows.insert(key,Row{owner:Observation::Arena(Arc::downgrade(owner)),bytes});Ok(())}
 pub(super) fn has_source_arena(&self,owner:&super::source_arena::Allocation)->bool{let key=(6,std::ptr::from_ref(owner)as usize);self.rows.get(&key).is_some_and(|row|matches!(&row.owner,Observation::Arena(weak)if weak.strong_count()!=0&&weak.as_ptr()==std::ptr::from_ref(owner)))}

 /// Settlement is a cleanup/ownership transaction, not new source work. No
 /// cancellation checkpoint/refresh may interrupt registration after actual
 /// provider allocation or hide retained exceptional originals on error.
 pub(super) fn adopt_original_read(&mut self,lease:&SourceAcquisitionLease,reservation:usize)->io::Result<usize>{
  // Six actual source/constructor resource rows must be paid before the bounded read begins.
  let nodes=6usize.checked_mul(NODE).ok_or_else(oom)?;
  if reservation<nodes{return Err(io::Error::new(io::ErrorKind::InvalidInput,"raw read bookkeeping was not funded before acquisition"))}
  let text=lease.source_text();let mut backing=0;let mut original=None;
  text.visit_storage(|address,_,storage|{backing=address;if let SourceTextStorage::Original(payload)=storage{original=Some((Arc::as_ptr(payload)as*const u8 as usize,Arc::downgrade(payload)))}});
  let mut staged:[Option<(ResourceKey,Observation,usize)>;6]=[None,None,None,None,None,None];
  let owner=Observation::Text(text.downgrade(),self.arena_domain.clone());
  let n=owner.bytes()?.ok_or_else(||io::Error::new(io::ErrorKind::InvalidInput,"actual acquired source lost its backing"))?;staged[0]=Some(((0,backing),owner,n));
  if let Some((address,weak))=original{let owner=Observation::Original(weak);let n=owner.bytes()?.ok_or_else(||io::Error::new(io::ErrorKind::InvalidInput,"actual acquired source lost original payload"))?;staged[1]=Some(((1,address),owner,n));}
  if let crate::input_snapshot::RecordedSourceOriginal::Bytes(bytes)=crate::input_snapshot::recorded_source_original(lease)?{let owner=Observation::Bytes(Arc::downgrade(bytes.shared_owner()));let n=owner.bytes()?.ok_or_else(||io::Error::new(io::ErrorKind::InvalidInput,"actual acquired source lost exceptional bytes"))?;staged[2]=Some(((2,Arc::as_ptr(bytes.shared_owner())as usize),owner,n));}
  let mut next=3;let mut object_error=None;
  lease.visit_weak_resource_objects(|weak|{if object_error.is_some(){return}let(kind,address)=weak.resource_key();let owner=Observation::Acquisition(weak);match owner.bytes(){Ok(Some(n))=>{staged[next]=Some(((7+kind,address),owner,n));next+=1},Ok(None)=>object_error=Some(io::Error::new(io::ErrorKind::InvalidInput,"actual acquisition constructor owner died")),Err(e)=>object_error=Some(e)}});
  if let Some(error)=object_error{return Err(error)}
  let mut delta=0usize;
  // All actual live bytes are staged before map mutation. These sums are
  // bounded by actual admitted files; an overflow is a protocol bug, never a
  // reason to fabricate a zero/empty source result.
  for (key,_,bytes) in staged.iter().flatten(){let addition=match self.rows.get(key){Some(old)=>bytes.saturating_sub(old.bytes),None=>bytes.checked_add(NODE).ok_or_else(oom)?};delta=delta.checked_add(addition).ok_or_else(oom)?;}
  // Bookkeeping was prepaid. ALWAYS publish every actual weak owner before a
  // surprise payload denial, matching existing RawInputCredits::retain. The
  // caller keeps its temporary reservation on error; after it drops, the
  // surviving original bytes remain observed in this SAME weak ledger.
  for (key,owner,bytes) in staged.into_iter().flatten(){if let Some(old)=self.rows.get_mut(&key){old.bytes=old.bytes.max(bytes);old.owner=owner;}else{self.rows.insert(key,Row{owner,bytes});}}
  if delta>reservation{return Err(oom())}
  Ok(delta)
 }
 pub(super) fn refresh(&mut self)->io::Result<usize>{crate::daemon::control::checkpoint()?;let mut total=FIXED;let mut first=None;self.rows.retain(|_,row|{if first.is_some(){return true}let pending=(||{crate::daemon::control::checkpoint()?;let Some(bytes)=row.owner.bytes()?else{return Ok(false)};row.bytes=bytes;total=total.checked_add(bytes).and_then(|n|n.checked_add(NODE)).ok_or_else(oom)?;Ok(true)})();match pending{Ok(keep)=>keep,Err(actual)=>{first=Some(actual);true}}});if let Some(actual)=first{return Err(actual)}Ok(total)}
 fn capture_metadata(&self,capture:&Arc<WorkspaceCapture>)->Option<usize>{self.rows.get(&(5,Arc::as_ptr(capture)as usize)).and_then(|r|match &r.owner{Observation::Capture(w,bytes)if w.strong_count()!=0&&Weak::ptr_eq(w,&Arc::downgrade(capture))=>Some(*bytes),_=>None})}
 fn has_source(&self,lease:&SourceAcquisitionLease)->bool{let mut key=0;lease.source_text().visit_storage(|address,_,_|key=address);self.rows.get(&(0,key)).is_some_and(|r|r.owner.live())}
}
fn oom()->io::Error{io::Error::new(io::ErrorKind::OutOfMemory,"raw source input-family resource allowance exhausted")}
fn charge(b:&Budget,n:usize)->io::Result<()>{b.charge(n).map_err(|m|io::Error::new(io::ErrorKind::OutOfMemory,m))}
/// Operation-local funding only; the ledger carries weak storage, never source data or answers.
pub(crate) struct RawInputCredits<'a>{ledger:&'a mut Ledger,budget:&'a Arc<Budget>,source_nodes:usize,capture_node:bool,prepared:bool}
impl RawInputCredits<'_>{
 /// Reserve weak/key bookkeeping BEFORE a new source/decode allocation can occur.
 pub(crate) fn prepare_source(&mut self)->io::Result<()>{crate::daemon::control::checkpoint()?;if self.prepared{return Err(io::Error::new(io::ErrorKind::InvalidInput,"raw source accounting preparation was not consumed"))}let needed=3usize.saturating_sub(self.source_nodes);charge(self.budget,needed.checked_mul(NODE).ok_or_else(oom)?)?;self.source_nodes+=needed;self.prepared=true;Ok(())}
 fn observe(&mut self,key:ResourceKey,owner:Observation)->io::Result<usize>{let bytes=owner.bytes()?.ok_or_else(||io::Error::new(io::ErrorKind::InvalidInput,"live lease lost resource backing"))?;if let Some(row)=self.ledger.rows.get_mut(&key){let delta=bytes.saturating_sub(row.bytes);row.bytes=row.bytes.max(bytes);row.owner=owner;return Ok(delta)}if self.source_nodes==0{return Err(io::Error::new(io::ErrorKind::InvalidInput,"raw source resource node was not prepared before allocation"))}self.source_nodes-=1;self.ledger.rows.insert(key,Row{owner,bytes});Ok(bytes)}
 pub(crate) fn retain(&mut self,lease:&SourceAcquisitionLease)->io::Result<()>{if !self.prepared{return Err(io::Error::new(io::ErrorKind::InvalidInput,"raw source retention requires pre-allocation preparation"))}self.prepared=false;let text=lease.source_text();let mut backing=0;let mut original=None;text.visit_storage(|address,_,storage|{backing=address;if let SourceTextStorage::Original(payload)=storage{original=Some((Arc::as_ptr(payload)as *const u8 as usize,Arc::downgrade(payload)));}});let mut delta=self.observe((0,backing),Observation::Text(text.downgrade(),self.ledger.arena_domain.clone()))?;if let Some((address,owner))=original{delta=delta.checked_add(self.observe((1,address),Observation::Original(owner))?).ok_or_else(oom)?;}if let crate::input_snapshot::RecordedSourceOriginal::Bytes(bytes)=crate::input_snapshot::recorded_source_original(lease)?{delta=delta.checked_add(self.observe((2,Arc::as_ptr(bytes.shared_owner())as usize),Observation::Bytes(Arc::downgrade(bytes.shared_owner())))?).ok_or_else(oom)?;}
 // Every actual backing is weakly registered BEFORE a payload denial, including
 // exceptional originals retained independently by RecordingInputs on failure.
 charge(self.budget,delta)}
 /// Caller computed/funded this immutable metadata while its construction scratch still lived.
 pub(crate) fn retain_capture_metadata(&mut self,capture:&Arc<WorkspaceCapture>,bytes:usize)->io::Result<()>{let key=(5,Arc::as_ptr(capture)as usize);if let Some(old)=self.ledger.capture_metadata(capture){if old!=bytes{return Err(io::Error::new(io::ErrorKind::InvalidInput,"immutable raw capture metadata charge changed"))}return Ok(())}if !self.capture_node{return Err(io::Error::new(io::ErrorKind::InvalidInput,"raw capture metadata registration was not prepared"))}self.capture_node=false;self.ledger.rows.insert(key,Row{owner:Observation::Capture(Arc::downgrade(capture),bytes),bytes});Ok(())}
}
impl QueryDb{
 /// Called by the EXISTING BuildHost idle census outside active query gates.
 /// Same family lock order as reserve/grow; no source content/cache is retained.
 pub(crate) fn raw_source_input_census(&self,c:&mut crate::heap_census::HeapCensus){let _gate=self.raw_policy.gate.lock().unwrap_or_else(|e|e.into_inner());self.raw_policy.workspace.raw_sources.lock().unwrap_or_else(|e|e.into_inner()).census(c);}
 pub(crate) fn raw_source_input_charge_locked(&self)->io::Result<usize>{self.raw_policy.workspace.raw_sources.lock().unwrap_or_else(|e|e.into_inner()).refresh()}
 pub(super) fn refresh_raw_source_inputs_locked(&self)->io::Result<()>{let sources=self.raw_source_input_charge_locked()?;self.workspace_input_base_headroom_locked(sources)?;Ok(())}
 pub(super) fn raw_source_capture_fixed_credit_locked(&self,capture:&Arc<WorkspaceCapture>)->io::Result<Option<usize>>{Ok(self.raw_policy.workspace.raw_sources.lock().unwrap_or_else(|e|e.into_inner()).capture_metadata(capture))}
 pub(crate) fn with_raw_source_capture_inputs(&self,run:impl FnOnce(&Arc<Budget>,&mut RawInputCredits<'_>)->io::Result<(Arc<WorkspaceCapture>,Arc<RawSourceIdentity>)>)->io::Result<(Arc<WorkspaceCapture>,Arc<RawSourceIdentity>)>{crate::daemon::control::checkpoint()?;let _gate=self.raw_policy.gate.lock().unwrap_or_else(|e|e.into_inner());let mut ledger=self.raw_policy.workspace.raw_sources.lock().unwrap_or_else(|e|e.into_inner());ledger.bind_source_arena(&self.raw_policy.admission)?;let live=ledger.refresh()?;let available=self.workspace_input_base_headroom_locked(live)?;let budget=Budget::new(available).map_err(|m|io::Error::new(io::ErrorKind::OutOfMemory,m))?;charge(&budget,NODE)?;let mut credits=RawInputCredits{ledger:&mut ledger,budget:&budget,source_nodes:0,capture_node:true,prepared:false};let pending=run(&budget,&mut credits);match pending{Err(actual)=>Err(actual),Ok((capture,identity))=>{if credits.ledger.capture_metadata(&capture).is_none(){return Err(io::Error::new(io::ErrorKind::InvalidInput,"returned raw capture lacks actual funded metadata registration"))}for lease in capture.raw_input_files(){if !credits.ledger.has_source(lease){return Err(io::Error::new(io::ErrorKind::InvalidInput,"returned raw capture has unregistered original backing"))}}budget.require().map_err(|m|io::Error::new(io::ErrorKind::OutOfMemory,m))?;let actual=credits.ledger.refresh()?;self.workspace_input_base_headroom_locked(actual)?;crate::daemon::control::checkpoint()?;Ok((capture,identity))}}}
}

#[cfg(test)]mod tests{
 use super::*;
 fn credits<'a>(ledger:&'a mut Ledger,budget:&'a Arc<Budget>)->RawInputCredits<'a>{RawInputCredits{ledger,budget,source_nodes:0,capture_node:true,prepared:false}}
 fn keep_text(c:&mut RawInputCredits<'_>,text:&SourceText)->io::Result<()>{c.prepare_source()?;c.prepared=false;let mut backing=0;let mut original=None;text.visit_storage(|address,_,storage|{backing=address;if let SourceTextStorage::Original(s)=storage{original=Some((Arc::as_ptr(s)as *const u8 as usize,Arc::downgrade(s)));}});let mut delta=c.observe((0,backing),Observation::Text(text.downgrade(),c.ledger.arena_domain.clone()))?;if let Some((address,owner))=original{delta+=c.observe((1,address),Observation::Original(owner))?;}charge(c.budget,delta)}
 #[test]fn raw_input_census_aliases_slices_and_equal_content_different_allocations_are_distinct(){let source:SourceText="abcdefgh".repeat(1024).into();let slice=source.checked_view(2..15).unwrap();let equal:SourceText=source.as_str().to_owned().into();let budget=Budget::new(1024*1024).unwrap();let mut ledger=Ledger::default();{let mut c=credits(&mut ledger,&budget);keep_text(&mut c,&source).unwrap();let first=c.ledger.refresh().unwrap();c.prepare_source().unwrap();let before=budget.used();c.prepared=false;let mut key=0;slice.visit_storage(|a,_,_|key=a);assert_eq!(c.observe((0,key),Observation::Text(slice.downgrade(),c.ledger.arena_domain.clone())).unwrap(),0);assert_eq!(budget.used(),before,"no backing funding for aliases");assert_eq!(c.ledger.refresh().unwrap(),first);keep_text(&mut c,&equal).unwrap();assert!(c.ledger.refresh().unwrap()>first+equal.len());}let held=ledger.refresh().unwrap();drop(source);assert_eq!(ledger.refresh().unwrap(),held,"overlapping detached view retains the whole first allocation");drop(slice);assert!(ledger.refresh().unwrap()<held);drop(equal);assert_eq!(ledger.refresh().unwrap(),FIXED);assert!(ledger.rows.is_empty());}
 #[test]fn raw_input_census_original_payload_outlives_backing_and_dedups_wrappers(){let payload:Arc<str>=Arc::from("large actual original".repeat(1000));let first:SourceText=payload.clone().into();let second:SourceText=payload.clone().into();let weak=first.downgrade();let strong=Arc::strong_count(&payload);let budget=Budget::new(1024*1024).unwrap();let mut ledger=Ledger::default();{let mut c=credits(&mut ledger,&budget);keep_text(&mut c,&first).unwrap();let one=c.ledger.refresh().unwrap();keep_text(&mut c,&second).unwrap();let two=c.ledger.refresh().unwrap();assert!(two>one);assert!(two-one<payload.len(),"same Arc payload is not charged again");assert_eq!(Arc::strong_count(&payload),strong,"census retains no strong payload owner");}drop(first);drop(second);assert!(weak.upgrade().is_none());let detached=ledger.refresh().unwrap();assert_eq!(ledger.rows.len(),1,"only original Arc payload survives frame/backing replacement");assert!(detached>=FIXED+payload.len());drop(payload);assert_eq!(ledger.refresh().unwrap(),FIXED);assert!(ledger.rows.is_empty());}
 #[test]fn raw_input_census_fingerprint_growth_is_refreshed_and_not_credited_as_freed(){let source:SourceText="x".repeat(8192).into();let budget=Budget::new(1024*1024).unwrap();let mut ledger=Ledger::default();keep_text(&mut credits(&mut ledger,&budget),&source).unwrap();let before=ledger.refresh().unwrap();for end in 1..128{source.span_fingerprint(0..end).unwrap();}let mut actual=0;source.visit_fingerprint_storage(|_,_,capacity|actual=capacity);assert!(actual>0);assert_eq!(ledger.refresh().unwrap()-before,actual);let alias=source.clone();drop(source);assert_eq!(ledger.refresh().unwrap(),before+actual);drop(alias);assert_eq!(ledger.refresh().unwrap(),FIXED);}
 #[test]fn raw_input_census_shared_bytes_aliases_and_failed_quota_keep_weak_observation_until_release(){let bytes=dm_resources::SharedBytes::from(vec![b'x';4096]);let alias=bytes.clone();let owner=Arc::as_ptr(bytes.shared_owner())as usize;let budget=Budget::new(1024*1024).unwrap();let mut ledger=Ledger::default();{let mut c=credits(&mut ledger,&budget);c.prepare_source().unwrap();c.prepared=false;let n=c.observe((2,owner),Observation::Bytes(Arc::downgrade(bytes.shared_owner()))).unwrap();charge(&budget,n).unwrap();assert_eq!(c.observe((2,owner),Observation::Bytes(Arc::downgrade(alias.shared_owner()))).unwrap(),0);}let held=ledger.refresh().unwrap();drop(bytes);assert_eq!(ledger.refresh().unwrap(),held);drop(alias);assert_eq!(ledger.refresh().unwrap(),FIXED);
 let source:SourceText="y".repeat(4096).into();let denied=Budget::new(2048).unwrap();let error=keep_text(&mut credits(&mut ledger,&denied),&source).unwrap_err();assert_eq!(error.kind(),io::ErrorKind::OutOfMemory);assert!(!ledger.rows.is_empty(),"allocated owner remains observed after payload funding refusal");assert!(ledger.refresh().unwrap()>source.len());drop(source);assert_eq!(ledger.refresh().unwrap(),FIXED);let retry:SourceText="retry".into();keep_text(&mut credits(&mut ledger,&budget),&retry).unwrap();assert!(ledger.refresh().unwrap()>FIXED);drop(retry);assert_eq!(ledger.refresh().unwrap(),FIXED);}
 #[test]fn raw_input_census_metadata_preflight_refuses_before_any_weak_node_growth(){let source:SourceText="x".into();let budget=Budget::new(128).unwrap();let mut ledger=Ledger::default();let error=credits(&mut ledger,&budget).prepare_source().unwrap_err();assert_eq!(error.kind(),io::ErrorKind::OutOfMemory);assert!(ledger.rows.is_empty());assert_eq!(ledger.refresh().unwrap(),FIXED);drop(source);}
 #[test]fn actual_bom_recorded_original_survives_failed_capture_and_credits_retire_only_after_input_owner_drops(){use crate::input_snapshot::{RecordingInputs,FileSystemInputs};let root=crate::test_scratch::dir("raw-census-bom-failure");let path=root.join("actual.dm");let mut bytes=vec![0xef,0xbb,0xbf];bytes.extend_from_slice("x".repeat(4096).as_bytes());std::fs::write(&path,&bytes).unwrap();let inputs=RecordingInputs::new(FileSystemInputs,0).with_initial_environment(dm_preprocess::InitialEnvironment::OriginalChecker0290);let lease=inputs.read_raw_source(&path,1024*1024,None,|_,_,_|Ok(())).unwrap().unwrap();let budget=Budget::new(2048).unwrap();let mut ledger=Ledger::default();{let mut c=credits(&mut ledger,&budget);c.prepare_source().unwrap();let error=c.retain(&lease).unwrap_err();assert_eq!(error.kind(),io::ErrorKind::OutOfMemory);}drop(lease);assert!(ledger.refresh().unwrap()>=FIXED+bytes.len(),"RecordingInputs still owns the original exceptional bytes after failed capture");assert!(ledger.rows.values().any(|r|matches!(r.owner,Observation::Bytes(_))));drop(inputs);assert_eq!(ledger.refresh().unwrap(),FIXED);assert!(ledger.rows.is_empty());}

}

#[cfg(test)]mod actual_arena_portion_census_tests{
 use super::*;use dm_preprocess::source_arena_credit::SourceArenaWork;
 #[test]fn existing_weak_census_skips_only_real_same_domain_parts_and_keeps_fingerprint_growth(){
  let db=QueryDb::default();let foreign=QueryDb::default();let text=String::from("native source with span cache");let capacity=text.capacity();let source=SourceText::from_source_arena(text,SourceArenaWork::reserve(&db,capacity).unwrap(),SourceArenaWork::reserve(&db,SourceText::source_arena_control_bytes().unwrap()).unwrap().into_control()).unwrap();
  let same=Observation::Text(source.downgrade(),Some(Arc::downgrade(&db.raw_policy.admission)));assert_eq!(same.bytes().unwrap(),Some(0));
  let other=Observation::Text(source.downgrade(),Some(Arc::downgrade(&foreign.raw_policy.admission)));assert!(other.bytes().unwrap().unwrap()>=capacity,"foreign family is not granted another family's reservation");
  source.span_fingerprint(0..source.len()).unwrap();let mut actual=0;source.visit_fingerprint_storage(|_,_,bytes|actual=bytes);assert!(actual>0);assert_eq!(same.bytes().unwrap(),Some(actual));assert!(other.bytes().unwrap().unwrap()>=capacity+actual);
  drop(source);assert_eq!(same.bytes().unwrap(),None,"resource observation never revives a source");drop(same);drop(other);
 }
 #[test]fn actual_ledger_heap_census_dedups_native_parts_tracks_live_fingerprints_and_never_revives_dead_source(){
  let db=QueryDb::default();let text="actual retained arena value".repeat(128);let capacity=text.capacity();let source=SourceText::from_source_arena(text,SourceArenaWork::reserve(&db,capacity).unwrap(),SourceArenaWork::reserve(&db,SourceText::source_arena_control_bytes().unwrap()).unwrap().into_control()).unwrap();let weak=source.downgrade();
  {let budget=Budget::new(1<<20).unwrap();let mut ledger=db.raw_policy.workspace.raw_sources.lock().unwrap();let mut credits=RawInputCredits{ledger:&mut ledger,budget:&budget,source_nodes:0,capture_node:false,prepared:false};credits.prepare_source().unwrap();credits.prepared=false;let mut address=0;source.visit_storage(|p,_,_|address=p);assert_eq!(credits.observe((0,address),Observation::Text(source.downgrade(),credits.ledger.arena_domain.clone())).unwrap(),0);}
  source.span_fingerprint(0..source.len()).unwrap();let mut fingerprints=0;source.visit_fingerprint_storage(|_,_,bytes|fingerprints=bytes);assert!(fingerprints>0);
  let mut once=crate::heap_census::HeapCensus::new("native_arena_once");db.raw_source_input_census(&mut once);let once=once.finish();let mut aliases=crate::heap_census::HeapCensus::new("native_arena_aliases");db.raw_source_input_census(&mut aliases);db.raw_source_input_census(&mut aliases);let aliases=aliases.finish();assert_eq!(once.unique_known_capacity_bytes,aliases.unique_known_capacity_bytes,"same real owners are deduplicated across alias walks");
  drop(source);assert!(weak.upgrade().is_none());let mut dead=crate::heap_census::HeapCensus::new("native_arena_dead");db.raw_source_input_census(&mut dead);let dead=dead.finish();assert!(weak.upgrade().is_none());assert!(once.unique_known_capacity_bytes>=dead.unique_known_capacity_bytes+capacity as u64+fingerprints as u64,"real String/fingerprint payload was freed while weak backing/credit metadata remains");
  drop(weak);let _=db.raw_source_input_charge_locked().unwrap();let mut gone=crate::heap_census::HeapCensus::new("native_arena_pruned");db.raw_source_input_census(&mut gone);let gone=gone.finish();assert_eq!(gone.unique_known_capacity_bytes,0,"actual dead weak row cleanup releases both backing and native credit metadata");
 }
}

impl crate::input_snapshot::RecordedPolicySourceLender for RawInputCredits<'_>{
 fn with_held_source_work(&mut self,queries:&crate::query_db::QueryDb,visit:&mut dyn FnMut(&dyn dm_preprocess::source_arena_credit::SourceArenaWork)->io::Result<()>)->io::Result<()>{RawInputCredits::with_held_source_work(self,queries,|work|visit(work))}

 fn prepare_directory_metadata(&mut self,issuer:&Arc<()>,bytes:usize)->io::Result<()>{
  let key=(251,Arc::as_ptr(issuer)as usize);
  let old=self.ledger.rows.get(&key).map_or(0,|row|row.bytes);
  if !self.ledger.rows.contains_key(&key){charge(self.budget,NODE)?;}
  // Actual metadata is published before a surprise denial, as with raw reads.
  self.ledger.rows.insert(key,Row{owner:Observation::RecorderMetadata(Arc::downgrade(issuer),bytes),bytes});
  charge(self.budget,bytes.saturating_sub(old))
 }
 fn directory_window_started(&mut self,issuer:&Arc<()>,upper:usize)->io::Result<()>{let key=(251,Arc::as_ptr(issuer)as usize);let row=self.ledger.rows.get_mut(&key).ok_or_else(||io::Error::new(io::ErrorKind::InvalidInput,"directory resource node was not prepared"))?;row.bytes=upper;row.owner=Observation::RecorderMetadata(Arc::downgrade(issuer),upper);Ok(())}
 fn directory_metadata_settled(&mut self,issuer:&Arc<()>,actual:usize)->io::Result<()>{let key=(251,Arc::as_ptr(issuer)as usize);let row=self.ledger.rows.get_mut(&key).ok_or_else(||io::Error::new(io::ErrorKind::InvalidInput,"directory resource window absent"))?;row.bytes=actual;row.owner=Observation::RecorderMetadata(Arc::downgrade(issuer),actual);Ok(())}
 fn prepare_source(&mut self)->io::Result<()>{RawInputCredits::prepare_source(self)}
 fn acquired(&mut self,lease:&SourceAcquisitionLease)->io::Result<()>{self.retain(lease)}
}
impl QueryDb {
 /// Genuine cold owner: SAME input-family gate, live census and headroom.
 /// This lends funding, not source data; the recorder still performs each read.
 pub(crate) fn prepare_derived_preflight<P:crate::input_snapshot::SnapshotProvider>(self:&Arc<Self>,inputs:&crate::input_snapshot::RecordingInputs<P>,intent:&crate::policy_request::AdmittedPolicyRequest)->io::Result<Arc<crate::input_snapshot::DerivedPreflight>>{
  crate::daemon::control::checkpoint()?;
  let _gate=self.raw_policy.gate.lock().unwrap_or_else(|e|e.into_inner());
  let mut ledger=self.raw_policy.workspace.raw_sources.lock().unwrap_or_else(|e|e.into_inner());
  ledger.bind_source_arena(&self.raw_policy.admission)?;
  let live=ledger.refresh()?;let available=self.workspace_input_base_headroom_locked(live)?;
  let budget=Budget::new(available).map_err(|m|io::Error::new(io::ErrorKind::OutOfMemory,m))?;
  charge(&budget,NODE)?; // preflight row BEFORE owner allocation
  let mut credits=RawInputCredits{ledger:&mut ledger,budget:&budget,source_nodes:0,capture_node:false,prepared:false};
  // On failure return the real first error. acquired() already settled actual
  // exceptional originals; no late checkpoint can replace that error or hide it.
  let owner=inputs.issue_derived_preflight_using(intent,self,&budget,&mut credits)?;
  let bytes=owner.input_retained_charge()?;
  let key=(250,Arc::as_ptr(&owner)as usize);
  if credits.ledger.rows.contains_key(&key){return Err(io::Error::new(io::ErrorKind::InvalidInput,"Derived preflight resource identity collision"))}
  credits.ledger.rows.insert(key,Row{owner:Observation::Derived(Arc::downgrade(&owner)),bytes});
  budget.require().map_err(|m|io::Error::new(io::ErrorKind::OutOfMemory,m))?;
  let actual=credits.ledger.refresh()?;self.workspace_input_base_headroom_locked(actual)?;
  crate::daemon::control::checkpoint()?;Ok(owner)
 }
}

#[cfg(test)]mod derived_preflight_resource_controls{
 use super::*;use crate::input_snapshot::{RecordingInputs,FileSystemInputs};
 #[test]fn actual_preflight_and_exceptional_originals_share_existing_input_ledger_until_their_real_owners_drop(){
  let root=crate::test_scratch::dir("derived-real-input-ledger");std::fs::create_dir_all(root.join("code")).unwrap();let mut bytes=vec![0xef,0xbb,0xbf];bytes.extend_from_slice(format!("/datum/probe\n    var/value\n// {}\n", "original payload ".repeat(512)).as_bytes());std::fs::write(root.join("code/a.dm"),&bytes).unwrap();
  let inputs=RecordingInputs::new(FileSystemInputs,0).with_initial_environment(dm_preprocess::InitialEnvironment::OriginalChecker0290);let db=Arc::new(QueryDb::default());
  let intent=crate::policy_request::PolicyInputRequest{analysis_context:Some(crate::policy_request::AnalysisContext::OriginalAnalyze0290),workspace:Some(crate::policy_request::WorkspacePolicyRequest{root:root.clone(),recursive_roots:vec![root.join("code")],configuration:root.join("tools/ci/lint_scopes.toml")}),workspace_auxiliary:vec![crate::policy_request::WorkspaceAuxiliaryQuestion::DerivedReads],..Default::default()}.admit().unwrap();
  let owner=db.prepare_derived_preflight(&inputs,&intent).unwrap();let held=db.raw_source_input_charge_locked().unwrap();assert!(held>owner.input_retained_charge().unwrap()+bytes.len());
  drop(owner);let original_only=db.raw_source_input_charge_locked().unwrap();assert!(original_only<held);assert!(original_only>=FIXED+bytes.len(),"actual recorder exceptional original outlives preflight, and remains settled");
  drop(inputs);assert_eq!(db.raw_source_input_charge_locked().unwrap(),FIXED,"same ledger retires all rows only after actual owners die");
 }
}

#[cfg(test)]mod directory_window_resource_controls{
 use super::*;use crate::input_snapshot::{SnapshotProvider,RecordingInputs,FileSystemInputs,Stamp,FolderListing,PolicyDirectoryListing};
 struct Observe{maximum:AtomicUsize,fail:bool}
 impl SnapshotProvider for Observe{
  fn stamp(&self,path:&Path)->io::Result<Stamp>{FileSystemInputs.stamp(path)}
  fn read(&self,path:&Path)->io::Result<(Stamp,Vec<u8>)>{FileSystemInputs.read(path)}
  fn list(&self,path:&Path)->io::Result<FolderListing>{FileSystemInputs.list(path)}
  fn policy_directory(&self,path:&Path,follow:bool,maximum:usize)->io::Result<Option<PolicyDirectoryListing>>{self.maximum.store(maximum,Ordering::Release);if self.fail{return Err(io::Error::from_raw_os_error(1450))}FileSystemInputs.policy_directory(path,follow,maximum)}
 }
 #[test]fn actual_bounded_directory_provider_receives_small_reserved_window_and_unused_credit_returns(){
  let root=crate::test_scratch::dir("actual-small-directory-window");std::fs::write(root.join("a.dm"),"/datum/a\n").unwrap();let provider=Observe{maximum:0.into(),fail:false};let inputs=RecordingInputs::new(&provider,0);let budget=Budget::new(16*1024).unwrap();let mut ledger=Ledger::default();let mut credits=RawInputCredits{ledger:&mut ledger,budget:&budget,source_nodes:0,capture_node:false,prepared:false};
  let listing=inputs.capture_policy_directory_lent(&root,true,0,&budget,&mut credits).unwrap();assert!(matches!(listing,PolicyDirectoryListing::Present(_)));let offered=provider.maximum.load(Ordering::Acquire);assert!(offered>0&&offered<16*1024,"provider must see remaining family window, not unconditional64MiB");assert!(budget.remaining()>1024,"unused maximum is refunded after real metadata settlement");drop(listing);drop(credits);assert!(ledger.refresh().unwrap()>FIXED);drop(inputs);assert_eq!(ledger.refresh().unwrap(),FIXED);
 }
 #[test]fn actual_directory_error_survives_window_cleanup_and_quota_refuses_before_provider(){
  let root=crate::test_scratch::dir("actual-directory-first-io");let provider=Observe{maximum:0.into(),fail:true};let inputs=RecordingInputs::new(&provider,0);let budget=Budget::new(16*1024).unwrap();let mut ledger=Ledger::default();let mut credits=RawInputCredits{ledger:&mut ledger,budget:&budget,source_nodes:0,capture_node:false,prepared:false};let error=inputs.capture_policy_directory_lent(&root,true,0,&budget,&mut credits).unwrap_err();assert_eq!(error.raw_os_error(),Some(1450));assert!(budget.remaining()>1024);drop(credits);drop(inputs);assert_eq!(ledger.refresh().unwrap(),FIXED);
  let provider=Observe{maximum:0.into(),fail:false};let inputs=RecordingInputs::new(&provider,0);let tiny=Budget::new(256).unwrap();let mut ledger=Ledger::default();let mut credits=RawInputCredits{ledger:&mut ledger,budget:&tiny,source_nodes:0,capture_node:false,prepared:false};assert!(inputs.capture_policy_directory_lent(&root,true,0,&tiny,&mut credits).is_err());assert_eq!(provider.maximum.load(Ordering::Acquire),0,"metadata quota denial must happen before directory provider growth");
 }
}

impl QueryDb{
 /// Serialized resource owner for an actual failed-root one-shot report. The
 /// failure object is a consumed private producer receipt, never caller None.
 pub(crate) fn with_failed_original_derived<P:crate::input_snapshot::SnapshotProvider,T>(&self,inputs:&crate::input_snapshot::RecordingInputs<P>,failed:crate::input_snapshot::OriginalRootOpenFailure,consume:impl FnOnce(&dq_analyze::captured_derived_reads::DerivedReadData,&dq_analyze::captured_raw_file::Config,&Arc<Budget>)->io::Result<T>)->io::Result<T>{
  failed.require_recording(inputs,self)?;crate::daemon::control::checkpoint()?;
  let _gate=self.raw_policy.gate.try_lock().map_err(|error|match error{std::sync::TryLockError::WouldBlock=>io::Error::new(io::ErrorKind::WouldBlock,"failed Derived report cannot reenter an active raw-family operation"),std::sync::TryLockError::Poisoned(_)=>io::Error::new(io::ErrorKind::InvalidData,"raw input-family gate poisoned")})?;
  let mut ledger=self.raw_policy.workspace.raw_sources.lock().unwrap_or_else(|e|e.into_inner());ledger.bind_source_arena(&self.raw_policy.admission)?;let live=ledger.refresh()?;let available=self.workspace_input_base_headroom_locked(live)?;
  let budget=Budget::new(available).map_err(|m|io::Error::new(io::ErrorKind::OutOfMemory,m))?;
  let mut credits=RawInputCredits{ledger:&mut ledger,budget:&budget,source_nodes:0,capture_node:false,prepared:false};
  let pending=inputs.with_failed_original_derived_using(failed,self,&budget,&mut credits,|data,config|consume(data,config,&budget));
  // Exceptional backing was registered by the SAME lender before any denial.
  // Preserve the first report/callback IO; cleanup cannot replace it.
  let value=match pending{Ok(value)=>value,Err(actual)=>return Err(actual)};budget.require().map_err(|m|io::Error::new(io::ErrorKind::OutOfMemory,m))?;
  let actual=credits.ledger.refresh()?;self.workspace_input_base_headroom_locked(actual)?;crate::daemon::control::checkpoint()?;Ok(value)
 }
}

impl QueryDb{
 /// Cold partial-purpose selection belongs to the SAME input resource family.
 /// The returned owner is not a model/full-source grant. Native preparation
 /// runs only after this lock is released and uses the existing source host.
 pub(crate) fn prepare_handlers_preflight<P:crate::input_snapshot::SnapshotProvider>(self:&Arc<Self>,inputs:&crate::input_snapshot::RecordingInputs<P>,intent:&crate::policy_request::AdmittedPolicyRequest)->io::Result<Arc<crate::input_snapshot::HandlerStructuralSubject>>{
  crate::daemon::control::checkpoint()?;
  let _gate=self.raw_policy.gate.lock().unwrap_or_else(|e|e.into_inner());
  let mut ledger=self.raw_policy.workspace.raw_sources.lock().unwrap_or_else(|e|e.into_inner());ledger.bind_source_arena(&self.raw_policy.admission)?;
  let live=ledger.refresh()?;let available=self.workspace_input_base_headroom_locked(live)?;
  let budget=Budget::new(available).map_err(|m|io::Error::new(io::ErrorKind::OutOfMemory,m))?;charge(&budget,NODE)?;
  let mut credits=RawInputCredits{ledger:&mut ledger,budget:&budget,source_nodes:0,capture_node:false,prepared:false};
  // No cleanup work replaces a preparation error. acquired() has already
  // settled any exceptional source payload retained by the real recorder.
  let subject=Arc::new(inputs.issue_handlers_structural_subject_using(intent,&budget,&mut credits,self)?);
  let bytes=subject.input_retained_charge()?;let key=(252,Arc::as_ptr(&subject)as usize);
  if credits.ledger.rows.contains_key(&key){return Err(io::Error::new(io::ErrorKind::InvalidInput,"handlers preflight resource identity collision"))}
  credits.ledger.rows.insert(key,Row{owner:Observation::Handlers(Arc::downgrade(&subject)),bytes});
  budget.require().map_err(|m|io::Error::new(io::ErrorKind::OutOfMemory,m))?;let actual=credits.ledger.refresh()?;self.workspace_input_base_headroom_locked(actual)?;crate::daemon::control::checkpoint()?;Ok(subject)
 }
}

impl RawInputCredits<'_>{
 /// Synchronous loan only: the same held ledger/budget, never another counter.
 /// Other credit operations resume after this borrow ends. No SourceArenaWork
 /// call in this closure may be replaced by ordinary QueryDb's locking lender.
 pub(super) fn with_held_source_work<R>(&mut self,db:&QueryDb,consume:impl FnOnce(&dyn dm_preprocess::source_arena_credit::SourceArenaWork)->io::Result<R>)->io::Result<R>{super::source_arena::with_held_source_work(db,self.ledger,self.budget,consume)}
}
