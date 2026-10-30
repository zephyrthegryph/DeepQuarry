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
    parameter_admission: usize,
}

/// One immutable parse, borrowed by lowering, lint policies and checker passes.
/// Lossless children remain available for unsupported lowering constructs.
pub struct BodySyntax {
    issuance: u64,
    pub(super) item: Item,
    pub(super) opening_parenthesis: Option<dm_syntax::Span>,
    pub(super) parameters: Arc<dm_syntax::ParameterSignature>,
    pub(super) statements: Arc<StatementBody>,
    input_bytes: usize,
}

impl BodySyntaxInput {
    pub fn key(&self) -> u64 {
        self.id
    }
    /// Pre-parse admission estimate, including a header-only receipt upper bound.
    /// This is a bounded-cohort estimate, not a bound on allocations or RSS.
    pub fn budget_charge(&self) -> usize {
        syntax_budget_charge(self.span.end.saturating_sub(self.span.start))
            .saturating_add(self.parameter_admission)
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
        if issued.parameters.retained_bytes() > self.parameter_admission {
            return Err(internal(
                "primary parameter receipt exceeded original header admission",
            ));
        }
        let mut item = issued.item;
        let statements =
            body_archive::parse_statements(&mut item, &self.source, &self.syntax, |_| false);
        Ok(BodySyntax {
            issuance: self.id,
            opening_parenthesis: issued.opening_parenthesis,
            parameters: Arc::new(issued.parameters),
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
    pub fn parameter_storage(&self) -> &Arc<dm_syntax::ParameterSignature> {
        &self.parameters
    }
    /// Provisional admission charge until the shared ownership census supplies
    /// exact AST allocation sizes. Does not claim to measure process RSS.
    pub fn budget_charge(&self) -> usize {
        syntax_budget_charge(self.input_bytes)
            .saturating_add(self.parameters.retained_bytes())
            .saturating_add(
                self.statements
                    .parsed()
                    .local_variables
                    .retained_admission(),
            )
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

    #[test]
    fn original_body_syntax_charge_includes_real_local_array_owners() {
        use std::{path::Path, sync::Arc};
        struct Original(dm_preprocess::AcquiredSource);
        impl dm_preprocess::SourceProvider for Original {
            fn read(&self, _: &Path) -> Result<String, String> {
                Err("original acquisition required".into())
            }
            fn acquired_source(
                &self,
                _: &Path,
            ) -> Result<Option<dm_preprocess::AcquiredSource>, String> {
                Ok(Some(self.0.clone()))
            }
            fn source_acquisition(
                &self,
                _: &Path,
                text: &dm_preprocess::SourceText,
            ) -> Option<dm_preprocess::AcquiredSource> {
                self.0
                    .lease()
                    .source_text()
                    .same_view(text)
                    .then(|| self.0.clone())
            }
        }
        #[derive(Debug)]
        struct Observe;
        impl super::BodySyntaxQueries for Observe {
            fn syntax(
                &self,
                input: &Arc<super::BodySyntaxInput>,
            ) -> Result<Arc<super::BodySyntax>, super::Diagnostic> {
                let syntax = input.parse()?;
                let actual = syntax
                    .statements
                    .parsed()
                    .local_variables
                    .retained_admission();
                assert!(actual > 0);
                assert_eq!(
                    syntax.budget_charge(),
                    super::syntax_budget_charge(syntax.input_bytes)
                        .saturating_add(syntax.parameters.retained_bytes())
                        .saturating_add(actual)
                );
                Ok(Arc::new(syntax))
            }
        }
        let source = Original(dm_preprocess::AcquiredSource::from_original_bytes(
            b"/proc/p()\n    var/x[3][4]\n".to_vec(),
            (),
        ));
        let frontend = crate::frontend::build(
            Path::new("array-budget.dme"),
            &source,
            &Default::default(),
            1,
        )
        .unwrap()
        .with_body_queries(Arc::new(Observe));
        let archive = frontend.body_archive().unwrap();
        assert!(archive.parse(0).is_ok());
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
        if self.reused_body_queries
            && self.source_export_mapping().is_some()
            && self.callable_roster().is_ok()
            && self
                .body_queries
                .as_ref()
                .is_some_and(|queries| Arc::ptr_eq(&queries.host, &host))
        {
            // Native same-original-acquisition/whole-program proof reissued the
            // source wrapper; the immutable original parser input is unchanged.
            self.reused_body_queries = false;
            return self;
        }
        self.reused_body_queries = false;
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
                    parameter_admission: self
                        .issued_syntax
                        .item_path(&body.ast_path)
                        .map(|item| {
                            item.header_span()
                                .end
                                .saturating_sub(item.header_span().start)
                                .saturating_mul(128)
                                .saturating_add(1024)
                        })
                        .unwrap_or(usize::MAX),
                })
            })
            .collect::<Vec<_>>()
            .into();
        self.body_queries = Some(BodyQueries { host, inputs });
        self
    }
}
