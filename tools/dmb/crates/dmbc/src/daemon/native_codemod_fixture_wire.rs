//! Typed utility terminal over the existing shared sealed-stream transport.
use super::*;
use dq_analyze::native_codemod_fixture_wire::{Binding,Terminal,Schema};
pub(crate) fn send_native_codemod_fixture(stream:&mut impl Write,report:crate::runner_host::NativeCodemodFixtureReport,work:&dyn SourceArenaWork)->Result<(),SendFailure>{
 report.into_delivery(|binding,requested,frame,exit,committed,stdout,stderr,current|{
  let terminal=Terminal{schema:Schema::V2,requested,frame,complete:true,exit,committed,stdout:seal_of(&stdout),stderr:seal_of(&stderr)};
  utility_streams::send(stream,terminal,stderr,stdout,work,current,&|terminal|terminal.require(&binding),|terminal|(terminal.stderr,terminal.stdout),SendReply::NativeCodemodFixtureFinished)
 })
}
pub(crate) fn receive_native_codemod_fixture(stream:&mut impl Read,cache:&Path,binding:&Binding)->Result<utility_streams::Delivered<Terminal>,Box<dyn Error>>{
 utility_streams::receive(stream,cache,&|terminal:&Terminal|terminal.require(binding),|terminal|(terminal.stderr,terminal.stdout),|reply|match reply{ReceiveReply::NativeCodemodFixtureFinished(terminal)=>Ok(terminal),other=>Err(other)})
}
