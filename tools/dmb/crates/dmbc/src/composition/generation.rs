//! One canonical generation retained at the existing validated model boundary.
//! Exact model equality is authoritative; no hash admits a generation.
use super::*;
use std::sync::Arc;
use std::sync::Mutex;

/// Request-local model after source/stage, instruction and reference admission.
/// Construction is private to the composition implementation so a caller cannot
/// replace those checks with an output fingerprint.
pub(super) struct CertifiedGenerationInputs {
    model: Dmb,
    string_seed: Option<strings::StringSeed>,
}
impl CertifiedGenerationInputs {
    pub(super) fn with_string_seed(mut self, seed: Option<strings::StringSeed>) -> Self {
        self.string_seed = seed;
        self
    }
    pub(super) fn after_validation(model: Dmb) -> Self {
        Self {
            model,
            string_seed: None,
        }
    }
}

/// Link answers of the generation's own build, retained for body-edit patches:
/// a patched procedure is linked against exactly the tables that produced it.
pub(crate) struct PatchLink {
    pub tables: dm_link::LinkTables,
    pub mobs: dm_link::MobBindings,
    /// Initializer procedures, relinked when a line shift moves their origins.
    pub initializers: Vec<crate::symbolic::PositionedCode>,
}
/// The published image of a patch base, detached from its model: list-row
/// ranges for splicing and each procedure's code list.
pub(crate) struct PatchImage {
    pub rows: byond_dmb::dmb::ListRowImage,
    pub proc_code: Arc<Vec<u32>>,
}
/// Body-edit patch state of the current generation (see `crate::body_patch`).
/// It is compact (no model) and survives wire-image pressure release.
#[derive(Clone, Default)]
pub(super) struct PatchSlot {
    link: Option<Arc<PatchLink>>,
    /// Variables-table record of each declared field of the patch base.
    fields: Option<crate::class_projection::FieldRecords>,
    base: Option<Arc<crate::body_patch::BodyPatchBase>>,
    image: Option<Arc<PatchImage>>,
}
/// A single latest successful generation; no history or source authority retained.
pub struct RetainedGeneration {
    current: Arc<Mutex<Option<Arc<Generation>>>>,
    patch: Arc<Mutex<PatchSlot>>,
    plan: Arc<Mutex<Option<Arc<procedure_plan::CachedPlan>>>>,
    publication: Arc<dm_session::ArtifactPublication<Pending>>,
    attempt: dm_session::ArtifactAttempt<Pending>,
    wire_evictions: Arc<std::sync::atomic::AtomicU64>,
    /// Symbolic header decisions share the session generation's policy and lifetime.
    /// Values and dense table IDs are always bound from the current model.
    pub(super) header_recipes: Arc<crate::class_projection::HeaderRecipes>,
}
struct Generation {
    inputs: CertifiedGenerationInputs,
    encoded: byond_dmb::dmb::EncodedDmb,
}
#[path = "generation_publication.rs"]
mod publication;
use publication::Pending;
impl RetainedGeneration {
    pub(super) fn string_index(
        &self,
        model: &Dmb,
    ) -> Result<(StringIndex, strings::StringSeed), CompositionError> {
        let current = self.current.lock().unwrap_or_else(|e| e.into_inner());
        let mut index = current
            .as_ref()
            .and_then(|old| {
                old.inputs
                    .string_seed
                    .as_ref()
                    .and_then(|seed| seed.admit(model, &old.inputs.model))
            })
            .map(Ok)
            .unwrap_or_else(|| StringIndex::build(model))?;
        let seed = index.seed(model.strings.len());
        Ok((index, seed))
    }
    pub(crate) fn census_string_index(&self, census: &mut crate::heap_census::HeapCensus) {
        self.visit_published(|old| {
            if let Some(seed) = old
                .current
                .lock()
                .unwrap_or_else(|e| e.into_inner())
                .as_ref()
                .and_then(|generation| generation.inputs.string_seed.as_ref())
            {
                seed.census(census);
            }
        });
        if let Some(seed) = self
            .current
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .as_ref()
            .and_then(|generation| generation.inputs.string_seed.as_ref())
        {
            seed.census(census);
        }
    }

