//! SETTINGS-ONLY admission provider. It is independent of optional whole-body
//! queries, so ABI-first and one-shot preparation need not parse a procedure.
//! The native host must install its EXISTING QueryDb; no fallback Db is created.
use super::*;

/// Opaque borrowed current-source proof. No constructor, Clone or detached
/// source/metadata fields are exposed; provider storage alone cannot mint it.
pub struct SettingExpressionInput<'a> {
    source: setting_source::OriginalSettingSource<'a>,
}
impl std::fmt::Debug for SettingExpressionInput<'_> {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("SettingExpressionInput")
            .finish_non_exhaustive()
    }
}
impl SettingExpressionInput<'_> {
    /// The provider issues ONE stack admission from its existing body counter.
    /// Real operational IO is extracted exactly once before this public boundary
    /// returns; an error status never becomes a parser/source Diagnostic.
    pub fn prepare(
        &self,
        a: &dm_syntax::SettingAdmission<'_>,
    ) -> Result<dm_syntax::SettingExpression, BodySyntaxFailure> {
        let result = self.source.expression(a);
        if let Some(actual) = a.take_operational_error() {
            return Err(BodySyntaxFailure::Operational(actual));
        }
        result.map_err(|failure| match failure {
            dm_syntax::SettingSyntaxFailure::Operational(error) => {
                BodySyntaxFailure::Operational(error)
            }
            dm_syntax::SettingSyntaxFailure::Syntax(error) => {
                let input = self.source.token_input();
                let Some(at) = error.span.start.checked_add(input.offset) else {
                    return BodySyntaxFailure::Operational(std::io::Error::new(
                        std::io::ErrorKind::InvalidInput,
                        "setting diagnostic projection overflow",
                    ));
                };
                BodySyntaxFailure::Syntax(Diagnostic {
                    kind: syntax_kind(error.kind),
                    stage: DiagnosticStage::Syntax,
                    location: self.source.frontend().location(at),
                    message: error.message,
                })
            }
        })
    }
}
/// Source-local roots use this existing-host provider only outside Kind4. The
/// Kind4 producer supplies its already-held stack permit directly at the leaf,
/// without calling this trait, QueryDb.get, begin_revision or any family gate.
/// One-shot checked statement demand, issued only after the SAME original
/// procedure body was actually requested. No ABI-first whole-body demand.
pub struct SettingStatementsInput<'issuer, 'item> {
    source: &'issuer dm_preprocess::SourceText,
    syntax: &'issuer DeclarationSyntax,
    code: IssuedBodyCode<'issuer>,
    item: &'item mut Item,
    supported: fn(&[dm_syntax::Statement]) -> bool,
    attempted: bool,
    produced: Option<std::sync::Weak<StatementBody>>,
}
impl std::fmt::Debug for SettingStatementsInput<'_, '_> {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("SettingStatementsInput")
    }
}
impl<'issuer, 'item> SettingStatementsInput<'issuer, 'item> {
    pub(super) fn issued(
        source: &'issuer dm_preprocess::SourceText,
        syntax: &'issuer DeclarationSyntax,
        code: IssuedBodyCode<'issuer>,
        item: &'item mut Item,
        supported: fn(&[dm_syntax::Statement]) -> bool,
    ) -> Self {
        Self {
            source,
            syntax,
            code,
            item,
            supported,
            attempted: false,
            produced: None,
        }
    }
    pub(super) fn accepts(&self, statements: &Arc<StatementBody>) -> bool {
        self.produced
            .as_ref()
            .is_some_and(|issued| std::sync::Weak::ptr_eq(issued, &Arc::downgrade(statements)))
    }

