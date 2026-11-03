//! Checker policies over the compiler's issued syntax. No parser or object tree
//! is constructed here. This is deliberately not a replacement for the full
//! checker until the coverage/parity gates for the remaining families pass.
// Diagnostic wording and negation policy adapted from SpacemanDMM dreamchecker,
// crates/dreamchecker/src/lib.rs, commit recorded below (GPL-3.0).
use dm_syntax::{
    Expr, ExprKind, NodeStep, Span, Statement, StatementKind, TypedVisitor, VisitDecision,
};
use dm_tree::frontend::{ColdFrontend, ParsedBody, SourceLocation, StatementBody};

pub const REFERENCE_COMMIT: &str = "0290db5c752fa292f9824521515b603a2afd11dc";

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum Severity {
    Disabled,
    Warning,
    Error,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct Note {
    pub message: String,
    pub source: Option<dm_tree::frontend::SourceNoteOrigin>,
}
impl Note {
    /// Preserve old textual notes while projecting authentic original coordinates.
    pub fn legacy_text(&self) -> String {
        match &self.source {
            Some(source) => format!("{}:{}: {}", source.line, source.byte_column, self.message),
            None => self.message.clone(),
        }
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct Diagnostic {
    pub family: &'static str,
    pub severity: Severity,
    /// Reference checker anchors these diagnostics to the enclosing statement.
    pub span: Span,
    pub expression_span: Span,
    pub message: String,
    pub notes: Vec<Note>,
}

/// A borrowed view is intentionally not constructible from an unrelated AST.
/// Its occurrence and syntax must have been issued by this exact frontend.
pub struct BodyView<'a> {
    frontend: &'a ColdFrontend,
    body: &'a ParsedBody<'a>,
    syntax: &'a StatementBody,
}

impl<'a> BodyView<'a> {
    pub fn new(frontend: &'a ColdFrontend, body: &'a ParsedBody<'a>) -> Result<Self, String> {
        frontend
            .validate_parsed_body(body, body.occurrence())
            .map_err(|error| error.message)?;
        let syntax = body
            .statement_body()
            .ok_or("body has no issued typed model")?;
        if !syntax.syntax_complete() {
            return Err("body has unsupported or malformed native syntax".into());
        }
        Ok(Self {
            frontend,
            body,
            syntax,
        })
    }

    pub(crate) fn frontend(&self) -> &'a ColdFrontend {self.frontend}

    pub fn syntax(&self) -> &'a StatementBody {
        self.syntax
    }

    pub fn body(&self) -> &'a ParsedBody<'a> {
        self.body
    }

    pub fn location(&self, diagnostic: &Diagnostic) -> Option<SourceLocation> {
        self.frontend.location(diagnostic.span.start)
    }

    /// The caller chooses policy; compiler acceptance is unaffected. A disabled
    /// family does not walk the body. Notes/messages follow pinned suite-1.11.
    pub fn ambiguous_in_lhs(&self, severity: Severity) -> Result<Vec<Diagnostic>, String> {
        crate::checks_ambiguous_in::check(self, severity)
    }
    pub fn ambiguous_not_bitwise(&self, severity: Severity) -> Vec<Diagnostic> {
        check_negated_bitwise(self.syntax, severity)
    }
}

/// Execute a policy directly against the compiler's revision-pinned archive.
/// This emits findings; it never serializes/reparses an executable model.
pub fn archived_ambiguous_not_bitwise(
    body: &dm_tree::frontend::ArchivedBody<'_>,
    severity: Severity,
) -> Result<Vec<Diagnostic>, String> {
    if !body.statement_body().syntax_complete() {
        return Err("body has unsupported or malformed native syntax".into());
    }
    Ok(check_negated_bitwise(body.statement_body(), severity))
}
fn check_negated_bitwise(syntax: &StatementBody, severity: Severity) -> Vec<Diagnostic> {
    if severity == Severity::Disabled {
        return Vec::new();
    }
    let mut visitor = NegatedBitwise {
        origins: syntax.parsed(),
        severity,
        diagnostics: Vec::new(),
        statements: Vec::new(),
        checkpoint:None,
        failure:None,
    };
    dm_syntax::visit_statements(&syntax.parsed().statements, &mut visitor);
    visitor.diagnostics
}

struct NegatedBitwise<'a> {
    origins: &'a dm_syntax::ParsedBody,
    severity: Severity,
    diagnostics: Vec<Diagnostic>,
    statements: Vec<Span>,
    checkpoint:Option<&'a dyn Fn()->std::io::Result<()>>,
    failure:Option<std::io::Error>,
}

