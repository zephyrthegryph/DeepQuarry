//! Shared bounded delivery DATA for explicit native utility routes.
//! Included under selected_report_wire; typed endpoint factories own request,
//! current Inputs and terminal authority. No generic completion is synthesized.
use super::*;
use serde::de::DeserializeOwned;
pub(super) fn as_io(actual:Box<dyn Error>)->io::Error{match actual.downcast::<io::Error>(){Ok(actual)=>*actual,Err(actual)=>io::Error::other(actual.to_string())}}
/// Caller must retain the actual report/input/credit owners through this call.
/// Terminal validation is performed before publication and source currentness
/// is checked again after both actual streams and before the terminal.
pub(crate) fn send<T:Serialize>(
 stream:&mut impl Write,terminal:T,stderr:Verified,stdout:Verified,
 work:&dyn SourceArenaWork,
 require_current:&mut dyn FnMut()->Result<(),Box<dyn Error>>,
 validate:&dyn Fn(&T)->io::Result<()>,
 seals:fn(&T)->(Seal,Seal),finish:fn(T)->SendReply<'static>
)->Result<(),SendFailure>{
 validate(&terminal).map_err(SendFailure::BeforePublication)?;
 let(err_seal,out_seal)=seals(&terminal);
 if err_seal!=seal_of(&stderr)||out_seal!=seal_of(&stdout)||err_seal.length.checked_add(out_seal.length).is_none_or(|n|n>MAX_STREAM){return Err(SendFailure::BeforePublication(invalid("utility terminal differs from actual bounded streams")))}
 require_current().map_err(as_io).map_err(SendFailure::BeforePublication)?;
 encode_header(&terminal).map_err(SendFailure::BeforePublication)?;
 let scratch=work.reserve(SEND_SCRATCH).map_err(SendFailure::BeforePublication)?;
 control::checkpoint().map_err(SendFailure::BeforePublication)?;
 let pending=(||{
  stderr.publish(&mut FragmentWriter{stream:&mut *stream,channel:Channel::Diagnostics,sequence:0,offset:0})?;
  stdout.publish(&mut FragmentWriter{stream:&mut *stream,channel:Channel::Report,sequence:0,offset:0})?;
  require_current().map_err(as_io)?;control::checkpoint()?;
  protocol::send(stream,&finish(terminal))?;control::checkpoint()
 })();drop(scratch);pending.map_err(SendFailure::AfterPublication)
}
/// Both sealed streams stay private until the typed terminal, aggregate bound,
/// exact channel order, EOF and per-stream seals have all been checked.
pub(crate) struct Delivered<T>{pub(crate) terminal:T,stderr:Verified,stdout:Verified}
impl<T:Serialize>Delivered<T>{
 /// Existing child CLI framing: one typed JSON header, stderr then stdout.
 /// The parser-free client authenticates/splits these same actual byte seals.
 pub(crate) fn publish_wire(self,output:&mut impl Write)->io::Result<T>{
  let(header,length)=encode_header(&self.terminal)?;output.write_all(&header[..length])?;
  self.stderr.publish(output)?;self.stdout.publish(output)?;Ok(self.terminal)
 }
}
pub(crate) fn receive<T:DeserializeOwned>(
 stream:&mut impl Read,cache:&Path,
 validate:&dyn Fn(&T)->io::Result<()>,seals:fn(&T)->(Seal,Seal),
 extract:fn(ReceiveReply)->Result<T,ReceiveReply>
)->Result<Delivered<T>,Box<dyn Error>>{
 let(mut accepted,mut stderr,mut stdout,mut total)=(false,Collector::default(),Collector::default(),0u64);
 loop{control::checkpoint()?;match protocol::receive_bounded::<ReceiveReply>(stream,protocol::MAX_FRAME)?{
  ReceiveReply::Accepted if !accepted=>accepted=true,
  ReceiveReply::Rejected(error)if stderr.next==0&&stdout.next==0=>return Err(RequestFailure{kind:error.kind,message:error.message}.into()),
  ReceiveReply::SelectedReportFragment(fragment)if accepted=>{
   total=total.checked_add(fragment.bytes.length as u64).filter(|n|*n<=MAX_STREAM).ok_or_else(||invalid("utility streams exceed existing aggregate report bound"))?;
   match fragment.channel{Channel::Diagnostics if stdout.next==0=>stderr.push(cache,&fragment)?,Channel::Report=>stdout.push(cache,&fragment)?,_=>return Err(invalid("unexpected or out-of-order utility channel").into())}
  },
  terminal if accepted=>{
   let terminal=extract(terminal).map_err(|_|invalid("unexpected typed utility terminal/frame"))?;
   validate(&terminal)?;require_end(stream)?;let(err_seal,out_seal)=seals(&terminal);
   if err_seal.length.checked_add(out_seal.length).is_none_or(|n|n>MAX_STREAM){return Err(invalid("utility terminal streams exceed existing aggregate bound").into())}
   let stderr=stderr.finish(Some(err_seal))?.ok_or_else(||invalid("utility terminal omits actual stderr stream"))?;
   let stdout=stdout.finish(Some(out_seal))?.ok_or_else(||invalid("utility terminal omits actual stdout stream"))?;
   return Ok(Delivered{terminal,stderr,stdout})
  },_=>return Err(invalid("unexpected utility transport frame before admission").into())
 }}
}
