//! Borrow original canonical body nodes in existing legacy-policy order.
//! No parser, model, source acquisition or competing statement traversal.
pub fn observe(view:dm_syntax::StatementView<'_>,visitor:&mut impl dm_syntax::TypedVisitor)->Result<(),&'static str>{
    crate::untyped_order::visit_value_policy(view,visitor)
}

/// Extra DATA needed by collect_writes_pub: increment/decrement counts only
/// at the terminal node of an old flattened Base chain, not every nested
/// executable unary node. SAME existing policy walk owns all child ordering.
pub trait BaseChainVisitor{
 fn statement(&mut self,node:&dm_syntax::Statement)->dm_syntax::VisitDecision;
 /// SAME old Var/Vars post-root frontier, before nested blocks.
 fn after_variable(&mut self,_:&dm_syntax::Statement)->dm_syntax::VisitDecision{dm_syntax::VisitDecision::Descend}
 fn expression(&mut self,node:&dm_syntax::Expr,chain_child:bool)->dm_syntax::VisitDecision;
 fn projected_expression(&mut self,node:dm_syntax::ProjectedExprView<'_>,chain_child:bool)->dm_syntax::VisitDecision;
 fn expression_at(&mut self,node:&dm_syntax::Expr,chain_child:bool,_at:dm_syntax::Span)->dm_syntax::VisitDecision{self.expression(node,chain_child)}
 fn projected_expression_at(&mut self,node:dm_syntax::ProjectedExprView<'_>,chain_child:bool,_at:dm_syntax::Span)->dm_syntax::VisitDecision{self.projected_expression(node,chain_child)}
 /// Actor tests use each authored If arm's actual condition location, while
 /// the other legacy policy families retain the first statement's location.
 fn if_condition_span(&mut self,_condition:&dm_syntax::Expr,at:dm_syntax::Span)->Result<dm_syntax::Span,&'static str>{Ok(at)}

 fn frame_capacity(&mut self,bytes:usize)->Result<(),&'static str>;
 fn frame_overflow(&mut self)->&'static str;
 fn frame_allocation_failed(&mut self)->&'static str;
}
pub fn observe_base_chains(view:dm_syntax::StatementView<'_>,visitor:&mut impl BaseChainVisitor)->Result<(),&'static str>{crate::untyped_order::visit_base_policy(view,visitor)}

/// Borrow one selected statement expression through the SAME canonical old-
/// policy walker. This is observation DATA, never a parser or source role.
pub fn observe_expression_base_chains(node:&dm_syntax::Expr,at:dm_syntax::Span,visitor:&mut impl BaseChainVisitor)->Result<(),&'static str>{crate::untyped_order::visit_base_expression(node,at,visitor)}
pub fn observe_projected_expression_base_chains(root:&dm_syntax::SettingExpression,at:dm_syntax::Span,visitor:&mut impl BaseChainVisitor)->Result<(),&'static str>{crate::untyped_order::visit_projected_base_expression(root,at,visitor)}

#[cfg(test)]mod selected_expression_controls{
 use super::*;use dm_syntax::{Expr,Span,VisitDecision,StatementKind};
 #[derive(Default)]struct Rows(Vec<(Span,bool,Span)>);
 impl BaseChainVisitor for Rows{fn statement(&mut self,_:&dm_syntax::Statement)->VisitDecision{VisitDecision::Descend}fn expression(&mut self,_:&Expr,_:bool)->VisitDecision{panic!("actual statement-coordinate callback required")}fn expression_at(&mut self,e:&Expr,child:bool,at:Span)->VisitDecision{self.0.push((e.span,child,at));VisitDecision::Descend}fn projected_expression(&mut self,_:dm_syntax::ProjectedExprView<'_>,_:bool)->VisitDecision{panic!("owned fixture") }fn frame_capacity(&mut self,_:usize)->Result<(),&'static str>{Ok(())}fn frame_overflow(&mut self)->&'static str{"overflow"}fn frame_allocation_failed(&mut self)->&'static str{"allocation"}}
 #[test]fn selected_expression_loans_preserve_same_root_follow_and_argument_stream(){
  for expression in ["call(named = A, container.Insert(A), new /datum(foo = A), list(A))","target::reference(ignored = A)","new /datum/probe(foo(A))"]{
   let source=format!("/proc/p()\n    {expression}\n");let syntax=dm_syntax::parse(&source);assert!(syntax.diagnostics.is_empty());let body=dm_syntax::parse_proc_body(&syntax.items[0]);assert!(body.diagnostics.is_empty());let statement=&body.statements[0];let expression=match &statement.kind{StatementKind::Call(e)|StatementKind::Expression(e)=>e,_=>panic!("actual selected expression")};let mut whole=Rows::default();let mut selected=Rows::default();observe_base_chains(dm_syntax::StatementView::from_parsed(&body),&mut whole).unwrap();observe_expression_base_chains(expression,statement.span,&mut selected).unwrap();assert_eq!(whole.0,selected.0,"selected root must reuse whole-body canonical child/filter order");
  }
 }
}
