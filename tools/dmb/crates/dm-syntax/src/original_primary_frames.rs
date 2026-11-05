//! Retained traversal DATA for the SAME primary layout/header/Item kernels.
//! No source EOF/model authority is issued by this internal frame machine.
use super::*;
use std::io;

#[derive(Clone,Copy)]struct Scope{indent:usize,in_body:bool,skeleton:bool,var_context:Option<u8>}
impl Scope{
 fn context<'s,'observer,'budget>(&self,tokens:&'s[SpanToken],original:&'s OriginalParseState<'s,'observer,'budget>)->ParseContext<'s,'observer,'budget>{ParseContext{in_body:self.in_body,skeleton:self.skeleton,tokens,original:Some(original),var_context:self.var_context}}
}
// Marker belongs only to this exact pending header, registered by its actual
// scoped callback. It is consumed with that row, never a global role/grant.
struct PendingPrimary{line:Line,scoped_observer:bool}
struct OpenPrimary{line:Line,prepared:PreparedPrimaryLine}
struct Frame<'a,'budget>{
 scope:Scope,pending:Option<PendingPrimary>,open:Option<OpenPrimary>,items:Vec<Item>,saw_item:bool,last_end:usize,
 _stack:crate::setting_expression::SettingParserFrame<'a,'budget>,
}
pub(super) struct NativeOriginalPrimaryFrames<'a,'budget>{
 frames:Vec<Frame<'a,'budget>>,finished:bool,live_header:Option<(usize,usize)>,
 // Last field: all frame coordination is physically freed before its credit.
 coord:crate::SettingRootLease,a:&'a crate::SettingAdmission<'budget>,
}
impl<'a,'budget> NativeOriginalPrimaryFrames<'a,'budget>{
 fn actual(&self,e:io::Error)->io::Error{self.a.take_operational_error().unwrap_or(e)}
 pub(super) fn new(a:&'a crate::SettingAdmission<'budget>)->io::Result<Self>{
  let coord=a.reserve(0).map_err(|e|a.take_operational_error().unwrap_or(e))?;let mut out=Self{frames:Vec::new(),finished:false,live_header:None,coord,a};out.push(Scope{indent:0,in_body:false,skeleton:true,var_context:None},0)?;Ok(out)
 }
 fn push(&mut self,scope:Scope,prior_end:usize)->io::Result<()>{
  let stack=self.a.parser_frame().map_err(|e|self.actual(e))?;let drop_depth=self.frames.len().checked_add(1).ok_or(io::ErrorKind::OutOfMemory)?;self.a.admit_drop_depth(drop_depth).map_err(|e|self.actual(e))?;
  if self.frames.len()==self.frames.capacity(){
   let capacity=self.frames.capacity().max(2).checked_mul(2).ok_or(io::ErrorKind::OutOfMemory)?;let peak=capacity.checked_mul(std::mem::size_of::<Frame<'a,'budget>>()).and_then(|n|n.checked_mul(4)).ok_or(io::ErrorKind::OutOfMemory)?;self.a.grow(&mut self.coord,peak).map_err(|e|self.a.take_operational_error().unwrap_or(e))?;
   let mut next=Vec::new();if let Err(e)=next.try_reserve_exact(capacity){return Err(io::Error::new(io::ErrorKind::OutOfMemory,e))}let old=self.frames.capacity();let growth=next.capacity().checked_sub(old).and_then(|n|n.checked_mul(std::mem::size_of::<Frame<'a,'budget>>())).ok_or(io::ErrorKind::OutOfMemory)?;let release=peak.checked_sub(growth).ok_or_else(||io::Error::new(io::ErrorKind::OutOfMemory,"primary frame allocator exceeded actual admitted peak"))?;next.append(&mut self.frames);self.frames=next;self.a.shrink(&mut self.coord,release).map_err(|e|self.a.take_operational_error().unwrap_or(e))?;
  }
  self.frames.push(Frame{scope,pending:None,open:None,items:Vec::new(),saw_item:false,last_end:prior_end,_stack:stack});Ok(())
 }
 fn check(&self,original:&OriginalParseState<'_,'_,'_>)->io::Result<()>{
  if self.finished||!std::ptr::eq(self.a,original.storage.a){return Err(io::Error::new(io::ErrorKind::InvalidInput,"retained primary frames are finished or belong to a foreign actual host"))}self.a.checkpoint().map_err(|e|self.actual(e))
 }
 fn resolve(&mut self,source:&str,tokens:&[SpanToken],child:Option<&Line>,original:&OriginalParseState<'_,'_,'_>,diagnostics:&mut Vec<Diagnostic>)->io::Result<bool>{
  let Some(frame)=self.frames.last_mut()else{return Err(io::ErrorKind::InvalidInput.into())};let Some(pending)=frame.pending.take()else{return Ok(true)};let line=pending.line;let scope=frame.scope;
  let child=child.filter(|next|next.indent>line.indent);let context=scope.context(tokens,original);let Some(prepared)=prepare_primary_line(source,&line,child,context,diagnostics,pending.scoped_observer)else{return Ok(false)};
  if let Some(child)=child{
   let scope=Scope{indent:child.indent,in_body:scope.in_body||matches!(prepared.kind,ItemKind::Proc|ItemKind::Verb|ItemKind::Statement),skeleton:scope.skeleton&&(scope.in_body||!matches!(prepared.kind,ItemKind::Statement)),var_context:prepared.var_context};let prior_end=line.end;frame.open=Some(OpenPrimary{line,prepared});self.push(scope,prior_end)?;
  }else{let end=line.end;if !commit_primary_item(source,&line,prepared.kind,end,Vec::new(),false,prepared.outer,context,&mut frame.items){return Ok(false)}frame.saw_item=true;frame.last_end=end;}
  Ok(true)
 }
 fn close_child(&mut self,source:&str,tokens:&[SpanToken],original:&OriginalParseState<'_,'_,'_>)->io::Result<bool>{
  let Some(mut child)=self.frames.pop()else{return Err(io::ErrorKind::InvalidInput.into())};
  let items=std::mem::take(&mut child.items);let items=if child.scope.skeleton&&child.scope.in_body{match original.storage.compact(items.len()){Some(_temporary)=>retain_setting_chains(items,Some(original)),None=>return Ok(false)}}else{items};let child_end=child.last_end;
  // Exactly like returning from the old recursive call, release this actual
  // worker frame only AFTER its unique compaction judge has finished.
  drop(child);let Some(parent)=self.frames.last_mut()else{return Err(io::ErrorKind::InvalidInput.into())};let Some(open)=parent.open.take()else{return Err(io::Error::new(io::ErrorKind::InvalidInput,"retained native child has no actual parent header"))};let context=parent.scope.context(tokens,original);let end=if parent.scope.skeleton{child_end}else{items.last().map_or(open.line.end,|item|item.span.end)};
  if !commit_primary_item(source,&open.line,open.prepared.kind,end,items,true,open.prepared.outer,context,&mut parent.items){return Ok(false)}parent.saw_item=true;parent.last_end=end;Ok(true)
 }
 fn begin_line_scope(&mut self,source:&str,tokens:&[SpanToken],line:&Line,original:&OriginalParseState<'_,'_,'_>,diagnostics:&mut Vec<Diagnostic>)->io::Result<bool>{
  self.check(original)?;if original.stopped(){return Ok(false)}if !self.resolve(source,tokens,Some(line),original,diagnostics)?{return Ok(false)}
  loop{let Some(top)=self.frames.last()else{return Err(io::ErrorKind::InvalidInput.into())};if line.indent>=top.scope.indent&&!(line.indent>top.scope.indent&&top.saw_item){break}if self.frames.len()==1{
   let header=source.get(line.header_start..line.header_end).unwrap_or_default();
   let excerpt:String=header.chars().take(96).collect();
   return Err(io::Error::new(io::ErrorKind::Unsupported,format!(
    "Original retained primary root has an unissued relative-indentation frontier: indent {} after root {} near {excerpt:?}",
    line.indent,top.scope.indent
   )))
  }if !self.close_child(source,tokens,original)?{return Ok(false)}}
  Ok(true)
 }
 /// Only the SAME structural cursor can construct this event. Resolve
 /// previous completed header/parents once using actual observed indentation;
 /// no current header/body or following token is guessed or reparsed here.
 pub(super) fn begin_early_header(&mut self,source:&str,tokens:&[SpanToken],start:NativePrimaryHeaderStart,original:&OriginalParseState<'_,'_,'_>,diagnostics:&mut Vec<Diagnostic>)->io::Result<bool>{
  if self.live_header.is_some(){return Err(io::Error::new(io::ErrorKind::InvalidInput,"actual live primary header already exists"))}
  if !self.begin_line_scope(source,tokens,&start.line,original,diagnostics)?{return Ok(false)}self.live_header=Some((start.line.header_start,start.line.indent));Ok(true)
 }
 /// Scalar locator only; source/token borrows are obtained only during the
 /// actual metadata callback and MUST end before another demand/growth pull.
 pub(super) fn live_header_scope(&self,original:&OriginalParseState<'_,'_,'_>)->io::Result<Option<(usize,usize,bool,Option<usize>)>>{
  self.check(original)?;let Some((start,indent))=self.live_header else{return Ok(None)};let frame=self.frames.last().ok_or(io::ErrorKind::InvalidData)?;Ok(Some((start,indent,frame.scope.in_body,original.first_outer_block.get())))
 }
 pub(super) fn line(&mut self,source:&str,tokens:&[SpanToken],line:Line,original:&OriginalParseState<'_,'_,'_>,diagnostics:&mut Vec<Diagnostic>)->io::Result<bool>{
  self.line_scoped(source,tokens,line,original,diagnostics,None)
 }
 pub(super) fn line_scoped(&mut self,source:&str,tokens:&[SpanToken],line:Line,original:&OriginalParseState<'_,'_,'_>,diagnostics:&mut Vec<Diagnostic>,observer:Option<&mut dyn OriginalDeclarationHeaderObserver>)->io::Result<bool>{
  self.check(original)?;if original.stopped(){return Ok(false)}
  if let Some((start,indent))=self.live_header.take(){if start!=line.header_start||indent!=line.indent{return Err(io::Error::new(io::ErrorKind::InvalidInput,"completed header differs from its actual early primary owner"))}}else if !self.begin_line_scope(source,tokens,&line,original,diagnostics)?{return Ok(false)}
  let frame=self.frames.last_mut().unwrap();if line.indent>frame.scope.indent{let span=Span::new(line.header_start,line.header_end);if !original.storage.diagnostic_parts(diagnostics,span,DiagnosticKind::Indentation,"unexpected indentation"){return Ok(false)}}
  // Crucially before asking the producer for another line/include. The SAME
  // private comma producer and SAME tree-owned formal observer are called once.
  let scoped_observer=observer.is_some();if !original_header_before_child_lookahead_scoped(source,&line,frame.scope.context(tokens,original),&mut frame.items,observer){return Ok(false)}frame.pending=Some(PendingPrimary{line,scoped_observer});Ok(true)
 }
 pub(super) fn finish(mut self,source:&str,tokens:&[SpanToken],original:&OriginalParseState<'_,'_,'_>,diagnostics:&mut Vec<Diagnostic>,actual_eof:bool)->io::Result<Vec<Item>>{
  self.check(original)?;
  if !actual_eof&&!original.stopped(){return Err(io::Error::new(io::ErrorKind::InvalidInput,"primary pause cannot be sealed as EOF or an authenticated fatal outcome"))}
  if actual_eof&&!original.stopped()&&!self.resolve(source,tokens,None,original,diagnostics)?{return Err(original.storage.take_failure().unwrap_or_else(||io::Error::new(io::ErrorKind::Unsupported,"primary final line has no issued native outcome")))}
  while self.frames.len()>1{if !self.close_child(source,tokens,original)?{return Err(original.storage.take_failure().unwrap_or_else(||io::Error::new(io::ErrorKind::Unsupported,"primary prefix child could not commit")))}}
  let mut root=self.frames.pop().ok_or(io::ErrorKind::InvalidInput)?;if root.pending.is_some()||root.open.is_some(){return Err(io::Error::new(io::ErrorKind::InvalidInput,"primary seal retains unresolved actual header state"))}self.finished=true;Ok(std::mem::take(&mut root.items))
 }
}

