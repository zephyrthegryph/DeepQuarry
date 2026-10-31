//! Borrow original canonical body nodes in existing legacy-policy order.
//! No parser, model, source acquisition or competing statement traversal.
pub fn observe(view:dm_syntax::StatementView<'_>,visitor:&mut impl dm_syntax::TypedVisitor)->Result<(),&'static str>{
    crate::untyped_order::visit_value_policy(view,visitor)
}
