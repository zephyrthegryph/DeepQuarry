//! Immutable engine-only payloads; source wrappers are freshly minted every request.
use super::*;
const CATALOG: &[u8] =
    include_bytes!("../../../../fixtures/native_template_nativebuiltins_5161687.json");
type NativeMethods = Arc<BTreeMap<(SymbolId, SymbolId), Arc<[u8]>>>;
type RetainedMethods = Arc<BTreeMap<(SymbolId, SymbolId, bool), u32>>;
pub(crate) struct PinnedEngineProviders {
    pub(super) engine: u128,
    pub(super) callables: CallableProviders,
    pub(super) variables: VariableProviders,
}
pub(super) struct CallableProviders {
    pub closed: Arc<intrinsic_methods::ClosedNamespace>,
    pub issuer: Option<u64>,
    pub engine: u128,
    pub retained: RetainedMethods,
    pub methods: NativeMethods,
    pub spellings: SymbolTable,
    pub intrinsic: BTreeSet<SymbolId>,
}
pub(super) struct VariableProviders {
    pub issuer: Option<u64>,
    pub spellings: SymbolTable,
    pub intrinsic: BTreeSet<SymbolId>,
    pub constants: ConstantCatalog,
    pub positive_constants: BTreeMap<SymbolId, SemanticValue>,
    pub identity: u128,
}
impl CallableProviders {
    pub fn capture(engine: &crate::engine::EngineSnapshot) -> Result<Self, String> {
        crate::engine_abi_coverage::NamedEngineCoverage::pinned(engine)?;
        let retained = crate::engine::procedure_abi::RetainedMethods::capture_entries(engine)?;
        let catalog: serde_json::Value =
            serde_json::from_slice(CATALOG).map_err(|error| error.to_string())?;
        let (methods, spellings) = intrinsic_methods::IntrinsicMethods::capture_payload(&catalog)?;
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
        static NEXT: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(1);
        let issuer = NEXT
            .fetch_update(
                std::sync::atomic::Ordering::Relaxed,
                std::sync::atomic::Ordering::Relaxed,
                |value| value.checked_add(1),
            )
            .ok();
        Ok(Self {
            issuer,
            engine: engine.identity(),
            closed: intrinsic_methods::ClosedNamespace::capture(&catalog)?,
            retained,
            methods,
            spellings,
            intrinsic,
        })
    }
}
impl VariableProviders {
    pub fn capture(engine: &crate::engine::EngineSnapshot) -> Result<Self, String> {
        crate::engine_abi_coverage::NamedEngineCoverage::pinned(engine)?;
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
        verify_lexical_type_namespace(&catalog, &intrinsic)?;
        let pinned_constants = ConstantCatalog::native_516_1687(&mut catalog_symbols)
            .map_err(|error| format!("pinned constants {error:?}"))?;
        let mut positive_constants = BTreeMap::new();
        for spelling in ["TRUE", "FALSE"] {
            let name = SymbolId::of(spelling);
            let value = pinned_constants.values.get(&name);
            let physically_const = engine
                .declaration_modifiers(SymbolId::of("/"), name)
                .map_err(|error| format!("pinned constant metadata {error:?}"))?
                .is_some_and(|flags| flags & 2 != 0);
            if let Some(value) = value.filter(|_| physically_const) {
                positive_constants.insert(name, value.clone());
            }
        }
        let mut bytes =
            b"pinned-authored-variable-absence-v4;physical-boolean-constants;captured-slot-uniqueness;lexical-type-full-namespace-exclusion".to_vec();
        bytes.extend_from_slice(&engine.identity().to_le_bytes());
        bytes.extend_from_slice(crate::engine::catalog::CATALOG_SCHEMA.as_bytes());
        bytes.extend_from_slice(CATALOG);
        for name in &intrinsic {
            bytes.extend_from_slice(&name.bits().to_le_bytes());
        }

        static NEXT: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(1);
        let issuer = NEXT
            .fetch_update(
                std::sync::atomic::Ordering::Relaxed,
                std::sync::atomic::Ordering::Relaxed,
                |value| value.checked_add(1),
            )
            .ok();
        Ok(Self {
            issuer,
            spellings: catalog_symbols,
            intrinsic,
            constants: pinned_constants,
            positive_constants,
            identity: xxhash_rust::xxh3::xxh3_128(&bytes),
        })
    }
}
impl PinnedEngineProviders {
    pub(crate) fn capture(engine: &crate::engine::EngineSnapshot) -> Result<Arc<Self>, String> {
        Ok(Arc::new(Self {
            engine: engine.identity(),
            callables: CallableProviders::capture(engine)?,
            variables: VariableProviders::capture(engine)?,
        }))
    }
}

impl PinnedEngineProviders {
    pub(crate) fn census(self: &Arc<Self>, census: &mut crate::heap_census::HeapCensus) {
        if !census.arc_object("host.engine.providers", self) {
            return;
        }
        self.callables.closed.census(census);
        if census.arc_object("host.intrinsic_methods", &self.callables.methods) {
            census.collection_entries::<((SymbolId, SymbolId), Arc<[u8]>)>(
                "host.intrinsic_methods",
                self.callables.methods.as_ref() as *const _ as usize,
                self.callables.methods.len(),
            );
            for bytes in self.callables.methods.values() {
                census.slice("host.intrinsic_methods", bytes, true);
            }
        }
        if census.arc_object("host.retained_methods.entries", &self.callables.retained) {
            census.collection_entries::<((SymbolId, SymbolId, bool), u32)>(
                "host.retained_methods.entries",
                self.callables.retained.as_ref() as *const _ as usize,
                self.callables.retained.len(),
            );
        }
        census.observe_items(
            "host.engine.providers.callable_names",
            self.callables.intrinsic.len(),
        );
        census.observe_items(
            "host.engine.providers.variable_names",
            self.variables.intrinsic.len(),
        );
        if census.arc_object(
            "host.engine.providers.constants",
            &self.variables.constants.values,
        ) {
            for value in self.variables.constants.values.values() {
                census.semantic_value("host.engine.providers.constants", value);
            }
        }
        for value in self.variables.positive_constants.values() {
            census.semantic_value("host.engine.providers.booleans", value);
        }
        census.unknown("host.engine.providers","private symbol/set/map nodes and control layout excluded; exposed shared objects and value payloads counted");
    }
}
