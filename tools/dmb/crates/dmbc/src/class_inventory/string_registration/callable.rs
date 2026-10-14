//! Authored first-root candidate name/literal chronology from one issued body.
use super::*;
use dm_syntax::{ForControl, ForInitializer, StatementKind};

pub(super) fn registrations(
    frontend: &ColdFrontend,
    input: &dm_tree::frontend::IssuedBodyInput<'_>,
    parsed: &dm_tree::frontend::ParsedBody<'_>,
    names: &HashSet<SymbolId>,
) -> Result<Vec<SymbolId>, String> {
    frontend
        .validate_parsed_body(parsed, input.occurrence())
        .map_err(|error| error.message)?;
    let item = parsed.item();
    let member = frontend
        .snapshot
        .tree
        .member(input.occurrence().member)
        .ok_or("first root signature member absent")?;
    let metadata = member
        .metadata
        .procedure
        .as_ref()
        .ok_or("first root signature absent")?;
    let parameters = crate::argument_sources::ParameterDiagnosticSource::from_current(
        frontend,
        item,
        metadata,
        frontend.snapshot.tree.symbols(),
    )
    .ok_or("first root signature differs from current captured source")?;
    let mut events = Vec::new();
    for (ordinal, parameter) in metadata.signature.parameters.iter().enumerate() {
        if names.contains(&parameter.name) {
            events.push((parameters.declaration_at(ordinal)?.start, parameter.name));
        }
    }
    let mut visitor = LocalNames {
        names,
        events: &mut events,
    };
    match parsed.statement_body() {
        Some(body) => {
            dm_syntax::visit_statements(&body.parsed().statements, &mut visitor);
        }
        None => {
            // Compatibility/lossless callers still use the shared statement
            // grammar for this one issued body. No Item/body buffer is cloned.
            let body = dm_syntax::parse_proc_body(item);
            dm_syntax::visit_statements(&body.statements, &mut visitor);
        }
    }
    events.extend(candidate_literals_at(
        input.source(),
        names,
        input.occurrence().expanded_span.start,
    )?);
    // Stable source-order merge preserves paired loop bindings and nested
    // literal leaves at one token offset, without evaluating/folding branches.
    events.sort_by_key(|(at, _)| *at);
    let mut seen = HashSet::new();
    Ok(events
        .into_iter()
        .filter_map(|(_, id)| seen.insert(id).then_some(id))
        .collect())
}

struct LocalNames<'a> {
    names: &'a HashSet<SymbolId>,
    events: &'a mut Vec<(usize, SymbolId)>,
}
impl LocalNames<'_> {
    fn declaration(&mut self, declaration: &str, at: usize) {
        if let Some(name) = dm_syntax::local_name(declaration) {
            let id = SymbolId::of(name);
            if self.names.contains(&id) {
                self.events.push((at, id));
            }
        }
    }
}
impl dm_syntax::TypedVisitor for LocalNames<'_> {
    fn statement(
        &mut self,
        statement: &dm_syntax::Statement,
        _: &[dm_syntax::NodeStep],
    ) -> dm_syntax::VisitDecision {
        let at = statement.header_span.start;
        match &statement.kind {
            StatementKind::Var { declaration, .. } => self.declaration(declaration, at),
            StatementKind::For { control, .. } => match control {
                ForControl::All { declaration } => self.declaration(declaration, at),
                ForControl::Each { binding, .. } | ForControl::Range { binding, .. } => {
                    self.declaration(binding, at)
                }
                ForControl::Pair {
                    key_binding,
                    value_binding,
                    ..
                } => {
                    self.declaration(key_binding, at);
                    self.declaration(value_binding, at);
                }
                ForControl::CStyle { initializer, .. } => {
                    if let Some(ForInitializer::Declare { declaration, .. }) = initializer {
                        self.declaration(declaration, at);
                    }
                }
            },
            StatementKind::Try {
                catch_binding: Some(binding),
                catch_header_span,
                ..
            } => self.declaration(binding, catch_header_span.start),
            _ => {}
        }
        dm_syntax::VisitDecision::Descend
    }
}