#[cfg(test)]mod tests{
 use super::*;use std::sync::{Arc,atomic::{AtomicUsize,Ordering}};
 fn state<'a,'budget>(a:&'a crate::SettingAdmission<'budget>)->OriginalParseState<'a,'static,'budget>{OriginalParseState{storage:original_storage::Storage::new(a).unwrap(),fatal:Default::default(),unavailable:Default::default(),operational:Default::default(),observer:None,observer_stop:Default::default(),first_outer_block:Default::default()}}
 #[test]fn actual_retained_primary_frames_match_existing_whole_traversal_without_reparsing_prior_headers(){
  for source in["/datum/a\n    var/value=1\n    proc/p()\n        return 2\n/datum/b\n", "/proc/p()\n    if(1)\n        set name=\"actual\"\n    else\n        return\n    return 2\n", "/datum/a\n    proc/p() { return 1; }\n    var/next=2\n"]{
   let counter=Arc::new(AtomicUsize::new(0));let a=crate::SettingAdmission::new(&counter,4<<20,&||Ok(()));let original=state(&a);let tokens=lex_spans(source).tokens;let lines=original_declaration_lines(source,Span::new(0,source.len()),&tokens);let mut frames=NativeOriginalPrimaryFrames::new(&a).unwrap();let mut diagnostics=Vec::new();for line in lines{assert!(frames.line(source,&tokens,line,&original,&mut diagnostics).unwrap());}let actual=frames.finish(source,&tokens,&original,&mut diagnostics,true).unwrap();let expected=parse_declaration_skeleton(source);assert_eq!(format!("{actual:?}"),format!("{:?}",expected.items));assert_eq!(diagnostics,expected.diagnostics);drop(actual);drop(original);assert_eq!(counter.load(Ordering::Acquire),0);
  }
 }
 #[test]fn actual_comma_primary_stop_never_requests_a_future_line_and_retains_real_prefix_only(){
  let source="/datum/a\n    var/first,second\n/proc/later()\n    return 2\n";let counter=Arc::new(AtomicUsize::new(0));let a=crate::SettingAdmission::new(&counter,4<<20,&||Ok(()));let original=state(&a);let tokens=lex_spans(source).tokens;let lines=original_declaration_lines(source,Span::new(0,source.len()),&tokens);let mut frames=NativeOriginalPrimaryFrames::new(&a).unwrap();let mut diagnostics=Vec::new();let mut consumed=0;for line in lines{consumed+=1;if !frames.line(source,&tokens,line,&original,&mut diagnostics).unwrap(){break}}assert_eq!(consumed,2);let fatal=original.fatal.borrow().unwrap();assert_eq!(fatal.token_span().start,source.find(',').unwrap());let items=frames.finish(source,&tokens,&original,&mut diagnostics,false).unwrap();assert_eq!(items.len(),1);assert_eq!(items[0].children.len(),1);assert!(items[0].children[0].header.ends_with("first"));assert!(diagnostics.is_empty());drop(items);drop(original);assert_eq!(counter.load(Ordering::Acquire),0);
 }
}
