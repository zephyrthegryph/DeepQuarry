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
        relative.visit_body_storage(|address, logical, capacity| {
            self.buffer(owner, address, logical, capacity);
        });
        if let Some(source) = relative.shared_source() {
            self.arc_text(owner, source);
        }
        if let Some(items) = relative.wide_relative_items() {
            self.slice(owner, items, true);
        }
        relative.visit_item_storage(|address, logical, capacity| {
            self.buffer(owner, address, logical, capacity);
        });
    }
}
