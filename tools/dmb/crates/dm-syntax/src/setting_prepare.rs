//! Retained setting-root preparation over ORIGINAL primary token inputs.
//! This low-level syntax/storage facade grants no source/frame/Db authority.
use crate::{
    Diagnostic, DiagnosticKind, Expr, ExprKind, SettingAdmission, SettingExpression,
    SettingRootLease, SharedSettingRetention, Span, SpanToken, TokenKind,
};
use std::{io, mem::size_of};
#[derive(Debug)]
pub enum SettingSyntaxFailure {
    Syntax(Diagnostic),
    Operational(io::Error),
}
fn fail(a: &SettingAdmission<'_>, kind: io::ErrorKind, message: &'static str) -> io::Error {
    a.record_operational_error(io::Error::new(kind, message));
    kind.into()
}
fn add(a: &SettingAdmission<'_>, x: usize, y: usize) -> io::Result<usize> {
    x.checked_add(y).ok_or_else(|| {
        fail(
            a,
            io::ErrorKind::OutOfMemory,
            "setting syntax storage sum overflow",
        )
    })
}
fn mul(a: &SettingAdmission<'_>, x: usize, y: usize) -> io::Result<usize> {
    x.checked_mul(y).ok_or_else(|| {
        fail(
            a,
            io::ErrorKind::OutOfMemory,
            "setting syntax storage product overflow",
        )
    })
}
/// A conservative runtime work reservation, NOT source grammar or RSS. Each
/// original '[' byte may begin an overlapping interpolation child; escaped/raw
/// brackets overcharge rather than inventing another interpolation parser.
fn parser_peak(source: &str, tokens: &[SpanToken], a: &SettingAdmission<'_>) -> io::Result<usize> {
    let mut token_work = tokens.len();
    let mut text_work = 0usize;
    let mut fragment_work=0usize;
    for token in tokens {
        a.checkpoint()?;
        let text = source.get(token.span.range()).ok_or_else(|| {
            fail(
                a,
                io::ErrorKind::InvalidInput,
                "original setting token source differs",
            )
        })?;
        text_work = add(a, text_work, text.len())?;
        if token.kind == TokenKind::String {
            let brackets = text.bytes().filter(|b| *b == b'[').count();
            let overlap = mul(a, text.len(), brackets)?;
            if brackets!=0{fragment_work=add(a,fragment_work,add(a,text.len(),overlap)?)?;}
            token_work = add(a, token_work, overlap)?;
            text_work = add(a, text_work, add(a, overlap, text.len())?)?;
        }
    }
    // Covers original owned-token input/output overlap, AST boxes/vector growth,
    // diagnostics, primary projection/splice positions and admitted worklists.
    let node = size_of::<crate::Token>() * 12
        + size_of::<Expr>() * 16
        + size_of::<String>() * 8
        + size_of::<Vec<crate::literal::LiteralFragment>>()
        + 4*size_of::<crate::SpanToken>()
        + size_of::<usize>() * 16
        + 128;
    add(
        a,
        add(a,add(a,mul(a,token_work,node)?,mul(a,text_work,64)?)?,mul(a,fragment_work,4*(size_of::<crate::literal::LiteralFragment>()+size_of::<crate::SpanToken>()))?)?,
        8192,
    )
}
/// Leaf data used by the pending demanded root and its failure cleanup.
/// No private allocation or secondary syntax beyond the reported String.
pub(crate) fn demanded_leaf_owned_bytes(expression: &Expr) -> Option<usize> {
    match &expression.kind {
        ExprKind::Ident(text) | ExprKind::TypePath(text) => Some(text.capacity()),
        ExprKind::Literal(text) if !text.owns_template_syntax() => {
            Some(if text.original_data().is_some() { 0 } else { text.raw_storage().capacity() })
        }
        _ => None,
    }
}