    pub fn prepare(
        &mut self,
        a: &dm_syntax::SettingAdmission<'_>,
    ) -> Result<Arc<StatementBody>, BodySyntaxFailure> {
        if self.attempted {
            return Err(BodySyntaxFailure::Operational(std::io::Error::new(
                std::io::ErrorKind::InvalidInput,
                "original statement request was already consumed",
            )));
        }
        self.attempted = true;
        let result = body_archive::parse_statements_with_setting_admission(
            self.item,
            self.source,
            self.syntax,
            self.code.occurrence().expanded_span,
            Some(self.code.identity()),
            a,
            self.supported,
        )?;
        self.produced = Some(Arc::downgrade(&result));
        Ok(result)
    }
}
pub trait SettingExpressionQueries: std::fmt::Debug + Send + Sync {
    fn expression(
        &self,
        input: &SettingExpressionInput<'_>,
    ) -> Result<dm_syntax::SettingExpression, BodySyntaxFailure>;
    /// Custom source-root providers must opt into checked statement admission
    /// explicitly. This default is a typed refusal, never a compatibility parse.
    fn statements(
        &self,
        _: &mut SettingStatementsInput<'_, '_>,
    ) -> Result<Arc<StatementBody>, BodySyntaxFailure> {
        Err(BodySyntaxFailure::Operational(std::io::Error::new(
            std::io::ErrorKind::NotConnected,
            "existing settings provider does not admit native statement demand",
        )))
    }
}
impl ColdFrontend {
    /// Attach only an already-owned host. Weak keeps a declaration/frontend from
    /// retaining a second QueryDb manager. Rebinding any original issued frontend
    /// to another provider is refused even if the previous Weak has expired.
    pub fn with_setting_expression_queries(
        mut self,
        host: &Arc<dyn SettingExpressionQueries>,
    ) -> Result<Self, Diagnostic> {
        let weak = Arc::downgrade(host);
        if self
            .setting_expression_queries
            .as_ref()
            .is_some_and(|old| !std::sync::Weak::ptr_eq(old, &weak))
        {
            return Err(internal("original settings provider cannot be rebound"));
        }
        self.setting_expression_queries = Some(weak);
        Ok(self)
    }
    pub(super) fn setting_statements(
        &self,
        occurrence: &BodyOccurrence,
        item: &mut Item,
        supported: fn(&[dm_syntax::Statement]) -> bool,
    ) -> Result<Arc<StatementBody>, BodySyntaxFailure> {
        let code = self
            .body_code(occurrence)
            .map_err(BodySyntaxFailure::Syntax)?;
        let provider = self
            .setting_expression_queries
            .as_ref()
            .and_then(std::sync::Weak::upgrade)
            .ok_or_else(|| {
                BodySyntaxFailure::Operational(std::io::Error::new(
                    std::io::ErrorKind::NotConnected,
                    "original statements with settings require the existing native host provider",
                ))
            })?;
        let mut input = SettingStatementsInput::issued(
            &self.issued_arena,
            &self.issued_syntax,
            code,
            item,
            supported,
        );
        let statements = provider.statements(&mut input)?;
        if !input.accepts(&statements) {
            return Err(BodySyntaxFailure::Operational(std::io::Error::new(
                std::io::ErrorKind::InvalidData,
                "settings provider returned a foreign original statement result",
            )));
        }
        Ok(statements)
    }
    /// Native setting demand authenticates actual current source/occurrence/
    /// selected metadata BEFORE upgrading the provider or entering its cache.
    /// Standalone compatibility evaluators keep their separate explicit API.
    pub fn setting_expression(
        &self,
        occurrence: &BodyOccurrence,
        metadata: &dm_ir::ProcedureMetadata,
        expression: &dm_ir::SymbolicExpression,
    ) -> Result<dm_syntax::SettingExpression, BodySyntaxFailure> {
        let source = self
            .original_setting_source(occurrence, metadata, expression)
            .map_err(BodySyntaxFailure::Syntax)?;
        let provider = self
            .setting_expression_queries
            .as_ref()
            .and_then(std::sync::Weak::upgrade)
            .ok_or_else(|| {
                BodySyntaxFailure::Operational(std::io::Error::new(
                    std::io::ErrorKind::NotConnected,
                    "original settings require the existing native host provider",
                ))
            })?;
        let input = SettingExpressionInput { source };
        let root = provider.expression(&input)?;
        input
            .source
            .require_expression(&root)
            .map_err(BodySyntaxFailure::Operational)?;
        Ok(root)
    }
}
