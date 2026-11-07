
//! Original dynamic return binding over already evaluated call arguments.
//! Policy: SpacemanDMM0290db5c752fa292f9824521515b603a2afd11dc
//! type_expr.rs and lib.rs2422..2576 (GPL-3.0). No expression is revisited.
use crate::{checker_expression_visit::{TypeFact,OriginalValue},checker_return_expression::CompiledSetting,policy_body_demand::PolicyFailure};
use dm_syntax::{Expr,ExprKind};
use dm_ir::{ProcedureIdentity,SymbolId};
use std::borrow::Cow;
#[derive(Clone,Debug)]pub(crate) struct Argument<'a>{pub key:Option<Cow<'a,str>>,pub position:usize,pub ty:TypeFact,pub value:Option<OriginalValue<'a>>}
#[derive(Clone,Copy,Debug)]pub(crate) enum Selection<'a>{Value(TypeFact),Undefined(&'a str)}
fn truth(value:TypeFact)->Result<bool,PolicyFailure>{match value{TypeFact::Known(_)|TypeFact::List(_)|TypeFact::NestedList{..}|TypeFact::Proc=>Ok(true),TypeFact::Deferred(reason)=>Err(reason.into()),_=>Ok(false)}}
fn strip(mut value:TypeFact,mut n:usize)->Result<TypeFact,PolicyFailure>{value=match value{TypeFact::Deferred(reason)=>return Err(reason.into()),TypeFact::ReturnHint(..)|TypeFact::AuthoredVariableHint(_)|TypeFact::Unhinted=>TypeFact::Unknown,value=>value};while n>0{value=match value{TypeFact::List(Some(element))=>TypeFact::Known(element),TypeFact::NestedList{depth,element}if depth>1=>if depth==2{TypeFact::List(element)}else{TypeFact::NestedList{depth:depth-1,element}},_=>TypeFact::Unknown};n-=1;}Ok(value)}
fn parameter<'a>(mut expr:&'a Expr,checkpoint:&dyn Fn()->std::io::Result<()>)->Result<(&'a str,usize),PolicyFailure>{let mut n=0usize;loop{checkpoint().map_err(PolicyFailure::Operational)?;match &expr.kind{ExprKind::Ident(name)=>return Ok((name,n)),ExprKind::Group(inner)=>expr=inner,ExprKind::Index{object,..}|ExprKind::SafeIndex{object,..}=>{expr=object;n=n.checked_add(1).ok_or("return expression list depth overflow")?},_=>return Err("compiled return parameter is not represented".into())}}}
fn static_path<'a>(tree:&dm_tree::SemanticTree,resolver:&(impl dm_ir::Resolver+?Sized),path:&'a str,checkpoint:&dyn Fn()->std::io::Result<()>)->Result<Selection<'a>,PolicyFailure>{
 if !path.starts_with('/'){return Err("original return value relative prefab path is not represented".into())}
 let mut rest=path;let mut depth=0usize;loop{checkpoint().map_err(PolicyFailure::Operational)?;let Some(component)=rest.strip_prefix('/').and_then(|s|s.split('/').next())else{break};if component=="list"{depth=depth.checked_add(1).ok_or("return expression list depth overflow")?;rest=&rest[component.len()+1..];}else if ["static","global","const","tmp","final","SpacemanDMM_final","SpacemanDMM_private","SpacemanDMM_protected"].contains(&component){rest=&rest[component.len()+1..];}else{break}}
 let leaf=if rest.is_empty(){None}else if {let query=dm_ir::ResolveQuery::Type(SymbolId::of(rest));let actual=resolver.resolve(query);if actual!=dm_ir::Resolver::resolve(tree,query){return Err("original return static type dependency differs".into())}matches!(actual,dm_ir::ResolvedMeaning::Symbol(_))}{Some(SymbolId::of(rest))}else{return Ok(Selection::Undefined(rest))};
 if depth>0&&tree.lookup_type(SymbolId::of("/list")).is_none(){return Err("actual original return list builtin absent".into())}
 Ok(Selection::Value(match depth{0=>leaf.map(TypeFact::Known).unwrap_or(TypeFact::Unknown),1=>TypeFact::List(leaf),_=>TypeFact::NestedList{depth,element:leaf}}))
}
struct Eval<'a,'args,'op,R:?Sized>{tree:&'a dm_tree::SemanticTree,resolver:&'a R,parameters:&'a[dm_ir::Parameter],arguments:&'args[Argument<'a>],admission:&'a dm_syntax::SettingAdmission<'op>,checkpoint:&'a dyn Fn()->std::io::Result<()>}
impl<R:dm_ir::Resolver+?Sized> Eval<'_,'_,'_,R>{
 fn argument(&self,name:&str)->Result<Option<&Argument<'_>>,PolicyFailure>{
  // Name map wins even when a positional argument for this parameter exists;
  // duplicate keywords keep the last already-evaluated analysis.
  for arg in self.arguments.iter().rev(){(self.checkpoint)().map_err(PolicyFailure::Operational)?;if arg.key.as_deref()==Some(name){return Ok(Some(arg))}}
  let mut index=None;for(i,p)in self.parameters.iter().enumerate(){(self.checkpoint)().map_err(PolicyFailure::Operational)?;if self.tree.symbols().text(p.name)==Some(name){index=Some(i);break}}let index=index.ok_or("compiled original return parameter vanished")?;
  Ok(self.arguments.iter().find(|arg|arg.key.is_none()&&arg.position==index))
 }
 fn evaluate<'e>(&'e self,expr:&'e Expr)->Result<Selection<'e>,PolicyFailure>{
  (self.checkpoint)().map_err(PolicyFailure::Operational)?;
  let _frame=self.admission.evaluation_frame().map_err(PolicyFailure::Operational)?;
  match &expr.kind{
   ExprKind::Group(inner)=>self.evaluate(inner),
   ExprKind::Ident(name)if name=="null"=>Ok(Selection::Value(TypeFact::Unknown)),
   ExprKind::Literal(raw)if raw.original_value().is_none()&&raw.as_str()=="null"=>Ok(Selection::Value(TypeFact::Unknown)),
   ExprKind::TypePath(path)=>static_path(self.tree,self.resolver,path,self.checkpoint),
   ExprKind::ObjectInitializer{object,..}=>match &object.kind{ExprKind::TypePath(path)=>static_path(self.tree,self.resolver,path,self.checkpoint),_=>Err("compiled original return prefab unavailable".into())},
   ExprKind::Conditional{condition,then_value,else_value}=>match self.evaluate(condition)?{Selection::Value(value)=>if truth(value)?{self.evaluate(then_value)}else{self.evaluate(else_value)},other=>Ok(other)},
   ExprKind::Binary{op,lhs,rhs}if op=="||"||op=="&&"=>match self.evaluate(lhs)?{Selection::Value(value)=>if (op=="||"&&truth(value)?)||(op=="&&"&&!truth(value)?){self.evaluate(lhs)}else{self.evaluate(rhs)},other=>Ok(other)},
   ExprKind::Member{object,selector,..}|ExprKind::SafeMember{object,selector,..}if selector=="type"=>{let(name,n)=parameter(object,self.checkpoint)?;Ok(Selection::Value(match self.argument(name)?{Some(arg)=>strip(arg.ty,n)?,None=>TypeFact::Unknown}))},
   ExprKind::Ident(_)|ExprKind::Index{..}|ExprKind::SafeIndex{..}=>{
    let(name,_ignored_index_count)=parameter(expr,self.checkpoint)?;let value=self.argument(name)?.and_then(|arg|arg.value);match value{
     Some(OriginalValue::PrefabPath(path))=>static_path(self.tree,self.resolver,path,self.checkpoint),
     Some(OriginalValue::PrefabOwner(owner))=>{let path=self.tree.symbols().text(owner).ok_or("original return prefab owner spelling absent")?;match static_path(self.tree,self.resolver,path,self.checkpoint)?{Selection::Value(value)=>Ok(Selection::Value(value)),_=>Err("original return prefab owner type unavailable".into())}},
     Some(OriginalValue::ProcedurePath{..})=>Err("original return procedure-prefab static type diagnostic needs full path projection".into()),
     _=>Ok(Selection::Value(TypeFact::Unknown)),
    }
   },
   _=>Err("invalid expression escaped original return compilation".into()),
  }
 }
}

