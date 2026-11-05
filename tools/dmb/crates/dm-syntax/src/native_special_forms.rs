//! Borrowed views of constructor/locate forms ALREADY issued by primary syntax.
//! No source scan, expression parse, AST clone or alternate grammar.
use crate::{Expr, ExprKind};
pub enum Constructor<'a> {
    Implicit { args: &'a [Expr] },
    Static { path: &'a str, args: &'a [Expr] },
    Dynamic,
}
pub fn constructor(expr: &Expr) -> Result<Option<Constructor<'_>>, &'static str> {
    match &expr.kind {
        ExprKind::Call { callee, args } if matches!(&callee.kind,ExprKind::Ident(name) if name=="new") => {
            Ok(Some(Constructor::Implicit { args }))
        }
        ExprKind::Unary { op, value } if op == "new" => {
            let (target, args) = match &value.kind {
                ExprKind::Call { callee, args } => (callee.as_ref(), args.as_slice()),
                _ => (value.as_ref(), &[][..]),
            };
            match &target.kind {
                ExprKind::TypePath(path) => Ok(Some(Constructor::Static { path, args })),
                ExprKind::Ident(_) | ExprKind::Member { .. } => Ok(Some(Constructor::Dynamic)),
                _ => Err("constructor prefab modifications/target context is not issued"),
            }
        }
        _ => Ok(None),
    }
}
pub struct Locate<'a> {
    pub args: &'a [Expr],
    pub in_list: Option<&'a Expr>,
    pub at: crate::Span,
}
pub fn locate(expr: &Expr) -> Result<Option<Locate<'_>>, &'static str> {
    let (call, in_list) = match &expr.kind {
        ExprKind::Binary { op, lhs, rhs } if op == "in" => (lhs.as_ref(), Some(rhs.as_ref())),
        _ => (expr, None),
    };
    let ExprKind::Call { callee, args } = &call.kind else {
        return Ok(None);
    };
    if !matches!(&callee.kind,ExprKind::Ident(name) if name=="locate") {
        return Ok(None);
    }
    if (in_list.is_some() && args.len() > 1)
        || matches!(args.first().map(|e|&e.kind),Some(ExprKind::Binary{op,..}) if op=="in")
    {
        return Err("locate warning context requires exact primary primitive origins");
    }
    Ok(Some(Locate {
        args,
        in_list,
        at: callee.span,
    }))
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn constructor_views_do_not_absorb_outer_follows_or_copy_primary_nodes() {
        let expr = crate::parse_expression("new /datum/item(1).field")
            .expr
            .unwrap();
        let ExprKind::Member { object, .. } = &expr.kind else {
            panic!("outer follow missing");
        };
        assert!(constructor(&expr).unwrap().is_none());
        let Constructor::Static { path, args } = constructor(object).unwrap().unwrap() else {
            panic!("static form missing");
        };
        assert_eq!(path, "/datum/item");
        assert_eq!(args.len(), 1);
        let ExprKind::Unary { value, .. } = &object.kind else {
            unreachable!();
        };
        let ExprKind::Call { args: issued, .. } = &value.kind else {
            unreachable!();
        };
        assert!(std::ptr::eq(&args[0], &issued[0]));
    }
    #[test]
    fn locate_view_preserves_clause_and_parenthesized_membership_boundary() {
        let direct = crate::parse_expression("locate(1) in list(2)")
            .expr
            .unwrap();
        assert!(locate(&direct).unwrap().unwrap().in_list.is_some());
        let grouped = crate::parse_expression("(locate(1)) in list(2)")
            .expr
            .unwrap();
        assert!(locate(&grouped).unwrap().is_none());
    }
}

