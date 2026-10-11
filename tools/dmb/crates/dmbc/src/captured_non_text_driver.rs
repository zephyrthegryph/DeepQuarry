//! One explicit captured nontext path for the cold compiler. No query performs I/O.
use crate::{
    assets::ResourceProjection,
    initialization_artifact::InitializationArtifact,
    map_output::DescriptorPlan,
    map_projection::{Projection, WorldDefaults},
    world_projection::{DefaultKind, Directive},
};
use dm_ir::{Resolver, SymbolId, SymbolTable};
use dm_resources::native_resolver::NativeResourceResolver;
use dm_tree::frontend::ColdFrontend;
use std::collections::BTreeSet;
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum CaptureStage {
    NonTextParsing,
    ResourceDemand,
    ResourceAdmission,
    RetainedResourceOrder,
    ResourceCatalog,
    AssetCapture,
    ResourceOrder,
    ResourceProjection,
    SymbolBinding,
    MapProjection,
    MapDescriptors,
    MapInitializers,
}
#[derive(Clone, Copy, Debug)]
pub struct CaptureMeasurement {
    pub stage: CaptureStage,
    pub seconds: f64,
    pub succeeded: bool,
}
pub type CaptureObserver<'a> = &'a dyn Fn(CaptureMeasurement);
fn timed<T>(
    observer: Option<CaptureObserver<'_>>,
    stage: CaptureStage,
    run: impl FnOnce() -> Result<T, String>,
) -> Result<T, String> {
    let _profile = dm_profile::stage(match stage {
        CaptureStage::NonTextParsing => "resources.parse_nontext",
        CaptureStage::ResourceDemand => "resources.demand",
        CaptureStage::ResourceAdmission => "resources.reuse_validation",
        CaptureStage::RetainedResourceOrder => "resources.retained_order",
        CaptureStage::ResourceCatalog => "resources.catalog",
        CaptureStage::AssetCapture => "resources.asset_capture",
        CaptureStage::ResourceOrder => "resources.order",
        CaptureStage::ResourceProjection => "resources.projection",
        CaptureStage::SymbolBinding => "resources.symbol_binding",
        CaptureStage::MapProjection => "maps.projection",
        CaptureStage::MapDescriptors => "maps.descriptors",
        CaptureStage::MapInitializers => "maps.initializers",
    });
    let start = std::time::Instant::now();
    let result = run();
    if let Some(observer) = observer {
        observer(CaptureMeasurement {
            stage,
            seconds: start.elapsed().as_secs_f64(),
            succeeded: result.is_ok(),
        });
    }
    result
}
pub struct CapturedNonTextOutput<R> {
    pub captured: crate::non_text::CapturedNonText,
    pub resolver: NativeResourceResolver<R>,
    pub symbols: SymbolTable,
    pub resources: ResourceProjection,
    pub map: Option<Projection>,
    pub descriptors: Option<DescriptorPlan>,
    pub artifacts: Vec<InitializationArtifact>,
    pub resource_search_context: u128,
    pub resource_catalog: dm_resources::catalog::ResourceCatalog,
    pub resource_archive_order: Vec<usize>,
    pub retained_resource_inputs: Option<crate::input_snapshot::InputSnapshot>,
}
/// Exact owned publication facts after executable composition has finished.
/// Captured source models, resolver caches and linking inventories do not cross
/// this boundary. The archive and authenticated reuse metadata move unchanged.
pub struct PublicationNonText {
    pub archive: crate::assets::ResourceArchive,
    pub resource_catalog: dm_resources::catalog::ResourceCatalog,
    pub resource_archive_order: Vec<usize>,
    pub retained_resource_inputs: Option<crate::input_snapshot::InputSnapshot>,
}

impl<R> CapturedNonTextOutput<R> {
    pub fn into_publication(self) -> PublicationNonText {
        PublicationNonText {
            archive: self.resources.archive,
            resource_catalog: self.resource_catalog,
            resource_archive_order: self.resource_archive_order,
            retained_resource_inputs: self.retained_resource_inputs,
        }
    }

