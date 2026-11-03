//! Actual pure daemon frame encoders, shared by ordinary and retained-error transport.
use serde::{Serialize};
use std::io::{self,Write};
pub(super) const MAX_FRAME:usize=4*1024*1024;
pub(super) fn send_frame(stream: &mut impl Write, value: &impl Serialize) -> io::Result<()> {
    let bytes = serde_json::to_vec(value)?;
    if bytes.len() > MAX_FRAME {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            "daemon frame too large",
        ));
    }
    stream.write_all(&(bytes.len() as u32).to_le_bytes())?;
    stream.write_all(&bytes)?;
    stream.flush()
}
/// SAME Rejected JSON shape, borrowing the already-funded actual error text.
/// Count the frame without storage, then write the immutable text directly;
/// no from_error String or serde_json::to_vec buffer escapes native funding.
pub(super) fn send_rejected_text(stream:&mut impl Write,kind:crate::request_failure::FailureKind,message:&str)->io::Result<()>{
 #[derive(Serialize)]struct FailureView<'a>{kind:crate::request_failure::FailureKind,message:&'a str}
 #[derive(Serialize)]enum ReplyView<'a>{Rejected(FailureView<'a>)}
 struct Count{bytes:usize}impl Write for Count{fn write(&mut self,bytes:&[u8])->io::Result<usize>{let next=self.bytes.checked_add(bytes.len()).ok_or_else(||io::Error::new(io::ErrorKind::InvalidData,"daemon frame too large"))?;if next>MAX_FRAME{return Err(io::Error::new(io::ErrorKind::InvalidData,"daemon frame too large"))}self.bytes=next;Ok(bytes.len())}fn flush(&mut self)->io::Result<()>{Ok(())}}
 let view=ReplyView::Rejected(FailureView{kind,message});let mut count=Count{bytes:0};serde_json::to_writer(&mut count,&view).map_err(|error|io::Error::new(error.io_error_kind().unwrap_or(io::ErrorKind::InvalidData),error))?;
 stream.write_all(&(count.bytes as u32).to_le_bytes())?;
 struct Output<'a,W>{writer:&'a mut W,first:Option<io::Error>}impl<W:Write> Write for Output<'_,W>{fn write(&mut self,bytes:&[u8])->io::Result<usize>{if self.first.is_some(){return Err(io::ErrorKind::Other.into())}match self.writer.write(bytes){Ok(n)=>Ok(n),Err(error)=>{let kind=error.kind();self.first=Some(error);Err(kind.into())}}}fn flush(&mut self)->io::Result<()>{if self.first.is_some(){return Err(io::ErrorKind::Other.into())}match self.writer.flush(){Ok(())=>Ok(()),Err(error)=>{let kind=error.kind();self.first=Some(error);Err(kind.into())}}}}
 let mut output=Output{writer:stream,first:None};let result=serde_json::to_writer(&mut output,&view);if let Some(error)=output.first{return Err(error)}result.map_err(|error|io::Error::new(error.io_error_kind().unwrap_or(io::ErrorKind::Other),error))?;output.writer.flush()
}
