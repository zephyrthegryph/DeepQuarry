//! Original filter checks after RHS evaluation in the existing call transition.
use super::*;
use crate::checker_expression_visit::{ArgumentObserver,NamedArguments,OriginalArguments,OriginalValue};
use crate::checker_original_expression_debug::{CallDebug,with_call_debug};
struct Filter<'archive,'body,'loan,'work,W,R:?Sized>{inner:Arguments<'archive,'work,W,R>,body:&'loan ArchivedBody<'body>}
fn allowed(kind:&str)->Option<&'static [&'static str]>{Some(match kind{
 "alpha"=>&["x","y","icon","render_source","flags"],"angular_blur"=>&["x","y","size"],"bloom"=>&["threshold","size","offset","alpha"],"color"=>&["color","space"],"displace"=>&["x","y","size","icon","render_source"],"drop_shadow"=>&["x","y","size","offset","color"],"blur"=>&["size"],"layer"=>&["x","y","icon","render_source","flags","color","transform","blend_mode"],"motion_blur"=>&["x","y"],"outline"=>&["size","color","flags"],"radial_blur"=>&["x","y","size"],"rays"=>&["x","y","size","color","offset","density","threshold","factor","flags"],"ripple"=>&["x","y","size","repeat","radius","falloff","flags"],"wave"=>&["x","y","size","offset","flags"],_=>return None})}
fn flags(kind:&str)->Option<(&'static str,bool,bool,&'static [&'static str])>{Some(match kind{
 "alpha"=>("flags",false,true,&["MASK_INVERSE","MASK_SWAP"]),"color"=>("space",true,false,&["FILTER_COLOR_RGB","FILTER_COLOR_HSV","FILTER_COLOR_HSL","FILTER_COLOR_HCY"]),"layer"=>("flags",true,true,&["FILTER_OVERLAY","FILTER_UNDERLAY"]),"rays"=>("flags",false,true,&["FILTER_OVERLAY","FILTER_UNDERLAY"]),"outline"=>("flags",false,true,&["OUTLINE_SHARP","OUTLINE_SQUARE"]),"ripple"=>("flags",false,true,&["WAVE_BOUNDED"]),"wave"=>("flags",false,true,&["WAVE_SIDEWAYS","WAVE_BOUNDED"]),_=>return None})}
