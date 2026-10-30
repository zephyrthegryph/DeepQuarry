use super::*;
#[path = "driver_constructor_diagnostics.rs"]
mod constructor_diagnostics;
#[path = "driver_folded_features.rs"]
mod folded_features;

/// One immutable resolver must include the selected scalar constant overlay,
/// engine constants and captured resources. No filesystem access occurs here.
pub struct DriverEvaluator<'a> {
    pub pure_calls: Option<&'a dyn dm_tree::constants::PureCalls>,
    pub resource_search_context: Option<u128>,
    pub resolver: &'a dyn Resolver,
    pub symbols: &'a dm_ir::SymbolTable,
}
#[derive(Clone, Copy, Eq, PartialEq, Hash)]
enum ActiveConstant {
    ProcedureStatic(dm_ir::ProcedureStaticIdentity),
    Declaration { owner: SymbolId, name: SymbolId },
}
fn scalar_constant(value: SemanticValue, symbols: &dm_ir::SymbolTable) -> Option<Constant> {
    Some(match value {
        SemanticValue::Null => Constant::Null,
        SemanticValue::NumberBits(bits) => Constant::Number(f32::from_bits(bits)),
        SemanticValue::Text(bytes) => Constant::EncodedText(bytes.to_vec()),
        SemanticValue::Type(path) => Constant::TypePath(symbols.text(path)?.into()),
        SemanticValue::Resource(path) => Constant::Resource(path),
        SemanticValue::Procedure(procedure) => Constant::Procedure(procedure),
        SemanticValue::ModifiedInstance(descriptor) => Constant::ModifiedInstance(descriptor),
        SemanticValue::List(_) => return None,
    })
}
impl DriverEvaluator<'_> {
    fn instance_call_error(
        &self,
        write: &dm_ir::InitializerWrite,
        ast: &dm_syntax::Expr,
    ) -> Option<String> {
        if !matches!(write.target, dm_ir::InitializerTarget::Instance { .. })
            || write.lexical_procedure.is_some()
        {
            return None;
        }
        fn authored(
            evaluator: &DriverEvaluator<'_>,
            owner: SymbolId,
            node: &dm_syntax::Expr,
        ) -> bool {
            if let dm_syntax::ExprKind::Call { callee, .. } = &node.kind {
                if let dm_syntax::ExprKind::Ident(name) = &callee.kind {
                    if !dm_codegen_byond::is_intrinsic_named_call(name) {
                        let name = SymbolId::of(name);
                        let member = evaluator.resolver.resolve(ResolveQuery::Proc {
                            owner,
                            name,
                            verb: false,
                        });
                        if matches!(member, ResolvedMeaning::Member { ref data, .. } if data.procedure.is_some())
                        {
                            return true;
                        }
                        // Missing is the only proof that member precedence permits
                        // selecting the global declaration. Opaque answers decline.
                        if matches!(member, ResolvedMeaning::Missing)
                            && matches!(evaluator.resolver.resolve(ResolveQuery::GlobalProc(name)), ResolvedMeaning::Member { ref data, .. } if data.procedure.is_some())
                        {
                            return true;
                        }
                    }
                }
            }
            let mut found = false;
            dm_syntax::for_each_expression_child(node, |_, child| {
                if !found {
                    found = authored(evaluator, owner, child);
                }
            });
            found
        }
        authored(self, write.lexical_owner, ast).then(|| match write.source_site {
            dm_ir::InitializerSite::Declaration => "=: expected a constant expression".to_owned(),
            dm_ir::InitializerSite::Assignment => ": expected a constant expression".to_owned(),
        })
    }

    fn declaration_scalar(
        &self,
        owner: SymbolId,
        name: SymbolId,
        data: &dm_ir::DeclarationMeaning,
        active: &RefCell<std::collections::HashSet<ActiveConstant>>,
        qualified_initial: bool,
    ) -> Result<Option<SemanticValue>, String> {
        if data.inherited_opaque.is_some() || (!qualified_initial && data.flags & 2 == 0) {
            return Err("declaration constant metadata is not certified".into());
        }
        if let Some(value) = &data.resolved_constant {
            return Ok(Some(value.clone()));
        }
        let expression = data
            .initializer
            .as_ref()
            .ok_or("constant declaration has no captured initializer")?;
        let key = ActiveConstant::Declaration { owner, name };
        if !active.borrow_mut().insert(key) {
            return Err(format!("declaration constant cycle at {owner:?}/{name:?}"));
        }
        let result = self.scalar_in(owner, expression, None, active);
        active.borrow_mut().remove(&key);
        result
    }
    fn scalar(
        &self,
        owner: SymbolId,
        expression: &SymbolicExpression,
    ) -> Result<Option<SemanticValue>, String> {
        self.scalar_in(
            owner,
            expression,
            None,
            &RefCell::new(std::collections::HashSet::new()),
        )
    }
    fn scalar_in(
        &self,
        owner: SymbolId,
        expression: &SymbolicExpression,
        procedure: Option<dm_ir::ProcedureIdentity>,
        active: &RefCell<std::collections::HashSet<ActiveConstant>>,
    ) -> Result<Option<SemanticValue>, String> {
        let text = expression
            .source_text(self.symbols)
            .ok_or("expression spelling is not captured")?;
        #[cfg(test)]
        SCALAR_TEXT_PARSES.with(|n| n.set(n.get() + 1));
        let parsed = dm_syntax::parse_expression(&text);
        if !parsed.diagnostics.is_empty() {
            return Err("captured scalar expression failed parsing".into());
        }
        let Some(ast) = parsed.expr.as_ref() else {
            return Ok(None);
        };
        self.scalar_ast_in(owner, ast, procedure, active)
    }
    fn scalar_ast_in(
        &self,
        owner: SymbolId,
        ast: &dm_syntax::Expr,
        procedure: Option<dm_ir::ProcedureIdentity>,
        active: &RefCell<std::collections::HashSet<ActiveConstant>>,
    ) -> Result<Option<SemanticValue>, String> {
        self.scalar_ast_in_with_features(owner, ast, procedure, active, None, None, None)
    }
    fn scalar_ast_in_with_features(
        &self,
        owner: SymbolId,
        ast: &dm_syntax::Expr,
        procedure: Option<dm_ir::ProcedureIdentity>,
        active: &RefCell<std::collections::HashSet<ActiveConstant>>,
        source_features: Option<&RefCell<dm_codegen_byond::SourceFeatures>>,
        lexical_static: Option<dm_ir::ProcedureStaticIdentity>,
        typed_failure: Option<&RefCell<Option<folded_features::FoldedReferenceFailure>>>,
    ) -> Result<Option<SemanticValue>, String> {
        if let dm_syntax::ExprKind::ObjectInitializer { object, fields } = &ast.kind {
            let dm_syntax::ExprKind::TypePath(path) = &object.kind else {
                return Err("modified default requires an explicit type path".into());
            };
            let id = SymbolId::of(path.trim_end_matches('/'));
            match self.resolver.resolve(ResolveQuery::RuntimeType(id)) {
                ResolvedMeaning::Symbol(actual) if actual == id => (),
                _ => return Err("modified default runtime type is not positively captured".into()),
            }
            let feature_failure = RefCell::new(None);
            let observe_nameof = |expression: &dm_syntax::Expr| {
                if let Some(features) = source_features {
                    match self.nameof_source_features(
                        owner,
                        procedure,
                        lexical_static,
                        expression,
                        typed_failure,
                    ) {
                        Ok(current) => features.borrow_mut().union(current),
                        Err(error) => *feature_failure.borrow_mut() = Some(error),
                    }
                }
            };
            let observer = source_features.map(|_| &observe_nameof as &dyn Fn(&dm_syntax::Expr));
            let descriptor =
                dm_ir::ModifiedInstance::capture_with_resources_and_nameof_observer_checked(
                    id,
                    owner,
                    self.resource_search_context,
                    fields,
                    |raw| {
                        dm_codegen_byond::decode_native_constant_string_literal(raw)
                            .ok()
                            .flatten()
                    },
                    self.pure_calls,
                    |path| {
                        let search_context = self
                            .resource_search_context
                            .ok_or("modified resource scalar has no captured search context")?;
                        let query = ResolveQuery::ResourceIn {
                            path: SymbolId::of(path),
                            search_context: search_context.into(),
                        };
                        match self.resolver.resolve(query) {
                        ResolvedMeaning::Resource { path, content } => {
                            Ok(dm_ir::CapturedModifiedResource { path, content: content.get() })
                        }
                        _ => Err(
                            "modified resource scalar has no positive captured payload identity"
                                .into(),
                        ),
                    }
                    },
                    observer,
                )
                .map_err(|error| {
                    if error == dm_ir::ModifiedCaptureError::InvalidNameofReference {
                        if let Some(failure) = typed_failure {
                            *failure.borrow_mut() = Some(folded_features::FoldedReferenceFailure {
                                recovery: Some(dm_codegen_byond::NameofDiagnosticRecovery::ModifiedReferenceRequired),
                                error: dm_codegen_byond::LowerError {
                                    kind: dm_codegen_byond::LowerErrorKind::SourceError,
                                    reason: error.to_string(),
                                    ..Default::default()
                                },
                            });
                        }
                    }
                    error.to_string()
                });
            // Preserve descriptor source failures for evaluate_prepared_write,
            // while opaque resource/policy failures keep their original class.
            let descriptor = descriptor?;
            if let Some(error) = feature_failure.into_inner() {
                return Err(error);
            }
            return Ok(Some(SemanticValue::ModifiedInstance(Arc::new(descriptor))));
        }
        let failure = RefCell::new(None);
        let observe_nameof = |expr: &dm_syntax::Expr| {
            if let Some(features) = source_features {
                match self.nameof_source_features(
                    owner,
                    procedure,
                    lexical_static,
                    expr,
                    typed_failure,
                ) {
                    Ok(observed) => features.borrow_mut().union(observed),
                    Err(error) => *failure.borrow_mut() = Some(error),
                }
            }
        };
        let observer = source_features.map(|_| &observe_nameof as &dyn Fn(&dm_syntax::Expr));
        let result = dm_tree::constants::evaluate_expr_with_resources_and_calls_and_nameof_observer(
            ast,
            |name| {
                let unqualified = !name.contains("::");
                let (scope, name) = name
                    .rsplit_once("::")
                    .map_or((owner, name), |(path, name)| (SymbolId::of(path), name));
                if let Some(procedure) = procedure.filter(|_| scope == owner && unqualified) {
                    match self.resolver.resolve(ResolveQuery::ProcedureStatic {
                        procedure,
                        name: SymbolId::of(name),
                    }) {
                        ResolvedMeaning::ProcedureStatic(declaration) => {
                            if declaration.identity
                                != (dm_ir::ProcedureStaticIdentity {
                                    procedure,
                                    name: SymbolId::of(name),
                                })
                            {
                                *failure.borrow_mut() = Some(
                                    "static constant answer belongs to another lexical slot".into(),
                                );
                                return None;
                            }
                            if declaration.modifiers & 2 == 0 {
                                return None;
                            }
                            let dm_ir::InitializerValue::Expression(value) =
                                &declaration.initializer
                            else {
                                *failure.borrow_mut() =
                                    Some("static constant has no scalar expression".into());
                                return None;
                            };
                            let inserted = active
                                .borrow_mut()
                                .insert(ActiveConstant::ProcedureStatic(declaration.identity));
                            if !inserted {
                                *failure.borrow_mut() = Some(format!(
                                    "procedure static constant cycle at {:?}",
                                    declaration.identity
                                ));
                                return None;
                            }
                            let result = self.scalar_in(owner, value, Some(procedure), active);
                            active
                                .borrow_mut()
                                .remove(&ActiveConstant::ProcedureStatic(declaration.identity));
                            return match result {
                                Ok(Some(SemanticValue::Null)) => Some(Constant::Null),
                                Ok(Some(SemanticValue::Resource(path))) => {
                                    Some(Constant::Resource(path))
                                }
                                Ok(Some(SemanticValue::NumberBits(bits))) => {
                                    Some(Constant::Number(f32::from_bits(bits)))
                                }
                                Ok(Some(SemanticValue::Text(bytes))) => {
                                    Some(Constant::EncodedText(bytes.to_vec()))
                                }
                                Ok(Some(SemanticValue::Procedure(procedure))) => {
                                    Some(Constant::Procedure(procedure))
                                }
                                Ok(Some(SemanticValue::ModifiedInstance(descriptor))) => {
                                    Some(Constant::ModifiedInstance(descriptor))
                                }
                                Ok(Some(SemanticValue::Type(path))) => self
                                    .symbols
                                    .text(path)
                                    .map(|text| Constant::TypePath(text.into())),
                                Ok(_) => {
                                    *failure.borrow_mut() =
                                        Some("static constant is not scalar".into());
                                    None
                                }
                                Err(error) => {
                                    *failure.borrow_mut() = Some(error);
                                    None
                                }
                            };
                        }
                        ResolvedMeaning::Missing => {}
                        other => {
                            *failure.borrow_mut() =
                                Some(format!("static lexical inventory unavailable: {other:?}"));
                            return None;
                        }
                    }
                }
                let query = ResolveQuery::Constant {
                    owner: scope,
                    name: SymbolId::of(name),
                };
                let answer = self.resolver.resolve(query);
                let value = match answer {
                    ResolvedMeaning::Value(value) => value,
                    ResolvedMeaning::Member { data, .. } if data.resolved_constant.is_some() => {
                        data.resolved_constant.as_ref().unwrap().clone()
                    }
                    // Exact lexical positives shadow globals. Only certified
                    // lexical absence permits unqualified global fallback.
                    other @ (ResolvedMeaning::Unsupported(_) | ResolvedMeaning::Missing) => {
                        let lexical = self.resolver.resolve(ResolveQuery::Var {
                            owner: scope,
                            name: SymbolId::of(name),
                        });
                        let fallback = match lexical {
                            ResolvedMeaning::Member {
                                owner, name, data, ..
                            } => {
                                if unqualified
                                    && data.inherited_opaque.is_none()
                                    && data.flags & 2 == 0
                                {
                                    return None;
                                }
                                return match self.declaration_scalar(
                                    owner,
                                    name,
                                    &data,
                                    active,
                                    !unqualified,
                                ) {
                                    Ok(Some(value)) => scalar_constant(value, self.symbols),
                                    Ok(None) => {
                                        *failure.borrow_mut() =
                                            Some("constant initializer is not scalar".into());
                                        None
                                    }
                                    Err(error) => {
                                        *failure.borrow_mut() = Some(error);
                                        None
                                    }
                                };
                            }
                            ResolvedMeaning::Missing if unqualified => self
                                .resolver
                                .resolve(ResolveQuery::GlobalVar(SymbolId::of(name))),
                            ResolvedMeaning::Missing => ResolvedMeaning::Missing,
                            lexical => {
                                *failure.borrow_mut() = Some(format!(
                                    "lexical constant {name} is unavailable: {lexical:?}"
                                ));
                                return None;
                            }
                        };
                        match fallback {
                            ResolvedMeaning::Member {
                                owner, name, data, ..
                            } => {
                                if data.inherited_opaque.is_none() && data.flags & 2 == 0 {
                                    return None;
                                }
                                return match self
                                    .declaration_scalar(owner, name, &data, active, false)
                                {
                                    Ok(Some(value)) => scalar_constant(value, self.symbols),
                                    Ok(None) => {
                                        *failure.borrow_mut() = Some(
                                            "global constant initializer is not scalar".into(),
                                        );
                                        None
                                    }
                                    Err(error) => {
                                        *failure.borrow_mut() = Some(error);
                                        None
                                    }
                                };
                            }
                            ResolvedMeaning::Value(value) => value,
                            ResolvedMeaning::Missing if unqualified && name == "__TYPE__" => {
                                // Only certified absence in static, lexical and global
                                // namespaces permits the lexical intrinsic fallback.
                                // Final TypePath admission records a positive Type query.
                                if owner == SymbolId::of("/") {
                                    return Some(Constant::Null);
                                }
                                return match self.symbols.text(owner) {
                                    Some(path) => Some(Constant::TypePath(path.into())),
                                    None => {
                                        *failure.borrow_mut() = Some(
                                            "__TYPE__ lexical owner spelling is not captured"
                                                .into(),
                                        );
                                        None
                                    }
                                };
                            }
                            ResolvedMeaning::Missing if unqualified => match self
                                .resolver
                                .resolve(ResolveQuery::PredefinedConstant(SymbolId::of(name)))
                            {
                                ResolvedMeaning::Value(value) => value,
                                _ => {
                                    *failure.borrow_mut() =
                                        Some(format!("constant {name} is not captured: {other:?}"));
                                    return None;
                                }
                            },
                            fallback => {
                                *failure.borrow_mut() = Some(format!(
                                    "constant {name} fallback is unavailable: {fallback:?}"
                                ));
                                return None;
                            }
                        }
                    }
                    other => {
                        *failure.borrow_mut() =
                            Some(format!("constant query is unsupported: {other:?}"));
                        return None;
                    }
                };
                match value {
                    SemanticValue::Null => Some(Constant::Null),
                    SemanticValue::Resource(path) => Some(Constant::Resource(path)),
                    SemanticValue::NumberBits(bits) => Some(Constant::Number(f32::from_bits(bits))),
                    SemanticValue::Text(bytes) => Some(Constant::EncodedText(bytes.to_vec())),
                    SemanticValue::Procedure(procedure) => Some(Constant::Procedure(procedure)),
                    SemanticValue::ModifiedInstance(descriptor) => {
                        Some(Constant::ModifiedInstance(descriptor))
                    }
                    SemanticValue::Type(path) => self
                        .symbols
                        .text(path)
                        .map(|path| Constant::TypePath(path.into())),
                    _ => {
                        *failure.borrow_mut() = Some("constant value is not scalar".into());
                        None
                    }
                }
            },
            |raw| match dm_codegen_byond::decode_native_constant_string_literal(raw) {
                Ok(value) => value,
                Err(error) => {
                    *failure.borrow_mut() = Some(error);
                    None
                }
            },
            |expr| dm_codegen_byond::nameof_reference(expr).map(str::to_owned),
            |raw| {
                let path = raw
                    .strip_prefix('\'')
                    .and_then(|path| path.strip_suffix('\''))?;
                if path.contains(['\0', '\'', '[', ']']) {
                    *failure.borrow_mut() =
                        Some("resource literal requires captured decoder".into());
                    return None;
                }
                let Some(search_context) = self.resource_search_context else {
                    *failure.borrow_mut() =
                        Some("resource scalar has no captured search context".into());
                    return None;
                };
                let path = SymbolId::of(path);
                let query = ResolveQuery::ResourceIn {
                    path,
                    search_context: search_context.into(),
                };
                match self.resolver.resolve(query) {
                    ResolvedMeaning::Resource { path: found, .. } if found == path => Some(path),
                    other => {
                        *failure.borrow_mut() =
                            Some(format!("resource scalar is not captured: {other:?}"));
                        None
                    }
                }
            },
            self.pure_calls,
            observer,
        );
        if let Some(error) = failure.into_inner() {
            return Err(error);
        }
        let value = result
            .map_err(|error| format!("pure call {} rejected: {}", error.name, error.reason))?;
        Ok(match value {
            None => None,
            Some(Constant::Null) => Some(SemanticValue::Null),
            Some(Constant::Resource(path)) => Some(SemanticValue::Resource(path)),
            Some(Constant::Procedure(procedure)) => Some(SemanticValue::Procedure(procedure)),
            Some(Constant::ModifiedInstance(descriptor)) => {
                Some(SemanticValue::ModifiedInstance(descriptor))
            }
            Some(Constant::Number(number)) => Some(SemanticValue::NumberBits(number.to_bits())),
            Some(Constant::Text(text)) => Some(SemanticValue::Text(text.into_bytes().into())),
            Some(Constant::EncodedText(bytes)) => Some(SemanticValue::Text(bytes.into())),
            Some(Constant::TypePath(path)) => {
                if let Some(query) = dm_tree::constants::procedure_literal_query(&path) {
                    return match self.resolver.resolve(query) {
                        ResolvedMeaning::Value(value @ SemanticValue::Procedure(_)) => {
                            Ok(Some(value))
                        }
                        answer => Err(format!(
                            "procedure literal {path} is not positively captured: {answer:?}"
                        )),
                    };
                }
                let id = SymbolId::of(&path);
                if self.symbols.text(id) != Some(path.as_str())
                    || !matches!(self.resolver.resolve(ResolveQuery::Type(id)), ResolvedMeaning::Symbol(found) if found == id)
                {
                    return Err(format!("type constant {path} is not positively captured"));
                }
                Some(SemanticValue::Type(id))
            }
        })
    }
}
/// Native setting-only adapter over the SAME existing scalar evaluator and
/// resolver (including artifact recording). Other expression domains deliberately
/// keep their explicit compatibility entry until their own original issuer lands.
pub(super) struct OriginalSettingEvaluator<'source, 'e, 'resolver> {
    pub(super) frontend: &'source ColdFrontend,
    pub(super) body: &'source dm_tree::frontend::BodyOccurrence,
    pub(super) metadata: &'source dm_ir::ProcedureMetadata,
    pub(super) evaluator: &'e DriverEvaluator<'resolver>,
    pub(super) lexical: bool,
}
impl OriginalSettingEvaluator<'_, '_, '_> {
    fn require_context(&self, context: &AbiContext<'_>) -> Result<(), AbiError> {
        let roster = self
            .frontend
            .callable_roster()
            .map_err(AbiError::unsupported)?;
        let ordinal = roster
            .ordinal(self.body.member)
            .ok_or_else(|| AbiError::invariant("original setting callable unavailable"))?;
        let id = roster
            .identity(ordinal)
            .ok_or_else(|| AbiError::invariant("original setting callable identity unavailable"))?;
        let issued = UnitIdentity {
            owner: id.owner,
            name: id.name,
            namespace: if id.verb {
                Namespace::Verb
            } else {
                Namespace::Proc
            },
            occurrence: id.occurrence,
        };
        if issued != context.identity {
            return Err(AbiError::invariant(
                "setting ABI context differs from original callable",
            ));
        }
        Ok(())
    }
}
impl CapturedConstantEvaluator for OriginalSettingEvaluator<'_, '_, '_> {
    fn evaluate_in_site(
        &self,
        site: dm_codegen_byond::procedure_abi::AbiExpressionSite,
        expression: &SymbolicExpression,
        context: &AbiContext<'_>,
    ) -> Result<SemanticValue, AbiError> {
        self.require_context(context)?;
        use dm_codegen_byond::procedure_abi::AbiExpressionSite as Site;
        match site {
            Site::Setting => self.evaluate(expression, context),
            Site::ReturnAnnotation => {
                if self.lexical {
                    LexicalAbiEvaluator(self.evaluator).evaluate(expression, context)
                } else {
                    CapturedConstantEvaluator::evaluate(self.evaluator, expression, context)
                }
            }
            Site::SettingCondition => Err(AbiError::unsupported(
                "native conditional setting metadata has no original source issuer",
            )),
        }
    }

    fn evaluate(
        &self,
        expression: &SymbolicExpression,
        context: &AbiContext<'_>,
    ) -> Result<SemanticValue, AbiError> {
        self.require_context(context)?;
        let root = self
            .frontend
            .setting_expression(self.body, self.metadata, expression)
            .map_err(|error| match error {
                dm_tree::frontend::BodySyntaxFailure::Operational(actual) => {
                    AbiError::operational(actual)
                }
                dm_tree::frontend::BodySyntaxFailure::Syntax(_) => {
                    AbiError::unsupported("captured scalar expression failed parsing")
                }
            })?;
        let procedure = self.lexical.then(|| dm_ir::ProcedureIdentity {
            owner: context.identity.owner,
            name: context.identity.name,
            verb: context.identity.namespace == Namespace::Verb,
            occurrence: context.identity.occurrence,
        });
        self.evaluator
            .scalar_ast_in(
                context.identity.owner,
                root.original_expression(),
                procedure,
                &RefCell::new(std::collections::HashSet::new()),
            )
            .map_err(AbiError::unsupported)?
            .ok_or_else(|| AbiError::unsupported("ABI setting is not a captured scalar"))
    }
}
impl CapturedConstantEvaluator for DriverEvaluator<'_> {
    fn evaluate(
        &self,
        expression: &SymbolicExpression,
        context: &AbiContext<'_>,
    ) -> Result<SemanticValue, AbiError> {
        self.scalar(context.identity.owner, expression)
            .map_err(AbiError::unsupported)?
            .ok_or_else(|| AbiError::unsupported("ABI setting is not a captured scalar"))
    }
}
/// Lexical procedure-static ABI evaluation is used only with a complete captured
/// StaticResolver inventory; its Missing answers permit ordinary constant lookup.
pub(super) struct LexicalAbiEvaluator<'a>(pub(super) &'a DriverEvaluator<'a>);
impl CapturedConstantEvaluator for LexicalAbiEvaluator<'_> {
    fn evaluate(
        &self,
        expression: &SymbolicExpression,
        context: &AbiContext<'_>,
    ) -> Result<SemanticValue, AbiError> {
        let procedure = dm_ir::ProcedureIdentity {
            owner: context.identity.owner,
            name: context.identity.name,
            verb: context.identity.namespace == Namespace::Verb,
            occurrence: context.identity.occurrence,
        };
        self.0
            .scalar_in(
                context.identity.owner,
                expression,
                Some(procedure),
                &RefCell::new(std::collections::HashSet::new()),
            )
            .map_err(AbiError::unsupported)?
            .ok_or_else(|| AbiError::unsupported("ABI setting is not a captured scalar"))
    }
}
impl crate::initializer_policy::InitializerEvaluatorFactory for DriverEvaluator<'_> {
    fn immutable_initializer_policy_bytes_for_engine(
        &self,
        _current: Option<&EngineSnapshot>,
    ) -> Option<Arc<[u8]>> {
        // DriverEvaluator has no hidden engine owner. The supplied engine is
        // applied by with_recording_evaluator and proved by the transport.
        self.immutable_initializer_policy_bytes()
    }

    fn immutable_initializer_policy_bytes(&self) -> Option<Arc<[u8]>> {
        // Bump this implementation domain whenever initializer evaluation
        // semantics change, independently of process-local recording tokens.
        let mut bytes =
            b"dmbc-driver-initializer-policy-v7;modified-nameof-source-class\0".to_vec();
        match self.pure_calls {
            None => bytes.push(0),
            Some(calls) => {
                let pure = calls.immutable_policy_bytes()?;
                bytes.push(1);
                bytes.extend_from_slice(&(pure.len() as u64).to_le_bytes());
                bytes.extend_from_slice(pure);
            }
        }
        Some(bytes.into())
    }

    fn recording_policy_identity(&self) -> Option<u128> {
        let pure = match self.pure_calls {
            None => 0,
            Some(calls) => calls.immutable_policy_identity()?,
        };
        Some(pure ^ 0x6a21_31c9_842a_9181_032c_bbec_672d_a910)
    }
    fn with_recording_evaluator(
        &self,
        engine: Option<&EngineSnapshot>,
        resolver: &dyn Resolver,
        operation: &mut dyn FnMut(&dyn CapturedInitializerEvaluator),
    ) -> bool {
        let evaluator = DriverEvaluator {
            pure_calls: self.pure_calls,
            resource_search_context: self.resource_search_context,
            resolver,
            symbols: self.symbols,
        };
        if let Some(engine) = engine {
            operation(&crate::initializer_policy::EngineCapturedEvaluator {
                engine,
                evaluator: &evaluator,
            });
        } else {
            operation(&evaluator);
        }
        true
    }
    fn with_evaluator(
        &self,
        engine: Option<&EngineSnapshot>,
        operation: &mut dyn FnMut(&dyn CapturedInitializerEvaluator),
    ) {
        let evaluator = DriverEvaluator {
            pure_calls: self.pure_calls,
            resource_search_context: self.resource_search_context,
            resolver: self.resolver,
            symbols: self.symbols,
        };
        if let Some(engine) = engine {
            operation(&crate::initializer_policy::EngineCapturedEvaluator {
                engine,
                evaluator: &evaluator,
            });
        } else {
            operation(&evaluator);
        }
    }
}
impl CapturedInitializerEvaluator for DriverEvaluator<'_> {
    fn initializer_intrinsic_constructor(
        &self,
        _write: &dm_ir::InitializerWrite,
        name: &str,
    ) -> bool {
        // These names are reserved constructors in the pinned compiler, not
        // callable namespace lookups. BYOND rejects authored procs with either
        // name, and code generation selects their constructor opcodes directly.
        // An incomplete engine callable catalog must not turn them into runtime
        // expressions without initializer markers.
        matches!(name, "file" | "icon")
    }
    fn parallel_evaluator(&self) -> Option<crate::initializer_policy::ParallelEvaluator<'_>> {
        Some(crate::initializer_policy::ParallelEvaluator {
            factory: self,
            engine: None,
        })
    }
    fn initializer_token_scalar(&self, value: &SemanticValue) -> Result<Vec<u8>, String> {
        let SemanticValue::Resource(path) = value else {
            return Ok(value.canonical_bytes());
        };
        let search_context = self
            .resource_search_context
            .ok_or("initializer resource identity lacks captured context")?;
        match self.resolver.resolve(ResolveQuery::ResourceIn {
            path: *path,
            search_context: search_context.into(),
        }) {
            ResolvedMeaning::Resource {
                path: found,
                content,
                ..
            } if found == *path => {
                let mut key = b"dm-initializer-resource-content-v1\0".to_vec();
                key.extend_from_slice(&content.to_le_bytes());
                Ok(key)
            }
            _ => Err("initializer resource token requires positive captured content".into()),
        }
    }
    fn initializer_constructor_type(
        &self,
        write: &dm_ir::InitializerWrite,
    ) -> Result<Option<SymbolId>, String> {
        let declared = self.declared_constructor_type(write)?;
        declared
            .map(
                |path| match self.resolver.resolve(ResolveQuery::RuntimeType(path)) {
                    ResolvedMeaning::Symbol(actual) => Ok(actual),
                    _ => Err("initializer constructor runtime type is not captured".into()),
                },
            )
            .transpose()
    }
    fn pure_calls(&self) -> Option<&dyn dm_tree::constants::PureCalls> {
        self.pure_calls
    }
    fn instance_storage(
        &self,
        write: &dm_ir::InitializerWrite,
    ) -> Result<Option<(SymbolId, SymbolId)>, String> {
        let dm_ir::InitializerTarget::Instance {
            declaring_owner,
            receiver_owner,
            name,
        } = write.target
        else {
            return Ok(None);
        };
        let query = ResolveQuery::VarStorage {
            owner: receiver_owner,
            name,
        };
        match self.resolver.resolve(query) {
            ResolvedMeaning::InstanceField {
                declaring_owner: actual_owner,
                name: actual_name,
            } if actual_owner == declaring_owner && actual_name == name => {
                Ok(Some((actual_owner, actual_name)))
            }
            ResolvedMeaning::Missing | ResolvedMeaning::Slot { .. } => Ok(None),
            answer => Err(format!(
                "initializer instance storage differs or is unavailable: {query:?}: {answer:?}"
            )),
        }
    }
    fn evaluate_write(
        &self,
        write: &dm_ir::InitializerWrite,
        expression: &SymbolicExpression,
    ) -> Result<Evaluation, String> {
        Ok(self.evaluate_prepared_write(write, expression)?.0)
    }
    fn evaluate_prepared_write(
        &self,
        write: &dm_ir::InitializerWrite,
        expression: &SymbolicExpression,
    ) -> Result<
        (
            Evaluation,
            Option<crate::initializer_policy::PreparedInitializerExpression>,
        ),
        String,
    > {
        let Some(mut prepared) =
            crate::initializer_policy::PreparedInitializerExpression::parse_captured(
                expression,
                self.symbols,
            )
            .map_err(|_| "captured scalar expression failed parsing".to_owned())?
        else {
            return Ok((Evaluation::Runtime, None));
        };
        let ast = prepared.ast();
        if let Some(reason) = self.instance_call_error(write, ast) {
            return Ok((Evaluation::SourceError(reason), Some(prepared)));
        }
        if let Some(reason) = self.constructor_reference_error(write, ast) {
            return Ok((Evaluation::SourceError(reason), Some(prepared)));
        }
        let source_features = RefCell::new(dm_codegen_byond::SourceFeatures::default());
        let typed_failure = RefCell::new(None);
        let result = self.scalar_ast_in_with_features(
            write.lexical_owner,
            ast,
            write.lexical_procedure,
            &RefCell::new(std::collections::HashSet::new()),
            Some(&source_features),
            match write.target {
                dm_ir::InitializerTarget::ProcedureStatic(identity) => Some(identity),
                _ => None,
            },
            Some(&typed_failure),
        );
        // The same observer records every resolver edge before classification.
        // Only a typed source failure can become an authored diagnostic; opaque
        // proof/evaluator failures retain the existing unsupported error path.
        let evaluation = match typed_failure.into_inner() {
            Some(failure)
                if failure.error.kind == dm_codegen_byond::LowerErrorKind::SourceError =>
            {
                match failure.recovery {
                    Some(recovery) => Evaluation::InvalidNameof(failure.error.reason, recovery),
                    None => Evaluation::SourceError(failure.error.reason),
                }
            }
            _ => result?.map_or(Evaluation::Runtime, Evaluation::Scalar),
        };
        prepared.set_source_features(source_features.into_inner());
        Ok((evaluation, Some(prepared)))
    }
    fn evaluate_ast_write(
        &self,
        write: &dm_ir::InitializerWrite,
        ast: &dm_syntax::Expr,
        _source: &str,
        _symbols: &dm_ir::SymbolTable,
    ) -> Result<Evaluation, String> {
        if let Some(reason) = self.instance_call_error(write, ast) {
            return Ok(Evaluation::SourceError(reason));
        }
        if let Some(reason) = self.constructor_reference_error(write, ast) {
            return Ok(Evaluation::SourceError(reason));
        }
        Ok(self
            .scalar_ast_in(
                write.lexical_owner,
                ast,
                write.lexical_procedure,
                &RefCell::new(std::collections::HashSet::new()),
            )?
            .map_or(Evaluation::Runtime, Evaluation::Scalar))
    }
    fn evaluate(
        &self,
        owner: SymbolId,
        expression: &SymbolicExpression,
    ) -> Result<Evaluation, String> {
        Ok(self
            .scalar(owner, expression)?
            .map_or(Evaluation::Runtime, Evaluation::Scalar))
    }
}

