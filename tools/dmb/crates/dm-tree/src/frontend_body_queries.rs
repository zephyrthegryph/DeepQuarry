//! Optional body-syntax queries supplied by the compiler's existing query host.
//! Query keys are issuance-local, never authority minted from matching bytes.
use super::*;

/// Only the frontend can create this captured input. Query parameters hold it
/// weakly, so keeping graph metadata cannot retain obsolete source revisions.
#[derive(Debug)]
pub struct BodySyntaxInput {
    id: u64,
    source: dm_preprocess::SourceText,
    syntax: Arc<DeclarationSyntax>,
    span: dm_syntax::Span,
    location: SourceLocation,
    mapping: Arc<SourceExportMapping>,
}

/// One immutable parse, borrowed by lowering, lint policies and checker passes.
/// Lossless children remain available for unsupported lowering constructs.
pub struct BodySyntax {
    issuance: u64,
    pub(super) item: Item,
    pub(super) opening_parenthesis: Option<dm_syntax::Span>,
    pub(super) statements: Arc<StatementBody>,
    input_bytes: usize,
}

impl BodySyntaxInput {
    pub fn key(&self) -> u64 {
        self.id
    }
    /// Pre-parse admission estimate, identical to the resulting syntax charge.
    /// This is a bounded-cohort estimate, not a bound on allocations or RSS.
    pub fn budget_charge(&self) -> usize {
        syntax_budget_charge(self.span.end.saturating_sub(self.span.start))
    }
    pub(super) fn obtain(
        self: &Arc<Self>,
        host: &dyn BodySyntaxQueries,
    ) -> Result<Arc<BodySyntax>, Diagnostic> {
        let syntax = host.syntax(self)?;
        if syntax.issuance != self.id {
            return Err(internal("body query returned a foreign parser issuance"));
        }
        Ok(syntax)
    }
    pub fn parse(&self) -> Result<BodySyntax, Diagnostic> {
        let issued = dm_syntax::parse_proc_with_origins_at_span(&self.source, self.span).map_err(
            |error| Diagnostic {
                kind: syntax_kind(error.kind),
                stage: DiagnosticStage::Syntax,
                location: self
                    .mapping
                    .output(error.span.start)
                    .or_else(|| Some(self.location.clone())),
                message: error.message,
            },
        )?;
        let mut item = issued.item;
        let statements =
            body_archive::parse_statements(&mut item, &self.source, &self.syntax, |_| false);
        Ok(BodySyntax {
            issuance: self.id,
            opening_parenthesis: issued.opening_parenthesis,
            item,
            statements,
            input_bytes: self.span.end.saturating_sub(self.span.start),
        })
    }
}
impl std::fmt::Debug for BodySyntax {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("BodySyntax")
            .field("issuance", &self.issuance)
            .field("input_bytes", &self.input_bytes)
            .finish_non_exhaustive()
    }
}
impl BodySyntax {
    /// Provisional admission charge until the shared ownership census supplies
    /// exact AST allocation sizes. Does not claim to measure process RSS.
    pub fn budget_charge(&self) -> usize {
        syntax_budget_charge(self.input_bytes)
    }
}

fn syntax_budget_charge(input_bytes: usize) -> usize {
    input_bytes.saturating_mul(64).saturating_add(4096)
}

#[cfg(test)]
mod budget_tests {
    #[test]
    fn input_and_result_admission_estimate_has_shared_saturating_boundaries() {
        assert_eq!(super::syntax_budget_charge(0), 4096);
        assert_eq!(super::syntax_budget_charge(1), 4160);
        assert_eq!(super::syntax_budget_charge(usize::MAX), usize::MAX);
    }
}

pub trait BodySyntaxQueries: std::fmt::Debug + Send + Sync {
    /// Quiescent admission boundary: collect expired issuance metadata once,
    /// never scan the whole graph for every body in a large program.
    fn begin_revision(&self) {}
    fn syntax(&self, input: &Arc<BodySyntaxInput>) -> Result<Arc<BodySyntax>, Diagnostic>;
}

#[derive(Clone, Debug)]
pub(super) struct BodyQueries {
    pub host: Arc<dyn BodySyntaxQueries>,
    pub inputs: Arc<[Arc<BodySyntaxInput>]>,
}

impl ColdFrontend {
    /// Opt in only after declaration construction. The source, occurrence list
    /// and syntax are captured together; callers cannot substitute foreign ASTs.
    pub fn with_body_queries(mut self, host: Arc<dyn BodySyntaxQueries>) -> Self {
        host.begin_revision();
        static NEXT: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(1);
        let inputs = self
            .issued_bodies
            .iter()
            .map(|body| {
                Arc::new(BodySyntaxInput {
                    id: NEXT.fetch_add(1, std::sync::atomic::Ordering::Relaxed),
                    source: self.issued_arena.clone(),
                    syntax: self.issued_syntax.clone(),
                    span: body.expanded_span,
                    location: body.source.clone(),
                    mapping: Arc::clone(&self.source_export_mapping),
                })
            })
            .collect::<Vec<_>>()
            .into();
        self.body_queries = Some(BodyQueries { host, inputs });
        self
    }
}