    pub(crate) fn census_headers(&self, census: &mut crate::heap_census::HeapCensus) {
        census.header_recipes(&self.header_recipes);
        self.visit_published(|old| census.header_recipes(&old.headers));
    }

    /// All current composition checks must finish before this entry is called.
    /// Equality includes every ordered output table, raw string byte and header.
    /// A mismatch follows the ordinary canonical encoder and independent decoder.
    pub(super) fn encode_pending(
        &self,
        inputs: CertifiedGenerationInputs,
        executor: Option<&dm_exec::BuildExecutor>,
    ) -> Result<byond_dmb::dmb::EncodedDmb, CompositionError> {
        let mut current = self
            .current
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        if let Some(hit) = current
            .as_ref()
            .filter(|hit| hit.inputs.model == inputs.model)
        {
            return Ok(hit.encoded.clone());
        }
        // Equality is complete. Reuse only the previous successful generation
        // during canonical row encoding; errors leave an empty performance memo.
        let encoded_result = {
            let _profile = dm_profile::stage("composition.encode");
            inputs
                .model
                .encode_reusing_list_rows(
                    current
                        .as_ref()
                        .map(|previous| &previous.inputs.model.lists),
                    executor,
                )
                .map_err(CompositionError::Decode)
        };
        // The previous generation is only a source of immutable row encodings.
        // Release it before decoder validation and publication of its replacement.
        // Explicit bounded performance-cache eviction, not publication of a
        // replacement. The conventional output pair and attempt token are intact.
        *current = None;
        self.evict_published_wire_memo();
        let (encoded, certificate) = encoded_result?;
        validate_encoded(&encoded)?;
        if !inputs.model.lists.retain_encoded_rows(certificate) {
            return Err(unsupported(
                "canonical row certificate differs from current words",
            ));
        }
        *current = Some(Arc::new(Generation {
            inputs,
            encoded: encoded.clone(),
        }));
        Ok(encoded)
    }
    pub(super) fn bind_plan_pending(
        &self,
        mut raw: procedure_plan::CompositionPlan,
        batch: &FrozenBatch,
        assignment_floor: Option<usize>,
    ) -> procedure_plan::BoundCompositionPlan {
        let mut cached = self.plan.lock().unwrap_or_else(|error| error.into_inner());
        if let Some(hit) = cached
            .as_ref()
            .and_then(|previous| previous.admit(&raw, batch))
        {
            if let (Some(previous), Some(floor)) = (cached.as_mut(), assignment_floor) {
                if !previous.has_assignment_floor(floor) {
                    Arc::make_mut(previous).issue_assignment_floor(floor);
                }
            }
            return hit;
        }
        let captured = raw.clone();
        raw.canonicalize();
        let bound = raw.bind(batch);
        let mut replacement = procedure_plan::CachedPlan::capture(captured, batch, &bound);
        if let (Some(next), Some(floor)) = (replacement.as_mut(), assignment_floor) {
            next.issue_assignment_floor(floor);
        }
        if let (Some(next), Some(previous)) = (replacement.as_mut(), cached.as_mut()) {
            next.inherit_metadata(Arc::make_mut(previous));
        }
        *cached = replacement.map(Arc::new);
        bound
    }
    pub(super) fn argument_sources_pending(
        &self,
        tables: &dm_link::LinkTables,
        start: usize,
        order: &[Key],
    ) -> Result<std::sync::Arc<dm_link::ArgumentSourceReferences>, dm_link::LinkError> {
        let mut plan = self.plan.lock().unwrap_or_else(|error| error.into_inner());
        match plan.as_mut() {
            Some(plan) => Arc::make_mut(plan).argument_sources(tables, start, order),
            None => dm_link::ArgumentSourceReferences::assign(tables, start, order)
                .map(std::sync::Arc::new),
        }
    }
    pub(super) fn prepare_metadata_pending(
        &self,
        slots: &[procedure_plan::Slot<crate::lowering::UnitIdentity>],
        batch: &FrozenBatch,
        projection: Option<&crate::class_projection::ClassProjection>,
        symbols: &SymbolTable,
        references: &std::sync::Arc<dm_link::ArgumentSourceReferences>,
        executor: Option<&dm_exec::BuildExecutor>,
    ) -> Vec<Result<procedure_plan::PreparedMetadata, CompositionError>> {
        let mut plan = self.plan.lock().unwrap_or_else(|e| e.into_inner());
        match plan.as_mut() {
            Some(plan) => Arc::make_mut(plan)
                .prepare_metadata(slots, batch, projection, symbols, references, executor),
            None => procedure_plan::prepare_metadata(
                slots, batch, projection, symbols, references, executor, true,
            ),
        }
    }
    pub(crate) fn census_plan(&self, census: &mut crate::heap_census::HeapCensus) {
        self.visit_published(|old| {
            if let Some(plan) = old.plan.lock().unwrap_or_else(|e| e.into_inner()).as_ref() {
                plan.census(census);
            }
        });
        if let Some(plan) = self
            .plan
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .as_ref()
        {
            plan.census(census);
        }
    }
    pub fn clear(&self) {
        self.header_recipes.evict_cached_claims();
        self.release_wire_images();
    }
    /// Composition records the link answers of the model it is about to encode.
    /// The source half of the patch base is installed by the runner after a
    /// successful build; until then the slot holds no base.
    pub(super) fn capture_patch_link(
        &self,
        tables: &dm_link::LinkTables,
        mobs: &dm_link::MobBindings,
        initializers: Vec<crate::symbolic::PositionedCode>,
    ) {
        self.attempt.with_pending(|_| {
            *self.patch.lock().unwrap_or_else(|e| e.into_inner()) = PatchSlot {
                link: Some(Arc::new(PatchLink {
                    tables: tables.clone(),
                    mobs: mobs.clone(),
                    initializers,
                })),
                base: None,
                image: None,
                fields: None,
            };
        });
    }
    /// Field records of the model this request composes (after capture_patch_link).
    pub(super) fn capture_field_records(&self, fields: crate::class_projection::FieldRecords) {
        self.attempt.with_pending(|_| {
            self.patch.lock().unwrap_or_else(|e| e.into_inner()).fields = Some(fields);
        });
    }
    /// Variables-table record of a declared field in the patch base.
    pub(crate) fn field_record(&self, owner: dm_ir::SymbolId, name: dm_ir::SymbolId) -> Option<u32> {
        let slot = self.patch.lock().unwrap_or_else(|e| e.into_inner());
        slot.fields.as_ref()?.0.get(&(owner, name)).copied()
    }
    /// Default-edit patch: replace Variables-table values in the retained
    /// image (see `crate::body_patch::try_default_patch`). The base advances
    /// exactly as `patch_rows` advances it.
    pub(crate) fn patch_variable_values(
        &self,
        image: &PatchImage,
        values: &[(u32, u8, u32)],
        base: crate::body_patch::BodyPatchBase,
    ) -> Result<byond_dmb::dmb::EncodedDmb, String> {
        self.attempt
            .with_pending(|_| {
                let patched = image
                    .rows
                    .patch_variable_values(values)
                    .map_err(|error| format!("variable patch: {error}"))?;
                let encoded = patched.image().clone();
                validate_encoded(&encoded).map_err(|error| format!("{error:?}"))?;
                // Keep the retained model describing the published image so a
                // later structural patch can edit it (stable numbering).
                {
                    let _timer = dm_profile::detail_timer("patch.default_model_sync");
                    let mut current = self.current.lock().unwrap_or_else(|e| e.into_inner());
                    let synced = current.as_ref().and_then(|generation| {
                        (generation.encoded.content_hash() == image.rows.image().content_hash())
                            .then(|| {
                                let mut inputs = CertifiedGenerationInputs {
                                    model: generation.inputs.model.clone(),
                                    string_seed: generation.inputs.string_seed.clone(),
                                };
                                for &(record, _, value) in values {
                                    inputs.model.variables[record as usize].value = value;
                                }
                                Generation {
                                    inputs,
                                    encoded: encoded.clone(),
                                }
                            })
                    });
                    *current = synced.map(Arc::new);
                }
                let mut slot = self.patch.lock().unwrap_or_else(|e| e.into_inner());
                slot.base = Some(Arc::new(base.with_output_hash(encoded.content_hash())));
                slot.image = Some(Arc::new(PatchImage {
                    rows: patched,
                    proc_code: Arc::clone(&image.proc_code),
                }));
                Ok(encoded)
            })
            .unwrap_or_else(|| Err("generation attempt is not pending".into()))
    }
    /// First free physical index of each link table in the retained model
    /// that describes the published image `base_hash` (append-only linking).
    pub(crate) fn model_table_starts(
        &self,
        base_hash: u128,
    ) -> Option<std::collections::BTreeMap<dm_link::Table, u32>> {
        let current = self.current.lock().unwrap_or_else(|e| e.into_inner());
        let generation = current.as_ref()?;
        if generation.encoded.content_hash() != base_hash {
            return None;
        }
        let model = &generation.inputs.model;
        use dm_link::Table;
        Some(
            [
                (Table::String, model.strings.len()),
                (Table::Procedure, model.procs.len()),
                (Table::List, model.lists.len()),
                (Table::Variable, model.variables.len()),
                (Table::VariableRecord, model.variables.len()),
                (Table::Type, model.classes.len()),
                (Table::Instance, model.instances.len()),
            ]
            .into_iter()
            .map(|(table, len)| (table, len as u32))
            .collect(),
        )
    }
    /// Structural append patch on the retained composed model, which must
    /// still describe the published image with `base_hash`. `strings` runs
    /// before the string index is built (table strings), `edit` after. The
    /// edited model is encoded with list-row reuse and becomes the current
    /// generation and patch base (`link` carries the extended tables).
    pub(crate) fn patch_model(
        &self,
        base_hash: u128,
        strings: impl FnOnce(&mut Dmb) -> Result<(), CompositionError>,
        edit: impl FnOnce(&mut Dmb, &mut StringIndex) -> Result<(), CompositionError>,
        link: PatchLink,
        base: crate::body_patch::BodyPatchBase,
        executor: &dm_exec::BuildExecutor,
    ) -> Result<byond_dmb::dmb::EncodedDmb, String> {
        self.attempt
            .with_pending(|_| {
                let mut model = {
                    let current = self.current.lock().unwrap_or_else(|e| e.into_inner());
                    let generation = current
                        .as_ref()
                        .ok_or("retained model released")?;
                    if generation.encoded.content_hash() != base_hash {
                        return Err("retained model differs from the patch base".to_string());
                    }
                    generation.inputs.model.clone()
                };
                strings(&mut model).map_err(|error| format!("{error:?}"))?;
                let (mut index, seed) = self.string_index(&model).map_err(|error| format!("{error:?}"))?;
                edit(&mut model, &mut index).map_err(|error| format!("{error:?}"))?;
                let encoded = self
                    .encode_pending(
                        CertifiedGenerationInputs::after_validation(model).with_string_seed(Some(seed)),
                        Some(executor),
                    )
                    .map_err(|error| format!("{error:?}"))?;
                let current = self.current.lock().unwrap_or_else(|e| e.into_inner());
                let generation = current.as_ref().ok_or("encoded generation absent")?;
                let rows = generation
                    .inputs
                    .model
                    .list_row_image()
                    .ok_or("list rows not certified")?;
                let proc_code = Arc::new(
                    generation
                        .inputs
                        .model
                        .procs
                        .iter()
                        .map(|proc| proc.code_locals_args[0])
                        .collect(),
                );
                drop(current);
                let mut slot = self.patch.lock().unwrap_or_else(|e| e.into_inner());
                slot.link = Some(Arc::new(link));
                slot.base = Some(Arc::new(base.with_output_hash(encoded.content_hash())));
                slot.image = Some(Arc::new(PatchImage { rows, proc_code }));
                Ok(encoded)
            })
            .unwrap_or_else(|| Err("generation attempt is not pending".into()))
    }
    /// Attach the source half of the patch base to this request's generation
    /// and detach the row image of the model it just encoded.
    pub(crate) fn install_patch_base(&self, base: crate::body_patch::BodyPatchBase) -> bool {
        self.attempt
            .with_pending(|_| {
                let image = {
                    let current = self.current.lock().unwrap_or_else(|e| e.into_inner());
                    let Some(generation) = current.as_ref() else {
                        return false;
                    };
                    let model = &generation.inputs.model;
                    let Some(rows) = model.list_row_image() else {
                        return false;
                    };
                    if rows.image().content_hash() != generation.encoded.content_hash() {
                        return false;
                    }
                    PatchImage {
                        rows,
                        proc_code: Arc::new(
                            model.procs.iter().map(|proc| proc.code_locals_args[0]).collect(),
                        ),
                    }
                };
                let mut slot = self.patch.lock().unwrap_or_else(|e| e.into_inner());
                if slot.link.is_none() {
                    return false;
                }
                slot.base = Some(Arc::new(base));
                slot.image = Some(Arc::new(image));
                true
            })
            .unwrap_or(false)
    }
    /// The patch base, its link answers and the image they describe.
    pub(crate) fn patch_base(
        &self,
    ) -> Option<(
        Arc<crate::body_patch::BodyPatchBase>,
        Arc<PatchLink>,
        Arc<PatchImage>,
    )> {
        let slot = self.patch.lock().unwrap_or_else(|e| e.into_inner()).clone();
        Some((slot.base?, slot.link?, slot.image?))
    }
    /// Splice whole code-list rows into the retained patch image; the result
    /// equals a canonical encode of the model with those rows replaced. The
    /// spliced image and `base` become this request's pending patch state. The
    /// retained model memo (if any) is left as is: it is keyed by complete
    /// model equality, so it stays correct for the model it describes.
    pub(crate) fn patch_rows(
        &self,
        image: &PatchImage,
        rows: &[(usize, Arc<Vec<u32>>)],
        base: crate::body_patch::BodyPatchBase,
        initializers: Option<Vec<crate::symbolic::PositionedCode>>,
    ) -> Result<byond_dmb::dmb::EncodedDmb, String> {
        self.attempt
            .with_pending(|_| {
                let spliced = {
                    let _profile = dm_profile::stage("patch.splice");
                    image
                        .rows
                        .splice(rows)
                        .map_err(|error| format!("list splice: {error}"))?
                };
                dm_profile::request_mark("patch.spliced");
                let encoded = spliced.image().clone();
                validate_encoded(&encoded).map_err(|error| format!("{error:?}"))?;
                let mut slot = self.patch.lock().unwrap_or_else(|e| e.into_inner());
                slot.base = Some(Arc::new(base.with_output_hash(encoded.content_hash())));
                if let (Some(initializers), Some(link)) = (initializers, slot.link.as_ref()) {
                    // Shifted initializer origins are the next patch's baseline.
                    slot.link = Some(Arc::new(PatchLink {
                        tables: link.tables.clone(),
                        mobs: link.mobs.clone(),
                        initializers,
                    }));
                }
                slot.image = Some(Arc::new(PatchImage {
                    rows: spliced,
                    proc_code: Arc::clone(&image.proc_code),
                }));
                Ok(encoded)
            })
            .unwrap_or_else(|| Err("generation attempt is not pending".into()))
    }
    /// Release physical generation buffers without discarding symbolic header recipes.
    pub(crate) fn release_wire_images(&self) {
        self.evict_published_wire_memo();
        self.visit_published(|old| {
            *old.plan.lock().unwrap_or_else(|error| error.into_inner()) = None;
        });
        *self.plan.lock().unwrap_or_else(|error| error.into_inner()) = None;
        *self
            .current
            .lock()
            .unwrap_or_else(|error| error.into_inner()) = None;
        // The compact patch slot (row image, link answers, source base) stays:
        // it is what lets the next body edit skip whole-program compilation.
    }
    /// Borrow retained physical owners for opt-in census without cloning buffers.
    pub(crate) fn visit_retained(
        &self,
        mut visitor: impl FnMut(&Dmb, &byond_dmb::dmb::EncodedDmb),
    ) {
        let current = self
            .current
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        if let Some(generation) = current.as_ref() {
            visitor(&generation.inputs.model, &generation.encoded);
        }

        drop(current);
        self.visit_published(|old| {
            let current = old
                .current
                .lock()
                .unwrap_or_else(|error| error.into_inner());
            if let Some(generation) = current.as_ref() {
                visitor(&generation.inputs.model, &generation.encoded);
            }
        });
    }
}
pub(super) fn encode_model(
    model: &Dmb,
    executor: Option<&dm_exec::BuildExecutor>,
) -> Result<byond_dmb::dmb::EncodedDmb, CompositionError> {
    let encoded = {
        let _profile = dm_profile::stage("composition.encode");
        match executor {
            Some(executor) => model.encode_on_executor(executor),
            None => model.encode(),
        }
        .map_err(CompositionError::Decode)?
    };
    Ok(encoded)
}
/// Whether composition repeats checks that only re-prove what construction
/// already guaranteed: the engine and output reference validation and the
/// independent decode of every encoded image. Debug builds (all unit tests)
/// verify by default; release builds skip unless `DMB_VERIFY_OUTPUT=1`.
/// `DMB_VERIFY_OUTPUT=0` forces them off. The byte oracle (fresh native build
/// comparison) is the correctness backstop for the skipped release path.
pub(crate) fn full_verification() -> bool {
    static MODE: std::sync::OnceLock<bool> = std::sync::OnceLock::new();
    *MODE.get_or_init(|| {
        let (enabled, source) = match std::env::var("DMB_VERIFY_OUTPUT").as_deref() {
            Ok("1") => (true, "DMB_VERIFY_OUTPUT=1"),
            Ok("0") => (false, "DMB_VERIFY_OUTPUT=0"),
            _ if cfg!(debug_assertions) => (true, "debug build default"),
            _ => (false, "release build default"),
        };
        crate::daemon_eprintln!(
            "composition verification (decode round-trip, reference validation): {} ({source})",
            if enabled { "on" } else { "off" }
        );
        enabled
    })
}
pub(super) fn validate_encoded(
    encoded: &byond_dmb::dmb::EncodedDmb,
) -> Result<(), CompositionError> {
    if !full_verification() {
        return Ok(());
    }
    let _profile = dm_profile::stage("composition.independent_roundtrip");
    Dmb::from_bytes(encoded.bytes())
        .and_then(|decoded| decoded.validate_references())
        .map_err(CompositionError::Decode)?;
    Ok(())
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn debug_builds_verify_composition_output_by_default() {
        // Unit tests keep the decode round-trip on unless the environment says otherwise.
        if std::env::var_os("DMB_VERIFY_OUTPUT").is_none() {
            assert_eq!(full_verification(), cfg!(debug_assertions));
        }
        let encoded = model().encode().unwrap();
        validate_encoded(&encoded).unwrap();
    }
    fn model() -> Dmb {
        Dmb::from_bytes(include_bytes!("../../../../fixtures/native_template.bin")).unwrap()
    }
    #[test]
    fn pending_generation_and_explicit_wire_eviction_preserve_publication_boundary() {
        let owner = RetainedGeneration::default();
        let original = model();
        let first = owner.for_request(true);
        let encoded = first
            .encode(
                CertifiedGenerationInputs::after_validation(original.clone()),
                None,
            )
            .unwrap();
        assert!(first.publish_successful());
        let published = owner
            .publication
            .with_published(|old| old.current.lock().unwrap().as_ref().unwrap().clone())
            .unwrap();
        let failed = owner.for_request(true);
        assert!(Arc::ptr_eq(
            encoded.shared_bytes(),
            failed
                .encode(
                    CertifiedGenerationInputs::after_validation(original.clone()),
                    None
                )
                .unwrap()
                .shared_bytes()
        ));
        drop(failed);
        let next = owner.for_request(true);
        let analysis = owner.for_request(false);
        assert!(!analysis.publish_successful());
        assert!(next.publish_successful());
        assert!(owner
            .publication
            .with_published(|old| Arc::ptr_eq(
                &published,
                old.current.lock().unwrap().as_ref().unwrap()
            ))
            .unwrap());
        let previous_weak = Arc::downgrade(&published);
        drop(published);
        drop(first);
        drop(next);
        drop(analysis);
        let changed = owner.for_request(true);
        let token = changed.attempt.generation().clone();
        let mut new_model = original.clone();
        new_model.lists.push(vec![7, 9]);
        let result = changed
            .encode(
                CertifiedGenerationInputs::after_validation(new_model.clone()),
                None,
            )
            .unwrap();
        assert_eq!(result.bytes(), new_model.encode().unwrap().bytes());
        assert_eq!(changed.wire_memo_evictions(), 1);
        assert_eq!(owner.wire_memo_evictions(), 1);
        assert!(previous_weak.upgrade().is_none());
        assert!(changed.attempt.generation().same_as(&token));
        assert!(owner
            .publication
            .with_published(|old| old.current.lock().unwrap().is_none())
            .unwrap());
        // Dropping a completed but unpublished encode does not install that generation.
        drop(changed);
        let fallback = owner.for_request(true);
        let result = fallback
            .encode(
                CertifiedGenerationInputs::after_validation(original.clone()),
                None,
            )
            .unwrap();
        assert_eq!(result.bytes(), original.encode().unwrap().bytes());
        assert!(fallback.publish_successful());
    }

    #[test]
    fn successful_generation_reuses_initial_string_seed_with_fresh_output_parity() {
        let owner = RetainedGeneration::default();
        let initial = model();
        let (mut index, seed) = owner.string_index(&initial).unwrap();
        let mut first_model = initial.clone();
        index
            .intern(&mut first_model, b"late generation metadata")
            .unwrap();
        owner
            .encode(
                CertifiedGenerationInputs::after_validation(first_model)
                    .with_string_seed(Some(seed)),
                None,
            )
            .unwrap();
        let (mut retained, next_seed) = owner.string_index(&initial).unwrap();
        let mut next = initial.clone();
        let mut fresh = initial.clone();
        let mut fresh_index = StringIndex::build(&fresh).unwrap();
        for bytes in [
            b"replacement metadata".as_slice(),
            b"late generation metadata",
        ] {
            assert_eq!(
                retained.intern(&mut next, bytes).unwrap(),
                fresh_index.intern(&mut fresh, bytes).unwrap()
            );
        }
        let result = owner
            .encode(
                CertifiedGenerationInputs::after_validation(next).with_string_seed(Some(next_seed)),
                None,
            )
            .unwrap();
        assert_eq!(result.bytes(), fresh.encode().unwrap().bytes());
        owner.clear();
        let (_, seed_after_clear) = owner.string_index(&initial).unwrap();
        assert!(seed_after_clear.admit(&initial, &initial).is_some());
    }
    #[test]
    fn complete_model_equality_reuses_and_ordered_payload_change_invalidates() {
        let owner = RetainedGeneration::default();
        let original = model();
        let first = owner
            .encode(
                CertifiedGenerationInputs::after_validation(original.clone()),
                None,
            )
            .unwrap();
        let second = owner
            .encode(
                CertifiedGenerationInputs::after_validation(original.clone()),
                None,
            )
            .unwrap();
        assert!(Arc::ptr_eq(first.shared_bytes(), second.shared_bytes()));
        let mut changed = original.clone();
        changed.lists.push(vec![7, 9]);
        let third = owner
            .encode(
                CertifiedGenerationInputs::after_validation(changed.clone()),
                None,
            )
            .unwrap();
        assert!(!Arc::ptr_eq(first.shared_bytes(), third.shared_bytes()));
        assert_eq!(third.bytes(), changed.encode().unwrap().bytes());
        let last = changed.lists.len() - 1;
        changed.lists[last].reverse();
        let fourth = owner
            .encode(CertifiedGenerationInputs::after_validation(changed), None)
            .unwrap();
        assert!(!Arc::ptr_eq(third.shared_bytes(), fourth.shared_bytes()));
        owner.clear();
        let fifth = owner
            .encode(CertifiedGenerationInputs::after_validation(original), None)
            .unwrap();
        assert!(!Arc::ptr_eq(first.shared_bytes(), fifth.shared_bytes()));
    }
}
