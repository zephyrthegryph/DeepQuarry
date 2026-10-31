//! Lazy current source export projection, retaining coordinates/provenance only.
use super::*;
use crate::OccurrenceTable;
use std::sync::{OnceLock, Weak};
#[derive(Clone, PartialEq, Eq)]
struct IncludeCoordinates {
    path: Arc<PathBuf>,
    semantic_path: Arc<str>,
    original_entry: Option<Arc<PathBuf>>,
    parent: Option<usize>,
}
#[derive(Clone, Copy)]
pub(super) struct DeclarationCompatibility {
    pub ordinal: OccurrenceId,
    pub occurrence: Option<usize>,
    pub line: usize,
    pub column: usize,
    pub source_len: usize,
}
/// Policy diagnostic cursor: logical boundary and physical byte point remain
/// distinct. No column is claimed from a macro LINE-only receipt.
pub struct SourceDeclarationPolicyCursor {
    pub path: Arc<PathBuf>,
    pub line: usize,
    pub byte_column: Option<usize>,
    pub logical_boundary: bool,
}
pub struct SourceExportMapping {
    acquisitions: Arc<[Option<dm_preprocess::SourceAcquisitionLease>]>,
    origins: dm_preprocess::regions::ExpandedOriginArena,
    arena: dm_preprocess::WeakSourceText,
    tree: Weak<crate::SemanticTree>,
    revision: OnceLock<u128>,
    regions: Arc<[(usize, usize)]>,
    includes: Arc<[IncludeCoordinates]>,
    by_path: Arc<HashMap<PathBuf, FileId>>,
    files: Weak<[SourceFile]>,
    occurrences: Arc<OccurrenceTable>,
    declaration_cursors: Box<[u32]>,
    declaration_compatibility: Option<Box<[DeclarationCompatibility]>>,
    declaration_qualifiers: Box<[u8]>,
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
    source_location_in(
        file,
        origin,
        path,
        semantic_path,
        encounter,
        occurrence,
        chain,
    )
}
/// `source_location` for a caller that already knows the row's file.
pub(super) fn source_location_in(
    file: FileId,
    origin: ExpandedOriginView<'_>,
    path: &Arc<PathBuf>,
    semantic_path: &Arc<str>,
    encounter: usize,
    occurrence: usize,
    chain: Arc<[usize]>,
) -> Option<SourceLocation> {
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
    pub fn source_acquisition_storage(
        &self,
    ) -> &Arc<[Option<dm_preprocess::SourceAcquisitionLease>]> {
        &self.acquisitions
    }
    pub(super) fn declaration_compatibility_issued(&self) -> bool {
        self.declaration_compatibility.is_some()
    }
    pub(super) fn reissue_unchanged(&self, current: &ColdFrontend) -> Self {
        // Only the native whole-program producer calls this after original
        // acquisition, plan, bytes and exact coordinate equality checks.
        let mut result = Self::capture(
            &current.plan,
            &current.expanded,
            &current.files,
            &current.source_by_path,
            &current.snapshot.occurrences,
            &current.snapshot.tree,
            self.declaration_cursors.clone(),
            self.declaration_qualifiers.clone(),
        );
        if let Some(rows) = &self.declaration_compatibility {
            result.bind_declaration_compatibility(rows.clone());
        }
        result
    }
    pub(super) fn capture(
        plan: &DirectivePlan,
        expanded: &ExpandedRegions,
        files: &Arc<[SourceFile]>,
        by_path: &Arc<HashMap<PathBuf, FileId>>,
        occurrences: &Arc<OccurrenceTable>,
        tree: &Arc<crate::SemanticTree>,
        declaration_cursors: Box<[u32]>,
        declaration_qualifiers: Box<[u8]>,
    ) -> Self {
        assert_eq!(declaration_cursors.len(), occurrences.source_order().len());
        assert_eq!(declaration_qualifiers.len(), declaration_cursors.len());
        let regions: Arc<[(usize, usize)]> = expanded
            .origins
            .byte_layout_regions()
            .cloned()
            .unwrap_or_else(|| {
                plan.regions
                    .iter()
                    .map(|region| (region.occurrence, region.encounter_ordinal))
                    .collect()
            });
        let includes: Arc<[IncludeCoordinates]> = plan
            .occurrences
            .iter()
            .map(|include| IncludeCoordinates {
                path: Arc::clone(&include.path),
                semantic_path: Arc::clone(&include.semantic_path),
                original_entry: include.original_entry_path().cloned(),
                parent: include.parent,
            })
            .collect();
        let mut hash = xxhash_rust::xxh3::Xxh3::new();
        hash.update(b"dm-source-export-coordinates-v3\0");
        hash.update(&declaration_qualifiers);
        for cursor in declaration_cursors.iter() {
            hash.update(&cursor.to_le_bytes());
        }
        for &(occurrence, encounter) in regions.iter() {
            hash.update(&(occurrence as u64).to_le_bytes());
            hash.update(&(encounter as u64).to_le_bytes());
        }
        for include in includes.iter() {
            if let Some(entry)=&include.original_entry{let text=entry.to_string_lossy();hash.update(&(text.len() as u64).to_le_bytes());hash.update(text.as_bytes());}else{hash.update(&u64::MAX.to_le_bytes());}
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
            acquisitions: plan
                .occurrences
                .iter()
                .enumerate()
                .map(|(id, _)| plan.source_acquisitions.get(&id).cloned())
                .collect::<Vec<_>>()
                .into(),
            origins: expanded.origins.clone(),
            arena: expanded.text.downgrade(),
            tree: Arc::downgrade(tree),
            revision: OnceLock::new(),
            regions,
            includes,
            by_path: Arc::clone(by_path),
            files: Arc::downgrade(files),
            occurrences: Arc::clone(occurrences),
            declaration_cursors,
            declaration_compatibility: None,
            declaration_qualifiers,
            locations: OnceLock::new(),
            coordinate_fingerprint: hash.digest128(),
        }
    }
    fn admits(&self, current: &ColdFrontend) -> bool {
        #[cfg(test)]
        FULL_SOURCE_ADMISSIONS.with(|count| count.set(count.get() + 1));
        self.acquisitions.len() == current.plan.occurrences.len()
            && self.acquisitions.iter().enumerate().all(|(id, old)| {
                match (old, current.plan.source_acquisitions.get(&id)) {
                    (None, None) => true,
                    (Some(old), Some(new)) => old.same_binding(new),
                    _ => false,
                }
            })
            && self.origins.same_owner(&current.expanded.origins)
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
                        && old.original_entry.as_ref() == new.original_entry_path()
                })
    }
    /// Borrow only this authenticated mapping's per-occurrence binding. Missing
    /// producer evidence stays None; no synthetic proof from source contents.
    pub fn source_acquisition(
        &self,
        occurrence: usize,
    ) -> Option<&dm_preprocess::SourceAcquisitionLease> {
        self.acquisitions.get(occurrence)?.as_ref()
    }
    /// A join token only; exact current owner/coordinates separately admit capture.
    pub fn coordinate_fingerprint(&self) -> u128 {
        self.coordinate_fingerprint
    }
    /// Current expanded coordinate, using the same issued origin choice as Mapping.
    pub fn output(&self, offset: usize) -> Option<SourceLocation> {
        let index = self
            .origins
            .partition_point(|origin| origin.output_span.end <= offset);
        let origin = self.origins.get(index).or_else(|| self.origins.last())?;
        let (include, encounter) = *self.regions.get(origin.region)?;
        let coordinates = self.includes.get(include)?;
        let mut chain = vec![include];
        let mut cursor = include;
        while let Some(parent) = self.includes.get(cursor)?.parent {
            chain.push(parent);
            cursor = parent;
        }
        chain.reverse();
        source_location(
            origin,
            &coordinates.path,
            &coordinates.semantic_path,
            encounter,
            include,
            chain.into(),
            &self.by_path,
        )
    }
    /// Location of one occurrence without issuing the all-occurrence index:
    /// the first origin of the occurrence's source offset, as `location` picks.
    pub fn location_of(&self, ordinal: OccurrenceId) -> Option<SourceLocation> {
        if let Some(all) = self.locations.get() {
            return all
                .get(ordinal.0 as usize)
                .and_then(Option::as_ref)
                .cloned();
        }
        let provenance = &self.occurrences.get(ordinal)?.provenance;
        let offset = self
            .origins
            .iter()
            .find(|origin| {
                self.regions[origin.region].0 == provenance.include_occurrence as usize
                    && origin.source_span.start == provenance.span.start as usize
            })?
            .output_span
            .start;
        self.output(offset)
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
    hash.update(b"dm-analysis-source-revision-v3\0");
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
    // The origin rows dominate the cost (hundreds of thousands of them, each with a path string). Fixed
    // chunks are digested independently and combined in order, so the value does not depend on how many
    // threads run them.
    let origins = &frontend.expanded.origins;
    let chunk_digest = |range: std::ops::Range<usize>| -> u128 {
        let mut hash = Xxh3::new();
        let mut traces = HashMap::new();
        for index in range {
            let Some(origin) = origins.get(index) else {
                break;
            };
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
    };
    const CHUNK: usize = 16 * 1024;
    let chunks = origins.len().div_ceil(CHUNK);
    let threads = std::thread::available_parallelism()
        .map_or(1, |n| n.get())
        .min(8)
        .min(chunks.max(1));
    let next = std::sync::atomic::AtomicUsize::new(0);
    let digests = std::sync::Mutex::new(vec![0u128; chunks]);
    std::thread::scope(|scope| {
        for _ in 0..threads {
            scope.spawn(|| loop {
                let chunk = next.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
                if chunk >= chunks {
                    break;
                }
                let digest = chunk_digest(chunk * CHUNK..((chunk + 1) * CHUNK).min(origins.len()));
                digests.lock().unwrap_or_else(|e| e.into_inner())[chunk] = digest;
            });
        }
    });
    for digest in digests.into_inner().unwrap_or_else(|e| e.into_inner()) {
        hash.update(&digest.to_le_bytes());
    }
    hash.digest128()
}

// Scalar original-coordinate notes from compiler-issued compact layout evidence.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct SourceNoteOrigin {
    pub path: Arc<PathBuf>,
    pub line: usize,
    pub byte_column: usize,
}
impl SourceExportMapping {
    /// Borrow the issued include/lease roster without allocating a second list.
    /// Missing acquisition evidence remains visible, including empty DME inputs.
    pub fn source_acquisitions(
        &self,
    ) -> impl Iterator<Item = (&Path, Option<&dm_preprocess::SourceAcquisitionLease>)> {
        self.includes
            .iter()
            .enumerate()
            .map(move |(index, include)| {
                (
                    include.path.as_path(),
                    self.acquisitions.get(index).and_then(Option::as_ref),
                )
            })
    }
    pub fn original_note_origin(&self, offset: usize) -> Result<SourceNoteOrigin, String> {
        let index = self
            .origins
            .partition_point(|origin| origin.output_span.end <= offset);
        let origin = self
            .origins
            .get(index)
            .ok_or("note has no native expanded origin")?;
        let (include, _) = *self
            .regions
            .get(origin.region)
            .ok_or("note region unavailable")?;
        let acquired = self
            .source_acquisition(include)
            .ok_or("note original acquisition unavailable")?;
        let cursor = self
            .origins
            .original_byte_cursor(index, include, acquired, offset)
            .map_err(str::to_owned)?;
        let coordinates = self
            .includes
            .get(include)
            .ok_or("note include coordinates unavailable")?;
        Ok(SourceNoteOrigin {
            path: Arc::clone(&coordinates.path),
            line: cursor.line,
            byte_column: cursor.byte_column,
        })
    }
    /// Genuine checker token provenance, including native-issued macro invocation points.
    pub fn source_note_point(&self,offset:usize)->Result<SourceNoteOrigin,String>{self.borrowed_source_note_point(offset).map(BorrowedSourceNoteOrigin::into_owned).map_err(str::to_owned)}
    pub fn borrowed_source_note_point(&self,offset:usize)->Result<BorrowedSourceNoteOrigin<'_>,&'static str>{
        let point=original_note_point_in(&self.origins,offset,|region|{
            let(include,_)=*self.regions.get(region).ok_or("note region unavailable")?;
            let acquired=self.source_acquisition(include).ok_or("note original acquisition unavailable")?;
            Ok((include,acquired))
        },|include|Ok(&self.includes.get(include).ok_or("note include coordinates unavailable")?.path))?;
        Ok(BorrowedSourceNoteOrigin{path:point.path,registration:self.registered_checker_path(point.include)?,line:point.line,byte_column:point.byte_column})
    }
}

