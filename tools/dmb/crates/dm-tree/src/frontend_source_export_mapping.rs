//! Lazy current source export projection, retaining coordinates/provenance only.
use super::*;
use crate::OccurrenceTable;
use std::sync::{OnceLock, Weak};
#[derive(Clone, PartialEq, Eq)]
struct IncludeCoordinates {
    path: Arc<PathBuf>,
    semantic_path: Arc<str>,
    parent: Option<usize>,
}
pub struct SourceExportMapping {
    origins: dm_preprocess::regions::ExpandedOriginArena,
    arena: dm_preprocess::WeakSourceText,
    tree: Weak<crate::SemanticTree>,
    revision: OnceLock<u128>,
    regions: Arc<[(usize, usize)]>,
    includes: Arc<[IncludeCoordinates]>,
    by_path: Arc<HashMap<PathBuf, FileId>>,
    files: Weak<[SourceFile]>,
    occurrences: Arc<OccurrenceTable>,
    locations: OnceLock<Arc<[Option<SourceLocation>]>>,
    coordinate_fingerprint: u128,
}
impl std::fmt::Debug for SourceExportMapping {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("SourceExportMapping")
            .field("regions", &self.regions.len())
            .field("includes", &self.includes.len())
            .field("locations_issued", &self.locations.get().is_some())
            .finish()
    }
}

