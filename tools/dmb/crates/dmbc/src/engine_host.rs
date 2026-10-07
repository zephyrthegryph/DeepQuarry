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
    tree: Arc<R>,
    constants: ConstantCatalog,
    runtime: RuntimeAliasCatalog,
    callable_absence: Option<Arc<HashSet<SymbolId>>>,
    intrinsic_methods: Option<Arc<intrinsic_methods::IntrinsicMethods>>,
    variable_absence: Option<Arc<VariableAbsence>>,
}
impl<R: Resolver> EngineResolverHost<R> {
    pub fn new(tree: Arc<R>, constants: ConstantCatalog, runtime: RuntimeAliasCatalog) -> Self {
        Self {
            tree,
            constants,
            runtime,
            callable_absence: None,
            intrinsic_methods: None,
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
            if engine.declaration_modifiers(SymbolId::of("/"), name)
                .map_err(|error| format!("pinned constant metadata {error:?}"))?
                .is_some_and(|flags| flags & 2 != 0)
                && value.is_some() && self.constants.values.get(&name) == value
            {
                positive_constants.insert(name, value.unwrap().clone());
            }
        }
        let mut bytes =
            b"pinned-authored-variable-absence-v2;physical-boolean-constants".to_vec();
        bytes.extend_from_slice(&engine.identity().to_le_bytes());
        bytes.extend_from_slice(crate::engine::catalog::CATALOG_SCHEMA.as_bytes());
        bytes.extend_from_slice(CATALOG);
        for name in &intrinsic {
            bytes.extend_from_slice(&name.bits().to_le_bytes());
        }
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
        if self.callable_absence.is_some() {
            bytes.extend_from_slice(b"pinned-callable-policy-v2;explicit-runtime-receiver-methods");
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
                        {
                            if let Some(value) = coverage.positive_constants.get(&name) {
                                // Authored declarations, including unresolved scalar
                                // outcomes, were handled above and always shadow this.
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
mod tests {
    use super::*;
    struct Missing;
    impl Resolver for Missing {
        fn resolve(&self, _: Q) -> M {
            M::Missing
        }
    }
    #[test]
    fn unordered_type_membership_has_canonical_content_and_policy_identity() {
        let mut symbols = SymbolTable::default();
        let first = symbols.intern("/datum/first").unwrap();
        let second = symbols.intern("/datum/second").unwrap();
        let left = RuntimeAliasCatalog::new(
            1,
            &symbols,
            Vec::new(),
            vec![first, second],
            Completeness::Partial,
        )
        .unwrap();
        let right = RuntimeAliasCatalog::new(
            1,
            &symbols,
            Vec::new(),
            vec![second, first, second],
            Completeness::Partial,
        )
        .unwrap();
        assert_eq!(left.identity(), right.identity());
        assert_eq!(left.policy_identity(), right.policy_identity());
        assert!(left.ordinary.contains(&first));
        assert!(right.ordinary.contains(&second));
    }
    #[test]
    fn pinned_receiver_methods_lower_dynamically_without_fabricated_abi() {
        use std::path::Path;
        struct Source;
        impl dm_preprocess::SourceProvider for Source {
            fn read(&self, _: &Path) -> Result<String, String> {
                Ok(
                    "/datum/probe\n/proc/copy_probe(list/items)\n    return items.Copy(1, 2)\n"
                        .into(),
                )
            }
        }
        let engine = crate::engine::EngineSnapshot::from_bytes(
            include_bytes!("../../../fixtures/native_template.bin"),
            1,
        )
        .unwrap()
        .with_bootstrap_catalog()
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
        let mut symbols = frontend.snapshot.tree.symbols().clone();
        let constants = ConstantCatalog::native_516_1687(&mut symbols).unwrap();
        let runtime = RuntimeAliasCatalog::new(
            engine.identity(),
            &symbols,
            Vec::new(),
            frontend
                .snapshot
                .tree
                .types()
                .iter()
                .map(|node| node.path)
                .collect(),
            Completeness::Partial,
        )
        .unwrap();
        let host = EngineResolverHost::new(frontend.snapshot.tree.clone(), constants, runtime)
            .with_pinned_callables(&engine, &frontend)
            .unwrap();
        let list = SymbolId::of("/list");
        let copy = SymbolId::of("Copy");
        assert_eq!(
            host.resolve(Q::Proc {
                owner: list,
                name: copy,
                verb: false
            }),
            M::IntrinsicProc {
                declaring_owner: list,
                name: copy
            }
        );
        assert_eq!(
            host.resolve(Q::Proc {
                owner: list,
                name: copy,
                verb: true
            }),
            M::Missing
        );
        assert_eq!(
            host.resolve(Q::HasMemberProc {
                owner: list,
                name: copy
            }),
            M::Presence(true)
        );
        let read = SymbolId::of("Read");
        assert_eq!(
            host.resolve(Q::Proc {
                owner: SymbolId::of("/datum/probe"),
                name: read,
                verb: false
            }),
            M::IntrinsicProc {
                declaring_owner: SymbolId::of("/datum"),
                name: read
            }
        );
        for query in [
            Q::GlobalProc(copy),
            Q::Proc {
                owner: SymbolId::of("/never_captured"),
                name: copy,
                verb: false,
            },
            Q::Proc {
                owner: list,
                name: SymbolId::of("never_authored"),
                verb: false,
            },
        ] {
            assert_eq!(host.resolve(query), M::Unsupported(query));
        }
        let body = frontend.body(&frontend.bodies[0]).unwrap();
        let inputs = dm_codegen_byond::ProcedureInputs {
            parameters: vec!["items".into()],
            parameter_types: [("items".into(), "/list".into())].into(),
            ..Default::default()
        };
        let lowered = dm_codegen_byond::compile_simple_proc_with_resolver(
            &body.children,
            &inputs,
            &symbols,
            &host,
        )
        .unwrap();
        let receiver_call = lowered
            .procedure
            .code
            .items
            .iter()
            .find_map(|item| match item {
                dm_codegen_byond::Item::Instruction(instruction)
                    if instruction.opcode == byond_dmb::bytecode::opcode::CALL =>
                {
                    Some(instruction)
                }
                _ => None,
            })
            .expect("receiver Copy call");
        assert_eq!(
            receiver_call.operands,
            vec![
                dm_codegen_byond::Word::Variable(dm_codegen_byond::VariableWord::SetCache(
                    Box::new(dm_codegen_byond::VariableWord::Arg(0)),
                    Box::new(dm_codegen_byond::VariableWord::DynamicProc("Copy".into())),
                )),
                dm_codegen_byond::Word::Immediate(2),
            ]
        );
    }
    #[test]
    fn pinned_global_callable_absence_keeps_source_and_intrinsic_domains_distinct() {
        use std::path::Path;
        struct Source;
        impl dm_preprocess::SourceProvider for Source {
            fn read(&self, _: &Path) -> Result<String, String> {
                Ok("/datum/probe/proc/member_only()\n    return 1\n/proc/global_only()\n    return 2\n".into())
            }
        }
        let engine = crate::engine::EngineSnapshot::from_bytes(
            include_bytes!("../../../fixtures/native_template.bin"),
            1,
        )
        .unwrap()
        .with_bootstrap_catalog()
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
        let mut symbols = frontend.snapshot.tree.symbols().clone();
        let constants = ConstantCatalog::native_516_1687(&mut symbols).unwrap();
        let runtime = RuntimeAliasCatalog::new(
            engine.identity(),
            &symbols,
            Vec::new(),
            frontend
                .snapshot
                .tree
                .types()
                .iter()
                .map(|node| node.path)
                .collect(),
            Completeness::Partial,
        )
        .unwrap();
        let host = EngineResolverHost::new(frontend.snapshot.tree.clone(), constants, runtime)
            .with_pinned_callables(&engine, &frontend)
            .unwrap();
        assert_eq!(
            host.resolve(Q::GlobalProc(SymbolId::of("member_only"))),
            M::Missing
        );
        assert!(
            matches!(host.resolve(Q::GlobalProc(SymbolId::of("global_only"))), M::Member { owner, .. } if owner == SymbolId::of("/"))
        );
        assert!(matches!(
            host.resolve(Q::Proc {
                owner: SymbolId::of("/datum/probe"),
                name: SymbolId::of("member_only"),
                verb: false
            }),
            M::Member { .. }
        ));
        for name in ["sin", "never_authored_name"] {
            let query = Q::GlobalProc(SymbolId::of(name));
            assert_eq!(host.resolve(query), M::Unsupported(query));
        }
    }
    #[test]
    fn source_membership_changes_do_not_change_compiler_policy_identity() {
        use std::path::Path;
        struct Source(&'static str);
        impl dm_preprocess::SourceProvider for Source {
            fn read(&self, _: &Path) -> Result<String, String> {
                Ok(self.0.into())
            }
        }
        let engine = crate::engine::EngineSnapshot::from_bytes(
            include_bytes!("../../../fixtures/native_template.bin"),
            1,
        )
        .unwrap()
        .with_bootstrap_catalog()
        .unwrap();
        let seed = engine.frontend_seed();
        let build = |source| {
            let frontend = dm_tree::frontend::build_with_config(
                Path::new("project.dme"),
                &Source(source),
                &Default::default(),
                dm_tree::frontend::FrontendConfig {
                    workers: 1,
                    engine: Some(&seed),
                    observer: None,
                },
            )
            .unwrap();
            let mut symbols = frontend.snapshot.tree.symbols().clone();
            let constants = ConstantCatalog::native_516_1687(&mut symbols).unwrap();
            let runtime = RuntimeAliasCatalog::new(
                engine.identity(),
                &symbols,
                Vec::new(),
                frontend
                    .snapshot
                    .tree
                    .types()
                    .iter()
                    .map(|node| node.path)
                    .collect(),
                Completeness::Partial,
            )
            .unwrap();
            EngineResolverHost::new(frontend.snapshot.tree.clone(), constants, runtime)
                .with_pinned_callables(&engine, &frontend)
                .unwrap()
                .with_pinned_variables(&engine, &frontend)
                .unwrap()
        };
        let before = build("/datum/probe\n");
        let after = build("/datum/probe\n/datum/unrelated\n    var/fresh = 1\n    proc/new_function()\n        return fresh\n");
        assert_eq!(
            before.configuration_identity(),
            after.configuration_identity()
        );
        let type_query = Q::RuntimeType(SymbolId::of("/datum/unrelated"));
        assert_ne!(
            before.resolve(type_query.clone()),
            after.resolve(type_query)
        );
        let variable_query = Q::Var {
            owner: SymbolId::of("/datum/unrelated"),
            name: SymbolId::of("fresh"),
        };
        assert_ne!(
            before.resolve(variable_query.clone()),
            after.resolve(variable_query)
        );
        let proc_query = Q::Proc {
            owner: SymbolId::of("/datum/unrelated"),
            name: SymbolId::of("new_function"),
            verb: false,
        };
        assert_ne!(
            before.resolve(proc_query.clone()),
            after.resolve(proc_query)
        );
    }
    #[test]
    fn pinned_authored_variable_absence_preserves_global_and_field_shadow_domains() {
        use std::path::Path;
        struct Source;
        impl dm_preprocess::SourceProvider for Source {
            fn read(&self, _: &Path) -> Result<String, String> {
                Ok("var/global_only = 4\nvar/shared_name = 1\n/datum/probe\n    var/shared_name = 2\n/datum/probe/proc/read()\n    return shared_name + global_only\n/proc/root_read()\n    return shared_name\n".into())
            }
        }
        let bytes = include_bytes!("../../../fixtures/native_template.bin");
        let engine = crate::engine::EngineSnapshot::from_bytes(bytes, 1)
            .unwrap()
            .with_bootstrap_catalog()
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
        let mut symbols = frontend.snapshot.tree.symbols().clone();
        let constants = ConstantCatalog::native_516_1687(&mut symbols).unwrap();
        let runtime = RuntimeAliasCatalog::new(
            engine.identity(),
            &symbols,
            Vec::new(),
            frontend
                .snapshot
                .tree
                .types()
                .iter()
                .map(|node| node.path)
                .collect(),
            Completeness::Partial,
        )
        .unwrap();
        let base = EngineResolverHost::new(frontend.snapshot.tree.clone(), constants, runtime);
        let base_identity = base.configuration_identity();
        let host = base.with_pinned_variables(&engine, &frontend).unwrap();
        assert_ne!(host.configuration_identity(), base_identity);
        let owner = SymbolId::of("/datum/probe");
        let root = SymbolId::of("/");
        let global = SymbolId::of("global_only");
        let shadow = SymbolId::of("shared_name");
        for (spelling, value) in [("TRUE", 1.0_f32), ("FALSE", 0.0_f32)] {
            let name = SymbolId::of(spelling);
            assert_eq!(host.resolve(Q::GlobalVar(name)), M::Value(SemanticValue::NumberBits(value.to_bits())));
            assert_eq!(host.resolve(Q::Constant { owner, name }), M::Value(SemanticValue::NumberBits(value.to_bits())));
        }
        assert!(
            matches!(host.resolve(Q::GlobalVar(global)),M::Member{owner:actual,..} if actual==root)
        );
        assert_eq!(
            host.resolve(Q::Var {
                owner,
                name: global
            }),
            M::Missing
        );
        assert_eq!(
            host.resolve(Q::VarStorage {
                owner,
                name: global
            }),
            M::Missing
        );
        assert_eq!(
            host.resolve(Q::HasMemberVar {
                owner,
                name: global
            }),
            M::Presence(false)
        );
        assert!(
            matches!(host.resolve(Q::VarStorage{owner,name:shadow}),M::InstanceField{declaring_owner,name} if declaring_owner==owner&&name==shadow)
        );
        assert_eq!(
            host.resolve(Q::Var {
                owner,
                name: SymbolId::of("NORTH")
            }),
            M::Missing
        );
        assert!(matches!(
            host.resolve(Q::PredefinedConstant(SymbolId::of("NORTH"))),
            M::Value(_)
        ));
        for name in ["never_captured_variable"] {
            let query = Q::Var {
                owner,
                name: SymbolId::of(name),
            };
            assert_eq!(host.resolve(query), M::Unsupported(query));
        }
        let unknown_owner = Q::Var {
            owner: SymbolId::of("/never_captured_owner"),
            name: global,
        };
        assert_eq!(host.resolve(unknown_owner), M::Unsupported(unknown_owner));
        let intrinsic = Q::DeclaredVarType {
            owner,
            name: SymbolId::of("tag"),
        };
        assert_eq!(host.resolve(intrinsic), M::Unsupported(intrinsic));
        let tree = &frontend.snapshot.tree;
        let instance = tree
            .resolve(
                tree.lookup_type(owner).unwrap(),
                shadow,
                dm_tree::MemberKind::Var,
            )
            .unwrap();
        assert_eq!(tree.override_chain(instance), vec![instance]);
        for body in frontend.bodies.iter() {
            let parsed = frontend.body(body).unwrap();
            let member = tree.member(body.member).unwrap();
            let path = tree.type_node(member.owner).unwrap().path;
            let inputs = dm_codegen_byond::ProcedureInputs {
                current_type_path: (path != root)
                    .then(|| tree.symbols().text(path).unwrap().to_owned()),
                ..Default::default()
            };
            let code = dm_codegen_byond::compile_simple_proc_with_resolver(
                &parsed.children,
                &inputs,
                tree.symbols(),
                &host,
            )
            .unwrap();
            let expected = if path == root { shadow } else { global };
            let expected_text = tree.symbols().text(expected).unwrap();
            let globals: Vec<_> = code
                .procedure
                .code
                .items
                .iter()
                .flat_map(|item| match item {
                    dm_codegen_byond::Item::Instruction(instruction) => instruction
                        .operands
                        .iter()
                        .filter_map(|word| match word {
                            dm_codegen_byond::Word::Variable(
                                dm_codegen_byond::VariableWord::Global(name),
                            ) => Some(name.as_str()),
                            _ => None,
                        })
                        .collect::<Vec<_>>(),
                    _ => Vec::new(),
                })
                .collect();
            assert_eq!(globals, vec![expected_text]);
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
