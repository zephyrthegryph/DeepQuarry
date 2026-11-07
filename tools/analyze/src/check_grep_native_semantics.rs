//! Borrow primary compiler nodes for check_grep exception candidates only.
//! No callback result grants source coverage, a type fact, or a completed report.
use crate::{captured_generator_budget::Budget,reactive_reads_native::Failure};
use crate::check_grep_semantic_policy::{Mask,TryMaskView};
use dm_syntax::{Expr,ExprKind,ProjectedExprView,TypedVisitor,VisitDecision};

#[derive(Clone,Copy,Debug,Eq,PartialEq)]
pub(crate) enum Candidate<'a>{
    Slot{offset:usize,through_src:bool},
    Holder{offset:usize,receiver:&'a str},
}
fn grouped(mut node:&Expr)->&Expr{while let ExprKind::Group(inner)=&node.kind{node=inner;}node}
struct NumericMask<'a>{budget:&'a Budget,peak:&'a mut usize}
impl TryMaskView<Expr,Failure> for NumericMask<'_>{
 fn mask<'a>(&mut self,node:&'a Expr)->Result<Mask<'a,Expr>,Failure>{
  Ok(match &node.kind{
   ExprKind::Group(inner)=>Mask::Through(inner),
   ExprKind::Binary{op,lhs,rhs} if matches!(op.as_str(),"&"|"|"|"^"|"<<"|">>")=>Mask::Both(lhs,rhs),
   ExprKind::Unary{op,value} if matches!(op.as_str(),"~"|"-")=>Mask::Through(value),
   ExprKind::Ident(name)=>Mask::Name(name),
   ExprKind::Literal(text)=>{
    let raw:&str=text;
    if raw.as_bytes().first().is_some_and(|byte|byte.is_ascii_digit()||*byte==b'.'){
     let peak=raw.len().checked_mul(8).and_then(|n|n.checked_add(1024)).ok_or_else(||{self.budget.deny();oom("check_grep numeric projection overflow")})?;
     if peak>*self.peak{self.budget.charge(peak-*self.peak).map_err(oom)?;*self.peak=peak;}
     dm_syntax::numeric_form::numeric_form(raw).map_err(Failure::Unsupported)?;
     Mask::Number
    }else{Mask::Other}
   }
   _=>Mask::Other,
  })
 }
}
fn oom(message:impl Into<String>)->Failure{Failure::Operational(std::io::Error::new(std::io::ErrorKind::OutOfMemory,message.into()))}
struct Walk<'a,F>{budget:&'a Budget,poll:&'a dyn Fn()->std::io::Result<()>,visit:F,error:Option<Failure>,numeric_peak:usize,suppressed:*const Expr}
impl<F> Walk<'_,F> where F:for<'n>FnMut(Candidate<'n>)->Result<(),Failure>{
 fn candidate(&mut self,node:&Expr,project:Option<ProjectedExprView<'_>>)->Result<(),Failure>{
  self.budget.require().map_err(oom)?;(self.poll)()?;self.budget.require().map_err(oom)?;
  let offset=|node:&Expr|->Result<usize,Failure>{Ok(match project{Some(project)=>project.current_span_of(node).ok_or_else(||Failure::Unsupported("check_grep candidate escapes its actual setting projection".into()))?.start,None=>node.span.start})};
  if let ExprKind::Call{callee,args}=&node.kind{
   let setter=match &callee.kind{
    ExprKind::Ident(name)=>name=="set_slot_flags",
    ExprKind::Member{object,selector,..}|ExprKind::SafeMember{object,selector,..}=>matches!(&object.kind,ExprKind::Ident(name) if name=="src")&&selector=="set_slot_flags",
    _=>false,
   };
   if setter&&args.len()==1{
    if let ExprKind::Binary{op,lhs,rhs}=&grouped(&args[0]).kind{
     if op=="&"{
      let poll=self.poll;let budget=self.budget;
      if crate::check_grep_semantic_policy::try_mask(&mut NumericMask{budget,peak:&mut self.numeric_peak},rhs,&mut||{budget.require().map_err(oom)?;poll()?;budget.require().map_err(oom)})?{
       let lhs=grouped(lhs);
       match &lhs.kind{
        ExprKind::Ident(name) if name=="slot_flags"=>(self.visit)(Candidate::Slot{offset:offset(lhs)?,through_src:false})?,
        ExprKind::Member{object,selector,..}|ExprKind::SafeMember{object,selector,..} if selector=="slot_flags"&&matches!(&object.kind,ExprKind::Ident(name) if name=="src")=>(self.visit)(Candidate::Slot{offset:offset(object)?,through_src:true})?,
        _=>(),
       }
      }
     }
    }
   }
  }
  if let ExprKind::Member{object,selector,..}|ExprKind::SafeMember{object,selector,..}=&node.kind{
   if selector=="holder"{if let ExprKind::Ident(receiver)=&object.kind{(self.visit)(Candidate::Holder{offset:offset(object)?,receiver})?;}}
  }
  Ok(())
 }
 fn enter(&mut self,node:&Expr,project:Option<ProjectedExprView<'_>>)->VisitDecision{
  if self.error.is_some(){return VisitDecision::Stop}
  let suppressed=std::ptr::eq(self.suppressed,node);
  // The old Expression::Base sees its complete follow chain at once. An
  // intermediate object/callee is not a second standalone field expression.
  self.suppressed=match &node.kind{
   ExprKind::Call{callee,..}=>&**callee,
   ExprKind::Member{object,..}|ExprKind::SafeMember{object,..}|ExprKind::StaticMember{object,..}|ExprKind::Index{object,..}|ExprKind::SafeIndex{object,..}=>&**object,
   ExprKind::Unary{value,..}|ExprKind::TypeFilter{value,..}=>&**value,
   _=>std::ptr::null(),
  };
  if suppressed{return VisitDecision::Descend}
  match self.candidate(node,project){Ok(())=>VisitDecision::Descend,Err(error)=>{self.error=Some(error);VisitDecision::Stop}}
 }
}
impl<F> TypedVisitor for Walk<'_,F> where F:for<'n>FnMut(Candidate<'n>)->Result<(),Failure>{
 fn statement(&mut self,node:&dm_syntax::Statement,_:&[dm_syntax::NodeStep])->VisitDecision{
  if self.error.is_some(){return VisitDecision::Stop}
  if matches!(node.kind,dm_syntax::StatementKind::Unsupported){self.error=Some(Failure::Unsupported("check_grep requires original supported body syntax".into()));return VisitDecision::Stop}
  match self.budget.require().map_err(oom).and_then(|_|(self.poll)().map_err(Failure::Operational)).and_then(|_|self.budget.require().map_err(oom)){Ok(())=>VisitDecision::Descend,Err(error)=>{self.error=Some(error);VisitDecision::Stop}}
 }
 fn expression(&mut self,node:&Expr,_:&[dm_syntax::NodeStep])->VisitDecision{self.enter(node,None)}
 fn projected_expression(&mut self,node:ProjectedExprView<'_>,_:&[dm_syntax::NodeStep])->VisitDecision{self.enter(node.original(),Some(node))}
}
/// The host must separately validate the actual archive/body owner, shadowing,
/// receiver declaration and original file/line before accepting any candidate.
/// The shared primary walker path Vec retains its existing allocator baseline.
pub(crate) fn candidates(body:&dm_syntax::ParsedBody,budget:&Budget,poll:&dyn Fn()->std::io::Result<()>,visit:impl for<'n>FnMut(Candidate<'n>)->Result<(),Failure>)->Result<(),Failure>{
 let mut walk=Walk{budget,poll,visit,error:None,numeric_peak:0,suppressed:std::ptr::null()};
 dm_syntax::visit_statement_view(dm_syntax::StatementView::from_parsed(body),&mut walk);
 if let Some(error)=walk.error{return Err(error)}
 budget.require().map_err(oom)?;poll()?;budget.require().map_err(oom)
}

