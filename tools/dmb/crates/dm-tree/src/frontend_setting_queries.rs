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
        let result = body_archive::parse_statements_with_body_literal_admission(
            self.item,
            self.source,
            self.syntax,
            self.code.occurrence().expanded_span,
            Some(self.code.identity()),
            a,
            self.supported,
        );
        // SAME admitted native body boundary as Kind4: preserve the actual
        // first IO, not a checkpoint proxy, before recording successful output.
        if matches!(&result,Err(BodySyntaxFailure::Operational(_))){
            return match a.take_operational_error(){Some(actual)=>Err(BodySyntaxFailure::Operational(actual)),None=>result};
        }
        let completion=a.checkpoint();
        if let Some(actual)=a.take_operational_error(){return Err(BodySyntaxFailure::Operational(actual));}
        completion.map_err(BodySyntaxFailure::Operational)?;
        let result=result?;
        self.produced = Some(Arc::downgrade(&result));
        Ok(result)
    }
}
pub trait SettingExpressionQueries: std::fmt::Debug + Send + Sync {
    /// Borrow the EXISTING host's transformed-source resource ledger. A source
    /// preparation never creates another budget, QueryDb, executor or cache.
    fn original_source_work(&self)->Result<&dyn dm_preprocess::source_arena_credit::SourceArenaWork,BodySyntaxFailure>{Err(BodySyntaxFailure::Operational(std::io::Error::new(std::io::ErrorKind::NotConnected,"existing expression host cannot lend actual Original source work")))}

