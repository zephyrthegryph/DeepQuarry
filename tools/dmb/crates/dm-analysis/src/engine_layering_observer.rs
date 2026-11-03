//! Original Engine Walker::expr_one/block over the SAME issued native body.
//! Prefix/follow structure is borrowed; no generic receiver inference or calls'
//! return hints. Existing canonical policy walker owns header/block ordering.
use super::*;use dm_syntax::{Expr,ExprKind,Statement,StatementKind,ForControl,Span};
use dm_tree::frontend::ArchivedBody;use std::collections::BTreeMap;
#[derive(Clone,Copy,Debug,Eq,PartialEq)]pub enum Use<'a>{Type(&'a str),Method{owner:&'a str,name:&'a str},Global(&'a str)}
struct Walker<'m,'b,'a,'w,W:WorkspaceWork,F>{model:&'m Model<'a>,body:&'b ArchivedBody<'a>,work:&'w mut W,emit:&'w mut F,file:String,line:u32,owner:String,locals:BTreeMap<String,String>}
impl<W:WorkspaceWork,F:for<'x>FnMut(&str,u32,Use<'x>,&mut W)->Result<(),W::Error>> Walker<'_,'_,'_,'_,W,F>{
 fn event(&mut self,e:Use<'_>)->Result<(),W::Error>{self.work.checkpoint()?;(self.emit)(&self.file,self.line,e,self.work)}
 fn copy(&mut self,s:&str)->Result<String,W::Error>{self.work.checkpoint()?;if W::CHECKED{let bytes=s.len().checked_mul(16).and_then(|n|n.checked_add(1024)).ok_or_else(||self.work.overflow())?;self.work.temporary(bytes)?;}Ok(s.to_owned())}
 fn type_use(&mut self,ty:&str)->Result<(),W::Error>{self.event(Use::Type(ty))}
 fn method_use(&mut self,owner:&str,name:&str)->Result<(),W::Error>{self.event(Use::Method{owner,name})}
 fn owner_copy(&mut self)->Result<String,W::Error>{self.work.checkpoint()?;if W::CHECKED{let bytes=self.owner.len().checked_mul(16).and_then(|n|n.checked_add(1024)).ok_or_else(||self.work.overflow())?;self.work.temporary(bytes)?;}Ok(self.owner.clone())}
 fn scoped_call(&mut self,name:&str)->Result<(),W::Error>{let owner=self.owner_copy()?;if self.model.method(&owner,name,self.work)?.is_some(){self.method_use(&owner,name)}else{self.event(Use::Global(name))}}
 fn at(&mut self,span:Span)->Result<(),W::Error>{self.work.checkpoint()?;let source=self.model.inputs.archive().original_policy_line(span.start).map_err(Unsupported)?;self.line=self.model.point(&source.path,source.line,self.work)?.1;Ok(())}
 fn bind(&mut self,st:&Statement)->Result<(),W::Error>{self.at(st.span)?;let source=self.body.source_locals().map_err(Unsupported)?;let entries=source.in_span(st.header_span).map_err(Unsupported)?;
  if matches!(&st.kind,StatementKind::For{control:ForControl::Pair{..},..}){for value in entries.iter().skip(1){self.work.checkpoint()?;if W::CHECKED{let bytes=source.type_path_width(value).map_err(Unsupported)?.checked_mul(16).and_then(|n|n.checked_add(512)).ok_or_else(||self.work.overflow())?;self.work.temporary(bytes)?;}if source.type_path(value).map_err(Unsupported)?.is_some(){return Err("engine original key/value value-typed binding grammar is unissued".into())}}}
  let take=match &st.kind{StatementKind::Var{..}=>usize::MAX,StatementKind::For{control:ForControl::All{..}|ForControl::Each{..},..}=>1,StatementKind::For{control:ForControl::Pair{..},..}=>1,StatementKind::For{control:ForControl::CStyle{..},..}=>usize::MAX,_=>0};
  for fact in entries.iter().take(take){self.work.checkpoint()?;if fact.source_kind==dm_syntax::LocalSourceKind::CommaContinuation{return Err("engine original simultaneous comma-local binding needs issued statement-group contract".into())}if W::CHECKED{let bytes=source.type_path_width(fact).map_err(Unsupported)?.checked_mul(16).and_then(|n|n.checked_add(512)).ok_or_else(||self.work.overflow())?;self.work.temporary(bytes)?;}let Some(ty)=source.type_path(fact).map_err(Unsupported)?else{continue};let name=source.name(fact).map_err(Unsupported)?;if W::CHECKED{let bytes=name.len().checked_add(ty.len()).and_then(|n|n.checked_mul(4)).and_then(|n|n.checked_add(512)).ok_or_else(||self.work.overflow())?;self.work.retain(bytes)?;}self.type_use(&ty)?;self.locals.insert(name.to_owned(),ty);
  }Ok(())
 }
 fn prefab(&mut self,expr:&Expr)->Result<Option<String>,W::Error>{let path=match &expr.kind{ExprKind::TypePath(path)=>path,ExprKind::ObjectInitializer{object,..}=>return self.prefab(object),_=>return Ok(None)};self.work.checkpoint()?;if W::CHECKED{let bytes=path.len().checked_mul(4).and_then(|n|n.checked_add(512)).ok_or_else(||self.work.overflow())?;self.work.temporary(bytes)?;}let mut normalized=String::new();for part in path.split(['/', '.', ':']).filter(|p|!p.is_empty()){self.work.checkpoint()?;normalized.push('/');normalized.push_str(part);}Ok(Some(normalized))}
 /// SAME ExprOne term then follow order. Structural native callee/object nodes
 /// are not mistaken for extra old Expression::Base observations.
 fn chain(&mut self,e:&Expr,depth:usize)->Result<Option<String>,W::Error>{self.work.checkpoint()?;if depth>128{return Err("engine original prefix/follow recursion exceeds admitted native depth".into())}match &e.kind{
  ExprKind::Ident(name)if name=="src"=>{self.owner_copy().map(Some)},
  ExprKind::Ident(name)if !matches!(name.as_str(),"null"|"__PROC__"|"__TYPE__"|"__IMPLIED_TYPE__")=>{if let Some(ty)=self.locals.get(name){if W::CHECKED{let bytes=ty.len().checked_mul(16).and_then(|n|n.checked_add(1024)).ok_or_else(||self.work.overflow())?;self.work.temporary(bytes)?;}return Ok(Some(ty.clone()))}let owner=self.owner_copy()?;if let Some(ty)=self.model.declared(&owner,name,self.work)?{if !ty.is_empty(){self.type_use(&ty)?;}Ok(Some(ty))}else{Ok(None)}},
  ExprKind::TypePath(_)|ExprKind::ObjectInitializer{..}=>{let ty=self.prefab(e)?.ok_or("engine original prefab primary path unavailable")?;self.type_use(&ty)?;Ok(Some(ty))},
  ExprKind::Member{object,selector,..}|ExprKind::SafeMember{object,selector,..}=>{if let Some(owner)=self.chain(object,depth+1)?{if let Some(ty)=self.model.declared(&owner,selector,self.work)?{if !ty.is_empty(){self.type_use(&ty)?;}return Ok(Some(ty))}}Ok(None)},
  ExprKind::StaticMember{object,selector}=>{let owner=self.chain(object,depth+1)?;if let Some(ty)=owner.as_deref().filter(|s|!s.is_empty()){self.method_use(ty,selector)?;}else if matches!(&object.kind,ExprKind::Ident(n)if n=="src"){let owner=self.owner_copy()?;self.method_use(&owner,selector)?;}Ok(owner)},
  ExprKind::Index{object,..}|ExprKind::SafeIndex{object,..}=>{let _=self.chain(object,depth+1)?;Ok(None)},
  ExprKind::Unary{op,value}if !matches!(op.as_str(),"new"|"::")=>self.chain(value,depth+1),
  ExprKind::Call{callee,..}=>{match dm_syntax::call_target(callee){dm_syntax::CallTarget::Named(name)if !matches!(name,"new"|"list"|"alist"|"input"|"locate"|"pick"|"call"|"call_ext"|"as"|"."|"..")=>self.scoped_call(name)?,dm_syntax::CallTarget::GlobalNamed(name)=>self.event(Use::Global(name))?,dm_syntax::CallTarget::Member{object,selector}|dm_syntax::CallTarget::SafeMember{object,selector,..}=>{if let Some(ty)=self.chain(object,depth+1)?.filter(|s|!s.is_empty()){self.method_use(&ty,selector)?;}},_=>{if matches!(&callee.kind,ExprKind::StaticMember{..}){return self.chain(callee,depth+1)}}}Ok(None)},
  // Parent target is checked once at the enclosing procedure header. An old
  // grouped expression or GlobalIdent has NO propagated receiver.
  _=>Ok(None)
 }}
 fn expressions(&mut self,e:&Expr,depth:usize)->Result<(),W::Error>{self.work.checkpoint()?;if depth>128{return Err("engine original nested expression exceeds admitted native depth".into())}
  match &e.kind{ExprKind::Binary{lhs,rhs,..}=>{self.expressions(lhs,depth+1)?;self.expressions(rhs,depth+1)},ExprKind::Conditional{condition,then_value,else_value}=>{self.expressions(condition,depth+1)?;self.expressions(then_value,depth+1)?;self.expressions(else_value,depth+1)},_=>{let _=self.chain(e,0)?;self.children(e,depth+1)}}
 }
 /// SAME walk_term followed by each Follow::Index/Call argument. Calls never
 /// revisit their callee as an identifier/field; constructors never visit their
 /// target or prefab variables; ProcReference arguments remain discarded.
 fn children(&mut self,e:&Expr,depth:usize)->Result<(),W::Error>{self.work.checkpoint()?;if depth>128{return Err("engine original term child depth exceeds native admission".into())}match &e.kind{
  ExprKind::Member{object,..}|ExprKind::SafeMember{object,..}|ExprKind::StaticMember{object,..}=>self.children(object,depth+1),
  ExprKind::Index{object,index}|ExprKind::SafeIndex{object,index}=>{self.children(object,depth+1)?;self.expressions(index,depth+1)},
  ExprKind::Unary{op,value}if op=="new"=>{if let ExprKind::Call{args,..}=&value.kind{for arg in args{self.work.checkpoint()?;self.expressions(arg,depth+1)?;}}Ok(())},
  ExprKind::Unary{op,..}if op=="::"=>Ok(()),
  ExprKind::Unary{value,..}=>self.children(value,depth+1),
  ExprKind::Group(inner)=>self.expressions(inner,depth+1),
  ExprKind::ObjectInitializer{fields,..}=>{for(_,value)in fields{self.work.checkpoint()?;self.expressions(value,depth+1)?;}Ok(())},
  ExprKind::Call{callee,args}=>{if matches!(&callee.kind,ExprKind::StaticMember{..}){return self.children(callee,depth+1)}match dm_syntax::call_target(callee){dm_syntax::CallTarget::Member{object,..}|dm_syntax::CallTarget::SafeMember{object,..}=>self.children(object,depth+1)?,dm_syntax::CallTarget::Dynamic{targets,..}=>for target in targets{self.work.checkpoint()?;self.expressions(target,depth+1)?;},_=>{}}for arg in args{self.work.checkpoint()?;self.expressions(arg,depth+1)?;}Ok(())},
  ExprKind::Literal(text)=>{if let Some(parts)=text.parts().map_err(Unsupported::from)?{parts.lexical.map_err(|e|Unsupported(format!("{e:?}")))?;}dm_syntax::try_for_each_expression_child(e,|_,child|self.expressions(child,depth+1))},
  ExprKind::TypeFilter{value,..}=>self.expressions(value,depth+1),
  _=>Ok(())
 }}
}
pub fn observe_body_using<W:WorkspaceWork,F:for<'x>FnMut(&str,u32,Use<'x>,&mut W)->Result<(),W::Error>>(model:&Model<'_>,ordinal:usize,work:&mut W,emit:&mut F)->Result<(),W::Error>{
 work.checkpoint()?;let archive=model.inputs.archive();let occurrence=archive.occurrences().get(ordinal).ok_or("engine original body ordinal absent")?;let body=work.body(archive,ordinal)?;if !body.belongs_to(archive)||!std::ptr::eq(body.occurrence(),occurrence){return Err("engine original body loan is foreign".into())}let member=archive.tree().member(occurrence.member).ok_or("engine body member absent")?;let owner=archive.tree().type_node(member.owner).ok_or("engine body owner absent")?.path;let origin=archive.callable_header_policy_line(occurrence.member).map_err(Unsupported)?;let(file,line)=model.point(&origin.path,origin.line,work)?;let owner=model.spelling(owner)?;let name=model.spelling(member.name)?;if W::CHECKED{let bytes=file.len().checked_add(owner.len()).and_then(|n|n.checked_add(name.len())).and_then(|n|n.checked_mul(4)).and_then(|n|n.checked_add(1024)).ok_or_else(||work.overflow())?;work.retain(bytes)?;}let owner=owner.to_owned();let name=name.to_owned();
 for fact in body.source_locals().map_err(Unsupported)?.entries().map_err(Unsupported)?{work.checkpoint()?;if fact.source_kind==dm_syntax::LocalSourceKind::CommaContinuation{return Err("engine simultaneous comma-local binding needs original statement-group issuance".into())}}
 let mut w=Walker{model,body:&body,work,emit,file,line,owner,locals:BTreeMap::new()};let owner=w.owner_copy()?;w.type_use(&owner)?;let parameters=body.source_parameters().map_err(Unsupported)?;if W::CHECKED{let bytes=body.header_source().ok_or("engine original header source unavailable")?.len().checked_mul(32).and_then(|n|n.checked_add(1024)).ok_or_else(||w.work.overflow())?;w.work.temporary(bytes)?;}for parameter in parameters.entries().map_err(Unsupported)?{w.work.checkpoint()?;let Some(ty)=parameters.type_path(parameter).map_err(Unsupported)?else{continue};let name=parameters.name(parameter).map_err(Unsupported)?;if W::CHECKED{let bytes=name.len().checked_add(ty.len()).and_then(|n|n.checked_mul(4)).and_then(|n|n.checked_add(512)).ok_or_else(||w.work.overflow())?;w.work.retain(bytes)?;}w.type_use(&ty)?;w.locals.insert(name.to_owned(),ty);}
 let mut parent=false;let control=std::cell::RefCell::new(&mut*w.work);let scanned=crate::untyped_order::try_policy_expressions(body.statement_body().view(),&mut||control.borrow_mut().checkpoint(),&mut|view,_|{control.borrow_mut().checkpoint()?;if matches!(&view.original().kind,ExprKind::Call{callee,..}if matches!(&callee.kind,ExprKind::Ident(n)if n=="..")){parent=true;}Ok::<_,W::Error>(())});drop(control);match scanned{Ok(())=>{},Err(crate::untyped_order::PolicyVisitFailure::Callback(e))=>return Err(e),Err(crate::untyped_order::PolicyVisitFailure::Unsupported(s))=>return Err(s.into())}
 if parent{if let Some(parent)=model.parent(&owner,w.work)?{w.method_use(&parent,&name)?;}}
 let result=crate::untyped_order::try_engine_roots(body.statement_body().view(),&mut w,&mut|w|w.work.checkpoint(),&mut|w,st|w.bind(st),&mut|w,root,at|{w.at(at)?;w.expressions(root.original(),0)});match result{Ok(())=>w.work.checkpoint(),Err(crate::untyped_order::PolicyVisitFailure::Callback(e))=>Err(e),Err(crate::untyped_order::PolicyVisitFailure::Unsupported(s))=>Err(s.into())}
}
