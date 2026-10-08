//! Captured CLI policy adapter prototype. Not exported until inherited absence
//! coverage and resource capture are supplied by the production discovery stage.
use crate::{
    engine::EngineSnapshot,
    initializer_policy::{CapturedInitializerEvaluator, Evaluation},
    lowering::{Namespace, UnitIdentity},
    procedure_policy::{
        AbiContext, CapturedConstantEvaluator, CapturedInheritedFacts, InheritedLayout,
    },
};
use dm_codegen_byond::procedure_abi::{AbiError, ProcLayout};
use dm_ir::{ResolveQuery, ResolvedMeaning, Resolver, SemanticValue, SymbolId, SymbolicExpression};
use dm_tree::{constants::Constant, frontend::ColdFrontend, MemberId, MemberKind};
use std::{
    cell::RefCell,
    collections::{BTreeMap, HashMap},
    sync::Arc,
};

/// Configuration captured before compilation. All policy views borrow these
/// same immutable hosts; resource context is issued by discovery, not filenames.
pub struct DriverFacts<'a> {
    pub evaluator: DriverEvaluator<'a>,
    pub inherited: DriverInheritedFacts<'a>,
    pub resource_search_context: Option<u128>,
}
impl DriverFacts<'_> {
    pub fn procedure_policy(&self) -> crate::procedure_policy::CapturedProcedurePolicy<'_> {
        crate::procedure_policy::CapturedProcedurePolicy {
            evaluator: &self.evaluator,
            inherited: &self.inherited,
            resource_search_context: self.resource_search_context,
        }
    }
    pub fn initializer_evaluator(&self) -> crate::initializer_policy::EngineCapturedEvaluator<'_> {
        crate::initializer_policy::EngineCapturedEvaluator {
            engine: self.inherited.engine,
            evaluator: &self.evaluator,
        }
    }
}

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
    fn declaration_scalar(
        &self,
        owner: SymbolId,
        name: SymbolId,
        data: &dm_ir::DeclarationMeaning,
        active: &RefCell<std::collections::HashSet<ActiveConstant>>,
    ) -> Result<Option<SemanticValue>, String> {
        if data.inherited_opaque.is_some() || data.flags & 2 == 0 {
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
        if let dm_syntax::ExprKind::ObjectInitializer { object, fields } = &ast.kind {
            let dm_syntax::ExprKind::TypePath(path) = &object.kind else {
                return Err("modified default requires an explicit type path".into());
            };
            let id = SymbolId::of(path.trim_end_matches('/'));
            match self.resolver.resolve(ResolveQuery::RuntimeType(id)) {
                ResolvedMeaning::Symbol(actual) if actual == id => (),
                _ => return Err("modified default runtime type is not positively captured".into()),
            }
            let descriptor = dm_ir::ModifiedInstance::capture_with_resources(
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
            )?;
            return Ok(Some(SemanticValue::ModifiedInstance(Arc::new(descriptor))));
        }
        let failure = RefCell::new(None);
        let result = dm_tree::constants::evaluate_expr_with_resources_and_calls(
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
                                if data.inherited_opaque.is_none() && data.flags & 2 == 0 {
                                    return None;
                                }
                                return match self.declaration_scalar(owner, name, &data, active) {
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
                                return match self.declaration_scalar(owner, name, &data, active) {
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
            .map_err(AbiError)?
            .ok_or_else(|| AbiError("ABI setting is not a captured scalar".into()))
    }
}
/// Lexical procedure-static ABI evaluation is used only with a complete captured
/// StaticResolver inventory; its Missing answers permit ordinary constant lookup.
struct LexicalAbiEvaluator<'a>(&'a DriverEvaluator<'a>);
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
            .map_err(AbiError)?
            .ok_or_else(|| AbiError("ABI setting is not a captured scalar".into()))
    }
}
impl CapturedInitializerEvaluator for DriverEvaluator<'_> {
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
        let query = match write.target {
            dm_ir::InitializerTarget::Shared { owner, name, .. } if owner == SymbolId::of("/") => {
                ResolveQuery::GlobalVar(name)
            }
            dm_ir::InitializerTarget::Shared { owner, name, .. } => {
                ResolveQuery::DeclaredVarType { owner, name }
            }
            dm_ir::InitializerTarget::Instance {
                receiver_owner: owner,
                name,
                ..
            } => ResolveQuery::DeclaredVarType { owner, name },
            dm_ir::InitializerTarget::ProcedureStatic(identity) => ResolveQuery::ProcedureStatic {
                procedure: identity.procedure,
                name: identity.name,
            },
        };
        let declared = match self.resolver.resolve(query) {
            ResolvedMeaning::DeclaredType(value) => value,
            ResolvedMeaning::Member { data, .. } if data.inherited_opaque.is_none() => {
                data.declared_type
            }
            ResolvedMeaning::ProcedureStatic(declaration) => declaration.declared_type,
            _ => return Err("initializer constructor declared type is not captured".into()),
        };
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
        Ok(self
            .scalar_in(
                write.lexical_owner,
                expression,
                write.lexical_procedure,
                &RefCell::new(std::collections::HashSet::new()),
            )?
            .map_or(Evaluation::Runtime, Evaluation::Scalar))
    }
    fn evaluate_ast_write(
        &self,
        write: &dm_ir::InitializerWrite,
        ast: &dm_syntax::Expr,
        _source: &str,
        _symbols: &dm_ir::SymbolTable,
    ) -> Result<Evaluation, String> {
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

/// Captured boundary facts are explicit; a missing entry never means Fresh.
/// Discovery must certify Fresh only with complete named-procedure absence.
pub enum BoundaryAbi {
    Fresh,
    CertifiedIntrinsic(CertifiedIntrinsicAbi),
    Engine {
        owner: SymbolId,
        name: SymbolId,
        kind: MemberKind,
    },
}
/// Positive finite native-control receipt; this is not semantic name absence.
pub struct CertifiedIntrinsicAbi {
    engine_identity: u128,
    owner: SymbolId,
    name: SymbolId,
    layout: ProcLayout,
}
impl CertifiedIntrinsicAbi {
    pub(crate) fn callback(
        engine: &EngineSnapshot,
        owner: SymbolId,
        name: SymbolId,
    ) -> Result<Self, AbiError> {
        const TEMPLATE: &[u8] = include_bytes!("../../../fixtures/native_template.bin");
        if !engine.matches_template(TEMPLATE, 1) {
            return Err(AbiError(
                "unsupported intrinsic ABI receipt template".into(),
            ));
        }
        let fact = crate::native_callbacks::lookup(owner, name)
            .ok_or_else(|| AbiError("unsupported intrinsic ABI receipt callback".into()))?;
        Ok(Self {
            engine_identity: engine.identity(),
            owner,
            name,
            layout: fact.layout(),
        })
    }
}
pub struct DriverInheritedFacts<'a> {
    pub frontend: &'a ColdFrontend,
    pub engine: &'a EngineSnapshot,
    /// Prepared ABI of actual previous source members, populated in dependency order.
    pub source_layouts: &'a HashMap<MemberId, ProcLayout>,
    pub boundaries: &'a BTreeMap<UnitIdentity, BoundaryAbi>,
    pub unit_members: &'a BTreeMap<UnitIdentity, MemberId>,
}
impl CapturedInheritedFacts for DriverInheritedFacts<'_> {
    fn inherited(&self, context: &AbiContext<'_>) -> Result<InheritedLayout, AbiError> {
        let tree = &self.frontend.snapshot.tree;
        let id = self
            .unit_members
            .get(&context.identity)
            .ok_or_else(|| AbiError("procedure is not in captured model".into()))?;
        let node = tree
            .member(*id)
            .ok_or_else(|| AbiError("indexed procedure member missing".into()))?;
        if let Some(previous) = node.previous {
            return self
                .source_layouts
                .get(&previous)
                .cloned()
                .map(InheritedLayout::Known)
                .ok_or_else(|| {
                    AbiError("previous source procedure ABI has not been prepared".into())
                });
        }
        match self.boundaries.get(&context.identity) {
            Some(BoundaryAbi::Fresh) => Ok(InheritedLayout::Fresh),
            Some(BoundaryAbi::CertifiedIntrinsic(receipt)) => {
                if receipt.engine_identity != self.engine.identity()
                    || receipt.name != node.name
                    || node.kind != MemberKind::Proc
                    || node.definition == dm_tree::DefinitionMode::Declare
                {
                    return Err(AbiError(
                        "intrinsic ABI receipt does not match current procedure".into(),
                    ));
                }
                let mut cursor = Some(node.owner);
                while let Some(id) = cursor {
                    if tree
                        .type_node(id)
                        .is_some_and(|ty| ty.path == receipt.owner)
                    {
                        return Ok(InheritedLayout::Known(receipt.layout.clone()));
                    }
                    cursor = tree.parent(id);
                }
                Err(AbiError(
                    "intrinsic ABI receipt is outside current ancestry".into(),
                ))
            }
            Some(BoundaryAbi::Engine { owner, name, kind }) => {
                if *name != node.name || *kind != node.kind {
                    return Err(AbiError(
                        "engine boundary names a different procedure".into(),
                    ));
                }
                let mut cursor = Some(node.owner);
                let mut contains = false;
                while let Some(id) = cursor {
                    contains |= tree.type_node(id).is_some_and(|ty| ty.path == *owner);
                    cursor = tree.parent(id);
                }
                if !contains {
                    return Err(AbiError(
                        "engine boundary is outside current ancestry".into(),
                    ));
                }
                self.engine
                    .procedure_layout(*owner, *name, *kind)
                    .map_err(|error| AbiError(format!("engine ABI: {error:?}")))?
                    .cloned()
                    .map(InheritedLayout::Known)
                    .ok_or_else(|| AbiError("selected engine ABI is not captured".into()))
            }
            None => Ok(InheritedLayout::Unsupported),
        }
    }
}