impl NegatedBitwise<'_>{
 fn poll(&mut self)->bool{if self.failure.is_some(){return false}if let Some(checkpoint)=self.checkpoint{if let Err(actual)=checkpoint(){self.failure=Some(actual);return false}}true}
}
impl TypedVisitor for NegatedBitwise<'_> {
    fn projected_expression(
        &mut self,
        view: dm_syntax::ProjectedExprView<'_>,
        path: &[dm_syntax::NodeStep],
    ) -> dm_syntax::VisitDecision {
        // Both written Set variants are skipped at the statement boundary.
        let _ = (view, path);
        dm_syntax::VisitDecision::Skip
    }

    fn statement(&mut self, statement: &Statement, _: &[NodeStep]) -> VisitDecision {
        if !self.poll(){return VisitDecision::Stop}
        let anchor = match &statement.kind {
            StatementKind::If { condition, .. } | StatementKind::DoWhile { condition, .. } => self
                .origins
                .control_origin(condition.span)
                .expect("validated primary control origin"),
            _ => statement.span,
        };
        self.statements.push(anchor);
        if matches!(
            &statement.kind,
            StatementKind::Set { .. } | StatementKind::ProjectedSet { .. }
        ) {
            VisitDecision::Skip
        } else {
            VisitDecision::Descend
        }
    }
    fn leave_statement(&mut self, _: &Statement, _: &[NodeStep]) {
        self.statements.pop();
    }
    fn expression(&mut self, expression: &Expr, _: &[NodeStep]) -> VisitDecision {
        if !self.poll(){return VisitDecision::Stop}
        // Base terms reset their children's source anchor; other nodes inherit.
        let anchor = match &expression.kind {
            ExprKind::Group(_) | ExprKind::Literal(_) => expression.span,
            ExprKind::Call { callee, .. } if matches!(callee.kind, ExprKind::Ident(_)) => {
                expression.span
            }
            _ => self.statements.last().copied().unwrap_or(expression.span),
        };
        self.statements.push(anchor);
        if matches!(&expression.kind, ExprKind::ObjectInitializer { .. }) {
            // Pinned visit_term(Prefab) never evaluates modified field values.
            VisitDecision::Skip
        } else {
            VisitDecision::Descend
        }
    }
    fn leave_expression(&mut self, expression: &Expr, _: &[NodeStep]) {
        if !self.poll(){return}
        // Reference BinaryOp checks its lhs only AFTER visiting both children.
        if let ExprKind::Binary { op, lhs, .. } = &expression.kind {
            let boolean = match op.as_str() {
                "&" => Some("&&"),
                "|" => Some("||"),
                "^" => Some("!="),
                _ => None,
            };
            if let Some(boolean) = boolean {
                let mut current = lhs.as_ref();
                let mut negated = false;
                while let ExprKind::Unary { op, value } = &current.kind {
                    if !self.poll(){return}
                    negated |= op == "!";
                    current = value;
                }
                if negated {
                    self.diagnostics.push(Diagnostic {
                        family: "ambiguous_not_bitwise",
                        severity: self.severity,
                        span: self.statements.last().copied().unwrap_or(expression.span),
                        expression_span: expression.span,
                        message: format!("Ambiguous `!` on left side of bitwise `{op}` operator"),
                        notes: [
                            format!("Did you mean `!(x {op} y)`?"),
                            format!("Did you mean `!x {boolean} y`?"),
                            format!("Did you mean `~x {op} y`?"),
                        ]
                        .into_iter()
                        .map(|message| Note {
                            message,
                            source: None,
                        })
                        .collect(),
                    });
                }
            }
        }
        self.statements.pop();
    }
}

#[cfg(test)]
#[path = "checks_tests.rs"]
mod tests;

#[cfg(test)]
#[path = "checks_bitwise_repair_tests.rs"]
mod bitwise_repair_tests;

/// SAME bitwise diagnostic producer over ONE canonical native parser product
/// with an actual current archive binding. No alternate checker algorithm,
/// AST clone, source/model loader or current header-slot forgery.
pub fn current_ambiguous_not_bitwise(body:&dm_tree::frontend::CurrentArchivedBody<'_,'_>,severity:Severity,checkpoint:&dyn Fn()->std::io::Result<()>)->Result<Vec<Diagnostic>,crate::policy_body_demand::PolicyFailure>{
 use crate::policy_body_demand::PolicyFailure;
 checkpoint().map_err(PolicyFailure::Operational)?;
 let syntax=body.syntax().canonical_statement_storage();
 if !syntax.syntax_complete(){return Err("body has unsupported or malformed native syntax".into())}
 if severity==Severity::Disabled{return Ok(Vec::new())}
 let mut visitor=NegatedBitwise{origins:syntax.parsed(),severity,diagnostics:Vec::new(),statements:Vec::new(),checkpoint:Some(checkpoint),failure:None};
 dm_syntax::visit_statements(&syntax.parsed().statements,&mut visitor);
 if let Some(actual)=visitor.failure{return Err(PolicyFailure::Operational(actual))}
 for diagnostic in &mut visitor.diagnostics{
  checkpoint().map_err(PolicyFailure::Operational)?;
  diagnostic.span=body.syntax().projection().span(diagnostic.span).ok_or("native bitwise diagnostic escapes actual current code")?;
  diagnostic.expression_span=body.syntax().projection().span(diagnostic.expression_span).ok_or("native bitwise expression escapes actual current code")?;
  if diagnostic.notes.iter().any(|note|note.source.is_some()){return Err("bitwise producer emitted an unissued absolute source note".into())}
 }
 checkpoint().map_err(PolicyFailure::Operational)?;Ok(visitor.diagnostics)
}
