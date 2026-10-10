//! Reusable immutable symbolic ownership and current-generation provenance.
//! Table assignments and CurrentImage certificates are always issued later.
use super::parallel::BoundContribution;
use super::*;
pub(crate) mod disk;
#[path = "retained_census.rs"]
mod retained_census;

/// Immutable procedure payload, independent of source positions and link tables.
/// Its private constructor is reached only through the existing checked freezer.
pub struct ReusableProcedureArtifact {
    warnings: Arc<[dm_codegen_byond::ProcedureWarning]>,
    identity: UnitIdentity,
    frozen: Arc<FrozenProc>,
    metadata_recipe: Arc<crate::composition::ProcedureMetadataRecipe>,
    image_owner: Arc<latest_image::LatestImage>,
    features: BytecodeFeatures,
    frame: Arc<FrozenFrame>,
    abi: Option<Arc<crate::procedure_policy::PreparedAbi>>,
    inventory: Arc<dm_link::InventoryContribution>,
    instances: Vec<(SymbolId, SymbolId)>,
    helpers: Vec<HelperArtifact>,
}
struct HelperArtifact {
    warnings: Arc<[dm_codegen_byond::ProcedureWarning]>,
    argument: u32,
    frozen: Arc<FrozenProc>,
    image_owner: Arc<latest_image::LatestImage>,
    features: BytecodeFeatures,
    local_names: Arc<Vec<String>>,
    inventory: Arc<dm_link::InventoryContribution>,
    instances: Vec<(SymbolId, SymbolId)>,
}
/// Current source occurrence, kept outside the reusable payload. Fields remain
/// private; this is not a caller-supplied proof of a different source revision.
struct ProcedureRevisionBinding {
    origin: dm_tree::frontend::BodyOccurrence,
    debug: crate::debug_sources::FrozenDebugOrigins,
    helpers: Vec<crate::debug_sources::FrozenDebugOrigins>,
    abi: Option<Arc<crate::procedure_policy::PreparedAbi>>,
}
pub(super) struct Contribution {
    artifact: Arc<ReusableProcedureArtifact>,
    binding: ProcedureRevisionBinding,
}
impl Contribution {
    pub(super) fn current_warnings(
        &self,
        symbols: &SymbolTable,
    ) -> Result<Vec<crate::initializer_policy::warnings::InitializerWarning>, String> {
        let mut warnings = crate::procedure_warnings::bind(
            &self.artifact.warnings,
            &self.binding.debug,
            symbols,
            &self.artifact.frame.local_names,
        )?;
        if self.artifact.helpers.len() != self.binding.helpers.len() {
            return Err("procedure helper warning bindings incomplete".into());
        }
        for (helper, origins) in self.artifact.helpers.iter().zip(&self.binding.helpers) {
            warnings.extend(crate::procedure_warnings::bind(
                &helper.warnings,
                origins,
                symbols,
                &helper.local_names,
            )?);
        }
        Ok(warnings)
    }
    pub(super) fn current_source(&self) -> &dm_tree::frontend::SourceLocation {
        &self.binding.origin.source
    }

