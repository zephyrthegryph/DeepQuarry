//! Structural paths select current typed nodes, independent of source offsets.
use super::descriptor_recipe::DescriptorRecipe;
use super::*;
use dm_syntax::{Expr, ExprKind};

#[derive(Clone)]
pub(crate) struct ExpressionRecipe {
    descriptor: DescriptorRecipe,
    path: Vec<u32>,
}
#[cfg(test)]
#[path = "expression_recipe_tests.rs"]
mod tests;
impl ExpressionRecipe {
    pub(crate) fn from_capture(
        reference: SymRef,
        captured: &CapturedModifiedInstance,
        root: &Expr,
    ) -> Option<Self> {
        let descriptor = DescriptorRecipe::from_capture(reference, captured)?;
        let span = captured.source_span?;
        let mut matches = Vec::new();
        fn find(
            node: &Expr,
            span: dm_syntax::Span,
            path: &mut Vec<u32>,
            matches: &mut Vec<Vec<u32>>,
        ) {
            if node.span == span && matches!(&node.kind, ExprKind::ObjectInitializer { .. }) {
                matches.push(path.clone());
            }
            for_each_child(node, |index, child| {
                path.push(index);
                find(child, span, path, matches);
                path.pop();
            });
        }
        find(root, span, &mut Vec::new(), &mut matches);
        if matches.len() != 1 {
            return None;
        }
        Some(Self {
            descriptor,
            path: matches.pop()?,
        })
    }
    pub(crate) fn reissue(
        &self,
        root: &Expr,
        resolver: &dyn Resolver,
        symbols: &SymbolTable,
    ) -> Option<(SymRef, CapturedModifiedInstance)> {
        let mut expression = root;
        for index in &self.path {
            let mut selected = None;
            for_each_child(expression, |candidate, child| {
                if candidate == *index {
                    selected = Some(child);
                }
            });
            expression = selected?;
        }
        Some((
            self.descriptor.reference(),
            self.descriptor
                .capture_current(expression, resolver, symbols)?,
        ))
    }
    pub(crate) fn retained_parts(&self) -> (&Vec<u32>, &Arc<[u8]>) {
        (&self.path, self.descriptor.canonical())
    }
}
fn for_each_child<'a>(node: &'a Expr, mut visit: impl FnMut(u32, &'a Expr)) {
    match &node.kind {
        ExprKind::Ident(_) | ExprKind::Literal(_) | ExprKind::TypePath(_) => {}
        ExprKind::Unary { value, .. }
        | ExprKind::TypeFilter { value, .. }
        | ExprKind::Group(value) => visit(0, value),
        ExprKind::Member { object, .. }
        | ExprKind::StaticMember { object, .. }
        | ExprKind::SafeMember { object, .. } => visit(0, object),
        ExprKind::Binary { lhs, rhs, .. } => {
            visit(0, lhs);
            visit(1, rhs);
        }
        ExprKind::Index { object, index } | ExprKind::SafeIndex { object, index } => {
            visit(0, object);
            visit(1, index);
        }
        ExprKind::Conditional {
            condition,
            then_value,
            else_value,
        } => {
            visit(0, condition);
            visit(1, then_value);
            visit(2, else_value);
        }
        ExprKind::Call { callee, args } => {
            visit(0, callee);
            for (index, arg) in args.iter().enumerate() {
                if let Some(index) = u32::try_from(index).ok().and_then(|i| i.checked_add(1)) {
                    visit(index, arg);
                }
            }
        }
        ExprKind::ObjectInitializer { object, fields } => {
            visit(0, object);
            for (index, (_, value)) in fields.iter().enumerate() {
                if let Some(index) = u32::try_from(index).ok().and_then(|i| i.checked_add(1)) {
                    visit(index, value);
                }
            }
        }
    }
}
