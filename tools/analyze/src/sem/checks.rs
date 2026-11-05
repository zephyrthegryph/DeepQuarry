//! Per-proc structural checks on the AST: ACT_TRY pairing, context escape, boolean returns.
//!
//! These look at one proc body at a time (they need the proc's own statements and the names of
//! its act-typed locals, nothing from other files), so they run on a partial model of just the
//! files that mention an action or a context (see `lints/sem_handlers.rs`).

use std::collections::{BTreeMap, BTreeSet};

use dreammaker::ast::{AssignOp, BinaryOp, Block, Expression, Follow, Spanned, Statement, Term, UnaryOp};

use super::ast::{as_call, as_ident, calls_in, stmt_blocks, stmt_exprs, strip_parens, walk_block, walk_expr};

/// Calls that start a world action (the macro `ACT_TRY` must survive expansion as one of these).
pub use crate::sem_handlers_partial_recipe::DEFAULT_TRY_CALLS;
/// Calls that end one.
pub const CLOSE_CALLS: &[&str] = &["act_done", "act_cancel"];

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Found {
    pub rule: &'static str,
    pub line: u32,
    pub msg: String,
}

// ---- ACT_TRY pairing ----------------------------------------------------------------------------

/// "Every ACT_TRY has act_done or act_cancel on every path of the same proc." A returned
/// `null` (refused or taken over) and the ACT_PASS sentinel carry no act to close, so a branch
/// that tests the result for null or `ACT_PASS` is clean.
pub fn act_try_pairing(code:&Block,try_calls:&[&str],out:&mut Vec<Found>){match crate::sem_handlers_pair_policy::collect_using(&OldPairSyntax{try_calls},code.as_ref(),&mut crate::key_policy_control::Compatibility){Ok(rows)=>out.extend(rows.into_iter().map(|row|Found{rule:"act_try_unpaired",line:row.line,msg:row.msg})),Err(never)=>match never{}}}
struct OldPairSyntax<'a>{try_calls:&'a[&'a str]}
impl crate::sem_handlers_pair_policy::Syntax<crate::key_policy_control::Compatibility> for OldPairSyntax<'_>{
 type Statement=Spanned<Statement>;type Expression=Expression;
 fn seen_try(&self,block:&[Self::Statement],_:&mut crate::key_policy_control::Compatibility)->Result<bool,std::convert::Infallible>{let mut seen=false;walk_block(block,&mut|e,_|if matches!(as_call(e),Some((name,_))if self.try_calls.contains(&name)){seen=true});Ok(seen)}
 fn line(&self,statement:&Self::Statement,_:&mut crate::key_policy_control::Compatibility)->Result<u32,std::convert::Infallible>{Ok(statement.location.line)}
 fn step<'a>(&'a self,statement:&'a Self::Statement,_:&mut crate::key_policy_control::Compatibility)->Result<crate::sem_handlers_pair_policy::Step<'a,Self::Statement,Self::Expression>,std::convert::Infallible>{use crate::sem_handlers_pair_policy::{Step,Var};Ok(match &statement.elem{
  Statement::Return(e)=>Step::Return(e.as_ref()),Statement::Throw(_)|Statement::Crash(_)=>Step::Terminate,
  Statement::If{arms,else_arm}=>Step::Conditional{arms:arms.iter().map(|(condition,body)|(&condition.elem,body.as_ref())).collect(),otherwise:else_arm.as_deref()},
  Statement::Expr(Expression::AssignOp{op,lhs,rhs})=>Step::Assign{lhs,rhs,plain:*op==AssignOp::Assign},Statement::Expr(e)=>Step::Simple(e),
  Statement::Var(var)=>Step::Variables{values:vec![Var{name:&var.name,value:var.value.as_ref()}],grouped:false},Statement::Vars(vars)=>Step::Variables{values:vars.iter().map(|var|Var{name:var.name.as_str(),value:var.value.as_ref()}).collect(),grouped:true},
  other=>Step::Other{expressions:stmt_exprs(other),blocks:stmt_blocks(other).into_iter().map(|body|body.as_ref()).collect(),exhaustive:matches!(other,Statement::Switch{default:Some(_),..})},
 })}
 fn is_try(&self,e:&Expression,_:&mut crate::key_policy_control::Compatibility)->Result<bool,std::convert::Infallible>{Ok(matches!(as_call(strip_parens(e)),Some((name,_))if self.try_calls.contains(&name)))}
 fn bare_name<'a>(&self,e:&'a Expression)->Option<&'a str>{as_ident(strip_parens(e))}
 fn closes(&self,e:&Expression,pending:&mut crate::sem_handlers_pair_policy::Pending,_:&mut crate::key_policy_control::Compatibility)->Result<(),std::convert::Infallible>{calls_in(e,&mut|name,args|{if CLOSE_CALLS.contains(&name){if let Some(id)=args.first().and_then(|arg|as_ident(strip_parens(arg))){pending.close(id);}}});Ok(())}
 fn null_tested(&self,e:&Expression,_:&mut crate::key_policy_control::Compatibility)->Result<Vec<String>,std::convert::Infallible>{Ok(null_tested(e))}
 fn non_null_tested(&self,e:&Expression,_:&mut crate::key_policy_control::Compatibility)->Result<Vec<String>,std::convert::Infallible>{Ok(non_null_tested(e))}
}

