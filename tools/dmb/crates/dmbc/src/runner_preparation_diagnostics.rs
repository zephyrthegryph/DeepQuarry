//! Scoped writer loan, no buffers/counters/source or cached rendered stamp.
use std::io::{self,Write};
#[derive(Debug)]pub struct PreparationDiagnosticResult{pub preparation:Result<crate::request::BuildOutcome,Box<dyn std::error::Error>>,pub diagnostics:io::Result<()>}
enum Destination<'a>{Writer(&'a mut dyn Write),ReportStage(&'a mut crate::selected_report_spool::Stage)}
pub(crate) struct PreparationDiagnosticOutput<'a>{destination:Destination<'a>,checker:Option<&'a mut crate::selected_report_spool::Stage>,checker_frame:Option<dq_analyze::selected_exclusions_wire::Frame>,first:Option<io::Error>,capture:bool}
struct Guarded<'a>{writer:&'a mut dyn Write,first:Option<io::Error>}
impl Write for Guarded<'_>{
 fn write(&mut self,b:&[u8])->io::Result<usize>{if self.first.is_some(){return Err(io::ErrorKind::Other.into())}match self.writer.write(b){Ok(n)=>Ok(n),Err(actual)=>{self.first=Some(actual);Err(io::ErrorKind::Other.into())}}}
 fn flush(&mut self)->io::Result<()>{if self.first.is_some(){return Err(io::ErrorKind::Other.into())}match self.writer.flush(){Ok(())=>Ok(()),Err(actual)=>{self.first=Some(actual);Err(io::ErrorKind::Other.into())}}}
}

#[cfg(test)]
mod selected_attempt_controls {
    use super::*;

    #[test]
    fn selected_report_keeps_only_the_latest_preparation_attempt() {
        let root = crate::test_scratch::dir("selected-diagnostic-attempts");
        let mut stage = crate::selected_report_spool::Stage::new(&root).unwrap();
        let mut output = PreparationDiagnosticOutput::selected_report(&mut stage);
        output.start_attempt().unwrap();
        output.emit(|sink| sink.write_all(b"warning from source that moved\n")).unwrap();
        output.start_attempt().unwrap();
        output.emit(|sink| sink.write_all(b"warning from current source\n")).unwrap();
        assert!(output.take_error().is_none());
        drop(output);

        let (verified, _) = stage.seal().unwrap().validate(|file| io::copy(file, &mut io::sink())).unwrap();
        let mut published = Vec::new();
        verified.publish(&mut published).unwrap();
        assert_eq!(published, b"warning from current source\n");
    }
}
impl<'a> PreparationDiagnosticOutput<'a>{
 pub(crate) fn immediate(writer:&'a mut dyn Write)->Self{Self{destination:Destination::Writer(writer),checker:None,checker_frame:None,first:None,capture:false}}
 pub(crate) fn captured(writer:&'a mut dyn Write)->Self{Self{destination:Destination::Writer(writer),checker:None,checker_frame:None,first:None,capture:true}}
 pub(crate) fn selected_report(stage:&'a mut crate::selected_report_spool::Stage)->Self{Self{destination:Destination::ReportStage(stage),checker:None,checker_frame:None,first:None,capture:true}}
 pub(crate) fn selected_combined(stage:&'a mut crate::selected_report_spool::Stage,checker:&'a mut crate::selected_report_spool::Stage)->Self{
  Self{destination:Destination::ReportStage(stage),checker:Some(checker),checker_frame:None,first:None,capture:true}
 }
 pub(crate) fn needs_combined_checker(&self)->bool{self.checker.is_some()}
 pub(crate) fn emit_combined_checker(&mut self,run:impl FnOnce(&mut crate::selected_report_spool::Stage)->io::Result<dq_analyze::selected_exclusions_wire::Frame>)->io::Result<()>{
  if self.first.is_some(){return Err(self.first.take().expect("actual preparation write error"));}
  let stage=self.checker.as_deref_mut().ok_or_else(||io::Error::other("combined checker stage absent"))?;
  if self.checker_frame.is_some(){return Err(io::Error::other("combined checker issued twice in one preparation attempt"));}
  self.checker_frame=Some(run(stage)?);
  Ok(())
 }
 pub(crate) fn checker_frame(&self)->Option<dq_analyze::selected_exclusions_wire::Frame>{self.checker_frame}
 pub(crate) fn start_attempt(&mut self)->io::Result<()>{
  let Destination::ReportStage(stage)=&mut self.destination else{return Ok(())};
  if let Some(error)=self.first.take(){return Err(error)}
  stage.restart_attempt()?;
  if let Some(checker)=self.checker.as_deref_mut(){checker.restart_attempt()?;}
  self.checker_frame=None;
  Ok(())
 }
 pub(crate) fn take_error(&mut self)->Option<io::Error>{self.first.take()}
 pub(crate) fn emit(&mut self,run:impl FnOnce(&mut dyn Write)->io::Result<()>)->io::Result<()>{
  if self.first.is_some(){return Ok(())}let writer:&mut dyn Write=match &mut self.destination{Destination::Writer(writer)=>*writer,Destination::ReportStage(stage)=>*stage};let mut guarded=Guarded{writer,first:None};let pending=run(&mut guarded);let pending=match guarded.first.take(){Some(actual)=>Err(actual),None=>pending};
  match pending{Ok(())=>Ok(()),Err(actual)if self.capture=>{self.first=Some(actual);Ok(())},Err(actual)=>Err(actual)}
 }
}