/// Intentionally has NO column: only the producer proved physical policy line.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct SourcePolicyLineOrigin {
    pub path: Arc<PathBuf>,
    pub line: usize,
}
impl SourceExportMapping {
    pub fn original_policy_line(&self, offset: usize) -> Result<SourcePolicyLineOrigin, String> {
        if let Ok(origin) = self.original_note_origin(offset) {
            return Ok(SourcePolicyLineOrigin {
                path: origin.path,
                line: origin.line,
            });
        }
        let index = self
            .origins
            .partition_point(|origin| origin.output_span.end <= offset);
        let origin = self
            .origins
            .get(index)
            .ok_or("policy point has no native expanded origin")?;
        let (include, _) = *self
            .regions
            .get(origin.region)
            .ok_or("policy point region unavailable")?;
        let lease = self
            .source_acquisition(include)
            .ok_or("policy point acquisition unavailable")?;
        let line = self
            .origins
            .original_policy_line(index, include, lease, offset)
            .map_err(str::to_owned)?;
        let coordinates = self
            .includes
            .get(include)
            .ok_or("policy point include coordinates unavailable")?;
        Ok(SourcePolicyLineOrigin {
            path: Arc::clone(&coordinates.path),
            line,
        })
    }
}

impl SourceExportMapping {
    pub fn declaration_anchor_storage(&self) -> (usize, usize, usize) {
        (
            self.declaration_cursors.as_ptr() as usize,
            self.declaration_cursors.len(),
            std::mem::size_of_val(self.declaration_cursors.as_ref()),
        )
    }
    pub fn declaration_qualifier_storage(&self) -> (usize, usize, usize) {
        (
            self.declaration_qualifiers.as_ptr() as usize,
            self.declaration_qualifiers.len(),
            self.declaration_qualifiers.len(),
        )
    }
    pub fn declaration_checker_qualifiers(&self, ordinal: OccurrenceId) -> Result<u8, String> {
        // Same bound occurrence/cursor check; macro LINE proof supplies no flag authority.
        self.declaration_policy_cursor(ordinal)?;
        let flags = *self
            .declaration_qualifiers
            .get(ordinal.0 as usize)
            .ok_or("declaration qualifier roster unavailable")?;
        if flags == dm_syntax::UNKNOWN_HEADER_QUALIFIERS
            || flags & !dm_syntax::CHECKER_VAR_MASK != 0
        {
            return Err("original primary declaration qualifier context was not issued".into());
        }
        Ok(flags)
    }
    pub(super) fn initializer_declaration_cursor(
        &self,
        ordinal: OccurrenceId,
    ) -> Result<usize, String> {
        self.declaration_policy_cursor(ordinal)
    }
    pub(super) fn primary_declaration_cursors(
        &self,
    ) -> impl Iterator<Item = (OccurrenceId, usize)> + '_ {
        self.declaration_cursors
            .iter()
            .enumerate()
            .filter_map(|(ordinal, &cursor)| {
                (cursor != u32::MAX).then_some((OccurrenceId(ordinal as u32), cursor as usize))
            })
    }
    pub(super) fn bind_declaration_compatibility(&mut self, rows: Box<[DeclarationCompatibility]>) {
        assert!(
            self.revision.get().is_none(),
            "compatibility facts must precede publication"
        );
        let mut hash = xxhash_rust::xxh3::Xxh3::new();
        hash.update(&self.coordinate_fingerprint.to_le_bytes());
        hash.update(b"native-declaration-policy-continuation-v1");
        for row in rows.iter() {
            hash.update(&row.ordinal.0.to_le_bytes());
            for value in [
                row.occurrence.unwrap_or(usize::MAX),
                row.line,
                row.column,
                row.source_len,
            ] {
                hash.update(&(value as u64).to_le_bytes());
            }
        }
        self.coordinate_fingerprint = hash.digest128();
        self.declaration_compatibility = Some(rows);
    }
    pub fn declaration_compatibility_storage(&self) -> (usize, usize) {
        self.declaration_compatibility
            .as_ref()
            .map_or((0, 0), |rows| {
                (rows.as_ptr() as usize, std::mem::size_of_val(rows.as_ref()))
            })
    }
    pub fn declaration_policy_compatibility_cursor(
        &self,
        ordinal: OccurrenceId,
    ) -> Result<SourceDeclarationPolicyCursor, String> {
        let rows = self
            .declaration_compatibility
            .as_ref()
            .ok_or("declaration compatibility producer was not requested")?;
        if let Ok(index) = rows.binary_search_by_key(&ordinal.0, |row| row.ordinal.0) {
            let row = rows[index];
            let occurrence = row
                .occurrence
                .ok_or("declaration continuation has no issued compatibility cursor")?;
            let include = self
                .includes
                .get(occurrence)
                .ok_or("compatibility include absent")?;
            let acquired = self
                .source_acquisition(occurrence)
                .ok_or("compatibility acquisition absent")?;
            if acquired.source_text().len() != row.source_len {
                return Err("compatibility acquisition differs".into());
            }
            return Ok(SourceDeclarationPolicyCursor {
                path: Arc::clone(&include.path),
                line: row.line,
                byte_column: Some(row.column),
                logical_boundary: true,
            });
        }
        match self.declaration_policy_point(ordinal) {
            Ok(point) => Ok(SourceDeclarationPolicyCursor {
                path: point.path,
                line: point.line,
                byte_column: Some(point.byte_column),
                logical_boundary: false,
            }),
            Err(_) => {
                self.declaration_policy_line(ordinal)
                    .map(|line| SourceDeclarationPolicyCursor {
                        path: line.path,
                        line: line.line,
                        byte_column: None,
                        logical_boundary: false,
                    })
            }
        }
    }
    fn declaration_policy_cursor(&self, ordinal: OccurrenceId) -> Result<usize, String> {
        let occurrence = self
            .occurrences
            .get(ordinal)
            .ok_or("declaration occurrence unavailable")?;
        let cursor = *self
            .declaration_cursors
            .get(ordinal.0 as usize)
            .ok_or("declaration token roster unavailable")?;
        if cursor == u32::MAX {
            return Err("original primary declaration token was not issued".into());
        }
        let source = self
            .output(cursor as usize)
            .ok_or("declaration token origin unavailable")?;
        if source.span.file != occurrence.provenance.span.file
            || source.include_occurrence != occurrence.provenance.include_occurrence as usize
        {
            return Err("declaration token belongs to another issued occurrence".into());
        }
        Ok(cursor as usize)
    }
    pub fn declaration_policy_line(
        &self,
        ordinal: OccurrenceId,
    ) -> Result<SourcePolicyLineOrigin, String> {
        self.original_policy_line(self.declaration_policy_cursor(ordinal)?)
    }
    /// Same primary cursor/occurrence proof as the line API, but requires an
    /// actual byte point. A LINE-only macro receipt must NEVER invent a column.
    pub fn declaration_primary_policy_span(
        &self,
        ordinal: OccurrenceId,
    ) -> Result<dm_syntax::Span, String> {
        let at = self.declaration_policy_cursor(ordinal)?;
        Ok(dm_syntax::Span::new(at, at))
    }
    pub fn declaration_policy_point(
        &self,
        ordinal: OccurrenceId,
    ) -> Result<SourceNoteOrigin, String> {
        self.original_note_origin(self.declaration_policy_cursor(ordinal)?)
    }
}

