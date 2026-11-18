use super::*;
use std::sync::atomic::Ordering;

struct Output;
impl crate::OriginalLiteralOutputOwner for Output{
 fn as_any(&self)->&dyn std::any::Any{self}
 fn release(self:Arc<Self>){drop(Arc::into_inner(self));}
 fn visit_storage(&self,_:&mut dyn FnMut(usize,usize,usize)){}
}
struct Fixture{
 facts:OriginalPrimaryLiteralFacts,source:String,
 alias:Option<crate::OriginalLiteralData>,filler:crate::OriginalLiteralData,
 output:crate::OriginalLiteralProjectionOwner,
 owners:Vec<(usize,usize,usize,usize)>,raw_bytes:usize,
}
fn fixture(a:&crate::SettingAdmission<'_>)->Fixture{
 let output=crate::OriginalLiteralProjectionOwner::from_output_data(Arc::new(Output));
 let mut facts=OriginalPrimaryLiteralFacts::new(a).unwrap();facts.enable_projection(output.clone()).unwrap();
 // Resource DATA has no lexical string mode. Actual String and the three
 // interpolation token kinds carry the producer's Normal string mode.
 let cases=[
  ("\"escaped\\ntext\"",crate::OriginalTokenValue::String("escaped\ntext"),crate::OriginalStringMode::Normal),
  ("'sound\\'quote.ogg'",crate::OriginalTokenValue::Resource("sound'quote.ogg"),crate::OriginalStringMode::Unknown),
  ("\"head\\n[",crate::OriginalTokenValue::InterpBegin("head\n"),crate::OriginalStringMode::Normal),
  ("]middle\\t[",crate::OriginalTokenValue::InterpPart("middle\t"),crate::OriginalStringMode::Normal),
  ("]tail\\n\"",crate::OriginalTokenValue::InterpEnd("tail\n"),crate::OriginalStringMode::Normal),
 ];
 let mut source=String::new();let mut spans=Vec::new();let mut slots=Vec::new();
 for(raw,value,mode)in cases{
  let start=source.len();source.push_str(raw);source.push('\n');spans.push(Span::new(start,start+raw.len()));
  let data=crate::OriginalLiteralData::from_value_with_mode_using(raw.to_owned(),value,mode,a).unwrap();
  assert_eq!(data.string_mode(),mode,"actual typed producer mode survives construction");slots.push(Some(data));
 }
 crate::OriginalLiteralData::pack_delivery_batch_using(&mut slots,a).unwrap();
 let alias=slots[0].as_ref().unwrap().clone();let key=alias.as_view().page_storage_identity().expect("real packed body bank");
 let mut owners=Vec::new();let mut raw_bytes=0;
 for(span,data)in spans.into_iter().zip(slots){
  let data=data.unwrap();assert_eq!(data.as_view().page_storage_identity(),Some(key));
  let value_pointer=match data.value(){crate::OriginalTokenValue::String(v)|crate::OriginalTokenValue::Resource(v)|crate::OriginalTokenValue::InterpBegin(v)|crate::OriginalTokenValue::InterpPart(v)|crate::OriginalTokenValue::InterpEnd(v)=>v.as_ptr()as usize,_=>panic!("cooked text")};
  raw_bytes+=data.raw_storage().capacity();owners.push((data.as_view().owner_key(),data.as_view().ordinal(),value_pointer,data.raw().as_ptr()as usize));
  facts.append_actual(span,data,a).unwrap();
 }
 let filler=crate::OriginalLiteralData::from_value_using("0".into(),crate::OriginalTokenValue::Int(0),a).unwrap();
 for _ in owners.len()..LITERAL_PAGE_LEN{let start=source.len();source.push_str("0\n");facts.append_actual(Span::new(start,start+1),filler.clone(),a).unwrap();}
 {
  let page=&mut Arc::get_mut(facts.0.as_mut().unwrap()).unwrap().rows.chunks[0].pages[0];
  page.body[0]=(1<<owners.len())-1;page.data.settle_full_using(a).unwrap();
  assert_eq!(page.withdraw_compact_source_raw(&source,a).unwrap(),0,"the real delivery alias blocks early raw retirement");
 }
 facts.seal_actual_frontier(source.len(),a).unwrap();
 Fixture{facts,source,alias:Some(alias),filler,output,owners,raw_bytes}
}
fn assert_survivors(f:&Fixture){
 let page=&f.facts.payload().rows.chunks[0].pages[0];let loan=ProjectionLoan{source:&f.source,origin:0};
 for(index,&(owner,ordinal,cooked,old_raw))in f.owners.iter().enumerate(){
  let(span,data)=page.get_data(index,0,Some(loan),Some(&f.output)).unwrap();
  assert_eq!((data.owner_key(),data.ordinal()),(owner,ordinal));
  assert_eq!(data.raw().unwrap().as_ptr(),f.source[span.range()].as_ptr());assert_ne!(data.raw().unwrap().as_ptr()as usize,old_raw);
  let actual=match data.value().unwrap(){crate::OriginalTokenValue::String(v)|crate::OriginalTokenValue::Resource(v)|crate::OriginalTokenValue::InterpBegin(v)|crate::OriginalTokenValue::InterpPart(v)|crate::OriginalTokenValue::InterpEnd(v)=>v.as_ptr()as usize,_=>panic!("same cooked text")};assert_eq!(actual,cooked);
  let(_,unbound)=page.get_data(index,0,None,Some(&f.output)).unwrap();assert_eq!(unbound.raw().unwrap_err().kind(),io::ErrorKind::NotConnected);
 }
}

