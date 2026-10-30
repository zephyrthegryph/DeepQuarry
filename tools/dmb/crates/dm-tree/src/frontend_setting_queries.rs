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
pub trait SettingExpressionQueries: std::fmt::Debug + Send + Sync {
    fn expression(
        &self,
        input: &SettingExpressionInput<'_>,
    ) -> Result<dm_syntax::SettingExpression, BodySyntaxFailure>;
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
