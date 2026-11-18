//! Actual native call occurrence loan for the original codemod edit kernel.
//! No parser, semantic clone, persistent index, source grant or writer.
use std::{io,path::Path,sync::Arc};
use crate::{captured_generator_budget::Budget,reactive_original_source::ReadSource,reactive_reads_native::Failure,reactive_global_source::{Source,Body}};
use dm_syntax::{ExprKind,StatementKind,Span,VisitDecision};
pub struct Call<'a>{pub relative:&'a str,pub line:u32,pub column:u32,pub callee:&'a str,pub arguments:usize,pub owner:&'a str,pub procedure:&'a str,pub whole_statement:bool}
type Borrower<'a>=dyn Fn(&Arc<dm_tree::frontend::BodySyntaxInput>)->Result<Arc<dm_tree::frontend::OriginalBodySyntaxProduct>,dm_tree::frontend::BodySyntaxFailure>+'a;
/// Callback rows borrow the SAME actual current body. Their scalar DATA does
/// not grant rewrite authority; caller retains native ledger/current facts.
pub fn visit(inputs:&dm_analysis::policy_inputs::PolicyInputs,root:&Path,names:&[&str],excluded:&dyn Fn(&str)->bool,budget:&Arc<Budget>,poll:&dyn Fn()->io::Result<()>,body:&Borrower<'_>,work:&dyn crate::policy_finish::admitted::Work,path_work:&dyn dm_preprocess::source_arena_credit::SourceArenaWork,emit:&mut dyn for<'a> FnMut(Call<'a>)->Result<(),Failure>)->Result<(),Failure>{
 let pending=(||{
 let source=ReadSource::native(inputs,root,budget)?.with_checkpoint(poll).with_utility_body_borrower(body);source.require()?;
 for(ordinal,occurrence)in source.occurrences().iter().enumerate(){
  poll()?;source.require()?;let header=source.inputs().archive().callable_header_policy_line(occurrence.member)?;let canonical=if source.inputs().file_exact(&header.path).is_none(){Some(dm_preprocess::regions::canonical_path_using(&header.path,path_work).map_err(Failure::Operational)?)}else{None};let file=source.inputs().file_exact(canonical.as_ref().map_or(header.path.as_path(),dm_preprocess::regions::FundedPath::path)).ok_or("native codemod original header file unavailable")?;let mut relative_credit=path_work.reserve(0).map_err(Failure::Operational)?;let relative=match dm_preprocess::regions::relative_slash_into_credit(file.path(),root,path_work,&mut relative_credit).map_err(Failure::Operational)?{Some(relative)=>relative,None=>dm_preprocess::regions::slash_path_into_credit(file.path(),path_work,&mut relative_credit).map_err(Failure::Operational)?};if excluded(&relative){continue}let tree=source.tree();let member=tree.member(occurrence.member).ok_or("native codemod callable member unavailable")?;let owner=tree.type_node(member.owner).and_then(|node|tree.symbols().text(node.path)).ok_or("native codemod owner unavailable")?;let procedure=tree.symbols().text(member.name).ok_or("native codemod procedure unavailable")?;
  source.with_body(ordinal,&mut|actual:&dyn Body|{
   let syntax=actual.statement_body();if !syntax.original_literal_syntax_complete(){return Err("native codemod requires actual complete canonical body syntax".into())}
   struct Walker<'source,'scope,'emit>{source:&'scope ReadSource<'source>,root:&'scope Path,names:&'scope[&'scope str],owner:&'scope str,procedure:&'scope str,whole:Option<Span>,error:Option<Failure>,work:&'scope dyn crate::policy_finish::admitted::Work,path_work:&'scope dyn dm_preprocess::source_arena_credit::SourceArenaWork,emit:&'emit mut dyn for<'v> FnMut(Call<'v>)->Result<(),Failure>}
   impl Walker<'_,'_,'_>{fn call(&mut self,node:&dm_syntax::Expr,current:Span)->VisitDecision{
    if let Err(error)=self.source.checkpoint(){self.error=Some(Failure::Operational(error));return VisitDecision::Stop}
    let ExprKind::Call{callee,args}=&node.kind else{return VisitDecision::Descend};let ExprKind::Ident(name)=&callee.kind else{return VisitDecision::Descend};if !self.names.contains(&name.as_str()){return VisitDecision::Descend}
    if callee.span.start!=node.span.start{self.error=Some("native codemod callee has no exact current opening".into());return VisitDecision::Stop}
    let answer=(||{let point=self.source.inputs().archive().source_mapping().original_note_origin(current.start)?;let mut relative_credit=self.path_work.reserve(0).map_err(Failure::Operational)?;let relative=dm_preprocess::regions::relative_slash_into_credit(point.path.as_path(),self.root,self.path_work,&mut relative_credit).map_err(Failure::Operational)?.ok_or("native codemod physical source is outside its captured namespace")?;if Path::new(&relative).components().any(|part|matches!(part,std::path::Component::ParentDir)){return Err("native codemod source escapes captured namespace".into())}let row=Call{relative:&relative,line:u32::try_from(point.line).map_err(|_|"native codemod line overflow")?,column:u32::try_from(point.byte_column).map_err(|_|"native codemod column overflow")?,callee:name,arguments:args.len(),owner:self.owner,procedure:self.procedure,whole_statement:self.whole==Some(node.span)};(self.emit)(row)})();if let Err(error)=answer{self.error=Some(error);VisitDecision::Stop}else{VisitDecision::Descend}
   }}
   impl dm_analysis::policy_body_observation::BaseChainVisitor for Walker<'_,'_,'_>{
    fn statement(&mut self,node:&dm_syntax::Statement)->VisitDecision{if self.error.is_some(){return VisitDecision::Stop}self.whole=match &node.kind{StatementKind::Call(expr)|StatementKind::Expression(expr)=>Some(expr.span),_=>None};VisitDecision::Descend}
    fn expression(&mut self,node:&dm_syntax::Expr,_:bool)->VisitDecision{self.call(node,node.span)}
    fn projected_expression(&mut self,node:dm_syntax::ProjectedExprView<'_>,_:bool)->VisitDecision{self.call(node.original(),node.current_span())}
    fn frame_capacity(&mut self,bytes:usize)->Result<(),&'static str>{match self.work.reserve(bytes){Ok(())=>Ok(()),Err(first)=>{if self.error.is_none(){self.error=Some(Failure::Operational(first))}Err("native codemod canonical observation frame admission refused")}}}
    fn frame_overflow(&mut self)->&'static str{if self.error.is_none(){self.error=Some(Failure::Operational(self.work.overflow()))}"native codemod canonical observation frame overflow"}
    fn frame_allocation_failed(&mut self)->&'static str{if self.error.is_none(){self.error=Some(Failure::Operational(self.work.overflow()))}"native codemod canonical observation frame allocation failed"}
   }
   let mut walker=Walker{source:&source,root,names,owner,procedure,whole:None,error:None,work,path_work,emit};
   let pending=dm_analysis::policy_body_observation::observe_base_chains(syntax.view(),&mut walker);
   if let Some(first)=walker.error{return Err(first)}pending?;
   poll()?;source.require()?;Ok(())
  })?;
 }
 poll()?;source.require()?;Ok(())
 })();
 if matches!(&pending,Err(Failure::Operational(_))){return pending}
 budget.require().map_err(|m|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,m)))?;poll()?;pending
}

