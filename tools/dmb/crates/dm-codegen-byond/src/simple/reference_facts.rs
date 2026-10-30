//! Optional current-node index; no AST addresses survive this compiler invocation.
use super::*;
use dm_ir::{SelectedMeaning as M, SelectedReference, SelectedReferences};
#[cfg(test)]
#[path = "reference_facts_tests.rs"]
mod tests;

/// Compile with optional partial selected-reference evidence from the same emitter.
/// The ordinary API allocates no reference index and performs no extra traversal.
pub fn compile_statement_view_with_resolver_and_references<R: dm_ir::Resolver>(
    view: dm_syntax::StatementView<'_>,
    inputs: &crate::lower_resolver::ProcedureInputs,
    symbols: &dm_ir::SymbolTable,
    resolver: &R,
    debug: Option<&dyn DebugSourceProvider>,
) -> Result<(crate::lower_resolver::ResolverProc, SelectedReferences), Vec<LowerError>> {
    compile_references(view, inputs, symbols, resolver, debug, None)
}
/// Capture checked body-relative coordinates from the same selected AST nodes.
pub fn compile_statement_view_with_resolver_and_references_at<R: dm_ir::Resolver>(
    view: dm_syntax::StatementView<'_>,
    inputs: &crate::lower_resolver::ProcedureInputs,
    symbols: &dm_ir::SymbolTable,
    resolver: &R,
    debug: Option<&dyn DebugSourceProvider>,
    body_span: dm_syntax::Span,
) -> Result<(crate::lower_resolver::ResolverProc, SelectedReferences), Vec<LowerError>> {
    compile_references(view, inputs, symbols, resolver, debug, Some(body_span))
}
fn compile_references<R: dm_ir::Resolver>(
    view: dm_syntax::StatementView<'_>,
    inputs: &crate::lower_resolver::ProcedureInputs,
    symbols: &dm_ir::SymbolTable,
    resolver: &R,
    debug: Option<&dyn DebugSourceProvider>,
    body_span: Option<dm_syntax::Span>,
) -> Result<(crate::lower_resolver::ResolverProc, SelectedReferences), Vec<LowerError>> {
    let mut references = SelectedReferences::default();
    let procedure = resolver_body::compile_resolver_body_captured(
        &[],
        Some(TypedInput::Statements(view)),
        inputs,
        symbols,
        resolver,
        debug,
        Some(ReferenceRequest {
            output: &mut references,
            body_span,
        }),
    )?;
    Ok((procedure, references))
}
/// Same partial body-selection evidence as the compatibility entry, while
/// borrowing original default roots. Default/header selections outside the
/// body visitor remain explicitly unbound; no new completeness is claimed.
pub fn compile_statement_view_with_original_defaults_and_references_at<R: dm_ir::Resolver>(
    view: dm_syntax::StatementView<'_>,
    parameters: &dm_syntax::ParameterSignature,
    source: &str,
    inputs: &crate::lower_resolver::ProcedureInputs,
    symbols: &dm_ir::SymbolTable,
    resolver: &R,
    debug: Option<&dyn DebugSourceProvider>,
    body_span: dm_syntax::Span,
) -> Result<(crate::lower_resolver::ResolverProc, SelectedReferences), Vec<LowerError>> {
    let mut references = SelectedReferences::default();
    let procedure = resolver_body::compile_resolver_body_captured(
        &[],
        Some(TypedInput::ParameterStatements(view, parameters, source)),
        inputs,
        symbols,
        resolver,
        debug,
        Some(ReferenceRequest {
            output: &mut references,
            body_span: Some(body_span),
        }),
    )?;
    Ok((procedure, references))
}

