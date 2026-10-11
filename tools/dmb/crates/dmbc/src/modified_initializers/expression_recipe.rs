//! Structural paths select current typed nodes, independent of source offsets.
use super::descriptor_recipe::DescriptorRecipe;
use super::*;
use dm_syntax::{Expr, ExprKind};

#[derive(Clone)]
pub(crate) struct ExpressionRecipe {
    descriptor: DescriptorRecipe,
    path: Vec<u32>,
}
/// Source-neutral evidence. Only reissue can construct a current descriptor.
#[derive(Clone, serde::Serialize, serde::Deserialize)]
pub(crate) struct ExpressionEvidence {
    reference: SymRef,
    canonical: Vec<u8>,
    runtime_type: SymbolId,
    lexical_owner: SymbolId,
    origin: u32,
    path: Vec<u32>,
}
#[cfg(test)]
#[path = "expression_recipe_tests.rs"]
mod tests;
impl ExpressionRecipe {
    pub(crate) fn disk_evidence(&self) -> Option<ExpressionEvidence> {
        let (reference, canonical, runtime_type, lexical_owner, context, origin) =
            self.descriptor.evidence();
        if context.is_some() || self.path.len() > 256 {
            return None;
        }
        Some(ExpressionEvidence {
            reference,
            canonical: canonical.to_vec(),
            runtime_type,
            lexical_owner,
            origin: origin?,
            path: self.path.clone(),
        })
    }
    pub(crate) fn accepts_current_path(&self, root: &Expr) -> bool {
        let Some(node) = self.current_node(root) else {
            return false;
        };
        let ExprKind::ObjectInitializer { object, .. } = &node.kind else {
            return false;
        };
        let ExprKind::TypePath(path) = &object.kind else {
            return false;
        };
        let (_, _, runtime_type, _, _, _) = self.descriptor.evidence();
        SymbolId::of(path.trim_end_matches('/')) == runtime_type
    }
    fn current_node<'a>(&self, root: &'a Expr) -> Option<&'a Expr> {
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
        Some(expression)
    }
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
        let expression = self.current_node(root)?;
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
impl ExpressionEvidence {
    pub(crate) fn reference(&self) -> SymRef {
        self.reference
    }
    pub(crate) fn origin(&self) -> u32 {
        self.origin
    }
    pub(crate) fn runtime_type(&self) -> SymbolId {
        self.runtime_type
    }
    pub(crate) fn resident_recipe(&self) -> Option<ExpressionRecipe> {
        if self.path.len() > 256 || self.canonical.is_empty() {
            return None;
        }
        let alias = format!(
            "modified-instance:{:032x}",
            xxhash_rust::xxh3::xxh3_128(&self.canonical)
        );
        if self.reference != SymRef::Instance(SymbolId::of(&alias)) {
            return None;
        }
        Some(ExpressionRecipe {
            descriptor: DescriptorRecipe::from_evidence(
                self.reference,
                Arc::from(self.canonical.as_slice()),
                self.runtime_type,
                self.lexical_owner,
                None,
                Some(self.origin),
            )?,
            path: self.path.clone(),
        })
    }
}