impl SourceExportMapping {
    pub fn declaration_source_note_point(
        &self,
        ordinal: OccurrenceId,
    ) -> Result<SourceNoteOrigin, String> {
        self.source_note_point(self.declaration_policy_cursor(ordinal)?)
    }
}

#[cfg(test)]
thread_local! {static FULL_SOURCE_ADMISSIONS:std::cell::Cell<usize>=const{std::cell::Cell::new(0)};}
#[cfg(test)]
pub(super) fn reset_full_source_admissions_for_test() {
    FULL_SOURCE_ADMISSIONS.with(|count| count.set(0));
}
#[cfg(test)]
pub(super) fn full_source_admissions_for_test() -> usize {
    FULL_SOURCE_ADMISSIONS.with(|count| count.get())
}

/// Same source-note projection borrowed before any path-owner clone. This is
/// coordinate data, not a source/cache admission capability.
#[derive(Clone,Copy)]pub struct BorrowedSourceNoteOrigin<'a>{path:&'a Arc<PathBuf>,registration:&'a Path,line:usize,byte_column:usize}
impl BorrowedSourceNoteOrigin<'_>{
 /// Exact original FileList registration key plus its reported source point.
 /// Physical acquisition identity alone is not reported-file identity.
 pub fn same_reported_point(&self,other:&BorrowedSourceNoteOrigin<'_>)->bool{self.registration==other.registration&&self.line==other.line&&self.byte_column==other.byte_column}

 /// Borrowed original reported-file key and byte point; no registration is minted.
 pub fn reported_coordinates(&self)->(&Path,usize,usize){(self.registration,self.line,self.byte_column)}
 pub fn retained_charge(&self)->Option<usize>{std::mem::size_of::<SourceNoteOrigin>().checked_add(std::mem::size_of::<PathBuf>())?.checked_add(self.path.capacity())?.checked_add(2*std::mem::size_of::<usize>())}
 pub fn into_owned(self)->SourceNoteOrigin{SourceNoteOrigin{path:Arc::clone(self.path),line:self.line,byte_column:self.byte_column}}
}