/// Small, already completed roots can settle their actual allocations before
/// the header owner reaches EOF. No template is prepared or inspected here.
/// Bound both work and stack without reserving a temporary heap worklist.
pub(crate) fn demanded_completed_owned_bytes(root: &Expr) -> Option<usize> {
    if let Some(leaf) = demanded_leaf_owned_bytes(root) {
        return Some(leaf);
    }
    const LIMIT: usize = 32;

    fn vec_capacity<T>(rows: &Vec<T>) -> Option<usize> {
        rows.capacity().checked_mul(size_of::<T>())
    }
    fn measure(root: &Expr, remaining: &mut usize) -> Option<usize> {
        *remaining = remaining.checked_sub(1)?;
        if let Some(leaf) = demanded_leaf_owned_bytes(root) {
            return Some(leaf);
        }
        let mut owned = 0usize;
        let mut charge = |bytes: usize| -> Option<()> {
            owned = owned.checked_add(bytes)?;
            Some(())
        };
        macro_rules! boxed {
            ($child:expr) => {{
                charge(size_of::<Expr>())?;
                charge(measure($child, remaining)?)?;
            }};
        }
        match &root.kind {
            ExprKind::Unary { op, value } => {
                charge(op.capacity())?;
                boxed!(value);
            }
            ExprKind::Binary { op, lhs, rhs } => {
                charge(op.capacity())?;
                boxed!(lhs);
                boxed!(rhs);
            }
            ExprKind::Conditional { condition, then_value, else_value } => {
                boxed!(condition);
                boxed!(then_value);
                boxed!(else_value);
            }
            ExprKind::Call { callee, args } => {
                boxed!(callee);
                charge(vec_capacity(args)?)?;
                for value in args {
                    charge(measure(value, remaining)?)?;
                }
            }
            ExprKind::Member { object, selector, .. }
            | ExprKind::StaticMember { object, selector }
            | ExprKind::SafeMember { object, selector, .. } => {
                boxed!(object);
                charge(selector.capacity())?;
            }
            ExprKind::TypeFilter { value, types } => {
                boxed!(value);
                if types.len() > LIMIT { return None; }
                charge(vec_capacity(types)?)?;
                for path in types {
                    charge(path.capacity())?;
                }
            }
            ExprKind::ObjectInitializer { object, fields } => {
                boxed!(object);
                charge(vec_capacity(fields)?)?;
                for (name, value) in fields {
                    charge(name.capacity())?;
                    charge(measure(value, remaining)?)?;
                }
            }
            ExprKind::Index { object, index } | ExprKind::SafeIndex { object, index } => {
                boxed!(object);
                boxed!(index);
            }
            ExprKind::Group(value) => boxed!(value),
            // An independently funded Original DATA literal is already a
            // leaf above. An ordinary template can own private syntax caches.
            ExprKind::Literal(_) => return None,
            ExprKind::Ident(_) | ExprKind::TypePath(_) => unreachable!("measured leaf"),
        }
        Some(owned)
    }

    let mut remaining = LIMIT;
    let retained = measure(root, &mut remaining)?;
    let nodes = LIMIT - remaining;
    // The later Unpublished failure guard can still use iterative destruction
    // before the final SettingExpression anchor exists. Keep the same
    // cleanup worklist envelope used by that final owner until it commits.
    let cleanup = nodes.checked_mul(4 * (size_of::<Expr>() + size_of::<SharedSettingRetention>()))?;
    retained.checked_add(cleanup)
}

