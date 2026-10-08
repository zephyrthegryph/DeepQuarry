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
impl<R> CapturedNonTextOutput<R> {
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
            Ok(order) if order == retained.order => Some(retained),
            _ => None,
        }
    } else {
        None
    };
    let (resolver, projection, order, retained_inputs, retained_catalog) = if let Some(retained) =
        retained
    {
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
                &retained.order,
                retained.archive,
            )
            .map_err(|error| format!("retained resource projection: {error:?}"))
        })?;
        (
            resolver,
            projection,
            retained.order,
            Some(retained.inputs),
            Some(retained.catalog),
        )
    } else {
        let resources = timed(observer, CaptureStage::AssetCapture, || {
            let resources =
                crate::assets::capture_discovered(demand, &captured.assets, resource_provider)
                    .map_err(|error| error.to_string())?;
            reject_missing_literals(frontend, &captured, &resources)?;
            resources
                .require_complete()
                .map_err(|error| error.to_string())?;
            Ok(resources)
        })?;
        let order = timed(observer, CaptureStage::ResourceOrder, || {
            let (prefix, suffix) = crate::resource_order::nontext_imports(&captured, &resources)?;
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
            crate::assets::project_captured_resources(&resolver, &order)
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
        let descriptors = timed(observer, CaptureStage::MapDescriptors, || {
            crate::map_output::descriptors(frontend, &map, &captured.maps)
                .map_err(|error| format!("map descriptors: {error:?}"))
        })?;
        let artifacts = timed(observer, CaptureStage::MapInitializers, || {
            crate::map_artifacts::lower(
                frontend,
                &captured.maps,
                &map,
                &descriptors,
                &symbols,
                &resolver,
                Some(context),
            )
        })?;
        (Some(map), Some(descriptors), artifacts)
    };
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
mod tests {
    use super::*;
    use std::{path::Path, sync::Arc};
    struct Source;
    impl dm_preprocess::SourceProvider for Source {
        fn read(&self, path: &Path) -> Result<String, String> {
            match path.file_name().and_then(|name|name.to_str()) {
                Some("project.dme")=>Ok("#include \"skin.dmf\"\n#include \"source.dm\"\n#include \"map.dmm\"\n".into()),
                Some("source.dm")=>Ok("/turf/tile\n    var/asset\n/obj/plain\n".into()),
                Some("skin.dmf")=>Ok("macro \"default\"\nwindow \"default\"\n    elem \"main\"\n        type = MAIN\n        icon = 'tiny.png'\n".into()),
                Some("map.dmm")=>Ok("\"a\"=(/obj/plain,/turf/tile{asset='asset.txt'},/area)\n(1,1,1)={\"a\"}\n".into()),
                _=>Err("fixture input absent".into()),
            }
        }
    }
    impl dm_resources::capture::CaptureProvider for Source {
        fn read_candidate(&self, path: &Path) -> std::io::Result<Option<Arc<[u8]>>> {
            let bytes = match path.file_name().and_then(|name| name.to_str()) {
                Some("skin.dmf") => dm_preprocess::SourceProvider::read(self, path)
                    .unwrap()
                    .into_bytes(),
                Some("tiny.png") => {
                    include_bytes!("../../../fixtures/translation/selected_skin/tiny.png").to_vec()
                }
                Some("asset.txt") => b"map asset".to_vec(),
                _ => return Ok(None),
            };
            Ok(Some(bytes.into()))
        }
    }
    #[derive(Clone, Copy)]
    enum MissingDomain {
        Code,
        Map,
        Skin,
    }
    impl dm_preprocess::SourceProvider for MissingDomain {
        fn read(&self, path: &Path) -> Result<String, String> {
            match path.file_name().and_then(|name| name.to_str()) {
                Some("project.dme") => Ok(match self {
                    Self::Code => "#include \"source.dm\"\n",
                    Self::Map => "#include \"source.dm\"\n#include \"map.dmm\"\n",
                    Self::Skin => "#include \"skin.dmf\"\n",
                }
                .into()),
                Some("source.dm") if matches!(self, Self::Code) => Ok(
                    "/var/asset='missing.png'\n/proc/probe()\n    return 'missing.png'\n".into(),
                ),
                Some("map.dmm") => dm_preprocess::SourceProvider::read(&Source, path)
                    .map(|text| text.replace("asset.txt", "missing.png")),
                Some("skin.dmf") => dm_preprocess::SourceProvider::read(&Source, path)
                    .map(|text| text.replace("tiny.png", "missing.png")),
                _ => dm_preprocess::SourceProvider::read(&Source, path),
            }
        }
    }
    impl dm_resources::capture::CaptureProvider for MissingDomain {
        fn read_candidate(&self, path: &Path) -> std::io::Result<Option<Arc<[u8]>>> {
            if path.file_name().and_then(|name| name.to_str()) == Some("skin.dmf") {
                return Ok(Some(
                    dm_preprocess::SourceProvider::read(self, path)
                        .unwrap()
                        .into_bytes()
                        .into(),
                ));
            }
            dm_resources::capture::CaptureProvider::read_candidate(&Source, path)
        }
    }
    #[test]
    fn contradictory_missing_lookups_preserve_first_literal_error() {
        use dm_resources::native_resolver::{CapturedResourceLookup, CapturedResourceOutcome};
        let bytes = include_bytes!("../../../fixtures/native_template.bin");
        let engine = crate::engine::EngineSnapshot::from_bytes(bytes, 1).unwrap();
        let seed = engine.frontend_seed();
        let domain = MissingDomain::Code;
        let frontend = dm_tree::frontend::build_with_config(
            Path::new("game/project.dme"),
            &domain,
            &Default::default(),
            dm_tree::frontend::FrontendConfig {
                workers: 1,
                engine: Some(&seed),
                observer: None,
            },
        )
        .unwrap();
        let nontext = crate::non_text::capture_with_map_memo(&frontend, &domain, None).unwrap();
        let demand = dm_resources::capture::discover_demand(
            &frontend.plan,
            &frontend.expanded,
            &nontext.assets.literals,
            &nontext.assets.skins,
        )
        .unwrap();
        let lookups = vec![
            CapturedResourceLookup {
                path: "asset.txt".into(),
                search_context: demand.context.identity(),
                outcome: CapturedResourceOutcome::Missing,
            },
            CapturedResourceLookup {
                path: "missing.png".into(),
                search_context: demand.context.identity(),
                outcome: CapturedResourceOutcome::Missing,
            },
            CapturedResourceLookup {
                path: "missing.png".into(),
                search_context: demand.context.identity(),
                outcome: CapturedResourceOutcome::Unsupported,
            },
        ];
        let error =
            reject_missing_demands(&frontend, &nontext, &demand.literals, &lookups).unwrap_err();
        assert!(
            error.ends_with("source.dm:1:error: 'missing.png': cannot find file"),
            "{error}"
        );
        let mut reordered = lookups;
        reordered.reverse();
        assert_eq!(
            reject_missing_demands(&frontend, &nontext, &demand.literals, &reordered).unwrap_err(),
            error
        );
    }
    #[test]
    fn missing_literal_errors_preserve_domain_and_current_source_origin() {
        let bytes = include_bytes!("../../../fixtures/native_template.bin");
        let engine = crate::engine::EngineSnapshot::from_bytes(bytes, 1).unwrap();
        let seed = engine.frontend_seed();
        let decoded = byond_dmb::dmb::Dmb::from_bytes(bytes).unwrap();
        for domain in [MissingDomain::Code, MissingDomain::Map, MissingDomain::Skin] {
            let frontend = dm_tree::frontend::build_with_config(
                Path::new("game/project.dme"),
                &domain,
                &Default::default(),
                dm_tree::frontend::FrontendConfig {
                    workers: 1,
                    engine: Some(&seed),
                    observer: None,
                },
            )
            .unwrap();
            let measurements = std::cell::RefCell::new(Vec::new());
            let observer = |measurement| measurements.borrow_mut().push(measurement);
            let result = capture_with_observer(
                &frontend,
                &domain,
                &domain,
                Tree(frontend.snapshot.tree.clone()),
                &decoded,
                &BTreeSet::new(),
                &[],
                Some(&observer),
            );
            let stages = measurements.borrow();
            assert!(stages
                .iter()
                .all(|stage: &CaptureMeasurement| stage.seconds >= 0.0));
            if !matches!(domain, MissingDomain::Skin) {
                assert_eq!(stages.last().unwrap().stage, CaptureStage::AssetCapture);
                assert!(!stages.last().unwrap().succeeded);
                assert_eq!(stages.len(), 3);
                assert_eq!(stages[0].stage, CaptureStage::NonTextParsing);
                assert_eq!(stages[1].stage, CaptureStage::ResourceDemand);
                assert!(stages[0].succeeded);
                assert!(stages[1].succeeded);
            }
            match domain {
                MissingDomain::Code => match result {
                    Err(message) => assert!(
                        message.ends_with("source.dm:1:error: 'missing.png': cannot find file"),
                        "{message}"
                    ),
                    Ok(_) => panic!("missing DM literal accepted"),
                },
                MissingDomain::Map => match result {
                    Err(message) => assert!(
                        message.ends_with("map.dmm:1:error: cannot find file"),
                        "{message}"
                    ),
                    Ok(_) => panic!("missing map literal accepted"),
                },
                MissingDomain::Skin => {
                    let output = result.unwrap();
                    assert_eq!(output.resources.records.len(), 1);
                }
            }
        }
    }
    struct Tree(Arc<dm_tree::SemanticTree>);
    impl Resolver for Tree {
        fn resolve(&self, query: dm_ir::ResolveQuery) -> dm_ir::ResolvedMeaning {
            dm_ir::Resolver::resolve(self.0.as_ref(), query)
        }
    }
    #[test]
    fn map_skin_asset_capture_produces_shared_inventory_and_initializer_artifact() {
        let bytes = include_bytes!("../../../fixtures/native_template.bin");
        let engine = crate::engine::EngineSnapshot::from_bytes(bytes, 1).unwrap();
        let seed = engine.frontend_seed();
        let frontend = dm_tree::frontend::build_with_config(
            Path::new("game/project.dme"),
            &Source,
            &Default::default(),
            dm_tree::frontend::FrontendConfig {
                workers: 1,
                engine: Some(&seed),
                observer: None,
            },
        )
        .unwrap();
        let roots = [
            "/",
            "/datum",
            "/obj",
            "/mob",
            "/turf",
            "/area",
            "/client",
            "/atom",
            "/image",
            "/mutable_appearance",
        ]
        .into_iter()
        .map(SymbolId::of)
        .collect();
        let decoded = byond_dmb::dmb::Dmb::from_bytes(bytes).unwrap();
        let directives = vec![
            Directive::DefaultType {
                kind: DefaultKind::Turf,
                path: Some(SymbolId::of("/turf/tile")),
            },
            Directive::Dimension { axis: 0, value: 2 },
            Directive::Dimension { axis: 1, value: 1 },
            Directive::Dimension { axis: 2, value: 1 },
        ];
        let output = capture(
            &frontend,
            &Source,
            &Source,
            Tree(frontend.snapshot.tree.clone()),
            &decoded,
            &roots,
            &directives,
        )
        .unwrap();
        assert!(output.symbols.text(SymbolId::of("asset")).is_some());
        assert_eq!(
            output.symbols.text(SymbolId::of("asset.txt")),
            Some("asset.txt")
        );
        assert!(matches!(
            output.resolver.resolve(dm_ir::ResolveQuery::ResourceIn {
                path: SymbolId::of("asset.txt"),
                search_context: output.resource_search_context,
            }),
            dm_ir::ResolvedMeaning::Resource { .. }
        ));
        assert_eq!(output.map.as_ref().unwrap().dimensions, [2, 1, 1]);
        assert_eq!(
            output.map.as_ref().unwrap().instances[0].atom.type_path,
            SymbolId::of("/turf/tile")
        );
        assert_eq!(output.artifacts.len(), 1);
        let records =
            byond_dmb::rsc::read_all(&mut output.resources.archive.captured_bytes().unwrap())
                .unwrap();
        let aliases = records
            .iter()
            .map(|entry| match entry {
                byond_dmb::rsc::Entry::Named(named) => named.name.as_slice(),
                _ => panic!(),
            })
            .collect::<Vec<_>>();
        assert_eq!(
            aliases,
            [
                b"tiny.png".as_slice(),
                b"skin.dmf".as_slice(),
                b"asset.txt".as_slice()
            ]
        );
        let mut inventory = dm_link::LinkInventory::default();
        output.extend_inventory(&mut inventory).unwrap();
        assert!(inventory
            .entries
            .iter()
            .any(|entry| matches!(entry.key, dm_link::Key::MapInstance { .. })));
        let stage = output.stage(&frontend);
        crate::composition::NonTextOutputStage::validate_source(&stage, &frontend).unwrap();
        assert!(
            crate::composition::NonTextOutputStage::required_types(&stage)
                .contains(&SymbolId::of("/obj/plain"))
        );
    }
    #[test]
    fn retained_source_only_capture_preserves_rows_and_skips_asset_reads() {
        struct Changed;
        impl dm_preprocess::SourceProvider for Changed {
            fn read(&self, path: &Path) -> Result<String, String> {
                let mut text = dm_preprocess::SourceProvider::read(&Source, path)?;
                if path.file_name().and_then(|name| name.to_str()) == Some("source.dm") {
                    text.push_str("// source-only edit\n");
                }
                Ok(text)
            }
        }
        struct NoAssets;
        impl dm_resources::capture::CaptureProvider for NoAssets {
            fn read_candidate(&self, _: &Path) -> std::io::Result<Option<Arc<[u8]>>> {
                panic!("retained capture reread asset payload")
            }
        }
        struct Facts;
        impl crate::input_snapshot::SnapshotProvider for Facts {
            fn stamp(&self, path: &Path) -> std::io::Result<crate::input_snapshot::Stamp> {
                let bytes =
                    dm_resources::capture::CaptureProvider::read_candidate(&Source, path)?.unwrap();
                Ok(crate::input_snapshot::Stamp {
                    size: bytes.len() as u64,
                    modified_ns: 1,
                    file_id: Some(1),
                })
            }
            fn read(
                &self,
                path: &Path,
            ) -> std::io::Result<(crate::input_snapshot::Stamp, Vec<u8>)> {
                Ok((
                    self.stamp(path)?,
                    dm_resources::capture::CaptureProvider::read_candidate(&Source, path)?
                        .unwrap()
                        .to_vec(),
                ))
            }
            fn list(&self, _: &Path) -> std::io::Result<crate::input_snapshot::FolderListing> {
                Ok(crate::input_snapshot::FolderListing::Missing)
            }
        }
        use crate::input_snapshot::SnapshotProvider;
        let bytes = include_bytes!("../../../fixtures/native_template.bin");
        let engine = crate::engine::EngineSnapshot::from_bytes(bytes, 1).unwrap();
        let seed = engine.frontend_seed();
        let config = dm_tree::frontend::FrontendConfig {
            workers: 1,
            engine: Some(&seed),
            observer: None,
        };
        let frontend = dm_tree::frontend::build_with_config(
            Path::new("game/project.dme"),
            &Source,
            &Default::default(),
            config,
        )
        .unwrap();
        let decoded = byond_dmb::dmb::Dmb::from_bytes(bytes).unwrap();
        let roots = [
            "/",
            "/datum",
            "/obj",
            "/mob",
            "/turf",
            "/area",
            "/client",
            "/atom",
            "/image",
            "/mutable_appearance",
        ]
        .into_iter()
        .map(SymbolId::of)
        .collect();
        let directives = [Directive::DefaultType {
            kind: DefaultKind::Turf,
            path: Some(SymbolId::of("/turf/tile")),
        }];
        let cold = capture(
            &frontend,
            &Source,
            &Source,
            Tree(frontend.snapshot.tree.clone()),
            &decoded,
            &roots,
            &directives,
        )
        .unwrap();
        let mut inputs = crate::input_snapshot::InputSnapshot::new(10_000_000_000);
        for alias in &cold.resource_catalog.record().aliases {
            let (stamp, bytes) = Facts.read(&alias.disk_path).unwrap();
            inputs.record_file(&alias.disk_path, stamp, &bytes).unwrap();
        }
        let archive = cold.resources.archive.identity();
        let manifest = crate::resource_manifest::ResourceManifest::capture(
            7,
            &cold.resource_catalog,
            inputs,
            cold.resource_archive_order.clone(),
            archive,
        )
        .unwrap();
        let changed = dm_tree::frontend::build_with_config(
            Path::new("game/project.dme"),
            &Changed,
            &Default::default(),
            dm_tree::frontend::FrontendConfig {
                workers: 1,
                engine: Some(&seed),
                observer: None,
            },
        )
        .unwrap();
        assert_ne!(changed.expanded.text, frontend.expanded.text);
        let authenticated = std::cell::Cell::new(0);
        let admission = |demand: &dm_resources::capture::ResourceDemand| {
            manifest
                .validate(7, demand, &Facts, false, 20_000_000_000, |identity| {
                    authenticated.set(authenticated.get() + 1);
                    Ok(identity == archive)
                })
                .map_err(|error| error.to_string())
        };
        let retained = capture_with_resource_reuse(
            &changed,
            &Changed,
            &NoAssets,
            Tree(changed.snapshot.tree.clone()),
            &decoded,
            &roots,
            &directives,
            None,
            None,
            Some(&admission),
        )
        .unwrap();
        assert_eq!(authenticated.get(), 1);
        assert!(
            matches!(retained.resources.archive,crate::assets::ResourceArchive::Retained(identity) if identity==archive)
        );
        assert!(retained.resolver.resources().is_none());
        assert_eq!(cold.resources.records, retained.resources.records);
        assert_eq!(cold.resource_archive_order, retained.resource_archive_order);
        assert_eq!(
            cold.resource_catalog.identity(),
            retained.resource_catalog.identity()
        );
        assert_eq!(
            cold.resource_catalog.record(),
            retained.resource_catalog.record()
        );
        assert_eq!(
            cold.resources
                .inventory
                .iter()
                .map(|entry| (entry.key, entry.content.as_ref()))
                .collect::<Vec<_>>(),
            retained
                .resources
                .inventory
                .iter()
                .map(|entry| (entry.key, entry.content.as_ref()))
                .collect::<Vec<_>>()
        );
        assert_eq!(retained.artifacts.len(), cold.artifacts.len());
    }
    #[test]
    fn unsupported_map_type_reports_current_origin_and_query_spellings() {
        struct ContextualSource;
        impl dm_preprocess::SourceProvider for ContextualSource {
            fn read(&self, path: &Path) -> Result<String, String> {
                if path.file_name().and_then(|name| name.to_str()) == Some("map.dmm") {
                    Ok(
                        "\"a\"=(/obj/plain,/turf/tile{\nasset=new()\n},/area)\n(1,1,1)={\"a\"}\n"
                            .into(),
                    )
                } else {
                    dm_preprocess::SourceProvider::read(&Source, path)
                }
            }
        }
        struct OpaqueType(Tree);
        impl Resolver for OpaqueType {
            fn resolve(&self, query: dm_ir::ResolveQuery) -> dm_ir::ResolvedMeaning {
                if matches!(query, dm_ir::ResolveQuery::DeclaredVarType { owner, name }
                    if owner == SymbolId::of("/turf/tile") && name == SymbolId::of("asset"))
                {
                    dm_ir::ResolvedMeaning::Unsupported(query)
                } else {
                    self.0.resolve(query)
                }
            }
        }
        let bytes = include_bytes!("../../../fixtures/native_template.bin");
        let engine = crate::engine::EngineSnapshot::from_bytes(bytes, 1).unwrap();
        let seed = engine.frontend_seed();
        let frontend = dm_tree::frontend::build_with_config(
            Path::new("game/project.dme"),
            &ContextualSource,
            &Default::default(),
            dm_tree::frontend::FrontendConfig {
                workers: 1,
                engine: Some(&seed),
                observer: None,
            },
        )
        .unwrap();
        let measurements = std::cell::RefCell::new(Vec::new());
        let observer = |measurement| measurements.borrow_mut().push(measurement);
        let result = capture_with_observer(
            &frontend,
            &ContextualSource,
            &Source,
            OpaqueType(Tree(frontend.snapshot.tree.clone())),
            &byond_dmb::dmb::Dmb::from_bytes(bytes).unwrap(),
            &BTreeSet::new(),
            &[],
            Some(&observer),
        );
        let message = match result {
            Err(message) => message,
            Ok(_) => panic!("opaque contextual map type was accepted"),
        };
        assert!(
            message.contains("map.dmm:1: unsupported map initializer for /turf/tile"),
            "{message}"
        );
        assert!(
            message.contains("owner=/turf/tile, field=asset"),
            "{message}"
        );
        let measurements = measurements.borrow();
        assert_eq!(
            measurements.last().unwrap().stage,
            CaptureStage::MapInitializers
        );
        assert!(!measurements.last().unwrap().succeeded);
    }
}
