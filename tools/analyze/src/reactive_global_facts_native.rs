//! Native producers for the original name-based boot and typed-write policies.
//! Unique policy facts only; declarations/bodies/types stay in the original graph.
use crate::{reactive_original_source::ReadSource,reactive_global_source::{Source as GlobalSource,Body as GlobalBody,Callable as GlobalCallable},reactive_reads_native::{Failure,GlobalFacts},global_policy::{self,CompactGlobalBuilder},key_policy_control as kc};
use dm_syntax::{Expr,ExprKind,Statement,StatementKind,ForControl,TypedVisitor,VisitDecision,NodeStep};
use std::{collections::{HashMap,HashSet},io,cell::RefCell};
#[derive(serde::Serialize)]
pub(crate) struct NativeGlobals{globals:crate::global_policy::GlobalRows,writes:crate::write_policy::WriteRows,#[serde(skip)]outside_writes:crate::write_policy::WriteRows}
fn denial()->Failure{Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,"native global policy admission refused"))}
fn require(source:&dyn GlobalSource)->Result<(),Failure>{{let pending=source.require();if matches!(&pending,Err(Failure::Operational(_))){return pending}if source.budget().denied(){return Err(denial())}pending}}
fn reserve(source:&dyn GlobalSource,bytes:Option<usize>)->Result<(),Failure>{bytes.ok_or_else(denial).and_then(|n|source.budget().charge(n).map_err(|_|denial()))}
struct Control<'a>{source:&'a dyn GlobalSource,poll:&'a dyn Fn()->io::Result<()>}
impl kc::Control for Control<'_>{
 type Error=Failure;const CHECKED:bool=true;
 fn checkpoint(&mut self)->Result<(),Failure>{(self.poll)()?;require(self.source)}
 fn reserve(&mut self,n:usize)->Result<(),Failure>{reserve(self.source,Some(n))}
 fn overflow(&mut self)->Failure{self.source.budget().deny();denial()}
 fn allocation_failed(&mut self)->Failure{self.source.budget().deny();denial()}
}
fn row<T>(source:&dyn GlobalSource,rows:&mut Vec<T>)->Result<(),Failure>{if source.budget().row(rows){Ok(())}else{Err(denial())}}
fn own(source:&dyn GlobalSource,text:&str)->Result<String,Failure>{reserve(source,text.len().checked_mul(4).and_then(|n|n.checked_add(256)))?;Ok(text.to_owned())}
fn test_code(rel:&str)->bool{rel.starts_with("code/tests/")||rel.starts_with("code/modules/unit_tests/")}
fn plain(name:&str)->bool{let mut chars=name.chars();chars.next().is_some_and(|c|c=='_'||c.is_alphabetic())&&chars.all(|c|c=='_'||c.is_alphanumeric())}
fn variable_owner(source:&dyn GlobalSource,owner:&str,name:&str)->Result<Option<String>,Failure>{source.declaring_owner(owner,name)?.map(|owner|own(source,owner)).transpose()}