/// Exact source occurrence index built once, independently of source encounter
/// scheduling. Distinct formal/reopen identities cannot alias one prepared ABI.
pub fn unit_members(frontend: &ColdFrontend) -> Result<BTreeMap<UnitIdentity, MemberId>, AbiError> {
    let tree = &frontend.snapshot.tree;
    let mut result = BTreeMap::new();
    for body in frontend.bodies.iter() {
        let node = tree
            .member(body.member)
            .ok_or_else(|| AbiError("body member missing".into()))?;
        let owner = tree
            .type_node(node.owner)
            .ok_or_else(|| AbiError("body owner missing".into()))?
            .path;
        let namespace = match node.kind {
            MemberKind::Proc => Namespace::Proc,
            MemberKind::Verb => Namespace::Verb,
            MemberKind::Var => return Err(AbiError("variable body in procedure index".into())),
        };
        let occurrence = tree
            .override_chain(body.member)
            .iter()
            .filter(|id| {
                tree.member(**id).is_some_and(|prior| {
                    prior.owner == node.owner && prior.name == node.name && prior.kind == node.kind
                })
            })
            .count()
            .checked_sub(1)
            .ok_or_else(|| AbiError("empty procedure chain".into()))?;
        let identity = UnitIdentity {
            owner,
            name: node.name,
            namespace,
            occurrence: u32::try_from(occurrence)
                .map_err(|_| AbiError("procedure occurrence overflow".into()))?,
        };
        if result.insert(identity, body.member).is_some() {
            return Err(AbiError("ambiguous current procedure occurrence".into()));
        }
    }
    Ok(result)
}