    /// Resource-only weak alias registration on the SAME native owner. An old
    /// custom provider must explicitly opt in; no silently unfunded public IR.
    fn retain_original_signature_aliases(&self,_:Arc<super::original_signature_funding::OriginalSignatureAliasGroup>,_:&dm_syntax::SettingAdmission<'_>)->Result<(),BodySyntaxFailure>{Err(BodySyntaxFailure::Operational(std::io::Error::new(std::io::ErrorKind::NotConnected,"native provider has no original signature alias lifetime census")))}

    /// Early declaration work on the already-owned native host's SAME counter.
    /// This grants resource admission only, not any source/declaration proof.
    /// Checked builder owns the original input and keeps the full semantic
    /// AdapterError vector separate; actual IO travels this callback directly.
    /// No whole BodySyntax query, new Db, revision, gate or budget reset occurs.
    fn with_declaration_admission(
        &self,
        _: &mut dyn FnMut(&dm_syntax::SettingAdmission<'_>) -> Result<(), BodySyntaxFailure>,
    ) -> Result<(), BodySyntaxFailure> {
        Err(BodySyntaxFailure::Operational(std::io::Error::new(
            std::io::ErrorKind::NotConnected,
            "existing expression provider does not admit original declaration work",
        )))
    }

    fn expression(
        &self,
        input: &SettingExpressionInput<'_>,
    ) -> Result<dm_syntax::SettingExpression, BodySyntaxFailure>;
    fn return_annotation(
        &self,
        _: &ReturnAnnotationInput<'_>,
    ) -> Result<dm_syntax::SettingExpression, BodySyntaxFailure> {
        Err(BodySyntaxFailure::Operational(std::io::Error::new(
            std::io::ErrorKind::NotConnected,
            "existing original expression provider does not admit return annotations",
        )))
    }
    fn initializer<'source>(
        &self,
        _: &OriginalInitializerExpressionInput<'source>,
    ) -> Result<OriginalInitializerExpression<'source>, BodySyntaxFailure> {
        Err(BodySyntaxFailure::Operational(std::io::Error::new(
            std::io::ErrorKind::NotConnected,
            "existing original expression provider does not admit initializers",
        )))
    }
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

/// Opaque exact current-source annotation projection. No detached constructor,
/// semantic clone or whole-body parser is exposed by this request.
pub struct ReturnAnnotationInput<'a> {
    frontend: &'a ColdFrontend,
    input: relative_declarations::OriginalReturnTokenInput<'a>,
}
impl std::fmt::Debug for ReturnAnnotationInput<'_> {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("ReturnAnnotationInput")
    }
}
impl ReturnAnnotationInput<'_> {
    pub fn prepare(
        &self,
        a: &dm_syntax::SettingAdmission<'_>,
    ) -> Result<dm_syntax::SettingExpression, BodySyntaxFailure> {
        let input = &self.input;
        let result = input
            .slots
            .obtain(input.ordinal, input.count, a, || {
                input.tokens.with_dense_using(a,|dense|Ok(dm_syntax::prepare_setting_expression_with_original_literal_facts(input.source,dense,input.original_value,a,input.literal_owner.original_literal_facts()?))).map_err(dm_syntax::SettingSyntaxFailure::Operational)?
            })
            .and_then(|root| {
                root.project_current(input.offset, input.source.len())
                    .map_err(dm_syntax::SettingSyntaxFailure::Operational)
            });
        if let Some(actual) = a.take_operational_error() {
            return Err(BodySyntaxFailure::Operational(actual));
        }
        result.map_err(|error| match error {
            dm_syntax::SettingSyntaxFailure::Operational(error) => {
                BodySyntaxFailure::Operational(error)
            }
            dm_syntax::SettingSyntaxFailure::Syntax(error) => {
                let Some(at) = error.span.start.checked_add(input.offset) else {
                    return BodySyntaxFailure::Operational(std::io::Error::new(
                        std::io::ErrorKind::InvalidInput,
                        "return annotation diagnostic projection overflow",
                    ));
                };
                BodySyntaxFailure::Syntax(Diagnostic {
                    kind: syntax_kind(error.kind),
                    stage: DiagnosticStage::Syntax,
                    location: self.frontend.location(at),
                    message: error.message,
                })
            }
        })
    }
}
impl ColdFrontend {
    pub fn return_annotation_expression(
        &self,
        occurrence: &BodyOccurrence,
        metadata: &dm_ir::ProcedureMetadata,
        fragment: &dm_ir::SymbolicExpression,
    ) -> Result<dm_syntax::SettingExpression, BodySyntaxFailure> {
        self.compact_body(occurrence)
            .map_err(BodySyntaxFailure::Syntax)?;
        let index = *self
            .body_by_declaration
            .get(&occurrence.declaration)
            .ok_or_else(|| internal("original return occurrence unavailable"))?;
        if !self
            .issued_bodies
            .get(index)
            .is_some_and(|row| std::ptr::eq(row, occurrence))
        {
            return Err(BodySyntaxFailure::Syntax(internal(
                "original return occurrence copied or foreign",
            )));
        }
        let selected = self
            .snapshot
            .tree
            .member(occurrence.member)
            .and_then(|m| m.metadata.procedure.as_deref())
            .ok_or_else(|| internal("original return metadata unavailable"))?;
        let bound = self
            .issued_settings
            .get(index)
            .and_then(Option::as_deref)
            .ok_or_else(|| internal("original return metadata binding unavailable"))?;
        if !std::ptr::eq(selected, metadata) || !std::ptr::eq(bound, metadata) {
            return Err(BodySyntaxFailure::Syntax(internal(
                "original return metadata copied or foreign",
            )));
        }
        let code = self
            .body_code(occurrence)
            .map_err(BodySyntaxFailure::Syntax)?;
        let input = self
            .issued_syntax
            .return_annotation_token_input(
                occurrence.expanded_span,
                code.identity(),
                fragment,
                metadata,
                self.snapshot.tree.symbols(),
            )
            .map_err(|error| {
                BodySyntaxFailure::Syntax(Diagnostic {
                    kind: syntax_kind(error.kind),
                    stage: DiagnosticStage::Syntax,
                    location: self.location(error.span.start),
                    message: error.message,
                })
            })?;
        let provider = self
            .setting_expression_queries
            .as_ref()
            .and_then(std::sync::Weak::upgrade)
            .ok_or_else(|| {
                BodySyntaxFailure::Operational(std::io::Error::new(
                    std::io::ErrorKind::NotConnected,
                    "original return annotation requires the existing native host provider",
                ))
            })?;
        let request = ReturnAnnotationInput {
            frontend: self,
            input,
        };
        let root = provider.return_annotation(&request)?;
        if root.current_offset() != request.input.offset
            || !request
                .input
                .slots
                .contains_original(request.input.ordinal, &root)
        {
            return Err(BodySyntaxFailure::Operational(std::io::Error::new(
                std::io::ErrorKind::InvalidData,
                "return annotation provider returned foreign root or projection",
            )));
        }
        Ok(root)
    }
}