/// Per-body policy scratch only; duplicate locals intentionally erase a known
/// parameter/type just as the original whole-body check does.
pub(crate) struct Bindings{types:std::collections::BTreeMap<String,Option<String>>,pub slot_shadowed:bool}
impl Bindings{pub(crate) fn receiver_type(&self,name:&str)->Option<&str>{self.types.get(name).and_then(|value|value.as_deref())}}
fn directory_charge(budget:&Budget,name:&str,width:usize)->Result<(),Failure>{
 let bytes=name.len().checked_add(width).and_then(|n|n.checked_mul(4)).and_then(|n|n.checked_add(4096)).ok_or_else(||{budget.deny();oom("check_grep binding admission overflow")})?;
 budget.charge(bytes).map_err(oom)
}
fn add_local(bindings:&mut Bindings,budget:&Budget,name:&str,ty:Option<String>)->Result<(),Failure>{
 if let Some(existing)=bindings.types.get_mut(name){*existing=None;}else{directory_charge(budget,name,0)?;bindings.types.insert(name.to_owned(),ty);}Ok(())
}
pub(crate) fn bindings(body:&dm_tree::frontend::CurrentArchivedBody<'_,'_>,admission:&dm_syntax::SettingAdmission<'_>,budget:&Budget,poll:&dyn Fn()->std::io::Result<()>)->Result<Bindings,Failure>{
 let mut bindings=Bindings{types:std::collections::BTreeMap::new(),slot_shadowed:false};
 let parameters=body.source_parameters(admission).map_err(crate::captured_untyped_pages::body_failure)?;
 for parameter in parameters.entries()?{
  budget.require().map_err(oom)?;poll()?;
  if parameter.variadic(){continue}
  let name=parameters.name(parameter)?;
  let width=parameter.type_components().iter().try_fold(5usize,|width,span|width.checked_add(span.end.checked_sub(span.start)?).and_then(|width|width.checked_add(1))).ok_or_else(||{budget.deny();oom("check_grep parameter width overflow")})?;
  directory_charge(budget,name,width)?;
  // Parameter duplicates preserve the original collect-last behavior.
  let ty=parameters.type_path(parameter)?;bindings.types.insert(name.to_owned(),ty);
  bindings.slot_shadowed|=name=="slot_flags";
 }
 let locals=body.source_locals(admission).map_err(crate::captured_untyped_pages::body_failure)?;
 struct LocalWalk<'a,F>{locals:dm_tree::frontend::SourceLocalView<'a>,bindings:&'a mut Bindings,budget:&'a Budget,poll:F,error:Option<Failure>}
 impl<F:Fn()->std::io::Result<()>> LocalWalk<'_,F>{
  fn statement_facts(&mut self,node:&dm_syntax::Statement)->Result<(),Failure>{
   self.budget.require().map_err(oom)?;(self.poll)()?;
   use dm_syntax::{StatementKind as S,ForControl as C};
   let local_rows=matches!(&node.kind,S::Var{..}|S::For{control:C::All{..}|C::Each{..}|C::Pair{..},..});
   if local_rows{
    let pair=matches!(&node.kind,S::For{control:C::Pair{..},..});
    let rows=self.locals.in_span(node.header_span)?;
    for row in rows{
     let name=self.locals.name(row)?;let width=self.locals.type_path_width(row)?;
     self.budget.charge(width.checked_mul(4).and_then(|n|n.checked_add(64)).ok_or_else(||{self.budget.deny();oom("check_grep local type width overflow")})?).map_err(oom)?;
     let ty=if pair{None}else{self.locals.type_path(row)?};
     self.bindings.slot_shadowed|=name=="slot_flags";
     add_local(self.bindings,self.budget,name,ty)?;
    }
    // Untyped for-in/key-value binders are already grammar-issued identifiers,
    // but deliberately have no LocalVariableSyntax declaration row.
    let mut bare=|name:&str|->Result<(),Failure>{
     if name.is_empty()||!name.chars().all(|c|c.is_alphanumeric()||c=='_'){return Err(Failure::Unsupported("check_grep untyped loop binder is not an issued bare identifier".into()))}
     if !rows.iter().any(|row|self.locals.name(row).is_ok_and(|actual|actual==name)){add_local(self.bindings,self.budget,name,None)?;}
     Ok(())
    };
    match &node.kind{
     S::For{control:C::Each{binding,..},..} if rows.is_empty()=>bare(binding)?,
     S::For{control:C::Pair{key_binding,value_binding,..},..}=>{if !key_binding.starts_with("var/"){bare(key_binding)?;}if !value_binding.starts_with("var/"){bare(value_binding)?;}},
     _=>(),
    }
   }
   Ok(())
  }
 }
 impl<F:Fn()->std::io::Result<()>> TypedVisitor for LocalWalk<'_,F>{
  fn projected_expression(&mut self,_:ProjectedExprView<'_>,_:&[dm_syntax::NodeStep])->VisitDecision{VisitDecision::Skip}
  fn expression(&mut self,_:&Expr,_:&[dm_syntax::NodeStep])->VisitDecision{VisitDecision::Skip}
  fn statement(&mut self,node:&dm_syntax::Statement,_:&[dm_syntax::NodeStep])->VisitDecision{if self.error.is_some(){return VisitDecision::Stop}match self.statement_facts(node){Ok(())=>VisitDecision::Descend,Err(error)=>{self.error=Some(error);VisitDecision::Stop}}}
 }
 {let mut walk=LocalWalk{locals,bindings:&mut bindings,budget,poll,error:None};dm_syntax::visit_statement_view(body.syntax().canonical_statement_storage().view(),&mut walk);if let Some(error)=walk.error{return Err(error)}}
 budget.require().map_err(oom)?;poll()?;budget.require().map_err(oom)?;Ok(bindings)
}

