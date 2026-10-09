//! Resident recipes retain semantic evidence and relative coordinates, never old ASTs.
use super::*;
use dm_syntax::{ExprKind, Span};

#[derive(Clone)]
pub(crate) struct SourceRecipe {
    reference: SymRef,
    canonical: Arc<[u8]>,
    runtime_type: SymbolId,
    lexical_owner: SymbolId,
    resource_context: Option<u128>,
    relative_span: Span,
    origin: u32,
}
impl PreparedSeed {
    pub(crate) fn source_recipe(&self, body: Span) -> Option<SourceRecipe> {
        let span = self.captured.source_span?;
        if span.start < body.start || span.end > body.end || span.start > span.end {
            return None;
        }
        let origin = self.captured.origin?;
        if self
            .captured
            .field_origins
            .iter()
            .any(|field| *field != Some(origin))
        {
            return None;
        }
        Some(SourceRecipe {
            reference: self.reference,
            canonical: self.captured.descriptor.canonical_bytes().into(),
            runtime_type: self.captured.descriptor.runtime_type(),
            lexical_owner: self.captured.descriptor.lexical_owner(),
            resource_context: self.captured.descriptor.resource_context(),
            relative_span: Span::new(
                span.start.checked_sub(body.start)?,
                span.end.checked_sub(body.start)?,
            ),
            origin,
        })
    }
}
impl SourceRecipe {
    pub(crate) fn retained_census(&self, census: &mut crate::heap_census::HeapCensus) {
        census.slice("session_symbolic.modified_canonical", &self.canonical, true);
    }
    pub(crate) fn reissue(
        &self,
        parsed: &dm_tree::frontend::ParsedBody<'_>,
        resolver: &dyn Resolver,
        symbols: &SymbolTable,
        debug: &DebugOrigins,
    ) -> Option<PreparedSeed> {
        let body = parsed.occurrence().expanded_span;
        let span = Span::new(
            body.start.checked_add(self.relative_span.start)?,
            body.start.checked_add(self.relative_span.end)?,
        );
        if span.end > body.end {
            return None;
        }
        let expression = parsed.object_initializer_at(span).ok()??;
        let ExprKind::ObjectInitializer { object, fields } = &expression.kind else {
            return None;
        };
        let ExprKind::TypePath(path) = &object.kind else {
            return None;
        };
        let path = path.trim_end_matches('/');
        if SymbolId::of(path) != self.runtime_type {
            return None;
        }
        let owner = symbols.text(self.lexical_owner)?;
        let context = dm_codegen_byond::lower_resolver::ModifiedCaptureContext {
            resolver,
            symbols,
            resource_search_context: self.resource_context,
        };
        let captured = context
            .capture(path, owner, fields, Some(self.origin), span)
            .ok()?;
        if captured.descriptor.canonical_bytes() != self.canonical.as_ref()
            || SymRef::Instance(SymbolId::of(&captured.descriptor.alias())) != self.reference
        {
            return None;
        }
        prepare_seed(self.reference, &captured, debug).ok()
    }
}

#[cfg(test)]
#[path = "source_recipe_tests.rs"]
mod tests;
