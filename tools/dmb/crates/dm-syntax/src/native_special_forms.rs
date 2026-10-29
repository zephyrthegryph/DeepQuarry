//! Borrowed views of constructor/locate forms ALREADY issued by primary syntax.
//! No source scan, expression parse, AST clone or alternate grammar.
use crate::{Expr,ExprKind};
pub enum Constructor<'a> {
    Implicit {args:&'a [Expr]},
    Static {path:&'a str,args:&'a [Expr]},
    Dynamic,
}
pub fn constructor(expr:&Expr)->Result<Option<Constructor<'_>>,&'static str> {
    match &expr.kind {
        ExprKind::Call {callee,args} if matches!(&callee.kind,ExprKind::Ident(name) if name=="new") => Ok(Some(Constructor::Implicit{args})),
        ExprKind::Unary {op,value} if op=="new"=>{
            let (target,args)=match &value.kind {ExprKind::Call{callee,args}=>(callee.as_ref(),args.as_slice()),_ => (value.as_ref(),&[][..])};
            match &target.kind {
                ExprKind::TypePath(path)=>Ok(Some(Constructor::Static{path,args})),
                ExprKind::Ident(_)|ExprKind::Member{..}=>Ok(Some(Constructor::Dynamic)),
                _=>Err("constructor prefab modifications/target context is not issued"),
            }
        }
        _=>Ok(None),
    }
}
pub struct Locate<'a> {pub args:&'a [Expr],pub in_list:Option<&'a Expr>}
pub fn locate(expr:&Expr)->Result<Option<Locate<'_>>,&'static str> {
    let (call,in_list)=match &expr.kind {
        ExprKind::Binary{op,lhs,rhs} if op=="in" => (lhs.as_ref(),Some(rhs.as_ref())),
        _=>(expr,None),
    };
    let ExprKind::Call{callee,args}=&call.kind else{return Ok(None);};
    if !matches!(&callee.kind,ExprKind::Ident(name) if name=="locate") {return Ok(None);}
    if (in_list.is_some() && args.len()>1)
        || matches!(args.first().map(|e|&e.kind),Some(ExprKind::Binary{op,..}) if op=="in") {
        return Err("locate warning context requires exact primary primitive origins");
    }
    Ok(Some(Locate{args,in_list}))
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn constructor_views_do_not_absorb_outer_follows_or_copy_primary_nodes() {
        let expr=crate::parse_expression("new /datum/item(1).field").expr.unwrap();
        let ExprKind::Member{object,..}=&expr.kind else{panic!("outer follow missing");};
        assert!(constructor(&expr).unwrap().is_none());
        let Constructor::Static{path,args}=constructor(object).unwrap().unwrap() else{panic!("static form missing");};
        assert_eq!(path,"/datum/item");assert_eq!(args.len(),1);
        let ExprKind::Unary{value,..}=&object.kind else{unreachable!();};
        let ExprKind::Call{args:issued,..}=&value.kind else{unreachable!();};
        assert!(std::ptr::eq(&args[0],&issued[0]));
    }
    #[test]
    fn locate_view_preserves_clause_and_parenthesized_membership_boundary() {
        let direct=crate::parse_expression("locate(1) in list(2)").expr.unwrap();
        assert!(locate(&direct).unwrap().unwrap().in_list.is_some());
        let grouped=crate::parse_expression("(locate(1)) in list(2)").expr.unwrap();
        assert!(locate(&grouped).unwrap().is_none());
    }
}
