//! Compact procedure completion: discard rich IR on its producing worker.
use super::*;
use crate::debug_sources::DebugOrigins;
use dm_codegen_byond::lower_resolver::ResolverProc;

pub use super::procedure_artifact::ReusableProcedureArtifact;
pub use crate::modified_initializers::PreparedSeed as PreparedModifiedSeed;
pub struct PreparedContribution {
    identity: UnitIdentity,
    effective: bool,
    contribution: super::procedure_artifact::Contribution,
    required_types: Arc<[SymbolId]>,
    modified_seeds: Vec<PreparedModifiedSeed>,
    modified_recipes: Option<Arc<[crate::modified_initializers::SourceRecipe]>>,
    selected_facts: Option<Arc<dm_ir::SelectedReferences>>,
}
impl PreparedContribution {
    pub(crate) fn current_warnings(
        &self,
        symbols: &SymbolTable,
    ) -> Result<Vec<crate::initializer_policy::warnings::InitializerWarning>, String> {
        self.contribution.current_warnings(symbols)
    }
    pub(crate) fn current_source(&self) -> &dm_tree::frontend::SourceLocation {
        self.contribution.current_source()
    }

    pub(crate) fn selected_facts(&self) -> Option<&Arc<dm_ir::SelectedReferences>> {
        self.selected_facts.as_ref()
    }

    pub(crate) fn variable_record_count(&self) -> Option<usize> {
        self.contribution.variable_record_count()
    }
    pub(crate) fn is_reusable(&self) -> bool {
        self.modified_recipes.is_some()
    }
    pub(crate) fn modified_recipes(&self) -> Option<&[crate::modified_initializers::SourceRecipe]> {
        self.modified_recipes.as_deref()
    }
    pub(crate) fn modified_recipes_owner(
        &self,
    ) -> Option<&Arc<[crate::modified_initializers::SourceRecipe]>> {
        self.modified_recipes.as_ref()
    }
    pub(crate) fn required_types_owner(&self) -> &Arc<[SymbolId]> {
        &self.required_types
    }
    #[cfg(test)]
    pub(crate) fn rebind(
        artifact: &Arc<ReusableProcedureArtifact>,
        frontend: &dm_tree::frontend::ColdFrontend,
        body: &dm_tree::frontend::BodyOccurrence,
        prepared: &crate::procedure_policy::PreparedUnit,
        debug: crate::debug_sources::DebugOrigins,
        required_types: &[SymbolId],
    ) -> Option<Self> {
        Self::rebind_with_modified(
            artifact,
            frontend,
            body,
            prepared,
            debug,
            Arc::from(required_types),
            Vec::new(),
            Some(Arc::from([])),
        )
    }
    pub(crate) fn rebind_with_modified(
        artifact: &Arc<ReusableProcedureArtifact>,
        frontend: &dm_tree::frontend::ColdFrontend,
        body: &dm_tree::frontend::BodyOccurrence,
        prepared: &crate::procedure_policy::PreparedUnit,
        debug: crate::debug_sources::DebugOrigins,
        required_types: Arc<[SymbolId]>,
        modified_seeds: Vec<PreparedModifiedSeed>,
        modified_recipes: Option<Arc<[crate::modified_initializers::SourceRecipe]>>,
    ) -> Option<Self> {
        let identity = crate::lowering::source_unit_identity(frontend, body)
            .ok()?
            .identity;
        prepared.require_production_abi().ok()?;
        if artifact.identity() != identity || !artifact.can_rebind(&prepared.abi) {
            return None;
        }
        let node = frontend.snapshot.tree.member(body.member)?;
        let helpers = artifact.helper_origins(frontend, body, prepared)?;
        let effective = frontend
            .snapshot
            .tree
            .resolve(node.owner, node.name, node.kind)
            == Some(body.member);
        Some(Self {
            identity,
            effective,
            contribution: super::procedure_artifact::Contribution::rebind(
                artifact,
                body.clone(),
                debug,
                prepared.abi.clone(),
                helpers,
            ),
            required_types,
            modified_seeds,
            modified_recipes,
            selected_facts: None,
        })
    }
    pub(crate) fn census(&self, census: &mut crate::heap_census::HeapCensus) {
        self.contribution.census(census);
        if let Some(facts) = &self.selected_facts {
            let size = std::mem::size_of::<dm_ir::SelectedReferences>();
            if census.exposed_buffer(
                "prepared_selections",
                Arc::as_ptr(facts) as usize,
                size,
                size,
            ) && census.vec_payload("prepared_selections", &facts.references)
            {
                for reference in &facts.references {
                    census.vec_payload("prepared_selections", &reference.path);
                }
            }
        }
        census.slice("prepared_type_requests", &self.required_types, true);
        if let Some(recipes) = &self.modified_recipes {
            if census.slice("prepared_modified_recipes", recipes, true) {
                for recipe in recipes.iter() {
                    recipe.retained_census(census);
                }
            }
        }
        census.vec_payload("prepared_modified_seeds", &self.modified_seeds);
        for seed in &self.modified_seeds {
            seed.census(census);
        }
    }

