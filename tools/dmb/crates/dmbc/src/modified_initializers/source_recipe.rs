//! Resident recipes retain semantic evidence and relative coordinates, never old ASTs.
use super::descriptor_recipe::DescriptorRecipe;
use super::*;
use dm_syntax::Span;

#[derive(Clone)]
pub(crate) struct SourceRecipe {
    descriptor: DescriptorRecipe,
    relative_span: Span,
}
impl PreparedSeed {
    pub(crate) fn source_recipe(&self, body: Span) -> Option<SourceRecipe> {
        // Procedure recipes bind through the current debug-origin certificate.
        // Assignment recipes may instead represent a build with debug disabled.
        self.captured.origin?;
        let span = self.captured.source_span?;
        if span.start < body.start || span.end > body.end || span.start > span.end {
            return None;
        }
        let descriptor = DescriptorRecipe::from_capture(self.reference, &self.captured)?;
        Some(SourceRecipe {
            descriptor,
            relative_span: Span::new(
                span.start.checked_sub(body.start)?,
                span.end.checked_sub(body.start)?,
            ),
        })
    }
}
impl SourceRecipe {
    pub(crate) fn retained_census(&self, census: &mut crate::heap_census::HeapCensus) {
        self.descriptor.retained_census(census);
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
        let captured = self
            .descriptor
            .capture_current(&expression, resolver, symbols)?;
        prepare_seed(self.descriptor.reference(), &captured, debug).ok()
    }
}

#[cfg(test)]
#[path = "source_recipe_tests.rs"]
mod tests;