impl GlobalFacts for NativeGlobals{
 fn outside_written_on(&self,source:&dyn GlobalSource,owner:&str,name:&str)->Result<bool,Failure>{self.outside_writes.is_written_on_checked(owner,name,|owner,name|variable_owner(source,owner,name),|a,b|source.is_subtype(a,b))}
 fn constant_after_init(&self,name:&str)->Result<bool,Failure>{Ok(self.globals.constant_after_init(name))}
 fn field_constant_after_init(&self,name:&str)->Result<bool,Failure>{Ok(self.globals.field_constant_after_init(name))}
 fn is_written_on(&self,source:&dyn GlobalSource,owner:&str,name:&str)->Result<bool,Failure>{
  reserve(source,owner.len().checked_mul(4).and_then(|n|n.checked_add(256)))?;
  self.writes.is_written_on_checked(owner,name,|owner,name|variable_owner(source,owner,name),|a,b|source.is_subtype(a,b).map_err(Failure::from))
 }
}
struct Locals{globals:HashSet<String>,typed:HashMap<String,Option<String>>}
struct LocalCollector<'a>{source:&'a dyn GlobalSource,body:&'a dyn GlobalBody,locals:Locals,error:Option<Failure>,poll:&'a dyn Fn()->io::Result<()>}
impl LocalCollector<'_>{
 fn add(&mut self,name:&str,ty:Option<String>,typed:bool)->Result<(),Failure>{reserve(self.source,name.len().checked_add(ty.as_ref().map_or(0,String::len)).and_then(|n|n.checked_mul(8)).and_then(|n|n.checked_add(1024)))?;self.locals.globals.insert(name.to_owned());if typed{self.locals.typed.insert(name.to_owned(),ty);}Ok(())}
 fn bind(&mut self,header:dm_syntax::Span,bare:&[&str],typed:bool)->Result<(),Failure>{
  let locals=self.body.source_locals()?;let rows=locals.in_span(header)?;
  if !rows.is_empty(){for entry in rows{(self.poll)()?;let name=locals.name(entry)?;reserve(self.source,locals.type_path_width(entry)?.checked_mul(8).and_then(|n|n.checked_add(512)))?;let ty=if typed{locals.type_path(entry)?}else{None};self.add(name,ty,typed)?;}
   // Pair's declared key may be the only ledger row; its bare value still
   // shadows a global in the old whole-proc local-name set.
   for name in bare{if plain(name)&&!self.locals.globals.contains(*name){self.add(name,None,typed)?;}}
   return Ok(())}
  for name in bare{if !plain(name){return Err("global policy binding lacks original declaration or bare identifier".into())}self.add(name,None,typed)?;}Ok(())
 }
 fn statement_checked(&mut self,s:&Statement)->Result<(),Failure>{
  (self.poll)()?;require(self.source)?;
  match &s.kind{
   StatementKind::Var{..}=>self.bind(s.header_span,&[],true)?,
   StatementKind::For{control,..}=>match control{
    ForControl::All{declaration, ..}=>self.bind(s.header_span,&[declaration],true)?,
    ForControl::Each{binding,..}=>self.bind(s.header_span,&[binding],true)?,
    ForControl::Pair{key_binding,value_binding,..}=>self.bind(s.header_span,&[key_binding,value_binding],false)?,
    ForControl::Range{binding,..}|ForControl::RangeImplicitArray{binding,..}=>self.bind(s.header_span,&[binding],false)?,
    // The original collect_locals does not descend into C-style init clauses.
    ForControl::CStyle{..}=>(),
   },_=>(),
  }Ok(())
 }
}
impl TypedVisitor for LocalCollector<'_>{
 fn statement(&mut self,s:&Statement,_:&[NodeStep])->VisitDecision{if self.error.is_some(){return VisitDecision::Stop}match self.statement_checked(s){Ok(())=>VisitDecision::Descend,Err(e)=>{self.error=Some(e);VisitDecision::Stop}}}
 fn expression(&mut self,_:&Expr,_:&[NodeStep])->VisitDecision{VisitDecision::Skip}
 fn projected_expression(&mut self,_:dm_syntax::ProjectedExprView<'_>,_:&[NodeStep])->VisitDecision{VisitDecision::Skip}
}
fn field_name(mut e:&Expr)->Option<&str>{loop{match &e.kind{ExprKind::Index{object,..}|ExprKind::SafeIndex{object,..}=>e=object,ExprKind::Member{selector,..}|ExprKind::SafeMember{selector,..}=>return Some(selector),ExprKind::Ident(n)=>return Some(n),_=>return None}}}
fn is_bare_field(mut e:&Expr)->bool{loop{match &e.kind{ExprKind::Index{object,..}|ExprKind::SafeIndex{object,..}=>e=object,ExprKind::Ident(_)=>return true,_=>return false}}}
fn global_name<'a>(mut e:&'a Expr,globals:&HashSet<String>,glob:&HashSet<String>,locals:&HashSet<String>)->Option<&'a str>{loop{match &e.kind{
 ExprKind::Index{object,..}|ExprKind::SafeIndex{object,..}=>e=object,
 ExprKind::Member{object,selector,..}|ExprKind::SafeMember{object,selector,..}=>{
  if let ExprKind::Ident(n)=&object.kind{if n=="GLOB"&&glob.contains(selector){return Some(selector)}}
  if selector=="len"{e=object;continue}return None
 },ExprKind::Ident(n)if !locals.contains(n)&&globals.contains(n)=>return Some(n),_=>return None}}}

