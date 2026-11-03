use crate::Span;use std::io;
/// Value facts from the SAME resource consumption branch; DATA only.
#[derive(Clone,Copy,Debug,Eq,PartialEq)]pub struct OriginalResourceFacts{span:Span,unterminated:bool}
impl OriginalResourceFacts{
 pub(super) fn issued(span:Span,unterminated:bool)->Self{Self{span,unterminated}}
 pub fn span(&self)->Span{self.span}pub fn recovering(&self)->bool{self.unterminated}
 pub fn notice_point(&self)->Option<crate::OriginalLexicalNoticePoint>{self.unterminated.then(||crate::OriginalLexicalNoticePoint::consumed(self.span.start))}
 pub fn visit_value_bytes<E>(&self,input:&[u8],emit:impl FnMut(&[u8])->Result<(),E>)->Result<Result<(),io::Error>,E>{
  let Some(raw)=input.get(self.span.range())else{return Ok(Err(io::ErrorKind::InvalidInput.into()))};if raw.first()!=Some(&b'\'')||(!self.unterminated&&raw.last()!=Some(&b'\'')){return Ok(Err(io::ErrorKind::InvalidInput.into()))}let end=raw.len().saturating_sub(usize::from(!self.unterminated));if end<1{return Ok(Err(io::ErrorKind::InvalidInput.into()))}
  Ok(if crate::literal::visit_pinned_resource_bytes(&raw[1..end],self.unterminated,emit)?{Ok(())}else{Err(io::ErrorKind::InvalidData.into())})
 }
}
#[cfg(test)]mod tests{use super::*;#[test]fn actual_issued_resource_value_uses_same_projection_and_recovers_terminal_escape_without_runtime_escapes(){for(raw,bad,expected)in[(b"'a\\nb'" as &[u8],false,b"anb" as &[u8]),(b"'a\\'b'",false,b"a'b"),(b"'a\\",true,b"a"),(b"'\xc3\xa9'",false,b"\xc3\xa9")]{let facts=OriginalResourceFacts::issued(Span::new(0,raw.len()),bad);let mut text=Vec::new();facts.visit_value_bytes(raw,|part|{text.extend_from_slice(part);Ok::<_,()>(())}).unwrap().unwrap();assert_eq!(text,expected);}}}