impl ColdFrontend {
    /// Capture the join digest once beside the exact current mapping owner.
    pub fn source_export_revision(&self) -> u128 {
        if let Some(mapping) = self.source_export_mapping() {
            *mapping.revision.get_or_init(|| source_revision(self))
        } else {
            source_revision(self)
        }
    }
    /// Exact current producer inputs; public compatibility mutations decline.
    pub fn source_export_mapping(&self) -> Option<&Arc<SourceExportMapping>> {
        self.source_export_mapping
            .admits(self)
            .then_some(&self.source_export_mapping)
    }
}
pub(super) fn source_location(
    origin: ExpandedOriginView<'_>,
    path: &Arc<PathBuf>,
    semantic_path: &Arc<str>,
    encounter: usize,
    occurrence: usize,
    chain: Arc<[usize]>,
    by_path: &HashMap<PathBuf, FileId>,
) -> Option<SourceLocation> {
    let file = *by_path.get(origin.origin.path.as_ref())?;
    Some(SourceLocation {
        span: source_span(file, origin.source_span).ok()?,
        path: Arc::clone(path),
        semantic_path: Arc::clone(semantic_path),
        line: origin.origin.source_line,
        encounter_ordinal: encounter,
        include_occurrence: occurrence,
        include_chain: chain,
        macro_expansions: Arc::clone(origin.macro_expansions),
    })
}
impl SourceExportMapping {
    pub(super) fn capture(
        plan: &DirectivePlan,
        expanded: &ExpandedRegions,
        files: &Arc<[SourceFile]>,
        by_path: &Arc<HashMap<PathBuf, FileId>>,
        occurrences: &Arc<OccurrenceTable>,
        tree: &Arc<crate::SemanticTree>,
    ) -> Self {
        let regions: Arc<[(usize, usize)]> = plan
            .regions
            .iter()
            .map(|region| (region.occurrence, region.encounter_ordinal))
            .collect();
        let includes: Arc<[IncludeCoordinates]> = plan
            .occurrences
            .iter()
            .map(|include| IncludeCoordinates {
                path: Arc::clone(&include.path),
                semantic_path: Arc::clone(&include.semantic_path),
                parent: include.parent,
            })
            .collect();
        let mut hash = xxhash_rust::xxh3::Xxh3::new();
        hash.update(b"dm-source-export-coordinates-v1\0");
        for &(occurrence, encounter) in regions.iter() {
            hash.update(&(occurrence as u64).to_le_bytes());
            hash.update(&(encounter as u64).to_le_bytes());
        }
        for include in includes.iter() {
            let path = include.path.to_string_lossy();
            for value in [path.as_bytes(), include.semantic_path.as_bytes()] {
                hash.update(&(value.len() as u64).to_le_bytes());
                hash.update(value);
            }
            hash.update(
                &include
                    .parent
                    .map(|parent| parent as u64)
                    .unwrap_or(u64::MAX)
                    .to_le_bytes(),
            );
        }
        Self {
            origins: expanded.origins.clone(),
            arena: expanded.text.downgrade(),
            tree: Arc::downgrade(tree),
            revision: OnceLock::new(),
            regions,
            includes,
            by_path: Arc::clone(by_path),
            files: Arc::downgrade(files),
            occurrences: Arc::clone(occurrences),
            locations: OnceLock::new(),
            coordinate_fingerprint: hash.digest128(),
        }
    }
    fn admits(&self, current: &ColdFrontend) -> bool {
        self.origins.same_owner(&current.expanded.origins)
            && self
                .arena
                .upgrade()
                .is_some_and(|arena| arena.same_view(&current.expanded.text))
            && Weak::ptr_eq(&self.tree, &Arc::downgrade(&current.snapshot.tree))
            && Weak::ptr_eq(&self.files, &Arc::downgrade(&current.files))
            && Arc::ptr_eq(&self.by_path, &current.source_by_path)
            && Arc::ptr_eq(&self.occurrences, &current.snapshot.occurrences)
            && self.regions.len() == current.plan.regions.len()
            && self.regions.iter().zip(&current.plan.regions).all(
                |(&(occurrence, encounter), region)| {
                    occurrence == region.occurrence && encounter == region.encounter_ordinal
                },
            )
            && self.includes.len() == current.plan.occurrences.len()
            && self
                .includes
                .iter()
                .zip(&current.plan.occurrences)
                .all(|(old, new)| {
                    old.path == new.path
                        && old.semantic_path == new.semantic_path
                        && old.parent == new.parent
                })
    }
    /// A join token only; exact current owner/coordinates separately admit capture.
    pub fn coordinate_fingerprint(&self) -> u128 {
        self.coordinate_fingerprint
    }
    pub fn location(&self, ordinal: OccurrenceId) -> Option<&SourceLocation> {
        self.locations
            .get_or_init(|| {
                // Preserve the full export's FIRST matching expanded location. This
                // transient index exists only on first provenance query, not builds.
                let mut offsets = HashMap::new();
                for origin in self.origins.iter() {
                    let include = self.regions[origin.region].0;
                    offsets
                        .entry((include, origin.source_span.start))
                        .or_insert(origin.output_span.start);
                }
                let mut chains = HashMap::new();
                self.occurrences
                    .source_order()
                    .iter()
                    .map(|occurrence| {
                        let provenance = &occurrence.provenance;
                        let offset = *offsets.get(&(
                            provenance.include_occurrence as usize,
                            provenance.span.start as usize,
                        ))?;
                        let index = self
                            .origins
                            .partition_point(|origin| origin.output_span.end <= offset);
                        let origin = self.origins.get(index).or_else(|| self.origins.last())?;
                        let (include, encounter) = self.regions[origin.region];
                        let coordinates = &self.includes[include];
                        let chain = chains
                            .entry(include)
                            .or_insert_with(|| {
                                let mut chain = vec![include];
                                let mut cursor = include;
                                while let Some(parent) = self.includes[cursor].parent {
                                    chain.push(parent);
                                    cursor = parent;
                                }
                                chain.reverse();
                                Arc::<[usize]>::from(chain)
                            })
                            .clone();
                        source_location(
                            origin,
                            &coordinates.path,
                            &coordinates.semantic_path,
                            encounter,
                            include,
                            chain,
                            &self.by_path,
                        )
                    })
                    .collect()
            })
            .get(ordinal.0 as usize)
            .and_then(Option::as_ref)
    }
    pub fn locations_if_issued(&self) -> Option<&Arc<[Option<SourceLocation>]>> {
        self.locations.get()
    }
    pub fn origin_storage(&self, visit: impl FnMut(usize, usize, usize)) {
        self.origins.visit_storage(visit);
    }
    pub fn coordinate_counts(&self) -> (usize, usize, usize) {
        (
            self.regions.len(),
            self.includes.len(),
            self.locations.get().map_or(0, |locations| locations.len()),
        )
    }
    pub fn coordinate_storage(&self) -> (usize, usize, usize, usize) {
        (
            self.regions.as_ptr() as usize,
            self.regions.len() * std::mem::size_of::<(usize, usize)>(),
            self.includes.as_ptr() as usize,
            self.includes.len() * std::mem::size_of::<IncludeCoordinates>(),
        )
    }
}

