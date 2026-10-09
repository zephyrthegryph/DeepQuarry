//! Current bindings share immutable relative AST owners across revisions.
use super::*;

impl HeapCensus {
    pub(super) fn declaration_syntax(
        &mut self,
        owner: &str,
        syntax: &Arc<dm_tree::frontend::DeclarationSyntax>,
    ) {
        if !self.arc_object(owner, syntax) {
            return;
        }
        self.slice(owner, syntax.chunks(), true);
        self.slice(owner, syntax.root_prefix(), true);
        for chunk in syntax.chunks().iter() {
            self.relative_syntax(owner, chunk.shared_relative());
        }
    }
    pub(super) fn relative_syntax(
        &mut self,
        owner: &str,
        relative: &Arc<dm_tree::frontend::RelativeSyntax>,
    ) {
        if !self.arc_object(owner, relative) {
            return;
        }
        let roots = relative.relative_items();
        if !self.slice(owner, roots, true) {
            return;
        }
        // Nested children remain ordinary owned Vecs; no expanded roster or
        // shifted AST is allocated to traverse their exact owners.
        let mut pending: Vec<_> = roots.iter().collect();
        while let Some(item) = pending.pop() {
            self.string(owner, &item.header);
            if self.vec_payload(owner, &item.children) {
                pending.extend(item.children.iter());
            }
        }
    }
}
