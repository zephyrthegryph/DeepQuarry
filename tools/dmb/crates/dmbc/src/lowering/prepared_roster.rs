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
    pub(crate) fn body(&self) -> &'frontend BodyOccurrence {
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
    order: &'frontend [usize],
    // Issued once beside the validated current rows; completion and disk replay
    // borrow the same immutable symbolic namespace without a second body pass.
    bindings: &'frontend std::collections::BTreeSet<dm_ir::SymRef>,
}
impl<'frontend> PreparedBodyRoster<'frontend> {
    pub(crate) fn issue(
        frontend: &'frontend ColdFrontend,
    ) -> Result<Self, Vec<LoweringDiagnostic>> {
        let mut rows = Vec::with_capacity(frontend.bodies.len());
        let mut diagnostics = Vec::new();
        let callable = frontend.callable_roster().map_err(|message| {
            frontend
                .bodies
                .first()
                .map(|body| body.source.clone())
                .or_else(|| frontend.location(0))
                .map(|origin| LoweringDiagnostic {
                    related: Vec::new(),
                    kind: DiagnosticKind::Internal,
                    identity: None,
                    origin,
                    message,
                })
                .into_iter()
                .collect::<Vec<_>>()
        })?;
        let bindings = callable.source_bindings();
        for body in frontend.bodies.iter() {
            match PreparedBody::issue(frontend, body) {
                Ok(row) => {
                    rows.push(row);
                }
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
        let order = callable.source_order();
        Ok(Self {
            frontend,
            rows,
            order,
            bindings,
        })
    }
    pub(crate) fn authenticates(&self, frontend: &ColdFrontend) -> bool {
        std::ptr::eq(self.frontend, frontend)
    }
    pub(crate) fn len(&self) -> usize {
        self.rows.len()
    }
    pub(crate) fn at(&self, position: usize) -> &PreparedBody<'frontend> {
        &self.rows[self.order[position]]
    }
    pub(crate) fn ordered(&self) -> impl ExactSizeIterator<Item = &PreparedBody<'frontend>> {
        self.order.iter().map(|index| &self.rows[*index])
    }
    pub(crate) fn source_bindings(
        &self,
        frontend: &ColdFrontend,
    ) -> Option<&std::collections::BTreeSet<dm_ir::SymRef>> {
        self.authenticates(frontend).then_some(self.bindings)
    }
    /// Borrow only an actual current occurrence, never a copied public descriptor.
    pub(crate) fn current(&self, body: &BodyOccurrence) -> Option<&PreparedBody<'frontend>> {
        let ordinal = self.frontend.callable_roster().ok()?.ordinal(body.member)?;
        let row = self.rows.get(ordinal)?;
        std::ptr::eq(row.body(), body).then_some(row)
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
