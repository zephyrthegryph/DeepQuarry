//! Caller-selected semantic questions tied to current typed-node coordinates.
//! Syntax alone cannot establish local shadowing or an expression receiver type;
//! callers must supply those questions from their actual scope/binding model.
use super::{visit, NoTypedModel};
use crate::tree_export::{write_queries_jsonl, AnalysisQuery, ExportError};
use dm_ir::{ResolveQuery, Resolver, SymbolTable};
use dm_syntax::{Expr, NodeStep, TypedVisitor, VisitDecision};
use dm_tree::frontend::ParsedBody;
use std::io::Write;

#[derive(Debug)]
pub enum QueryError {
    NoTypedModel(NoTypedModel),
    Export(ExportError),
}
impl std::fmt::Display for QueryError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::NoTypedModel(error) => error.fmt(f),
            Self::Export(error) => error.fmt(f),
        }
    }
}
impl std::error::Error for QueryError {}

/// Stream exact Resolver answers using the existing resolved-query schema.
/// Subjects are current occurrence/path coordinates, not edit-stable identities.
/// Empty query iterators are allowed. This does not infer bindings from names.
pub fn write_jsonl<I: IntoIterator<Item = ResolveQuery>>(
    body: &ParsedBody<'_>,
    symbols: &SymbolTable,
    resolver: &(impl Resolver + ?Sized),
    queries: impl FnMut(&Expr, &[NodeStep]) -> I,
    writer: &mut impl Write,
) -> Result<usize, QueryError> {
    struct Questions<'a, R: ?Sized, W, F> {
        symbols: &'a SymbolTable,
        resolver: &'a R,
        writer: &'a mut W,
        queries: F,
        declaration: u32,
        count: usize,
        error: Option<ExportError>,
    }
    impl<
            R: Resolver + ?Sized,
            W: Write,
            I: IntoIterator<Item = ResolveQuery>,
            F: FnMut(&Expr, &[NodeStep]) -> I,
        > TypedVisitor for Questions<'_, R, W, F>
    {
        fn expression(&mut self, node: &Expr, path: &[NodeStep]) -> VisitDecision {
            let subject = format!("body-occurrence:{}:node:{path:?}", self.declaration);
            let questions = (self.queries)(node, path);
            match write_queries_jsonl(
                self.symbols,
                self.resolver,
                questions.into_iter().map(|query| AnalysisQuery {
                    subject: Some(&subject),
                    query,
                }),
                self.writer,
            ) {
                Ok(count) => {
                    self.count += count;
                    VisitDecision::Descend
                }
                Err(error) => {
                    self.error = Some(error);
                    VisitDecision::Stop
                }
            }
        }
    }
    let mut visitor = Questions {
        symbols,
        resolver,
        writer,
        queries,
        declaration: body.occurrence().declaration.0,
        count: 0,
        error: None,
    };
    visit(body, &mut visitor).map_err(QueryError::NoTypedModel)?;
    if let Some(error) = visitor.error {
        return Err(QueryError::Export(error));
    }
    Ok(visitor.count)
}
