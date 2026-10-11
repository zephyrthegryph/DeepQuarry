//! One request-borrowed current source admission, shared by all completion users.
use super::*;

pub(crate) struct PreparedBody<'frontend> {
    frontend: &'frontend ColdFrontend,
    input: dm_tree::frontend::IssuedBodyInput<'frontend>,
    source: SourceUnitIdentity,
}
#[cfg(test)]
#[path = "prepared_roster_tests.rs"]
mod tests;
impl<'frontend> PreparedBody<'frontend> {
    pub(super) fn issue(
        frontend: &'frontend ColdFrontend,
        body: &BodyOccurrence,
    ) -> Result<Self, String> {
        let input = frontend.body_input(body).map_err(|error| error.message)?;
        let source = source_identity::from_issued(frontend, &input)?;
        Ok(Self {
            frontend,
            input,
            source,
        })
    }
    pub(crate) fn body(&self) -> &BodyOccurrence {
        self.input.occurrence()
    }
    pub(crate) fn input(&self) -> &dm_tree::frontend::IssuedBodyInput<'frontend> {
        &self.input
    }
    pub(crate) fn source(&self) -> SourceUnitIdentity {
        self.source
    }
    pub(crate) fn authenticates(&self, frontend: &ColdFrontend) -> bool {
        std::ptr::eq(self.frontend, frontend)
    }
    pub(crate) fn authenticates_body(
        &self,
        frontend: &ColdFrontend,
        body: &BodyOccurrence,
    ) -> bool {
        self.authenticates(frontend)
            && (std::ptr::eq(self.body(), body)
                || frontend.validate_body_input(&self.input, body).is_ok())
    }
}
pub(crate) struct PreparedBodyRoster<'frontend> {
    frontend: &'frontend ColdFrontend,
    // Same ordinal as the issuer's callable roster. No second declaration index.
    rows: Vec<PreparedBody<'frontend>>,
    order: Vec<usize>,
}
impl<'frontend> PreparedBodyRoster<'frontend> {
    pub(crate) fn issue(
        frontend: &'frontend ColdFrontend,
    ) -> Result<Self, Vec<LoweringDiagnostic>> {
        let mut rows = Vec::with_capacity(frontend.bodies.len());
        let mut diagnostics = Vec::new();
        for body in frontend.bodies.iter() {
            match PreparedBody::issue(frontend, body) {
                Ok(row) => rows.push(row),
                Err(message) => diagnostics.push((
                    (
                        body.source.encounter_ordinal,
                        body.expanded_span.start,
                        body.declaration.0,
                    ),
                    LoweringDiagnostic {
                        related: Vec::new(),
                        kind: DiagnosticKind::Internal,
                        identity: None,
                        origin: body.source.clone(),
                        message,
                    },
                )),
            }
        }
        if !diagnostics.is_empty() {
            diagnostics.sort_by_key(|(order, _)| *order);
            return Err(diagnostics.into_iter().map(|(_, error)| error).collect());
        }
        let mut order: Vec<_> = (0..rows.len()).collect();
        order.sort_by_key(|index| {
            let body = rows[*index].body();
            (
                body.source.encounter_ordinal,
                body.expanded_span.start,
                body.declaration.0,
            )
        });
        Ok(Self {
            frontend,
            rows,
            order,
        })
    }
    pub(crate) fn authenticates(&self, frontend: &ColdFrontend) -> bool {
        std::ptr::eq(self.frontend, frontend)
    }
    pub(crate) fn ordered(&self) -> impl ExactSizeIterator<Item = &PreparedBody<'frontend>> {
        self.order.iter().map(|index| &self.rows[*index])
    }
    /// Explicit selections retain the original exact current-input check. Full
    /// production scheduling borrows these already issued rows directly.
    pub(super) fn selected(&self, body: &BodyOccurrence) -> Option<&PreparedBody<'frontend>> {
        let ordinal = self.frontend.callable_roster().ok()?.ordinal(body.member)?;
        let row = self.rows.get(ordinal)?;
        self.frontend.validate_body_input(row.input(), body).ok()?;
        Some(row)
    }
}