    pub fn stage<'a>(
        &'a self,
        frontend: &'a ColdFrontend,
    ) -> crate::non_text_output::CapturedOutputStage<'a> {
        crate::non_text_output::CapturedOutputStage {
            source: frontend,
            maps: &self.captured.maps,
            map: self.map.as_ref(),
            descriptors: self.descriptors.as_ref(),
            resources: &self.resources,
            skin: Some(&self.captured.skin),
        }
    }
    pub fn extend_inventory(&self, inventory: &mut dm_link::LinkInventory) -> Result<(), String> {
        self.resources.extend_inventory(inventory);
        for (id, text) in self.symbols.ordered() {
            inventory.spellings.push((id, text.as_bytes().into()));
        }
        if let (Some(map), Some(descriptors)) = (&self.map, &self.descriptors) {
            descriptors
                .extend_inventory(map, inventory)
                .map_err(|error| format!("map inventory: {error:?}"))?;
        }
        Ok(())
    }
}
/// Executable handoff with parsed map documents released before lowering/linking.
pub struct PreparedNonTextOutput<R> {
    pub resolver: NativeResourceResolver<R>,
    pub symbols: SymbolTable,
    pub artifacts: Vec<InitializationArtifact>,
    pub resource_search_context: u128,
    stage: crate::non_text_output::PreparedOutputStage,
    resource_catalog: dm_resources::catalog::ResourceCatalog,
    resource_archive_order: Vec<usize>,
    retained_resource_inputs: Option<crate::input_snapshot::InputSnapshot>,
}
impl<R> CapturedNonTextOutput<R> {
    pub fn into_prepared(
        self,
        frontend: &ColdFrontend,
    ) -> Result<PreparedNonTextOutput<R>, String> {
        let Self {
            captured,
            resolver,
            symbols,
            resources,
            map,
            descriptors,
            artifacts,
            resource_search_context,
            resource_catalog,
            resource_archive_order,
            retained_resource_inputs,
        } = self;
        let stage = crate::non_text_output::PreparedOutputStage::new(
            frontend,
            &captured.maps,
            map,
            descriptors,
            resources,
            captured.skin,
        )?;
        // The remainder of captured (maps, skins, input documents, asset demand)
        // is dropped here; the writer retains only output plans and provenance.
        Ok(PreparedNonTextOutput {
            resolver,
            symbols,
            artifacts,
            resource_search_context,
            stage,
            resource_catalog,
            resource_archive_order,
            retained_resource_inputs,
        })
    }
}
impl<R> PreparedNonTextOutput<R> {
    /// Split the exact publication archive from source-independent output plans.
    pub fn into_composition_parts(
        self,
    ) -> (
        NativeResourceResolver<R>,
        crate::non_text_output::PreparedOutputStage,
        PublicationNonText,
    ) {
        let Self {
            resolver,
            symbols: _,
            artifacts: _,
            resource_search_context: _,
            mut stage,
            resource_catalog,
            resource_archive_order,
            retained_resource_inputs,
        } = self;
        let publication = PublicationNonText {
            archive: stage.take_archive(),
            resource_catalog,
            resource_archive_order,
            retained_resource_inputs,
        };
        (resolver, stage, publication)
    }

    pub fn stage(&self) -> &crate::non_text_output::PreparedOutputStage {
        &self.stage
    }
    pub fn extend_inventory(&self, inventory: &mut dm_link::LinkInventory) -> Result<(), String> {
        self.stage.extend_inventory(inventory, &self.symbols)
    }
    pub fn into_publication(self) -> PublicationNonText {
        PublicationNonText {
            archive: self.stage.into_archive(),
            resource_catalog: self.resource_catalog,
            resource_archive_order: self.resource_archive_order,
            retained_resource_inputs: self.retained_resource_inputs,
        }
    }
}
/// Defaults come only from the captured engine header and exact authored world
/// directives supplied by the preceding initializer classification stage.
fn defaults(
    engine: &byond_dmb::dmb::Dmb,
    directives: &[Directive],
) -> Result<WorldDefaults, String> {
    let class = |index: u32| -> Result<SymbolId, String> {
        let record = engine
            .classes
            .get(index as usize)
            .ok_or("engine map default class absent")?;
        let path = engine
            .string(record.path_string_id())
            .ok_or("engine map default path absent")?;
        let path = std::str::from_utf8(path).map_err(|_| "engine map default path not UTF-8")?;
        Ok(SymbolId::of(path))
    };
    let mut turf = Some(class(engine.world.turf_class_id())?);
    let mut area = Some(class(engine.world.area_class_id())?);
    let mut dimensions = engine.dimensions;
    for directive in directives {
        match directive {
            Directive::DefaultType {
                kind: DefaultKind::Turf,
                path,
            } => turf = *path,
            Directive::DefaultType {
                kind: DefaultKind::Area,
                path,
            } => area = *path,
            Directive::Dimension { axis, value } => {
                *dimensions
                    .get_mut(*axis)
                    .ok_or("invalid captured world dimension axis")? = *value
            }
            _ => (),
        }
    }
    Ok(WorldDefaults {
        turf: turf.ok_or("null default turf map semantics not yet supported")?,
        area: area.ok_or("null default area map semantics not yet supported")?,
        minimum_dimensions: dimensions,
    })
}
#[allow(clippy::too_many_arguments)] // Explicit immutable capture inputs, no global session/store.
pub fn capture<
    R: Resolver,
    P: dm_preprocess::SourceProvider,
    C: dm_resources::capture::CaptureProvider,