struct Unpublished<'a, 'op> {
    expression: Option<Expr>,
    anchor: Option<SharedSettingRetention>,
    // Last: all original/temporary AST storage dies before scratch credit.
    _peak: SettingRootLease,
    _admission: &'a SettingAdmission<'op>,
}
impl Drop for Unpublished<'_, '_> {
    fn drop(&mut self) {
        if let Some(e) = self.expression.take() {
            if demanded_leaf_owned_bytes(&e).is_some() {
                drop(e);
            } else {
                crate::setting_drop::drop_expression(e, self.anchor.take());
            }
        }
    }
}
fn vec_bytes<T>(v: &Vec<T>) -> usize {
    v.capacity().saturating_mul(size_of::<T>())
}
pub(crate) struct Measured {
    pub(crate) bytes: usize,
    pub(crate) nodes: usize,
}
// ONE original-AST worklist prepares every genuinely issued literal's children
// and counts exposed retained capacities. It never parses a second root/model.
fn prepare_measure(root: &Expr, a: &SettingAdmission<'_>) -> io::Result<Measured> {
    prepare_measure_using(root,a,false)
}
pub(crate) fn prepare_body_measure(root:&Expr,a:&SettingAdmission<'_>)->io::Result<Measured>{prepare_measure_using(root,a,true)}
fn prepare_measure_using(root:&Expr,a:&SettingAdmission<'_>,body_fresh:bool)->io::Result<Measured>{
    let mut pending = crate::admitted_worklist::Worklist::new(a)?;
    pending.push(root)?;
    let mut bytes = 0usize;
    let mut nodes = 0usize;
    while let Some(e) = pending.pop() {
        a.checkpoint()?;
        nodes = add(a, nodes, 1)?;
        macro_rules! charge {
            ($n:expr) => {{
                bytes = add(a, bytes, $n)?;
            }};
        }
        macro_rules! boxed{($e:expr)=>{{charge!(size_of::<Expr>());pending.push($e)?;}}}
        match &e.kind {
            ExprKind::Ident(s) | ExprKind::TypePath(s) => charge!(s.capacity()),
            ExprKind::Literal(l) => {
                if body_fresh {l.require_fresh_body_owner(a)?;}
                l.prepare_parts_admitted(a)?;
                // Neutral typed DATA is already independently owned/funded;
                // sharing its immutable allocation does not create another raw
                // buffer or pin this root through the header owner.
                if l.original_data().is_none(){charge!(l.raw_storage().capacity());}
                if let Some((_, n)) = l.shared_storage() {
                    charge!(n);
                }
                match l.prepared_syntax_parts() {
                    Some(Ok(Some(p))) => {
                        charge!(p.runtime_error_storage().map_or(0,String::capacity));
                        charge!(vec_bytes(&p.template));
                        charge!(vec_bytes(&p.fragments));
                        for row in &p.fragments{charge!(vec_bytes(&row.tokens));}
                        charge!(vec_bytes(&p.expressions));
                        pending.extend(p.expressions.iter())?;
                    }
                    Some(Err(e)) => charge!(e.capacity()),
                    _ => (),
                }
            }
            ExprKind::Unary { op, value } => {
                charge!(op.capacity());
                boxed!(value);
            }
            ExprKind::Binary { op, lhs, rhs } => {
                charge!(op.capacity());
                boxed!(lhs);
                boxed!(rhs);
            }
            ExprKind::Conditional {
                condition,
                then_value,
                else_value,
            } => {
                boxed!(condition);
                boxed!(then_value);
                boxed!(else_value);
            }
            ExprKind::Call { callee, args } => {
                boxed!(callee);
                charge!(vec_bytes(args));
                pending.extend(args.iter())?;
            }
            ExprKind::Member {
                object, selector, ..
            }
            | ExprKind::StaticMember { object, selector }
            | ExprKind::SafeMember {
                object, selector, ..
            } => {
                charge!(selector.capacity());
                boxed!(object);
            }
            ExprKind::TypeFilter { value, types } => {
                boxed!(value);
                charge!(vec_bytes(types));
                for s in types {
                    charge!(s.capacity());
                }
            }
            ExprKind::ObjectInitializer { object, fields } => {
                boxed!(object);
                charge!(vec_bytes(fields));
                for (n, v) in fields {
                    charge!(n.capacity());
                    pending.push(v)?;
                }
            }
            ExprKind::Index { object, index } | ExprKind::SafeIndex { object, index } => {
                boxed!(object);
                boxed!(index);
            }
            ExprKind::Group(v) => boxed!(v),
        }
    }
    Ok(Measured { bytes, nodes })
}
pub(crate) fn attach(
    root: &Expr,
    anchor: &SharedSettingRetention,
    a: &SettingAdmission<'_>,
) -> io::Result<()> {
    let mut pending = crate::admitted_worklist::Worklist::new(a)?;
    pending.push(root)?;
    while let Some(e) = pending.pop() {
        a.checkpoint()?;
        match &e.kind {
            ExprKind::Literal(l) => {
                l.attach_setting_retention(anchor).map_err(|e| {
                    let kind = e.kind();
                    a.record_operational_error(e);
                    io::Error::from(kind)
                })?;
                if let Some(Ok(Some(p))) = l.prepared_syntax_parts() {
                    pending.extend(p.expressions.iter())?;
                }
            }
            ExprKind::Unary { value, .. }
            | ExprKind::Group(value)
            | ExprKind::TypeFilter { value, .. } => pending.push(value)?,
            ExprKind::Binary { lhs, rhs, .. } => {
                pending.push(lhs)?;
                pending.push(rhs)?;
            }
            ExprKind::Conditional {
                condition,
                then_value,
                else_value,
            } => {
                pending.push(condition)?;
                pending.push(then_value)?;
                pending.push(else_value)?;
            }
            ExprKind::Call { callee, args } => {
                pending.push(callee)?;
                pending.extend(args.iter())?;
            }
            ExprKind::Member { object, .. }
            | ExprKind::StaticMember { object, .. }
            | ExprKind::SafeMember { object, .. } => pending.push(object)?,
            ExprKind::ObjectInitializer { object, fields } => {
                pending.push(object)?;
                pending.extend(fields.iter().map(|(_, e)| e))?;
            }
            ExprKind::Index { object, index } | ExprKind::SafeIndex { object, index } => {
                pending.push(object)?;
                pending.push(index)?;
            }
            ExprKind::Ident(_) | ExprKind::TypePath(_) => (),
        }
    }
    Ok(())
}
/// Prepare ONE original RHS in stable ORIGINAL chunk coordinates, before publication.
/// Source owners must authenticate their exact current input before this call.
/// Operational errors remain in the SAME admission for its outer typed boundary
/// to extract; this low-level result carries only the stop status proxy.
pub fn prepare_setting_expression(
    source: &str,
    tokens: &[SpanToken],
    value_span: Span,
    a: &SettingAdmission<'_>,
) -> Result<SettingExpression, SettingSyntaxFailure> {prepare_setting_expression_with_original_literal_facts(source,tokens,value_span,a,None)}
/// SAME admitted primary parser with authentic scalar/static DATA loaned by the
/// current header owner. Numeric spans alone do not grant source authority.
pub fn prepare_setting_expression_with_original_literal_facts(
 source:&str,tokens:&[SpanToken],value_span:Span,a:&SettingAdmission<'_>,facts:Option<crate::OriginalLiteralFactsView<'_>>,
)->Result<SettingExpression,SettingSyntaxFailure>{
    let produce = || -> Result<SettingExpression, SettingSyntaxFailure> {
        a.checkpoint().map_err(SettingSyntaxFailure::Operational)?;
        for token in tokens {
            if token.span.start > token.span.end
                || token.span.start < value_span.start
                || token.span.end > value_span.end
            {
                return Err(SettingSyntaxFailure::Operational(fail(
                    a,
                    io::ErrorKind::InvalidInput,
                    "setting token escaped original RHS",
                )));
            }
        }
        if tokens
            .windows(2)
            .any(|pair| pair[0].span.end > pair[1].span.start)
        {
            return Err(SettingSyntaxFailure::Operational(fail(
                a,
                io::ErrorKind::InvalidInput,
                "original setting tokens overlap or reorder",
            )));
        }
        let peak = a
            .reserve(parser_peak(source, tokens, a).map_err(SettingSyntaxFailure::Operational)?)
            .map_err(SettingSyntaxFailure::Operational)?;
        let mut guard = Unpublished {
            expression: None,
            anchor: None,
            _peak: peak,
            _admission: a,
        };
        let mut parsed = crate::expression_parser::parse_expression_span_tokens_with_original_literals(
            source,tokens,0,a,facts,
        );
        guard.expression = parsed.expr.take();
        a.checkpoint().map_err(SettingSyntaxFailure::Operational)?;
        if let Some(error) = parsed.diagnostics.into_iter().next() {
            return Err(SettingSyntaxFailure::Syntax(error));
        }
        let expression = guard.expression.as_ref().ok_or_else(|| {
            SettingSyntaxFailure::Syntax(Diagnostic {
                span: value_span,
                kind: DiagnosticKind::Expression,
                message: "empty setting expression".into(),
            })
        })?;
        let measured = prepare_measure(expression, a).map_err(SettingSyntaxFailure::Operational)?;
        // Cleanup vectors may be allocated when the final alias dies. Reserve
        // their coordination headroom now, not after the remaining budget fills.
        let cleanup = mul(
            a,
            measured.nodes,
            4 * (size_of::<Expr>() + size_of::<SharedSettingRetention>()),
        )
        .map_err(SettingSyntaxFailure::Operational)?;
        let final_bytes = add(
            a,
            add(a, measured.bytes, cleanup).map_err(SettingSyntaxFailure::Operational)?,
            crate::setting_expression::root_storage_envelope(),
        )
        .map_err(SettingSyntaxFailure::Operational)?;
        let anchor = SharedSettingRetention::new(
            a.reserve(final_bytes)
                .map_err(SettingSyntaxFailure::Operational)?,
        );
        guard.anchor = Some(anchor.clone());
        attach(expression, &anchor, a).map_err(SettingSyntaxFailure::Operational)?;
        a.checkpoint().map_err(SettingSyntaxFailure::Operational)?;
        let expression = guard.expression.take().expect("prepared original root");
        Ok(SettingExpression::retained_with_anchor(expression, anchor))
    };
    produce()
}
#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::{
        atomic::{AtomicUsize, Ordering},
        Arc,
    };
    fn original(
        text: &str,
        a: &SettingAdmission<'_>,
    ) -> Result<SettingExpression, SettingSyntaxFailure> {
        let lexed = crate::lex_spans(text);
        assert!(lexed.diagnostics.is_empty());
        prepare_setting_expression(text, &lexed.tokens, Span::new(0, text.len()), a)
    }
    #[test]
    fn admitted_setting_preparation_preserves_original_syntax_and_literal_alias_credit() {
        let counter = Arc::new(AtomicUsize::new(0));
        let healthy = || Ok(());
        let a = SettingAdmission::with_stack_allowance(
            &counter,
            8 * 1024 * 1024,
            1024 * 1024,
            &healthy,
        );
        let text = "\"value [1 + 2]\"";
        let root = original(text, &a).unwrap();
        let compat = crate::parse_expression(text).expr.unwrap();
        assert_eq!(root.original_expression(), &compat);
        let ExprKind::Literal(literal) = &root.kind else {
            panic!("original literal root")
        };
        assert_eq!(literal.parts().unwrap().unwrap().expressions.len(), 1);
        let alias = literal.clone();
        let retained = counter.load(Ordering::Acquire);
        assert!(retained > 0);
        drop(root);
        assert_eq!(counter.load(Ordering::Acquire), retained);
        drop(alias);
        assert_eq!(counter.load(Ordering::Acquire), 0);
    }
    #[test]
    fn native_setting_stack_work_refusal_is_operational_uncached_and_retryable() {
        let counter = Arc::new(AtomicUsize::new(0));
        let healthy = || Ok(());
        let text = format!("{}1", "-".repeat(100));
        let low =
            SettingAdmission::with_stack_allowance(&counter, 8 * 1024 * 1024, 64 * 1024, &healthy);
        assert!(
            matches!(original(&text,&low),Err(SettingSyntaxFailure::Operational(ref e))
            if e.kind()==io::ErrorKind::OutOfMemory)
        );
        assert_eq!(
            low.take_operational_error().unwrap().kind(),
            io::ErrorKind::OutOfMemory
        );
        assert_eq!(
            counter.load(Ordering::Acquire),
            0,
            "partial primary root/scratch must be gone"
        );
        let retry = SettingAdmission::with_stack_allowance(
            &counter,
            8 * 1024 * 1024,
            4 * 1024 * 1024,
            &healthy,
        );
        let root = original(&text, &retry).unwrap();
        assert_eq!(
            root.original_expression(),
            &crate::parse_expression(&text).expr.unwrap()
        );
        drop(root);
        assert_eq!(counter.load(Ordering::Acquire), 0);
    }
    #[test]
    fn native_setting_flat_ast_cleanup_refusal_cannot_be_cached_as_syntax() {
        let counter = Arc::new(AtomicUsize::new(0));
        let healthy = || Ok(());
        let text = std::iter::repeat_n("1", 80).collect::<Vec<_>>().join("+");
        let a =
            SettingAdmission::with_stack_allowance(&counter, 8 * 1024 * 1024, 64 * 1024, &healthy);
        assert!(matches!(
            original(&text, &a),
            Err(SettingSyntaxFailure::Operational(_))
        ));
        assert_eq!(counter.load(Ordering::Acquire), 0);
        let retry = SettingAdmission::with_stack_allowance(
            &counter,
            8 * 1024 * 1024,
            4 * 1024 * 1024,
            &healthy,
        );
        let root = original(&text, &retry).unwrap();
        drop(root);
        assert_eq!(counter.load(Ordering::Acquire), 0);
    }
}