/// Lower a real original expression as the helper's return value, capturing
/// expression-relative lexical selections through the SAME existing emitter.
/// The native host binds original-owner authority before choosing this API.
pub fn compile_return_expression_with_resolver_and_references<R: dm_ir::Resolver>(
    expression: &Expr,
    diagnostic_context: &str,
    inputs: &crate::lower_resolver::ProcedureInputs,
    symbols: &dm_ir::SymbolTable,
    resolver: &R,
    debug: Option<&dyn DebugSourceProvider>,
) -> Result<(crate::lower_resolver::ResolverProc, SelectedReferences), Vec<LowerError>> {
    if inputs.parameter_defaults.iter().any(Option::is_some) {
        return Err(vec![error(
            "helper frame",
            "borrowed helper requires cleared parameter defaults",
        )]);
    }
    let mut references = SelectedReferences::default();
    let procedure = resolver_body::compile_resolver_body_captured(
        &[],
        Some(TypedInput::ReturnExpression(expression, diagnostic_context)),
        inputs,
        symbols,
        resolver,
        debug,
        Some(ReferenceRequest {
            output: &mut references,
            body_span: Some(expression.span),
        }),
    )?;
    Ok((procedure, references))
}

pub(super) struct ReferenceRequest<'a> {
    pub(super) output: &'a mut SelectedReferences,
    pub(super) body_span: Option<dm_syntax::Span>,
}

pub(super) struct ReferenceCapture {
    paths: HashMap<usize, Vec<dm_syntax::NodeStep>>,
    pub(super) facts: SelectedReferences,
    body_span: Option<dm_syntax::Span>,
}
impl ReferenceCapture {
    pub(super) fn new(
        view: dm_syntax::StatementView<'_>,
        body_span: Option<dm_syntax::Span>,
    ) -> Self {
        let mut capture = Self {
            paths: HashMap::new(),
            facts: SelectedReferences::default(),
            body_span,
        };
        dm_syntax::visit_statement_view(view, &mut capture);
        capture
    }
    pub(super) fn expression(expression: &Expr) -> Self {
        let mut capture = Self {
            paths: HashMap::new(),
            facts: SelectedReferences::default(),
            body_span: Some(expression.span),
        };
        dm_syntax::visit_expression(expression, &mut capture);
        capture
    }
    fn record(&mut self, expr: &Expr, name: &str, meaning: M) {
        let Some(path) = self.paths.get(&(expr as *const Expr as usize)) else {
            self.facts.unbound_selections += 1;
            return;
        };
        self.facts.references.push(SelectedReference {
            path: path.clone(),
            name: SymbolId::of(name),
            meaning,
            relative_span: self.body_span.and_then(|body| {
                if body.start > body.end
                    || expr.span.start > expr.span.end
                    || expr.span.end > body.end
                {
                    return None;
                }
                Some((
                    expr.span.start.checked_sub(body.start)?,
                    expr.span.end.checked_sub(body.start)?,
                ))
            }),
        });
    }
}
impl dm_syntax::TypedVisitor for ReferenceCapture {
    fn projected_expression(
        &mut self,
        view: dm_syntax::ProjectedExprView<'_>,
        path: &[dm_syntax::NodeStep],
    ) -> dm_syntax::VisitDecision {
        // Explicitly shape/identity-only; no original span is used as current.
        self.expression(view.original(), path)
    }

