//! Funding for actual allocations in the SAME original primary parser.
//! No parser/model/cache is stored here; unique storage leases live with the
//! native primary result and scoped temporary layout/compaction allocations.
use super::*;
use std::{cell::RefCell,io};
pub(super) struct Storage<'a,'b>{pub(super) a:&'a crate::SettingAdmission<'b>,owned:RefCell<crate::SettingRootLease>,failure:RefCell<Option<io::Error>>}
impl<'a,'b> Storage<'a,'b>{
 pub(super) fn new(a:&'a crate::SettingAdmission<'b>)->io::Result<Self>{let owned=match a.reserve(4096){Ok(lease)=>lease,Err(actual)=>return Err(a.take_operational_error().unwrap_or(actual))};Ok(Self{a,owned:RefCell::new(owned),failure:RefCell::new(None)})}
 pub(super) fn poll(&self)->bool{if self.failure.borrow().is_some(){return false}match self.a.checkpoint(){Ok(())=>true,Err(actual)=>self.fail(actual)}}
 pub(super) fn fail(&self,actual:io::Error)->bool{if self.failure.borrow().is_none(){*self.failure.borrow_mut()=Some(self.a.take_operational_error().unwrap_or(actual));}false}
 pub(super) fn take_failure(&self)->Option<io::Error>{self.failure.borrow_mut().take()}
 pub(super) fn bytes(&self)->usize{self.owned.borrow().bytes()}
 fn grow(&self,bytes:usize)->bool{if !self.poll(){return false}match self.a.grow(&mut self.owned.borrow_mut(),bytes){Ok(())=>true,Err(actual)=>self.fail(actual)}}
 fn release(&self,bytes:usize)->bool{match self.a.shrink(&mut self.owned.borrow_mut(),bytes){Ok(())=>true,Err(actual)=>self.fail(actual)}}
 fn overflow(&self)->bool{self.fail(io::ErrorKind::OutOfMemory.into())}
 pub(super) fn push<T>(&self,rows:&mut Vec<T>,value:T)->bool{
  if !self.poll(){return false}
  if rows.len()==rows.capacity(){
   let Some(capacity)=rows.capacity().max(2).checked_mul(2)else{return self.overflow()};let Some(extra)=capacity.checked_mul(std::mem::size_of::<T>()).and_then(|n|n.checked_mul(4))else{return self.overflow()};
   if !self.grow(extra){return false}let old_capacity=rows.capacity();let mut next=Vec::new();if let Err(actual)=next.try_reserve_exact(capacity){return self.fail(io::Error::new(io::ErrorKind::OutOfMemory,actual))}
   let Some(delta)=next.capacity().checked_sub(old_capacity).and_then(|n|n.checked_mul(std::mem::size_of::<T>()))else{return self.overflow()};let Some(release)=extra.checked_sub(delta)else{return self.fail(io::Error::new(io::ErrorKind::OutOfMemory,"primary vector allocator exceeded admitted growth peak"))};
   next.append(rows);*rows=next;if !self.release(release){return false}
  }
  rows.push(value);true
 }
 pub(super) fn text(&self,text:&str)->Option<String>{
  let Some(extra)=text.len().checked_mul(4)else{self.overflow();return None};if !self.grow(extra){return None}let mut out=String::new();if let Err(actual)=out.try_reserve_exact(text.len()){self.fail(io::Error::new(io::ErrorKind::OutOfMemory,actual));return None}let Some(release)=extra.checked_sub(out.capacity())else{self.fail(io::Error::new(io::ErrorKind::OutOfMemory,"primary string allocator exceeded admitted growth peak"));return None};out.push_str(text);self.release(release).then_some(out)
 }
 pub(super) fn diagnostic_parts(&self,rows:&mut Vec<Diagnostic>,span:Span,kind:DiagnosticKind,message:&str)->bool{let Some(message)=self.text(message)else{return false};self.push(rows,Diagnostic{span,kind,message})}
 /// SAME existing worker stack resource contract, not a grammar nesting limit.
 /// One admitted cleanup frame beyond actual parser/inventory recursion ensures
 /// unwinding can safely drop the unique just-produced child tree as well.
 pub(super) fn frame(&self)->Option<crate::setting_expression::SettingParserFrame<'_,'b>>{
  let frame=match self.a.parser_frame(){Ok(frame)=>frame,Err(actual)=>{self.fail(actual);return None}};
  if let Err(actual)=self.a.admit_drop_depth(1){drop(frame);self.fail(actual);return None}Some(frame)
 }
 pub(super) fn temporary(&self,bytes:usize)->Option<crate::SettingRootLease>{if !self.poll(){return None}match self.a.reserve(bytes){Ok(lease)=>Some(lease),Err(actual)=>{self.fail(actual);None}}}
 pub(super) fn layout(&self,source:&str,tokens:&[SpanToken],line_width:usize)->Option<crate::SettingRootLease>{
  let(mut boundaries,mut multiline)=(8usize,0usize);for token in tokens{if !self.poll(){return None}if token.kind==TokenKind::Newline||matches!(token.text(source),"{"|"}"|";"|"("){let Some(next)=boundaries.checked_add(2)else{self.overflow();return None};boundaries=next}if token.kind==TokenKind::String&&token.text(source).contains('\n'){multiline+=1;}}
  // Exactly two byte masks plus the simultaneous input/output line vectors,
  // their geometric old/new growth overlap, and actual multiline span roster.
  let bytes=source.len().checked_mul(2).and_then(|n|boundaries.checked_mul(line_width).and_then(|rows|rows.checked_mul(8)).and_then(|rows|n.checked_add(rows))).and_then(|n|multiline.checked_mul(std::mem::size_of::<Span>()).and_then(|rows|rows.checked_mul(4)).and_then(|rows|n.checked_add(rows)));let Some(bytes)=bytes else{self.overflow();return None};
  self.temporary(bytes)
 }
 pub(super) fn compact(&self,count:usize)->Option<crate::SettingRootLease>{let Some(bytes)=count.checked_mul(std::mem::size_of::<Item>()).and_then(|n|n.checked_mul(8))else{self.overflow();return None};self.temporary(bytes)}
 fn item_bytes(&self,items:&Vec<Item>)->Option<usize>{let mut bytes=items.capacity().checked_mul(std::mem::size_of::<Item>())?;if items.is_empty(){return Some(bytes)}let _frame=self.frame()?;for item in items{if !self.poll(){return None}bytes=bytes.checked_add(item.header.capacity())?.checked_add(self.item_bytes(&item.children)?)?;}Some(bytes)}
 fn diagnostic_bytes(&self,rows:&Vec<Diagnostic>)->Option<usize>{let mut bytes=rows.capacity().checked_mul(std::mem::size_of::<Diagnostic>())?;for row in rows{if !self.poll(){return None}bytes=bytes.checked_add(row.message.capacity())?;}Some(bytes)}
 pub(super) fn discard_item(&self,item:Item)->bool{let bytes=self.item_bytes(&item.children).and_then(|n|n.checked_add(item.header.capacity()));drop(item);match bytes{Some(bytes)=>self.release(bytes),None=>self.overflow()}}
 pub(super) fn transfer_compacted_vector(&self,old_capacity:usize,new_capacity:usize)->bool{let Some(release)=old_capacity.checked_sub(new_capacity).and_then(|n|n.checked_mul(std::mem::size_of::<Item>()))else{return self.fail(io::Error::new(io::ErrorKind::InvalidData,"compacted primary vector exceeded funded native input capacity"))};self.release(release)}
 pub(super) fn finish(self,items:&Vec<Item>,tokens:&Vec<SpanToken>,diagnostics:&Vec<Diagnostic>)->io::Result<crate::SettingRootLease>{
  if let Some(actual)=self.take_failure(){return Err(actual)}let target=self.item_bytes(items).and_then(|n|tokens.capacity().checked_mul(std::mem::size_of::<SpanToken>()).and_then(|tokens|n.checked_add(tokens))).and_then(|n|self.diagnostic_bytes(diagnostics).and_then(|diags|n.checked_add(diags))).and_then(|n|n.checked_add(std::mem::size_of::<OriginalDeclarationSkeleton>()));let Some(target)=target else{return Err(self.take_failure().unwrap_or_else(||io::Error::from(io::ErrorKind::OutOfMemory)))};
  let excess=self.bytes().checked_sub(target).ok_or_else(||io::Error::new(io::ErrorKind::InvalidData,"native primary final storage lacks actual allocation funding"))?;if !self.release(excess){return Err(self.take_failure().unwrap_or_else(||io::Error::from(io::ErrorKind::OutOfMemory)))}Ok(self.owned.into_inner())
 }
}
