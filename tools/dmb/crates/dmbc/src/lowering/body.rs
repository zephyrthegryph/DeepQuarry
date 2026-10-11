//! Consume one request-local parsed procedure through ordinary and helper lowering.
use super::*;
pub(super) struct LoweringCapture<'a, 'frontend> {
    pub startup: Option<&'a crate::startup::CapturedStartup<'frontend>>,
    pub capture: Option<&'a RefCell<MemoCapture>>,
    pub ready: Option<PreparedUnit>,
    pub capture_references: bool,
    pub current: Option<SourceUnitIdentity>,
}
pub(super) fn lower_one<R: Resolver, P: AbiPolicy>(
    frontend: &ColdFrontend,
    body: &BodyOccurrence,
    host: &R,
    policy: &P,
    startup: Option<&crate::startup::CapturedStartup>,
    bodies: &dm_tree::frontend::BodyArena<'_>,
    capture_references: bool,
    current: Option<SourceUnitIdentity>,
) -> Result<LoweredUnit, Vec<LoweringDiagnostic>> {
    lower_one_captured(
        frontend,
        body,
        host,
        policy,
        bodies,
        LoweringCapture {
            startup,
            capture: None,
            ready: None,
            capture_references,
            current,
        },
    )
}
pub(super) fn lower_one_captured<R: Resolver, P: AbiPolicy>(
    frontend: &ColdFrontend,
    body: &BodyOccurrence,
    host: &R,
    policy: &P,
    bodies: &dm_tree::frontend::BodyArena<'_>,
    captured: LoweringCapture<'_, '_>,
) -> Result<LoweredUnit, Vec<LoweringDiagnostic>> {
    let LoweringCapture {
        startup,
        capture,
        ready,
        capture_references,
        current,
    } = captured;
    let tree = &frontend.snapshot.tree;
    let error = |identity, message| {
        vec![LoweringDiagnostic {
            related: Vec::new(),
            kind: DiagnosticKind::Internal,
            identity,
            origin: body.source.clone(),
            message,
        }]
    };
    if let Some(captured) = startup {
        captured
            .validate_for(frontend)
            .map_err(|message| error(None, message))?;
    }
    let node = tree
        .member(body.member)
        .ok_or_else(|| error(None, "body member missing from immutable tree".into()))?;
    let source_identity = match current {
        Some(current) => current,
        None => source_unit_identity(frontend, body).map_err(|message| error(None, message))?,
    };
    let identity = source_identity.identity;
    let owner = identity.owner;
    let unsupported = |message| {
        vec![LoweringDiagnostic {
            related: Vec::new(),
            kind: DiagnosticKind::UnsupportedModel,
            identity: Some(identity),
            origin: body.source.clone(),
            message,
        }]
    };
    let metadata = node
        .metadata
        .procedure
        .as_ref()
        .ok_or_else(|| unsupported("procedure signature metadata unsupported".into()))?;
    let symbols = startup.map_or(tree.symbols(), |captured| captured.plan().symbols.as_ref());
    let parsed = bodies.take_parsed(body).map_err(|diagnostic| {
        vec![LoweringDiagnostic {
            related: Vec::new(),
            kind: diagnostic.kind,
            identity: Some(identity),
            origin: diagnostic.location.unwrap_or_else(|| body.source.clone()),
            message: diagnostic.message,
        }]
    })?;
    let parameter_diagnostics = crate::argument_sources::ParameterDiagnosticSource::from_current(
        frontend,
        parsed.item(),
        metadata,
        symbols,
    );
    let typed_attempted = parsed.statement_attempted();
    // The issued parser owner survives ABI hooks that return only a header.
    // It remains subject to the current startup/settings mask below.
    let issued_statements = parsed.shared_statement_body();
    // This receipt can only be issued from this arena's authenticated body.
    // Keep its shared owner before ABI preparation consumes the parsed wrapper.
    let static_receipt = parsed.stored_declaration_receipt();
    let (prepared, parsed, statements) = if let Some(ready) = ready {
        let mut header = parsed.into_item();
        header.children = Vec::new();
        (ready, header, None)
    } else {
        let context = AbiContext {
            identity,
            symbols,
            origin: &body.source,
            resolver: host,
        };
        policy
            .prepare_owned_captured(metadata, parsed, &context)
            .map_err(unsupported)?
    };
    let statements = statements.or(issued_statements);
    let parsed = &parsed;
    let procedure_identity = dm_ir::ProcedureIdentity {
        owner: identity.owner,
        name: identity.name,
        verb: identity.namespace == Namespace::Verb,
        occurrence: identity.occurrence,
    };
    // Mutation belongs to cold lowering, never the admitted immutable ABI owner.
    let mut inputs = Arc::unwrap_or_clone(prepared.inputs);
    if inputs
        .procedure_identity
        .is_some_and(|supplied| supplied != procedure_identity)
    {
        return Err(unsupported(
            "procedure ABI identity differs from current body".into(),
        ));
    }
    inputs.procedure_identity = Some(procedure_identity);
    let mut typed_removed = None;
    let mut typed_valid = false;
    let executable_mask = if let Some(statements) = statements.as_ref() {
        let fallback;
        let current = if let Some(receipt) = static_receipt.as_ref() {
            receipt.plan()
        } else {
            // Standalone compatibility callers may not have captured startup
            // facts through the arena. Preserve their existing capture path.
            fallback = if statements.may_contain_stored_declarations() {
                dm_tree::procedure_statics::capture_issued_statements(
                    procedure_identity,
                    statements,
                )
                .map_err(unsupported)?
            } else {
                dm_tree::procedure_statics::capture_declarations(procedure_identity, &[])
                    .map_err(unsupported)?
            };
            &fallback
        };
        if current.procedure != procedure_identity {
            return Err(unsupported(
                "procedure startup inventory differs from current body".into(),
            ));
        }
        if let Some(startup) = startup {
            let captured = startup
                .procedure(body.declaration)
                .ok_or_else(|| unsupported("procedure startup inventory missing".into()))?;
            if captured.procedure != current.procedure
                || captured.declarations != current.declarations
                || captured.origins != current.origins
            {
                return Err(unsupported(
                    "procedure startup inventory differs from current body".into(),
                ));
            }
        } else if !current.declarations.is_empty() {
            return Err(unsupported(
                "procedure statics require verified shared-slot/default/startup admission".into(),
            ));
        }
        let removed: std::collections::HashSet<_> = current
            .origins
            .iter()
            .map(|origin| (origin.header_span.start, origin.header_span.end))
            .collect();
        let mask = dm_syntax::StatementMask::from_predicate(
            &statements.parsed().statements,
            |statement| {
                dm_tree::settings::is_setting_header(&statement.raw_header)
                    || removed.contains(&(statement.header_span.start, statement.header_span.end))
            },
        );
        if let Some(diagnostic) = statements.parsed().diagnostics.iter().find(|diagnostic| {
            diagnostic.kind == dm_syntax::DiagnosticKind::InvalidDeclarationGroup
                && !mask.hides_diagnostic(diagnostic)
        }) {
            let origin = frontend
                .location(diagnostic.span.start)
                .unwrap_or_else(|| body.source.clone());
            return Err(vec![LoweringDiagnostic {
                related: vec![RelatedDiagnostic {
                    origin: origin.clone(),
                    message: "location of top-most unmatched {".into(),
                }],
                kind: DiagnosticKind::SourceError,
                identity: Some(identity),
                origin,
                message: diagnostic.message.clone(),
            }]);
        }
        if let Some(diagnostic) = statements.parsed().diagnostics.iter().find(|diagnostic| {
            diagnostic.kind == dm_syntax::DiagnosticKind::IncompleteExpression
                && !mask.hides_diagnostic(diagnostic)
        }) {
            // IncompleteExpression certifies exhaustion of the current parsed
            // statement expression. Its parser span may precede the operator;
            // bind the checked statement header end through the common cursor.
            struct HeaderEnd {
                diagnostic: dm_syntax::Span,
                end: Option<usize>,
            }
            impl dm_syntax::TypedVisitor for HeaderEnd {
                fn statement(
                    &mut self,
                    statement: &dm_syntax::Statement,
                    _: &[dm_syntax::NodeStep],
                ) -> dm_syntax::VisitDecision {
                    if statement.header_span.start <= self.diagnostic.start
                        && self.diagnostic.end <= statement.header_span.end
                    {
                        self.end = Some(statement.header_span.end);
                    }
                    dm_syntax::VisitDecision::Descend
                }
            }
            let mut cursor = HeaderEnd {
                diagnostic: diagnostic.span,
                end: None,
            };
            dm_syntax::visit_statements(&statements.parsed().statements, &mut cursor);
            let mut origin = frontend
                .location(diagnostic.span.start)
                .unwrap_or_else(|| body.source.clone());
            // Only the authenticated include-return oracle licenses replacing
            // this parser anchor. Direct-root recovery keeps its current span.
            if let Some(end) = cursor.end.filter(|_| {
                frontend
                    .plan
                    .occurrences
                    .get(origin.include_occurrence)
                    .is_some_and(|occurrence| occurrence.parent.is_some())
            }) {
                if let Ok(bound) = crate::debug_sources::diagnostic_origin(
                    frontend,
                    dm_codegen_byond::DiagnosticAnchor::LexerCursorAfterOffset(end),
                ) {
                    origin.semantic_path = bound.semantic_path;
                    origin.line = bound.line as usize;
                }
            }
            return Err(vec![LoweringDiagnostic {
                related: Vec::new(),
                kind: DiagnosticKind::SourceError,
                identity: Some(identity),
                origin,
                message: diagnostic.message.clone(),
            }]);
        }
        typed_valid = statements
            .parsed()
            .diagnostics
            .iter()
            .all(|diagnostic| mask.hides_diagnostic(diagnostic));
        typed_removed = Some(removed);
        Some(mask)
    } else {
        None
    };
    let executable_view = statements
        .as_ref()
        .zip(executable_mask.as_ref())
        .map(|(body, mask)| dm_syntax::StatementView::masked(&body.parsed().statements, mask));
    let typed_ready = typed_valid
        && executable_view.is_some_and(dm_codegen_byond::typed_statement_view_supported);

    let executable_body = if typed_ready {
        Vec::new()
    } else if let Some(removed) = &typed_removed {
        dm_tree::procedure_statics::filter_executable_items(prepared.executable_body, removed)
    } else if let Some(startup) = startup {
        let captured = startup
            .procedure(body.declaration)
            .ok_or_else(|| unsupported("procedure startup inventory missing".into()))?;
        if captured.procedure != procedure_identity {
            return Err(unsupported(
                "procedure startup inventory differs from current body".into(),
            ));
        }
        if captured.declarations.is_empty()
            && captured.origins.is_empty()
            && !dm_tree::procedure_statics::items_may_contain_stored_declarations(
                &prepared.executable_body,
            )
        {
            prepared.executable_body
        } else {
            let current = dm_tree::procedure_statics::capture_owned(
                procedure_identity,
                prepared.executable_body,
            )
            .map_err(unsupported)?;
            if captured.procedure != current.procedure
                || captured.declarations != current.declarations
                || captured.origins != current.origins
            {
                return Err(unsupported(
                    "procedure startup inventory differs from current body".into(),
                ));
            }
            current.executable_body
        }
    } else {
        if dm_tree::procedure_statics::items_may_contain_stored_declarations(
            &prepared.executable_body,
        ) {
            let static_plan = dm_tree::procedure_statics::capture_declarations(
                procedure_identity,
                &prepared.executable_body,
            )
            .map_err(unsupported)?;
            if !static_plan.declarations.is_empty() {
                return Err(unsupported(
                    "procedure statics require verified shared-slot/default/startup admission"
                        .into(),
                ));
            }
        }
        prepared.executable_body
    };
    let owner_text = symbols
        .text(owner)
        .ok_or_else(|| error(Some(identity), "owner spelling missing".into()))?;
    let name = symbols
        .text(node.name)
        .ok_or_else(|| error(Some(identity), "procedure spelling missing".into()))?;
    inputs.current_type_path = (owner_text != "/").then(|| owner_text.into());
    inputs.current_proc_path = Some(format!(
        "{}/{}/{}",
        owner_text.trim_end_matches('/'),
        if identity.namespace == Namespace::Verb {
            "verb"
        } else {
            "proc"
        },
        name
    ));
    let debug = MemoDebugProvider {
        original: FrontendDebugProvider::new(frontend, parsed.header_span.start),
        base: body.expanded_span.start,
        entry: parsed.header_span.start,
        capture,
        parameters: parameter_diagnostics,
    };
    let mut selected_references = None;
    let code = {
        let _profile = dm_profile::item("lowering.fresh_codegen");
        match executable_view {
            Some(view) if typed_ready && capture_references => {
                dm_codegen_byond::compile_statement_view_with_resolver_and_references_at(
                    view,
                    &inputs,
                    symbols,
                    host,
                    Some(&debug),
                    dm_syntax::Span {
                        start: body.expanded_span.start,
                        end: body.expanded_span.end,
                    },
                )
                .map(|(code, references)| {
                    selected_references = Some(Arc::new(references));
                    code
                })
            }
            Some(view) if typed_ready => dm_codegen_byond::compile_statement_view_with_resolver(
                view,
                &inputs,
                symbols,
                host,
                Some(&debug),
            ),
            _ if typed_attempted => dm_codegen_byond::compile_preparsed_lossless_with_resolver(
                &executable_body,
                &inputs,
                symbols,
                host,
                Some(&debug),
            ),
            _ => compile_simple_proc_with_resolver_and_debug(
                &executable_body,
                &inputs,
                symbols,
                host,
                Some(&debug),
            ),
        }
    };
    let code = super::grammar::append(code, statements.as_deref()).map_err(|mut errors| {
        for error in &mut errors {
            if let Some(anchor) = error.primary_anchor {
                error.primary_anchor = Some(super::error_anchor::parser_current(
                    anchor,
                    statements.as_deref(),
                    error.span,
                ));
            }
        }
        if let Some(capture) = capture {
            let relative = errors
                .iter()
                .map(|error| {
                    if error.kind == dm_codegen_byond::LowerErrorKind::Internal {
                        return None;
                    }
                    let mut error = error.clone();
                    if let Some(anchor) = error.primary_anchor {
                        error.primary_anchor = Some(super::error_anchor::relative(anchor, body)?);
                    }
                    if let Some(span) = &mut error.span {
                        span.start = span.start.checked_sub(body.expanded_span.start)?;
                        span.end = span.end.checked_sub(body.expanded_span.start)?;
                        if span.end > body.expanded_span.end - body.expanded_span.start {
                            return None;
                        }
                    }
                    for note in &mut error.related {
                        note.span.start = note.span.start.checked_sub(body.expanded_span.start)?;
                        note.span.end = note.span.end.checked_sub(body.expanded_span.start)?;
                        if note.span.start > note.span.end
                            || note.span.end > body.expanded_span.end - body.expanded_span.start
                        {
                            return None;
                        }
                    }
                    Some(error)
                })
                .collect::<Option<Vec<_>>>();
            capture.borrow_mut().errors = relative;
        }
        errors
            .into_iter()
            .map(|e| {
                let Some(related) = super::related::bind_current_related(
                    frontend,
                    body,
                    debug.parameters.as_ref(),
                    e.related,
                ) else {
                    return LoweringDiagnostic {
                        related: Vec::new(),
                        kind: DiagnosticKind::Internal,
                        identity: Some(identity),
                        origin: body.source.clone(),
                        message: "invalid secondary diagnostic source span".into(),
                    };
                };
                let origin = match e.primary_anchor {
                    Some(anchor) => {
                        match super::error_anchor::bind(frontend, body, anchor, false) {
                            Some(origin) => origin,
                            None => {
                                return LoweringDiagnostic {
                                    related: Vec::new(),
                                    kind: DiagnosticKind::Internal,
                                    identity: Some(identity),
                                    origin: body.source.clone(),
                                    message: "invalid primary diagnostic source anchor".into(),
                                }
                            }
                        }
                    }
                    None => e
                        .span
                        .and_then(|span| frontend.location(span.start))
                        .unwrap_or_else(|| body.source.clone()),
                };
                LoweringDiagnostic {
                    related,
                    kind: match e.kind {
                        dm_codegen_byond::LowerErrorKind::SourceError => {
                            DiagnosticKind::SourceError
                        }
                        dm_codegen_byond::LowerErrorKind::UnsupportedModel => {
                            DiagnosticKind::UnsupportedModel
                        }
                        dm_codegen_byond::LowerErrorKind::Internal => DiagnosticKind::Internal,
                    },
                    identity: Some(identity),
                    origin,
                    message: if e.kind == dm_codegen_byond::LowerErrorKind::SourceError
                        || e.statement.is_empty()
                    {
                        e.reason
                    } else {
                        format!("{}: {}", e.statement, e.reason)
                    },
                }
            })
            .collect::<Vec<_>>()
    })?;
    let source_helpers = match prepared.abi.as_ref() {
        Some(abi) => crate::argument_sources::lower_helpers(
            crate::argument_sources::HelperInputs {
                frontend,
                parsed: parsed.into(),
                metadata,
                owner: identity,
                inputs: &inputs,
                helpers: &abi.source_helpers,
                symbols,
            },
            host,
        )
        .map_err(unsupported)?,
        None => Vec::new(),
    };
    Ok(LoweredUnit {
        identity,
        effective: source_identity.effective,
        origin: body.clone(),
        code,
        selected_references,
        metadata: Arc::clone(metadata),
        abi: prepared.abi,
        debug_origins: debug.original.finish(),
        source_helpers,
    })
}
