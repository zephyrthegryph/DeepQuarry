//! Schema delivery borrows the existing bounded fragment/collector transport.
use super::*;use dq_analyze::schema_proposals_wire::{Schema,Terminal as SchemaTerminal};
pub(crate) fn send_schema(stream:&mut impl Write,completed:crate::runner_host::SchemaReport,work:&dyn SourceArenaWork)->Result<(),SendFailure>{
 let crate::runner_host::SchemaReport{root,inputs,frame,count,diagnostics,report,_credit,_prepare_credit}=completed;
 let convert=|error:Box<dyn Error>|match error.downcast::<io::Error>(){Ok(actual)=>*actual,Err(other)=>io::Error::other(other.to_string())};
 inputs.with_context(||inputs.require_current().map_err(convert)).map_err(SendFailure::BeforePublication)?;
 let terminal=SchemaTerminal{schema:Schema::V1,complete:true,applied:false,full_policy_parity:false,root,frame,count:u64::try_from(count).map_err(|_|SendFailure::BeforePublication(io::ErrorKind::OutOfMemory.into()))?,diagnostics:diagnostics.as_ref().map(seal_of),report:seal_of(&report)};
 terminal.require(&terminal.root).map_err(SendFailure::BeforePublication)?;encode_header(&terminal).map_err(SendFailure::BeforePublication)?;
 let _scratch=work.reserve(SEND_SCRATCH).map_err(SendFailure::BeforePublication)?;
 let sent=inputs.with_context(||{control::checkpoint()?;if let Some(stage)=diagnostics{stage.publish(&mut FragmentWriter{stream:&mut *stream,channel:Channel::Diagnostics,sequence:0,offset:0})?;}report.publish(&mut FragmentWriter{stream:&mut *stream,channel:Channel::Report,sequence:0,offset:0})?;inputs.require_current().map_err(convert)?;control::checkpoint()?;protocol::send(stream,&SendReply::SchemaProposalsFinished(terminal))});sent.map_err(SendFailure::AfterPublication)
}
pub(crate) struct DeliveredSchema{terminal:SchemaTerminal,diagnostics:Option<Verified>,report:Verified}
impl DeliveredSchema{pub(crate)fn publish(self,output:&mut impl Write)->io::Result<()>{let(header,length)=encode_header(&self.terminal)?;output.write_all(&header[..length])?;if let Some(stage)=self.diagnostics{stage.publish(output)?;}self.report.publish(output)}}
pub(crate)fn receive_schema(stream:&mut impl Read,cache:&Path,expected_root:&Path)->Result<DeliveredSchema,Box<dyn Error>>{
 let(mut accepted,mut diagnostics,mut report)=(false,Collector::default(),Collector::default());loop{control::checkpoint()?;match protocol::receive_bounded::<ReceiveReply>(stream,protocol::MAX_FRAME)?{
  ReceiveReply::Accepted if !accepted=>accepted=true,
  ReceiveReply::Rejected(error)if diagnostics.next==0&&report.next==0=>return Err(RequestFailure{kind:error.kind,message:error.message}.into()),
  ReceiveReply::SelectedReportFragment(fragment)if accepted=>match fragment.channel{Channel::Diagnostics=>diagnostics.push(cache,&fragment)?,Channel::Report=>report.push(cache,&fragment)?,_=>return Err(invalid("schema report cannot receive Checker/compile channel").into())},
  ReceiveReply::SchemaProposalsFinished(terminal)if accepted=>{terminal.require(expected_root)?;require_end(stream)?;let diagnostics=diagnostics.finish(terminal.diagnostics)?;let report=report.finish(Some(terminal.report))?.ok_or_else(||invalid("schema terminal lacks actual report stream"))?;return Ok(DeliveredSchema{terminal,diagnostics,report})},
  _=>return Err(invalid("unexpected schema report transport frame").into()),
 }}
}