pub struct PreparedSourceAbi {
    /// Encounter order, regardless of topological/worker completion order.
    pub units: Vec<(MemberId, crate::procedure_policy::PreparedUnit)>,
    pub diagnostics: Vec<(usize, String)>,
}
pub struct PreparedPinnedSourceAbi {
    pub policy_identity: u128,
    pub prepared: PreparedSourceAbi,
}
/// Preserve every failed unit's actual captured origin and cause. Preparation
/// stores encounter ordinals; these are never compiler-generated output IDs.
pub fn abi_diagnostics(
    frontend: &ColdFrontend,
    prepared: &PreparedSourceAbi,
) -> Result<Vec<crate::lowering::LoweringDiagnostic>, AbiError> {
    let identities: HashMap<_, _> = unit_members(frontend)?
        .into_iter()
        .map(|(unit, member)| (member, unit))
        .collect();
    let mut diagnostics = prepared
        .diagnostics
        .iter()
        .map(|(ordinal, message)| {
            let body = frontend.bodies.get(*ordinal).ok_or_else(|| {
                AbiError("ABI diagnostic body ordinal is outside captured frontend".into())
            })?;
            Ok(crate::lowering::LoweringDiagnostic {
                kind: dm_tree::frontend::DiagnosticKind::UnsupportedModel,
                identity: identities.get(&body.member).copied(),
                origin: body.source.clone(),
                message: message.clone(),
            })
        })
        .collect::<Result<Vec<_>, AbiError>>()?;
    diagnostics.sort_by_key(|diagnostic| {
        (
            diagnostic.origin.encounter_ordinal,
            diagnostic.origin.span.start,
        )
    });
    Ok(diagnostics)
}
/// Production constructor: dependency waves consume exact source predecessors
/// and pinned engine boundary certificates; callers cannot fill all rows Fresh.
pub fn prepare_pinned_source_abi(
    frontend: &ColdFrontend,
    engine: &EngineSnapshot,
    resolver: &dyn Resolver,
    resource_search_context: Option<u128>,
    workers: usize,
) -> Result<PreparedPinnedSourceAbi, AbiError> {
    let coverage =
        crate::engine_abi_coverage::NamedEngineCoverage::pinned(engine).map_err(AbiError)?;
    let policy_identity = coverage.policy_identity();
    let boundaries = coverage.boundaries(frontend).map_err(AbiError)?;
    let evaluator = DriverEvaluator {
        pure_calls: None,
        resource_search_context,
        resolver,
        symbols: frontend.snapshot.tree.symbols(),
    };
    let prepared = prepare_source_abi(
        frontend,
        engine,
        &evaluator,
        &boundaries,
        resource_search_context,
        workers,
    )?;
    Ok(PreparedPinnedSourceAbi {
        policy_identity,
        prepared,
    })
}
/// Production startup variant: settings and parameter scalar expressions resolve
/// lexical statics through the same captured inventory as executable lowering.
pub fn prepare_pinned_source_abi_with_startup<R: Resolver>(
    frontend: &ColdFrontend,
    engine: &EngineSnapshot,
    resolver: &R,
    startup: &crate::startup::CapturedStartup,
    resource_search_context: Option<u128>,
    workers: usize,
) -> Result<PreparedPinnedSourceAbi, AbiError> {
    startup.validate_for(frontend).map_err(AbiError)?;
    let static_resolver = startup.resolver(frontend, resolver).map_err(AbiError)?;
    let resolver = &static_resolver;
    let coverage =
        crate::engine_abi_coverage::NamedEngineCoverage::pinned(engine).map_err(AbiError)?;
    let policy_identity = coverage.policy_identity();
    let boundaries = coverage.boundaries(frontend).map_err(AbiError)?;
    let evaluator = DriverEvaluator {
        pure_calls: None,
        resource_search_context,
        resolver,
        symbols: startup.plan().symbols.as_ref(),
    };
    let prepared = prepare_source_abi_mode(
        frontend,
        engine,
        &evaluator,
        &boundaries,
        resource_search_context,
        workers,
        true,
    )?;
    Ok(PreparedPinnedSourceAbi {
        policy_identity,
        prepared,
    })
}
/// Dependency-ready waves borrow one immutable predecessor-layout map. A wave
/// never mutates that map while workers read it, and clones no project bindings.
/// Unsupported roots fail explicitly; their descendants cannot inherit defaults.
pub fn prepare_source_abi(
    frontend: &ColdFrontend,
    engine: &EngineSnapshot,
    evaluator: &DriverEvaluator<'_>,
    boundaries: &BTreeMap<UnitIdentity, BoundaryAbi>,
    resource_search_context: Option<u128>,
    workers: usize,
) -> Result<PreparedSourceAbi, AbiError> {
    prepare_source_abi_mode(
        frontend,
        engine,
        evaluator,
        boundaries,
        resource_search_context,
        workers,
        false,
    )
}