/// Original named/positional binding consumer. The actual call has already
/// evaluated every argument; this method consumes those facts without visiting
/// expressions or copying a compiled type-expression tree.
#[derive(Clone,Copy,Debug)]pub(crate) enum Binding{Absent,InvalidOnly,Bound(TypeFact),DiagnosedNone}
pub(crate) fn for_call<'a,D:crate::checker_prefix_demand::Demand,R:dm_ir::Resolver+?Sized>(archive:&'a dm_tree::frontend::BodyArchive,resolver:&R,identity:ProcedureIdentity,arguments:&[Argument<'a>],demand:&D,mut undefined:impl FnMut(&str)->Result<(),D::Error>)->Result<Binding,D::Error>{
 demand.checkpoint()?;if !demand.owns_return_expression_binding(){return Ok(Binding::Absent)}
 let tree=archive.tree();if resolver.source_owner()!=dm_ir::Resolver::source_owner(tree){return Err("original return binding resolver is foreign".into())}
 let query=dm_ir::ResolveQuery::SourceDeclarationChain{owner:identity.owner,name:identity.name,verb:identity.verb};if resolver.resolve(query)!=dm_ir::Resolver::resolve(tree,query){return Err("original return binding source dependency differs".into())}
 let pending=demand.prefix(archive,identity,|prefix|->Result<Binding,D::Error>{
  if !prefix.belongs_to(archive)||prefix.identity()!=identity{return Err("original return binding prefix is foreign".into())}
  let body=prefix.source_body();let parameters=&tree.member(body.occurrence().member).ok_or("original return binding member absent")?.metadata.procedure.as_ref().ok_or("original return binding signature absent")?.signature.parameters;
  let mut selected=None;let mut diagnosed=false;let mut saw_any=false;
  for(ordinal,statement)in prefix.settings().iter().enumerate(){
   demand.checkpoint()?;if statement.setting().ok_or("original return prefix statement changed")?.attribute!="SpacemanDMM_return_type"{continue}saw_any=true;
   // Callback Error remains opaque through the source admission, so its actual
   // typed IO/cancellation is returned unchanged after the root guard closes.
   let checkpoint=demand.source_checkpoint().ok_or("original return binding needs the actual checked source callback")?;
   let pending=crate::checker_return_expression::with_compiled_setting(body,resolver,ordinal,checkpoint,|compiled,admission|{
    let value=match compiled{CompiledSetting::Rejected=>return Ok(Ok(None)),CompiledSetting::Empty=>return Ok(Ok(Some((TypeFact::Unknown,false)))),CompiledSetting::Value(root)=>{
     let evaluator=Eval{tree,resolver,parameters,arguments,admission,checkpoint};
     match evaluator.evaluate(root)?{Selection::Value(value)=>Ok(Some((value,false))),Selection::Undefined(path)=>undefined(path).map(|_|Some((TypeFact::Unknown,true)))}
    }};Ok(value)
   });
   if let Some((value,error))=pending.map_err(|failure|demand.policy_failure(failure))??{selected=Some(value);diagnosed=error}
  }Ok(match selected{Some(_)if diagnosed=>Binding::DiagnosedNone,Some(value)=>Binding::Bound(value),None if saw_any=>Binding::InvalidOnly,None=>Binding::Absent})
 })?;match pending{Err(actual)=>Err(actual),Ok(value)=>{demand.checkpoint()?;Ok(value)}}
}

