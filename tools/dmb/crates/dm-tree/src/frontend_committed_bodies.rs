//! Actual procedure-commit preparation. No second memo/AST cache.
use super::*;
use crate::procedure::original_primary_signatures::CommittedBodySyntaxConsumer;
use dm_syntax::{SettingAdmission,SettingRootLease,Span};
use dm_preprocess::regions::OriginalNoticeRegistration;
use std::io;
fn checkpoint(a:&SettingAdmission<'_>)->io::Result<()>{let proxy=a.checkpoint();if let Some(actual)=a.take_operational_error(){return Err(actual)}proxy}
fn failure(actual:BodySyntaxFailure)->io::Error{match actual{BodySyntaxFailure::Operational(actual)=>actual,BodySyntaxFailure::Syntax(actual)=>io::Error::new(io::ErrorKind::Unsupported,format!("actual committed BODY contract: {actual:?}"))}}
struct Record{header:Span,input:Arc<BodySyntaxInput>,parameters:dm_syntax::SharedParameterSignature,settings:Option<Box<CommittedSettingRoots>>}
struct Records{rows:Vec<Record>,credit:Option<SettingRootLease>}
impl Records{
 fn reserve_one(&mut self,a:&SettingAdmission<'_>)->io::Result<()>{
  if self.rows.len()<self.rows.capacity(){return Ok(())}
  let capacity=self.rows.capacity().max(1).checked_mul(2).ok_or(io::ErrorKind::OutOfMemory)?;
  let(mut rows,credit)=crate::procedure::original_primary_signatures::allocate_funded_rows::<Record>(capacity,a)?;
  rows.append(&mut self.rows);let old=std::mem::replace(&mut self.rows,rows);drop(old);self.credit=Some(credit);Ok(())
 }
}
struct DiagnosticRow{header:Span,diagnostic:dm_syntax::Diagnostic,registration:OriginalNoticeRegistration}
struct Diagnostics{rows:Vec<DiagnosticRow>,credit:Option<SettingRootLease>}
/// Strong Inputs belong to preparation until moved into the existing final
/// BodyQueries input array. Products are weak here and remain ordinary Kind4 values.
pub(super) struct CommittedBodyPreparation{
 host:Arc<dyn BodySyntaxQueries>,primary:Option<dm_syntax::OriginalPrimaryProducerIdentity>,
 records:Records,diagnostics:Diagnostics,good:usize,bad:usize,failed_prefix:Option<Span>,
 // LAST: Code/Input allocations and controls physically retire before grant.
 credit:SettingRootLease,
}
impl CommittedBodyPreparation{
 pub(super) fn new(host:Arc<dyn BodySyntaxQueries>,a:&SettingAdmission<'_>)->io::Result<Self>{checkpoint(a)?;let credit=a.reserve(std::mem::size_of::<Self>())?;Ok(Self{host,primary:None,records:Records{rows:Vec::new(),credit:None},diagnostics:Diagnostics{rows:Vec::new(),credit:None},good:0,bad:0,failed_prefix:None,credit})}
 fn bind_primary(&mut self,input:&dm_syntax::OriginalCommittedBodyInput<'_,'_>,a:&SettingAdmission<'_>)->io::Result<()>{checkpoint(a)?;if !input.literal_facts().admitted_by(a)||!input.primary_producer().same_producer(input.primary_producer()){return Err(trace_invalid_input("committed-bind-primary: literal grant or primary producer identity"))}match &self.primary{Some(actual)if !actual.same_producer(input.primary_producer())=>Err(io::Error::new(io::ErrorKind::InvalidInput,"committed bodies belong to another actual primary epoch")),Some(_)=>Ok(()),None=>Ok(())}}
 fn retain_primary(&mut self,producer:dm_syntax::OriginalPrimaryProducerIdentity)->io::Result<()>{match &self.primary{Some(actual)if !actual.same_producer(&producer)=>Err(io::Error::new(io::ErrorKind::InvalidInput,"committed BODY result belongs to another actual primary epoch")),Some(_)=>Ok(()),None=>{self.primary=Some(producer);Ok(())}}}
 fn retain_first_error(&mut self,header:Span,diagnostic:&dm_syntax::Diagnostic,registration:&OriginalNoticeRegistration,a:&SettingAdmission<'_>)->io::Result<()>{
  checkpoint(a)?;let bytes=diagnostic.message.len().checked_mul(4).ok_or(io::ErrorKind::OutOfMemory)?;a.grow(&mut self.credit,bytes)?;
  let mut message=String::new();message.try_reserve_exact(diagnostic.message.len()).map_err(|actual|io::Error::new(io::ErrorKind::OutOfMemory,actual))?;if message.capacity()>bytes{return Err(io::Error::new(io::ErrorKind::OutOfMemory,"diagnostic allocator exceeded its admitted bound"))}message.push_str(&diagnostic.message);
  if self.diagnostics.rows.len()==self.diagnostics.rows.capacity(){let capacity=self.diagnostics.rows.capacity().max(1).checked_mul(2).ok_or(io::ErrorKind::OutOfMemory)?;let(mut rows,credit)=crate::procedure::original_primary_signatures::allocate_funded_rows::<DiagnosticRow>(capacity,a)?;rows.append(&mut self.diagnostics.rows);let old=std::mem::replace(&mut self.diagnostics.rows,rows);drop(old);self.diagnostics.credit=Some(credit);}
  self.diagnostics.rows.push(DiagnosticRow{header,diagnostic:dm_syntax::Diagnostic{span:diagnostic.span,kind:diagnostic.kind,message},registration:registration.clone()});Ok(())
 }
}
impl CommittedBodySyntaxConsumer for CommittedBodyPreparation{
 fn formal_prefix_adoption(&mut self,primary:&dm_preprocess::regions::OriginalStreamPrimary,a:&SettingAdmission<'_>)->io::Result<CommittedPrefixAdoption>{self.take_formal_prefix(primary,a)}
 fn final_adoption(&mut self,primary:&dm_preprocess::regions::OriginalStreamPrimary,end:&OriginalNoticeRegistration,a:&SettingAdmission<'_>)->io::Result<CommittedHeaderAdoption>{
  checkpoint(a)?;end.require_after_actual_end()?;for row in &self.diagnostics.rows{checkpoint(a)?;if row.registration.compare_same_source(end)?==std::cmp::Ordering::Greater{return Err(trace_invalid_input("committed-final-adoption: diagnostic registration follows actual reader end"))}}if self.primary.as_ref().is_some_and(|owner|!primary.same_primary_producer(owner))||primary.observer_stop().is_some(){return Err(trace_invalid_input("committed-final-adoption: producer identity mismatch or unfinished primary observer"))}
  let empty=Self{host:Arc::clone(&self.host),primary:None,records:Records{rows:Vec::new(),credit:None},diagnostics:Diagnostics{rows:Vec::new(),credit:None},good:0,bad:0,failed_prefix:None,credit:a.reserve(0)?};
  Ok(CommittedHeaderAdoption{preparation:std::mem::replace(self,empty)})
 }

 fn failed_prefix(&mut self,mut input:dm_syntax::OriginalCommittedBodyInput<'_,'_>,_:&OriginalNoticeRegistration,a:&SettingAdmission<'_>)->io::Result<()>{self.bind_primary(&input,a)?;let producer=input.take_primary_producer().ok_or_else(||io::Error::new(io::ErrorKind::InvalidInput,"actual failed-prefix producer was already taken"))?;self.retain_primary(producer)?;self.failed_prefix=Some(input.item().header_span);Ok(())}
 fn produce(&mut self,input:dm_syntax::OriginalCommittedBodyInput<'_,'_>,parameters:dm_syntax::SharedParameterSignature,registration:&OriginalNoticeRegistration,producer:&dm_syntax::OriginalPrimaryProducerIdentity,a:&SettingAdmission<'_>)->io::Result<()>{
  self.bind_primary(&input,a)?;if self.failed_prefix.is_some(){return Err(io::Error::new(io::ErrorKind::InvalidInput,"actual BODY follows a failed structural prefix"))}
  let header=input.item().header_span;let body=input.item().span;
  if self.records.rows.last().is_some_and(|prior|prior.header.start>=header.start){return Err(io::Error::new(io::ErrorKind::InvalidInput,"actual committed BODY order repeats or reverses"))}
  self.records.reserve_one(a)?;
  let code=super::relative_declarations::issue_committed_body_code(&input,producer,a)?;
  let allowance=header.end.checked_sub(header.start).and_then(|width|width.checked_mul(128)).and_then(|bytes|bytes.checked_add(1024)).ok_or(io::ErrorKind::OutOfMemory)?;
  let early=body_queries::issue_unsettled_body_admitted(body,Arc::clone(&code.identity),allowance,a).map_err(failure)?;
  let settings=CommittedSettingRoots::from_actual_item(input.item(),a)?;
  let mut loan=Some(input);let mut traversal=None;let mut retained_producer=None;
  let product=self.host.syntax_product_at_committed_input(&early,a,&mut|actual|{
   let input=loan.take().ok_or_else(||BodySyntaxFailure::Operational(io::Error::new(io::ErrorKind::InvalidInput,"actual BODY first producer repeated")))?;
   let(product,report,producer)=early.parse_at_committed_primary(input,&code,parameters.clone(),settings.as_deref(),actual)?;traversal=Some(report);retained_producer=Some(producer);Ok(product)
  }).map_err(failure)?;
  let traversal=traversal.ok_or_else(||io::Error::new(io::ErrorKind::InvalidData,"actual committed BODY first producer was omitted"))?;
  self.retain_primary(retained_producer.ok_or_else(||io::Error::new(io::ErrorKind::InvalidData,"actual committed BODY producer identity was omitted"))?)?;
  match traversal{
   dm_syntax::NativeBodySyntaxTraversal::Parsed=>self.good=self.good.checked_add(1).ok_or(io::ErrorKind::OutOfMemory)?,
   dm_syntax::NativeBodySyntaxTraversal::Rejected=>{let first=match product.as_ref(){OriginalBodySyntaxProduct::Parsed(syntax)=>syntax.statements.parsed().diagnostics.first().ok_or_else(||io::Error::new(io::ErrorKind::InvalidData,"local bad BODY omitted its actual first diagnostic"))?,OriginalBodySyntaxProduct::Rejected(error)=>error.original_diagnostic()};self.retain_first_error(header,first,registration,a)?;self.bad=self.bad.checked_add(1).ok_or(io::ErrorKind::OutOfMemory)?;},
   dm_syntax::NativeBodySyntaxTraversal::Unissued=>return Err(io::Error::new(io::ErrorKind::Unsupported,"unissued BODY cannot count as a parsed procedure")),
  }
  self.records.rows.push(Record{header,input:early,parameters,settings});checkpoint(a)
 }
}

/// Preparation-owned existing slots, transferred to the final typed footprint
/// roster by exact header/value occurrence. No BODY AST is retained here.
pub(crate) struct CommittedSettingRoots{headers:Vec<Span>,pub(crate) slots:dm_syntax::SettingExpressionSlots,_credit:SettingRootLease}
impl CommittedSettingRoots{
 fn from_actual_item(item:&dm_syntax::Item,a:&SettingAdmission<'_>)->io::Result<Option<Box<Self>>>{
  fn count(items:dm_syntax::OriginalItems<'_>,a:&SettingAdmission<'_>)->io::Result<usize>{let mut n=0usize;for item in items.iter(){checkpoint(a)?;let children=count(item.children(),a)?;n=n.checked_add(1).and_then(|n|n.checked_add(children)).ok_or(io::ErrorKind::OutOfMemory)?;}Ok(n)}
  let items=dm_syntax::OriginalItems::from_items(&item.children);let count=count(items,a)?;if count==0{return Ok(None)}
  let(mut headers,mut credit)=crate::procedure::original_primary_signatures::allocate_funded_rows::<Span>(count,a)?;
  super::relative_declarations::setting_spans_in_items(items,&mut headers);if headers.len()!=count||headers.windows(2).any(|pair|pair[0].start>=pair[1].start){return Err(io::ErrorKind::InvalidData.into())}
  a.grow(&mut credit,std::mem::size_of::<Self>())?;
  Ok(Some(Box::new(Self{headers,slots:Default::default(),_credit:credit})))
 }
 pub(crate) fn obtain(&self,header:Span,a:&SettingAdmission<'_>,produce:impl FnOnce()->Result<(dm_syntax::SettingExpression,Option<dm_syntax::NativeExpressionParserFacts>),dm_syntax::SettingSyntaxFailure>)->Result<(dm_syntax::SettingExpression,Option<dm_syntax::NativeExpressionParserFacts>),dm_syntax::SettingSyntaxFailure>{
  let ordinal=self.headers.binary_search_by_key(&header.start,|span|span.start).map_err(|_|dm_syntax::SettingSyntaxFailure::Operational(io::Error::new(io::ErrorKind::InvalidInput,"setting is absent from actual committed context inventory")))?;
  if self.headers[ordinal]!=header{return Err(dm_syntax::SettingSyntaxFailure::Operational(io::Error::new(io::ErrorKind::InvalidInput,"committed setting header extent differs")))}
  self.slots.obtain_with_native_observation(ordinal,self.headers.len(),a,produce)
 }
 pub(crate) fn produced(&self,header:Span,a:&SettingAdmission<'_>)->Result<(dm_syntax::SettingExpression,Option<dm_syntax::NativeExpressionParserFacts>),dm_syntax::SettingSyntaxFailure>{self.obtain(header,a,||Err(dm_syntax::SettingSyntaxFailure::Operational(io::Error::new(io::ErrorKind::Unsupported,"actual committed setting first writer is unissued"))))}
}

struct WeakBody{end:usize,input:Arc<super::BodySyntaxInputWeak>}
/// Same final literal owner plus weak Input locators only. It is not an AST cache.
pub(crate) struct CommittedHeaderProducts{
 literal:dm_preprocess::regions::OriginalLiteralSourceView,primary:Option<dm_syntax::OriginalPrimaryProducerIdentity>,
 bodies:Vec<WeakBody>,inputs:std::sync::Weak<[Arc<BodySyntaxInput>]>,settings:std::sync::Mutex<Vec<Option<Box<CommittedSettingRoots>>>>,
 diagnostics:Diagnostics,good:usize,bad:usize,failed_prefix:Option<Span>,
 credit:SettingRootLease,
}
pub(crate) struct FinalCommittedBodyInputs{host:Arc<dyn BodySyntaxQueries>,inputs:Arc<[Arc<BodySyntaxInput>]>}
pub(crate) struct CommittedHeaderAdoption{preparation:CommittedBodyPreparation}
pub(crate) struct CommittedHeaderInstallation{
 pub(crate) products:Arc<CommittedHeaderProducts>,pub(crate) parameters:Vec<dm_syntax::SharedParameterSignature>,pub(crate) parameter_credit:SettingRootLease,
 pub(crate) inputs:Box<std::sync::Mutex<Option<FinalCommittedBodyInputs>>>,
}
fn empty_rows<T>(count:usize,a:&SettingAdmission<'_>)->io::Result<(Vec<T>,Option<SettingRootLease>)>{if count==0{Ok((Vec::new(),None))}else{let(rows,credit)=crate::procedure::original_primary_signatures::allocate_funded_rows(count,a)?;Ok((rows,Some(credit)))}}
fn absorb_optional(a:&SettingAdmission<'_>,target:&mut SettingRootLease,source:&mut Option<SettingRootLease>)->io::Result<()>{if let Some(source)=source{a.absorb(target,source)?}Ok(())}
fn arc_array<T>(count:usize)->io::Result<usize>{let payload=std::alloc::Layout::array::<T>(count).map_err(|_|io::ErrorKind::OutOfMemory)?;let(layout,_)=std::alloc::Layout::new::<[std::sync::atomic::AtomicUsize;2]>().extend(payload).map_err(|_|io::ErrorKind::OutOfMemory)?;Ok(layout.pad_to_align().size())}
impl CommittedHeaderAdoption{
 pub(crate) fn install(mut self,source:&dm_preprocess::SourceText,headers:&[Span],literal:dm_preprocess::regions::OriginalLiteralSourceView,a:&SettingAdmission<'_>)->io::Result<CommittedHeaderInstallation>{
  checkpoint(a)?;let p=&mut self.preparation;
  let primary=p.primary.take();
  let count=p.records.rows.len();if p.good.checked_add(p.bad)!=Some(count){return Err(io::ErrorKind::InvalidData.into())}
  if p.failed_prefix.is_some(){return Err(io::Error::new(io::ErrorKind::Unsupported,"structural prefix has no completed committed BODY adoption"))}
  if headers.len()!=count||(count!=0&&primary.is_none())||p.records.rows.iter().zip(headers).any(|(row,header)|row.header!=*header){
   return Err(io::Error::new(io::ErrorKind::InvalidInput,"committed BODY/header final occurrence inventory differs"))
  }
  for row in &p.diagnostics.rows{checkpoint(a)?;if headers.binary_search_by_key(&row.header.start,|header|header.start).ok().and_then(|index|headers.get(index)).is_none_or(|header|*header!=row.header)||row.diagnostic.span.start>row.diagnostic.span.end||row.diagnostic.span.end>source.len(){return Err(trace_invalid_input("committed-install: diagnostic header membership or diagnostic span escapes source"))}}
  let facts=literal.checked_facts(source)?;if !facts.admitted_by(a){return Err(trace_invalid_input("committed-install: literal facts belong to another SettingAdmission"))}
  let(mut bodies,mut bodies_credit)=empty_rows::<WeakBody>(count,a)?;
  let(mut parameters,parameter_credit)=empty_rows::<dm_syntax::SharedParameterSignature>(count,a)?;
  let(mut settings,mut settings_credit)=empty_rows::<Option<Box<CommittedSettingRoots>>>(count,a)?;
  let(mut inputs,mut inputs_credit)=empty_rows::<Arc<BodySyntaxInput>>(count,a)?;
  absorb_optional(a,&mut p.credit,&mut bodies_credit)?;absorb_optional(a,&mut p.credit,&mut settings_credit)?;absorb_optional(a,&mut p.credit,&mut inputs_credit)?;
  for row in p.records.rows.drain(..){checkpoint(a)?;let body=row.input.captured_span();if body.start!=row.header.start||body.end>source.len()||body.end<row.header.end{return Err(trace_invalid_input("committed-install: captured BODY span differs from header/source extent"))}bodies.push(WeakBody{end:body.end,input:row.input.weak_allocation_owner()});parameters.push(row.parameters);settings.push(row.settings);inputs.push(row.input);}
  // Vec backing retires before its row credit; all actual children have moved.
  drop(std::mem::take(&mut p.records.rows));p.records.credit=None;
  let input_vec_bytes=inputs.capacity().checked_mul(std::mem::size_of::<Arc<BodySyntaxInput>>()).ok_or(io::ErrorKind::OutOfMemory)?;
  a.grow(&mut p.credit,arc_array::<Arc<BodySyntaxInput>>(count)?)?;
  let inputs:Arc<[Arc<BodySyntaxInput>]>=inputs.into();a.shrink(&mut p.credit,input_vec_bytes)?;
  a.grow(&mut p.credit,arc_array::<CommittedHeaderProducts>(1)?.checked_add(std::mem::size_of::<std::sync::Mutex<Option<FinalCommittedBodyInputs>>>()).ok_or(io::ErrorKind::OutOfMemory)?)?;
  let host=Arc::clone(&p.host);let diagnostics=std::mem::replace(&mut p.diagnostics,Diagnostics{rows:Vec::new(),credit:None});
  let credit=std::mem::replace(&mut p.credit,a.reserve(0)?);
  let products=Arc::new(CommittedHeaderProducts{literal,primary,bodies,inputs:Arc::downgrade(&inputs),settings:std::sync::Mutex::new(settings),diagnostics,good:p.good,bad:p.bad,failed_prefix:p.failed_prefix,credit});
  let parameter_credit=match parameter_credit{Some(actual)=>actual,None=>a.reserve(0)?};
  Ok(CommittedHeaderInstallation{products,parameters,parameter_credit,inputs:Box::new(std::sync::Mutex::new(Some(FinalCommittedBodyInputs{host,inputs})))})
 }
}
impl CommittedHeaderProducts{
 // Resource-only census of the actual unique locators moved from strictly
 // increasing producer Records. Each locator owns its own Input lease once.
 pub(crate) fn input_resource_summary(&self)->(usize,usize,usize,Option<usize>,usize){
  let(mut live,mut missing,mut sum)=(0usize,0usize,Some(0usize));
  for row in &self.bodies{
   if row.input.strong_count()!=0{live+=1;}
   match row.input.allocation_credit(){Some(credit)=>{sum=sum.and_then(|total|total.checked_add(credit.bytes()));},None=>missing+=1}
  }
  (self.bodies.len(),live,self.credit.bytes(),sum,missing)
 }

 pub(crate) fn literal_view(&self)->&dm_preprocess::regions::OriginalLiteralSourceView{&self.literal}
 pub(crate) fn body_code(&self,index:usize,span:Span)->io::Result<Option<Arc<BodyCodeIdentity>>>{
  let Some(row)=self.bodies.get(index)else{if self.failed_prefix.is_some_and(|failed|span.start>=failed.start){return Ok(None)}return Err(io::Error::new(io::ErrorKind::InvalidInput,"actual committed BODY Input row is absent"))};
  let input=row.input.upgrade().ok_or_else(||io::Error::new(io::ErrorKind::NotConnected,"actual committed BODY Input owner expired before capture"))?;
  if row.end!=span.end||input.captured_span()!=span{return Err(trace_invalid_input("committed-body-code: requested span differs from captured BODY input"))}
  input.original_code_owner().cloned().map(Some).ok_or_else(||io::Error::new(io::ErrorKind::InvalidInput,"actual committed BODY code owner is absent"))
 }
 pub(crate) fn produced_setting(&self,index:usize,header:Span,a:&SettingAdmission<'_>)->Result<(dm_syntax::SettingExpression,Option<dm_syntax::NativeExpressionParserFacts>),dm_syntax::SettingSyntaxFailure>{
  let settings=self.settings.lock().map_err(|_|dm_syntax::SettingSyntaxFailure::Operational(io::Error::other("committed setting transfer poisoned")))?;
  settings.get(index).and_then(Option::as_ref).ok_or_else(||dm_syntax::SettingSyntaxFailure::Operational(io::Error::new(io::ErrorKind::Unsupported,"actual committed setting preparation absent")))?.produced(header,a)
 }
 pub(crate) fn finish_settings_transfer(&self,index:usize)->io::Result<()>{let mut settings=self.settings.lock().map_err(|_|io::Error::other("committed setting transfer poisoned"))?;if let Some(slot)=settings.get_mut(index){drop(slot.take());}Ok(())}
}

impl FinalCommittedBodyInputs{
 pub(super) fn adopt(self,mut frontend:ColdFrontend,expected:&Arc<dyn BodySyntaxQueries>,a:&SettingAdmission<'_>)->Result<ColdFrontend,BodySyntaxFailure>{
  checkpoint(a).map_err(BodySyntaxFailure::Operational)?;
  if !Arc::ptr_eq(&self.host,expected)||self.inputs.len()!=frontend.issued_bodies.len(){return Err(BodySyntaxFailure::Operational(io::Error::new(io::ErrorKind::InvalidInput,"committed final BODY host/input inventory differs")))}
  for(index,input)in self.inputs.iter().enumerate(){checkpoint(a).map_err(BodySyntaxFailure::Operational)?;input.settle_for_final_frontend(&frontend,index)?;}
  // The complete actual roster has settled above. Observe these existing
  // unique Input grants once per adoption; no pressure cursor or extra state.
  if std::env::var_os("DMB_ORIGINAL_TRACE_BODY_PRESSURE").is_some(){
   use std::io::Write as _;
   let(mut sum,mut missing)=(Some(0usize),0usize);
   for input in self.inputs.iter(){match input.committed_allocation_credit(){Some(credit)=>{sum=sum.and_then(|total|total.checked_add(credit.bytes()));},None=>missing+=1}}
   let mut output=std::io::stderr().lock();
   let _=writeln!(output,"ORIGINAL_BODY_OWNER_DIAGNOSTIC trigger=settled_committed_adoption unique_inputs={} input_grant_sum={sum:?} missing_input_grants={missing}",self.inputs.len());
   if let Some(input)=self.inputs.first(){input.write_admission_failure_context(&mut output);}else{let _=writeln!(output,"ORIGINAL_BODY_OWNER_DIAGNOSTIC settled_context=empty_roster");}
  }
  self.host.begin_revision_inputs(&self.inputs);
  frontend.body_queries=Some(body_queries::BodyQueries{host:self.host,inputs:body_queries::BodyQueryInputs::eager_admitted(self.inputs,a)?});frontend.reused_body_queries=false;
  checkpoint(a).map_err(BodySyntaxFailure::Operational)?;Ok(frontend)
 }
}
impl ColdFrontend{
 pub(super) fn adopt_committed_body_queries(self,expected:&Arc<dyn BodySyntaxQueries>,a:&SettingAdmission<'_>)->Result<Self,BodySyntaxFailure>{
  let primary=self.original_primary.as_ref().ok_or_else(||BodySyntaxFailure::Operational(io::Error::new(io::ErrorKind::InvalidInput,"committed BODY preparation lacks actual primary retention")))?;
  let inputs=primary.take_committed_inputs().map_err(BodySyntaxFailure::Operational)?.ok_or_else(||BodySyntaxFailure::Operational(io::Error::new(io::ErrorKind::InvalidInput,"actual committed BODY Input handoff absent")))?;
  inputs.adopt(self,expected,a)
 }
}

impl CommittedHeaderProducts{
 pub(crate) fn counts(&self)->(usize,usize){(self.good,self.bad)}
 pub(crate) fn visit_first_diagnostics<'a>(&'a self,checkpoint:&dyn Fn()->io::Result<()>,consume:&mut dyn FnMut(Span,&'a dm_syntax::Diagnostic,&'a OriginalNoticeRegistration)->io::Result<()>)->io::Result<()>{for row in &self.diagnostics.rows{checkpoint()?;consume(row.header,&row.diagnostic,&row.registration)?}Ok(())}
}

impl CommittedHeaderProducts{
 pub(crate) fn visit_storage(&self,a:Option<&SettingAdmission<'_>>,visit:&mut dyn FnMut(usize,usize,usize,bool)){
  let owned=a.is_some_and(|a|a.matches_lease_domain(&self.credit));
  visit(self as *const Self as usize,std::mem::size_of::<Self>(),arc_array::<Self>(1).expect("static committed Header Arc layout"),owned);
  if let Some(primary)=&self.primary{primary.visit_storage(|p,n,c|visit(p,n,c,owned));}
  if self.bodies.capacity()!=0{visit(self.bodies.as_ptr()as usize,self.bodies.len()*std::mem::size_of::<WeakBody>(),self.bodies.capacity()*std::mem::size_of::<WeakBody>(),owned)}
  visit(self.inputs.as_ptr()as *const Arc<BodySyntaxInput> as usize,if self.inputs.strong_count()!=0{self.bodies.len()*std::mem::size_of::<Arc<BodySyntaxInput>>()}else{0},arc_array::<Arc<BodySyntaxInput>>(self.bodies.len()).expect("actual committed Input array layout"),owned);
  for body in &self.bodies{
   let live=body.input.upgrade();let credit=body.input.allocation_credit();let tail_owned=a.is_some_and(|a|credit.is_some_and(|credit|a.matches_lease_domain(credit)));let mut counter_pointer=0;if let Some(credit)=credit{credit.visit_counter_storage(|p,_|counter_pointer=p);}
   body.input.visit_allocation_storage(&mut|p,n,c|visit(p,n,c,tail_owned&&p!=counter_pointer));
   if let Some(input)=live{if let Some(code)=input.original_code_owner(){let lease=code.committed_allocation_credit();let code_owned=a.is_some_and(|a|lease.is_some_and(|credit|a.matches_lease_domain(credit)));let mut code_counter=0;if let Some(credit)=lease{credit.visit_counter_storage(|p,_|code_counter=p);}code.visit_allocation_storage(&mut|p,n,c|visit(p,n,c,code_owned&&p!=code_counter));}}
  }
  if self.diagnostics.rows.capacity()!=0{visit(self.diagnostics.rows.as_ptr()as usize,self.diagnostics.rows.len()*std::mem::size_of::<DiagnosticRow>(),self.diagnostics.rows.capacity()*std::mem::size_of::<DiagnosticRow>(),owned)}
  for row in &self.diagnostics.rows{if row.diagnostic.message.capacity()!=0{visit(row.diagnostic.message.as_ptr()as usize,row.diagnostic.message.len(),row.diagnostic.message.capacity(),owned)}row.registration.visit_storage(&mut|p,n,c|visit(p,n,c,owned));}
  if let Ok(settings)=self.settings.lock(){
   if settings.capacity()!=0{visit(settings.as_ptr()as usize,settings.len()*std::mem::size_of::<Option<Box<CommittedSettingRoots>>>(),settings.capacity()*std::mem::size_of::<Option<Box<CommittedSettingRoots>>>(),owned)}
   for roots in settings.iter().flatten(){visit(&**roots as *const CommittedSettingRoots as usize,std::mem::size_of::<CommittedSettingRoots>(),std::mem::size_of::<CommittedSettingRoots>(),owned);roots.visit_storage(visit,owned);}
  }
  self.credit.visit_counter_storage(|p,n|visit(p,n,n,false));
 }
}
impl CommittedSettingRoots{
 fn visit_storage(&self,visit:&mut dyn FnMut(usize,usize,usize,bool),owned:bool){
  if self.headers.capacity()!=0{visit(self.headers.as_ptr()as usize,self.headers.len()*std::mem::size_of::<Span>(),self.headers.capacity()*std::mem::size_of::<Span>(),owned)}
  let visitor=std::cell::RefCell::new(visit);
  self.slots.visit_storage(|p,n,c|(visitor.borrow_mut())(p,n,c,owned),|root|{root.visit_root_storage(|p,n|(visitor.borrow_mut())(p,n,n,owned));root.visit_retention_storage(|p,n|(visitor.borrow_mut())(p,n,n,owned));});
 }
}
impl FinalCommittedBodyInputs{
 pub(super) fn visit_storage(&self,visit:&mut dyn FnMut(usize,usize,usize)){
  visit(self.inputs.as_ptr()as usize,self.inputs.len()*std::mem::size_of::<Arc<BodySyntaxInput>>(),arc_array::<Arc<BodySyntaxInput>>(self.inputs.len()).expect("actual committed Input array layout"));
 }
}

impl CommittedHeaderProducts{pub(crate) fn input_key(&self,index:usize)->io::Result<u64>{self.bodies.get(index).and_then(|row|row.input.upgrade()).map(|input|input.key()).ok_or_else(||io::Error::new(io::ErrorKind::NotConnected,"actual committed Input owner is unavailable"))}}

// Report-only fatal-prefix handoff. No unresolved Input is settled or exported.
pub(crate) struct CommittedPrefixAdoption{preparation:CommittedBodyPreparation}
pub(crate) struct CommittedPrefixProducts{
 literal:dm_preprocess::regions::OriginalLiteralSourceView,
 primary:Option<dm_syntax::OriginalPrimaryProducerIdentity>,
 diagnostics:Diagnostics,good:usize,bad:usize,
 // LAST: actual diagnostic rows/strings/producer retire before their credit.
 credit:SettingRootLease,
}
pub(crate) struct CommittedPrefixInstallation{pub(crate) products:Arc<CommittedPrefixProducts>,pub(crate) parameters:Vec<dm_syntax::SharedParameterSignature>,pub(crate) parameter_credit:SettingRootLease}
impl CommittedBodyPreparation{
 fn take_formal_prefix(&mut self,primary:&dm_preprocess::regions::OriginalStreamPrimary,a:&SettingAdmission<'_>)->io::Result<CommittedPrefixAdoption>{
  checkpoint(a)?;
  if primary.observer_stop().is_none()||self.failed_prefix.is_some()||self.primary.as_ref().is_some_and(|owner|!primary.same_primary_producer(owner)){return Err(io::Error::new(io::ErrorKind::Unsupported,"report-only BODY prefix requires the same actual formal stop, not structural TT failure"))}
  let empty=Self{host:Arc::clone(&self.host),primary:None,records:Records{rows:Vec::new(),credit:None},diagnostics:Diagnostics{rows:Vec::new(),credit:None},good:0,bad:0,failed_prefix:None,credit:a.reserve(0)?};
  Ok(CommittedPrefixAdoption{preparation:std::mem::replace(self,empty)})
 }
}
impl CommittedPrefixAdoption{
 pub(crate) fn install(mut self,source:&dm_preprocess::SourceText,headers:&[Span],literal:dm_preprocess::regions::OriginalLiteralSourceView,a:&SettingAdmission<'_>)->io::Result<CommittedPrefixInstallation>{
  checkpoint(a)?;let p=&mut self.preparation;let count=p.records.rows.len();
  if p.failed_prefix.is_some()||p.good.checked_add(p.bad)!=Some(count)||headers.len()!=count||(count!=0&&p.primary.is_none())||p.records.rows.iter().zip(headers).any(|(row,header)|row.header!=*header){return Err(io::Error::new(io::ErrorKind::InvalidInput,"actual report-only prefix header inventory differs"))}
  if !literal.checked_facts(source)?.admitted_by(a){return Err(trace_invalid_input("committed-prefix-install: literal facts belong to another SettingAdmission"))}
  for row in &p.diagnostics.rows{checkpoint(a)?;if headers.binary_search_by_key(&row.header.start,|header|header.start).ok().and_then(|index|headers.get(index)).is_none_or(|header|*header!=row.header)||row.diagnostic.span.start>row.diagnostic.span.end||row.diagnostic.span.end>source.len(){return Err(trace_invalid_input("committed-prefix-install: diagnostic header membership or span escapes prefix source"))}}
  let(mut parameters,parameter_credit)=empty_rows::<dm_syntax::SharedParameterSignature>(count,a)?;
  for row in p.records.rows.drain(..){checkpoint(a)?;let body=row.input.captured_span();if body.start!=row.header.start||body.end>source.len()||body.end<row.header.end{return Err(trace_invalid_input("committed-prefix-install: captured BODY span differs from header/prefix extent"))}parameters.push(row.parameters);drop(row.input);drop(row.settings);}
  drop(std::mem::take(&mut p.records.rows));p.records.credit=None;
  a.grow(&mut p.credit,arc_array::<CommittedPrefixProducts>(1)?)?;
  let diagnostics=std::mem::replace(&mut p.diagnostics,Diagnostics{rows:Vec::new(),credit:None});
  let credit=std::mem::replace(&mut p.credit,a.reserve(0)?);
  let products=Arc::new(CommittedPrefixProducts{literal,primary:p.primary.take(),diagnostics,good:p.good,bad:p.bad,credit});
  Ok(CommittedPrefixInstallation{products,parameters,parameter_credit:match parameter_credit{Some(credit)=>credit,None=>a.reserve(0)?}})
 }
}
impl CommittedPrefixProducts{
 pub(crate) fn literal_view(&self)->&dm_preprocess::regions::OriginalLiteralSourceView{&self.literal}
 pub(crate) fn counts(&self)->(usize,usize){(self.good,self.bad)}
 pub(crate) fn visit_first_diagnostics<'a>(&'a self,checkpoint:&dyn Fn()->io::Result<()>,consume:&mut dyn FnMut(Span,&'a dm_syntax::Diagnostic,&'a OriginalNoticeRegistration)->io::Result<()>)->io::Result<()>{for row in &self.diagnostics.rows{checkpoint()?;consume(row.header,&row.diagnostic,&row.registration)?}Ok(())}
 pub(crate) fn visit_storage(&self,a:Option<&SettingAdmission<'_>>,visit:&mut dyn FnMut(usize,usize,usize,bool)){
  let owned=a.is_some_and(|a|a.matches_lease_domain(&self.credit));visit(self as *const Self as usize,std::mem::size_of::<Self>(),arc_array::<Self>(1).expect("actual report-only prefix Arc layout"),owned);
  if let Some(primary)=&self.primary{primary.visit_storage(|p,n,c|visit(p,n,c,owned));}
  if self.diagnostics.rows.capacity()!=0{visit(self.diagnostics.rows.as_ptr()as usize,self.diagnostics.rows.len()*std::mem::size_of::<DiagnosticRow>(),self.diagnostics.rows.capacity()*std::mem::size_of::<DiagnosticRow>(),owned)}
  for row in &self.diagnostics.rows{if row.diagnostic.message.capacity()!=0{visit(row.diagnostic.message.as_ptr()as usize,row.diagnostic.message.len(),row.diagnostic.message.capacity(),owned)}row.registration.visit_storage(&mut|p,n,c|visit(p,n,c,owned));}self.credit.visit_counter_storage(|p,n|visit(p,n,n,false));
 }
}

// Conditional diagnostics for existing pure invariant failures. No new grant,
// guard, fallback or changed default error bytes; OS failures never enter here.
pub(super)fn trace_invalid_input(label:&'static str)->io::Error{
 invalid_input_diagnostic(label,std::env::var_os("DMB_ORIGINAL_TRACE_STAGES").is_some())
}
fn invalid_input_diagnostic(label:&'static str,trace:bool)->io::Error{
 if trace{io::Error::new(io::ErrorKind::InvalidInput,label)}else{io::ErrorKind::InvalidInput.into()}
}
#[cfg(test)]mod invariant_diagnostic_controls{
 #[test]fn conditional_invariant_diagnostics_keep_kind_and_default_bytes(){
  let original=std::io::Error::from(std::io::ErrorKind::InvalidInput);let off=super::invalid_input_diagnostic("actual-invariant",false);let on=super::invalid_input_diagnostic("actual-invariant",true);
  assert_eq!(off.to_string(),original.to_string());assert_eq!(off.kind(),original.kind());assert_eq!(off.raw_os_error(),original.raw_os_error());assert!(off.get_ref().is_none());assert_eq!(on.kind(),original.kind());assert_eq!(on.raw_os_error(),None);assert_eq!(on.to_string(),"actual-invariant");
 }
}