/// Borrowed input primitive from the ORIGINAL primary expression nodes.
/// This is not a parser, source scan, cloned expression or type inference table.
pub struct Input<'a> {
    pub args: &'a [Expr],
    pub types: &'a [String],
    pub in_list: Option<&'a Expr>,
    pub at: crate::Span,
}
pub fn input(expr: &Expr) -> Result<Option<Input<'_>>, &'static str> {
    let (value, in_list) = match &expr.kind {
        ExprKind::Binary { op, lhs, rhs } if op == "in" => (lhs.as_ref(), Some(rhs.as_ref())),
        _ => (expr, None),
    };
    let (value, types) = match &value.kind {
        ExprKind::TypeFilter { value, types } => (value.as_ref(), types.as_slice()),
        _ => (value, &[][..]),
    };
    let ExprKind::Call { callee, args } = &value.kind else {
        return Ok(None);
    };
    if !matches!(&callee.kind,ExprKind::Ident(name)if name=="input") {
        return Ok(None);
    }
    if types.iter().any(|t| {
        !matches!(
            t.as_str(),
            "null"
                | "text"
                | "message"
                | "num"
                | "mob"
                | "obj"
                | "turf"
                | "area"
                | "icon"
                | "sound"
                | "key"
                | "password"
                | "color"
                | "anything"
                | "file"
                | "command_text"
        )
    }) {
        return Err("input type filter lacks original fixed grammar contract");
    }
    Ok(Some(Input {
        args,
        types,
        in_list,
        at: callee.span,
    }))
}
#[cfg(test)]
mod input_tests {
    use super::*;
    #[test]
    fn input_view_borrows_actual_primary_argument_and_clause_nodes() {
        let p = crate::parse_expression("input(usr, call()) as null|mob in candidates");
        assert!(p.diagnostics.is_empty(), "{:?}", p.diagnostics);
        let e = p.expr.unwrap();
        let view = input(&e).unwrap().unwrap();
        assert_eq!(view.types, ["null", "mob"]);
        assert_eq!(view.at.start, 0);
        let ExprKind::Binary { lhs, rhs, .. } = &e.kind else {
            panic!("membership")
        };
        assert!(std::ptr::eq(view.in_list.unwrap(), rhs.as_ref()));
        let ExprKind::TypeFilter { value, .. } = &lhs.kind else {
            panic!("type")
        };
        let ExprKind::Call { args, .. } = &value.kind else {
            panic!("call")
        };
        assert!(std::ptr::eq(&view.args[1], &args[1]));
        let grouped = crate::parse_expression("(input(usr)) in candidates")
            .expr
            .unwrap();
        assert!(
            input(&grouped).unwrap().is_none(),
            "ordinary outer in is not an input clause"
        );
    }
}

/// Picks borrow the canonical call arguments. The parser places a semicolon
/// wrapper directly in the argument slot when it has issued a weight.
pub struct Pick<'a> {
    args: &'a [Expr],
    pub at: crate::Span,
}

pub struct PickChoice<'a> {
    pub weight: Option<&'a Expr>,
    pub value: &'a Expr,
}

impl<'a> Pick<'a> {
    pub fn choices(&self) -> impl Iterator<Item = PickChoice<'a>> + 'a {
        self.args.iter().map(|arg| match &arg.kind {
            ExprKind::Binary { op, lhs, rhs } if op == ";" => PickChoice {
                weight: Some(lhs.as_ref()),
                value: rhs.as_ref(),
            },
            _ => PickChoice { weight: None, value: arg },
        })
    }
}

pub fn pick(expr: &Expr) -> Option<Pick<'_>> {
    let ExprKind::Call { callee, args } = &expr.kind else {
        return None;
    };
    if !matches!(&callee.kind, ExprKind::Ident(name) if name == "pick") {
        return None;
    }
    Some(Pick { args, at: callee.span })
}

#[cfg(test)]
mod pick_tests {
    use super::*;

    #[test]
    fn pick_borrows_the_direct_weight_and_value_nodes_without_unwrapping_groups() {
        let parsed = crate::parse_expression("pick((plain), (weight); (choice), prob(2); 3)");
        assert!(parsed.diagnostics.is_empty(), "{:?}", parsed.diagnostics);
        let expression = parsed.expr.unwrap();
        let ExprKind::Call { args, .. } = &expression.kind else {
            panic!("pick must have canonical call arguments");
        };
        let form = pick(&expression).unwrap();
        let mut choices = form.choices();
        let plain = choices.next().unwrap();
        assert!(plain.weight.is_none());
        assert!(std::ptr::eq(plain.value, &args[0]));
        assert!(matches!(&plain.value.kind, ExprKind::Group(_)));
        for arg in &args[1..] {
            let ExprKind::Binary { lhs, rhs, .. } = &arg.kind else {
                panic!("weighted argument must have its primary wrapper");
            };
            let choice = choices.next().unwrap();
            assert!(std::ptr::eq(choice.weight.unwrap(), lhs.as_ref()));
            assert!(std::ptr::eq(choice.value, rhs.as_ref()));
        }
        assert!(choices.next().is_none());
    }