impl SourceExportMapping{
 fn registered_checker_path(&self,include:usize)->Result<&Path,&'static str>{
  let row=self.includes.get(include).ok_or("checker registered include absent")?;
  if row.parent.is_none(){return row.original_entry.as_deref().map(PathBuf::as_path).ok_or("original checker entry argument unissued")}
  let root=self.includes.first().and_then(|row|row.original_entry.as_deref()).ok_or("original checker entry argument unissued")?;
  let semantic=Path::new(row.semantic_path.as_ref());
  let environment=root.parent().unwrap_or(Path::new(""));
  Ok(if semantic.is_absolute(){semantic.strip_prefix(environment).unwrap_or(semantic)}else if environment.components().next().is_some(){
   // Original prepare_include_file joins under this nonempty environment,
   // then strip_prefix consumes that parent. std::Path's remaining component
   // view drops leading CurDir components at that boundary. Borrow that same
   // view; never canonicalize ParentDir or clone a reported registry key.
   semantic.strip_prefix(Path::new(".")).unwrap_or(semantic)
  }else{semantic})
 }
 pub fn original_checker_entry_storage(&self,mut visit:impl FnMut(usize,usize)){for row in self.includes.iter(){if let Some(entry)=&row.original_entry{visit(Arc::as_ptr(entry)as usize,std::mem::size_of::<PathBuf>());visit(entry.as_os_str().as_encoded_bytes().as_ptr()as usize,entry.capacity());}}}
}

