//! Allocation-free admission over ORIGINAL local-ledger owners.
//! This sums exposed capacities (aliases may be conservatively counted twice).
//! Exact address-deduplicated heap census remains the host's existing visitor.
use crate::{Expr, ExprKind, LocalVariableLedger};
use std::mem::size_of;
fn vec_bytes<T>(v: &Vec<T>) -> usize {
    v.capacity().saturating_mul(size_of::<T>())
}
pub(crate) fn expression(e: &Expr, depth: usize) -> usize {
    // Do not create a resource walk's own unbounded recursive stack. Unknown
    // deeper capacity refuses admission rather than claiming missing bytes.
    if depth > 256 {
        return usize::MAX;
    }
    let child = |e: &Expr| expression(e, depth + 1);
    let boxed = |e: &Expr| size_of::<Expr>().saturating_add(child(e));
    match &e.kind {
        ExprKind::Ident(s) | ExprKind::TypePath(s) => s.capacity(),
        ExprKind::Literal(l) => {
            let shared = l
                .shared_storage()
                .map_or(0, |(_, n)| n.saturating_add(2 * size_of::<usize>()));
            let mut n = shared.saturating_add(l.raw_storage().capacity());
            match l.prepared_syntax_parts() {
                Some(Ok(Some(p))) => {
                    n=n.saturating_add(p.runtime_error_storage().map_or(0,String::capacity));
                    l.visit_pinned_fragment_storage(|_,_,capacity|{n=n.saturating_add(capacity);});
                    n = n
                        .saturating_add(vec_bytes(&p.template))
                        .saturating_add(vec_bytes(&p.expressions));
                    for e in &p.expressions {
                        n = n.saturating_add(child(e));
                    }
                }
                Some(Err(error)) => n = n.saturating_add(error.capacity()),
                _ => (),
            }
            n
        }
        ExprKind::Unary { op, value } => op.capacity().saturating_add(boxed(value)),
        ExprKind::Binary { op, lhs, rhs } => op
            .capacity()
            .saturating_add(boxed(lhs))
            .saturating_add(boxed(rhs)),
        ExprKind::Conditional {
            condition,
            then_value,
            else_value,
        } => boxed(condition)
            .saturating_add(boxed(then_value))
            .saturating_add(boxed(else_value)),
        ExprKind::Call { callee, args } => {
            let mut n = boxed(callee).saturating_add(vec_bytes(args));
            for a in args {
                n = n.saturating_add(child(a));
            }
            n
        }
        ExprKind::Member {
            object, selector, ..
        }
        | ExprKind::StaticMember { object, selector }
        | ExprKind::SafeMember {
            object, selector, ..
        } => selector.capacity().saturating_add(boxed(object)),
        ExprKind::TypeFilter { value, types } => {
            let mut n = boxed(value).saturating_add(vec_bytes(types));
            for s in types {
                n = n.saturating_add(s.capacity());
            }
            n
        }
        ExprKind::ObjectInitializer { object, fields } => {
            let mut n = boxed(object).saturating_add(vec_bytes(fields));
            for (name, e) in fields {
                n = n.saturating_add(name.capacity()).saturating_add(child(e));
            }
            n
        }
        ExprKind::Index { object, index } | ExprKind::SafeIndex { object, index } => {
            boxed(object).saturating_add(boxed(index))
        }
        ExprKind::Group(value) => boxed(value),
    }
}
impl LocalVariableLedger {
    /// Actual exposed current capacities plus conservative Arc-header charge.
    /// Does not parse lazy literal parts, clone nodes, allocate an index, or
    /// measure allocator RSS. A depth refusal returns MAX, never a lower bound.
    pub fn retained_admission(&self) -> usize {
        let mut n = self
            .storage()
            .capacity()
            .saturating_mul(size_of::<crate::LocalVariableSyntax>());
        for local in self.storage() {
            n = n.saturating_add(std::mem::size_of_val(local.type_components.as_ref()));
            if let Some(array) = &local.array_syntax {
                n = n
                    .saturating_add(std::mem::size_of_val(array.root.brackets.as_ref()))
                    .saturating_add(std::mem::size_of_val(array.root.dimension_slots.as_ref()))
                    .saturating_add(std::mem::size_of_val(array.root.dimensions.as_ref()));
                for e in array.root.dimensions.iter() {
                    n = n.saturating_add(expression(e, 0));
                }
            }
        }
        n
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn original_dimension_storage_counts_lazy_children_without_parsing_them() {
        let ast = crate::parse("/proc/p()\n    var/x[\"[missing()]\"]\n");
        let body = crate::parse_proc_body(&ast.items[0]);
        let root = &body.local_variables.entries().unwrap()[0]
            .array_syntax
            .as_ref()
            .unwrap()
            .root;
        let ExprKind::Literal(literal) = &root.dimensions[0].kind else {
            panic!("fixture literal")
        };
        assert!(literal.retained_parts().is_none());
        let before = body.local_variables.retained_admission();
        assert!(
            before
                >= std::mem::size_of_val(root.dimensions.as_ref())
                    + std::mem::size_of_val(root.brackets.as_ref())
                    + std::mem::size_of_val(root.dimension_slots.as_ref())
        );
        assert!(
            literal.retained_parts().is_none(),
            "resource observation cannot demand parsing"
        );
        let _ = literal.parts().unwrap();
        assert!(
            body.local_variables.retained_admission() > before,
            "actual new cached child allocations must be charged"
        );
    }
    #[test]
    fn spare_string_capacity_and_unbounded_depth_are_never_credited_as_free() {
        let mut text = String::with_capacity(8192);
        text.push('x');
        let e = Expr {
            kind: ExprKind::Ident(text),
            span: crate::Span::new(0, 1),
        };
        assert!(expression(&e, 0) >= 8192);
        assert_eq!(
            expression(&e, 257),
            usize::MAX,
            "unknown deeper storage must refuse admission"
        );
    }
}
