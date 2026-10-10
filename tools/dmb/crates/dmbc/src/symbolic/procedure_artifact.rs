//! Reusable immutable symbolic ownership and current-generation provenance.
//! Table assignments and CurrentImage certificates are always issued later.
use super::parallel::{BoundContribution, HelperContribution, OwnedStrings, Slots};
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
    strings: OwnedStrings,
    slots: Slots,
    instances: Vec<(SymbolId, SymbolId)>,
    content: dm_link::EntryContent,
    helpers: Vec<HelperArtifact>,
}
struct HelperArtifact {
    warnings: Arc<[dm_codegen_byond::ProcedureWarning]>,
    argument: u32,
    frozen: Arc<FrozenProc>,
    image_owner: Arc<latest_image::LatestImage>,
    features: BytecodeFeatures,
    local_names: Vec<String>,
    strings: OwnedStrings,
    slots: Slots,
    instances: Vec<(SymbolId, SymbolId)>,
    content: dm_link::EntryContent,
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
            strings: self.strings.clone(),
            slots: self.slots.clone(),
            instances: self.instances.clone(),
            content: self.content.clone(),
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
            strings: self.strings.clone(),
            slots: self.slots.clone(),
            content: self.content.clone(),
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
                strings: entry.strings,
                slots: entry.slots,
                instances: entry.instances,
                content: entry.content,
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
                strings: bound.strings,
                slots: bound.slots,
                instances: bound.instances,
                content: bound.content,
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
    fn into_bound(self) -> BoundContribution {
        // Ordinary CLI emission moves all payloads. Retained consumers share
        // immutable code/content/string bytes and copy only output descriptors.
        let artifact = Arc::unwrap_or_clone(self.artifact);
        let identity = artifact.identity;
        let unit = FrozenUnit {
            lowered: FrozenUnitMetadata {
                warnings: artifact.warnings,
                identity,
                origin: self.binding.origin,
                abi: self.binding.abi,
                debug_origins: self.binding.debug,
                frame: artifact.frame,
            },
            frozen: artifact.frozen,
            metadata_recipe: artifact.metadata_recipe,
            image_owner: artifact.image_owner,
            features: artifact.features,
            current_image: None,
        };
        let helpers = artifact
            .helpers
            .into_iter()
            .zip(self.binding.helpers)
            .map(|(helper, debug_origins)| HelperContribution {
                helper: FrozenHelper {
                    warnings: helper.warnings,
                    owner: identity,
                    argument: helper.argument,
                    frozen: helper.frozen,
                    image_owner: helper.image_owner,
                    features: helper.features,
                    current_image: None,
                    debug_origins,
                    local_names: helper.local_names,
                },
                strings: helper.strings,
                slots: helper.slots,
                instances: helper.instances,
                content: helper.content,
            })
            .collect();
        BoundContribution {
            unit,
            helpers,
            strings: artifact.strings,
            slots: artifact.slots,
            content: artifact.content,
            instances: artifact.instances,
        }
    }
    pub(super) fn replay(
        self,
        inventory: &mut LinkInventory,
        strings: &mut StringInventory,
        symbols: &SymbolTable,
        units: &mut Vec<FrozenUnit>,
        helpers: &mut Vec<FrozenHelper>,
    ) {
        self.into_bound()
            .replay(inventory, strings, symbols, units, helpers);
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
        census.prepared_strings(&self.artifact.strings.0);
        census.vec_payload("prepared_inventory.slots", &self.artifact.slots.0);
        census.prepared_entry_bytes(&self.artifact.content);
        census.vec_payload("prepared_helpers", &self.artifact.helpers);
        for (helper, debug) in self.artifact.helpers.iter().zip(&self.binding.helpers) {
            census.prepared_helper_parts(&helper.frozen, &helper.local_names, debug);
            census.prepared_strings(&helper.strings.0);
            census.vec_payload("prepared_inventory.slots", &helper.slots.0);
            census.prepared_entry_bytes(&helper.content);
        }
    }
}
