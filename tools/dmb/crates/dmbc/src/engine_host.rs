//! Immutable compiler configuration resolver; no output tables or legacy bindings.
#[path = "engine_constants.rs"]
mod constants;
use dm_ir::{
    ResolveQuery as Q, ResolvedMeaning as M, Resolver, SemanticValue, SymbolId, SymbolTable,
};
use std::{
    collections::{BTreeMap, BTreeSet},
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
    ordinary: Arc<BTreeSet<SymbolId>>,
    completeness: Completeness,
    identity: u128,
}
impl RuntimeAliasCatalog {
    pub fn new(
        schema: u128,
        symbols: &SymbolTable,
        aliases: Vec<(SymbolId, SymbolId)>,
        ordinary: Vec<SymbolId>,
        completeness: Completeness,
    ) -> Result<Self, HostError> {
        let ordinary: BTreeSet<_> = ordinary.into_iter().collect();
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
        for id in &ordinary {
            if symbols.text(*id).is_none() {
                return Err(HostError::UnknownSymbol(*id));
            }
        }
        let mut bytes = b"dm-runtime-alias-catalog-v1\0".to_vec();
        bytes.extend_from_slice(&schema.to_le_bytes());
        bytes.push(completeness as u8);
        bytes.extend_from_slice(&(mapping.len() as u64).to_le_bytes());
        for (alias, target) in &mapping {
            bytes.extend_from_slice(&alias.bits().to_le_bytes());
            bytes.extend_from_slice(&target.bits().to_le_bytes());
        }
        bytes.extend_from_slice(&(ordinary.len() as u64).to_le_bytes());
        for id in &ordinary {
            bytes.extend_from_slice(&id.bits().to_le_bytes());
        }
        Ok(Self {
            aliases: Arc::new(mapping),
            ordinary: Arc::new(ordinary),
            completeness,
            identity: xxhash_rust::xxh3::xxh3_128(&bytes),
        })
    }
    pub fn identity(&self) -> u128 {
        self.identity
    }
}
#[derive(Clone, Debug)]
pub struct EngineResolverHost<R> {
    tree: Arc<R>,
    constants: ConstantCatalog,
    runtime: RuntimeAliasCatalog,
    callable_absence: Option<Arc<BTreeSet<SymbolId>>>,
}
impl<R: Resolver> EngineResolverHost<R> {
    pub fn new(tree: Arc<R>, constants: ConstantCatalog, runtime: RuntimeAliasCatalog) -> Self {
        Self {
            tree,
            constants,
            runtime,
            callable_absence: None,
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
        let catalog: serde_json::Value = serde_json::from_slice(include_bytes!(
            "../../../fixtures/native_template_nativebuiltins_5161687.json"
        ))
        .map_err(|error| error.to_string())?;
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
    pub fn configuration_identity(&self) -> u128 {
        let mut bytes = b"dm-engine-host-v1\0".to_vec();
        bytes.extend_from_slice(&self.constants.identity.to_le_bytes());
        bytes.extend_from_slice(&self.runtime.identity.to_le_bytes());
        if let Some(names) = &self.callable_absence {
            bytes.extend_from_slice(b"pinned-authored-callable-absence-v1");
            bytes.extend_from_slice(include_bytes!(
                "../../../fixtures/native_template_nativebuiltins_5161687.json"
            ));
            for name in names.iter() {
                bytes.extend_from_slice(&name.bits().to_le_bytes());
            }
        }
        xxhash_rust::xxh3::xxh3_128(&bytes)
    }
}
impl<R: Resolver + Send> Resolver for EngineResolverHost<R> {
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
                let (owner, name, presence) = match query {
                    Q::Proc { owner, name, .. } => (owner, name, false),
                    Q::HasMemberProc { owner, name } => (owner, name, true),
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
mod tests {
    use super::*;
    struct Missing;
    impl Resolver for Missing {
        fn resolve(&self, _: Q) -> M {
            M::Missing
        }
    }
    #[test]
    fn exact_constant_bits_and_bytes_preserve_partial_negatives() {
        let mut symbols = SymbolTable::default();
        let constants = ConstantCatalog::new(
            1,
            &mut symbols,
            vec![
                ("X".into(), SemanticValue::NumberBits(0x80000000)),
                ("TEXT".into(), SemanticValue::Text(Arc::from([0xff, 0]))),
            ],
            Completeness::Partial,
        )
        .unwrap();
        let runtime =
            RuntimeAliasCatalog::new(1, &symbols, vec![], vec![], Completeness::Partial).unwrap();
        let host = EngineResolverHost::new(Arc::new(Missing), constants, runtime);
        assert_eq!(
            host.resolve(Q::PredefinedConstant(SymbolId::of("X"))),
            M::Value(SemanticValue::NumberBits(0x80000000))
        );
        assert_eq!(
            host.resolve(Q::PredefinedConstant(SymbolId::of("TEXT"))),
            M::Value(SemanticValue::Text(Arc::from([0xff, 0])))
        );
        let absent = Q::PredefinedConstant(SymbolId::of("absent"));
        assert_eq!(host.resolve(absent), M::Unsupported(absent));
    }
    #[test]
    fn captured_aliases_and_ordinary_types_do_not_imply_negative_completeness() {
        let mut symbols = SymbolTable::default();
        let ordinary = symbols.intern("/obj").unwrap();
        let alias = symbols.intern("/obj{a=1}").unwrap();
        let constants =
            ConstantCatalog::new(1, &mut symbols, vec![], Completeness::Complete).unwrap();
        let runtime = RuntimeAliasCatalog::new(
            1,
            &symbols,
            vec![(alias, ordinary)],
            vec![ordinary],
            Completeness::Partial,
        )
        .unwrap();
        let host = EngineResolverHost::new(Arc::new(Missing), constants, runtime);
        assert_eq!(host.resolve(Q::RuntimeType(alias)), M::Symbol(ordinary));
        assert_eq!(host.resolve(Q::RuntimeType(ordinary)), M::Symbol(ordinary));
        let absent = Q::RuntimeType(SymbolId::of("/unknown"));
        assert_eq!(host.resolve(absent), M::Unsupported(absent));
        assert_eq!(
            host.resolve(Q::PredefinedConstant(SymbolId::of("missing"))),
            M::Missing
        );
    }
}