    /// Retain the immutable payload without retaining source/debug provenance
    /// or any current output table assignment.
    pub(crate) fn share_code(&mut self, lease: &super::shared_procedure_code::Lease) {
        self.contribution.share_code(lease);
    }
    pub fn shared_artifact(&self) -> Arc<ReusableProcedureArtifact> {
        self.contribution.shared_artifact()
    }
    pub fn identity(&self) -> UnitIdentity {
        self.identity
    }
    pub fn effective(&self) -> bool {
        self.effective
    }
    pub fn required_types(&self) -> &[SymbolId] {
        &self.required_types
    }
    pub fn modified_seeds(&self) -> &[PreparedModifiedSeed] {
        &self.modified_seeds
    }
    pub fn take_modified_seeds(&mut self) -> Vec<PreparedModifiedSeed> {
        std::mem::take(&mut self.modified_seeds)
    }
}
fn sidecars(
    code: &ResolverProc,
    debug: &DebugOrigins,
    symbols: &SymbolTable,
    types: &mut Vec<SymbolId>,
    seeds: &mut Vec<PreparedModifiedSeed>,
) -> Result<(), IntegrationError> {
    crate::required_types::append_code_requests(code, types, symbols)
        .map_err(IntegrationError::InvalidInitializer)?;
    let mut instances = Vec::new();
    code.procedure.code.for_each_reference(|reference| {
        if matches!(reference, SymRef::Instance(_)) {
            instances.push(reference);
        }
    });
    let mut seen = std::collections::BTreeSet::new();
    for reference in instances {
        let Some(captured) = code.modified_instances.get(&reference) else {
            continue;
        };
        if !seen.insert(reference) {
            continue;
        }
        seeds.push(
            crate::modified_initializers::prepare_seed(reference, captured, debug)
                .map_err(IntegrationError::InvalidInitializer)?,
        );
    }
    Ok(())
}
pub fn prepare_contribution(
    mut unit: LoweredUnit,
    symbols: &SymbolTable,
    source_bindings: &std::collections::BTreeSet<SymRef>,
    external: &ReferenceBindings,
    freeze_detail: bool,
) -> Result<PreparedContribution, IntegrationError> {
    let identity = unit.identity;
    let effective = unit.effective;
    let body_span = unit.origin.expanded_span;
    let mut required_types = Vec::new();
    let mut modified_seeds = Vec::new();
    sidecars(
        &unit.code,
        &unit.debug_origins,
        symbols,
        &mut required_types,
        &mut modified_seeds,
    )?;
    let mut modified_recipes: Option<Vec<_>> = modified_seeds
        .iter()
        .map(|seed| seed.source_recipe(body_span))
        .collect();
    for helper in &unit.source_helpers {
        let start = modified_seeds.len();
        sidecars(
            &helper.code,
            &helper.debug_origins,
            symbols,
            &mut required_types,
            &mut modified_seeds,
        )?;
        if let Some(recipes) = &mut modified_recipes {
            if let Some(helper_recipes) = modified_seeds[start..]
                .iter()
                .map(|seed| seed.helper_source_recipe(helper.argument))
                .collect::<Option<Vec<_>>>()
            {
                recipes.extend(helper_recipes);
            } else {
                modified_recipes = None;
            }
        }
    }
    let selected_facts = unit.selected_references.take();
    let contribution =
        parallel::freeze_unit(unit, symbols, source_bindings, external, freeze_detail)?;
    if required_types.capacity() > required_types.len() {
        required_types.shrink_to_fit();
    }
    if modified_seeds.capacity() > modified_seeds.len() {
        modified_seeds.shrink_to_fit();
    }
    Ok(PreparedContribution {
        identity,
        effective,
        contribution,
        required_types: required_types.into(),
        modified_seeds,
        modified_recipes: modified_recipes.map(Arc::from),
        selected_facts,
    })
}
/// Replay pre-frozen contributions in the same source order as ordinary lowering.
pub fn link_prepared_artifact_tables(
    contributions: Vec<PreparedContribution>,
    symbols: &SymbolTable,
    external: &ReferenceBindings,
    inventory: LinkInventory,
    initialization: Vec<crate::initialization_artifact::InitializationArtifact>,
) -> Result<FrozenBatch, IntegrationError> {
    link_prepared_execution(
        contributions,
        symbols,
        external,
        inventory,
        initialization,
        None,
        None,
    )
}
pub fn link_prepared_artifact_tables_on_executor(
    contributions: Vec<PreparedContribution>,
    symbols: &SymbolTable,
    external: &ReferenceBindings,
    inventory: LinkInventory,
    initialization: Vec<crate::initialization_artifact::InitializationArtifact>,
    executor: &dm_exec::BuildExecutor,
) -> Result<FrozenBatch, IntegrationError> {
    link_prepared_execution(
        contributions,
        symbols,
        external,
        inventory,
        initialization,
        Some(executor),
        None,
    )
}
#[allow(clippy::too_many_arguments)]
pub fn link_prepared_artifact_tables_on_executor_with_bindings(
    contributions: Vec<PreparedContribution>,
    symbols: &SymbolTable,
    external: &ReferenceBindings,
    inventory: LinkInventory,
    initialization: Vec<crate::initialization_artifact::InitializationArtifact>,
    executor: &dm_exec::BuildExecutor,
    bindings: Option<&dm_link::RetainedBindings>,
) -> Result<FrozenBatch, IntegrationError> {
    link_prepared_execution(
        contributions,
        symbols,
        external,
        inventory,
        initialization,
        Some(executor),
        bindings,
    )
}
#[allow(clippy::too_many_arguments)]
fn link_prepared_execution(
    contributions: Vec<PreparedContribution>,
    symbols: &SymbolTable,
    external: &ReferenceBindings,
    mut inventory: LinkInventory,
    initialization: Vec<crate::initialization_artifact::InitializationArtifact>,
    executor: Option<&dm_exec::BuildExecutor>,
    bindings: Option<&dm_link::RetainedBindings>,
) -> Result<FrozenBatch, IntegrationError> {
    let mut units = Vec::with_capacity(contributions.len());
    let mut helpers = Vec::new();
    let mut source_bindings = std::collections::BTreeSet::new();
    let mut string_inventory = StringInventory::new(&inventory);
    for entry in inventory.entry_iter() {
        if let Key::Type(id) = entry.key {
            let path = symbols
                .text(id)
                .ok_or(IntegrationError::MissingSpelling(id))?;
            if SymbolId::of(path) != id {
                return Err(IntegrationError::MissingSpelling(id));
            }
            source_bindings.insert(SymRef::Type(id));
        }
    }
    let mut identities = std::collections::BTreeSet::new();
    for unit in &contributions {
        if !identities.insert(unit.identity) {
            return Err(IntegrationError::DuplicateUnit(unit.identity));
        }
        if unit.effective {
            source_bindings.insert(unit_reference(unit.identity));
        }
    }
    for prepared in contributions {
        prepared.contribution.replay(
            &mut inventory,
            &mut string_inventory,
            symbols,
            &mut units,
            &mut helpers,
        );
    }
    let freeze_detail =
        std::env::var_os("DMB_PROFILE_FREEZE_DETAIL").is_some_and(|value| value == "1");
    finish_frozen_inventory(
        FrozenInventory {
            inventory,
            string_inventory,
            units,
            helpers,
            source_bindings,
        },
        symbols,
        external,
        initialization,
        freeze_detail,
        executor,
        bindings,
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn consuming_early_freeze_matches_legacy_order_and_images() {
        struct Source;
        impl dm_preprocess::SourceProvider for Source {
            fn read(&self, _: &std::path::Path) -> Result<String, String> {
                Ok(
                    "/proc/first()\n    return \"first\"\n/proc/second()\n    return \"second\"\n"
                        .into(),
                )
            }
        }
        struct Policy;
        impl crate::lowering::AbiPolicy for Policy {
            fn inputs(
                &self,
                _: UnitIdentity,
                _: &dm_ir::ProcedureMetadata,
                _: &SymbolTable,
                _: &dm_tree::frontend::SourceLocation,
            ) -> Result<dm_codegen_byond::ProcedureInputs, String> {
                Ok(Default::default())
            }
        }
        let frontend = dm_tree::frontend::build(
            std::path::Path::new("project.dme"),
            &Source,
            &Default::default(),
            1,
        )
        .unwrap();
        let tree = frontend.snapshot.tree.as_ref();
        let batch = crate::lowering::lower_frontend(&frontend, tree, &Policy, Default::default());
        assert!(batch.diagnostics.is_empty());
        let expected_content: std::collections::BTreeMap<_, _> = batch
            .units
            .iter()
            .map(|unit| {
                let frozen =
                    dm_codegen_byond::encoder::freeze_proc(&unit.code.procedure.code).unwrap();
                let mut bytes = b"dm-frozen-procedure-v2\0".to_vec();
                match &unit.abi {
                    None => bytes.push(0),
                    Some(abi) => {
                        bytes.push(1);
                        let data = abi.canonical_bytes();
                        bytes.extend_from_slice(&(data.len() as u64).to_le_bytes());
                        bytes.extend_from_slice(&data);
                    }
                }
                for data in [
                    frozen.code().canonical_bytes(),
                    unit.metadata.canonical_bytes(),
                ] {
                    bytes.extend_from_slice(&(data.len() as u64).to_le_bytes());
                    bytes.extend_from_slice(&data);
                }
                let procedure = &unit.code.procedure;
                bytes.extend_from_slice(&procedure.local_count.to_le_bytes());
                for names in [&procedure.local_names, &procedure.argument_names] {
                    bytes.extend_from_slice(&(names.len() as u64).to_le_bytes());
                    for name in names {
                        bytes.extend_from_slice(&(name.len() as u64).to_le_bytes());
                        bytes.extend_from_slice(name.as_bytes());
                    }
                }
                for values in [
                    &procedure.argument_type_flags,
                    &procedure.argument_value_sources,
                ] {
                    bytes.extend_from_slice(&(values.len() as u64).to_le_bytes());
                    for value in values {
                        bytes.extend_from_slice(&value.to_le_bytes());
                    }
                }
                (unit_key(unit.identity), bytes)
            })
            .collect();
        let external = ReferenceBindings::default();
        let legacy = freeze_and_link_tables(
            crate::lowering::LoweringBatch {
                units: batch.units.clone(),
                diagnostics: Vec::new(),
            },
            tree.symbols(),
            &external,
            LinkInventory::default(),
        )
        .unwrap();
        let bindings = batch
            .units
            .iter()
            .filter(|unit| unit.effective)
            .map(|unit| unit_reference(unit.identity))
            .collect();
        let prepared: Vec<PreparedContribution> = batch
            .units
            .into_iter()
            .map(|unit| {
                prepare_contribution(unit, tree.symbols(), &bindings, &external, false).unwrap()
            })
            .collect();
        // Retaining the reusable owner exercises the shared-payload emission
        // path; current provenance is still supplied by each completion.
        let retained: Vec<_> = prepared
            .iter()
            .map(PreparedContribution::shared_artifact)
            .collect();
        let early = link_prepared_artifact_tables(
            prepared,
            tree.symbols(),
            &external,
            LinkInventory::default(),
            Vec::new(),
        )
        .unwrap();
        assert_eq!(legacy.tables.assignments(), early.tables.assignments());
        for (key, bytes) in expected_content {
            assert_eq!(early.tables.content(key), Some(bytes.as_slice()));
        }

        assert_eq!(legacy.units.len(), early.units.len());
        assert_eq!(retained.len(), legacy.units.len());
        for (index, artifact) in retained.iter().enumerate() {
            assert_eq!(artifact.identity(), early.units[index].lowered.identity);
            assert!(Arc::ptr_eq(
                &artifact.code().shared_code(),
                &early.units[index].frozen.shared_code()
            ));
            assert_eq!(
                legacy.units[index].lowered.debug_origins,
                early.units[index].lowered.debug_origins
            );
            assert_eq!(
                legacy.units[index].lowered.identity,
                early.units[index].lowered.identity
            );
            assert_eq!(
                legacy.link_unit(index, &SourceBindings::default()).unwrap(),
                early.link_unit(index, &SourceBindings::default()).unwrap()
            );
        }
    }
}
