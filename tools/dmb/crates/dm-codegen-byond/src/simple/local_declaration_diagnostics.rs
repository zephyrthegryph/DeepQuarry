//! One declaration collision rule for typed and compatibility statement paths.
use super::*;
impl Compiler<'_> {
    pub(super) fn record_local_header(&mut self, slot: u32, span: dm_syntax::Span) {
        self.local_declarations.insert(
            slot,
            LowerSpan {
                start: span.start,
                end: span.end,
            },
        );
    }

    pub(super) fn check_local_declaration(
        &self,
        name: &str,
        statement: &str,
        span: LowerSpan,
    ) -> Result<(), LowerError> {
        let parameter = self.bindings.parameters.iter().any(|formal| formal == name);
        if !parameter && !self.local_slots.contains_key(name) {
            return Ok(());
        }
        let mut failure = error(statement, &format!("{name}: duplicate definition"));
        failure.kind = LowerErrorKind::SourceError;
        if let Some(previous) = self
            .local_slots
            .get(name)
            .and_then(|slot| self.local_declarations.get(slot))
        {
            failure.related.push(LowerRelated {
                span: *previous,
                message: format!("{name}: previous definition"),
            });
        } else if parameter {
            if let Some(provider) = self.debug {
                if let Some(previous) = provider
                    .parameter_declaration(name)
                    .map_err(|reason| error(statement, &reason))?
                {
                    failure.related.push(LowerRelated {
                        span: previous,
                        message: format!("{name}: previous definition"),
                    });
                }
            }
        }
        Err(failure.at(Some(span)))
    }
}