/// Idents the condition proves null (or the ACT_PASS sentinel) when TRUE: `!X`, `isnull(X)`,
/// `X == null`, `X == (-1)`.
fn null_tested(c: &Expression) -> Vec<String> {
    let mut out = Vec::new();
    let c = strip_parens(c);
    match c {
        Expression::Base { term, follow } => {
            if follow.len() == 1 && matches!(follow[0].elem, Follow::Unary(UnaryOp::Not)) {
                if let Term::Ident(n) = &term.elem {
                    out.push(n.clone());
                }
                if let Term::Expr(inner) = &term.elem {
                    // !(X)
                    if let Some(id) = as_ident(strip_parens(inner)) {
                        out.push(id.to_string());
                    }
                }
            }
            if follow.is_empty() {
                if let Term::Call(n, args) = &term.elem {
                    if n.as_str() == "isnull" {
                        if let Some(id) = args.first().and_then(|a| as_ident(strip_parens(a))) {
                            out.push(id.to_string());
                        }
                    }
                }
                // ACT_REFUSED_BY(X) after expansion: an ACT_ATTEMPT refusal carries no act to close.
                if let Some(id) = refusal_tested(term) {
                    out.push(id);
                }
            }
        }
        Expression::BinaryOp { op: BinaryOp::Eq, lhs, rhs } => {
            for (a, b) in [(lhs, rhs), (rhs, lhs)] {
                if let Some(id) = as_ident(strip_parens(a)) {
                    if is_null_or_sentinel(b) {
                        out.push(id.to_string());
                    }
                }
            }
        }
        Expression::BinaryOp { op: BinaryOp::Or, lhs, rhs } => {
            out.extend(null_tested(lhs));
            out.extend(null_tested(rhs));
        }
        _ => {}
    }
    out
}

/// `istype(X, /datum/act_refusal)` (the expansion of ACT_REFUSED_BY(X)): X.
fn refusal_tested(term: &Spanned<Term>) -> Option<String> {
    if let Term::Call(n, args) = &term.elem {
        if n.as_str() == "istype" && args.len() == 2 {
            let path = format!("{:?}", args[1]);
            if path.contains("act_refusal") {
                return as_ident(strip_parens(&args[0])).map(|s| s.to_string());
            }
        }
    }
    None
}

/// Idents the condition proves non-null when TRUE (`if(X)`, `X != null`, `!ACT_REFUSED_BY(X)`), so the else path has them null.
fn non_null_tested(c: &Expression) -> Vec<String> {
    let mut out = Vec::new();
    let c = strip_parens(c);
    if let Expression::Base { term, follow } = c {
        if follow.len() == 1 && matches!(follow[0].elem, Follow::Unary(UnaryOp::Not)) {
            let inner = match &term.elem {
                Term::Expr(e) => match strip_parens(e) {
                    Expression::Base { term: t, follow: f } if f.is_empty() => refusal_tested(t),
                    _ => None,
                },
                _ => refusal_tested(term),
            };
            if let Some(id) = inner {
                out.push(id);
            }
        }
    }
    match c {
        Expression::Base { term, follow } if follow.is_empty() => {
            if let Term::Ident(n) = &term.elem {
                out.push(n.clone());
            }
        }
        Expression::BinaryOp { op: BinaryOp::NotEq, lhs, rhs } => {
            for (a, b) in [(lhs, rhs), (rhs, lhs)] {
                if let Some(id) = as_ident(strip_parens(a)) {
                    if is_null_or_sentinel(b) {
                        out.push(id.to_string());
                    }
                }
            }
        }
        _ => {}
    }
    out
}

