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
    let native_literals = parsed
        .statement_body()
        .is_some_and(|body| body.syntax_complete() && native_literal_roots_complete(body));
    let mut visitor = LocalNames {
        names,
        events: &mut events,
        error: None,
        literals: native_literals,
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
    if let Some(error) = visitor.error {
        return Err(error);
    }
    // Where the primary syntax retains every authored literal root, body
    // literals were borrowed above, including interpolation children. Only the
    // signature remains lossless then (defaults are not body AST).
    let header_end = item
        .header_span
        .end
        .checked_sub(input.occurrence().expanded_span.start)
        .ok_or("first root header precedes its issued source")?;
    let header = if native_literals {
        input
            .source()
            .get(..header_end)
            .ok_or("first root header exceeds issued source")?
    } else {
        // Unsupported bodies and normalized declaration cohorts retain the
        // existing lossless registration authority over this issued source.
        // Registration observes authored constants, including expressions the
        // primary parser legitimately erases before executable lowering.
        input.source()
    };
    events.extend(candidate_literals_at(
        header,
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

/// Native executable syntax is not always a complete lexical registration log.
/// Declaration membership normalization may erase an effect-free trailing list;
/// array dimensions remain declaration text. C-style declaration initializers
/// have no separately retained header extent, so their cohort is conservative.
/// These cases use the existing issued-source token registration, not a second
/// statement/expression parser. All other complete bodies borrow native literals.
fn native_literal_roots_complete(body: &dm_tree::frontend::StatementBody) -> bool {
    struct Coverage(bool);
    impl dm_syntax::TypedVisitor for Coverage {
        fn expression(
            &mut self,
            _: &dm_syntax::Expr,
            _: &[dm_syntax::NodeStep],
        ) -> dm_syntax::VisitDecision {
            dm_syntax::VisitDecision::Skip
        }
        fn statement(
            &mut self,
            statement: &dm_syntax::Statement,
            _: &[dm_syntax::NodeStep],
        ) -> dm_syntax::VisitDecision {
            self.0 &= match &statement.kind {
                StatementKind::Var { declaration, value } => {
                    !declaration.contains('[')
                        && value
                            .as_ref()
                            .is_none_or(|value| value.span.end >= statement.header_span.end)
                }
                StatementKind::For { control, .. } => match control {
                    ForControl::CStyle {
                        initializer: Some(ForInitializer::Declare { .. }),
                        ..
                    } => false,
                    ForControl::All { declaration } => !declaration.contains('['),
                    ForControl::Each { binding, .. }
                    | ForControl::Range { binding, .. }
                    | ForControl::RangeImplicitArray { binding, .. } => !binding.contains('['),
                    ForControl::Pair {
                        key_binding,
                        value_binding,
                        ..
                    } => !key_binding.contains('[') && !value_binding.contains('['),
                    _ => true,
                },
                _ => true,
            };
            if self.0 {
                dm_syntax::VisitDecision::Descend
            } else {
                dm_syntax::VisitDecision::Stop
            }
        }
    }
    let mut coverage = Coverage(true);
    dm_syntax::visit_statements(&body.parsed().statements, &mut coverage);
    coverage.0
}

struct LocalNames<'a> {
    names: &'a HashSet<SymbolId>,
    events: &'a mut Vec<(usize, SymbolId)>,
    error: Option<String>,
    literals: bool,
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
    fn expression(
        &mut self,
        expression: &dm_syntax::Expr,
        _: &[dm_syntax::NodeStep],
    ) -> dm_syntax::VisitDecision {
        if !self.literals {
            return dm_syntax::VisitDecision::Skip;
        }
        if let dm_syntax::ExprKind::Literal(text) = &expression.kind {
            if let Err(error) =
                dm_codegen_byond::visit_native_constant_string_literals(text, |bytes| {
                    let id = SymbolId::of_bytes(bytes);
                    if self.names.contains(&id) {
                        self.events.push((expression.span.start, id));
                    }
                })
            {
                self.error = Some(error);
                return dm_syntax::VisitDecision::Stop;
            }
            // The native literal walker already handled all nested leaves once.
            return dm_syntax::VisitDecision::Skip;
        }
        dm_syntax::VisitDecision::Descend
    }

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
                ForControl::Each { binding, .. }
                | ForControl::Range { binding, .. }
                | ForControl::RangeImplicitArray { binding, .. } => self.declaration(binding, at),
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

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::Path;

    struct Source(&'static str);
    impl dm_preprocess::SourceProvider for Source {
        fn read(&self, _: &Path) -> Result<String, String> {
            Ok(self.0.into())
        }
    }

    fn registration(source: &'static str, native_complete: bool) -> Vec<SymbolId> {
        let frontend = dm_tree::frontend::build(
            Path::new("probe.dme"),
            &Source(source),
            &Default::default(),
            1,
        )
        .unwrap();
        let names = [SymbolId::of("candidate"), SymbolId::of("after")]
            .into_iter()
            .collect();
        let occurrence = &frontend.bodies[0];
        let input = frontend.body_input(occurrence).unwrap();
        let arena = dm_tree::frontend::BodyArena::new_typed(&frontend, |_| true);
        arena
            .with_parsed(occurrence, |parsed| {
                let body = parsed.statement_body().unwrap();
                assert!(body.syntax_complete());
                assert_eq!(native_literal_roots_complete(body), native_complete);
                let actual = registrations(&frontend, &input, parsed, &names).unwrap();
                let mut seen = HashSet::new();
                let old: Vec<_> = candidate_literals_at(
                    input.source(),
                    &names,
                    input.occurrence().expanded_span.start,
                )
                .unwrap()
                .into_iter()
                .filter_map(|(_, name)| seen.insert(name).then_some(name))
                .collect();
                assert_eq!(actual, old, "retain lossless authored literal chronology");
                actual
            })
            .unwrap()
    }

    #[test]
    fn erased_membership_literal_keeps_registration_order_without_duplicates() {
        let actual = registration(
            "/proc/first()\n    var/x = 1 in list(\"candidate\")\n    var/y = \"after\"\n    return \"candidate\"\n/datum/example\n    var/candidate\n    var/after\n",
            false,
        );
        assert_eq!(actual, [SymbolId::of("candidate"), SymbolId::of("after")]);
    }

    #[test]
    fn c_style_declaration_keeps_lossless_registration_chronology() {
        let actual = registration(
            "/proc/first()\n    for(var/x = \"candidate\"; x < 2; x++)\n        var/y = \"after\"\n    return \"candidate\"\n/datum/example\n    var/candidate\n    var/after\n",
            false,
        );
        assert_eq!(actual, [SymbolId::of("candidate"), SymbolId::of("after")]);
    }

    #[test]
    fn complete_literal_roots_keep_native_registration_path() {
        assert_eq!(registration(
            "/proc/first()\n    var/x = \"candidate\"\n    return \"after\"\n/datum/example\n    var/candidate\n    var/after\n",
            true,
        ), [SymbolId::of("candidate"), SymbolId::of("after")]);
    }
}
