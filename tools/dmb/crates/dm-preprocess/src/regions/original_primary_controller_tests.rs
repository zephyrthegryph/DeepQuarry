//! Real raw-driver -> primary producer controls. No alternate lexer/parser.
use super::*;
use super::super::{original_ordinary_output::OriginalOrdinaryOutput,original_output_queue::OriginalOutputQueue,original_token_factory,original_raw_frame::OriginalRawNotice,original_raw_points::OriginalRawPoint,OriginalLexicalFrameIdentity};
use crate::{SourceAcquisitionLease,InitialEnvironment,source_arena_credit::{SourceArenaWork,SourceArenaCredit,SourceArenaCreditOwner},macro_expansion::{OriginalMacroDefinition,OriginalMacroDoc,OriginalMacroRows}};
use std::{path::Path,collections::BTreeMap,sync::{Arc,atomic::{AtomicUsize,Ordering}},any::Any};
struct File{raw:Vec<u8>,lease:SourceAcquisitionLease}
impl File{fn new(text:&str)->Self{Self{raw:text.as_bytes().to_vec(),lease:SourceAcquisitionLease::from_raw_original_bytes(text.as_bytes().to_vec(),17u64)}}}
impl SourceProvider for File{
 fn read(&self,_:&Path)->Result<String,String>{panic!("actual primary must not call decoded read")}
 fn original_source_bytes<'a>(&'a self,lease:&'a SourceAcquisitionLease)->io::Result<Option<&'a[u8]>>{if !lease.same_original_acquisition(&self.lease){return Err(io::ErrorKind::InvalidInput.into())}Ok(Some(&self.raw))}
}
struct Notices{lexical:usize,numeric:usize}
impl OriginalRawNoticeSink for Notices{
 fn lexical(&mut self,_:&OriginalLexicalFrameIdentity,_:usize,_:OriginalRawPoint,_:OriginalRawNotice,_:&SettingAdmission<'_>)->io::Result<()>{self.lexical+=1;Ok(())}
 fn numeric(&mut self,_:&OriginalLexicalFrameIdentity,_:usize,_:OriginalRawPoint,_:dm_syntax::OriginalLexicalNoticePoint,_:dm_syntax::numeric_form::OriginalNumberNotice<'_>,_:&SettingAdmission<'_>)->io::Result<()>{self.numeric+=1;Ok(())}
}
struct Host(OriginalOrdinaryOutput);
impl Host{fn new(a:&SettingAdmission<'_>)->Self{Self(OriginalOrdinaryOutput::new(a).unwrap())}}
impl OriginalMacroHost for Host{
 fn take_docs_for_define(&mut self,a:&SettingAdmission<'_>)->io::Result<OriginalMacroRows<OriginalMacroDoc<'static>>>{self.0.take_docs_for_define(a)}
 fn before_identifier(&mut self,name:&str,origin:Origin,queue:&mut OriginalOutputQueue<'static>,a:&SettingAdmission<'_>)->io::Result<()>{self.0.before_identifier(name,origin,queue,a)}
 fn ordinary_token(&mut self,token:Token<'static>,queue:&mut OriginalOutputQueue<'static>,a:&SettingAdmission<'_>)->io::Result<()>{self.0.ordinary_token(token,queue,a)}
 fn direct_noncall_output(&mut self,token:&Token<'static>,a:&SettingAdmission<'_>)->io::Result<()>{self.0.direct_noncall_output(token,a)}
 fn dynamic(&mut self,_:bool,_:Origin,_:Option<usize>,_:Option<Origin>,_:&SettingAdmission<'_>)->io::Result<Token<'static>>{panic!("fixture has no dynamic macro")}
 fn invocation(&mut self,_:&str,_:Origin,_:&SettingAdmission<'_>)->io::Result<()>{Ok(())}
}
struct Control{emitted:usize,fail:bool}
impl OriginalStreamControl for Control{
 fn directive(&mut self,_:Origin,_:&mut RawSourceDriver,_:&dyn SourceProvider,_:&mut dyn OriginalRawNoticeSink,_:&mut dyn OriginalMacroHost,_:&SettingAdmission<'_>)->io::Result<()>{panic!("no directive in this producer control")}
 fn macro_notice(&mut self,_:MacroNotice,_:&mut RawSourceDriver,_:&dyn SourceProvider,_:&mut dyn OriginalRawNoticeSink,_:&mut dyn OriginalMacroHost,_:&SettingAdmission<'_>)->io::Result<()>{panic!("no macro source error in fixture")}
 fn conditional_eof(&mut self,_:super::super::original_conditional::Unterminated,_:&SettingAdmission<'_>)->io::Result<()>{panic!("no conditional in fixture")}
 fn indent_notice(&mut self,_:NativeIndentNotice,_:Option<Origin>,_:&SettingAdmission<'_>)->io::Result<()>{panic!("valid indentation")}
 fn emitted(&mut self,_:&Token<'static>,token:SpanToken,cover:Span,produced:super::super::original_prepared_output::OriginalProducedSpan<'_>,_:&mut RawSourceDriver,_:&dyn SourceProvider,_:&SettingAdmission<'_>)->io::Result<()>{assert_eq!(produced.token(),token);assert_eq!(produced.cover(),cover);assert!(produced.output_line()>=1);assert!(cover.start==token.span.start&&cover.end>=token.span.end);self.emitted+=1;if self.fail{Err(io::Error::from_raw_os_error(1450))}else{Ok(())}}
}
struct Consumer{callables:usize,stop:bool}
impl dm_syntax::OriginalDeclarationHeaderObserver for Consumer{fn header(&mut self,_:dm_syntax::OriginalPrimaryHeader<'_>)->io::Result<OriginalHeaderFlow>{Ok(OriginalHeaderFlow::Continue)}}
impl OriginalPrimaryStreamConsumer for Consumer{
 fn callable(&mut self,live:OriginalPrimaryLiveHeader,source:&mut dyn super::super::OriginalFormalTokenStream)->io::Result<OriginalHeaderFlow>{
  self.callables+=1;assert!(self.stop,"this control is a callback loan, not a second formal parser");let token=source.next_header_token()?.ok_or(io::ErrorKind::UnexpectedEof)?;assert_eq!(token.text,"datum");let at=SpanToken{kind:token.kind,span:token.span};assert!(matches!(source.current_header_value(at)?,dm_syntax::OriginalTokenValue::Ident{spelling,..}if spelling=="datum"));let mut visited=false;source.with_current_source(&mut|text,tokens|{assert!(token.span.start>=live.argument_start());assert_eq!(text.get(token.span.range()),Some("datum"));assert_eq!(tokens.last(),Some(&at));visited=true;Ok(())})?;assert!(visited);Ok(OriginalHeaderFlow::Stop)
 }
}
struct Credit{bytes:AtomicUsize,live:Arc<AtomicUsize>}
impl Drop for Credit{fn drop(&mut self){self.live.fetch_sub(self.bytes.load(Ordering::Acquire),Ordering::AcqRel);}}
impl SourceArenaCreditOwner for Credit{fn as_any(&self)->&dyn Any{self}fn reserved_bytes(&self)->usize{self.bytes.load(Ordering::Acquire)}fn visit_storage(&self,_:&mut dyn FnMut(usize,usize)){}}
struct Work(Arc<AtomicUsize>);
impl Work{fn actual<'a>(&self,credit:&'a SourceArenaCredit)->io::Result<&'a Credit>{let credit=credit.owner().as_any().downcast_ref::<Credit>().ok_or(io::ErrorKind::InvalidInput)?;if !Arc::ptr_eq(&credit.live,&self.0){return Err(io::ErrorKind::InvalidInput.into())}Ok(credit)}}
impl SourceArenaWork for Work{
 fn checkpoint(&self)->io::Result<()>{Ok(())}
 fn reserve(&self,bytes:usize)->io::Result<SourceArenaCredit>{self.0.fetch_add(bytes,Ordering::AcqRel);Ok(SourceArenaCredit::from_resource_owner(Arc::new(Credit{bytes:AtomicUsize::new(bytes),live:self.0.clone()})))}
 fn grow(&self,credit:&mut SourceArenaCredit,bytes:usize)->io::Result<()>{let actual=self.actual(credit)?;actual.bytes.fetch_add(bytes,Ordering::AcqRel);self.0.fetch_add(bytes,Ordering::AcqRel);Ok(())}
 fn shrink(&self,credit:&mut SourceArenaCredit,bytes:usize)->io::Result<()>{let actual=self.actual(credit)?;let next=actual.bytes.load(Ordering::Acquire).checked_sub(bytes).ok_or(io::ErrorKind::InvalidInput)?;actual.bytes.store(next,Ordering::Release);self.0.fetch_sub(bytes,Ordering::AcqRel);Ok(())}
}
fn driver(file:&File,a:&SettingAdmission<'_>)->RawSourceDriver{let mut driver=RawSourceDriver::new(InitialEnvironment::OriginalChecker0290,&BTreeMap::new(),a,&mut|input,a|->io::Result<OriginalMacroDefinition<'static>>{original_token_factory::initial_definition_using(input,a,&mut|_|panic!("fixed defaults have no lexical notice"),&mut|_,_|panic!("fixed defaults have no numeric notice"))}).unwrap();driver.push_opened(file,file.lease.clone(),0,a).unwrap();driver}
#[test]fn actual_raw_primary_seals_same_typed_literals_and_shared_tokens_into_real_binding(){
 let used=Arc::new(AtomicUsize::new(0));let source_used=Arc::new(AtomicUsize::new(0));let a=SettingAdmission::new(&used,32<<20,&||Ok(()));let work=Work(source_used.clone());let file=File::new("var/a=2147483647\nvar/s=\"stable\"\n");let mut driver=driver(&file,&a);let mut host=Host::new(&a);let mut notices=Notices{lexical:0,numeric:0};let mut control=Control{emitted:0,fail:false};let mut consumer=Consumer{callables:0,stop:false};
 let output=consume_lazy_primary_using(&mut driver,&file,&work,&mut notices,&mut host,&mut control,&a,&mut consumer).unwrap();assert!(output.consumed_eof);assert_eq!(consumer.callables,0);assert!(control.emitted>0);let(source,primary,tokens,binding,ended)=output.into_bound_parts_using(&a).unwrap();assert!(ended);assert!(primary.original_literal_fact_owner().is_none());assert_eq!(primary.syntax().tokens.as_ptr(),tokens.as_slice().as_ptr());let view=binding.checked_view(&source,Span::new(0,source.len()),&binding,&a).unwrap();let facts=view.checked_facts(&source).unwrap();let(rows,_)=facts.raw_parts();assert_eq!(rows.len(),2);assert!(matches!(rows[0].1.value(),dm_syntax::OriginalTokenValue::Int(i32::MAX)));assert!(matches!(rows[1].1.value(),dm_syntax::OriginalTokenValue::String("stable")));drop(facts);drop(view);drop((binding,tokens,primary,source,driver,host));assert_eq!(used.load(Ordering::Acquire),0);assert_eq!(source_used.load(Ordering::Acquire),0);
}
#[test]fn genuine_callable_dispatch_lends_current_typed_value_and_stops_before_bad_later_quote(){
 let used=Arc::new(AtomicUsize::new(0));let source_used=Arc::new(AtomicUsize::new(0));let a=SettingAdmission::new(&used,32<<20,&||Ok(()));let work=Work(source_used.clone());let file=File::new("/proc/probe(datum/act/A)\n    return \"unterminated\n");let mut driver=driver(&file,&a);let mut host=Host::new(&a);let mut notices=Notices{lexical:0,numeric:0};let mut control=Control{emitted:0,fail:false};let mut consumer=Consumer{callables:0,stop:true};
 let output=consume_lazy_primary_using(&mut driver,&file,&work,&mut notices,&mut host,&mut control,&a,&mut consumer).unwrap();assert!(!output.consumed_eof);assert!(output.primary.observer_stop().is_some());assert_eq!(consumer.callables,1);assert_eq!(notices.lexical,0,"lazy real stop must not demand the later quote");drop((output,driver,host));assert_eq!(used.load(Ordering::Acquire),0);assert_eq!(source_used.load(Ordering::Acquire),0);
}
#[test]fn actual_emission_io_failure_never_returns_prefix_success_and_fresh_driver_recovers(){
 let used=Arc::new(AtomicUsize::new(0));let source_used=Arc::new(AtomicUsize::new(0));let a=SettingAdmission::new(&used,32<<20,&||Ok(()));let work=Work(source_used.clone());let file=File::new("var/a=1\n");
 for fail in [true,false]{let mut driver=driver(&file,&a);let mut host=Host::new(&a);let mut notices=Notices{lexical:0,numeric:0};let mut control=Control{emitted:0,fail};let mut consumer=Consumer{callables:0,stop:false};let output=consume_lazy_primary_using(&mut driver,&file,&work,&mut notices,&mut host,&mut control,&a,&mut consumer);if fail{assert_eq!(output.err().unwrap().raw_os_error(),Some(1450));}else{assert!(output.unwrap().consumed_eof);}drop((driver,host));assert_eq!(used.load(Ordering::Acquire),0);assert_eq!(source_used.load(Ordering::Acquire),0);}
}
struct ColonConsumer<'a,'budget>{a:&'a SettingAdmission<'budget>,allowed:Option<bool>}
impl dm_syntax::OriginalDeclarationHeaderObserver for ColonConsumer<'_,'_>{fn header(&mut self,_:dm_syntax::OriginalPrimaryHeader<'_>)->io::Result<OriginalHeaderFlow>{Ok(OriginalHeaderFlow::Continue)}}
impl OriginalPrimaryStreamConsumer for ColonConsumer<'_,'_>{
 fn callable(&mut self,_:OriginalPrimaryLiveHeader,source:&mut dyn super::super::OriginalFormalTokenStream)->io::Result<OriginalHeaderFlow>{
  // Fixed grammar-control prefix, not a replacement formal parser.
  assert_eq!(source.next_header_token()?.unwrap().text,"arg");assert_eq!(source.next_header_token()?.unwrap().text,"=");
  let mut clauses=dm_syntax::ParameterClauseCursor::new(0);let mut input=dm_syntax::ParameterExpressionDemand::new(source,&mut clauses).original();
  let output=dm_syntax::parse_original_expression_demanded(&mut input,self.a)?;self.allowed=Some(output.parsed().diagnostics.is_empty());drop(output);Ok(OriginalHeaderFlow::Stop)
 }
}
#[test]fn genuine_raw_colon_kinds_reach_same_parameter_pratt_without_demanding_later_bad_body(){
 let used=Arc::new(AtomicUsize::new(0));let source_used=Arc::new(AtomicUsize::new(0));let a=SettingAdmission::new(&used,32<<20,&||Ok(()));let work=Work(source_used.clone());
 for (text,allowed) in [("/proc/probe(arg=value:key)\n    return \"unterminated\n",true),("/proc/probe(arg=value : key)\n    return \"unterminated\n",false),("/proc/probe(arg=a ? f():b)\n    return \"unterminated\n",true)]{
  let file=File::new(text);let mut driver=driver(&file,&a);let mut host=Host::new(&a);let mut notices=Notices{lexical:0,numeric:0};let mut control=Control{emitted:0,fail:false};let mut consumer=ColonConsumer{a:&a,allowed:None};
  let output=consume_lazy_primary_using(&mut driver,&file,&work,&mut notices,&mut host,&mut control,&a,&mut consumer).unwrap();assert_eq!(consumer.allowed,Some(allowed));assert!(!output.consumed_eof);assert_eq!(notices.lexical,0,"header failure/stop never requests later body quote");drop((output,driver,host));assert_eq!(used.load(Ordering::Acquire),0);assert_eq!(source_used.load(Ordering::Acquire),0);
 }
}
struct TemplateConsumer<'a,'budget>{a:&'a SettingAdmission<'budget>,allowed:Option<bool>,alias:Option<dm_syntax::LiteralText>}
impl dm_syntax::OriginalDeclarationHeaderObserver for TemplateConsumer<'_,'_>{fn header(&mut self,_:dm_syntax::OriginalPrimaryHeader<'_>)->io::Result<OriginalHeaderFlow>{Ok(OriginalHeaderFlow::Continue)}}
impl OriginalPrimaryStreamConsumer for TemplateConsumer<'_,'_>{fn callable(&mut self,_:OriginalPrimaryLiveHeader,source:&mut dyn super::super::OriginalFormalTokenStream)->io::Result<OriginalHeaderFlow>{
 assert_eq!(source.next_header_token()?.unwrap().text,"arg");assert_eq!(source.next_header_token()?.unwrap().text,"=");let mut clauses=dm_syntax::ParameterClauseCursor::new(0);let mut input=dm_syntax::ParameterExpressionDemand::new(source,&mut clauses).original();let output=dm_syntax::parse_original_expression_demanded(&mut input,self.a)?;self.allowed=Some(output.parsed().diagnostics.is_empty());if self.allowed==Some(true){let dm_syntax::ExprKind::Literal(value)=&output.parsed().expr.as_ref().unwrap().kind else{panic!("actual typed template")};self.alias=Some(value.clone());}drop(output);Ok(OriginalHeaderFlow::Stop)
}}
#[test]fn actual_raw_interpolation_parts_loan_same_pratt_children_empty_slots_and_lazy_bad_body_frontier(){
 let used=Arc::new(AtomicUsize::new(0));let source_used=Arc::new(AtomicUsize::new(0));let a=SettingAdmission::new(&used,32<<20,&||Ok(()));let work=Work(source_used.clone());
 let file=File::new("/proc/probe(arg=\"head[a.b]middle[]tail\")\n    return \"unterminated\n");let mut driver=driver(&file,&a);let mut host=Host::new(&a);let mut notices=Notices{lexical:0,numeric:0};let mut control=Control{emitted:0,fail:false};let mut consumer=TemplateConsumer{a:&a,allowed:None,alias:None};
 let output=consume_lazy_primary_using(&mut driver,&file,&work,&mut notices,&mut host,&mut control,&a,&mut consumer).unwrap();assert_eq!(consumer.allowed,Some(true));assert!(!output.consumed_eof);assert_eq!(notices.lexical,0);let literal=consumer.alias.take().unwrap();assert_eq!(literal.syntax_parts().unwrap().unwrap().expressions.len(),1);let pointer=literal.syntax_parts().unwrap().unwrap().expressions.as_ptr();let mut fragments=Vec::new();for part in literal.pinned_fragments().unwrap().unwrap(){let mut text=String::new();part.unwrap().write_text(&mut text).unwrap();fragments.push(text)}assert_eq!(fragments,["head","middle","tail"]);assert!(literal.parts().unwrap().is_some());drop((output,driver,host));assert_eq!(source_used.load(Ordering::Acquire),0);assert!(used.load(Ordering::Acquire)>0);assert_eq!(literal.syntax_parts().unwrap().unwrap().expressions.as_ptr(),pointer);drop(literal);assert_eq!(used.load(Ordering::Acquire),0);
}
#[test]fn genuine_raw_close_bit_reaches_separate_primary_rows_and_the_later_same_token_body_parser(){
 let used=Arc::new(AtomicUsize::new(0));let source_used=Arc::new(AtomicUsize::new(0));let a=SettingAdmission::new(&used,32<<20,&||Ok(()));let work=Work(source_used.clone());
 for(text,closed)in[("var/result=target:key\n",true),("var/result=target : key\n",false)]{
  let file=File::new(text);let mut driver=driver(&file,&a);let mut host=Host::new(&a);let mut notices=Notices{lexical:0,numeric:0};let mut control=Control{emitted:0,fail:false};let mut consumer=Consumer{callables:0,stop:false};let output=consume_lazy_primary_using(&mut driver,&file,&work,&mut notices,&mut host,&mut control,&a,&mut consumer).unwrap();assert!(output.consumed_eof);
  let(source,primary,tokens,binding,ended)=output.into_bound_parts_using(&a).unwrap();assert!(ended);let view=binding.checked_view(&source,Span::new(0,source.len()),&binding,&a).unwrap();let foreign:crate::SourceText=source.as_str().to_owned().into();assert_eq!(binding.checked_view(&foreign,Span::new(0,source.len()),&binding,&a).err().unwrap().kind(),io::ErrorKind::InvalidInput);assert_eq!(view.checked_facts(&foreign).err().unwrap().kind(),io::ErrorKind::InvalidInput);drop(foreign);let facts=view.checked_facts(&source).unwrap();let(colons,_)=facts.raw_colons();assert_eq!(colons.len(),1);assert_eq!(colons[0].1,closed);assert!(facts.raw_parts().0.is_empty(),"punctuation must not masquerade as literal DATA");let start=source.as_str().find("target").unwrap();let end=source.as_str().find("key").unwrap()+3;let first=tokens.as_slice().partition_point(|t|t.span.end<=start);let last=tokens.as_slice().partition_point(|t|t.span.start<end);let parsed=dm_syntax::parse_expression_original_token_view(source.as_str(),&tokens.as_slice()[first..last],start,&a,Some(facts));assert_eq!(parsed.diagnostics.is_empty(),closed,"actual raw CloseColon decision survives source projection and later parser loan");drop(parsed);drop(view);drop((source,primary,tokens,binding,driver,host));assert_eq!(used.load(Ordering::Acquire),0);assert_eq!(source_used.load(Ordering::Acquire),0);
 }
}

struct EndConsumer;
impl dm_syntax::OriginalDeclarationHeaderObserver for EndConsumer {
    fn header(&mut self,_:dm_syntax::OriginalPrimaryHeader<'_>)->io::Result<OriginalHeaderFlow>{panic!("failed header never completes")}
}
impl OriginalPrimaryStreamConsumer for EndConsumer {
    fn callable(&mut self,live:OriginalPrimaryLiveHeader,source:&mut dyn super::super::OriginalFormalTokenStream)->io::Result<OriginalHeaderFlow>{
        assert!(source.actual_end()?.is_none());
        assert_eq!(source.next_header_token()?.unwrap().text,"A");
        let semicolon=source.next_header_token()?.unwrap();
        assert_eq!(semicolon.text,";");
        assert!(source.actual_end()?.is_none(),"actual delimiter is not a drained End");
        assert!(source.next_header_token()?.is_none());
        let end=source.actual_end()?.expect("real receiver accepted the producer footer");
        source.with_current_source(&mut|text,_|{
            assert!(end.closes(&live,text.len()));
            assert!(!end.closes(&live,semicolon.span.end),"end includes the same emitted layout padding");
            Ok(())
        })?;
        Ok(OriginalHeaderFlow::Stop)
    }
}
#[test]
fn actual_consumed_end_is_available_to_failed_formal_without_completing_primary() {
    let used=Arc::new(AtomicUsize::new(0));
    let source_used=Arc::new(AtomicUsize::new(0));
    let a=SettingAdmission::new(&used,32<<20,&||Ok(()));
    let work=Work(source_used.clone());
    let file=File::new("/proc/p(A");
    let mut driver=driver(&file,&a);
    let mut host=Host::new(&a);
    let mut notices=Notices{lexical:0,numeric:0};
    let mut control=Control{emitted:0,fail:false};
    let output=consume_lazy_primary_using(&mut driver,&file,&work,&mut notices,&mut host,&mut control,&a,&mut EndConsumer).unwrap();
    assert!(!output.consumed_eof,"the failed primary stopped even though the physical receiver drained");
    assert!(output.primary.observer_stop().is_some());
    assert!(output.primary.syntax().items.is_empty());
    drop((output,driver,host));
    assert_eq!(used.load(Ordering::Acquire),0);
    assert_eq!(source_used.load(Ordering::Acquire),0);
}
#[test]
fn genuine_logical_end_refuses_undelivered_and_foreign_frontiers() {
    let used=Arc::new(AtomicUsize::new(0));
    let a=SettingAdmission::new(&used,32<<20,&||Ok(()));
    let file=File::new("/datum/a");
    let work=Work(Arc::new(AtomicUsize::new(0)));
    let drain=||{
        let mut driver=driver(&file,&a);
        let mut host=Host::new(&a);
        let mut notices=Notices{lexical:0,numeric:0};
        let mut control=Control{emitted:0,fail:false};
        let mut producer=OriginalLogicalProducer::new(&mut driver,&file,&mut notices,&mut host,&mut control,&a).unwrap();
        let early=producer.initial_delivery();
        let mut output=OriginalFinalOutput::receiver(&work,early.clone()).unwrap();
        let mut primary=OriginalPrimaryDemand::new(&a,None).unwrap();
        assert!(producer.actual_end().is_none());
        while let Some(token)=producer.next_prepared().unwrap(){
            output.adopt(token,&mut primary,&a).unwrap();
        }
        let end=producer.actual_end().expect("genuine logical End");
        (end,early,output.delivery().unwrap())
    };
    let (end,early,delivered)=drain();
    let (foreign_end,_,foreign_delivered)=drain();
    end.validate(&delivered,&a).unwrap();
    assert!(end.end()>early.end());
    assert_eq!(end.end(),foreign_end.end(),"foreign output has the same source and offset");
    assert_eq!(end.validate(&early,&a).unwrap_err().kind(),io::ErrorKind::InvalidInput);
    assert_eq!(end.validate(&foreign_delivered,&a).unwrap_err().kind(),io::ErrorKind::InvalidInput);
    drop((end,early,delivered,foreign_end,foreign_delivered));
    assert_eq!(used.load(Ordering::Acquire),0);
    assert_eq!(work.0.load(Ordering::Acquire),0);
}