#[cfg(test)]
#[path = "driver_facts_tests.rs"]
mod tests;

#[cfg(test)]
#[path = "driver_qualified_initial_tests.rs"]
mod qualified_initial_tests;

#[cfg(test)]
#[path = "driver_modified_nameof_tests.rs"]
mod modified_nameof_tests;

#[cfg(test)]
thread_local! {static SCALAR_TEXT_PARSES:std::cell::Cell<usize>=const{std::cell::Cell::new(0)};}
#[cfg(test)]
mod original_setting_tests {
    use super::*;
    use dm_tree::frontend::{BodyOccurrence, BodySyntaxQueries, SettingExpressionQueries};
    use std::path::Path;
    struct Source<'a>(&'a str);
    impl dm_preprocess::SourceProvider for Source<'_> {
        fn read(&self, _: &Path) -> Result<String, String> {
            Ok(self.0.to_owned())
        }
    }
    fn attach(front: ColdFrontend, db: &Arc<crate::query_db::QueryDb>) -> ColdFrontend {
        let settings = Arc::clone(db) as Arc<dyn SettingExpressionQueries>;
        front
            .with_setting_expression_queries(&settings)
            .unwrap()
            .with_body_queries(Arc::clone(db) as Arc<dyn BodySyntaxQueries>)
    }
    fn front(source: &str, db: &Arc<crate::query_db::QueryDb>) -> ColdFrontend {
        attach(
            dm_tree::frontend::build(
                Path::new("original-settings.dme"),
                &Source(source),
                &Default::default(),
                1,
            )
            .unwrap(),
            db,
        )
    }
    fn selected(
        front: &ColdFrontend,
    ) -> (
        &BodyOccurrence,
        &dm_ir::ProcedureMetadata,
        &SymbolicExpression,
    ) {
        let body = front
            .bodies
            .iter()
            .find(|body| {
                front
                    .snapshot
                    .tree
                    .member(body.member)
                    .is_some_and(|m| m.name == SymbolId::of("p"))
            })
            .unwrap();
        let metadata = front
            .snapshot
            .tree
            .member(body.member)
            .unwrap()
            .metadata
            .procedure
            .as_deref()
            .unwrap();
        let dm_ir::ProcedureSettingNode::Setting(setting) = &metadata.settings[0] else {
            panic!("actual setting")
        };
        (body, metadata, &setting.value)
    }
    fn context<'a>(front: &'a ColdFrontend, body: &'a BodyOccurrence) -> AbiContext<'a> {
        let roster = front.callable_roster().unwrap();
        let index = roster.ordinal(body.member).unwrap();
        let id = roster.identity(index).unwrap();
        AbiContext {
            identity: UnitIdentity {
                owner: id.owner,
                name: id.name,
                namespace: if id.verb {
                    Namespace::Verb
                } else {
                    Namespace::Proc
                },
                occurrence: id.occurrence,
            },
            symbols: front.snapshot.tree.symbols(),
            origin: &body.source,
            resolver: front.snapshot.tree.as_ref(),
        }
    }
    fn body_root(front: &ColdFrontend) -> dm_syntax::SettingExpression {
        let archive = front.body_archive().unwrap();
        let ordinal = archive.body_index(selected(front).0.declaration).unwrap();
        let body = archive.parse_checked(ordinal).unwrap();
        let dm_syntax::StatementKind::ProjectedSet { value, .. } =
            &body.statement_body().parsed().statements[0].kind
        else {
            panic!("native body must expose explicit projected original setting")
        };
        value.clone()
    }
    #[test]
    fn projected_setting_modifier_refusal_does_not_block_executable_modifier_in_same_native_body() {
        for padding in ["", "// current source prefix\n\n"] {
            let source = format!(
                "{padding}/obj/base\n    var/amount = 0\n/proc/p()\n    set name = /obj/base{{amount=2}}\n    return (/obj/base{{amount=1}})\n"
            );
            let db = Arc::new(crate::query_db::QueryDb::default());
            let current = front(&source, &db);
            let (occurrence, _, _) = selected(&current);
            let arena = dm_tree::frontend::BodyArena::new_typed(
                &current,
                dm_codegen_byond::typed_statements_supported_for_capture,
            );
            arena.with_parsed_checked(occurrence, |parsed| {
                let statements = &parsed.statement_body().unwrap().parsed().statements;
                let dm_syntax::StatementKind::ProjectedSet { value: setting, .. } =
                    &statements[0].kind
                else { panic!("genuine native setting must retain its projected root") };
                assert!(matches!(setting.original_expression().kind,
                    dm_syntax::ExprKind::ObjectInitializer { .. }));
                let dm_syntax::StatementKind::Return(Some(value)) = &statements[1].kind
                else { panic!("independent executable return must remain available") };
                let executable = match &value.kind {
                    dm_syntax::ExprKind::Group(inner) => inner.as_ref(),
                    _ => value,
                };
                assert!(matches!(executable.kind, dm_syntax::ExprKind::ObjectInitializer { .. }));
                assert_ne!(setting.current_span(), executable.span);
                assert!(std::ptr::eq(parsed.object_initializer_at(executable.span)
                    .unwrap().unwrap(), executable));
                assert!(parsed.object_initializer_at(setting.current_span()).is_err(),
                    "a requested setting root cannot masquerade as a current executable Expr");
                assert!(std::ptr::eq(parsed.object_initializer_at(executable.span)
                    .unwrap().unwrap(), executable),
                    "specific projected refusal must not poison another executable lookup");
                assert!(parsed.object_initializer_at(dm_syntax::Span::new(0, 0)).unwrap().is_none());
            }).unwrap();
        }
    }
    #[test]
    fn native_setting_abi_first_and_body_first_share_original_root_without_scalar_text_parse() {
        for abi_first in [false, true] {
            let db = Arc::new(crate::query_db::QueryDb::default());
            let front = front("/proc/p()\n    set name = \"shared\"\n    return 1\n", &db);
            let (body, metadata, expression) = selected(&front);
            let context = context(&front, body);
            let driver = DriverEvaluator {
                pure_calls: None,
                resource_search_context: None,
                resolver: front.snapshot.tree.as_ref(),
                symbols: front.snapshot.tree.symbols(),
            };
            let native = OriginalSettingEvaluator {
                frontend: &front,
                body,
                metadata,
                evaluator: &driver,
                lexical: false,
            };
            let first_body = (!abi_first).then(|| body_root(&front));
            SCALAR_TEXT_PARSES.with(|n| n.set(0));
            let value = native.evaluate(expression, &context).unwrap();
            assert_eq!(
                SCALAR_TEXT_PARSES.with(|n| n.get()),
                0,
                "native top-level setting never calls source_text parse"
            );
            assert!(
                native.evaluate(&expression.clone(), &context).is_err(),
                "copied setting cannot select a compatibility fallback"
            );
            let foreign = AbiContext {
                identity: UnitIdentity {
                    owner: SymbolId::of("/datum/foreign"),
                    ..context.identity
                },
                ..context
            };
            let rejected = native.evaluate(expression, &foreign).unwrap_err();
            assert_eq!(
                rejected.kind,
                dm_codegen_byond::procedure_abi::AbiErrorKind::Invariant
            );
            assert_eq!(
                rejected.message,
                "setting ABI context differs from original callable"
            );
            assert_eq!(SCALAR_TEXT_PARSES.with(|n| n.get()), 0);
            let original = front
                .setting_expression(body, metadata, expression)
                .unwrap();
            let from_body = first_body.unwrap_or_else(|| body_root(&front));
            assert!(original.same_root(&from_body));
            let compatible = CapturedConstantEvaluator::evaluate(&driver, expression, &context).unwrap();
            assert_eq!(value, compatible);
            assert_eq!(
                SCALAR_TEXT_PARSES.with(|n| n.get()),
                1,
                "independent compatibility route remains real"
            );
        }
    }
    #[test]
    fn native_setting_midparse_cancel_is_operational_and_same_source_body_retry_recovers() {
        let db = Arc::new(crate::query_db::QueryDb::default());
        let front = front(
            "/proc/p()\n    set name = \"value [1 + 2]\"\n    return 1\n",
            &db,
        );
        let archive = front.body_archive().unwrap();
        let token = crate::daemon::control::Cancellation::default();
        let binding = crate::daemon::control::bind_with_deadline(
            token.clone(),
            std::time::Instant::now() + std::time::Duration::from_secs(300),
        );
        let scheduled = db.cancel_settings_after_checkpoints_for_test(12, token);
        let error = archive
            .parse_checked(0)
            .err()
            .expect("actual admitted setting work must observe cancellation");
        let dm_tree::frontend::BodySyntaxFailure::Operational(error) = error else {
            panic!("no syntax/cache error from cancellation")
        };
        assert_eq!(error.kind(), std::io::ErrorKind::Interrupted);
        assert_eq!(error.to_string(), "build superseded before publication");
        drop(scheduled);
        drop(binding);
        let complete = body_root(&front);
        let (body, metadata, value) = selected(&front);
        assert!(complete.same_root(&front.setting_expression(body, metadata, value).unwrap()));
        assert!(
            archive.parse_checked(0).is_ok(),
            "same Kind4 issuance must not retain operational rejection"
        );
    }
    #[test]
    fn native_setting_missing_provider_refuses_while_standalone_scalar_compatibility_stays_available(
    ) {
        let bare = dm_tree::frontend::build(
            Path::new("bare-setting.dme"),
            &Source("/proc/p()\n    set invisibility = 7\n"),
            &Default::default(),
            1,
        )
        .unwrap();
        let (body, metadata, value) = selected(&bare);
        let context = context(&bare, body);
        let driver = DriverEvaluator {
            pure_calls: None,
            resource_search_context: None,
            resolver: bare.snapshot.tree.as_ref(),
            symbols: bare.snapshot.tree.symbols(),
        };
        assert!(CapturedConstantEvaluator::evaluate(&driver, value, &context).is_ok());
        let error = OriginalSettingEvaluator {
            frontend: &bare,
            body,
            metadata,
            evaluator: &driver,
            lexical: false,
        }
        .evaluate(value, &context)
        .unwrap_err();
        assert_eq!(
            error.operational_error().unwrap().kind(),
            std::io::ErrorKind::NotConnected
        );
    }
    struct Includes {
        p: String,
        q: String,
    }
    impl dm_preprocess::SourceProvider for Includes {
        fn read(&self, path: &Path) -> Result<String, String> {
            Ok(match path.file_name().and_then(|n| n.to_str()) {
                Some("p.dm") => self.p.clone(),
                Some("q.dm") => self.q.clone(),
                _ => "#include \"q.dm\"\n#include \"p.dm\"\n".into(),
            })
        }
    }
    fn q_chunk(prefix: &str, value: u32) -> String {
        let closes = |header: &str| {
            header.bytes().fold(0xcbf29ce484222325u64, |h, b| {
                (h ^ u64::from(b)).wrapping_mul(0x100000001b3)
            }) & 15
                == 0
        };
        let tail = (0..)
            .map(|i| format!("/proc/q_tail{i}()"))
            .find(|h| closes(h))
            .unwrap();
        format!("{prefix}/proc/q()\n    return {value}\n{tail}\n    return {value}\n")
    }
    fn included(
        state: &mut dm_tree::frontend::RetainedSemanticTree,
        db: &Arc<crate::query_db::QueryDb>,
        q: String,
    ) -> ColdFrontend {
        let source = Includes {
            p: "/proc/p()\n    set name = 7\n    return 1\n".into(),
            q,
        };
        let executor = dm_exec::BuildExecutor::new(1).unwrap();
        attach(
            dm_tree::frontend::build_with_executor_and_semantic_state(
                Path::new("setting-offset.dme"),
                &source,
                &Default::default(),
                dm_tree::frontend::FrontendConfig {
                    workers: 1,
                    engine: None,
                    observer: None,
                },
                None,
                &executor,
                Some(state),
            )
            .unwrap(),
            db,
        )
    }
    #[derive(Debug)]
    struct CompatibilityBody;
    impl BodySyntaxQueries for CompatibilityBody {
        fn syntax(
            &self,
            input: &Arc<dm_tree::frontend::BodySyntaxInput>,
        ) -> Result<Arc<dm_tree::frontend::BodySyntax>, dm_tree::frontend::Diagnostic> {
            input.parse().map(Arc::new)
        }
    }
    #[test]
    fn warm_original_setting_body_and_scalar_keep_same_root_with_current_warning_coordinates() {
        let db = Arc::new(crate::query_db::QueryDb::default());
        let mut state = dm_tree::frontend::RetainedSemanticTree::default();
        let old = included(&mut state, &db, q_chunk("", 2));
        let old_root = body_root(&old);
        let current = included(
            &mut state,
            &db,
            q_chunk("// changed earlier include\n\n", 333),
        );
        let now = body_root(&current);
        assert!(old_root.same_root(&now));
        assert_ne!(old_root.current_offset(), now.current_offset());
        assert_eq!(old_root.original_expression(), now.original_expression());
        let (body, metadata, expression) = selected(&current);
        let context = context(&current, body);
        let evaluator = DriverEvaluator {
            pure_calls: None,
            resource_search_context: None,
            resolver: current.snapshot.tree.as_ref(),
            symbols: current.snapshot.tree.symbols(),
        };
        let scalar = OriginalSettingEvaluator {
            frontend: &current,
            body,
            metadata,
            evaluator: &evaluator,
            lexical: false,
        }
        .evaluate(expression, &context)
        .unwrap();
        assert_eq!(scalar, CapturedConstantEvaluator::evaluate(&evaluator, expression, &context).unwrap());
        assert!(now.same_root(
            &current
                .setting_expression(body, metadata, expression)
                .unwrap()
        ));
        let archive = current.body_archive().unwrap();
        let ordinal = archive.body_index(body.declaration).unwrap();
        let parsed = archive.parse_checked(ordinal).unwrap();
        let native = dm_analysis::checks_invalid_set::archived(
            &parsed,
            dm_analysis::checks::Severity::Error,
        )
        .unwrap();
        assert_eq!(native.len(), 1);
        assert_eq!(native[0].expression_span, now.current_span());
        assert_eq!(
            native[0].span,
            parsed.statement_body().parsed().statements[0].header_span
        );
        assert_eq!(
            &current.expanded.text[native[0].expression_span.range()],
            "7"
        );
        let compatible = current
            .clone()
            .with_body_queries(Arc::new(CompatibilityBody));
        let reference = compatible.body_archive().unwrap();
        let reference = reference.parse(ordinal).unwrap();
        let legacy = dm_analysis::checks_invalid_set::archived(
            &reference,
            dm_analysis::checks::Severity::Error,
        )
        .unwrap();
        assert_eq!(
            native, legacy,
            "same old judge and statement-anchor policy with current coordinates"
        );
        let mut native_rows = Vec::new();
        let mut compatibility_rows = Vec::new();
        dm_analysis::typed_body_jsonl::write_archived_jsonl(&parsed, &mut native_rows).unwrap();
        dm_analysis::typed_body_jsonl::write_archived_jsonl(&reference, &mut compatibility_rows)
            .unwrap();
        assert_eq!(
            native_rows, compatibility_rows,
            "complete current node rows/spans/schema stay identical"
        );
        assert!(current
            .setting_expression(&body.clone(), metadata, expression)
            .is_err());
        let copied = metadata.clone();
        assert!(current
            .setting_expression(body, &copied, expression)
            .is_err());
    }

    #[test]
    fn lazy_one_shot_statement_admission_shares_abi_root_without_body_query_attachment() {
        for abi_first in [false, true] {
            let db = Arc::new(crate::query_db::QueryDb::default());
            let provider = Arc::clone(&db) as Arc<dyn SettingExpressionQueries>;
            let front = dm_tree::frontend::build(
                Path::new("one-shot-settings.dme"),
                &Source("/proc/p()\n    set name = \"one\"\n    return 1\n"),
                &Default::default(),
                1,
            )
            .unwrap()
            .with_setting_expression_queries(&provider)
            .unwrap();
            let (body, metadata, expression) = selected(&front);
            let arena = dm_tree::frontend::BodyArena::new_typed(
                &front,
                dm_codegen_byond::typed_statements_supported_for_capture,
            );
            let direct = abi_first.then(|| {
                front
                    .setting_expression(body, metadata, expression)
                    .unwrap()
            });
            let from_body = arena
                .with_parsed_checked(body, |parsed| {
                    let dm_syntax::StatementKind::ProjectedSet { value, .. } =
                        &parsed.statement_body().unwrap().parsed().statements[0].kind
                    else {
                        panic!("one-shot native root must be projected explicitly")
                    };
                    value.clone()
                })
                .unwrap();
            let from_abi = direct.unwrap_or_else(|| {
                front
                    .setting_expression(body, metadata, expression)
                    .unwrap()
            });
            assert!(from_abi.same_root(&from_body));
            assert!(
                front.body_archive().unwrap().body_query_host().is_none(),
                "settings-only provider never attaches whole-body host"
            );
            let archive = front.body_archive().unwrap();
            let archived = archive.parse_checked(0).unwrap();
            let dm_syntax::StatementKind::ProjectedSet { value, .. } =
                &archived.statement_body().parsed().statements[0].kind
            else {
                panic!("checked archive must use attached native setting provider")
            };
            assert!(from_abi.same_root(value));
        }
    }
    #[test]
    fn lazy_one_shot_setting_cancel_never_fills_arena_and_same_source_retries() {
        let db = Arc::new(crate::query_db::QueryDb::default());
        let provider = Arc::clone(&db) as Arc<dyn SettingExpressionQueries>;
        let front = dm_tree::frontend::build(
            Path::new("one-shot-cancel.dme"),
            &Source("/proc/p()\n    set name = \"value [1 + 2]\"\n    return 1\n"),
            &Default::default(),
            1,
        )
        .unwrap()
        .with_setting_expression_queries(&provider)
        .unwrap();
        let (body, metadata, expression) = selected(&front);
        let arena = dm_tree::frontend::BodyArena::new_typed(
            &front,
            dm_codegen_byond::typed_statements_supported_for_capture,
        );
        let token = crate::daemon::control::Cancellation::default();
        let binding = crate::daemon::control::bind_with_deadline(
            token.clone(),
            std::time::Instant::now() + std::time::Duration::from_secs(300),
        );
        let scheduled = db.cancel_settings_after_checkpoints_for_test(12, token);
        let consumed = std::cell::Cell::new(false);
        let failed = arena.with_parsed_checked(body, |_| {
            consumed.set(true);
        });
        assert!(!consumed.get());
        assert!(
            matches!(failed,Err(dm_tree::frontend::BodySyntaxFailure::Operational(ref e)) if e.kind()==std::io::ErrorKind::Interrupted)
        );
        drop(scheduled);
        drop(binding);
        let root = arena
            .with_parsed_checked(body, |parsed| {
                let dm_syntax::StatementKind::ProjectedSet { value, .. } =
                    &parsed.statement_body().unwrap().parsed().statements[0].kind
                else {
                    panic!("successful retry must expose original root")
                };
                value.clone()
            })
            .unwrap();
        assert!(root.same_root(
            &front
                .setting_expression(body, metadata, expression)
                .unwrap()
        ));
    }
}
