//! Immutable compiler configuration resolver; no output tables or legacy bindings.
mod catalog_domains;
#[path = "engine_constants.rs"]
mod constants;
mod engine_providers;
#[path = "intrinsic_methods.rs"]
mod intrinsic_methods;
mod pinned_facts;
use dm_ir::{
    ResolveQuery as Q, ResolvedMeaning as M, Resolver, SemanticValue, SymbolId, SymbolTable,
};
pub(crate) use engine_providers::PinnedEngineProviders;
pub use pinned_facts::{PinnedHostFacts, PinnedSource};
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
    issuer: Option<u64>,
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
            issuer: catalog_domains::issue(),
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
    issuer: Option<u64>,
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
            issuer: catalog_domains::issue(),
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
    issuer: Option<u64>,
    names: HashSet<SymbolId>,
    positive_constants: BTreeMap<SymbolId, SemanticValue>,
    identity: u128,
    source: Arc<dm_tree::SemanticTree>,
}
#[derive(Clone, Debug)]
pub struct EngineResolverHost<R> {
    answer_domain: std::sync::OnceLock<Option<u128>>,
    source_versions: Vec<u128>,
    callable_issuer: Option<u64>,
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
            callable_issuer: None,
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
        self,
        engine: &crate::engine::EngineSnapshot,
        frontend: &dm_tree::frontend::ColdFrontend,
    ) -> Result<Self, String> {
        check_provider_source(engine, frontend)?;
        self.bind_callables(
            frontend,
            &engine_providers::CallableProviders::capture(engine)?,
        )
    }
    fn bind_callables(
        mut self,
        frontend: &dm_tree::frontend::ColdFrontend,
        providers: &engine_providers::CallableProviders,
    ) -> Result<Self, String> {
        let mut symbols = SymbolTable::overlay(frontend.snapshot.tree.shared_symbols());
        symbols
            .merge_from(&providers.spellings)
            .map_err(|error| format!("native symbol {error:?}"))?;
        self.answer_domain = std::sync::OnceLock::new();
        self.source_versions.push(frontend.snapshot.tree.identity());
        self.retained_methods = Some(Arc::new(
            crate::engine::procedure_abi::RetainedMethods::from_entries(
                Arc::clone(&frontend.snapshot.tree),
                providers.engine,
                Arc::clone(&providers.retained),
            ),
        ));
        self.intrinsic_methods = Some(Arc::new(intrinsic_methods::IntrinsicMethods::from_payload(
            Arc::clone(&frontend.snapshot.tree),
            Arc::clone(&providers.methods),
        )));
        self.callable_issuer = providers.issuer;
        self.callable_absence = Some(Arc::new(
            frontend
                .snapshot
                .tree
                .host_declaration_selections()
                .flat_map(|(_, selection)| selection.callable_names.iter().copied())
                .filter(|name| !providers.intrinsic.contains(name))
                .collect(),
        ));
        Ok(self)
    }
    pub fn with_pinned_variables(
        self,
        engine: &crate::engine::EngineSnapshot,
        frontend: &dm_tree::frontend::ColdFrontend,
    ) -> Result<Self, String> {
        check_provider_source(engine, frontend)?;
        self.bind_variables(
            frontend,
            &engine_providers::VariableProviders::capture(engine)?,
        )
    }
    fn bind_variables(
        mut self,
        frontend: &dm_tree::frontend::ColdFrontend,
        providers: &engine_providers::VariableProviders,
    ) -> Result<Self, String> {
        let mut symbols = SymbolTable::overlay(frontend.snapshot.tree.shared_symbols());
        symbols
            .merge_from(&providers.spellings)
            .map_err(|error| format!("native variable symbol {error:?}"))?;
        let mut names: HashSet<_> = frontend
            .snapshot
            .tree
            .host_declaration_selections()
            .flat_map(|(_, selection)| selection.declared_variable_names.iter().copied())
            .filter(|name| !providers.intrinsic.contains(name))
            .collect();
        names.insert(SymbolId::of("__TYPE__"));
        for (name, value) in providers.constants.values.iter() {
            if !providers.intrinsic.contains(name) && self.constants.values.get(name) == Some(value)
            {
                names.insert(*name);
            }
        }
        let positive_constants = providers
            .positive_constants
            .iter()
            .filter(|(name, value)| self.constants.values.get(*name) == Some(*value))
            .map(|(name, value)| (*name, value.clone()))
            .collect();
        self.answer_domain = std::sync::OnceLock::new();
        self.source_versions.push(frontend.snapshot.tree.identity());
        self.variable_absence = Some(Arc::new(VariableAbsence {
            issuer: providers.issuer,
            names,
            positive_constants,
            identity: providers.identity,
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
        if let Some(version) = self.catalog_domain(domain) {
            return version;
        }
        if let dm_ir::ReadDomain::OwnerScalar(query) = domain {
            let base = u64::try_from(self.tree.domain_version(domain)?).ok()?;
            // Only a positive enriched source answer bypasses engine fallback.
            // Its admitted scalar owner already records the exact engine read.
            if !matches!(self.tree.resolve(query), M::Member { .. }) {
                return None;
            }
            let provider = match &self.variable_absence {
                Some(coverage) => coverage.issuer?,
                None => 0,
            };
            return Some((u128::from(base) << 64) | u128::from(provider));
        }
        if let dm_ir::ReadDomain::OwnerVariable(query) = domain {
            if let Q::UniqueStaticVar(name) = query {
                let (base, provider) = if matches!(self.tree.resolve(query), M::Unsupported(_)) {
                    let coverage = self.variable_absence.as_ref()?;
                    if !coverage.names.contains(&name) {
                        return None;
                    }
                    (coverage.source.domain_version(domain)?, coverage.issuer?)
                } else {
                    let provider = match &self.variable_absence {
                        Some(coverage) => coverage.issuer?,
                        None => 0,
                    };
                    (self.tree.domain_version(domain)?, provider)
                };
                return Some((u128::from(u64::try_from(base).ok()?) << 64) | u128::from(provider));
            }
            let base = u64::try_from(self.tree.domain_version(domain)?).ok()?;
            // Only an unchanged positive/current source answer may use the
            // local certificate. Native absence fallback remains uncertified.
            if matches!(self.tree.resolve(query), M::Unsupported(_)) {
                return None;
            }
            let provider = match &self.variable_absence {
                Some(coverage) => coverage.issuer?,
                None => 0,
            };
            return Some((u128::from(base) << 64) | u128::from(provider));
        }
        if let dm_ir::ReadDomain::OwnerCallable(query) = domain {
            let base = u64::try_from(self.tree.domain_version(domain)?).ok()?;
            // Global authored-name exclusion can change fallback answers even
            // when this owner's source declarations are unchanged. Such reads
            // are not certified by a local owner token.
            if matches!(self.tree.resolve(query), M::Unsupported(_)) {
                return None;
            }
            let provider = if self.callable_absence.is_some()
                || self.intrinsic_methods.is_some()
                || self.retained_methods.is_some()
            {
                self.callable_issuer?
            } else {
                0
            };
            return Some((u128::from(base) << 64) | u128::from(provider));
        }
        if matches!(domain, dm_ir::ReadDomain::OwnerHierarchy(_)) {
            // These three queries are delegated unchanged to the current source
            // resolver. Its certificate includes the pinned hierarchy gate; no
            // engine method/variable/scalar fallback can answer them here.
            return self.tree.domain_version(domain);
        }
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
/// Verify the finite lexical intrinsic against every physical variable domain.
/// Root globals must participate even though general authored-name exclusion
/// treats pinned compiler constants separately.
fn check_provider_source(
    engine: &crate::engine::EngineSnapshot,
    frontend: &dm_tree::frontend::ColdFrontend,
) -> Result<(), String> {
    crate::engine_abi_coverage::NamedEngineCoverage::pinned(engine)?;
    if frontend.engine.as_ref().map(|status| status.identity) != Some(engine.identity()) {
        return Err("host coverage belongs to another engine capture".into());
    }
    Ok(())
}

fn verify_lexical_type_namespace(
    catalog: &serde_json::Value,
    physical_names: &BTreeSet<SymbolId>,
) -> Result<(), String> {
    for owner in catalog["Types"]
        .as_array()
        .ok_or("native variable catalog absent")?
    {
        for domain in ["Variables", "GlobalVariables"] {
            if let Some(values) = owner.get(domain) {
                let values = values
                    .as_object()
                    .ok_or("native variable domain malformed")?;
                if values.contains_key("__TYPE__") {
                    return Err("pinned catalog declares __TYPE__ storage".into());
                }
            }
        }
        if let Some(values) = owner.get("ConstVariables") {
            for value in values
                .as_array()
                .ok_or("native const variable catalog malformed")?
            {
                if value
                    .as_str()
                    .ok_or("native const variable name malformed")?
                    == "__TYPE__"
                {
                    return Err("pinned catalog declares __TYPE__ constant storage".into());
                }
            }
        }
    }
    if physical_names.contains(&SymbolId::of("__TYPE__")) {
        return Err("pinned generated catalog declares __TYPE__ storage".into());
    }
    Ok(())
}

#[cfg(test)]
#[path = "engine_host/tests.rs"]
mod tests;

#[cfg(test)]
#[path = "engine_host/owner_domain_tests.rs"]
mod owner_domain_tests;
