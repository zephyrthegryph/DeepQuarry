//! Value-proof equations from the already-issued native expression tree.
//! Selection, mutable-field eligibility and argument escape barriers belong to
//! the shared semantic host. This layer neither invents call identities from
//! names nor assumes an unresolved expression is a scalar.
use crate::value_equations::Equation;
use dm_syntax::{Expr, ExprKind, NodeStep, Statement, StatementKind, TypedVisitor, VisitDecision};
use std::collections::BTreeSet;

pub trait ValueHost<K> {
    type Error;
    fn checkpoint(&self)->Result<(),Self::Error>{Ok(())}
    fn admit_entries(&self,_:usize)->Result<(),Self::Error>{Ok(())}
    /// Locals/parameters and mutable fields resolve through the same native
    /// binding/receiver queries as compilation. Field proofs include all writes.
    fn read(&self, expression: &Expr) -> Result<Equation<K>, Self::Error>;
    /// The selected source definition and every runtime-reachable override;
    /// builtins require an identity proof, never just a familiar spelling.
    fn call(&self, expression: &Expr) -> Result<Equation<K>, Self::Error>;
}

#[derive(Debug, Eq, PartialEq)]
pub enum ProofError<E> {
    UnsupportedSyntax,
    Host(E),
}

fn constant<K>(admissible: bool) -> Equation<K> {
    Equation {
        admissible,
        requires: BTreeSet::new(),
    }
}
fn both<K: Ord>(mut left: Equation<K>, right: Equation<K>) -> Equation<K> {
    left.admissible &= right.admissible;
    left.requires.extend(right.requires);
    left
}

/// Mirrors the reference's expression proof rules. In particular, arithmetic
/// produces a value even if its operands do not; `&&`/`||` can return an operand
/// and require both operands. A ternary requires both values, not its condition.
pub fn expression<K: Ord, H: ValueHost<K>>(node: &Expr, host: &H) -> Result<Equation<K>, H::Error> {
    host.checkpoint()?;
    Ok(match &node.kind {
        ExprKind::Literal(_) | ExprKind::TypePath(_) => constant(true),
        ExprKind::Ident(name) if name == "." => constant(true),
        ExprKind::Ident(_)
        | ExprKind::Member { .. }
        | ExprKind::SafeMember { .. }
        | ExprKind::StaticMember { .. }
        | ExprKind::TypeFilter { .. }
        | ExprKind::ObjectInitializer { .. } => host.read(node)?,
        ExprKind::Unary { op, .. } => constant(!matches!(op.as_str(), "new" | "&" | "*")),
        ExprKind::Binary { op, lhs, rhs } => match op.as_str() {
            "&&" | "||" => {let left=expression(lhs,host)?;let right=expression(rhs,host)?;host.admit_entries(left.requires.len().saturating_add(right.requires.len()))?;both(left,right)},
            "=" | ":=" | "&&=" | "||=" => expression(rhs, host)?,
            _ => constant(true),
        },
        ExprKind::Conditional {
            then_value,
            else_value,
            ..
        } => {let left=expression(then_value,host)?;let right=expression(else_value,host)?;host.admit_entries(left.requires.len().saturating_add(right.requires.len()))?;both(left,right)},
        ExprKind::Call { .. } => host.call(node)?,
        ExprKind::Group(inner) => expression(inner, host)?,
        ExprKind::Index { .. } | ExprKind::SafeIndex { .. } => constant(false),
    })
}