fn is_null_or_sentinel(e: &Expression) -> bool {
    let e = strip_parens(e);
    if let Expression::Base { term, follow } = e {
        match (&term.elem, follow.len()) {
            (Term::Null, 0) => return true,
            // (-1): the ACT_PASS sentinel after expansion.
            (Term::Int(i), 0) if *i < 0 => return true,
            (Term::Int(1), 1) if matches!(follow[0].elem, Follow::Unary(UnaryOp::Neg)) => return true,
            _ => {}
        }
    }
    false
}

// ---- context escape -----------------------------------------------------------------------------

/// "A pooled datum/act may not be stored in a var or passed in with =; use A.snapshot()."
/// `acts` are the proc's act-typed idents (params and locals).
pub fn context_escape(code: &Block, acts: &BTreeSet<String>, locals: &BTreeSet<String>, out: &mut Vec<Found>) {
    if acts.is_empty() {
        return;
    }
    let is_act = |e: &Expression| -> Option<String> {
        let id = as_ident(strip_parens(e))?;
        acts.contains(id).then(|| id.to_string())
    };
    let mut named_args: Vec<*const Expression> = Vec::new();
    walk_block(code, &mut |e, line| {
        match e {
            Expression::AssignOp { lhs, rhs, .. } => {
                // A named call argument (`with = A`) is reported by its call, not as a store.
                if named_args.contains(&(e as *const Expression)) {
                    return;
                }
                if let Some(a) = is_act(rhs) {
                    // Storing into a plain local is an alias for the trigger; anything else outlives it.
                    let local = as_ident(strip_parens(lhs)).map(|n| locals.contains(n)).unwrap_or(false);
                    if !local {
                        out.push(Found { rule: "context_escape", line, msg: format!("`{}` is a pooled context and is stored where it can outlive the trigger; use {}.snapshot()", a, a) });
                    }
                }
            }
            Expression::Base { term, follow } => {
                let mut note_named = |args: &[Expression]| {
                    for a in args {
                        if matches!(a, Expression::AssignOp { op: AssignOp::Assign, .. }) {
                            named_args.push(a as *const Expression);
                        }
                    }
                };
                match &term.elem {
                    Term::Call(_, args) | Term::NewPrefab { args: Some(args), .. } | Term::NewImplicit { args: Some(args) } => note_named(args),
                    _ => {}
                }
                for fo in follow.iter() {
                    if let Follow::Call(_, _, args) = &fo.elem {
                        note_named(args);
                    }
                }
                fn check_args(args: &[Expression], what: &str, line: u32, is_act: &dyn Fn(&Expression) -> Option<String>, out: &mut Vec<Found>) {
                    for a in args {
                        // A named argument `with = A`.
                        if let Expression::AssignOp { op: AssignOp::Assign, rhs, .. } = a {
                            if let Some(n) = is_act(rhs) {
                                out.push(Found { rule: "context_escape", line, msg: format!("`{}` is passed in with = to {}; use {}.snapshot()", n, what, n) });
                            }
                        }
                    }
                }
                match &term.elem {
                    Term::Call(n, args) => check_args(args, n.as_str(), line, &is_act, out),
                    Term::List(args) => {
                        for a in args.iter() {
                            if let Some(n) = is_act(a) {
                                out.push(Found { rule: "context_escape", line, msg: format!("`{}` is put in a list; use {}.snapshot()", n, n) });
                            }
                        }
                    }
                    Term::NewPrefab { args: Some(args), .. } | Term::NewImplicit { args: Some(args) } => check_args(args, "new", line, &is_act, out),
                    _ => {}
                }
                for fo in follow.iter() {
                    if let Follow::Call(_, n, args) = &fo.elem {
                        check_args(args, n.as_str(), line, &is_act, out);
                        if matches!(n.as_str(), "Add" | "Insert") {
                            for a in args.iter() {
                                if let Some(x) = is_act(a) {
                                    out.push(Found { rule: "context_escape", line, msg: format!("`{}` is added to a list; use {}.snapshot()", x, x) });
                                }
                            }
                        }
                    }
                }
            }
            _ => {}
        }
    });
}

// ---- requirement and condition returns ------------------------------------------------------------