#[cfg(test)]#[path="../examples/support/reference_hierarchy.rs"]mod return_reference_hierarchy;
#[cfg(test)]mod tests{
 use super::*;

 struct Source;
 impl dm_preprocess::SourceProvider for Source{fn read(&self,_:&std::path::Path)->Result<String,String>{Ok("/datum/a\n/datum/b\n/proc/choose(x)\n    return null\n".into())}}
 fn frontend()->dm_tree::frontend::ColdFrontend{let seed=return_reference_hierarchy::seed();dm_tree::frontend::build_with_config(std::path::Path::new("return-binding-kernel.dme"),&Source,&Default::default(),dm_tree::frontend::FrontendConfig{workers:1,engine:Some(&seed),observer:None}).unwrap()}
 fn parameters(tree:&dm_tree::SemanticTree)->&[dm_ir::Parameter]{let owner=tree.lookup_type(SymbolId::of("/")).unwrap();let id=tree.resolve(owner,SymbolId::of("choose"),dm_tree::MemberKind::Proc).unwrap();&tree.member(id).unwrap().metadata.procedure.as_ref().unwrap().signature.parameters}
 #[test]fn dynamic_return_lookup_prefers_last_keyword_then_only_positional_index(){
  let front=frontend();let tree=front.snapshot.tree.as_ref();let counter=std::sync::Arc::new(std::sync::atomic::AtomicUsize::new(0));let poll=||Ok(());let admission=dm_syntax::SettingAdmission::new(&counter,1<<20,&poll);
  let arguments=[Argument{key:None,position:0,ty:TypeFact::Known(SymbolId::of("/datum/a")),value:None},Argument{key:Some(Cow::Borrowed("x")),position:1,ty:TypeFact::Known(SymbolId::of("/datum/a")),value:None},Argument{key:Some(Cow::Borrowed("x")),position:1,ty:TypeFact::Known(SymbolId::of("/datum/b")),value:None}];
  let evaluator=Eval{tree,resolver:tree,parameters:parameters(tree),arguments:&arguments,admission:&admission,checkpoint:&poll};assert_eq!(evaluator.argument("x").unwrap().unwrap().ty,TypeFact::Known(SymbolId::of("/datum/b")));
 }
 #[test]fn dynamic_return_list_stripping_removes_argument_hints_and_does_not_keep_plain_type_after_index(){
  let owner=SymbolId::of("/datum/b");assert_eq!(strip(TypeFact::NestedList{depth:2,element:Some(owner)},1).unwrap(),TypeFact::List(Some(owner)));assert_eq!(strip(TypeFact::NestedList{depth:2,element:Some(owner)},2).unwrap(),TypeFact::Known(owner));assert_eq!(strip(TypeFact::Known(owner),1).unwrap(),TypeFact::Unknown);assert_eq!(strip(TypeFact::ReturnHint(crate::checker_return_facts::ReturnFixHint::EvaluatedNone,dm_syntax::Span::new(0,1)),0).unwrap(),TypeFact::Unknown);
 }
 #[test]fn dynamic_return_actual_evaluation_frame_denial_and_reader_io_do_not_publish_a_value(){
  use std::sync::{Arc,atomic::{AtomicUsize,Ordering}};let front=frontend();let tree=front.snapshot.tree.as_ref();let parsed=dm_syntax::parse_expression("null");let expr=parsed.expr.unwrap();let counter=Arc::new(AtomicUsize::new(0));let healthy=||Ok(());let admission=dm_syntax::SettingAdmission::new(&counter,0,&healthy);let evaluator=Eval{tree,resolver:tree,parameters:parameters(tree),arguments:&[],admission:&admission,checkpoint:&healthy};assert!(matches!(evaluator.evaluate(&expr),Err(PolicyFailure::Operational(ref e))if e.kind()==std::io::ErrorKind::OutOfMemory));assert_eq!(counter.load(Ordering::Acquire),0);
  let fail=||Err(std::io::Error::from_raw_os_error(1450));let admission=dm_syntax::SettingAdmission::new(&counter,1<<20,&fail);let evaluator=Eval{tree,resolver:tree,parameters:parameters(tree),arguments:&[],admission:&admission,checkpoint:&fail};assert!(matches!(evaluator.evaluate(&expr),Err(PolicyFailure::Operational(ref e))if e.raw_os_error()==Some(1450)));assert_eq!(counter.load(Ordering::Acquire),0);
 }
}