/// Conservative parser/projection overlap for ONE already-issued literal.
/// Counts raw '[' even when escaped; this is resource refusal, never grammar.
pub(crate) fn literal_parser_peak(raw:&str,a:&SettingAdmission<'_>)->io::Result<usize>{
 let overlap=mul(a,raw.len(),raw.bytes().filter(|b|*b==b'[').count())?;
 let token_work=add(a,1,overlap)?;let text_work=add(a,mul(a,raw.len(),2)?,overlap)?;
 let node=size_of::<crate::Token>()*12+size_of::<Expr>()*16+size_of::<String>()*8+size_of::<usize>()*16+128;
 let fragments=if raw.as_bytes().contains(&b'['){add(a,raw.len(),overlap)?}else{0};let fragment_bytes=add(a,mul(a,fragments,4*(size_of::<crate::literal::LiteralFragment>()+size_of::<crate::SpanToken>()))?,size_of::<Vec<crate::literal::LiteralFragment>>())?;
 add(a,add(a,add(a,mul(a,token_work,node)?,mul(a,text_work,64)?)?,fragment_bytes)?,8192)
}

/// Move ONE genuine native demanded Pratt result into the existing sealed
/// SettingExpression owner. No parser is invoked, and no source grant follows.
/// The original demanded lease guards failure cleanup until final root commit.
pub fn retain_demanded_expression(demanded:crate::DemandedExpression,a:&SettingAdmission<'_>)->Result<SettingExpression,SettingSyntaxFailure>{
 let(mut parsed,tokens,peak)=demanded.into_parts();drop(tokens);
 let mut guard=Unpublished{expression:parsed.expr.take(),anchor:None,_peak:peak,_admission:a};
 check_demanded_retention(&guard,a)?;
 if let Some(error)=parsed.diagnostics.into_iter().next(){return Err(SettingSyntaxFailure::Syntax(error))}
 retain_demanded_root(&mut guard,a)
}

