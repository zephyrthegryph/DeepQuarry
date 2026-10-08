//! Request-local lowering view. All project answers come from one immutable
//! resolver; the input structure contains only this procedure's lexical state.
use crate::simple::{LowerBindings, LowerError};
use dm_ir::{
    ResolveQuery as Q, ResolvedMeaning as M, Resolver, SemanticValue, SymbolId, SymbolTable,
};
use std::cell::RefCell;
use std::collections::{BTreeMap, BTreeSet, HashMap};
use std::sync::Arc;

pub(crate) fn shared_slot_key(owner: &str, name: &str) -> String {
    format!("var{}/{name}", owner.trim_end_matches('/'))
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ResolvedSlot {
    pub symbol: SymbolId,
    pub owner: SymbolId,
    pub name: SymbolId,
}
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ResolvedInstance {
    pub alias: SymbolId,
    pub runtime_type: SymbolId,
}
#[derive(Clone, Debug)]
pub struct CapturedModifiedInstance {
    pub descriptor: dm_ir::ModifiedInstance,
    /// Current caller statement origins, never AST-relative offsets interpreted
    /// as frontend positions. Empty blocks retain the parent origin separately.
    pub field_origins: Vec<Option<u32>>,
    pub origin: Option<u32>,
}
#[derive(Clone)]
pub struct ResolverProc {
    pub modified_instances: BTreeMap<crate::Symbol, CapturedModifiedInstance>,
    pub procedure_values: BTreeMap<crate::Symbol, dm_ir::ProcedureIdentity>,
    pub procedure_statics: BTreeMap<crate::Symbol, dm_ir::ProcedureStaticIdentity>,
    pub procedure: crate::SimpleProc,
    /// Exact resolver-issued slot tuples; no output slot is selected here.
    pub slots: BTreeMap<crate::Symbol, ResolvedSlot>,
    pub resources: BTreeMap<String, u128>,
    /// RuntimeType licenses alias classification, not the modifier payload.
    /// The linker still requires an explicit semantic instance artifact.
    pub instances: BTreeMap<String, ResolvedInstance>,
}

#[derive(Clone, Debug, Default)]
pub struct ProcedureInputs {
    pub procedure_identity: Option<dm_ir::ProcedureIdentity>,
    pub current_proc_path: Option<String>,
    pub current_type_path: Option<String>,
    pub parameters: Vec<String>,
    pub parameter_type_flags: Vec<u32>,
    pub parameter_value_sources: Vec<u32>,
    pub parameter_defaults: Vec<Option<String>>,
    pub parameter_types: HashMap<String, String>,
    /// Const formal bindings, identified by their exact argument slot.
    pub readonly_parameters: BTreeSet<u32>,
    /// Explicit captured FILE_DIR/source-directory context, never inferred here.
    pub resource_search_context: Option<u128>,
}
impl ProcedureInputs {
    pub(crate) fn lexical_bindings(&self) -> LowerBindings {
        LowerBindings {
            procedure_identity: self.procedure_identity,
            current_proc_path: self.current_proc_path.clone(),
            current_type_path: self.current_type_path.clone(),
            parameters: self.parameters.clone(),
            parameter_type_flags: self.parameter_type_flags.clone(),
            parameter_value_sources: self.parameter_value_sources.clone(),
            parameter_defaults: self.parameter_defaults.clone(),
            parameter_types: self.parameter_types.clone(),
            readonly_parameters: self.readonly_parameters.clone(),
            ..LowerBindings::default()
        }
    }
}
pub(crate) struct ProjectResolver<'a> {
    pub modified_instances: RefCell<BTreeMap<crate::Symbol, CapturedModifiedInstance>>,
    pub procedure_values: RefCell<BTreeMap<crate::Symbol, dm_ir::ProcedureIdentity>>,
    pub procedure_statics: RefCell<BTreeMap<crate::Symbol, dm_ir::ProcedureStaticIdentity>>,
    pub resolver: &'a dyn Resolver,
    pub symbols: &'a SymbolTable,
    pub slots: RefCell<BTreeMap<crate::Symbol, ResolvedSlot>>,
    pub resources: RefCell<BTreeMap<String, u128>>,
    pub instances: RefCell<BTreeMap<String, ResolvedInstance>>,
    pub runtime_types: RefCell<BTreeMap<String, SymbolId>>,
    pub resource_search_context: Option<u128>,
}
impl ProjectResolver<'_> {
    pub fn modified_instance(
        &self,
        path: &str,
        lexical_owner: &str,
        fields: &[(String, dm_syntax::Expr)],
        origin: Option<u32>,
    ) -> Result<String, LowerError> {
        let query = Q::RuntimeType(SymbolId::of(path));
        let M::Symbol(runtime_type) = self.answer(query)? else {
            return Err(self.error(
                query,
                "modified instance needs a captured ordinary runtime type",
            ));
        };
        if runtime_type != SymbolId::of(path) {
            return Err(self.error(query, "modified instance base is not an ordinary type"));
        }
        let descriptor = dm_ir::ModifiedInstance::capture_with_resources(
            runtime_type,
            SymbolId::of(lexical_owner),
            self.resource_search_context,
            fields,
            |raw| crate::decode_constant_string_literal(raw).ok().flatten(),
            None,
            |path| {
                let query = match self.resource_search_context {
                    Some(search_context) => Q::ResourceIn {
                        path: SymbolId::of(path),
                        search_context,
                    },
                    None => Q::Resource(SymbolId::of(path)),
                };
                match self.answer(query).map_err(|error| error.reason)? {
                    M::Resource { path, content } => {
                        Ok(dm_ir::CapturedModifiedResource { path, content })
                    }
                    _ => Err("modified resource needs a positive captured payload identity".into()),
                }
            },
        )
        .map_err(|reason| self.error(query, &reason))?;
        let alias = descriptor.alias();
        let symbol = crate::Symbol::new(crate::Table::Instance, &alias);
        let mut descriptors = self.modified_instances.borrow_mut();
        if descriptors
            .get(&symbol)
            .is_some_and(|old| old.descriptor.canonical_bytes() != descriptor.canonical_bytes())
        {
            return Err(self.error(query, "modified instance identity collision"));
        }
        descriptors
            .entry(symbol)
            .or_insert(CapturedModifiedInstance {
                descriptor,
                field_origins: vec![origin; fields.len()],
                origin,
            });
        Ok(alias)
    }

    pub fn procedure_value_key(
        &self,
        identity: dm_ir::ProcedureIdentity,
    ) -> Result<String, LowerError> {
        let key = format!(
            "procedure-value:{:016x}:{:016x}:{}:{}",
            identity.owner.bits(),
            identity.name.bits(),
            u8::from(identity.verb),
            identity.occurrence
        );
        let symbol = crate::Symbol::new(crate::Table::Proc, &key);
        let old = self.procedure_values.borrow_mut().insert(symbol, identity);
        if old.is_some_and(|old| old != identity) {
            return Err(self.error(
                Q::ProcedureValue {
                    owner: identity.owner,
                    name: identity.name,
                    verb: identity.verb,
                    formal: true,
                },
                "conflicting procedure literal answers",
            ));
        }
        Ok(key)
    }
    pub fn procedure_literal(&self, path: &str) -> Result<String, LowerError> {
        let query = dm_ir::procedure_value_query(path).ok_or_else(|| {
            self.error(
                Q::Type(SymbolId::of(path)),
                "unsupported procedure literal shape",
            )
        })?;
        let Q::ProcedureValue {
            owner, name, verb, ..
        } = query
        else {
            unreachable!()
        };
        match self.answer(query)? {
            M::Value(SemanticValue::Procedure(identity))
                if identity.owner == owner && identity.name == name && identity.verb == verb =>
            {
                self.procedure_value_key(identity)
            }
            _ => Err(self.error(query, "procedure literal is not positively captured")),
        }
    }
    pub fn procedure_static(
        &self,
        procedure: Option<dm_ir::ProcedureIdentity>,
        name: &str,
    ) -> Result<Option<Arc<dm_ir::ProcedureStaticDeclaration>>, LowerError> {
        let Some(procedure) = procedure else {
            return Ok(None);
        };
        let query = Q::ProcedureStatic {
            procedure,
            name: SymbolId::of(name),
        };
        match self.answer(query)? {
            M::Missing => Ok(None),
            M::ProcedureStatic(declaration)
                if declaration.identity.procedure == procedure
                    && declaration.identity.name == SymbolId::of(name) =>
            {
                Ok(Some(declaration))
            }
            _ => Err(self.error(query, "invalid procedure-static declaration answer")),
        }
    }
    pub fn procedure_static_slot(
        &self,
        procedure: Option<dm_ir::ProcedureIdentity>,
        name: &str,
    ) -> Result<Option<String>, LowerError> {
        let Some(declaration) = self.procedure_static(procedure, name)? else {
            return Ok(None);
        };
        let identity = declaration.identity;
        let key = format!(
            "procedure-static:{:016x}:{:016x}:{}:{}:{:016x}",
            identity.procedure.owner.bits(),
            identity.procedure.name.bits(),
            u8::from(identity.procedure.verb),
            identity.procedure.occurrence,
            identity.name.bits()
        );
        self.procedure_statics
            .borrow_mut()
            .insert(crate::Symbol::new(crate::Table::Variable, &key), identity);
        Ok(Some(key))
    }
    pub fn runtime_type(&self, path: &str) -> Result<String, LowerError> {
        let alias = SymbolId::of(path);
        let query = Q::RuntimeType(alias);
        let runtime_type = match self.answer(query)? {
            M::Symbol(id) => id,
            M::Missing => return Err(self.error(query, "runtime type coverage is missing")),
            _ => return Err(self.error(query, "invalid runtime type answer")),
        };
        let text = self.text(query, runtime_type)?;
        let old = self
            .runtime_types
            .borrow_mut()
            .insert(path.to_owned(), runtime_type);
        if old.is_some_and(|old| old != runtime_type) {
            return Err(self.error(query, "conflicting runtime type answers"));
        }
        if runtime_type != alias {
            self.instances.borrow_mut().insert(
                path.to_owned(),
                ResolvedInstance {
                    alias,
                    runtime_type,
                },
            );
        }
        Ok(text)
    }
    pub fn resource(&self, path: &str) -> Result<String, LowerError> {
        let path_id = SymbolId::of(path);
        let query = match self.resource_search_context {
            Some(search_context) => Q::ResourceIn {
                path: path_id,
                search_context,
            },
            None => Q::Resource(path_id),
        };
        match self.answer(query)? {
            M::Resource { path, content } => {
                let alias = self.text(query, path)?;
                let old = self.resources.borrow_mut().insert(alias.clone(), content);
                if old.is_some_and(|old| old != content) {
                    return Err(self.error(query, "conflicting captured resource content"));
                }
                Ok(alias)
            }
            M::Missing => Err(self.error(query, "resource missing in captured search context")),
            _ => Err(self.error(query, "invalid resource lookup answer")),
        }
    }
    pub fn answer(&self, query: Q) -> Result<M, LowerError> {
        match self.resolver.resolve(query) {
            M::Unsupported(_) => Err(self.error(query, "unsupported semantic query")),
            answer => Ok(answer),
        }
    }
    pub fn error(&self, query: Q, reason: &str) -> LowerError {
        let names = match query {
            Q::Var { owner, name }
            | Q::HasMemberVar { owner, name }
            | Q::DeclaredVarType { owner, name }
            | Q::VarStorage { owner, name }
            | Q::Proc { owner, name, .. }
            | Q::ProcedureValue { owner, name, .. }
            | Q::OverrideChain { owner, name, .. }
            | Q::Constant { owner, name }
            | Q::StaticVar { owner, name }
            | Q::HasMemberProc { owner, name } => {
                match (self.symbols.text(owner), self.symbols.text(name)) {
                    (Some(owner), Some(name)) => format!(" (owner={owner}, name={name})"),
                    _ => String::new(),
                }
            }
            Q::GlobalVar(name)
            | Q::GlobalProc(name)
            | Q::UniqueStaticVar(name)
            | Q::PredefinedConstant(name) => self
                .symbols
                .text(name)
                .map(|name| format!(" (name={name})"))
                .unwrap_or_default(),
            _ => String::new(),
        };
        LowerError {
            statement: String::new(),
            reason: format!("{reason}: {query:?}{names}"),
            ..LowerError::default()
        }
    }
    pub fn text(&self, query: Q, symbol: SymbolId) -> Result<String, LowerError> {
        self.symbols
            .text(symbol)
            .map(str::to_owned)
            .ok_or_else(|| self.error(query, "resolver symbol spelling unavailable"))
    }
    pub fn presence(&self, query: Q) -> Result<bool, LowerError> {
        match self.answer(query)? {
            M::Missing => Ok(false),
            M::Presence(value) => Ok(value),
            M::Member { .. }
            | M::IntrinsicProc { .. }
            | M::RetainedProc { .. }
            | M::Symbol(_)
            | M::Slot { .. } => Ok(true),
            _ => Err(self.error(query, "invalid presence answer")),
        }
    }
    pub fn declared_type(&self, query: Q) -> Result<Option<String>, LowerError> {
        match self.answer(query)? {
            M::Missing => Ok(None),
            M::DeclaredType(value) => value.map(|id| self.text(query, id)).transpose(),
            M::Member { data, .. } => data
                .declared_type
                .map(|id| self.text(query, id))
                .transpose(),
            _ => Err(self.error(query, "declared type metadata unavailable")),
        }
    }
    pub fn slot(&self, query: Q) -> Result<Option<String>, LowerError> {
        match self.answer(query)? {
            M::Missing => Ok(None),
            M::InstanceField {
                declaring_owner,
                name,
            } if matches!(query, Q::VarStorage { .. }) => {
                // Consume the issued storage tuple without demanding opaque default metadata.
                self.text(query, declaring_owner)?;
                self.text(query, name)?;
                Ok(None)
            }
            M::Slot {
                symbol,
                owner,
                name,
            } => {
                let key = shared_slot_key(&self.text(query, owner)?, &self.text(query, name)?);
                let slot = ResolvedSlot {
                    symbol,
                    owner,
                    name,
                };
                let old = self.slots.borrow_mut().insert(
                    crate::Symbol::new(crate::Table::Variable, &key),
                    slot.clone(),
                );
                if old.is_some_and(|old| old != slot) {
                    return Err(self.error(query, "conflicting slot tuple"));
                }
                Ok(Some(key))
            }
            _ => Err(self.error(query, "slot symbol spelling unavailable")),
        }
    }
    pub fn member_proc(&self, owner: &str, name: &str) -> Result<Option<String>, LowerError> {
        let owner_id = SymbolId::of(owner);
        let name_id = SymbolId::of(name);
        let proc_query = Q::Proc {
            owner: owner_id,
            name: name_id,
            verb: false,
        };
        let verb_query = Q::Proc {
            owner: owner_id,
            name: name_id,
            verb: true,
        };
        let procedure = self.answer(proc_query)?;
        // The semantic tree rejects cross-namespace callable declarations.
        // A positively issued procedure therefore selects the callable without
        // requiring an unrelated negative answer from a partial engine catalog.
        let (answer, query, namespace) = match procedure {
            answer @ (M::Member { .. }
            | M::IntrinsicProc { .. }
            | M::RetainedProc { verb: false, .. }) => (answer, proc_query, "proc"),
            M::Missing => match self.answer(verb_query)? {
                M::Missing => return Ok(None),
                answer @ (M::Member { .. } | M::RetainedProc { verb: true, .. }) => {
                    (answer, verb_query, "verb")
                }
                _ => {
                    return Err(self.error(verb_query, "procedure declaration metadata unavailable"))
                }
            },
            _ => return Err(self.error(proc_query, "procedure declaration metadata unavailable")),
        };
        match answer {
            M::RetainedProc {
                declaring_owner,
                name,
                verb,
                ..
            } if name == name_id && verb == (namespace == "verb") => {
                // This exact engine procedure is already linked in the retained
                // prefix. Runtime name dispatch needs no fabricated source unit.
                self.text(query, declaring_owner)?;
                Ok(None)
            }
            M::IntrinsicProc {
                declaring_owner,
                name,
            } if namespace == "proc" && name == name_id => {
                // A runtime method is called by the existing dynamic name
                // selector. Its engine implementation has no emitted proc image.
                self.text(query, declaring_owner)?;
                Ok(None)
            }
            M::Member { owner, name, .. } => Ok(Some(format!(
                "{}/{}/{}",
                self.text(query, owner)?.trim_end_matches('/'),
                namespace,
                self.text(query, name)?
            ))),
            _ => Err(self.error(query, "procedure declaration metadata unavailable")),
        }
    }
    /// Only an authored exact path annotation supplies a receiver type. Return
    /// value inference never examines executable bodies or invents engine ABI.
    pub fn procedure_return_type(&self, query: Q) -> Result<Option<String>, LowerError> {
        let answer = self.answer(query)?;
        let M::Member { data, .. } = answer else {
            return match answer {
                M::Missing | M::IntrinsicProc { .. } | M::RetainedProc { .. } => Ok(None),
                _ => Err(self.error(query, "procedure return metadata unavailable")),
            };
        };
        let Some(annotation) = data
            .procedure
            .as_ref()
            .and_then(|metadata| metadata.signature.return_annotation.as_ref())
        else {
            return Ok(None);
        };
        let text = annotation
            .source_text(self.symbols)
            .ok_or_else(|| self.error(query, "return annotation spelling unavailable"))?;
        let text = text.trim();
        // Unions and scalar annotations do not establish one class receiver.
        if !text.starts_with('/') || text.contains('|') {
            return Ok(None);
        }
        let Some(expression) = dm_syntax::parse_expression(text).expr else {
            return Ok(None);
        };
        let dm_syntax::ExprKind::TypePath(path) = expression.kind else {
            return Ok(None);
        };
        self.runtime_type(&path).map(Some)
    }
    pub fn constant(&self, name: &str) -> Result<Option<SemanticValue>, LowerError> {
        let query = Q::PredefinedConstant(SymbolId::of(name));
        match self.answer(query)? {
            M::Missing => Ok(None),
            M::Value(value) => Ok(Some(value)),
            _ => Err(self.error(query, "invalid predefined constant answer")),
        }
    }
}

#[cfg(test)]
#[path = "lower_resolver_tests.rs"]
mod tests;