    pub(super) fn variable_record_count(&self) -> Option<usize> {
        let frame = &self.artifact.frame;
        self.artifact.helpers.iter().try_fold(
            frame
                .local_names
                .len()
                .checked_add(frame.argument_names.len())?,
            |count, helper| count.checked_add(helper.local_names.len()),
        )
    }
}
impl ReusableProcedureArtifact {
    pub(crate) fn release_bound_images(&self) -> usize {
        self.helpers.iter().fold(
            self.image_owner
                .release_bound_images()
                .saturating_add(self.metadata_recipe.release_numeric_caches()),
            |released, helper| released.saturating_add(helper.image_owner.release_bound_images()),
        )
    }
    #[cfg(test)]
    pub(super) fn inventory_owner(&self) -> &Arc<dm_link::InventoryContribution> {
        &self.inventory
    }
    pub fn identity(&self) -> UnitIdentity {
        self.identity
    }
    pub fn code(&self) -> &FrozenProc {
        &self.frozen
    }
    pub(super) fn can_rebind(
        &self,
        abi: &Option<Arc<crate::procedure_policy::PreparedAbi>>,
    ) -> bool {
        match (&self.abi, abi) {
            (Some(old), Some(current)) => {
                old.layout == current.layout
                    && old.argument_sources == current.argument_sources
                    && self.helpers.len() == current.source_helpers.len()
                    && self
                        .helpers
                        .iter()
                        .zip(&current.source_helpers)
                        .all(|(stored, issued)| stored.argument as usize == issued.argument)
            }
            (None, None) => self.helpers.is_empty(),
            _ => false,
        }
    }
    pub(super) fn helper_origins(
        &self,
        frontend: &dm_tree::frontend::ColdFrontend,
        body: &dm_tree::frontend::BodyOccurrence,
        prepared: &crate::procedure_policy::PreparedUnit,
    ) -> Option<Vec<crate::debug_sources::FrozenDebugOrigins>> {
        if self.helpers.is_empty() {
            return Some(Vec::new());
        }
        let parsed = frontend.compact_body(body).ok()?;
        let member = frontend.snapshot.tree.member(body.member)?;
        let metadata = member.metadata.procedure.as_ref()?;
        let abi = prepared.abi.as_ref()?;
        let context = crate::argument_sources::HelperInputs {
            frontend,
            parsed: parsed.into(),
            metadata,
            owner: self.identity,
            inputs: &prepared.inputs,
            helpers: &abi.source_helpers,
            symbols: frontend.snapshot.tree.symbols(),
        };
        self.helpers
            .iter()
            .map(|helper| {
                crate::argument_sources::current_helper_origins(&context, helper.argument)
                    .ok()
                    .map(Into::into)
            })
            .collect()
    }
}
impl Clone for HelperArtifact {
    fn clone(&self) -> Self {
        Self {
            argument: self.argument,
            warnings: Arc::clone(&self.warnings),
            frozen: self.frozen.clone(),
            image_owner: Arc::clone(&self.image_owner),
            features: self.features,
            local_names: self.local_names.clone(),
            inventory: self.inventory.clone(),
            instances: self.instances.clone(),
        }
    }
}
impl Clone for ReusableProcedureArtifact {
    fn clone(&self) -> Self {
        Self {
            identity: self.identity,
            warnings: Arc::clone(&self.warnings),
            frozen: self.frozen.clone(),
            metadata_recipe: Arc::clone(&self.metadata_recipe),
            image_owner: Arc::clone(&self.image_owner),
            features: self.features,
            frame: Arc::clone(&self.frame),
            instances: self.instances.clone(),
            abi: self.abi.clone(),
            inventory: self.inventory.clone(),
            helpers: self.helpers.clone(),
        }
    }
}
impl Contribution {
    pub(super) fn rebind(
        artifact: &Arc<ReusableProcedureArtifact>,
        origin: dm_tree::frontend::BodyOccurrence,
        debug: crate::debug_sources::DebugOrigins,
        abi: Option<Arc<crate::procedure_policy::PreparedAbi>>,
        helpers: Vec<crate::debug_sources::FrozenDebugOrigins>,
    ) -> Self {
        Self {
            artifact: Arc::clone(artifact),
            binding: ProcedureRevisionBinding {
                origin,
                debug: debug.into(),
                helpers,
                abi,
            },
        }
    }
    pub(super) fn from_bound(bound: BoundContribution) -> Self {
        let FrozenUnit {
            lowered,
            frozen,
            metadata_recipe,
            features,
            current_image,
            image_owner,
        } = bound.unit;
        debug_assert!(
            current_image.is_none(),
            "artifact is created before output linking"
        );
        let FrozenUnitMetadata {
            warnings,
            identity,
            origin,
            abi,
            debug_origins,
            frame,
        } = lowered;
        let mut helper_artifacts = Vec::with_capacity(bound.helpers.len());
        let mut helper_origins = Vec::with_capacity(bound.helpers.len());
        for entry in bound.helpers {
            let FrozenHelper {
                warnings,
                owner,
                argument,
                frozen,
                image_owner,
                features,
                current_image,
                debug_origins,
                local_names,
            } = entry.helper;
            debug_assert_eq!(owner, identity);
            debug_assert!(current_image.is_none());
            helper_origins.push(debug_origins);
            helper_artifacts.push(HelperArtifact {
                warnings,
                argument,
                frozen,
                image_owner,
                features,
                local_names,
                inventory: Arc::new(
                    dm_link::InventoryContribution::new(
                        helper_key(identity, argument),
                        entry.content,
                        entry.slots.0,
                    )
                    .with_strings(entry.strings.0),
                ),
                instances: entry.instances,
            });
        }
        let artifact_abi = abi.clone();
        Self {
            artifact: Arc::new(ReusableProcedureArtifact {
                warnings,
                identity,
                frozen,
                metadata_recipe,
                image_owner,
                features,
                frame,
                abi,
                inventory: Arc::new(
                    dm_link::InventoryContribution::new(
                        unit_key(identity),
                        bound.content,
                        bound.slots.0,
                    )
                    .with_strings(bound.strings.0),
                ),
                instances: bound.instances,
                helpers: helper_artifacts,
            }),
            binding: ProcedureRevisionBinding {
                abi: artifact_abi,
                origin,
                debug: debug_origins,
                helpers: helper_origins,
            },
        }
    }
    pub(super) fn shared_artifact(&self) -> Arc<ReusableProcedureArtifact> {
        self.artifact.clone()
    }
    pub(super) fn replay(
        self,
        inventory: &mut LinkInventory,
        strings: &mut StringInventory,
        symbols: &SymbolTable,
        units: &mut Vec<FrozenUnit>,
        helpers: &mut Vec<FrozenHelper>,
    ) {
        let Self { artifact, binding } = self;
        let unit = FrozenUnit {
            lowered: FrozenUnitMetadata {
                warnings: artifact.warnings.clone(),
                identity: artifact.identity,
                origin: binding.origin,
                abi: binding.abi,
                debug_origins: binding.debug,
                frame: artifact.frame.clone(),
            },
            frozen: artifact.frozen.clone(),
            metadata_recipe: artifact.metadata_recipe.clone(),
            image_owner: artifact.image_owner.clone(),
            features: artifact.features,
            current_image: None,
        };
        super::parallel::replay_shared_unit(
            &unit,
            Arc::clone(&artifact.inventory),
            inventory,
            strings,
            symbols,
        );
        units.push(unit);
        for (retained, debug_origins) in artifact.helpers.iter().zip(binding.helpers) {
            let helper = FrozenHelper {
                warnings: retained.warnings.clone(),
                owner: artifact.identity,
                argument: retained.argument,
                frozen: retained.frozen.clone(),
                image_owner: retained.image_owner.clone(),
                features: retained.features,
                current_image: None,
                debug_origins,
                local_names: retained.local_names.clone(),
            };
            super::parallel::replay_shared_helper(
                &helper,
                Arc::clone(&retained.inventory),
                inventory,
                strings,
            );
            helpers.push(helper);
        }
    }
    pub(super) fn census(&self, census: &mut crate::heap_census::HeapCensus) {
        crate::composition::ProcedureMetadataRecipe::census(&self.artifact.metadata_recipe, census);
        census.arc_object("prepared_artifact", &self.artifact);
        census.vec_payload("prepared_revision.debug_helpers", &self.binding.helpers);
        census.prepared_procedure_parts(
            &self.artifact.frozen,
            &self.artifact.frame,
            &self.artifact.abi,
            &self.binding.origin,
            &self.binding.debug,
        );
        census.prepared_inventory_contribution(&self.artifact.inventory);
        census.vec_payload("prepared_helpers", &self.artifact.helpers);
        for (helper, debug) in self.artifact.helpers.iter().zip(&self.binding.helpers) {
            census.prepared_helper_parts(&helper.frozen, &helper.local_names, debug);
            census.prepared_inventory_contribution(&helper.inventory);
        }
    }
}