impl crate::CompletedDemandedExpression {
    /// Publish a source-authenticated completed root through the same owner
    /// used by ordinary demanded expression retention.
    pub fn retain(self, a: &SettingAdmission<'_>) -> Result<SettingExpression, SettingSyntaxFailure> {
        let (expression, tokens, peak) = self.into_parts();
        drop(tokens);
        let mut guard = Unpublished { expression: Some(expression), anchor: None, _peak: peak, _admission: a };
        check_demanded_retention(&guard, a)?;
        retain_demanded_root(&mut guard, a)
    }
}

fn check_demanded_retention(guard: &Unpublished<'_, '_>, a: &SettingAdmission<'_>) -> Result<(), SettingSyntaxFailure> {
    if !a.matches_lease_domain(&guard._peak) {
        return Err(SettingSyntaxFailure::Operational(fail(a,io::ErrorKind::InvalidInput,"demanded default root belongs to another actual native resource owner")));
    }
    a.checkpoint().map_err(SettingSyntaxFailure::Operational)
}

fn retain_demanded_root(guard: &mut Unpublished<'_, '_>, a: &SettingAdmission<'_>) -> Result<SettingExpression, SettingSyntaxFailure> {
 let expression=guard.expression.as_ref().ok_or_else(||SettingSyntaxFailure::Operational(fail(a,io::ErrorKind::InvalidData,"demanded default has no native root")))?;
 let measured=prepare_measure(expression,a).map_err(SettingSyntaxFailure::Operational)?;
 let cleanup=mul(a,measured.nodes,4*(size_of::<Expr>()+size_of::<SharedSettingRetention>())).map_err(SettingSyntaxFailure::Operational)?;
 let final_bytes=add(a,add(a,measured.bytes,cleanup).map_err(SettingSyntaxFailure::Operational)?,crate::setting_expression::root_storage_envelope()).map_err(SettingSyntaxFailure::Operational)?;
 let anchor=SharedSettingRetention::new(a.reserve(final_bytes).map_err(SettingSyntaxFailure::Operational)?);guard.anchor=Some(anchor.clone());attach(expression,&anchor,a).map_err(SettingSyntaxFailure::Operational)?;a.checkpoint().map_err(SettingSyntaxFailure::Operational)?;
 Ok(SettingExpression::retained_with_anchor(guard.expression.take().expect("checked demanded root"),anchor))
}