#[cfg(test)]mod tests{
 use super::*;
 fn body(source:&str)->dm_syntax::ParsedBody{let syntax=dm_syntax::parse(source);assert!(syntax.diagnostics.is_empty(),"{:?}",syntax.diagnostics);let body=dm_syntax::parse_body_items(&syntax.items[0].children);assert!(body.diagnostics.is_empty(),"{:?}",body.diagnostics);body}
 #[test]fn primary_candidates_preserve_complete_follow_chains_groups_and_mask_rules(){
  let source="/proc/probe()\n    set_slot_flags(slot_flags & ~FLAG)\n    src.set_slot_flags((src.slot_flags) & (FLAG | 2))\n    set_slot_flags(slot_flags & src.flags)\n    a.holder\n    a.holder.other\n    a.holder()\n    a?.holder\n    (a).holder\n";
  let parsed=body(source);let budget=Budget::new(1<<20).unwrap();let mut found=Vec::new();
  candidates(&parsed,&budget,&||Ok(()),|candidate|{match candidate{Candidate::Slot{offset,through_src}=>{assert!(source[offset..].starts_with(if through_src{"src"}else{"slot_flags"}));found.push(if through_src{"src-slot"}else{"slot"}.to_owned());},Candidate::Holder{offset,receiver}=>{assert!(source[offset..].starts_with(receiver));found.push(format!("holder:{receiver}"));}}Ok(())}).unwrap();
  assert_eq!(found,["slot","src-slot","holder:a","holder:a"]);
 }
 #[test]fn primary_candidate_callback_first_io_survives_later_cancellation(){
  let parsed=body("/proc/p()\n    a.holder\n    b.holder\n");let budget=Budget::new(1<<20).unwrap();let cancelled=std::cell::Cell::new(false);let mut visits=0;
  let result=candidates(&parsed,&budget,&||if cancelled.get(){Err(std::io::Error::new(std::io::ErrorKind::Interrupted,"late"))}else{Ok(())},|_|{visits+=1;cancelled.set(true);Err(Failure::Operational(std::io::Error::from_raw_os_error(1450)))});
  assert!(matches!(result,Err(Failure::Operational(ref error)) if error.raw_os_error()==Some(1450)));assert_eq!(visits,1);
 }
 #[test]fn numeric_mask_denial_is_typed_before_late_poll_and_fresh_retry(){
  let parsed=body("/proc/p()\n    set_slot_flags(slot_flags & 12)\n");let tiny=Budget::new(128).unwrap();let mut visits=0;
  let result=candidates(&parsed,&tiny,&||if tiny.denied(){Err(std::io::Error::new(std::io::ErrorKind::Interrupted,"late"))}else{Ok(())},|_|{visits+=1;Ok(())});
  assert!(matches!(result,Err(Failure::Operational(ref error)) if error.kind()==std::io::ErrorKind::OutOfMemory));assert_eq!(visits,0);
  let healthy=Budget::new(1<<20).unwrap();candidates(&parsed,&healthy,&||Ok(()),|_|{visits+=1;Ok(())}).unwrap();assert_eq!(visits,1);
 }
}