/// Escaping candidate DATA keeps its actual SAME raw-family grant. It never
/// carries a source/completion or physical rewrite permission.
pub struct Rows{rows:Vec<crate::codemod::Cand>,credit:dm_preprocess::source_arena_credit::SourceArenaCredit}
impl Rows{
 pub fn rows(&self)->&[crate::codemod::Cand]{&self.rows}
 pub fn collect(inputs:&dm_analysis::policy_inputs::PolicyInputs,root:&Path,names:&[&str],aliases:&[(&str,&str,usize)],excluded:&dyn Fn(&str)->bool,budget:&Arc<Budget>,poll:&dyn Fn()->io::Result<()>,body:&Borrower<'_>,frames:&dyn crate::policy_finish::admitted::Work,work:&dyn dm_preprocess::source_arena_credit::SourceArenaWork)->Result<Self,Failure>{
  let mut actual=Self{rows:Vec::new(),credit:work.reserve(0).map_err(Failure::Operational)?};
  // Match the original candidate factory's authored-plus-expanded name demand.
  // This is borrowed CLI metadata, not another AST traversal or source grant.
  let count=names.len().checked_add(aliases.len()).ok_or_else(||Failure::Operational(io::ErrorKind::OutOfMemory.into()))?;
  let upper=count.checked_mul(4).ok_or_else(||Failure::Operational(io::ErrorKind::OutOfMemory.into()))?;
  let names_paid=upper.checked_mul(std::mem::size_of::<&str>()).ok_or_else(||Failure::Operational(io::ErrorKind::OutOfMemory.into()))?;
  let mut names_credit=work.reserve(names_paid).map_err(Failure::Operational)?;
  let mut ast_names=Vec::new();ast_names.try_reserve_exact(count).map_err(|_|Failure::Operational(io::ErrorKind::OutOfMemory.into()))?;
  if ast_names.capacity()>upper{return Err(Failure::Operational(io::ErrorKind::OutOfMemory.into()))}
  work.shrink(&mut names_credit,names_paid.checked_sub(ast_names.capacity()*std::mem::size_of::<&str>()).ok_or_else(||Failure::Operational(io::ErrorKind::OutOfMemory.into()))?).map_err(Failure::Operational)?;
  ast_names.extend_from_slice(names);ast_names.extend(aliases.iter().map(|(actual,_,_)|*actual));
  visit(inputs,root,&ast_names,excluded,budget,poll,body,frames,work,&mut|row|{
   work.checkpoint().map_err(Failure::Operational)?;
   if actual.rows.len()==actual.rows.capacity(){
    let wanted=actual.rows.capacity().max(4).checked_mul(2).ok_or_else(||Failure::Operational(io::ErrorKind::OutOfMemory.into()))?;
    let upper=wanted.checked_mul(4).ok_or_else(||Failure::Operational(io::ErrorKind::OutOfMemory.into()))?;
    let old=actual.rows.capacity().checked_mul(std::mem::size_of::<crate::codemod::Cand>()).ok_or_else(||Failure::Operational(io::ErrorKind::OutOfMemory.into()))?;
    let paid=upper.checked_mul(std::mem::size_of::<crate::codemod::Cand>()).ok_or_else(||Failure::Operational(io::ErrorKind::OutOfMemory.into()))?;work.grow(&mut actual.credit,paid).map_err(Failure::Operational)?;
    actual.rows.try_reserve_exact(wanted-actual.rows.len()).map_err(|_|Failure::Operational(io::ErrorKind::OutOfMemory.into()))?;
    if actual.rows.capacity()>upper{return Err(Failure::Operational(io::ErrorKind::OutOfMemory.into()))}
    let live=actual.rows.capacity().checked_mul(std::mem::size_of::<crate::codemod::Cand>()).ok_or_else(||Failure::Operational(io::ErrorKind::OutOfMemory.into()))?;work.shrink(&mut actual.credit,old.checked_add(paid).and_then(|n|n.checked_sub(live)).ok_or_else(||Failure::Operational(io::ErrorKind::OutOfMemory.into()))?).map_err(Failure::Operational)?;
   }
   let mut copy=|text:&str|->Result<String,Failure>{dm_preprocess::regions::copy_string_into_credit(text,work,&mut actual.credit).map_err(Failure::Operational)};
   let(callee,argc)=crate::codemod::normalized_candidate(row.callee,row.arguments,aliases);
   let row=crate::codemod::Cand{rel:copy(row.relative)?,line:row.line,col:row.column,callee:copy(callee)?,argc,owner:copy(row.owner)?,proc_name:copy(row.procedure)?,stmt_level:row.whole_statement};
   actual.rows.push(row);Ok(())
  })?;
  drop(ast_names);drop(names_credit);
  // Old growth buffers are dead. Retain actual owned capacities, not a
  // reference-weighted estimate, while the copied candidates escape.
  let mut retained=actual.rows.capacity().checked_mul(std::mem::size_of::<crate::codemod::Cand>()).ok_or_else(||Failure::Operational(io::ErrorKind::OutOfMemory.into()))?;
  for row in &actual.rows{for text in [&row.rel,&row.callee,&row.owner,&row.proc_name]{retained=retained.checked_add(text.capacity()).ok_or_else(||Failure::Operational(io::ErrorKind::OutOfMemory.into()))?;}}
  let excess=actual.credit.reserved_bytes().checked_sub(retained).ok_or_else(||Failure::Operational(io::ErrorKind::InvalidData.into()))?;work.shrink(&mut actual.credit,excess).map_err(Failure::Operational)?;
  Ok(actual)
 }
}