fn actual_filter(fact:&CallableFact,name:&str)->bool{name=="filter"&&fact.owner()==Some(SymbolId::of("/"))}
fn follows(expr:&Expr)->bool{match &expr.kind{ExprKind::Unary{op,..}=>matches!(op.as_str(),"-"|"!"|"~"|"pre++"|"post++"|"pre--"|"post--"|"&"|"*"),ExprKind::Member{..}|ExprKind::SafeMember{..}|ExprKind::StaticMember{..}|ExprKind::Index{..}|ExprKind::SafeIndex{..}=>true,ExprKind::Call{callee,..}=>matches!(callee.kind,ExprKind::Member{..}|ExprKind::SafeMember{..}|ExprKind::StaticMember{..}),_=>false}}
impl<W:EffectReportWork,R:Resolver+?Sized> Filter<'_,'_,'_,'_,W,R>{
 fn emit(&mut self,at:Option<Span>,expression:Span,message:String,kind:Option<&str>)->Result<(),PolicyFailure>{let mut notes=Vec::new();if let Some(kind)=kind{let note=Note{message:text(self.inner.work,format_args!("See: http://www.byond.com/docs/ref/#/{{notes}}/filters/{kind} for the permitted arguments"))?,source:None};push(self.inner.work,&mut notes,note)?;}self.inner.emit("filter_call",at,expression,message,notes)}
 fn static_string(&mut self,value:Option<OriginalValue<'_>>)->Result<Option<String>,PolicyFailure>{let Some(OriginalValue::Literal(value))=value else{return Ok(None)};let width=value.as_str().len();reserve(self.inner.work,width.checked_mul(4).and_then(|n|n.checked_add(size_of::<String>()+128)).ok_or_else(oom)?)?;let mut output=String::new();output.try_reserve_exact(width).map_err(|e|PolicyFailure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,e)))?;if output.capacity()>width.checked_mul(4).ok_or_else(oom)?{return Err(oom())}let found=value.write_pinned_static_text(&mut Fixed(&mut output)).map_err(|e|format!("filter actual static value: {e:?}"))?;Ok(found.then_some(output))}
 fn flag(&mut self,expr:&Expr,kind:&str,field:&str,exclusive:bool,zero:bool,valid:&[&str],at:Option<Span>,expression:Span)->Result<(),PolicyFailure>{
  let mut pending=Vec::new();push(self.inner.work,&mut pending,expr)?;while let Some(expr)=pending.pop(){self.inner.poll()?;
   if let ExprKind::Binary{op,lhs,rhs}=&expr.kind{if op=="|"{if exclusive{let message=text(self.inner.work,format_args!("filter(type=\"{kind}\") '{field}' parameter must have one value, found bitwise OR"))?;self.emit(at,expression,message,Some(kind))?;}else{push(self.inner.work,&mut pending,rhs.as_ref())?;push(self.inner.work,&mut pending,lhs.as_ref())?;}continue}}
   if follows(expr){let message=text(self.inner.work,format_args!("filter() flag fields cannot have unary ops or field accesses"))?;self.emit(at,expression,message,None)?;continue}
   if matches!(expr.kind,ExprKind::Binary{..}|ExprKind::Conditional{..}){let message=text(self.inner.work,format_args!("filter(type=\"{kind}\"), extremely invalid value passed to '{field}' field"))?;self.emit(at,expression,message,Some(kind))?;continue}
   if let ExprKind::Ident(name)=&expr.kind{if !matches!(name.as_str(),"null"|"__TYPE__"|"__PROC__"|"__IMPLIED_TYPE__"){if !valid.contains(&name.as_str()){let message=text(self.inner.work,format_args!("filter(type=\"{kind}\") called with invalid '{field}' flag '{name}'"))?;self.emit(at,expression,message,Some(kind))?;}continue}}
   if zero&&matches!(&expr.kind,ExprKind::Literal(value)if matches!(dm_syntax::numeric_form::numeric_form(value.as_str()),Ok(dm_syntax::numeric_form::NumericForm::Integer(0)))){continue}
   let body=self.body;let checkpoint=self.inner.checkpoint;with_call_debug(body,CallDebug::Term(expr),checkpoint,|word|{let message=text(self.inner.work,format_args!("filter(type=\"{kind}\") called with invalid '{field}' value '{word}'"))?;self.emit(at,expression,message,Some(kind))})?;
  }Ok(())
 }
}
impl<W:EffectReportWork,R:Resolver+?Sized> ArgumentObserver<PolicyFailure> for Filter<'_,'_,'_,'_,W,R>{
 fn reserve(&mut self,bytes:usize)->Result<(),PolicyFailure>{reserve(self.inner.work,bytes)}
 fn original_values(&self)->bool{true}
 fn begin_call(&mut self,tree:&dm_tree::SemanticTree,fact:&CallableFact,name:&str)->Result<(),PolicyFailure>{self.inner.begin_call(tree,fact,name)}
 fn argument(&mut self,tree:&dm_tree::SemanticTree,fact:&CallableFact,name:&str,key:Option<&Expr>,after_keyword:bool,at:Option<Span>,expression:Span)->Result<(),PolicyFailure>{if actual_filter(fact,name){self.inner.argument(tree,fact,name,key,after_keyword,at,expression)?;}Ok(())}
 fn finished(&mut self,tree:&dm_tree::SemanticTree,fact:&CallableFact,name:&str,_args:&[Expr],named:&NamedArguments<'_>,values:OriginalArguments<'_>,at:Option<Span>,expression:Span)->Result<(),PolicyFailure>{
  self.inner.poll()?;if !std::ptr::eq(tree,self.inner.archive.tree()){return Err("filter actual tree differs from archive".into())}if !actual_filter(fact,name){return Err("filter post-evaluation callback has another actual target".into())}
  if !values.type_present{if !values.first_arglist{let message=text(self.inner.work,format_args!("filter() called without mandatory keyword parameter 'type'"))?;self.emit(at,expression,message,None)?;}return Ok(())}
  let Some(kind)=self.static_string(values.type_value)?else{let body=self.body;let checkpoint=self.inner.checkpoint;return with_call_debug(body,CallDebug::Value(values.type_value),checkpoint,|word|{let message=text(self.inner.work,format_args!("filter() called with non-string type keyword parameter value '{word}'"))?;self.emit(at,expression,message,None)})};
  let Some(valid)=allowed(&kind)else{let message=text(self.inner.work,format_args!("filter() called with invalid type keyword parameter value '{kind}'"))?;self.emit(at,expression,message,None)?;return Ok(())};
  // Preserve the pinned foldhash iteration domain. Multiple invalid keyword
  // order is deliberately not sorted or advertised as deterministic.
  for key in named.keys(){self.inner.poll()?;if key.as_ref()!="type"&&key.as_ref()!="name"&&!valid.contains(&key.as_ref()){let message=text(self.inner.work,format_args!("filter(type=\"{kind}\") called with invalid keyword parameter '{key}'"))?;self.emit(at,expression,message,Some(&kind))?;}}
  if let Some((field,exclusive,zero,valid))=flags(&kind){if let Some(expr)=named.get(field){self.flag(expr,&kind,field,exclusive,zero,valid,at,expression)?;}}Ok(())
 }
}
pub fn with_archived_body<W:EffectReportWork,R:Resolver+?Sized>(archive:&BodyArchive,body:&ArchivedBody<'_>,resolver:&R,profile:PackedU128,work:&mut W,checkpoint:&dyn Fn()->io::Result<()>,consume:impl FnOnce(&Findings<'_>)->Result<(),PolicyFailure>)->Result<(),PolicyFailure>{
 checkpoint().map_err(PolicyFailure::Operational)?;if !body.belongs_to(archive)||resolver.source_owner()!=Some(std::ptr::from_ref(archive.tree()).cast()){return Err("filter body/resolver belongs to another actual archive".into())}archive.tree().validate_checker_builtin_profile(profile).map_err(|e|format!("filter profile: {e:?}"))?;
 let mut observer=Filter{inner:Arguments{archive,profile,work,checkpoint,resolver,rows:Vec::new()},body};let pending=(||{crate::checker_expression_visit::call_arguments_archived(archive,body,resolver,profile,checkpoint,&mut observer)?;let findings=Findings::from_rows(archive,std::mem::take(&mut observer.inner.rows));checkpoint().map_err(PolicyFailure::Operational)?;consume(&findings)?;Ok(())})();if matches!(&pending,Err(PolicyFailure::Operational(_))){return pending}checkpoint().map_err(PolicyFailure::Operational)?;pending
}