    #[test]
    fn pick_does_not_classify_member_calls_as_a_primitive() {
        let parsed = crate::parse_expression("receiver.pick(1)");
        assert!(parsed.diagnostics.is_empty(), "{:?}", parsed.diagnostics);
        assert!(pick(&parsed.expr.unwrap()).is_none());
    }
}

/// A parser-issued chained dispatch. The target list of `call` is a normal
/// argument list; `call_ext` names one or two expressions before its arguments.
pub struct ChainedDispatch<'a> {
    pub target: DispatchTarget<'a>,
    pub args: &'a [Expr],
    pub at: crate::Span,
}

pub enum DispatchTarget<'a> {
    Dynamic(&'a [Expr]),
    External {
        library: Option<&'a Expr>,
        function: &'a Expr,
    },
}

pub fn chained_dispatch(expr: &Expr) -> Result<Option<ChainedDispatch<'_>>, &'static str> {
    let ExprKind::Call { callee, args } = &expr.kind else {
        return Ok(None);
    };
    let crate::CallTarget::Dynamic { dispatcher, targets } = crate::call_target(callee) else {
        return Ok(None);
    };
    let ExprKind::Call { callee: primitive, .. } = &callee.kind else {
        return Err("chained dispatch lacks the primary primitive node");
    };
    if targets.iter().chain(args).any(|arg| {
        matches!(&arg.kind, ExprKind::Binary { op, .. } if op == ";")
    }) {
        return Err("weighted argument syntax is unsupported in chained dispatch");
    }
    let target = if dispatcher == "call" {
        DispatchTarget::Dynamic(targets)
    } else {
        if targets.iter().any(|arg| {
            arg.span.start == arg.span.end
                && matches!(&arg.kind, ExprKind::Literal(text) if text.as_str() == "null")
        }) {
            return Err("external dispatch target needs an authored expression");
        }
        let (library, function) = match targets {
            [function] => (None, function),
            [library, function] => (Some(library), function),
            _ => return Err("external dispatch requires one or two target expressions"),
        };
        DispatchTarget::External { library, function }
    };
    Ok(Some(ChainedDispatch { target, args, at: primitive.span }))
}

#[cfg(test)]
mod chained_dispatch_tests {
    use super::*;

    #[test]
    fn chained_dispatch_borrows_primary_target_and_argument_nodes() {
        for (source, external) in [
            ("call(first, second)(third)", false),
            ("call_ext(first, second)(third)", true),
        ] {
            let parsed = crate::parse_expression(source);
            assert!(parsed.diagnostics.is_empty(), "{:?}", parsed.diagnostics);
            let expression = parsed.expr.unwrap();
            let ExprKind::Call { callee, args } = &expression.kind else {
                panic!("outer call missing");
            };
            let ExprKind::Call { callee: primitive, args: targets } = &callee.kind else {
                panic!("inner call missing");
            };
            let form = chained_dispatch(&expression).unwrap().unwrap();
            assert_eq!(form.at, primitive.span);
            assert!(std::ptr::eq(form.args.as_ptr(), args.as_ptr()));
            match form.target {
                DispatchTarget::Dynamic(actual) if !external => {
                    assert!(std::ptr::eq(actual.as_ptr(), targets.as_ptr()));
                }
                DispatchTarget::External { library: Some(library), function } if external => {
                    assert!(std::ptr::eq(library, &targets[0]));
                    assert!(std::ptr::eq(function, &targets[1]));
                }
                _ => panic!("wrong original target role"),
            }
        }
    }

    #[test]
    fn chained_dispatch_distinguishes_absent_target_from_authored_null() {
        let explicit = crate::parse_expression("call_ext(null)(1)").expr.unwrap();
        assert!(matches!(
            chained_dispatch(&explicit).unwrap().unwrap().target,
            DispatchTarget::External { library: None, .. },
        ));
        let missing = crate::parse_expression("call_ext(,function)(1)").expr.unwrap();
        assert_eq!(
            chained_dispatch(&missing).err(),
            Some("external dispatch target needs an authored expression"),
        );
        for source in ["call(target)", "receiver.call(target)(1)"] {
            let expression = crate::parse_expression(source).expr.unwrap();
            assert!(chained_dispatch(&expression).unwrap().is_none());
        }
    }
}
