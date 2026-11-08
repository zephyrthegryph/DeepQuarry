//! Borrow the existing native body AST for the original setter's boolean facts.
//! No semantic inference, second parser/model, source issuance or cache.
use crate::policy_body_demand::WorkspaceWork;
use dm_syntax::{Expr,ExprKind,Statement,StatementKind,VisitDecision};
#[path="../../../shared/setter_publication.rs"]mod judge;
#[derive(Clone,Copy,Debug,Eq,PartialEq)]pub struct BodyPublication{pub writes:bool,pub publishes:bool}
struct Scan<'a,W:WorkspaceWork>{work:&'a mut W,var:&'a str,flags:BodyPublication,error:Option<W::Error>}
impl<W:WorkspaceWork> Scan<'_,W>{
 fn note_target(&mut self,mut e:&Expr)->Result<(),W::Error>{loop{self.work.checkpoint()?;match &e.kind{ExprKind::Index{object,..}|ExprKind::SafeIndex{object,..}=>e=object,ExprKind::Ident(name)=>{self.flags.writes|=name==self.var;return Ok(())},ExprKind::Member{selector,..}|ExprKind::SafeMember{selector,..}=>{self.flags.writes|=selector==self.var;return Ok(())},ExprKind::StaticMember{..}=>return Ok(()),_=>return Ok(())}}}
 fn expr(&mut self,e:&Expr,chain_child:bool)->Result<(),W::Error>{self.work.checkpoint()?;match &e.kind{
  ExprKind::Binary{op,lhs,..}if dm_syntax::assignment_target_access(op).is_some()=>self.note_target(lhs)?,
  ExprKind::Unary{op,value}if !chain_child&&matches!(op.as_str(),"++"|"--"|"post++"|"post--")=>self.note_target(value)?,
  ExprKind::Call{callee,..}=>match dm_syntax::call_target(callee){
   dm_syntax::CallTarget::Named(name)=>{self.flags.publishes|=name==".."||judge::publishes_named(name)||judge::owned_base_call(name)},
   dm_syntax::CallTarget::Member{selector,..}|dm_syntax::CallTarget::SafeMember{selector,..}=>self.flags.publishes|=judge::publishes_named(selector),
   // Canonical policy_body_observation already projects Scope calls as
   // old ProcReference (including its genuinely discarded arguments).
   _=>{},
  },_=>{}
 }Ok(())}
 fn accept(&mut self,result:Result<(),W::Error>)->VisitDecision{match result{Ok(())=>VisitDecision::Descend,Err(actual)=>{self.error=Some(actual);VisitDecision::Stop}}}
}
impl<W:WorkspaceWork> crate::policy_body_observation::BaseChainVisitor for Scan<'_,W>{
 fn frame_capacity(&mut self,n:usize)->Result<(),&'static str>{if let Err(actual)=self.work.temporary(n){self.error=Some(actual);return Err("setter actual frame admission refused")}Ok(())}
 fn frame_overflow(&mut self)->&'static str{self.error=Some(self.work.overflow());"setter actual frame geometry overflow"}
 fn frame_allocation_failed(&mut self)->&'static str{self.error=Some(self.work.allocation_failed());"setter actual frame allocation refused"}
 fn statement(&mut self,s:&Statement)->VisitDecision{if self.error.is_some(){return VisitDecision::Stop}let result=(||{self.work.checkpoint()?;if let StatementKind::Assign{target,..}=&s.kind{self.note_target(target)?}Ok(())})();self.accept(result)}
 fn expression(&mut self,e:&Expr,child:bool)->VisitDecision{if self.error.is_some(){return VisitDecision::Stop}let result=self.expr(e,child);self.accept(result)}
 fn projected_expression(&mut self,e:dm_syntax::ProjectedExprView<'_>,child:bool)->VisitDecision{if self.error.is_some(){return VisitDecision::Stop}let result=self.expr(e.original(),child);self.accept(result)}
}

