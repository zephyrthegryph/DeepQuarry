//! Captured map units enter the common anonymous executable artifact boundary.
use crate::debug_sources::{DebugOrigin, DebugOriginCollector, DebugOriginProvider};
use crate::initialization_artifact::{InitializationArtifact, InitializationCoverage};
use crate::{map_initializers, map_output, map_projection};
use dm_ir::{ResolveQuery, ResolvedMeaning, Resolver, SymbolTable};
use dm_tree::{frontend::ColdFrontend, maps::MapPlan};
use std::{cell::RefCell, collections::BTreeMap, sync::Arc};
struct Origins<'a> {
    path: &'a str,
    line_starts: &'a [usize],
    source_length: usize,
    entry: usize,
    collector: RefCell<DebugOriginCollector>,
}
struct DiagnosticResolver<'a, R> {
    host: &'a R,
    unsupported: std::sync::Mutex<Vec<ResolveQuery>>,
}
impl<R: Resolver> Resolver for DiagnosticResolver<'_, R> {
    fn resolve(&self, query: ResolveQuery) -> ResolvedMeaning {
        let result = self.host.resolve(query);
        if matches!(&result, ResolvedMeaning::Unsupported(_)) {
            if let Ok(mut queries) = self.unsupported.lock() {
                if queries.len() < 8 {
                    queries.push(query);
                }
            }
        }
        result
    }
}
fn query_description(query: ResolveQuery, symbols: &SymbolTable) -> String {
    let spelling = |symbol| {
        symbols
            .text(symbol)
            .map(str::to_owned)
            .unwrap_or_else(|| format!("{symbol:?} (spelling unavailable)"))
    };
    match query {
        ResolveQuery::DeclaredVarType { owner, name }
        | ResolveQuery::HasMemberVar { owner, name }
        | ResolveQuery::VarStorage { owner, name } => format!(
            "{query:?}: owner={}, field={}",
            spelling(owner),
            spelling(name)
        ),
        _ => format!("{query:?}"),
    }
}
impl DebugOriginProvider for Origins<'_> {
    fn origin(&self, offset: usize) -> Result<DebugOrigin, String> {
        if offset > self.source_length {
            return Err("map debug source offset exceeds capture".into());
        }
        let line = self.line_starts.partition_point(|start| *start <= offset);
        Ok(DebugOrigin {
            semantic_path: self.path.to_owned(),
            line: u32::try_from(line).map_err(|_| "map debug line overflow")?,
        })
    }
}
impl dm_codegen_byond::DebugSourceProvider for Origins<'_> {
    fn entry_ordinal(&self) -> Result<u32, String> {
        self.ordinal(self.entry)
    }
    fn ordinal(&self, offset: usize) -> Result<u32, String> {
        self.collector.borrow_mut().record(self, offset)
    }
}
/// Identical semantic document/descriptor identities share an executable after
/// exact body comparison. Source/debug binding chooses the first manifest
/// occurrence deterministically, while the map plan retains all source origins.
pub fn lower<R: Resolver>(
    frontend: &ColdFrontend,
    maps: &[MapPlan],
    projection: &map_projection::Projection,
    descriptors: &map_output::DescriptorPlan,
    symbols: &SymbolTable,
    host: &R,
    resource_search_context: Option<u128>,
) -> Result<Vec<InitializationArtifact>, String> {
    let planned = map_initializers::plan(projection, maps, host)
        .map_err(|error| format!("map initializer plan: {error:?}"))?;
    if planned.units.len() != descriptors.initializers.len() {
        return Err("map initializer coverage mismatch".into());
    }
    let lines = maps
        .iter()
        .map(|map| {
            std::iter::once(0)
                .chain(
                    map.captured
                        .source
                        .as_bytes()
                        .iter()
                        .enumerate()
                        .filter_map(|(offset, byte)| (*byte == b'\n').then_some(offset + 1)),
                )
                .collect::<Vec<_>>()
        })
        .collect::<Vec<_>>();
    let mut seen = BTreeMap::new();
    let mut artifacts = Vec::new();
    for (index, unit) in planned.units.iter().enumerate() {
        let Some(unit) = unit else {
            if descriptors.initializers[index].is_some() {
                return Err("map initializer absence mismatch".into());
            }
            continue;
        };
        let identity = descriptors.initializers[index].ok_or("map initializer identity absent")?;
        let body: Arc<[u8]> = unit.canonical_bytes().into();
        if let Some(previous) = seen.get(&identity) {
            if previous != &body {
                return Err("map initializer semantic identity collision".into());
            }
            continue;
        }
        seen.insert(identity, body.clone());
        let atom = projection.instances[index]
            .origin
            .ok_or("map initializer source absent")?;
        let map = maps
            .get(atom.map)
            .ok_or("map initializer source map absent")?;
        let include = frontend
            .plan
            .occurrences
            .get(map.captured.include_occurrence as usize)
            .ok_or("map initializer include occurrence absent")?;
        if include.path != map.captured.path {
            return Err("map initializer source differs from include capture".into());
        }
        let entry = map
            .template_origins
            .get(atom.template)
            .and_then(|template| template.atoms.get(atom.atom))
            .ok_or("map atom source origin absent")?
            .span
            .start;
        let origins = Origins {
            path: &include.semantic_path,
            line_starts: &lines[atom.map],
            source_length: map.captured.source.len(),
            entry,
            collector: RefCell::new(DebugOriginCollector::default()),
        };
        let diagnostics = DiagnosticResolver {
            host,
            unsupported: std::sync::Mutex::new(Vec::new()),
        };
        let code = map_initializers::lower_unit(
            unit,
            maps,
            dm_codegen_byond::initializer::InitializerContext {
                symbols,
                resource_search_context,
                debug: Some(&origins),
            },
            &diagnostics,
        )
        .map_err(|error| {
            let offset = match &error {
                map_initializers::LowerError::Expression { assignment, .. } =>
                    unit.origins.get(*assignment).map(|origin| origin.span.value_span.start).unwrap_or(entry),
                _ => entry,
            };
            let line = lines[atom.map].partition_point(|start| *start <= offset);
            let owner = symbols.text(unit.owner).unwrap_or("<owner spelling unavailable>");
            let queries = diagnostics.unsupported.lock().map(|queries| queries.iter()
                .map(|query| query_description(*query, symbols)).collect::<Vec<_>>().join("; "))
                .unwrap_or_else(|_| "query diagnostic lock poisoned".into());
            format!("{}:{line}: unsupported map initializer for {owner} (include={}, template={}, atom={}): {error:?}; unresolved queries: {queries}",
                include.semantic_path, map.captured.include_occurrence, atom.template, atom.atom)
        })?;
        let artifact = InitializationArtifact {
            identity,
            code,
            debug_origins: origins.collector.into_inner().finish(),
            coverage: InitializationCoverage::MapAssignments {
                count: u32::try_from(unit.assignments.len())
                    .map_err(|_| "map assignment count overflow")?,
                canonical_body: body,
            },
        };
        artifact.validate()?;
        artifacts.push(artifact);
    }
    Ok(artifacts)
}
