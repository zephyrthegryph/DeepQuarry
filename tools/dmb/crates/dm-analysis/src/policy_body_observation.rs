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
