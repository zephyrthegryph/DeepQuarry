//! Immutable compiler configuration resolver; no output tables or legacy bindings.
#[path = "engine_constants.rs"]
mod constants;
#[path = "intrinsic_methods.rs"]
mod intrinsic_methods;
use dm_ir::{
    ResolveQuery as Q, ResolvedMeaning as M, Resolver, SemanticValue, SymbolId, SymbolTable,
};
use std::{
    collections::{BTreeMap, BTreeSet, HashSet},
    sync::Arc,
};

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Completeness {
    Partial,
    Complete,
}
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum HostError {
    Symbol(dm_ir::SymbolCollision),
    UnknownSymbol(SymbolId),
    ConflictingConstant(SymbolId),
    ConflictingAlias(SymbolId),
    AliasIsOrdinary(SymbolId),
}
#[derive(Clone, Debug)]
pub struct ConstantCatalog {
    values: Arc<BTreeMap<SymbolId, SemanticValue>>,
    completeness: Completeness,
    identity: u128,
}
impl ConstantCatalog {
    /// Complete is an explicit assertion about the pinned compiler catalog, not
    /// inferred from the number of entries supplied. Values preserve exact bits.
    pub fn new(
        schema: u128,
        symbols: &mut SymbolTable,
        entries: Vec<(String, SemanticValue)>,
        completeness: Completeness,
    ) -> Result<Self, HostError> {
        let mut values = BTreeMap::new();
        for (name, value) in entries {
            let id = symbols.intern(&name).map_err(HostError::Symbol)?;
            if values
                .insert(id, value.clone())
                .is_some_and(|old| old != value)
            {
                return Err(HostError::ConflictingConstant(id));
            }
        }
        let mut bytes = b"dm-constant-catalog-v1\0".to_vec();
        bytes.extend_from_slice(&schema.to_le_bytes());
        bytes.push(completeness as u8);
        for (id, value) in &values {
            bytes.extend_from_slice(&id.bits().to_le_bytes());
            let value = value.canonical_bytes();
            bytes.extend_from_slice(&(value.len() as u64).to_le_bytes());
            bytes.extend_from_slice(&value);
        }
        Ok(Self {
            values: Arc::new(values),
            completeness,
            identity: xxhash_rust::xxh3::xxh3_128(&bytes),
        })
    }
    /// Finite values previously verified against BYOND 516.1687. The evidence
    /// establishes each positive value, not completeness of all engine names.
    pub fn native_516_1687(symbols: &mut SymbolTable) -> Result<Self, HostError> {
        let entries = constants::NUMBERS
            .iter()
            .map(|(name, bits)| (name.to_string(), SemanticValue::NumberBits(*bits)))
            .chain(constants::STRINGS.iter().map(|(name, text)| {
                (
                    name.to_string(),
                    SemanticValue::Text(Arc::from(text.as_bytes())),
                )
            }))
            .collect();
        Self::new(5161687, symbols, entries, Completeness::Partial)
    }
    pub fn identity(&self) -> u128 {
        self.identity
    }
}
#[derive(Clone, Debug)]
pub struct RuntimeAliasCatalog {
    aliases: Arc<BTreeMap<SymbolId, SymbolId>>,
    ordinary: Arc<HashSet<SymbolId>>,
    completeness: Completeness,
    identity: u128,
    policy_identity: u128,
}
impl RuntimeAliasCatalog {
    pub fn new(
        schema: u128,
        symbols: &SymbolTable,
        aliases: Vec<(SymbolId, SymbolId)>,
        ordinary: Vec<SymbolId>,
        completeness: Completeness,
    ) -> Result<Self, HostError> {
        let ordinary: HashSet<_> = ordinary.into_iter().collect();
        let mut mapping = BTreeMap::new();
        for &(alias, target) in &aliases {
            for id in [alias, target] {
                if symbols.text(id).is_none() {
                    return Err(HostError::UnknownSymbol(id));
                }
            }
            if ordinary.contains(&alias) {
                return Err(HostError::AliasIsOrdinary(alias));
            }
            if mapping
                .insert(alias, target)
                .is_some_and(|old| old != target)
            {
                return Err(HostError::ConflictingAlias(alias));
            }
        }
        let mut ordered_ordinary: Vec<_> = ordinary.iter().copied().collect();
        ordered_ordinary.sort_unstable();
        for id in &ordered_ordinary {
            if symbols.text(*id).is_none() {
                return Err(HostError::UnknownSymbol(*id));
            }
        }
        let mut bytes = b"dm-runtime-alias-catalog-v1\0".to_vec();
        bytes.extend_from_slice(&schema.to_le_bytes());
        bytes.push(completeness as u8);
        let policy_identity = xxhash_rust::xxh3::xxh3_128(&bytes);
        bytes.extend_from_slice(&(mapping.len() as u64).to_le_bytes());
        for (alias, target) in &mapping {
            bytes.extend_from_slice(&alias.bits().to_le_bytes());
            bytes.extend_from_slice(&target.bits().to_le_bytes());
        }
        bytes.extend_from_slice(&(ordinary.len() as u64).to_le_bytes());
        for id in ordered_ordinary {
            bytes.extend_from_slice(&id.bits().to_le_bytes());
        }
        Ok(Self {
            policy_identity,
            aliases: Arc::new(mapping),
            ordinary: Arc::new(ordinary),
            completeness,
            identity: xxhash_rust::xxh3::xxh3_128(&bytes),
        })
    }
    /// Exact catalog content, including source membership and captured aliases.
    pub fn identity(&self) -> u128 {
        self.identity
    }
    /// Immutable runtime schema and completeness policy; mappings are query data.
    pub fn policy_identity(&self) -> u128 {
        self.policy_identity
    }
}
#[derive(Clone, Debug)]
struct VariableAbsence {
    names: HashSet<SymbolId>,
    positive_constants: BTreeMap<SymbolId, SemanticValue>,
    identity: u128,
    source: Arc<dm_tree::SemanticTree>,
}
#[derive(Clone, Debug)]
pub struct EngineResolverHost<R> {
    answer_domain: std::sync::OnceLock<Option<u128>>,
    source_versions: Vec<u128>,
    tree: Arc<R>,
    constants: ConstantCatalog,
    runtime: RuntimeAliasCatalog,
    callable_absence: Option<Arc<HashSet<SymbolId>>>,
    intrinsic_methods: Option<Arc<intrinsic_methods::IntrinsicMethods>>,
    retained_methods: Option<Arc<crate::engine::procedure_abi::RetainedMethods>>,
    variable_absence: Option<Arc<VariableAbsence>>,
}
impl<R: Resolver> EngineResolverHost<R> {
    pub fn new(tree: Arc<R>, constants: ConstantCatalog, runtime: RuntimeAliasCatalog) -> Self {
        Self {
            answer_domain: std::sync::OnceLock::new(),
            source_versions: Vec::new(),
            tree,
            constants,
            runtime,
            callable_absence: None,
            intrinsic_methods: None,
            retained_methods: None,
            variable_absence: None,
        }
    }
    /// Certify the opposite callable namespace for authored names outside the
    /// pinned intrinsic exclusion catalog. This does not certify arbitrary
    /// absent names, variable fields, or layouts of intrinsic callbacks.
    pub fn with_pinned_callables(
        mut self,
        engine: &crate::engine::EngineSnapshot,
        frontend: &dm_tree::frontend::ColdFrontend,
    ) -> Result<Self, String> {
        crate::engine_abi_coverage::NamedEngineCoverage::pinned(engine)?;
        if frontend.engine.as_ref().map(|status| status.identity) != Some(engine.identity()) {
            return Err("callable coverage belongs to another engine capture".into());
        }
        self.answer_domain = std::sync::OnceLock::new();
        self.source_versions.push(frontend.snapshot.tree.identity());
        self.retained_methods = Some(Arc::new(
            crate::engine::procedure_abi::RetainedMethods::capture(
                engine,
                Arc::clone(&frontend.snapshot.tree),
            )?,
        ));
        let catalog: serde_json::Value = serde_json::from_slice(include_bytes!(
            "../../../fixtures/native_template_nativebuiltins_5161687.json"
        ))
        .map_err(|error| error.to_string())?;
        self.intrinsic_methods = Some(Arc::new(intrinsic_methods::IntrinsicMethods::capture(
            Arc::clone(&frontend.snapshot.tree),
            &catalog,
        )?));
        let intrinsic = catalog["Procs"]
            .as_array()
            .ok_or("native callable catalog absent")?
            .iter()
            .map(|proc| {
                proc["Name"]
                    .as_str()
                    .map(SymbolId::of)
                    .ok_or("native callable name absent")
            })
            .collect::<Result<BTreeSet<_>, _>>()?;
        self.callable_absence = Some(Arc::new(
            frontend
                .snapshot
                .tree
                .members()
                .iter()
                .filter(|member| {
                    matches!(
                        member.kind,
                        dm_tree::MemberKind::Proc | dm_tree::MemberKind::Verb
                    )
                })
                .map(|member| member.name)
                .filter(|name| !intrinsic.contains(name))
                .collect(),
        ));
        Ok(self)
    }
    /// Name exclusion is limited to authored declarations under one pinned
    /// engine schema. Unknown names and catalog intrinsics remain unsupported.
    pub fn with_pinned_variables(
        mut self,
        engine: &crate::engine::EngineSnapshot,
        frontend: &dm_tree::frontend::ColdFrontend,
    ) -> Result<Self, String> {
        crate::engine_abi_coverage::NamedEngineCoverage::pinned(engine)?;
        if frontend.engine.as_ref().map(|status| status.identity) != Some(engine.identity()) {
            return Err("variable coverage belongs to another engine capture".into());
        }
        const CATALOG: &[u8] =
            include_bytes!("../../../fixtures/native_template_nativebuiltins_5161687.json");
        let catalog: serde_json::Value =
            serde_json::from_slice(CATALOG).map_err(|error| error.to_string())?;
        let mut intrinsic = BTreeSet::new();
        for owner in catalog["Types"]
            .as_array()
            .ok_or("native variable catalog absent")?
        {
            for domain in ["Variables", "GlobalVariables"] {
                if domain == "GlobalVariables" && owner["Path"].as_str() == Some("/") {
                    continue;
                }
                if let Some(values) = owner.get(domain) {
                    for name in values
                        .as_object()
                        .ok_or("native variable domain malformed")?
                        .keys()
                    {
                        intrinsic.insert(SymbolId::of(name));
                    }
                }
            }
            if let Some(values) = owner.get("ConstVariables") {
                for name in values
                    .as_array()
                    .ok_or("native const variable catalog malformed")?
                {
                    intrinsic.insert(SymbolId::of(
                        name.as_str()
                            .ok_or("native const variable name malformed")?,
                    ));
                }
            }
        }
        let mut catalog_symbols = SymbolTable::default();
        for field in crate::engine::catalog::fields(&mut catalog_symbols)
            .map_err(|error| error.to_string())?
        {
            intrinsic.insert(field.name);
        }
        let mut names: HashSet<_> = frontend
            .snapshot
            .tree
            .members()
            .iter()
            .filter(|member| {
                member.kind == dm_tree::MemberKind::Var
                    && member.definition == dm_tree::DefinitionMode::Declare
            })
            .map(|member| member.name)
            .filter(|name| !intrinsic.contains(name))
            .collect();
        // Positive compiler constants are a separate semantic domain from root
        // runtime globals. Only exact pinned values may certify lexical absence.
        let pinned_constants = ConstantCatalog::native_516_1687(&mut catalog_symbols)
            .map_err(|error| format!("pinned constants {error:?}"))?;
        for (name, value) in pinned_constants.values.iter() {
            if !intrinsic.contains(name) && self.constants.values.get(name) == Some(value) {
                names.insert(*name);
            }
        }
        // TRUE/FALSE also survive native #undef as actual pinned const globals.
        // Require physical const metadata and the exact observed catalog value;
        // neither an arbitrary engine field nor a caller supplied constant qualifies.
        let mut positive_constants = BTreeMap::new();
        for spelling in ["TRUE", "FALSE"] {
            let name = SymbolId::of(spelling);
            let value = pinned_constants.values.get(&name);
            let physically_const = engine
                .declaration_modifiers(SymbolId::of("/"), name)
                .map_err(|error| format!("pinned constant metadata {error:?}"))?
                .is_some_and(|flags| flags & 2 != 0);
            if let Some(value) = value.filter(|value| {
                physically_const && self.constants.values.get(&name) == Some(*value)
            }) {
                positive_constants.insert(name, value.clone());
            }
        }
        let mut bytes =
            b"pinned-authored-variable-absence-v3;physical-boolean-constants;captured-slot-uniqueness".to_vec();
        bytes.extend_from_slice(&engine.identity().to_le_bytes());
        bytes.extend_from_slice(crate::engine::catalog::CATALOG_SCHEMA.as_bytes());
        bytes.extend_from_slice(CATALOG);
        for name in &intrinsic {
            bytes.extend_from_slice(&name.bits().to_le_bytes());
        }
        self.answer_domain = std::sync::OnceLock::new();
        self.source_versions.push(frontend.snapshot.tree.identity());
        self.variable_absence = Some(Arc::new(VariableAbsence {
            names,
            positive_constants,
            identity: xxhash_rust::xxh3::xxh3_128(&bytes),
            source: Arc::clone(&frontend.snapshot.tree),
        }));
        Ok(self)
    }
    /// Compiler policy only. Source membership and alias mapping are RuntimeType
    /// and declaration query inputs, never blanket procedure invalidation keys.
    pub fn configuration_identity(&self) -> u128 {
        let mut bytes = b"dm-engine-host-v1\0".to_vec();
        bytes.extend_from_slice(&self.constants.identity.to_le_bytes());
        bytes.extend_from_slice(&self.runtime.policy_identity.to_le_bytes());
        if let Some(retained) = &self.retained_methods {
            bytes.extend_from_slice(&retained.identity().to_le_bytes());
        }
        if self.callable_absence.is_some() {
            bytes.extend_from_slice(b"pinned-callable-policy-v3;explicit-runtime-receiver-methods;receiver-proof-sha256:5b09e0c80aeecb5b864a556a18f038313158f240adefd6d5503e8daf5961a8d9");
            bytes.extend_from_slice(include_bytes!(
                "../../../fixtures/native_template_nativebuiltins_5161687.json"
            ));
        }
        if let Some(coverage) = &self.variable_absence {
            bytes.extend_from_slice(&coverage.identity.to_le_bytes());
        }
        xxhash_rust::xxh3::xxh3_128(&bytes)
    }
}
impl<R: Resolver + Send> Resolver for EngineResolverHost<R> {
    fn domain_version(&self, domain: dm_ir::ReadDomain) -> Option<u128> {
        if domain != dm_ir::ReadDomain::Tree {
            return self.tree.domain_version(domain);
        }
        *self.answer_domain.get_or_init(|| {
            let base = self.tree.domain_version(domain)?;
            let mut hash = xxhash_rust::xxh3::Xxh3::new();
            hash.update(b"dm-engine-answer-domain-v1\0");
            for value in [base, self.configuration_identity(), self.runtime.identity()] {
                hash.update(&value.to_le_bytes());
            }
            hash.update(&(self.source_versions.len() as u64).to_le_bytes());
            for value in &self.source_versions {
                hash.update(&value.to_le_bytes());
            }
            let mut names: Vec<_> = self
                .callable_absence
                .iter()
                .flat_map(|names| names.iter())
                .copied()
                .collect();
            names.sort();
            hash.update(&(names.len() as u64).to_le_bytes());
            for name in names {
                hash.update(&name.bits().to_le_bytes());
            }
            Some(hash.digest128())
        })
    }