#[derive(Default)]pub struct Positions{pub slots:std::collections::BTreeSet<(usize,usize)>,pub holders:std::collections::BTreeSet<(usize,usize)>}
fn insert_position(set:&mut std::collections::BTreeSet<(usize,usize)>,point:(usize,usize),budget:&Budget)->Result<(),Failure>{if !set.contains(&point){budget.charge(1024).map_err(oom)?;set.insert(point);}Ok(())}
/// Same original effective-name selection used by the old defs_in/proc_ref loop.
pub(crate) fn is_effective_body(archive:&dm_tree::frontend::BodyArchive,ordinal:usize,budget:&Budget)->Result<bool,Failure>{
 use dm_ir::SymbolId;use dm_analysis::checker_call_facts::{callable_any,CallableFact};
 let occurrence=archive.occurrences().get(ordinal).ok_or("check_grep original body ordinal absent")?;
 if archive.callables().ordinal(occurrence.member)!=Some(ordinal){return Err("check_grep original body ordinal/roster differs".into())}
 let tree=archive.tree();let profile=tree.checker_builtin_profile().ok_or("check_grep checker profile absent")?;
 let member=tree.member(occurrence.member).ok_or("check_grep original callable member absent")?;
 let owner=tree.type_node(member.owner).ok_or("check_grep original owner absent")?.path;
 let identity=archive.callables().identity_for_member(occurrence.member).ok_or("check_grep original callable identity absent")?;
 let resolution=archive.callables().members().len().checked_mul(std::mem::size_of::<dm_ir::ResolvedMeaning>()*16).and_then(|n|n.checked_add(tree.types().len().checked_mul(std::mem::size_of::<SymbolId>()*16)?)).and_then(|n|n.checked_add(8192)).ok_or_else(||{budget.deny();oom("check_grep callable answer envelope overflow")})?;
 budget.charge(resolution).map_err(oom)?;
 Ok(matches!(callable_any(tree,tree,profile,owner,member.name)?,CallableFact::Source{identity:selected,..}if selected==identity))
}
/// Accept candidates from one actual archive body only after the same original
/// callable, type, variable and reported-file questions succeed. Caller keeps
/// this body-local scratch alive until every temporary has physically dropped;
/// returned position nodes are separately funded on the operation's root.
pub(crate) fn positions_for_body(
 archive:&dm_tree::frontend::BodyArchive,body:&dm_tree::frontend::CurrentArchivedBody<'_,'_>,admission:&dm_syntax::SettingAdmission<'_>,
 root:&std::path::Path,file:&crate::tree::SourceFile,tracked_slot_owners:&std::collections::BTreeSet<String>,
 want_slots:bool,want_holders:bool,scratch:&Budget,output_budget:&Budget,
 poll:&dyn Fn()->std::io::Result<()>,out:&mut Positions,
)->Result<(),Failure>{
 use dm_ir::SymbolId;use dm_analysis::checker_call_facts::{callable_any,CallableFact};
 if !body.belongs_to(archive)||!file.is_captured_input(){return Err("check_grep semantic loan lacks its actual archive/captured file".into())}
 let syntax=body.syntax();
 let statements=syntax.canonical_statement_storage();
 if !statements.original_literal_syntax_complete(){return Err("check_grep body primary syntax is not complete".into())}
 let tree=archive.tree();let profile=tree.checker_builtin_profile().ok_or("check_grep body checker profile absent")?;
 let proof=tree.validated_checker_profile(profile).map_err(|error|Failure::Unsupported(format!("check_grep checker profile: {error:?}")))?;
 let member=tree.member(body.occurrence().member).ok_or("check_grep original callable member absent")?;
 let owner=tree.type_node(member.owner).and_then(|node|tree.symbols().text(node.path)).ok_or("check_grep original owner spelling absent")?;
 let _name=tree.symbols().text(member.name).ok_or("check_grep original callable spelling absent")?;
 let identity=archive.callables().identity_for_member(body.occurrence().member).ok_or("check_grep actual original callable identity absent")?;
 // Existing call resolver materializes answer/ancestry vectors. This active
 // body scratch preadmits their simultaneous backing, not a retained index.
 let resolution=archive.callables().members().len().checked_mul(std::mem::size_of::<dm_ir::ResolvedMeaning>()*16).and_then(|n|n.checked_add(tree.types().len().checked_mul(std::mem::size_of::<SymbolId>()*16)?)).and_then(|n|n.checked_add(8192)).ok_or_else(||{scratch.deny();oom("check_grep callable answer envelope overflow")})?;
 scratch.charge(resolution).map_err(oom)?;
 match callable_any(tree,tree,profile,SymbolId::of(owner),member.name)?{CallableFact::Source{identity:selected,..} if selected==identity=>(),CallableFact::Source{..}|CallableFact::CheckerBuiltin{..}|CallableFact::Missing=>return Ok(())}
 let check=||->Result<(),Failure>{scratch.require().map_err(oom)?;poll()?;scratch.require().map_err(oom)};
 let subtype=|child:&str,parent:&str|crate::reactive_original_source::subtype_original(tree,child,parent,&mut||check(),&mut|path|tree.checker_source_type_presence(profile,path).map_err(|error|Failure::Unsupported(format!("check_grep source type: {error:?}"))));
 let mut slot_enabled=false;
 if want_slots{
  for tracked in tracked_slot_owners{check()?;if subtype(owner,tracked)?{slot_enabled=true;break}}
  if slot_enabled{slot_enabled=matches!(callable_any(tree,tree,profile,SymbolId::of(owner),SymbolId::of("set_slot_flags"))?,CallableFact::Source{..});}
 }
 if !slot_enabled&&!want_holders{return Ok(())}
 let bindings=bindings(body,admission,scratch,poll)?;
 let header=archive.callable_header_source().reported_point(body.occurrence().member)?;
 let(header_path,_,_)=header.reported_coordinates();
 let mut path_peak=header_path.as_os_str().len().checked_add(root.as_os_str().len()).and_then(|n|n.checked_mul(128)).and_then(|n|n.checked_add(4096)).ok_or_else(||{scratch.deny();oom("check_grep header path envelope overflow")})?;
 scratch.charge(path_peak).map_err(oom)?;
 if crate::util::rel_slash(header_path,root)!=file.rel{return Ok(())}
 // The existing visitor resolves nested setting projections into the canonical
 // body's coordinates. Rebase only that checked point to the current occurrence.
 candidates(statements.parsed(),scratch,poll,|candidate|{
  let original=match candidate{Candidate::Slot{offset,..}|Candidate::Holder{offset,..}=>offset};
  let offset=syntax.projection().span(dm_syntax::Span::new(original,original))
   .ok_or("check_grep candidate escapes its actual current body projection")?.start;
  let point=archive.borrowed_source_note_point(offset)?;let(registration,line,column)=point.reported_coordinates();
  let peak=registration.as_os_str().len().checked_add(root.as_os_str().len()).and_then(|n|n.checked_mul(128)).and_then(|n|n.checked_add(4096)).ok_or_else(||{scratch.deny();oom("check_grep report path envelope overflow")})?;
  if peak>path_peak{scratch.charge(peak-path_peak).map_err(oom)?;path_peak=peak;}
  if crate::util::rel_slash(registration,root)!=file.rel{return Ok(())}
  match candidate{
   Candidate::Slot{through_src,..} if slot_enabled&&(through_src||!bindings.slot_shadowed)=>{
    let column=column.checked_add(if through_src{4}else{0}).ok_or("check_grep slot column overflow")?;
    insert_position(&mut out.slots,(line,column),output_budget)?;
   },
   Candidate::Holder{receiver,..} if want_holders=>{
    let Some(ty)=(if receiver=="src"{Some(owner)}else{bindings.receiver_type(receiver)})else{return Ok(())};
    if !tree.checker_source_type_presence(profile,ty).map_err(|error|Failure::Unsupported(format!("check_grep holder type: {error:?}")))?||subtype(ty,"/client")?||subtype("/client",ty)?{return Ok(())}
    if dm_analysis::checker_variable_facts::variable_original_validated(tree,&proof,profile,SymbolId::of(ty),SymbolId::of("holder"))?.is_none(){return Ok(())}
    let Some(start)=column.checked_sub(1)else{return Err("check_grep original holder column is zero".into())};
    let Some(column)=crate::check_grep_semantic_policy::holder_column(file.raw_quiet().line(line),start,receiver)else{return Ok(())};
    insert_position(&mut out.holders,(line,column),output_budget)?;
   },_=>(),
  }Ok(())
 })?;
 check()
}
