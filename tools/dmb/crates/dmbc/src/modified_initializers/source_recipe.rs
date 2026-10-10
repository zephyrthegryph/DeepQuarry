//! Resident recipes retain semantic evidence and relative coordinates, never old ASTs.
use super::descriptor_recipe::DescriptorRecipe;
use super::*;
use dm_syntax::Span;

#[derive(Clone, Copy, serde::Serialize, serde::Deserialize)]
enum RecipeLocation {
    Body,
    HeaderHelper { argument: u32 },
}

#[derive(Clone)]
pub(crate) struct SourceRecipe {
    descriptor: DescriptorRecipe,
    relative_span: Span,
    location: RecipeLocation,
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
            location: RecipeLocation::Body,
            relative_span: Span::new(
                span.start.checked_sub(body.start)?,
                span.end.checked_sub(body.start)?,
            ),
        })
    }
    pub(crate) fn helper_source_recipe(&self, argument: u32) -> Option<SourceRecipe> {
        if self.captured.origin != Some(0) {
            return None;
        }
        let span = self.captured.source_span?;
        if span.start > span.end {
            return None;
        }
        Some(SourceRecipe {
            descriptor: DescriptorRecipe::from_capture(self.reference, &self.captured)?,
            relative_span: span,
            location: RecipeLocation::HeaderHelper { argument },
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
        frontend: &dm_tree::frontend::ColdFrontend,
        resolver: &dyn Resolver,
        symbols: &SymbolTable,
        debug: &DebugOrigins,
    ) -> Option<PreparedSeed> {
        if let RecipeLocation::HeaderHelper { argument } = self.location {
            let (expression, origins) = crate::argument_sources::current_header_modifier(
                frontend,
                parsed,
                argument,
                self.relative_span,
                symbols,
            )?;
            let captured = self
                .descriptor
                .capture_current(&expression, resolver, symbols)?;
            return prepare_seed(self.descriptor.reference(), &captured, &origins).ok();
        }
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

/// Wire evidence is not a current descriptor. Only reissue may produce a seed.
#[derive(serde::Serialize, serde::Deserialize)]
pub(crate) struct RecipeWire<'a> {
    reference: SymRef,
    #[serde(borrow)]
    canonical: std::borrow::Cow<'a, [u8]>,
    runtime_type: SymbolId,
    lexical_owner: SymbolId,
    resource_context: Option<u128>,
    origin: Option<u32>,
    start: usize,
    end: usize,
    location: RecipeLocation,
}
impl SourceRecipe {
    pub(crate) fn disk_evidence(&self) -> RecipeWire<'_> {
        let (reference, canonical, runtime_type, lexical_owner, resource_context, origin) =
            self.descriptor.evidence();
        RecipeWire {
            reference,
            canonical: std::borrow::Cow::Borrowed(canonical),
            runtime_type,
            lexical_owner,
            resource_context,
            origin,
            start: self.relative_span.start,
            end: self.relative_span.end,
            location: self.location,
        }
    }
}
impl RecipeWire<'_> {
    pub(crate) fn valid(&self) -> bool {
        matches!(self.reference, SymRef::Instance(_))
            && !self.canonical.is_empty()
            && self.origin.is_some()
            && self.start <= self.end
    }

    #[cfg(test)]
    pub(crate) fn corrupt_canonical(&mut self) {
        self.canonical = std::borrow::Cow::Borrowed(b"not issued descriptor bytes");
    }

    pub(crate) fn resident_recipe(&self) -> Option<SourceRecipe> {
        if !self.valid() {
            return None;
        }
        Some(SourceRecipe {
            descriptor: DescriptorRecipe::from_evidence(
                self.reference,
                Arc::from(self.canonical.as_ref()),
                self.runtime_type,
                self.lexical_owner,
                self.resource_context,
                self.origin,
            )?,
            relative_span: Span::new(self.start, self.end),
            location: self.location,
        })
    }
    pub(crate) fn reference(&self) -> SymRef {
        self.reference
    }
    pub(crate) fn runtime_type(&self) -> SymbolId {
        self.runtime_type
    }
    pub(crate) fn reissue(
        &self,
        parsed: &dm_tree::frontend::ParsedBody<'_>,
        frontend: &dm_tree::frontend::ColdFrontend,
        resolver: &dyn Resolver,
        symbols: &SymbolTable,
        debug: &DebugOrigins,
        context: Option<u128>,
        owner: SymbolId,
    ) -> Option<PreparedSeed> {
        if self.start > self.end
            || (matches!(self.location, RecipeLocation::Body)
                && self.end
                    > parsed
                        .occurrence()
                        .expanded_span
                        .end
                        .checked_sub(parsed.occurrence().expanded_span.start)?)
            || self.resource_context != context
            || self.lexical_owner != owner
            || match self.location {
                RecipeLocation::Body => self
                    .origin
                    .is_none_or(|i| i as usize >= debug.entries.len()),
                RecipeLocation::HeaderHelper { .. } => self.origin != Some(0),
            }
        {
            return None;
        }
        let descriptor = DescriptorRecipe::from_evidence(
            self.reference,
            Arc::from(self.canonical.as_ref()),
            self.runtime_type,
            self.lexical_owner,
            self.resource_context,
            self.origin,
        )?;
        SourceRecipe {
            descriptor,
            relative_span: Span::new(self.start, self.end),
            location: self.location,
        }
        .reissue(parsed, frontend, resolver, symbols, debug)
    }
}