/// Unique flags only. Full original policy admission additionally requires the
/// actual old Some/None body outcome; native acceptance alone is not that proof.
pub fn observe_body<W:WorkspaceWork>(body:&dm_tree::frontend::ArchivedBody<'_>,var:&str,work:&mut W)->Result<BodyPublication,W::Error>{observe_statement_body(body.statement_body(),var,work)}
pub fn observe_statement_body<W:WorkspaceWork>(syntax:&dm_tree::frontend::StatementBody,var:&str,work:&mut W)->Result<BodyPublication,W::Error>{
 work.checkpoint()?;if !syntax.original_literal_syntax_complete()||!syntax.has_native_literal_syntax(){return Err("setter publication needs complete actual native body syntax".into())}let mut scan=Scan{work,var,flags:BodyPublication{writes:false,publishes:false},error:None};let coverage=crate::policy_body_observation::observe_base_chains(syntax.view(),&mut scan);if let Some(actual)=scan.error{return Err(actual)}coverage.map_err(W::Error::from)?;let flags=scan.flags;scan.work.checkpoint()?;Ok(flags)
}

/// Own-group values in the SAME original formal-front/implicit-back chronology.
/// No inherited get_proc lookup, Proc-first choice, copied roster or body parse.
pub fn visit_own_values_using<W:WorkspaceWork>(inputs:&crate::policy_inputs::PolicyInputs,owner:&str,name:&str,work:&mut W,emit:&mut impl FnMut(usize,bool,&mut W)->Result<(),W::Error>)->Result<bool,W::Error>{
 visit_archive_own_values_using(inputs.archive(),owner,name,work,emit)
}
/// Shared neutral own-value DATA visitor. No model/source completeness grant.
pub(crate) fn visit_archive_own_values_using<W:WorkspaceWork>(archive:&dm_tree::frontend::BodyArchive,owner:&str,name:&str,work:&mut W,emit:&mut impl FnMut(usize,bool,&mut W)->Result<(),W::Error>)->Result<bool,W::Error>{
 use dm_ir::SymbolId;
 work.checkpoint()?;let tree=archive.tree();let profile=tree.checker_builtin_profile().ok_or("setter publication needs actual Original checker profile")?;
 if !tree.checker_source_type_presence(profile,owner).map_err(|_|"setter own group type presence is unissued")?{return Ok(false)}
 visit_admitted_own_values_using(archive,profile,SymbolId::of(owner),SymbolId::of(name),work,emit)
}

/// The whole-workspace roster already has the same tree's profile and a real
/// authored member for this owner/name. Read directly from that immutable tree.
pub(crate) fn visit_admitted_own_values_using<W:WorkspaceWork>(archive:&dm_tree::frontend::BodyArchive,profile:dm_ir::PackedU128,owner:dm_ir::SymbolId,name:dm_ir::SymbolId,work:&mut W,emit:&mut impl FnMut(usize,bool,&mut W)->Result<(),W::Error>)->Result<bool,W::Error>{
 let tree=archive.tree();
 let controlled=std::cell::RefCell::new(work);let group=crate::checker_original_group::Group::issue_using(tree,profile,owner,name,&mut||controlled.borrow_mut().checkpoint())?;let mut any=false;
 group.visit_source_values_using(&mut||controlled.borrow_mut().checkpoint(),&mut|identity,verb|{
  any=true;
  let mut work=controlled.borrow_mut();
  // The callable roster was issued from these very BodyOccurrences and
  // rejects duplicate ProcedureIdentity and MemberId at issuance. Group
  // emitted an actual chain member, so resolve through that same chain.
  let callables=archive.callables();
  let ordinal=callables.ordinal_for_identity_using(identity,&mut||work.checkpoint())?
   .ok_or("setter source value has no issued original body availability outcome")?;
  let occurrence=archive.occurrences().get(ordinal)
   .ok_or("setter source value has no issued original body availability outcome")?;
  if callables.identity_for_member(occurrence.member)!=Some(identity)
   || archive.body_index(occurrence.declaration)!=Some(ordinal){
   return Err("setter source value differs from the actual body occurrence".into());
  }
  work.checkpoint()?;
  emit(ordinal,verb,&mut **work)
 })?;controlled.borrow_mut().checkpoint()?;Ok(any)
}
