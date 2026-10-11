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
        self.scalar_ast_in_with_features(owner, ast, procedure, active, None)
    }
    fn scalar_ast_in_with_features(
        &self,
        owner: SymbolId,
        ast: &dm_syntax::Expr,
        procedure: Option<dm_ir::ProcedureIdentity>,
        active: &RefCell<std::collections::HashSet<ActiveConstant>>,
        source_features: Option<&RefCell<dm_codegen_byond::SourceFeatures>>,
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
                    match self.nameof_source_features(owner, procedure, expression) {
                        Ok(current) => features.borrow_mut().union(current),
                        Err(error) => *feature_failure.borrow_mut() = Some(error),
                    }
                }
            };
            let observer = source_features.map(|_| &observe_nameof as &dyn Fn(&dm_syntax::Expr));
            let descriptor = dm_ir::ModifiedInstance::capture_with_resources_and_nameof_observer(
                id,
                owner,
                self.resource_search_context,
                fields,
                |raw| {
                    dm_codegen_byond::decode_constant_string_literal(raw)
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
                        search_context,
                    };
                    match self.resolver.resolve(query) {
                        ResolvedMeaning::Resource { path, content } => {
                            Ok(dm_ir::CapturedModifiedResource { path, content })
                        }
                        _ => Err(
                            "modified resource scalar has no positive captured payload identity"
                                .into(),
                        ),
                    }
                },
                observer,
            )?;
            if let Some(error) = feature_failure.into_inner() {
                return Err(error);
            }
            return Ok(Some(SemanticValue::ModifiedInstance(Arc::new(descriptor))));
        }
        let failure = RefCell::new(None);
        let observe_nameof = |expr: &dm_syntax::Expr| {
            if let Some(features) = source_features {
                match self.nameof_source_features(owner, procedure, expr) {
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
            |raw| match dm_codegen_byond::decode_constant_string_literal(raw) {
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
                    search_context,
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
            b"dmbc-driver-initializer-policy-v5;nameof-current-reference-admission\0".to_vec();
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
        Some(pure ^ 0x6a21_31c9_842a_9181_032c_bbec_672d_a909)
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
            search_context,
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
        let evaluation = self
            .scalar_ast_in_with_features(
                write.lexical_owner,
                ast,
                write.lexical_procedure,
                &RefCell::new(std::collections::HashSet::new()),
                Some(&source_features),
            )?
            .map_or(Evaluation::Runtime, Evaluation::Scalar);
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
