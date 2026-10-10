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
    pub(crate) fn reference(&self) -> SymRef {
        self.descriptor.reference()
    }
    pub(crate) fn with_assignment_origin(&self, origin: u32) -> Self {
        Self {
            descriptor: self.descriptor.with_assignment_origin(origin),
            path: self.path.clone(),
        }
    }
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
            dm_syntax::for_each_expression_child(node, |index, child| {
                let Ok(index) = u32::try_from(index) else {
                    return;
                };
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
            dm_syntax::for_each_expression_child(expression, |candidate, child| {
                if candidate == *index as usize {
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