/// Returns and result-slot writes supply one procedure equation without cloning
/// statements. The host still has to scan calls/writes even when an explicit
/// scalar return annotation later settles the procedure's own answer.
pub fn returns<K: Ord, H: ValueHost<K>>(
    body: &dm_tree::frontend::StatementBody,
    host: &H,
) -> Result<Equation<K>, ProofError<H::Error>> {
    if !body.syntax_complete() {
        return Err(ProofError::UnsupportedSyntax);
    }
    returns_in(body.view(), host)
}
// Private shared policy over the already-admitted logical statement view.
// Production authority remains the StatementBody check above.
fn returns_in<K: Ord, H: ValueHost<K>>(
    view: dm_syntax::StatementView<'_>,
    host: &H,
) -> Result<Equation<K>, ProofError<H::Error>> {
    struct Returns<'a, K, H: ValueHost<K>> {
        host: &'a H,
        proof: Equation<K>,
        error: Option<H::Error>,
    }
    impl<K: Ord, H: ValueHost<K>> Returns<'_, K, H> {
        fn add(&mut self, rhs: &Expr) -> VisitDecision {
            match expression(rhs, self.host) {
                Ok(proof) => {
                    self.proof.admissible &= proof.admissible;
                    self.proof.requires.extend(proof.requires);
                    VisitDecision::Descend
                }
                Err(error) => {
                    self.error = Some(error);
                    VisitDecision::Stop
                }
            }
        }
    }
    fn is_result(mut node: &Expr) -> bool {
        while let ExprKind::Group(inner) = &node.kind {
            node = inner;
        }
        matches!(&node.kind, ExprKind::Ident(name) if name == ".")
    }
    fn preserves_rhs(op: &str) -> bool {
        matches!(op, "=" | ":=" | "&&=" | "||=")
    }
    impl<K: Ord, H: ValueHost<K>> TypedVisitor for Returns<'_, K, H> {
        fn projected_expression(
            &mut self,
            view: dm_syntax::ProjectedExprView<'_>,
            path: &[dm_syntax::NodeStep],
        ) -> dm_syntax::VisitDecision {
            // Same result-place/RHS shape proof. Neither this helper nor the
            // ValueHost contract interprets Expr spans as current source text.
            self.expression(view.original(), path)
        }

        fn statement(&mut self, node: &Statement, _: &[NodeStep]) -> VisitDecision {
            match &node.kind {
                StatementKind::Return(Some(rhs)) => self.add(rhs),
                StatementKind::Assign { target, op, value }
                    if is_result(target) && preserves_rhs(op) =>
                {
                    self.add(value)
                }
                _ => VisitDecision::Descend,
            }
        }
        fn expression(&mut self, node: &Expr, _: &[NodeStep]) -> VisitDecision {
            if let ExprKind::Binary { op, lhs, rhs } = &node.kind {
                if is_result(lhs) && preserves_rhs(op) {
                    return self.add(rhs);
                }
            }
            VisitDecision::Descend
        }
    }
    let mut visitor = Returns {
        host,
        proof: constant(true),
        error: None,
    };
    crate::untyped_order::visit_value_policy(view, &mut visitor)
        .map_err(|_| ProofError::UnsupportedSyntax)?;
    if let Some(error) = visitor.error {
        Err(ProofError::Host(error))
    } else {
        Ok(visitor.proof)
    }
}

#[cfg(test)]
#[path = "value_expressions_tests.rs"]
mod tests;


#[cfg(test)]
mod projected_returns_tests {
    use super::*;
    use std::sync::{atomic::AtomicUsize, Arc};
    struct ScalarOnly;
    impl ValueHost<()> for ScalarOnly {
        type Error = &'static str;
        fn read(&self, _: &Expr) -> Result<Equation<()>, Self::Error> { Err("fixture has no host read") }
        fn call(&self, _: &Expr) -> Result<Equation<()>, Self::Error> { Err("fixture has no host call") }
    }
    struct Provider(dm_syntax::SettingExpression);
    impl dm_syntax::SettingSyntaxProvider for Provider {
        fn setting(&self, _: &dm_syntax::Item) -> Result<dm_syntax::SettingStatement, dm_syntax::Diagnostic> {
            Ok(dm_syntax::SettingStatement { attribute: "name".into(), relation: "=".into(), value: self.0.clone() })
        }
    }
    #[test]
    fn projected_setting_result_writes_have_exact_owned_return_equations_after_offset_change() {
        let counter = Arc::new(AtomicUsize::new(0));
        let checkpoint = || Ok(());
        let a = dm_syntax::SettingAdmission::new(&counter, 16 * 1024 * 1024, &checkpoint);
        for (rhs, expected) in [("(. = 1)", true), ("(. = new /datum)", false)] {
            let lexed = dm_syntax::lex_spans(rhs);
            let root = dm_syntax::prepare_setting_expression(rhs, &lexed.tokens, dm_syntax::Span::new(0, rhs.len()), &a).unwrap();
            let original_ptr = root.original_expression() as *const Expr;
            for prefix in ["", "// UTF8 source shift é\n\n"] {
                let source = format!("{prefix}/proc/p()\n    set name = {rhs}\n    return 1\n");
                let ast = dm_syntax::parse(&source);
                assert!(ast.diagnostics.is_empty());
                let owned = dm_syntax::parse_body_items(&ast.items[0].children);
                let current = root.clone().project_current(source.find(rhs).unwrap(), rhs.len()).unwrap();
                let projected = dm_syntax::parse_body_items_with_context_and_settings(
                    &ast.items[0].children, &source, &|_| None, &Provider(current), &a);
                assert!(owned.diagnostics.is_empty());
                assert!(projected.diagnostics.is_empty());
                let old = returns_in(dm_syntax::StatementView::from_parsed(&owned), &ScalarOnly).unwrap();
                let actual = returns_in(dm_syntax::StatementView::from_parsed(&projected), &ScalarOnly).unwrap();
                assert_eq!(old, actual);
                assert_eq!(actual.admissible, expected, "setting result write must not disappear from return proof");
                assert!(actual.requires.is_empty());
                let StatementKind::ProjectedSet { value, .. } = &projected.statements[0].kind else { panic!("projected") };
                assert!(root.same_root(value));
                assert_eq!(original_ptr, value.original_expression() as *const Expr);
            }
        }
    }
}