>(
    frontend: &ColdFrontend,
    provider: &P,
    resource_provider: &C,
    host: R,
    engine: &byond_dmb::dmb::Dmb,
    known_roots: &BTreeSet<SymbolId>,
    world_directives: &[Directive],
) -> Result<CapturedNonTextOutput<R>, String> {
    capture_with_observer(
        frontend,
        provider,
        resource_provider,
        host,
        engine,
        known_roots,
        world_directives,
        None,
    )
}
#[allow(clippy::too_many_arguments)] // Explicit immutable captured domains and optional observation.
pub fn capture_with_observer<
    R: Resolver,
    P: dm_preprocess::SourceProvider,
    C: dm_resources::capture::CaptureProvider,
>(
    frontend: &ColdFrontend,
    provider: &P,
    resource_provider: &C,
    host: R,
    engine: &byond_dmb::dmb::Dmb,
    known_roots: &BTreeSet<SymbolId>,
    world_directives: &[Directive],
    observer: Option<CaptureObserver<'_>>,
) -> Result<CapturedNonTextOutput<R>, String> {
    capture_with_map_memo(
        frontend,
        provider,
        resource_provider,
        host,
        engine,
        known_roots,
        world_directives,
        observer,
        None,
    )
}
#[allow(clippy::too_many_arguments)] // Existing capture boundary plus optional request-owned S5 memo.
pub fn capture_with_map_memo<
    R: Resolver,
    P: dm_preprocess::SourceProvider,
    C: dm_resources::capture::CaptureProvider,
>(
    frontend: &ColdFrontend,
    provider: &P,
    resource_provider: &C,
    host: R,
    engine: &byond_dmb::dmb::Dmb,
    known_roots: &BTreeSet<SymbolId>,
    world_directives: &[Directive],
    observer: Option<CaptureObserver<'_>>,
    map_memo: Option<&crate::map_memo::MapMemo>,
) -> Result<CapturedNonTextOutput<R>, String> {
    capture_with_resource_reuse(
        frontend,
        provider,
        resource_provider,
        host,
        engine,
        known_roots,
        world_directives,
        observer,
        map_memo,
        None,
    )
}
/// Caller validates the authenticated session manifest and archive against the
/// current grammar demand. Returning None requests ordinary full asset capture.
pub type ResourceAdmission<'a> =
    &'a dyn Fn(
        &dm_resources::capture::ResourceDemand,
    ) -> Result<Option<crate::resource_manifest::ValidatedResources>, String>;
#[allow(clippy::too_many_arguments)] // Existing explicit capture inputs plus independently validated archive admission.
pub fn capture_with_resource_reuse<
    R: Resolver,
    P: dm_preprocess::SourceProvider,
    C: dm_resources::capture::CaptureProvider,
>(
    frontend: &ColdFrontend,
    provider: &P,
    resource_provider: &C,
    host: R,
    engine: &byond_dmb::dmb::Dmb,
    known_roots: &BTreeSet<SymbolId>,
    world_directives: &[Directive],
    observer: Option<CaptureObserver<'_>>,
    map_memo: Option<&crate::map_memo::MapMemo>,
    admission: Option<ResourceAdmission<'_>>,
) -> Result<CapturedNonTextOutput<R>, String> {
    capture_with_resource_operation(
        frontend,
        provider,
        resource_provider,
        host,
        engine,
        known_roots,
        world_directives,
        observer,
        map_memo,
        admission,
        None,
        crate::assets::capture_discovered,
    )
}

#[allow(clippy::too_many_arguments)] // One request-owned executor for every capture stage.
pub fn capture_with_resource_reuse_on_executor<
    R: Resolver,
    P: dm_preprocess::SourceProvider,
    C: dm_resources::capture::CaptureProvider + Sync,