/// Operation-local legacy FileList numbering over the SAME issued include
/// coordinates. This is diagnostic location DATA, never parser/runtime proof.
/// Borrowing prevents rebinding the map; no source text or AST is retained.
pub struct OriginalCheckerSourceRegistry<'source>{
 mapping:&'source SourceExportMapping,
 files:Vec<u16>,
 // LAST: physical row allocation is freed before its syntax-family credit.
 _lease:dm_syntax::SettingRootLease,
}
#[derive(Clone,Copy,Debug,Eq,PartialEq)]
pub struct OriginalCheckerLocation{pub file:u16,pub line:u32,pub byte_column:u16}
impl SourceExportMapping{
 pub fn original_checker_source_registry<'source>(&'source self,a:&dm_syntax::SettingAdmission<'_>)->std::io::Result<OriginalCheckerSourceRegistry<'source>>{
  fn denied(a:&dm_syntax::SettingAdmission<'_>,kind:std::io::ErrorKind,message:&'static str)->std::io::Error{a.record_operational_error(std::io::Error::new(kind,message));kind.into()}
  let pending=(||{
   a.checkpoint()?;
   // A BTree first node can contain unused entry slots. Reserve a complete
   // conservative node envelope per borrowed key BEFORE its first insertion.
   let count=self.includes.len();let rows=count.checked_mul(4).and_then(|n|n.checked_mul(std::mem::size_of::<u16>()));
   let bytes=rows.and_then(|n|n.checked_add(count.checked_mul(1024+std::mem::size_of::<(&Path,u16)>())?)).and_then(|n|n.checked_add(std::mem::size_of::<OriginalCheckerSourceRegistry<'_>>()+std::mem::size_of::<std::collections::BTreeMap<&Path,u16>>()));
   let lease=a.reserve(bytes.ok_or_else(||denied(a,std::io::ErrorKind::OutOfMemory,"original checker file registry size overflow"))?)?;
   let mut files=Vec::new();files.try_reserve_exact(count).map_err(|_|denied(a,std::io::ErrorKind::OutOfMemory,"original checker file registry allocation refused"))?;
   if files.capacity()>count.saturating_mul(4){return Err(denied(a,std::io::ErrorKind::OutOfMemory,"original checker file registry exposed excess capacity"))}
   let mut registered=std::collections::BTreeMap::<&Path,u16>::new();
   for (ordinal,row) in self.includes.iter().enumerate(){
    a.checkpoint()?;
    // Old preprocessor records maps/skins/scripts separately; it registers
    // ONLY actual DM/DME lexer files. Root entry is registered unconditionally.
    if row.parent.is_some()&&!matches!(Path::new(row.semantic_path.as_ref()).extension().and_then(|s|s.to_str()),Some("dm"|"dme")){files.push(0);continue}
    let key=self.registered_checker_path(ordinal).map_err(|message|denied(a,std::io::ErrorKind::InvalidInput,message))?;
    let id=if let Some(id)=registered.get(key){*id}else{let next=registered.len().checked_add(1).and_then(|n|u16::try_from(n).ok()).filter(|id|*id!=0).ok_or_else(||denied(a,std::io::ErrorKind::InvalidInput,"original checker FileId space exhausted"))?;registered.insert(key,next);next};files.push(id);
   }
   drop(registered);a.checkpoint()?;
   Ok(OriginalCheckerSourceRegistry{mapping:self,files,_lease:lease})
  })();
  if let Some(actual)=a.take_operational_error(){return Err(actual)}pending
 }
}
impl OriginalCheckerSourceRegistry<'_>{
 pub fn registrations(&self)->impl Iterator<Item=(usize,&Path,u16)>+'_ {self.files.iter().enumerate().filter_map(|(ordinal,&id)|{if id==0{None}else{self.mapping.registered_checker_path(ordinal).ok().map(|key|(ordinal,key,id))}})}
 pub fn matches_mapping(&self,mapping:&SourceExportMapping)->bool{std::ptr::eq(self.mapping,mapping)}
 pub fn location(&self,offset:usize)->Result<OriginalCheckerLocation,&'static str>{
  let index=self.mapping.origins.partition_point(|origin|origin.output_span.end<=offset);
  let origin=self.mapping.origins.get(index).or_else(||self.mapping.origins.last()).ok_or("original checker source origin absent")?;
  let(include,_)=*self.mapping.regions.get(origin.region).ok_or("original checker include coordinate absent")?;
  let file=*self.files.get(include).filter(|id|**id!=0).ok_or("original checker source is not a registered DM file")?;
  let point=self.mapping.borrowed_source_note_point(offset)?;
  Ok(OriginalCheckerLocation{file,line:u32::try_from(point.line).map_err(|_|"original checker source line overflow")?,byte_column:u16::try_from(point.byte_column).map_err(|_|"original checker source column overflow")?})
 }
 pub fn visit_storage(&self,mut visit:impl FnMut(usize,usize)){visit(self.files.as_ptr()as usize,self.files.capacity()*std::mem::size_of::<u16>());self._lease.visit_counter_storage(visit);}
}

/// SAME original token/macro source-note projection, parameterized only by the
/// actual owner's borrowed include/acquisition coordinates. No receipt minted.
pub(super) struct OriginalNotePoint<'a>{pub include:usize,pub path:&'a Arc<PathBuf>,pub line:usize,pub byte_column:usize}
pub(super) fn original_note_point_in<'a>(
    origins:&dm_preprocess::regions::ExpandedOriginArena,offset:usize,
    acquisition:impl FnOnce(usize)->Result<(usize,&'a dm_preprocess::SourceAcquisitionLease),&'static str>,
    path:impl FnOnce(usize)->Result<&'a Arc<PathBuf>,&'static str>,
)->Result<OriginalNotePoint<'a>,&'static str>{
    let index=origins.partition_point(|origin|origin.output_span.end<=offset);
    let origin=origins.get(index).ok_or("note has no native expanded origin")?;
    let(include,acquired)=acquisition(origin.region)?;
    let cursor=origins.source_note_cursor(index,include,acquired,offset)?;
    let path=path(include)?;
    Ok(OriginalNotePoint{include,path,line:cursor.line,byte_column:cursor.byte_column})
}