    fn expression(
        &mut self,
        expr: &Expr,
        path: &[dm_syntax::NodeStep],
    ) -> dm_syntax::VisitDecision {
        self.paths
            .insert(expr as *const Expr as usize, path.to_vec());
        dm_syntax::VisitDecision::Descend
    }
}
impl Compiler<'_> {
    pub(super) fn record_named_call_selection(
        &mut self,
        expr: &Expr,
        name: &str,
        word: &VariableWord,
    ) {
        if let ExprKind::Call { callee, .. } = &expr.kind {
            self.record_call_selection(callee, name, word, false);
        }
    }
    pub(super) fn record_named_intrinsic(&mut self, expr: &Expr, name: &str) {
        if self.reference_capture.is_none() {
            return;
        }
        if let ExprKind::Call { callee, .. } = &expr.kind {
            self.record_selection(callee, name, M::IntrinsicCall(SymbolId::of(name)));
        }
    }
    pub(super) fn record_property_selection(
        &mut self,
        expr: &Expr,
        name: &str,
        word: &VariableWord,
        safe: bool,
    ) {
        if self.reference_capture.is_none() {
            return;
        }
        let meaning = match word {
            VariableWord::Global(reference) => M::SharedStorage(*reference),
            VariableWord::StaticField(name) => M::RuntimeProperty {
                name: *name,
                static_property: true,
                safe,
            },
            _ => M::RuntimeProperty {
                name: SymbolId::of(name),
                static_property: false,
                safe,
            },
        };
        self.record_selection(expr, name, meaning);
    }
    pub(super) fn record_call_selection(
        &mut self,
        callee: &Expr,
        name: &str,
        word: &VariableWord,
        safe: bool,
    ) {
        if self.reference_capture.is_none() {
            return;
        }
        let meaning = match word {
            VariableWord::StaticProc(reference) | VariableWord::StaticVerb(reference) => {
                M::ProcedureCall {
                    reference: *reference,
                    safe,
                }
            }
            VariableWord::DynamicProc(selector) | VariableWord::DynamicVerb(selector) => {
                M::DynamicProcedure {
                    selector: *selector,
                    safe,
                }
            }
            _ => return,
        };
        self.record_selection(callee, name, meaning);
    }
    pub(super) fn record_selection(&mut self, expr: &Expr, name: &str, meaning: M) {
        if let Some(capture) = &mut self.reference_capture {
            capture.record(expr, name, meaning);
        }
    }
    pub(super) fn variable_for_node(
        &mut self,
        expr: &Expr,
        name: &str,
        statement: &str,
    ) -> Result<VariableWord, LowerError> {
        let meaning = self.variable_meaning(name, statement)?;
        let word = self.variable_operand(&meaning, name, statement)?;
        self.record_selection(expr, name, meaning);
        Ok(word)
    }
}

#[cfg(test)]
mod original_default_reference_tests {
    use super::*;
    #[test]
    fn borrowed_defaults_preserve_explicit_partial_selection_coverage() {
        struct NoQueries;
        impl dm_ir::Resolver for NoQueries {
            fn resolve(&self, q: dm_ir::ResolveQuery) -> dm_ir::ResolvedMeaning {
                panic!("argument-only fixture queried {q:?}")
            }
        }
        let source = "/proc/p(x,y=x+1)\n    return y\n";
        let cold = dm_syntax::parse_declaration_skeleton(source);
        let issued = dm_syntax::parse_proc_with_origins_from_spans(
            source,
            cold.items[0].span,
            &cold.tokens,
            0,
        )
        .unwrap();
        let body = dm_syntax::parse_body_items(&issued.item.children);
        let view = dm_syntax::StatementView::from_parsed(&body);
        let inputs = crate::ProcedureInputs {
            parameters: vec!["x".into(), "y".into()],
            parameter_defaults: vec![None, Some("x+1".into())],
            ..Default::default()
        };
        let symbols = dm_ir::SymbolTable::default();
        let (expected, old) = match compile_statement_view_with_resolver_and_references_at(
            view,
            &inputs,
            &symbols,
            &NoQueries,
            None,
            issued.item.span,
        ) {
            Ok(v) => v,
            Err(e) => panic!("compatibility {e:?}"),
        };
        let before = emission::default_text_parses();
        let (actual, new) = match compile_statement_view_with_original_defaults_and_references_at(
            view,
            &issued.parameters,
            source,
            &inputs,
            &symbols,
            &NoQueries,
            None,
            issued.item.span,
        ) {
            Ok(v) => v,
            Err(e) => panic!("original {e:?}"),
        };
        assert_eq!(actual.procedure, expected.procedure);
        assert_eq!(new, old);
        assert!(
            new.unbound_selections > 0,
            "formal default reads cannot be falsely reported as complete body evidence"
        );
        assert_eq!(emission::default_text_parses(), before);
    }
}