>(
    frontend: &ColdFrontend,
    provider: &P,
    resource_provider: &C,
    host: R,
    engine: &byond_dmb::dmb::Dmb,
    known_roots: &BTreeSet<SymbolId>,
    world_directives: &[Directive],
    observer: Option<CaptureObserver<'_>>,
    map_memo: Option<&crate::map_memo::MapMemo>,
    admission: Option<ResourceAdmission<'_>>,
    executor: &dm_exec::BuildExecutor,
) -> Result<CapturedNonTextOutput<R>, String> {
    capture_with_resource_reuse_on_executor_with_sink(
        frontend,
        provider,
        resource_provider,
        host,
        engine,
        known_roots,
        world_directives,
        observer,
        map_memo,
        admission,
        executor,
        None,
    )
}

#[allow(clippy::too_many_arguments)] // Existing captured request plus optional immutable archive writer.
pub fn capture_with_resource_reuse_on_executor_with_sink<
    R: Resolver,
    P: dm_preprocess::SourceProvider,
    C: dm_resources::capture::CaptureProvider + Sync,
>(
    frontend: &ColdFrontend,
    provider: &P,
    resource_provider: &C,
    host: R,
    engine: &byond_dmb::dmb::Dmb,
    known_roots: &BTreeSet<SymbolId>,
    world_directives: &[Directive],
    observer: Option<CaptureObserver<'_>>,
    map_memo: Option<&crate::map_memo::MapMemo>,
    admission: Option<ResourceAdmission<'_>>,
    executor: &dm_exec::BuildExecutor,
    sink: Option<&dyn crate::assets::ResourceArchiveSink>,
) -> Result<CapturedNonTextOutput<R>, String> {
    capture_with_resource_operation(
        frontend,
        provider,
        resource_provider,
        host,
        engine,
        known_roots,
        world_directives,
        observer,
        map_memo,
        admission,
        sink,
        |demand, extra, provider| {
            crate::assets::capture_discovered_on_executor(demand, extra, provider, executor)
        },
    )
}

#[allow(clippy::too_many_arguments)] // Shared ordered orchestration, independent candidate capture strategy.
fn capture_with_resource_operation<
    R: Resolver,
    P: dm_preprocess::SourceProvider,
    C: dm_resources::capture::CaptureProvider,