fn prepare_source_abi_mode(
    frontend: &ColdFrontend,
    engine: &EngineSnapshot,
    evaluator: &DriverEvaluator<'_>,
    boundaries: &BTreeMap<UnitIdentity, BoundaryAbi>,
    resource_search_context: Option<u128>,
    workers: usize,
    lexical_statics: bool,
) -> Result<PreparedSourceAbi, AbiError> {
    let index = unit_members(frontend)?;
    let identities: HashMap<_, _> = index.iter().map(|(key, id)| (*id, *key)).collect();
    let tree = &frontend.snapshot.tree;
    let mut layouts = HashMap::new();
    let mut remaining = vec![true; frontend.bodies.len()];
    let mut results: Vec<Option<crate::procedure_policy::PreparedUnit>> =
        (0..remaining.len()).map(|_| None).collect();
    let mut failures = BTreeMap::new();
    let body_ordinals: HashMap<_, _> = frontend
        .bodies
        .iter()
        .enumerate()
        .map(|(ordinal, body)| (body.member, ordinal))
        .collect();
    let mut dependents = vec![Vec::new(); frontend.bodies.len()];
    let mut ready = Vec::new();
    for (ordinal, body) in frontend.bodies.iter().enumerate() {
        let node = tree
            .member(body.member)
            .ok_or_else(|| AbiError("body member missing".into()))?;
        match node.previous {
            None => ready.push(ordinal),
            Some(previous) => {
                if let Some(predecessor) = body_ordinals.get(&previous) {
                    dependents[*predecessor].push(ordinal);
                }
            }
        }
    }
    while !ready.is_empty() {
        let inherited = DriverInheritedFacts {
            frontend,
            engine,
            source_layouts: &layouts,
            boundaries,
            unit_members: &index,
        };
        let lexical = LexicalAbiEvaluator(evaluator);
        let selected_evaluator: &dyn CapturedConstantEvaluator =
            if lexical_statics { &lexical } else { evaluator };
        let policy = crate::procedure_policy::CapturedProcedurePolicy {
            evaluator: selected_evaluator,
            inherited: &inherited,
            resource_search_context,
        };
        let worker_count = workers.clamp(1, 8).min(ready.len());
        let chunk = ready.len().div_ceil(worker_count);
        let wave = std::thread::scope(|scope| {
            let handles: Vec<_> = ready
                .chunks(chunk)
                .map(|ordinals| {
                    let policy = &policy;
                    let identities = &identities;
                    scope.spawn(move || {
                        let _profile = dm_profile::stage("cold.abi_preparation");
                        ordinals
                            .iter()
                            .map(|ordinal| {
                                let body = &frontend.bodies[*ordinal];
                                let result = (|| {
                                    let node = tree
                                        .member(body.member)
                                        .ok_or_else(|| AbiError("body member missing".into()))?;
                                    let metadata =
                                        node.metadata.procedure.as_ref().ok_or_else(|| {
                                            AbiError("procedure metadata unsupported".into())
                                        })?;
                                    let parsed = frontend.compact_body(body).map_err(|error| {
                                        AbiError(format!("body parse: {error:?}"))
                                    })?;
                                    let context = AbiContext {
                                        identity: identities[&body.member],
                                        symbols: evaluator.symbols,
                                        origin: &body.source,
                                        resolver: evaluator.resolver,
                                    };
                                    policy.prepare(metadata, parsed, &context)
                                })();
                                (*ordinal, result)
                            })
                            .collect::<Vec<_>>()
                    })
                })
                .collect();
            handles
                .into_iter()
                .map(|handle| {
                    handle
                        .join()
                        .map_err(|_| AbiError("ABI preparation worker panicked".into()))
                })
                .collect::<Result<Vec<_>, _>>()
        })?;
        ready.clear();
        for (ordinal, result) in wave.into_iter().flatten() {
            remaining[ordinal] = false;
            match result {
                Ok(unit) => {
                    let layout = unit.require_production_abi()?.layout.clone();
                    layouts.insert(frontend.bodies[ordinal].member, layout);
                    results[ordinal] = Some(unit);
                    ready.extend(dependents[ordinal].iter().copied());
                }
                Err(error) => {
                    failures.insert(ordinal, error.to_string());
                }
            }
        }
    }
    for (ordinal, pending) in remaining.into_iter().enumerate() {
        if pending {
            failures.insert(
                ordinal,
                "predecessor ABI unavailable, failed or cyclic".into(),
            );
        }
    }
    Ok(PreparedSourceAbi {
        units: results
            .into_iter()
            .enumerate()
            .filter_map(|(ordinal, result)| {
                result.map(|unit| (frontend.bodies[ordinal].member, unit))
            })
            .collect(),
        diagnostics: failures.into_iter().collect(),
    })
}