#[cfg(test)]
#[path = "frontend_source_export_mapping_tests.rs"]
mod tests;

// Versioned source join token; exact owner admission above is the authority.
fn source_revision(frontend: &ColdFrontend) -> u128 {
    use xxhash_rust::xxh3::Xxh3;
    let mut hash = Xxh3::new();
    hash.update(b"dm-analysis-source-revision-v2\0");
    if let Some(mapping) = frontend.source_export_mapping() {
        hash.update(&mapping.coordinate_fingerprint().to_le_bytes());
    }
    hash.update(&frontend.snapshot.tree.identity().to_le_bytes());
    for file in frontend.files.iter() {
        let path = file.path.to_string_lossy();
        hash.update(&(path.len() as u64).to_le_bytes());
        hash.update(path.as_bytes());
        hash.update(&[u8::from(file.captured)]);
        hash.update(
            &file
                .text
                .span_fingerprint(0..file.text.len())
                .expect("whole source range")
                .to_le_bytes(),
        );
    }
    hash.update(
        &frontend
            .expanded
            .text
            .span_fingerprint(0..frontend.expanded.text.len())
            .expect("whole expanded range")
            .to_le_bytes(),
    );
    let mut traces = HashMap::new();
    for origin in frontend.expanded.origins.iter() {
        let trace = traces
            .entry(std::sync::Arc::as_ptr(origin.macro_expansions) as usize)
            .or_insert_with(|| {
                let mut trace = Xxh3::new();
                for expansion in origin.macro_expansions.iter() {
                    let update = |hash: &mut Xxh3, value: &[u8]| {
                        hash.update(&(value.len() as u64).to_le_bytes());
                        hash.update(value);
                    };
                    update(&mut trace, expansion.name.as_bytes());
                    trace.update(&(expansion.invocation_span.start as u64).to_le_bytes());
                    trace.update(&(expansion.invocation_span.end as u64).to_le_bytes());
                    trace.update(&(expansion.replacement_chain.len() as u64).to_le_bytes());
                    for name in expansion.replacement_chain.iter() {
                        update(&mut trace, name.as_bytes());
                    }
                    trace.update(&[u8::from(expansion.definition.is_some())]);
                    if let Some(definition) = &expansion.definition {
                        update(&mut trace, definition.path.to_string_lossy().as_bytes());
                        for value in [
                            definition.source_span.start,
                            definition.source_span.end,
                            definition.source_line,
                        ] {
                            trace.update(&(value as u64).to_le_bytes());
                        }
                    }
                }
                trace.digest128()
            });
        hash.update(&trace.to_le_bytes());
        let path = origin.origin.path.to_string_lossy();
        hash.update(&(path.len() as u64).to_le_bytes());
        hash.update(path.as_bytes());
        for value in [
            origin.output_span.start,
            origin.output_span.end,
            origin.source_span.start,
            origin.source_span.end,
            origin.region,
            origin.origin.source_line,
        ] {
            hash.update(&(value as u64).to_le_bytes());
        }
    }
    hash.digest128()
}
