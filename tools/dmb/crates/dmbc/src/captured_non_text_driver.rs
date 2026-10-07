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
pub struct CapturedNonTextOutput<R> {
    pub captured: crate::non_text::CapturedNonText,
    pub resolver: NativeResourceResolver<R>,
    pub symbols: SymbolTable,
    pub resources: ResourceProjection,
    pub map: Option<Projection>,
    pub descriptors: Option<DescriptorPlan>,
    pub artifacts: Vec<InitializationArtifact>,
    pub resource_search_context: u128,
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
    let captured = crate::non_text::capture(frontend, provider)
        .map_err(|error| format!("nontext capture: {error:?}"))?;
    let resources = crate::assets::capture(frontend, &captured.assets, resource_provider)
        .map_err(|error| error.to_string())?;
    resources
        .require_complete()
        .map_err(|error| error.to_string())?;
    let (prefix, suffix) = crate::resource_order::nontext_imports(&captured, &resources)?;
    let order = crate::resource_order::captured_archive_order(
        frontend,
        &resources,
        &host,
        known_roots,
        &prefix,
        &suffix,
    )?;
    let projection = crate::assets::project_resources(&resources.resources, &order)
        .map_err(|error| format!("resource projection: {error:?}"))?;
    let context = resources.context.identity();
    let mut symbols = frontend.snapshot.tree.symbols().clone();
    for map in captured.maps.iter() {
        for (_, text) in map.symbols.ordered() {
            symbols.intern(text).map_err(|error| error.to_string())?;
        }
    }
    let resolver = resources
        .into_resolver(host, &symbols)
        .map_err(|error| error.to_string())?;
    let (map, descriptors, artifacts) = if captured.maps.is_empty() {
        (None, None, Vec::new())
    } else {
        let map = crate::map_projection::project(
            &captured.maps,
            defaults(engine, world_directives)?,
            &crate::map_projection::ResolverClassifier(&resolver),
        )
        .map_err(|error| format!("map projection: {error:?}"))?;
        let descriptors = crate::map_output::descriptors(frontend, &map, &captured.maps)
            .map_err(|error| format!("map descriptors: {error:?}"))?;
        let artifacts = crate::map_artifacts::lower(
            frontend,
            &captured.maps,
            &map,
            &descriptors,
            &symbols,
            &resolver,
            Some(context),
        )?;
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
    })
}