/// A condition or transitional req_bool callback answers TRUE or FALSE. A string, a type or a non-boolean number
/// would read as TRUE and silently allow the op, so a definite non-boolean return is an error.
pub fn boolean_returns(code: &Block, out: &mut Vec<Found>) {
    fn visit(b: &Block, out: &mut Vec<Found>) {
        for st in b.iter() {
            if let Statement::Return(e) = &st.elem {
                let line = st.location.line;
                match e {
                    None => out.push(Found { rule: "requirement_return", line, msg: "a bare `return` answers null; a condition or req_bool callback must answer TRUE or FALSE".to_string() }),
                    Some(e) => {
                        if let Some(why) = non_boolean(e) {
                            out.push(Found { rule: "requirement_return", line, msg: format!("returns {}: a condition or req_bool callback answers TRUE or FALSE", why) });
                        }
                    }
                }
            }
            for nb in stmt_blocks(&st.elem) {
                visit(nb, out);
            }
        }
    }
    visit(code, out);
}

/// Final requirements return null (allow) or a refusal. Unknown callback return types are
/// checked by the engine; reject only expressions whose invalid shape is definite here.
pub fn requirement_returns(code: &Block, out: &mut Vec<Found>) {
    fn visit(block: &Block, out: &mut Vec<Found>) {
        for statement in block.iter() {
            if let Statement::Return(Some(expression)) = &statement.elem {
                if let Some(why) = non_reason(expression) {
                    out.push(Found {
                        rule: "requirement_return",
                        line: statement.location.line,
                        msg: format!("returns {}: req callbacks return null to allow, or text/a refusal datum to refuse; use req_bool only for transitional boolean callbacks", why),
                    });
                }
            }
            for nested in stmt_blocks(&statement.elem) {
                visit(nested, out);
            }
        }
    }
    visit(code, out);
}

fn non_reason(expression: &Expression) -> Option<&'static str> {
    match crate::sem_handlers_policy::invalid_return_using(expression,crate::sem_handlers_policy::ReturnProtocol::Requirement,&mut crate::key_policy_control::Compatibility){Ok(why)=>why,Err(never)=>match never{}}
}

fn non_boolean(e: &Expression) -> Option<&'static str> {
    match crate::sem_handlers_policy::invalid_return_using(e,crate::sem_handlers_policy::ReturnProtocol::Boolean,&mut crate::key_policy_control::Compatibility){Ok(why)=>why,Err(never)=>match never{}}
}

/// Locals and params of a proc that are act-typed, by declared type path.
pub fn act_idents(params: &[dreammaker::ast::Parameter], code: &Block, try_calls: &[&str]) -> (BTreeSet<String>, BTreeSet<String>) {
    let mut acts = BTreeSet::new();
    let mut locals = BTreeSet::new();
    let is_act_path = |p: &[String]| p.len() >= 2 && p[0] == "datum" && p[1] == "act";
    for p in params {
        locals.insert(p.name.clone());
        if is_act_path(&p.var_type.type_path) {
            acts.insert(p.name.clone());
        }
    }
    fn walk(b: &Block, acts: &mut BTreeSet<String>, locals: &mut BTreeSet<String>, try_calls: &[&str], is_act_path: &dyn Fn(&[String]) -> bool) {
        for st in b.iter() {
            let mut add = |name: &str, tp: &[String], v: &Option<Expression>| {
                locals.insert(name.to_string());
                if is_act_path(tp) {
                    acts.insert(name.to_string());
                } else if let Some(e) = v {
                    if matches!(as_call(strip_parens(e)), Some((n, _)) if try_calls.contains(&n)) {
                        acts.insert(name.to_string());
                    }
                }
            };
            match &st.elem {
                Statement::Var(vs) => add(&vs.name, &vs.var_type.type_path, &vs.value),
                Statement::Vars(l) => {
                    for vs in l {
                        add(&vs.name, &vs.var_type.type_path, &vs.value);
                    }
                }
                Statement::ForList(fl) => {
                    locals.insert(fl.name.as_str().to_string());
                    if let Some(vt) = &fl.var_type {
                        if is_act_path(&vt.type_path) {
                            acts.insert(fl.name.as_str().to_string());
                        }
                    }
                }
                _ => {}
            }
            for nb in stmt_blocks(&st.elem) {
                walk(nb, acts, locals, try_calls, is_act_path);
            }
        }
    }
    walk(code, &mut acts, &mut locals, try_calls, &is_act_path);
    (acts, locals)
}

#[allow(dead_code)]
fn unused(e: &Expression) {
    walk_expr(e, &mut |_| {});
}

