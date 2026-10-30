//! Value-proof equations from the already-issued native expression tree.
//! Selection, mutable-field eligibility and argument escape barriers belong to
//! the shared semantic host. This layer neither invents call identities from
//! names nor assumes an unresolved expression is a scalar.
use crate::value_equations::Equation;
use dm_syntax::{Expr, ExprKind, NodeStep, Statement, StatementKind, TypedVisitor, VisitDecision};
use std::collections::BTreeSet;

pub trait ValueHost<K> {
    type Error;
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
            "&&" | "||" => both(expression(lhs, host)?, expression(rhs, host)?),
            "=" | ":=" | "&&=" | "||=" => expression(rhs, host)?,
            _ => constant(true),
        },
        ExprKind::Conditional {
            then_value,
            else_value,
            ..
        } => both(expression(then_value, host)?, expression(else_value, host)?),
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
    crate::untyped_order::visit_value_policy(body.view(), &mut visitor)
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