/// Immutable prepared-unit consumer for the existing lowering trait. Only this
/// unit's lexical inputs/body are cloned; inherited project maps stay borrowed.
pub struct FrozenPreparedPolicy<'a> {
    frontend: &'a ColdFrontend,
    prepared: &'a PreparedSourceAbi,
    by_identity: BTreeMap<UnitIdentity, usize>,
    members: BTreeMap<UnitIdentity, MemberId>,
    body_ordinals: HashMap<MemberId, usize>,
}
impl<'a> FrozenPreparedPolicy<'a> {
    pub fn new(
        frontend: &'a ColdFrontend,
        prepared: &'a PreparedSourceAbi,
    ) -> Result<Self, AbiError> {
        if !prepared.diagnostics.is_empty() {
            return Err(AbiError(
                "cannot lower a failed ABI preparation batch".into(),
            ));
        }
        let members = unit_members(frontend)?;
        let inverse: HashMap<_, _> = members
            .iter()
            .map(|(identity, member)| (*member, *identity))
            .collect();
        let mut by_identity = BTreeMap::new();
        for (index, (member, unit)) in prepared.units.iter().enumerate() {
            unit.require_production_abi()?;
            let identity = inverse
                .get(member)
                .ok_or_else(|| AbiError("prepared member belongs to another frontend".into()))?;
            if by_identity.insert(*identity, index).is_some() {
                return Err(AbiError("duplicate prepared member".into()));
            }
        }
        if by_identity.len() != members.len() {
            return Err(AbiError(
                "prepared ABI batch does not cover all bodies".into(),
            ));
        }
        let body_ordinals = frontend
            .bodies
            .iter()
            .enumerate()
            .map(|(ordinal, body)| (body.member, ordinal))
            .collect();
        Ok(Self {
            frontend,
            prepared,
            by_identity,
            members,
            body_ordinals,
        })
    }
    fn unit(
        &self,
        identity: UnitIdentity,
    ) -> Result<&crate::procedure_policy::PreparedUnit, String> {
        self.by_identity
            .get(&identity)
            .map(|index| &self.prepared.units[*index].1)
            .ok_or_else(|| "prepared ABI identity missing".into())
    }
    fn validate(
        &self,
        identity: UnitIdentity,
        metadata: &dm_ir::ProcedureMetadata,
        symbols: &dm_ir::SymbolTable,
        origin: &dm_tree::frontend::SourceLocation,
    ) -> Result<&dm_tree::frontend::BodyOccurrence, String> {
        if !symbols.is_extension_of(self.frontend.snapshot.tree.symbols()) {
            return Err("prepared ABI symbol snapshot changed".into());
        }
        let member = self
            .members
            .get(&identity)
            .ok_or("prepared ABI identity missing")?;
        let node = self
            .frontend
            .snapshot
            .tree
            .member(*member)
            .ok_or("prepared member missing")?;
        if node.metadata.procedure.as_deref() != Some(metadata) {
            return Err("prepared ABI metadata changed".into());
        }
        let ordinal = self
            .body_ordinals
            .get(member)
            .ok_or("prepared body missing")?;
        let body = &self.frontend.bodies[*ordinal];
        let source = &body.source;
        let macros_equal = source.macro_expansions.len() == origin.macro_expansions.len()
            && source
                .macro_expansions
                .iter()
                .zip(origin.macro_expansions.iter())
                .all(|(left, right)| {
                    left.name == right.name
                        && left.invocation_span == right.invocation_span
                        && left.replacement_chain == right.replacement_chain
                        && match (&left.definition, &right.definition) {
                            (None, None) => true,
                            (Some(left), Some(right)) => {
                                left.path == right.path
                                    && left.source_span == right.source_span
                                    && left.source_line == right.source_line
                            }
                            _ => false,
                        }
                });
        if source.span != origin.span
            || source.path != origin.path
            || source.semantic_path != origin.semantic_path
            || source.line != origin.line
            || source.encounter_ordinal != origin.encounter_ordinal
            || source.include_occurrence != origin.include_occurrence
            || source.include_chain != origin.include_chain
            || !macros_equal
        {
            return Err("prepared ABI source occurrence changed".into());
        }
        Ok(body)
    }
}
impl crate::lowering::AbiPolicy for FrozenPreparedPolicy<'_> {
    fn prepare_issued(
        &self,
        metadata: &dm_ir::ProcedureMetadata,
        input: &dm_tree::frontend::IssuedBodyInput<'_>,
        context: &AbiContext<'_>,
    ) -> Result<Option<crate::procedure_policy::PreparedReplay>, String> {
        let body = self.validate(context.identity, metadata, context.symbols, context.origin)?;
        self.frontend
            .validate_body_input(input, body)
            .map_err(|error| error.message)?;
        let unit = self.unit(context.identity)?;
        Ok(crate::procedure_policy::PreparedReplay::from_frozen(
            unit.inputs.clone(),
            Arc::clone(unit.abi.as_ref().ok_or("prepared production ABI missing")?),
        ))
    }
    fn prepare_captured(
        &self,
        metadata: &dm_ir::ProcedureMetadata,
        parsed: &dm_tree::frontend::ParsedBody<'_>,
        context: &AbiContext<'_>,
    ) -> Result<crate::procedure_policy::PreparedUnit, String> {
        let body = self.validate(context.identity, metadata, context.symbols, context.origin)?;
        self.frontend
            .validate_parsed_body(parsed, body)
            .map_err(|error| error.message)?;
        let unit = self.unit(context.identity)?;
        Ok(crate::procedure_policy::PreparedUnit {
            inputs: unit.inputs.clone(),
            executable_body: dm_tree::settings::strip_setting_items(parsed.item().children.clone()),
            abi: unit.abi.clone(),
        })
    }
    fn inputs(
        &self,
        identity: UnitIdentity,
        metadata: &dm_ir::ProcedureMetadata,
        symbols: &dm_ir::SymbolTable,
        origin: &dm_tree::frontend::SourceLocation,
    ) -> Result<dm_codegen_byond::ProcedureInputs, String> {
        self.validate(identity, metadata, symbols, origin)?;
        Ok(self.unit(identity)?.inputs.clone())
    }
    fn prepare(
        &self,
        metadata: &dm_ir::ProcedureMetadata,
        parsed: &dm_syntax::Item,
        context: &AbiContext<'_>,
    ) -> Result<crate::procedure_policy::PreparedUnit, String> {
        let body = self.validate(context.identity, metadata, context.symbols, context.origin)?;
        let captured = self
            .frontend
            .body(body)
            .map_err(|error| format!("prepared body capture: {error:?}"))?;
        if &captured != parsed {
            return Err("prepared ABI body differs from captured frontend".into());
        }
        let unit = self.unit(context.identity)?;
        Ok(crate::procedure_policy::PreparedUnit {
            inputs: unit.inputs.clone(),
            executable_body: dm_tree::settings::strip_setting_items(parsed.children.clone()),
            abi: unit.abi.clone(),
        })
    }
}

