//! SAME canonical old Base prefix/follow projection from the existing Debug core.
//! Borrowed syntax DATA only; no parse, allocation, model or source authority.
use dm_syntax::{Expr,ExprKind};
pub(crate) fn unary(op:&str)->Option<&'static str>{Some(match op{"-"=>"Neg","!"=>"Not","~"=>"BitNot","pre++"=>"PreIncr","post++"=>"PostIncr","pre--"=>"PreDecr","post--"=>"PostDecr","&"=>"Reference","*"=>"Dereference",_=>return None})}
pub fn base_child(expr:&Expr)->Option<&Expr>{match &expr.kind{
 ExprKind::Unary{op,value}if unary(op).is_some()=>Some(value),
 ExprKind::Member{object,..}|ExprKind::SafeMember{object,..}|ExprKind::StaticMember{object,..}|ExprKind::Index{object,..}|ExprKind::SafeIndex{object,..}=>Some(object),
 ExprKind::Call{callee,..}if matches!(callee.kind,ExprKind::Member{..}|ExprKind::SafeMember{..}|ExprKind::StaticMember{..})=>Some(callee),_=>None}}

pub fn leaf_using<'a,E>(mut node:&'a Expr,poll:&mut impl FnMut()->Result<(),E>)->Result<&'a Expr,E>{poll()?;while let Some(next)=base_child(node){poll()?;node=next}Ok(node)}

/// Null comes from the existing canonical keyword producer, not Ident or Group.
pub fn is_null_term(expr:&Expr)->bool{matches!(&expr.kind,ExprKind::Literal(text)if text.as_str()=="null")}
