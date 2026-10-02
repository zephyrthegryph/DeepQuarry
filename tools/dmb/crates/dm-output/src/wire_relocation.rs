//! Indexed relocation over verified immutable wire objects. This projection
//! never decodes an entire procedure into a word vector or scans for ID-like
//! values: the compiler supplies schema-known symbol and debug operand sites.
use crate::wire_image::VerifiedCodeHandle;
use sha2::{Digest,Sha256};
use std::io;
fn invalid(message:&'static str)->io::Error{io::Error::new(io::ErrorKind::InvalidData,message)}
#[derive(Clone,Debug,Eq,PartialEq)]
pub enum RelocationSite {
 Direct {offset:u32,expected:u32,current:u32},
 Tagged {offset:u32,tag:u8,expected:u32,current:u32},
}
impl RelocationSite {
 fn offset(&self)->u32{match self {Self::Direct{offset,..}|Self::Tagged{offset,..}=>*offset}}
 fn count(&self)->u32{if matches!(self,Self::Tagged{..}){2}else{1}}
 fn values(&self)->(u32,u32){match self{Self::Direct{expected,current,..}|Self::Tagged{expected,current,..}=>(*expected,*current)}}
}
/// A checked relocation layout. Semantic candidate validity and current symbol
/// resolution remain obligations of the caller; old sites are checked against
/// the actual digest-bound source bytes before any mutation is performed.
pub struct RelocationPlan {digest:String,words:usize,width:usize,sites:Vec<RelocationSite>}
impl RelocationPlan {
 pub fn new(source:&VerifiedCodeHandle,mut sites:Vec<RelocationSite>)->io::Result<Self>{
  let words=source.word_count();let width=source.object_width();
  if words>u16::MAX as usize||!matches!(width,2|4)||sites.len()>words.saturating_mul(2){return Err(invalid("invalid relocation object shape"));}
  sites.sort_by_key(RelocationSite::offset);sites.dedup();
  let mut end=0;
  for site in &sites {let next=site.offset().checked_add(site.count()).ok_or_else(||invalid("relocation site overflow"))?;
   if site.offset()<end||next as usize>words{return Err(invalid("overlapping or out-of-range relocation site"));}end=next;
   let (_,current)=site.values();if width==2 {let fits=match site{RelocationSite::Direct{..}=>current<=u16::MAX as u32,RelocationSite::Tagged{tag,..}=>u32::from(*tag)|((current>>16)<<8)<=u16::MAX as u32};if !fits{return Err(invalid("narrow relocation operand overflow"));}}
  }
  Ok(Self {digest:source.digest().to_owned(),words,width,sites})
 }
 pub fn changed(&self)->bool{self.sites.iter().any(|site|{let(old,new)=site.values();old!=new})}
 pub fn apply(&self,source:&VerifiedCodeHandle,bytes:&[u8])->io::Result<Vec<u8>>{
  if source.digest()!=self.digest||source.word_count()!=self.words||source.object_width()!=self.width
   ||bytes.len()!=2+self.words*self.width||bytes.get(..2)!=Some((self.words as u16).to_le_bytes().as_slice())
   ||format!("{:x}",Sha256::digest(bytes))!=self.digest{return Err(invalid("relocation source proof mismatch"));}
  let read=|offset:u32|->u32 {let start=2+offset as usize*self.width;let value=&bytes[start..start+self.width];if self.width==2 {u16::from_le_bytes(value.try_into().unwrap()) as u32}else{u32::from_le_bytes(value.try_into().unwrap())}};
  // Complete preflight: failure cannot expose a partially rewritten object.
  for site in &self.sites {match site {
   RelocationSite::Direct{offset,expected,..}=>if read(*offset)!=*expected{return Err(invalid("relocation operand witness mismatch"));},
   RelocationSite::Tagged{offset,tag,expected,..}=>if read(*offset)!=(u32::from(*tag)|((*expected>>16)<<8))||read(*offset+1)!=(*expected&0xffff){return Err(invalid("tagged relocation operand witness mismatch"));},
  }}
  let mut output=bytes.to_vec();
  let write=|output:&mut [u8],offset:u32,value:u32| {let start=2+offset as usize*self.width;if self.width==2{output[start..start+2].copy_from_slice(&(value as u16).to_le_bytes());}else{output[start..start+4].copy_from_slice(&value.to_le_bytes());}};
  for site in &self.sites {match site {
   RelocationSite::Direct{offset,current,..}=>write(&mut output,*offset,*current),
   RelocationSite::Tagged{offset,tag,current,..}=>{write(&mut output,*offset,u32::from(*tag)|((*current>>16)<<8));write(&mut output,*offset+1,*current&0xffff);},
  }}Ok(output)
 }
}