>(
    frontend: &ColdFrontend,
    provider: &P,
    resource_provider: &C,
    host: R,
    engine: &byond_dmb::dmb::Dmb,
    known_roots: &BTreeSet<SymbolId>,
    world_directives: &[Directive],
    observer: Option<CaptureObserver<'_>>,
    map_memo: Option<&crate::map_memo::MapMemo>,
    admission: Option<ResourceAdmission<'_>>,
    sink: Option<&dyn crate::assets::ResourceArchiveSink>,
    capture_resources: impl FnOnce(
        dm_resources::capture::ResourceDemand,
        &crate::assets::ExtraAssets,
        &C,
    ) -> Result<
        dm_resources::capture::CapturedResources,
        dm_resources::capture::CaptureError,
    >,
) -> Result<CapturedNonTextOutput<R>, String> {
    let captured = timed(observer, CaptureStage::NonTextParsing, || {
        crate::non_text::capture_with_map_memo(frontend, provider, map_memo)
            .map_err(|error| format!("nontext capture: {error:?}"))
    })?;
    let demand = timed(observer, CaptureStage::ResourceDemand, || {
        dm_resources::capture::discover_demand(
            &frontend.plan,
            &frontend.expanded,
            &captured.assets.literals,
            &captured.assets.skins,
        )
        .map_err(|error| error.to_string())
    })?;
    let context = demand.context.identity();
    let retained = match admission {
        Some(admit) => timed(observer, CaptureStage::ResourceAdmission, || admit(&demand))?,
        None => None,
    };
    let retained = if let Some(retained) = retained {
        let candidate = timed(observer, CaptureStage::RetainedResourceOrder, || {
            reject_missing_demands(
                frontend,
                &captured,
                &demand.literals,
                &retained.catalog.record().lookups,
            )?;
            let (prefix, suffix) =
                crate::resource_order::metadata_nontext_imports(&captured, &retained.catalog)?;
            crate::resource_order::metadata_archive_order(
                frontend,
                &retained.catalog,
                &demand,
                &host,
                known_roots,
                &prefix,
                &suffix,
            )
        });
        match candidate {
            Ok(order) if order == retained.content.order => Some((retained, order)),
            _ => None,
        }
    } else {
        None
    };
    let (resolver, projection, order, retained_inputs, retained_catalog) =
        if let Some((retained, current_order)) = retained {
            let resolver = timed(observer, CaptureStage::SymbolBinding, || {
                let mut symbols = SymbolTable::overlay(frontend.snapshot.tree.shared_symbols());
                for map in captured.maps.iter() {
                    for (_, text) in map.symbols.ordered() {
                        symbols.intern(text).map_err(|error| error.to_string())?;
                    }
                }
                let resolver = NativeResourceResolver::from_catalog(
                    host,
                    std::sync::Arc::new(symbols),
                    &retained.catalog,
                )
                .map_err(|error| error.to_string())?;
                Ok(resolver)
            })?;
            let projection = timed(observer, CaptureStage::ResourceProjection, || {
                crate::assets::project_retained_resources(
                    &retained.catalog,
                    &retained.content.order,
                    retained.content.archive,
                )
                .map_err(|error| format!("retained resource projection: {error:?}"))
            })?;
            (
                resolver,
                projection,
                current_order,
                Some(retained.inputs),
                Some(retained.catalog),
            )
        } else {
            let resources = timed(observer, CaptureStage::AssetCapture, || {
                let resources = capture_resources(demand, &captured.assets, resource_provider)
                    .map_err(|error| error.to_string())?;
                reject_missing_literals(frontend, &captured, &resources)?;
                crate::heap_census::emit_if_enabled("resources.captured", |census| {
                    census.resources(&resources)
                })
                .map_err(|error| format!("heap census: {error}"))?;
                resources
                    .require_complete()
                    .map_err(|error| error.to_string())?;
                Ok(resources)
            })?;
            let order = timed(observer, CaptureStage::ResourceOrder, || {
                let (prefix, suffix) =
                    crate::resource_order::nontext_imports(&captured, &resources)?;
                crate::resource_order::captured_archive_order(
                    frontend,
                    &resources,
                    &host,
                    known_roots,
                    &prefix,
                    &suffix,
                )
            })?;
            let resolver = timed(observer, CaptureStage::SymbolBinding, || {
                let mut symbols = SymbolTable::overlay(frontend.snapshot.tree.shared_symbols());
                for map in captured.maps.iter() {
                    for (_, text) in map.symbols.ordered() {
                        symbols.intern(text).map_err(|error| error.to_string())?;
                    }
                }
                for lookup in &resources.lookups {
                    symbols
                        .intern(&lookup.path)
                        .map_err(|error| error.to_string())?;
                }
                resources
                    .into_resolver_shared(host, std::sync::Arc::new(symbols))
                    .map_err(|error| error.to_string())
            })?;
            let projection = timed(observer, CaptureStage::ResourceProjection, || {
                crate::assets::project_captured_resources_with_sink(&resolver, &order, sink)
                    .map_err(|error| format!("resource projection: {error:?}"))
            })?;
            (resolver, projection, order, None, None)
        };
    let resolver = resolver.into_metadata();
    // This is the same immutable catalog used to construct the metadata host.
    // Reissuing it would clone/sort every lookup and reserialize its identity.
    let catalog = timed(observer, CaptureStage::ResourceCatalog, || {
        Ok(retained_catalog.unwrap_or_else(|| resolver.catalog()))
    })?;
    let symbols = SymbolTable::overlay(resolver.shared_symbols());
    let (map, descriptors, artifacts) = if captured.maps.is_empty() {
        (None, None, Vec::new())
    } else {
        let map = timed(observer, CaptureStage::MapProjection, || {
            let defaults = defaults(engine, world_directives)?;
            match map_memo {
                Some(memo) => memo.project(&captured.maps, defaults, &resolver),
                None => crate::map_projection::project(
                    &captured.maps,
                    defaults,
                    &crate::map_projection::ResolverClassifier(&resolver),
                ),
            }
            .map_err(|error| format!("map projection: {error:?}"))
        })?;
        let prepare_descriptors = |cached: Option<&crate::map_output::DescriptorPlan>| {
            timed(observer, CaptureStage::MapDescriptors, || match cached {
                Some(plan) => Ok(plan.clone()),
                None => crate::map_output::descriptors(frontend, &map, &captured.maps)
                    .map_err(|error| format!("map descriptors: {error:?}")),
            })
        };
        let prepare_initializers =
            |cached: Option<&[InitializationArtifact]>,
             descriptors: &crate::map_output::DescriptorPlan,
             host: &dm_session::RecordingResolver<'_, _>| {
                timed(observer, CaptureStage::MapInitializers, || match cached {
                    Some(artifacts) => Ok(artifacts.to_vec()),
                    None => crate::map_artifacts::lower_with_memo(
                        frontend,
                        &captured.maps,
                        &map,
                        descriptors,
                        &symbols,
                        host,
                        Some(context),
                        map_memo,
                    ),
                })
            };
        let (descriptors, artifacts) = match map_memo {
            Some(memo) => memo.output_artifacts(
                crate::map_memo::MapOutputInputs {
                    frontend,
                    maps: &captured.maps,
                    projection: &map,
                    host: &resolver,
                    resource_search_context: Some(context),
                },
                prepare_descriptors,
                prepare_initializers,
            )?,
            None => {
                let descriptors = prepare_descriptors(None)?;
                let recording = dm_session::RecordingResolver::new(&resolver);
                let artifacts = prepare_initializers(None, &descriptors, &recording)?;
                (descriptors, artifacts)
            }
        };
        (Some(map), Some(descriptors), artifacts)
    };
    if let Some(memo) = map_memo {
        memo.finish_revision();
    }
    Ok(CapturedNonTextOutput {
        captured,
        resolver,
        symbols,
        resources: projection,
        map,
        descriptors,
        artifacts,
        resource_search_context: context,
        resource_catalog: catalog,
        resource_archive_order: order,
        retained_resource_inputs: retained_inputs,
    })
}
/// Missing DM/map literals are proven source errors; a missing DMF-only icon
/// is an allowed negative lookup. Preserve the first unique request's origin.
fn reject_missing_literals(
    frontend: &ColdFrontend,
    nontext: &crate::non_text::CapturedNonText,
    captured: &dm_resources::capture::CapturedResources,
) -> Result<(), String> {
    reject_missing_demands(frontend, nontext, &captured.literals, &captured.lookups)
}
fn reject_missing_demands(
    frontend: &ColdFrontend,
    nontext: &crate::non_text::CapturedNonText,
    literals: &[dm_resources::capture::LiteralRequest],
    lookups: &[dm_resources::native_resolver::CapturedResourceLookup],
) -> Result<(), String> {
    use dm_resources::native_resolver::CapturedResourceOutcome;
    let extra_count = nontext.assets.literals.len();
    if extra_count != nontext.assets.origins.len() || literals.len() < extra_count {
        return Err("internal compiler error: resource literal origin coverage mismatch".into());
    }
    let missing_paths = lookups
        .iter()
        .filter(|entry| entry.outcome == CapturedResourceOutcome::Missing)
        .map(|entry| entry.path.as_str())
        .collect::<std::collections::HashSet<_>>();
    let code_count = literals.len() - extra_count;
    for (index, literal) in literals.iter().enumerate() {
        // Preserve any-Missing semantics even for contradictory duplicate
        // lookup records; retain literal encounter order for the first error.
        let missing = missing_paths.contains(literal.path.as_str());
        if !missing {
            continue;
        }
        if index < code_count {
            let location = frontend
                .location(literal.span.start)
                .ok_or("internal compiler error: missing resource has no current source origin")?;
            return Err(format!(
                "{}:{}:error: '{}': cannot find file",
                location.semantic_path, location.line, literal.path
            ));
        }
        let origin = &nontext.assets.origins[index - code_count];
        let occurrence = usize::try_from(origin.include_occurrence)
            .map_err(|_| "internal compiler error: resource include occurrence overflow")?;
        let include = frontend
            .plan
            .occurrences
            .get(occurrence)
            .ok_or("internal compiler error: resource include occurrence absent")?;
        if include.path != origin.source {
            return Err(
                "internal compiler error: resource source path differs from captured include"
                    .into(),
            );
        }
        if nontext
            .skins
            .iter()
            .any(|skin| skin.include_occurrence == origin.include_occurrence)
        {
            continue;
        }
        let map = nontext
            .maps
            .iter()
            .find(|map| map.captured.include_occurrence == origin.include_occurrence)
            .ok_or("internal compiler error: nontext missing resource has no map/skin origin")?;
        let preceding = map
            .captured
            .source
            .get(..origin.span.start)
            .ok_or("internal compiler error: map resource source range absent")?;
        let line = preceding.bytes().filter(|byte| *byte == b'\n').count() + 1;
        return Err(format!(
            "{}:{line}:error: cannot find file",
            include.semantic_path
        ));
    }
    Ok(())
}

#[cfg(test)]
#[path = "captured_non_text_driver/tests.rs"]
mod tests;