/// Exact source positions of bare names used as named call arguments, not entity assignments.
/// The parser represents both as AssignOp; the enclosing call argument is the distinction.
pub fn named_argument_positions(sem: &super::Sem, file: &str) -> BTreeSet<(usize, usize)> {
    let mut positions = BTreeSet::new();
    for (_, owner, name) in sem.defs_in(file) {
        let Some(proc) = sem.proc_ref(owner, name) else { continue };
        let body = sem.proc_body(proc);
        if body.file != file { continue; }
        let Some(code) = body.code else { continue };
        walk_block(code, &mut |expression, _| {
            let Expression::Base { term, follow } = expression else { return };
            let mut collect = |args: &[Expression]| {
                for arg in args {
                    let Expression::AssignOp { op: AssignOp::Assign, lhs, .. } = arg else { continue };
                    // Dotted lhs arguments are actual assignments, not argument names.
                    let Expression::Base { term: lhs_term, follow: lhs_follow } = strip_parens(lhs) else { continue };
                    if !lhs_follow.is_empty() || as_ident(strip_parens(lhs)).is_none() { continue; }
                    if sem.rel(lhs_term.location) == file {
                        positions.insert((lhs_term.location.line as usize, lhs_term.location.column as usize));
                    }
                }
            };
            match &term.elem {
                Term::Call(_, args) | Term::List(args) | Term::NewPrefab { args: Some(args), .. } | Term::NewImplicit { args: Some(args) } => collect(args),
                _ => {}
            }
            for item in follow.iter() {
                if let Follow::Call(_, _, args) = &item.elem { collect(args); }
            }
        });
    }
    positions
}

/// Exact self slot-flags reads that are the old value of a registered tracked setter
/// mutation. No conditions or arbitrary callback arguments receive this treatment.
pub fn slot_flags_mutation_positions(sem: &super::Sem, decls: &super::decls::Decls, file: &str) -> BTreeSet<(usize, usize)> {
    struct Mask;
    impl crate::check_grep_semantic_policy::MaskView<Expression> for Mask{fn mask<'a>(&self,e:&'a Expression)->crate::check_grep_semantic_policy::Mask<'a,Expression>{use crate::check_grep_semantic_policy::Mask as View;match strip_parens(e){Expression::BinaryOp{op:BinaryOp::BitAnd|BinaryOp::BitOr|BinaryOp::BitXor|BinaryOp::LShift|BinaryOp::RShift,lhs,rhs}=>View::Both(lhs,rhs),Expression::Base{term,follow}=>{if !follow.iter().all(|f|matches!(&f.elem,Follow::Unary(UnaryOp::BitNot|UnaryOp::Neg))){return View::Other}match &term.elem{Term::Int(_)|Term::Float(_)=>View::Number,Term::Ident(name)=>View::Name(name.as_str()),Term::Expr(inner)=>View::Through(inner),_=>View::Other}},_=>View::Other}}}
    fn mask(e:&Expression)->bool{crate::check_grep_semantic_policy::mask(&Mask,e,&mut||Ok::<_,std::convert::Infallible>(())).unwrap_or_else(|never|match never{})}
    fn shadows(b: &Block) -> bool {
        b.iter().any(|s| match &s.elem {
            Statement::Var(v) if v.name.as_str() == "slot_flags" => true,
            Statement::Vars(v) if v.iter().any(|x| x.name.as_str() == "slot_flags") => true,
            Statement::ForList(v) if v.var_type.is_some() && v.name.as_str() == "slot_flags" => true,
            Statement::ForKeyValue(v) if v.var_type.is_some() && (v.key.as_str() == "slot_flags" || v.value.as_str() == "slot_flags") => true,
            _ => stmt_blocks(&s.elem).iter().any(|b| shadows(b)),
        })
    }
    let mut positions = BTreeSet::new();
    for (_, owner, name) in sem.defs_in(file) {
        if !decls.tracked.iter().any(|(ty, vars)| vars.contains("slot_flags") && sem.is_subtype(owner, ty)) { continue; }
        let Some(setter) = sem.proc_ref(owner, "set_slot_flags") else { continue; };
        if setter.is_builtin() { continue; }
        let Some(proc) = sem.proc_ref(owner, name) else { continue; };
        let body = sem.proc_body(proc);
        if body.file != file { continue; }
        let Some(code) = body.code else { continue; };
        let shadowed = body.params.iter().any(|p| p.name.as_str() == "slot_flags") || shadows(code);
        walk_block(code, &mut |expression, _| {
            let Expression::Base { term, follow } = expression else { return; };
            let args = match (&term.elem, follow.as_ref()) {
                (Term::Call(n, args), []) if n.as_str() == "set_slot_flags" => args,
                (Term::Ident(n), [f]) if n.as_str() == "src" => match &f.elem {
                    Follow::Call(_, n, args) if n.as_str() == "set_slot_flags" => args,
                    _ => return,
                },
                _ => return,
            };
            if args.len() != 1 { return; }
            let Expression::BinaryOp { op: BinaryOp::BitAnd, lhs, rhs } = strip_parens(&args[0]) else { return; };
            if !mask(rhs) { return; }
            let Expression::Base { term: lhs_term, follow: lhs_follow } = strip_parens(lhs) else { return; };
            let column = match (&lhs_term.elem, lhs_follow.as_ref()) {
                (Term::Ident(n), []) if n.as_str() == "slot_flags" && !shadowed => lhs_term.location.column as usize,
                (Term::Ident(n), [f]) if n.as_str() == "src" && matches!(&f.elem, Follow::Field(_, field) if field.as_str() == "slot_flags") => lhs_term.location.column as usize + 4,
                _ => return,
            };
            if sem.rel(lhs_term.location) == file {
                positions.insert((lhs_term.location.line as usize, column));
            }
        });
    }
    positions
}