fn receiver(source:&dyn GlobalSource,owner:&str,locals:&HashMap<String,Option<String>>,mut e:&Expr,poll:&dyn Fn()->io::Result<()>)->Result<Option<String>,Failure>{
 let mut selectors=Vec::new();
 loop{poll()?;require(source)?;match &e.kind{ExprKind::Member{object,selector,..}|ExprKind::SafeMember{object,selector,..}=>{row(source,&mut selectors)?;selectors.push(selector.as_str());e=object;},_=>break}}
 let mut current=match &e.kind{
  ExprKind::Ident(n)if n=="src"=>Some(own(source,owner)?),
  ExprKind::Ident(n)if n=="usr"=>None,
  ExprKind::Ident(n)=>if let Some(ty)=locals.get(n){ty.as_deref().map(|s|own(source,s)).transpose()?}else{source.receiver_variable_type(owner,n)?.filter(|value|!value.is_empty())},
  _=>None,
 };
 for selector in selectors.into_iter().rev(){poll()?;require(source)?;current=match current{Some(ty)=>source.receiver_variable_type(&ty,selector)?.filter(|value|!value.is_empty()),None=>None};}
 Ok(current)
}

fn write_target(source:&dyn GlobalSource,owner:&str,locals:&HashMap<String,Option<String>>,mut e:&Expr,poll:&dyn Fn()->io::Result<()>)->Result<Option<(String,String)>,Failure>{
 require(source)?;while let ExprKind::Index{object,..}|ExprKind::SafeIndex{object,..}=&e.kind{e=object;poll()?;require(source)?;}let(recv,name)=match &e.kind{
  ExprKind::Member{object,selector,..}|ExprKind::SafeMember{object,selector,..}=>(receiver(source,owner,locals,object,poll)?,selector.as_str()),
  ExprKind::Ident(n)if !locals.contains_key(n)=>(Some(own(source,owner)?),n.as_str()),
  _=>return Ok(None),
 };
 let declaring=match recv{Some(ty)=>variable_owner(source,&ty,name)?,None=>None};
 Ok(Some((match declaring{Some(ty)=>ty,None=>own(source,crate::write_policy::UNTYPED_WRITE)?},own(source,name)?)))
}
struct Scan<'a,'g,C:kc::Control<Error=Failure>>{source:&'a dyn GlobalSource,owner:&'a str,locals:&'a Locals,global_names:&'a HashSet<String>,glob_names:&'a HashSet<String>,graph:&'g mut CompactGlobalBuilder,control:&'g mut C,capture_global:bool,outside:bool,own_setter:Option<&'a str>,constructor:bool,poll:&'a dyn Fn()->io::Result<()>,error:Option<Failure>}
impl<C:kc::Control<Error=Failure>> Scan<'_,'_,C>{
 fn put(&mut self,kind:global_policy::CompactGlobalKind,name:&str)->Result<(),Failure>{if self.capture_global{self.graph.edge(self.control,kind,name)?;}Ok(())}
 fn note(&mut self,e:&Expr,typed:bool)->Result<(),Failure>{
  if let Some(name)=field_name(e){if !is_bare_field(e)||!self.locals.globals.contains(name){self.put(global_policy::CompactGlobalKind::FieldWrite,name)?;}}
  if let Some(name)=global_name(e,self.global_names,self.glob_names,&self.locals.globals){self.put(global_policy::CompactGlobalKind::Write,name)?;}
  if typed&&!self.constructor{if let Some(pair)=write_target(self.source,self.owner,&self.locals.typed,e,self.poll)?{self.graph.typed_write(self.control,&pair.0,&pair.1)?;if self.outside&&self.own_setter!=Some(pair.1.as_str()){self.graph.outside_write(self.control,&pair.0,&pair.1)?;}}}
  Ok(())
 }
 fn expr(&mut self,e:&Expr)->Result<(),Failure>{
  (self.poll)()?;require(self.source)?;
  match &e.kind{
   ExprKind::Binary{op,lhs,..}if dm_syntax::assignment_target_access(op).is_some()=>self.note(lhs,true)?,
   ExprKind::Unary{op,value}if matches!(op.as_str(),"++"|"--"|"post++"|"post--")=>self.note(value,true)?,
   ExprKind::Unary{op,..}if op=="new"=>self.put(global_policy::CompactGlobalKind::Call,"New")?,
   ExprKind::Call{callee,args}=>match dm_syntax::call_target(callee){
    dm_syntax::CallTarget::Named(name)=>{
     if name=="new"{self.put(global_policy::CompactGlobalKind::Call,"New")?;}
     else if !matches!(name,"."|".."|"list"|"pick"|"input"|"locate"|"call"|"call_ext"|"as"){
      self.put(global_policy::CompactGlobalKind::Call,name)?;
      if global_policy::REF_MACROS.contains(&name){if let Some(Expr{kind:ExprKind::Ident(r),..})=args.last(){self.put(global_policy::CompactGlobalKind::Reference,r)?;}}
      if global_policy::ARG_MUTATORS.contains(&name){if let Some(first)=args.first(){self.note(first,false)?;}}
     }
    },
    dm_syntax::CallTarget::GlobalNamed(name)=>self.put(global_policy::CompactGlobalKind::Call,name)?,
    dm_syntax::CallTarget::Member{object,selector}|dm_syntax::CallTarget::SafeMember{object,selector,..}=>{self.put(global_policy::CompactGlobalKind::Call,selector)?;if global_policy::LIST_MUTATORS.contains(&selector){self.note(object,false)?;}},
    _=>if let ExprKind::StaticMember{selector,..}=&callee.kind{self.put(global_policy::CompactGlobalKind::Reference,selector)?;},
   },_=>(),
  }Ok(())
 }
 fn accept(&mut self,result:Result<(),Failure>)->VisitDecision{match result{Ok(())=>VisitDecision::Descend,Err(e)=>{self.error=Some(e);VisitDecision::Stop}}}
}
impl<C:kc::Control<Error=Failure>> TypedVisitor for Scan<'_,'_,C>{
 fn statement(&mut self,s:&Statement,_:&[NodeStep])->VisitDecision{if self.error.is_some(){return VisitDecision::Stop}(||{(self.poll)()?;require(self.source)?;if let StatementKind::Assign{target,..}=&s.kind{self.note(target,true)?;}Ok(())})().map_or_else(|e|{self.error=Some(e);VisitDecision::Stop},|_|VisitDecision::Descend)}
 fn expression(&mut self,e:&Expr,_:&[NodeStep])->VisitDecision{if self.error.is_some(){return VisitDecision::Stop}let result=self.expr(e);self.accept(result)}
 fn projected_expression(&mut self,e:dm_syntax::ProjectedExprView<'_>,_:&[NodeStep])->VisitDecision{if self.error.is_some(){return VisitDecision::Stop}let result=self.expr(e.original());self.accept(result)}
}
fn declared_names(source:&dyn GlobalSource,owner:&str,poll:&dyn Fn()->io::Result<()>)->Result<HashSet<String>,Failure>{
 let tree=source.tree();let mut out=HashSet::new();let Some(id)=tree.lookup_type(dm_ir::SymbolId::of(owner))else{return Ok(out)};
 for member in tree.type_node(id).ok_or("global declaration owner missing")?.members.iter(){
  poll()?;require(source)?;let member=tree.member(*member).ok_or("global original variable member missing")?;if member.kind!=dm_tree::MemberKind::Var{continue}
  let name=tree.symbols().text(member.name).ok_or("global original variable name missing")?;
  if variable_owner(source,owner,name)?.as_deref()==Some(owner){reserve(source,name.len().checked_mul(4).and_then(|n|n.checked_add(512)))?;out.insert(name.to_owned());}
 }Ok(out)
}
impl NativeGlobals{
 pub(crate) fn build(source:&ReadSource<'_>,checkpoint:impl FnMut()->io::Result<()>)->Result<Self,Failure>{Self::build_from(source,checkpoint)}
 pub(crate) fn build_from(source:&dyn GlobalSource,mut checkpoint:impl FnMut()->io::Result<()>)->Result<Self,Failure>{
  let pending=(||{
   let cell=RefCell::new(&mut checkpoint);let poll=||cell.borrow_mut()();
   let globals=declared_names(source,"/",&poll)?;let glob=declared_names(source,"/datum/controller/global_vars",&poll)?;
   let mut control=Control{source,poll:&poll};
   let mut graph=CompactGlobalBuilder::new(&mut control,source.body_count())?;
   source.visit_callables(None,&mut||poll().map_err(Failure::from),&mut|call:GlobalCallable<'_>|->Result<(),Failure>{
    poll()?;require(source)?;
    // Scope includes source-site formatting, local/parameter tables, receiver
    // copies, and all scanner temporaries. Their values die before scratch.
    // Persistent graph strings/edges are separately parent-funded BEFORE copy.
    let scratch=crate::captured_generator_budget::Budget::scoped_temporaries(source.operation_budget()).map_err(|_|denial())?;
    let result=source.with_budget(&scratch,&mut|page|->Result<(),Failure>{
     let rel=page.relative_body_file(call.ordinal)?;let capture_global=!test_code(&rel);
     if capture_global{
      let node=(own(page,call.owner)?,own(page,call.name)?);
      let root=global_policy::is_root_controlled(&node,||Ok::<_,Failure>(page.is_subtype(call.owner,"/datum/system")?||page.is_subtype(call.owner,"/datum/world_service")?||page.is_subtype(call.owner,"/datum/controller")?))?;
      graph.begin(&mut control,call.name,root)?;
     }
     page.with_body(call.ordinal,&mut|body|{
     // The classifier visits syntax only, including Original literals that
     // still have no native runtime string decoder.
     let syntax=body.statement_body();
     if !syntax.has_native_literal_syntax()||!syntax.original_literal_syntax_complete(){
      reserve(page, Some(1024))?;
      let detail=syntax.parsed().diagnostics.first().map_or("no parser diagnostic",|diagnostic|diagnostic.message.as_str());
      return Err(format!("global classifier requires checked complete original body: {rel}: {}/{}: {detail}",call.owner,call.name).into())
     }
     let mut locals=LocalCollector{source:page,body,locals:Locals{globals:HashSet::new(),typed:HashMap::new()},error:None,poll:&poll};
     let params=body.source_parameters()?;for p in params.entries()?{poll()?;let name=params.name(p)?;reserve(page,p.type_components().iter().try_fold(0usize,|n,s|n.checked_add(s.end.checked_sub(s.start)?)).and_then(|n|n.checked_mul(8)).and_then(|n|n.checked_add(1024)))?;locals.add(name,params.type_path(p)?,true)?;}
     dm_analysis::policy_body_observation::observe(body.statement_body().view(),&mut locals)?;if let Some(error)=locals.error.take(){return Err(error)}
     let mut scan=Scan{source:page,owner:call.owner,locals:&locals.locals,global_names:&globals,glob_names:&glob,graph:&mut graph,control:&mut control,capture_global,outside:rel!=crate::auto_setter_calls_policy::AUTO_REL&&rel!="code/engine/_generated/tracked_lists.dm",own_setter:call.name.strip_prefix("set_"),constructor:matches!(call.name,"New"|"Initialize"|"initialize"|"Init"),poll:&poll,error:None};
     dm_analysis::policy_body_observation::observe(body.statement_body().view(),&mut scan)?;if let Some(error)=scan.error.take(){return Err(error)}
     drop(scan);drop(locals);Ok(())
     })?;
     if capture_global{graph.finish(&mut control)?;}
     Ok(())
    });
    // with_budget's callback owns every scratch allocation. Only parent-funded
    // graph IDs/names survived a success. An Err may carry scratch-owned data;
    // retain its whole conservative reservation for the failed operation.
    if result.is_err(){scratch.keep_failed_scratch();}
    drop(scratch);result
   })?;
   let globals=graph.classify(&mut control)?.into_rows(&mut control)?;
   let writes=graph.write_rows(&mut control)?;let outside_writes=graph.outside_write_rows(&mut control)?;
   poll()?;require(source)?;Ok(Self{globals,writes,outside_writes})
  })();
  if matches!(&pending,Err(Failure::Operational(_))){return pending}
  if source.budget().denied(){return Err(denial())}pending
 }
}

impl NativeGlobals{pub(crate) fn visit_storage(&self,mut visit:impl FnMut(usize,usize)){self.globals.visit_storage(&mut visit);self.writes.visit_storage(&mut visit);self.outside_writes.visit_storage(visit);}}

impl NativeGlobals{
 pub(crate) fn retained_charge(&self)->Option<usize>{let mut bytes=Some(std::mem::size_of::<Self>());self.visit_storage(|_,n|bytes=bytes.and_then(|old|old.checked_add(n)));bytes}
}

impl NativeGlobals{
 pub(crate) fn outside_setters(&self)->&crate::write_policy::WriteRows{&self.outside_writes}
 /// Dependency fingerprint includes every unique fact, including auto-tracking
 /// writes deliberately omitted from the historical public Globals JSON schema.
 pub(crate) fn serialize_dependencies<S:serde::Serializer>(&self,serializer:S)->Result<S::Ok,S::Error>{
  use serde::ser::SerializeStruct;let mut fields=serializer.serialize_struct("NativeGlobalDependencies",3)?;
  fields.serialize_field("globals",&self.globals)?;fields.serialize_field("writes",&self.writes)?;fields.serialize_field("outside_setters",&self.outside_writes)?;fields.end()
 }
}