#[test]
fn actual_eof_raw_withdraw_retries_after_delivery_alias_and_keeps_cooked_identity(){
 let fixed=crate::SettingChargeCounter::root_allocation_bytes();let used=crate::SettingChargeCounter::try_new(fixed).unwrap();let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));
 let mut f=fixture(&a);let before=used.load(Ordering::Acquire);
 assert_eq!(f.facts.settle_delivered_body_payloads(&f.source,&a).unwrap(),0,"live escaped alias must remain untouched");assert_eq!(used.load(Ordering::Acquire),before);
 assert_eq!(f.alias.as_ref().unwrap().raw().as_ptr()as usize,f.owners[0].3);
 drop(f.alias.take());
 assert_eq!(f.facts.settle_delivered_body_payloads(&f.source,&a).unwrap(),f.raw_bytes);
 assert_eq!(used.load(Ordering::Acquire),before-f.raw_bytes,"only the physically freed raw Strings refund SAME-counter bytes");assert_survivors(&f);
 assert_eq!(f.facts.settle_delivered_body_payloads(&f.source,&a).unwrap(),0);assert_eq!(used.load(Ordering::Acquire),before-f.raw_bytes);
 let page=&f.facts.payload().rows.chunks[0].pages[0];let(_,bound)=page.get_data(0,0,Some(ProjectionLoan{source:&f.source,origin:0}),Some(&f.output)).unwrap();let detached=bound.detach_using(&a).unwrap();
 assert!(bound.same_owner(&detached));assert_ne!(detached.raw().as_ptr(),bound.raw().unwrap().as_ptr());
 drop(f);assert!(used.load(Ordering::Acquire)>fixed,"escaped copied raw + original cooked bank remain owned");
 assert!(matches!(detached.value(),crate::OriginalTokenValue::String("escaped\ntext")));drop(detached);assert_eq!(used.load(Ordering::Acquire),fixed);
}

#[test]
fn actual_eof_raw_withdraw_checks_source_domain_quota_and_first_io_before_retirement(){
 let fixed=crate::SettingChargeCounter::root_allocation_bytes();let used=crate::SettingChargeCounter::try_new(fixed).unwrap();let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));let mut f=fixture(&a);drop(f.alias.take());let before=used.load(Ordering::Acquire);
 let denied=crate::SettingAdmission::new(&used,before,&||Ok(()));assert_eq!(f.facts.settle_delivered_body_payloads(&f.source,&denied).unwrap(),0);assert_eq!(used.load(Ordering::Acquire),before);
 let other=crate::SettingChargeCounter::try_new(fixed).unwrap();let foreign=crate::SettingAdmission::new(&other,8<<20,&||Ok(()));assert_eq!(f.facts.settle_delivered_body_payloads(&f.source,&foreign).unwrap_err().kind(),io::ErrorKind::InvalidInput);assert_eq!(other.load(Ordering::Acquire),fixed);
 let mut wrong=f.source.clone();wrong.replace_range(1..2,"X");assert_eq!(f.facts.settle_delivered_body_payloads(&wrong,&a).unwrap_err().kind(),io::ErrorKind::InvalidData);assert_eq!(used.load(Ordering::Acquire),before);
 let polls=std::cell::Cell::new(0);let fault=||{polls.set(polls.get()+1);Err(io::Error::from_raw_os_error(1450))};let failed=crate::SettingAdmission::new(&used,8<<20,&fault);
 assert_eq!(f.facts.settle_delivered_body_payloads(&f.source,&failed).unwrap_err().raw_os_error(),Some(1450));assert_eq!(polls.get(),1);assert_eq!(used.load(Ordering::Acquire),before);
 let stop=crate::SettingAdmission::new(&used,8<<20,&||Err(io::ErrorKind::Interrupted.into()));assert_eq!(f.facts.settle_delivered_body_payloads(&f.source,&stop).unwrap_err().kind(),io::ErrorKind::Interrupted);assert_eq!(used.load(Ordering::Acquire),before);
 assert_eq!(f.facts.settle_delivered_body_payloads(&f.source,&a).unwrap(),f.raw_bytes);assert_survivors(&f);drop(f);assert_eq!(used.load(Ordering::Acquire),fixed);
}
