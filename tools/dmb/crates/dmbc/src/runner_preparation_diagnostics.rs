//! Scoped writer loan, no buffers/counters/source or cached rendered stamp.
use std::io::{self,Write};
#[derive(Debug)]pub struct PreparationDiagnosticResult{pub preparation:Result<crate::request::BuildOutcome,Box<dyn std::error::Error>>,pub diagnostics:io::Result<()>}
pub(crate) struct PreparationDiagnosticOutput<'a>{writer:&'a mut dyn Write,first:Option<io::Error>,capture:bool}
struct Guarded<'a>{writer:&'a mut dyn Write,first:Option<io::Error>}
impl Write for Guarded<'_>{
 fn write(&mut self,b:&[u8])->io::Result<usize>{if self.first.is_some(){return Err(io::ErrorKind::Other.into())}match self.writer.write(b){Ok(n)=>Ok(n),Err(actual)=>{self.first=Some(actual);Err(io::ErrorKind::Other.into())}}}
 fn flush(&mut self)->io::Result<()>{if self.first.is_some(){return Err(io::ErrorKind::Other.into())}match self.writer.flush(){Ok(())=>Ok(()),Err(actual)=>{self.first=Some(actual);Err(io::ErrorKind::Other.into())}}}
}
impl<'a> PreparationDiagnosticOutput<'a>{
 pub(crate) fn immediate(writer:&'a mut dyn Write)->Self{Self{writer,first:None,capture:false}}
 pub(crate) fn captured(writer:&'a mut dyn Write)->Self{Self{writer,first:None,capture:true}}
 pub(crate) fn take_error(&mut self)->Option<io::Error>{self.first.take()}
 pub(crate) fn emit(&mut self,run:impl FnOnce(&mut dyn Write)->io::Result<()>)->io::Result<()>{
  if self.first.is_some(){return Ok(())}let mut guarded=Guarded{writer:self.writer,first:None};let pending=run(&mut guarded);let pending=match guarded.first.take(){Some(actual)=>Err(actual),None=>pending};
  match pending{Ok(())=>Ok(()),Err(actual)if self.capture=>{self.first=Some(actual);Ok(())},Err(actual)=>Err(actual)}
 }
}
