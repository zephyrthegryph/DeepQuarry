//! Optional streaming node rows from the shared typed visitor.
use crate::typed_body::NoTypedModel;
use dm_syntax::{Expr, ExprKind, NodeStep, Statement, TypedVisitor, VisitDecision, VisitReport};
use dm_tree::frontend::ParsedBody;
use serde_json::{json, Value};
use std::io::{self, Write};

pub const SCHEMA: &str = "dm-typed-body-analysis-v1";

#[derive(Debug)]
pub enum ExportError {
    NoTypedModel(NoTypedModel),
    Io(io::Error),
    Json(serde_json::Error),
}
impl std::fmt::Display for ExportError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::NoTypedModel(error) => error.fmt(f),
            Self::Io(error) => error.fmt(f),
            Self::Json(error) => error.fmt(f),
        }
    }
}
impl std::error::Error for ExportError {}

/// Structural paths and byte spans describe this current body, not stable semantic
/// identities. The caller supplies an issued parse, so exporting never reparses.
pub fn write_jsonl(
    body: &ParsedBody<'_>,
    writer: &mut impl Write,
) -> Result<VisitReport, ExportError> {
    // Reject absence before writing a partial stream.
    body.statement_body()
        .ok_or(ExportError::NoTypedModel(NoTypedModel))?;
    write_model(
        body.occurrence(),
        body.statement_body().expect("checked above").parsed(),
        writer,
    )
}
/// The archive is minted by the same current frontend producer as ParsedBody.
pub fn write_archived_jsonl(
    body: &dm_tree::frontend::ArchivedBody<'_>,
    writer: &mut impl Write,
) -> Result<VisitReport, ExportError> {
    write_model(body.occurrence(), body.statement_body().parsed(), writer)
}
fn write_model(
    occurrence: &dm_tree::frontend::BodyOccurrence,
    model: &dm_syntax::ParsedBody,
    writer: &mut impl Write,
) -> Result<VisitReport, ExportError> {
    let mut visitor = Rows {
        writer,
        member: occurrence.member.0,
        declaration: occurrence.declaration.0,
        error: None,
    };
    let report = dm_syntax::visit_statements(&model.statements, &mut visitor);
    if let Some(error) = visitor.error {
        return Err(error);
    }
    visitor.emit(json!({"schema":SCHEMA,"row":"body_summary",
        "member":visitor.member,"declaration":visitor.declaration,
        "statements":report.statements,"expressions":report.expressions,
        "unsupported_statements":report.unsupported_statements,
        "diagnostics":model.diagnostics.iter().map(|d|json!({
            "span":[d.span.start,d.span.end],"message":d.message})).collect::<Vec<_>>() }));
    if let Some(error) = visitor.error {
        return Err(error);
    }
    Ok(report)
}
struct Rows<'a, W> {
    writer: &'a mut W,
    member: u32,
    declaration: u32,
    error: Option<ExportError>,
}
impl<W: Write> Rows<'_, W> {
    fn emit(&mut self, value: Value) -> VisitDecision {
        if self.error.is_some() {
            return VisitDecision::Stop;
        }
        if let Err(error) = serde_json::to_writer(&mut *self.writer, &value) {
            self.error = Some(ExportError::Json(error));
            return VisitDecision::Stop;
        }
        if let Err(error) = self.writer.write_all(b"\n") {
            self.error = Some(ExportError::Io(error));
            return VisitDecision::Stop;
        }
        VisitDecision::Descend
    }
    fn path(path: &[NodeStep]) -> Vec<Value> {
        path.iter()
            .map(|step| match step {
                NodeStep::Statement(i) => json!(["statement", i]),
                NodeStep::Branch(i) => json!(["branch", i]),
                NodeStep::Expression(i) => json!(["expression", i]),
                NodeStep::Child(i) => json!(["child", i]),
            })
            .collect()
    }
}
impl<W: Write> TypedVisitor for Rows<'_, W> {
    fn statement(&mut self, node: &Statement, path: &[NodeStep]) -> VisitDecision {
        self.emit(
            json!({"schema":SCHEMA,"row":"statement","member":self.member,
            "declaration":self.declaration,"path":Self::path(path),
            "span":[node.span.start,node.span.end],
            "header_span":[node.header_span.start,node.header_span.end],
            "header":node.raw_header}),
        )
    }
    fn expression(&mut self, node: &Expr, path: &[NodeStep]) -> VisitDecision {
        self.emit(
            json!({"schema":SCHEMA,"row":"expression","member":self.member,
            "declaration":self.declaration,"path":Self::path(path),
            "syntax":expression_syntax(&node.kind),"span":[node.span.start,node.span.end]}),
        )
    }
}

fn expression_syntax(kind: &ExprKind) -> Value {
    match kind {
        ExprKind::Ident(name) => json!({"kind":"identifier","name":name}),
        ExprKind::Literal(text) => json!({"kind":"literal","text":text}),
        ExprKind::TypePath(path) => json!({"kind":"type_path","path":path}),
        ExprKind::Unary { op, .. } => json!({"kind":"unary","operator":op}),
        ExprKind::Binary { op, .. } => json!({"kind":"binary","operator":op}),
        ExprKind::Conditional { .. } => json!({"kind":"conditional"}),
        ExprKind::Call { args, .. } => json!({"kind":"call","argument_count":args.len()}),
        ExprKind::Member {
            selector,
            via_colon,
            ..
        } => json!({"kind":"member","selector":selector,"via_colon":via_colon}),
        ExprKind::StaticMember { selector, .. } => {
            json!({"kind":"static_member","selector":selector})
        }
        ExprKind::TypeFilter { types, .. } => json!({"kind":"type_filter","types":types}),
        ExprKind::ObjectInitializer { fields, .. } => {
            json!({"kind":"object_initializer","fields":fields.iter().map(|(name,_)|name).collect::<Vec<_>>()})
        }
        ExprKind::SafeMember {
            selector,
            via_colon,
            ..
        } => json!({"kind":"safe_member","selector":selector,"via_colon":via_colon}),
        ExprKind::Index { .. } => json!({"kind":"index"}),
        ExprKind::SafeIndex { .. } => json!({"kind":"safe_index"}),
        ExprKind::Group(_) => json!({"kind":"group"}),
    }
}