#[cfg(test)]
mod tests {
    #[test]
    fn initializer_instance_storage_requires_exact_receiver_and_declaring_tuple() {
        struct Storage {
            answer: ResolvedMeaning,
            reads: std::sync::Mutex<Vec<ResolveQuery>>,
        }
        impl Resolver for Storage {
            fn resolve(&self, query: ResolveQuery) -> ResolvedMeaning {
                self.reads.lock().unwrap().push(query);
                self.answer.clone()
            }
        }
        let owner = SymbolId::of("/atom");
        let receiver = SymbolId::of("/obj/subtype");
        let name = SymbolId::of("density");
        let write = dm_ir::InitializerWrite {
            target: dm_ir::InitializerTarget::Instance {
                declaring_owner: owner,
                receiver_owner: receiver,
                name,
            },
            lexical_owner: receiver,
            lexical_procedure: None,
            value: dm_ir::InitializerValue::NoAuthoredValue,
            declared_array: None,
            declaration_flags: None,
        };
        let query = ResolveQuery::VarStorage {
            owner: receiver,
            name,
        };
        let symbols = dm_ir::SymbolTable::default();
        for (answer, expected) in [
            (
                ResolvedMeaning::InstanceField {
                    declaring_owner: owner,
                    name,
                },
                Some(Some((owner, name))),
            ),
            (
                ResolvedMeaning::InstanceField {
                    declaring_owner: receiver,
                    name,
                },
                None,
            ),
            (
                ResolvedMeaning::InstanceField {
                    declaring_owner: owner,
                    name: SymbolId::of("other"),
                },
                None,
            ),
            (ResolvedMeaning::Missing, Some(None)),
            (
                ResolvedMeaning::Slot {
                    symbol: name,
                    owner,
                    name,
                },
                Some(None),
            ),
            (ResolvedMeaning::Unsupported(query), None),
        ] {
            let host = Storage {
                answer,
                reads: std::sync::Mutex::new(Vec::new()),
            };
            let evaluator = DriverEvaluator {
                pure_calls: None,
                resolver: &host,
                symbols: &symbols,
                resource_search_context: None,
            };
            let result = evaluator.instance_storage(&write);
            match expected {
                Some(value) => assert_eq!(result.as_ref().unwrap(), &value),
                None => assert!(result.is_err()),
            }
            assert_eq!(*host.reads.lock().unwrap(), [query]);
            assert_eq!(write.declaration_flags, None);
            let startup = crate::startup::StartupEvaluator {
                ordinary: &evaluator,
                resolver: &host,
                symbols: &symbols,
                resource_search_context: None,
            };
            assert_eq!(startup.instance_storage(&write), result);
        }
    }
    use super::*;
    use std::path::Path;
    struct Source;
    impl dm_preprocess::SourceProvider for Source {
        fn read(&self, _: &Path) -> Result<String, String> {
            // Descendant encountered first: scheduling must follow previous,
            // not source order. Public result order remains source order.
            Ok("/child\n    parent_type = /base\n/child/p()\n    return 2\n/base\n/base/proc/p()\n    set name = \"base display\"\n    return 1\n".into())
        }
    }
    fn frontend() -> ColdFrontend {
        dm_tree::frontend::build_with_config(
            Path::new("project.dme"),
            &Source,
            &Default::default(),
            dm_tree::frontend::FrontendConfig {
                workers: 1,
                engine: None,
                observer: None,
            },
        )
        .unwrap()
    }
    #[test]
    fn lexical_abi_constants_support_long_acyclic_chains_and_reject_exact_cycles() {
        let procedure = dm_ir::ProcedureIdentity {
            owner: SymbolId::of("/"),
            name: SymbolId::of("work"),
            verb: false,
            occurrence: 0,
        };
        for cyclic in [false, true] {
            let mut source = "/proc/work()\n".to_owned();
            for index in 0..72 {
                let value = if index == 0 {
                    if cyclic {
                        "c71".into()
                    } else {
                        "7".into()
                    }
                } else {
                    format!("c{}", index - 1)
                };
                source.push_str(&format!("    var/static/const/c{index} = {value}\n"));
            }
            source.push_str("    var/static/const/result = c71\n");
            let ast = dm_syntax::parse(&source);
            let captured =
                dm_tree::procedure_statics::capture(procedure, &ast.items[0].children).unwrap();
            let resolver = dm_tree::procedure_statics::StaticResolver::from_plans(
                &MissingHost,
                [(procedure, &captured)],
            )
            .unwrap();
            let evaluator = DriverEvaluator {
                pure_calls: None,
                resource_search_context: None,
                resolver: &resolver,
                symbols: &captured.symbols,
            };
            let declaration = captured
                .declarations
                .iter()
                .find(|declaration| declaration.identity.name == SymbolId::of("result"))
                .unwrap();
            let dm_ir::InitializerValue::Expression(expression) = &declaration.initializer else {
                panic!("expression");
            };
            let frontend = frontend();
            let context = AbiContext {
                identity: UnitIdentity {
                    owner: procedure.owner,
                    name: procedure.name,
                    namespace: Namespace::Proc,
                    occurrence: 0,
                },
                symbols: &captured.symbols,
                origin: &frontend.bodies[0].source,
                resolver: &resolver,
            };
            let answer = LexicalAbiEvaluator(&evaluator).evaluate(expression, &context);
            if cyclic {
                assert!(answer.unwrap_err().0.contains("constant cycle"));
            } else {
                assert_eq!(answer.unwrap(), SemanticValue::NumberBits(7f32.to_bits()));
            }
        }
    }
    #[test]
    fn startup_evaluation_respects_procedure_static_shadowing() {
        let procedure = dm_ir::ProcedureIdentity {
            owner: SymbolId::of("/"),
            name: SymbolId::of("work"),
            verb: false,
            occurrence: 0,
        };
        let body=dm_syntax::parse("/proc/work()\n    var/static/const/base = 7\n    var/static/value = base + 1\n    return value\n");
        let captured =
            dm_tree::procedure_statics::capture(procedure, &body.items[0].children).unwrap();
        let resolver = dm_tree::procedure_statics::StaticResolver::from_plans(
            &MissingHost,
            [(procedure, &captured)],
        )
        .unwrap();
        let evaluator = DriverEvaluator {
            pure_calls: None,
            resource_search_context: None,
            resolver: &resolver,
            symbols: &captured.symbols,
        };
        let value = captured
            .declarations
            .iter()
            .find(|value| value.identity.name == SymbolId::of("value"))
            .unwrap();
        let dm_ir::InitializerValue::Expression(expression) = &value.initializer else {
            panic!("expression");
        };
        let write = dm_ir::InitializerWrite {
            target: dm_ir::InitializerTarget::ProcedureStatic(value.identity),
            lexical_owner: procedure.owner,
            lexical_procedure: Some(procedure),
            value: value.initializer.clone(),
            declared_array: None,
            declaration_flags: Some(value.modifiers),
        };
        assert!(
            matches!(evaluator.evaluate_write(&write,expression).unwrap(),Evaluation::Scalar(SemanticValue::NumberBits(bits)) if f32::from_bits(bits)==8.0)
        );
    }
    #[test]
    fn captured_resource_literal_and_static_alias_keep_symbolic_path() {
        struct Assets {
            constant: Option<SymbolicExpression>,
            runtime_field: bool,
        }
        impl Resolver for Assets {
            fn resolve(&self, query: ResolveQuery) -> ResolvedMeaning {
                match query {
                    ResolveQuery::Var { owner, name } if self.runtime_field => {
                        ResolvedMeaning::Member {
                            owner,
                            name,
                            fingerprint: 4,
                            data: std::sync::Arc::new(dm_ir::DeclarationMeaning::default()),
                        }
                    }
                    ResolveQuery::Var { .. } => ResolvedMeaning::Missing,
                    ResolveQuery::GlobalVar(name)
                        if name == SymbolId::of("asset") && self.constant.is_some() =>
                    {
                        ResolvedMeaning::Member {
                            owner: SymbolId::of("/"),
                            name,
                            fingerprint: 3,
                            data: std::sync::Arc::new(dm_ir::DeclarationMeaning {
                                flags: 2,
                                initializer: self.constant.clone(),
                                ..Default::default()
                            }),
                        }
                    }
                    ResolveQuery::ResourceIn {
                        path,
                        search_context: 17,
                    } if path == SymbolId::of("asset.txt") => {
                        ResolvedMeaning::Resource { path, content: 123 }
                    }
                    _ => ResolvedMeaning::Unsupported(query),
                }
            }
        }
        let procedure = dm_ir::ProcedureIdentity {
            owner: SymbolId::of("/"),
            name: SymbolId::of("p"),
            verb: false,
            occurrence: 0,
        };
        let body = dm_syntax::parse(
            "/proc/p()\n    var/static/const/asset = 'asset.txt'\n    var/static/value = asset\n",
        );
        let plan = dm_tree::procedure_statics::capture(procedure, &body.items[0].children).unwrap();
        let resolver = dm_tree::procedure_statics::StaticResolver::from_plans(
            &Assets {
                constant: None,
                runtime_field: false,
            },
            [(procedure, &plan)],
        )
        .unwrap();
        let evaluator = DriverEvaluator {
            pure_calls: None,
            resolver: &resolver,
            symbols: &plan.symbols,
            resource_search_context: Some(17),
        };
        for declaration in &plan.declarations {
            let dm_ir::InitializerValue::Expression(expression) = &declaration.initializer else {
                panic!("expression")
            };
            assert_eq!(
                evaluator
                    .scalar_in(
                        procedure.owner,
                        expression,
                        Some(procedure),
                        &RefCell::new(Default::default())
                    )
                    .unwrap(),
                Some(SemanticValue::Resource(SymbolId::of("asset.txt")))
            );
        }
        let dm_ir::InitializerValue::Expression(literal) = &plan.declarations[0].initializer else {
            panic!("expression")
        };
        let dm_ir::InitializerValue::Expression(alias) = &plan.declarations[1].initializer else {
            panic!("expression")
        };
        let assets = Assets {
            constant: Some(literal.clone()),
            runtime_field: false,
        };
        let ordinary = DriverEvaluator {
            pure_calls: None,
            resolver: &assets,
            symbols: &plan.symbols,
            resource_search_context: Some(17),
        };
        assert_eq!(
            ordinary
                .scalar(SymbolId::of("/datum/probe"), alias)
                .unwrap(),
            Some(SemanticValue::Resource(SymbolId::of("asset.txt")))
        );
        let shadow_assets = Assets {
            constant: Some(literal.clone()),
            runtime_field: true,
        };
        let shadow = DriverEvaluator {
            pure_calls: None,
            resolver: &shadow_assets,
            symbols: &plan.symbols,
            resource_search_context: Some(17),
        };
        assert_eq!(
            shadow.scalar(SymbolId::of("/datum/probe"), alias).unwrap(),
            None
        );
        let no_context = DriverEvaluator {
            resource_search_context: None,
            ..evaluator
        };
        let dm_ir::InitializerValue::Expression(expression) = &plan.declarations[0].initializer
        else {
            panic!("expression")
        };
        assert!(no_context
            .scalar(procedure.owner, expression)
            .unwrap_err()
            .contains("search context"));
    }
    struct MissingHost;
    impl Resolver for MissingHost {
        fn resolve(&self, query: ResolveQuery) -> ResolvedMeaning {
            ResolvedMeaning::Unsupported(query)
        }
    }
    #[test]
    fn abi_failures_keep_each_captured_source_and_specific_cause() {
        let frontend = frontend();
        let prepared = PreparedSourceAbi {
            units: Vec::new(),
            diagnostics: vec![
                (1, "second specific cause".into()),
                (0, "first specific cause".into()),
            ],
        };
        let diagnostics = abi_diagnostics(&frontend, &prepared).unwrap();
        assert_eq!(diagnostics.len(), 2);
        assert_eq!(diagnostics[0].message, "first specific cause");
        assert_eq!(diagnostics[1].message, "second specific cause");
        for (ordinal, diagnostic) in diagnostics.iter().enumerate() {
            assert_eq!(diagnostic.origin.path, frontend.bodies[ordinal].source.path);
            assert_eq!(diagnostic.origin.line, frontend.bodies[ordinal].source.line);
            assert!(diagnostic.identity.is_some());
        }
    }
    #[test]
    fn pinned_constructor_prepares_source_dependency_without_caller_fresh_map() {
        let engine =
            EngineSnapshot::from_bytes(include_bytes!("../../../fixtures/native_template.bin"), 1)
                .unwrap();
        let seed = engine.frontend_seed();
        let frontend = dm_tree::frontend::build_with_config(
            Path::new("project.dme"),
            &Source,
            &Default::default(),
            dm_tree::frontend::FrontendConfig {
                workers: 1,
                engine: Some(&seed),
                observer: None,
            },
        )
        .unwrap();
        let prepared =
            prepare_pinned_source_abi(&frontend, &engine, frontend.snapshot.tree.as_ref(), None, 2)
                .unwrap();
        assert!(
            prepared.prepared.diagnostics.is_empty(),
            "{:?}",
            prepared.prepared.diagnostics
        );
        assert_eq!(prepared.prepared.units.len(), frontend.bodies.len());
        assert_ne!(prepared.policy_identity, engine.identity());
        let policy = FrozenPreparedPolicy::new(&frontend, &prepared.prepared).unwrap();
        let mut overlay = dm_ir::SymbolTable::overlay(frontend.snapshot.tree.shared_symbols());
        overlay.intern("body-only-static-name").unwrap();
        let body = &frontend.bodies[0];
        let identity = *unit_members(&frontend)
            .unwrap()
            .iter()
            .find(|(_, member)| **member == body.member)
            .unwrap()
            .0;
        let metadata = frontend
            .snapshot
            .tree
            .member(body.member)
            .unwrap()
            .metadata
            .procedure
            .as_ref()
            .unwrap();
        assert!(policy
            .validate(identity, metadata, &overlay, &body.source)
            .is_ok());
        assert!(policy
            .validate(
                identity,
                metadata,
                &dm_ir::SymbolTable::default(),
                &body.source
            )
            .is_err());
        let lowered = crate::lowering::lower_frontend(
            &frontend,
            frontend.snapshot.tree.as_ref(),
            &policy,
            crate::lowering::LoweringConfig {
                workers: 2,
                ..Default::default()
            },
        );
        assert!(lowered.diagnostics.is_empty(), "{:?}", lowered.diagnostics);
        assert!(lowered.units.iter().all(|unit| unit.abi.is_some()));
    }
    #[test]
    fn predecessor_abi_waves_preserve_encounter_order_and_inherited_layout() {
        let frontend = frontend();
        let engine =
            EngineSnapshot::from_bytes(include_bytes!("../../../fixtures/native_template.bin"), 1)
                .unwrap();
        let index = unit_members(&frontend).unwrap();
        let base = *index
            .keys()
            .find(|identity| identity.owner == SymbolId::of("/base"))
            .unwrap();
        let evaluator = DriverEvaluator {
            pure_calls: None,
            resource_search_context: None,
            resolver: frontend.snapshot.tree.as_ref(),
            symbols: frontend.snapshot.tree.symbols(),
        };
        // Fixture explicitly declares its base fresh; production must capture
        // the corresponding complete engine absence fact before issuing Fresh.
        let boundaries = BTreeMap::from([(base, BoundaryAbi::Fresh)]);
        let batch =
            prepare_source_abi(&frontend, &engine, &evaluator, &boundaries, None, 2).unwrap();
        assert!(batch.diagnostics.is_empty(), "{:?}", batch.diagnostics);
        assert_eq!(
            batch.units.iter().map(|(id, _)| *id).collect::<Vec<_>>(),
            frontend
                .bodies
                .iter()
                .map(|body| body.member)
                .collect::<Vec<_>>()
        );
        for (_, unit) in &batch.units {
            assert_eq!(
                unit.require_production_abi()
                    .unwrap()
                    .layout
                    .display_name
                    .as_deref(),
                Some(b"base display".as_slice())
            );
        }
        let policy = FrozenPreparedPolicy::new(&frontend, &batch).unwrap();
        let lowered = crate::lowering::lower_frontend(
            &frontend,
            frontend.snapshot.tree.as_ref(),
            &policy,
            Default::default(),
        );
        assert!(lowered.diagnostics.is_empty(), "{:?}", lowered.diagnostics);
        lowered.require_production_abi().unwrap();
    }
    #[test]
    fn unknown_root_abi_is_not_fresh_and_blocks_descendants() {
        let frontend = frontend();
        let engine =
            EngineSnapshot::from_bytes(include_bytes!("../../../fixtures/native_template.bin"), 1)
                .unwrap();
        let evaluator = DriverEvaluator {
            pure_calls: None,
            resource_search_context: None,
            resolver: frontend.snapshot.tree.as_ref(),
            symbols: frontend.snapshot.tree.symbols(),
        };
        let batch =
            prepare_source_abi(&frontend, &engine, &evaluator, &BTreeMap::new(), None, 8).unwrap();
        assert!(batch.units.is_empty());
        assert_eq!(batch.diagnostics.len(), frontend.bodies.len());
        assert!(batch
            .diagnostics
            .windows(2)
            .all(|pair| pair[0].0 < pair[1].0));
        assert!(FrozenPreparedPolicy::new(&frontend, &batch).is_err());
    }
    #[test]
    fn procedure_scalar_literals_preserve_exact_identity_and_constant_aliases() {
        struct Host {
            identity: dm_ir::ProcedureIdentity,
        }
        impl Resolver for Host {
            fn resolve(&self, query: ResolveQuery) -> ResolvedMeaning {
                match query {
                    ResolveQuery::ProcedureValue {
                        owner,
                        name,
                        verb: false,
                        formal: true,
                    } if owner == self.identity.owner && name == self.identity.name => {
                        ResolvedMeaning::Value(SemanticValue::Procedure(self.identity))
                    }
                    ResolveQuery::Constant { name, .. } if name == SymbolId::of("alias") => {
                        ResolvedMeaning::Value(SemanticValue::Procedure(self.identity))
                    }
                    _ => ResolvedMeaning::Unsupported(query),
                }
            }
        }
        let host = Host {
            identity: dm_ir::ProcedureIdentity {
                owner: SymbolId::of("/"),
                name: SymbolId::of("callback"),
                verb: false,
                occurrence: 2,
            },
        };
        let mut symbols = dm_ir::SymbolTable::default();
        for source in ["/proc/callback", "alias", "/proc/unknown"] {
            let lexed = dm_syntax::lex_spans(source);
            assert!(lexed.diagnostics.is_empty());
            let expression = dm_ir::SymbolicExpression {
                tokens: lexed
                    .tokens
                    .iter()
                    .map(|token| dm_ir::ExpressionToken {
                        kind: token.kind,
                        text: symbols.intern(token.text(source)).unwrap(),
                        relative_span: token.span,
                    })
                    .collect::<Vec<_>>()
                    .into(),
            };
            let evaluator = DriverEvaluator {
                pure_calls: None,
                resolver: &host,
                symbols: &symbols,
                resource_search_context: None,
            };
            let result = evaluator.scalar_in(
                SymbolId::of("/"),
                &expression,
                None,
                &RefCell::new(std::collections::HashSet::new()),
            );
            if source == "/proc/unknown" {
                assert!(result.is_err());
            } else {
                assert_eq!(
                    result.unwrap(),
                    Some(SemanticValue::Procedure(host.identity))
                );
            }
        }
    }
}