// Prove direct fields whose declared receiver cannot be a client. An action's
// borrowed holder and a pending operation's owner are ordinary engine references,
// not the admin datum reached through client.holder. Unknown receivers stay debt.
pub fn act_holder_positions(sem: &super::Sem, file: &str, text: &str) -> BTreeSet<(usize, usize)> {
    fn declared(v: &dreammaker::ast::VarType) -> Option<String> {
        (!v.type_path.is_empty()).then(|| format!("/{}", v.type_path.join("/")))
    }
    fn collect(b: &Block, types: &mut BTreeMap<String, Option<String>>) {
        for s in b {
            let mut add = |name: &str, ty: Option<String>| {
                if types.contains_key(name) { types.insert(name.to_owned(), None); }
                else { types.insert(name.to_owned(), ty); }
            };
            match &s.elem {
                Statement::Var(v) => add(v.name.as_str(), declared(&v.var_type)),
                Statement::Vars(vs) => for v in vs { add(v.name.as_str(), declared(&v.var_type)); },
                Statement::ForList(v) => add(v.name.as_str(), v.var_type.as_ref().and_then(declared)),
                Statement::ForKeyValue(v) => { add(v.key.as_str(), None); add(v.value.as_str(), None); },
                _ => {}
            }
            for child in stmt_blocks(&s.elem) { collect(child, types); }
        }
    }
    let mut positions = BTreeSet::new();
    for (_, owner, name) in sem.defs_in(file) {
        let Some(proc) = sem.proc_ref(owner, name) else { continue; };
        let body = sem.proc_body(proc);
        if body.file != file { continue; }
        let Some(code) = body.code else { continue; };
        let mut types: BTreeMap<String, Option<String>> = body.params.iter().map(|p| (p.name.to_string(), declared(&p.var_type))).collect();
        collect(code, &mut types);
        walk_block(code, &mut |e, _| {
            let Expression::Base { term, follow } = e else { return; };
            let (Term::Ident(receiver), [field]) = (&term.elem, follow.as_ref()) else { return; };
            if !matches!(&field.elem, Follow::Field(_, n) if n.as_str() == "holder") { return; }
            let ty = if receiver.as_str() == "src" { Some(owner.as_str()) }
                else { types.get(receiver.as_str()).and_then(|ty| ty.as_deref()) };
            let Some(ty) = ty else { return; };
            // A broad ancestor of /client is not sufficient proof either: an actual
            // client may inhabit it. Require a real declared field on a disjoint type.
            if sem.ty(ty).is_none() || sem.is_subtype(ty, "/client") || sem.is_subtype("/client", ty) || sem.var_owner(ty, "holder").is_none() { return; }
            if sem.rel(term.location) != file { return; }
            let Some(line) = text.lines().nth(term.location.line as usize - 1) else { return; };
            let start = term.location.column as usize - 1;
            if let Some(column)=crate::check_grep_semantic_policy::holder_column(line,start,receiver.as_str()){positions.insert((term.location.line as usize,column));}
        });
    }
    positions
}