    fn resolve(&self, query: Q) -> M {
        match query {
            Q::PredefinedConstant(name) => self
                .constants
                .values
                .get(&name)
                .cloned()
                .map(M::Value)
                .unwrap_or_else(|| {
                    if self.constants.completeness == Completeness::Complete {
                        M::Missing
                    } else {
                        M::Unsupported(query)
                    }
                }),
            Q::RuntimeType(path) => {
                if let Some(target) = self.runtime.aliases.get(&path) {
                    return M::Symbol(*target);
                }
                if self.runtime.ordinary.contains(&path) {
                    return M::Symbol(path);
                }
                if self.runtime.completeness == Completeness::Partial {
                    return M::Unsupported(query);
                }
                match self.tree.resolve(Q::Type(path)) {
                    M::Symbol(id) => M::Symbol(id),
                    M::Missing => M::Missing,
                    _ => M::Unsupported(query),
                }
            }
            _ => {
                let answer = self.tree.resolve(query);
                if !matches!(answer, M::Unsupported(_)) {
                    return answer;
                }
                if let Q::UniqueStaticVar(name) = query {
                    // The source roster is complete, but the engine inventory
                    // is partial. Only the pinned intrinsic-name exclusion
                    // can close that gap; unknown/native names stay unsupported.
                    if let Some(coverage) = &self.variable_absence {
                        if coverage.names.contains(&name) {
                            return coverage.source.captured_variable_uniqueness(name);
                        }
                    }
                    return answer;
                }
                if let Some(meaning) = self
                    .retained_methods
                    .as_ref()
                    .and_then(|catalog| catalog.resolve(query))
                {
                    return meaning;
                }
                if let Some(meaning) = self
                    .intrinsic_methods
                    .as_ref()
                    .and_then(|catalog| catalog.resolve(query))
                {
                    return meaning;
                }
                let variable = match query {
                    Q::Var { owner, name }
                    | Q::DeclaredVarType { owner, name }
                    | Q::VarStorage { owner, name }
                    | Q::StaticVar { owner, name }
                    | Q::Constant { owner, name } => Some((owner, name, false)),
                    Q::HasMemberVar { owner, name } => Some((owner, name, true)),
                    Q::GlobalVar(name) => Some((SymbolId::of("/"), name, false)),
                    _ => None,
                };
                if let Some((owner, name, presence)) = variable {
                    if let Some(coverage) = &self.variable_absence {
                        // An evaluation layer can lack a scalar outcome while
                        // the captured declaration still has authoritative metadata.
                        let declared = dm_ir::Resolver::resolve(coverage.source.as_ref(), query);
                        if !matches!(declared, M::Unsupported(_) | M::Missing) {
                            return declared;
                        }
                        if matches!(query, Q::Constant { .. } | Q::GlobalVar(_))
                            && coverage.source.lookup_type(owner).is_some()
                            && !matches!(
                                dm_ir::Resolver::resolve(
                                    coverage.source.as_ref(),
                                    Q::Var { owner, name }
                                ),
                                M::Member { .. }
                            )
                        {
                            if let Some(value) = coverage.positive_constants.get(&name) {
                                // Even a mutable authored field without a scalar
                                // Constant answer shadows the native constant.
                                return M::Value(value.clone());
                            }
                        }
                        if matches!(
                            dm_ir::Resolver::resolve(
                                coverage.source.as_ref(),
                                Q::HasMemberVar { owner, name }
                            ),
                            M::Presence(true)
                        ) {
                            return answer;
                        }
                    }
                    if self.variable_absence.as_ref().is_some_and(|coverage| {
                        coverage.names.contains(&name)
                            && coverage.source.lookup_type(owner).is_some()
                    }) && self.runtime.ordinary.contains(&owner)
                    {
                        return if presence {
                            M::Presence(false)
                        } else {
                            M::Missing
                        };
                    }
                    return answer;
                }
                let (owner, name, presence) = match query {
                    Q::Proc { owner, name, .. } => (owner, name, false),
                    Q::HasMemberProc { owner, name } => (owner, name, true),
                    Q::GlobalProc(name) => (SymbolId::of("/"), name, false),
                    _ => return answer,
                };
                if self
                    .callable_absence
                    .as_ref()
                    .is_some_and(|names| names.contains(&name))
                    && self.runtime.ordinary.contains(&owner)
                {
                    if presence {
                        M::Presence(false)
                    } else {
                        M::Missing
                    }
                } else {
                    answer
                }
            }
        }
    }
}
#[cfg(test)]
#[path = "engine_host/tests.rs"]
mod tests;
