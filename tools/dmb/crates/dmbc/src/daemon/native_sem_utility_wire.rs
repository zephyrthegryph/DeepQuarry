//! Distinct typed Sem utility terminal; shared sealed stream delivery.
use super::*;
use dq_analyze::native_sem_utility_wire::{Binding,Terminal,Schema};
pub(crate)fn send_native_sem_utility(stream:&mut impl Write,report:crate::runner_host::NativeSemReport,work:&dyn SourceArenaWork)->Result<(),SendFailure>{
 report.require_current().map_err(|actual|SendFailure::BeforePublication(super::utility_streams::as_io(actual)))?;
 let crate::runner_host::NativeSemReport{binding,frame,exit,committed,inputs,frontend,stdout,stderr,_prepare_credit,_credit}=report;
 let terminal=Terminal{schema:Schema::V1,binding,frame,complete:true,exit,committed,stdout:seal_of(&stdout),stderr:seal_of(&stderr)};
 let pending=utility_streams::send(stream,terminal,stderr,stdout,work,&mut||crate::runner_host::native_sem_utility::require_current(&frontend,&inputs,&frame),&|terminal|terminal.require(&terminal.binding),|terminal|(terminal.stderr,terminal.stdout),SendReply::NativeSemUtilityFinished);
 drop(frontend);drop(inputs);drop(_prepare_credit);drop(_credit);pending
}
pub(crate)fn receive_native_sem_utility(stream:&mut impl Read,cache:&Path,binding:&Binding)->Result<utility_streams::Delivered<Terminal>,Box<dyn Error>>{utility_streams::receive(stream,cache,&|terminal:&Terminal|terminal.require(binding),|terminal|(terminal.stderr,terminal.stdout),|reply|match reply{ReceiveReply::NativeSemUtilityFinished(terminal)=>Ok(terminal),other=>Err(other)})}
