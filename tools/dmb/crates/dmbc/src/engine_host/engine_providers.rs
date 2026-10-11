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
/// Closed ordinary-global name policy under the existing pinned native ABI
/// interpretation. Exclusions need not have supported values or runtime behavior.
#[derive(Debug)]
pub(super) struct OrdinaryGlobalNames {
    excluded: BTreeSet<SymbolId>,
}
impl OrdinaryGlobalNames {
    pub(super) fn covers(&self, name: SymbolId) -> bool {
        !self.excluded.contains(&name)
    }
    /// The pinned root catalog excludes every catalogued predefined name,
    /// including opaque values; the pinned OD lexical dispatcher excludes its
    /// special identifiers. This is a separate ordinary-name interpretation,
    /// not a claim that the positive constant catalog is complete.
    pub(super) fn covers_predefined_absence(&self, name: SymbolId) -> bool {
        !self.excluded.contains(&name)
    }
    pub(super) fn census(self: &Arc<Self>, census: &mut crate::heap_census::HeapCensus) {
        if census.arc_object("host.ordinary_global_names", self) {
            census.observe_items("host.ordinary_global_names.excluded", self.excluded.len());
            census.unknown(
                "host.ordinary_global_names",
                "private BTreeSet node backing excluded",
            );
        }
    }
}
pub(super) struct VariableProviders {
    pub native_types: Arc<BTreeSet<SymbolId>>,
    pub native_callable_names: Arc<BTreeSet<SymbolId>>,
    pub issuer: Option<u64>,
    pub spellings: SymbolTable,
    pub intrinsic: BTreeSet<SymbolId>,
    pub constants: ConstantCatalog,
    pub positive_constants: BTreeMap<SymbolId, SemanticValue>,
    pub ordinary_globals: Arc<OrdinaryGlobalNames>,
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
        // Source reference: OpenDream 1362abc5accbc2037df9b45efa1de13fb1bb677f,
        // DMExpressionBuilder identifier dispatcher 608..653. It checks authored
        // globals first, then a closed lexical special-name set, then absence.
        // All specials remain exclusions; this does not assert their BYOND value
        // or runtime support. Root catalog constants are separate positive facts.
        let mut excluded = intrinsic.clone();
        excluded.extend(pinned_constants.values.keys().copied());
        for name in [
            "src",
            "usr",
            "args",
            "callee",
            "caller",
            "world",
            "__TYPE__",
            "__IMPLIED_TYPE__",
            "__PROC__",
            "global",
        ] {
            excluded.insert(SymbolId::of(name));
        }
        for owner in catalog["Types"]
            .as_array()
            .ok_or("native variable catalog absent")?
        {
            if owner["Path"].as_str() == Some("/") {
                if let Some(values) = owner.get("GlobalVariables") {
                    for name in values
                        .as_object()
                        .ok_or("root constant catalog malformed")?
                        .keys()
                    {
                        excluded.insert(SymbolId::of(name));
                    }
                }
            }
        }
        let ordinary_globals = Arc::new(OrdinaryGlobalNames { excluded });
        // Conservative bootstrap namespace interpretation, qualified by the
        // exact pinned template/schema above. Catalog-only native names remain
        // exclusions, never fabricated positive definitions or runtime slots.
        let seed = engine.frontend_seed();
        let mut native_types: BTreeSet<_> = seed
            .hierarchy
            .parents
            .iter()
            .map(|(path, _)| *path)
            .collect();
        for ty in catalog["Types"]
            .as_array()
            .ok_or("native type catalog absent")?
        {
            native_types.insert(SymbolId::of(
                ty["Path"].as_str().ok_or("native type path malformed")?,
            ));
        }
        let mut native_callable_names: BTreeSet<_> = seed
            .intrinsics
            .iter()
            .filter(|member| {
                matches!(
                    member.kind,
                    dm_tree::MemberKind::Proc | dm_tree::MemberKind::Verb
                )
            })
            .map(|member| member.name)
            .collect();
        for procedure in catalog["Procs"]
            .as_array()
            .ok_or("native procedure catalog absent")?
        {
            native_callable_names.insert(SymbolId::of(
                procedure["Name"]
                    .as_str()
                    .ok_or("native procedure name malformed")?,
            ));
        }
        // Versioned source policy is bound to the exact template/schema already
        // checked by NamedEngineCoverage::pinned above, never an ambient version.
        let mut bytes = b"pinned-authored-variable-absence-v7;lexical-implied-type-storage-exclusion;ordinary-root-global-and-predefined-absence;native-ABI-5161687-schema1;OD1362abc5accbc2037df9b45efa1de13fb1bb677f;dispatcher-SHA256=33cd1daf2c2090b6de58ea5ccecdc28918fb9b71deff84c51cbc693795b5bd38;objecttree-SHA256=2c19b1ea64495e67516b972d57aed171a4044eb0ae7835b4eb84ed2ee80a3440;vars-SHA256=ce372f294699c7c3d39c3a52e306d269800c033edb9f82620faf5fe4d3fc66ce".to_vec();
        bytes.extend_from_slice(&engine.interpretation_schema().to_le_bytes());
        bytes.extend_from_slice(b";pinned-semantic-namespace-v1;seeded-type-roster;ordinary-owner-variable-and-callable-exclusions");
        for path in &native_types {
            bytes.extend_from_slice(&path.bits().to_le_bytes());
        }
        bytes.push(0);
        for name in &native_callable_names {
            bytes.extend_from_slice(&name.bits().to_le_bytes());
        }
        for name in &ordinary_globals.excluded {
            bytes.extend_from_slice(&name.bits().to_le_bytes());
        }
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
            native_types: Arc::new(native_types),
            native_callable_names: Arc::new(native_callable_names),
            issuer,
            spellings: catalog_symbols,
            intrinsic,
            constants: pinned_constants,
            positive_constants,
            ordinary_globals,
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
        self.variables.ordinary_globals.census(census);
        for (label, names) in [
            (
                "host.variable_coverage.native_types",
                &self.variables.native_types,
            ),
            (
                "host.variable_coverage.native_callable_names",
                &self.variables.native_callable_names,
            ),
        ] {
            if census.arc_object(label, names) {
                census.observe_items(label, names.len());
                census.unknown(label, "private BTreeSet node backing excluded");
            }
        }
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
