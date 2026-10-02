//! Content-addressed structural syntax and procedure outlines.
//!
//! Source chunks retain the parser's declaration boundaries. Salsa owns their
//! immutable syntax identities; changed bodies create only changed chunk inputs.
//! Disk shards share syntax across CLI processes and worktrees.
use crate::bootstrap::{outline_descriptors, OutlineDescriptor};
use crate::incremental::{ProcedureSource, SourceOutline};
use dm_preprocess::PreprocessedProject;
use dm_syntax::{AstFile, Item, ItemKind, Span};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::collections::{BTreeMap, HashMap};
use std::fs;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;

#[path = "frontend_layout.rs"]
mod layout;
#[path = "frontend_segmented.rs"]
mod segmented;
#[cfg(test)]
#[path = "frontend_layout_tests.rs"]
mod layout_tests;

const CHUNK_TARGET: usize = 32 * 1024;
// Includes expanded source and the complete structural chunk layout.
const MAX_CACHE_BYTES: usize = 128 * 1024 * 1024;
const MAX_SHARD_BYTES: u64 = 8 * 1024 * 1024;
static TEMP_SEQUENCE: AtomicU64 = AtomicU64::new(0);

#[derive(Clone, Copy, Default, Debug)]
pub struct OutlineStats {
    pub chunks: usize,
    pub memory_hits: usize,
    pub disk_hits: usize,
    pub parsed_chunks: usize,
    pub scanned_procedures: usize,
    /// Bytes visited by lexical boundary scans (not prefix/suffix comparison).
    pub boundary_scanned_bytes: usize,
}

#[salsa::input]
struct ChunkInput {
    #[returns(ref)]
    text: Arc<str>,
    #[returns(ref)]
    cache_root: Option<PathBuf>,
    #[returns(ref)]
    digest: String,
}

struct Fragment {
    descriptor: OutlineDescriptor,
    source: Option<Arc<str>>,
    digest: String,
    locally_patchable: bool,
}

struct ParsedChunk {
    source_len: usize,
    digest: String,
    ast: Arc<AstFile>,
    fragments: Vec<Fragment>,
    resources: Vec<Span>,
    disk_hit: bool,
    resident_bytes: usize,
}

#[salsa::tracked(no_eq)]
fn parse_chunk(db: &dyn crate::Db, input: ChunkInput) -> Result<Arc<ParsedChunk>, String> {
    parse_fragment(input.text(db), input.digest(db), input.cache_root(db).as_deref())
}

fn parse_fragment(source: &str, digest: &str, cache_root: Option<&Path>) -> Result<Arc<ParsedChunk>, String> {
    let disk = cache_root.and_then(|root| read_shard(root, digest, source.len()).ok().flatten());
    let disk = disk.and_then(|mut stored| {
        if !valid_descriptors(source, &stored.descriptors)
            || !valid_resource_spans(source, &stored.resources)
        {
            return None;
        }
        stored
            .ast()
            .ok()
            .filter(|ast| valid_ast(source, &ast.items))
            .map(|ast| (ast, stored.descriptors, stored.resources, stored.fragments))
    });
    let disk_hit = disk.is_some();
    let (ast, descriptors, resources, stored_fragments, sensitive_offsets) = if let Some(stored) = disk {
        (stored.0,stored.1,stored.2,stored.3,Vec::new())
    } else {
        let (ast,sensitive_offsets) = crate::bootstrap::declaration_snapshot_fragment(source)?;
        let descriptors = outline_descriptors(&ast)?;
        let mut resources = Vec::new();
        crate::bootstrap::resource_scan::visit_resources(source, &mut |literal| {
            let start = literal.as_ptr() as usize - source.as_ptr() as usize;
            resources.push([start, start + literal.len()]);
        });
        (ast, descriptors, resources, Vec::new(),sensitive_offsets)
    };
    let mut previous = 0;
    let mut fragments = Vec::with_capacity(descriptors.len());
    for (index, descriptor) in descriptors.iter().cloned().enumerate() {
        if descriptor.start < previous
            || descriptor.start > descriptor.header_end
            || descriptor.header_end > descriptor.end
            || descriptor.end > source.len()
            || !source.is_char_boundary(descriptor.start)
            || !source.is_char_boundary(descriptor.header_end)
            || !source.is_char_boundary(descriptor.end)
        {
            return Err("invalid cached procedure boundary".into());
        }
        let raw = &source[descriptor.start..descriptor.end];
        let cached = stored_fragments.get(index);
        let locally_patchable = cached.map_or_else(|| {
            let first=sensitive_offsets.partition_point(|offset|*offset<descriptor.start);
            descriptor.safe_signature && !sensitive_offsets.get(first).is_some_and(|offset|*offset<descriptor.end)
        }, |cached| cached.locally_patchable);
        fragments.push(Fragment {
            source: None,
            digest: cached.map_or_else(|| crate::incremental::digest(raw.as_bytes()), |cached| cached.digest.clone()),
            locally_patchable,
            descriptor,
        });
        previous = fragments.last().unwrap().descriptor.end;
    }
    if !disk_hit {
        if let Some(root) = cache_root {
            let _ = write_shard(root, digest, source.len(), &ast, &descriptors, &resources, &fragments);
        }
    }
    let resources: Vec<Span> = resources
        .into_iter()
        .map(|[start, end]| Span::new(start, end))
        .collect();
    let ast_bytes = item_bytes(&ast.items);
    let resident_bytes = ast_bytes
        + resources.capacity() * std::mem::size_of::<Span>()
        + fragments
            .iter()
            .map(|fragment| {
                fragment.source.as_ref().map_or(0, |source| source.len())
                    + fragment.descriptor.path.len()
                    + fragment.digest.len()
                    + 192
            })
            .sum::<usize>();
    Ok(Arc::new(ParsedChunk {
        source_len: source.len(),
        digest: digest.to_owned(),
        ast: Arc::new(ast),
        fragments,
        resources,
        disk_hit,
        resident_bytes,
    }))
}

impl ParsedChunk {
    fn without_bodies(&self) -> Self {
        let fragments: Vec<_> = self
            .fragments
            .iter()
            .map(|fragment| Fragment {
                descriptor: fragment.descriptor.clone(),
                source: None,
                digest: fragment.digest.clone(),
                locally_patchable: fragment.locally_patchable,
            })
            .collect();
        let resident_bytes = item_bytes(&self.ast.items)
            + self.resources.len() * std::mem::size_of::<Span>()
            + fragments
                .iter()
                .map(|fragment| fragment.descriptor.path.len() + fragment.digest.len() + 192)
                .sum::<usize>();
        Self {
            source_len: self.source_len,
            digest: self.digest.clone(),
            ast: Arc::clone(&self.ast),
            fragments,
            resources: self.resources.clone(),
            disk_hit: self.disk_hit,
            resident_bytes,
        }
    }
}

/// Canonical disk restoration validates local coordinates against the exact
/// expansion sidecar. Procedure source and compatibility resource strings are
/// absent; neither requires hydrating an unchanged source chunk.
fn restore_fragment_segmented(source: &dm_syntax::SegmentedSource, span: Span, digest: &str, root: &Path) -> Option<Arc<ParsedChunk>> {
    let len = span.end.checked_sub(span.start)?;
    let mut stored = read_shard(root,digest,len).ok().flatten()?;
    let boundary = |at: usize| at <= len && source.is_char_boundary(span.start+at);
    let mut previous = 0;
    if !stored.descriptors.iter().all(|descriptor| {
        let valid=descriptor.start>=previous && descriptor.start<=descriptor.header_end && descriptor.header_end<=descriptor.end
            && [descriptor.start,descriptor.header_end,descriptor.end].into_iter().all(boundary);
        previous=descriptor.end;
        valid
    }) { return None; }
    let mut previous_resource=0;
    if !stored.resources.iter().all(|&[start,end]| {
        let valid=start>=previous_resource && start<end && boundary(start) && boundary(end);
        previous_resource=end;
        valid
    }) {return None;}
    let resources:Vec<_>=stored.resources.iter().map(|&[start,end]|Span::new(start,end)).collect();
    let ast=stored.ast().ok()?;
    fn valid_items(items:&[Item],boundary:&impl Fn(usize)->bool)->bool {
        items.iter().all(|item| item.span.start<=item.header_span.start && item.header_span.end<=item.span.end
            && [item.span.start,item.span.end,item.header_span.start,item.header_span.end].into_iter().all(boundary)
            && valid_items(&item.children,boundary))
    }
    if !valid_items(&ast.items,&boundary) { return None; }
    let fragments: Vec<_>=stored.descriptors.into_iter().zip(stored.fragments).map(|(descriptor,cached)|Fragment {
        descriptor,source:None,digest:cached.digest,locally_patchable:cached.locally_patchable,
    }).collect();
    let resident_bytes=item_bytes(&ast.items)+resources.capacity()*std::mem::size_of::<Span>()+fragments.iter().map(|fragment|fragment.descriptor.path.len()+fragment.digest.len()+192).sum::<usize>();
    Some(Arc::new(ParsedChunk {source_len:len,digest:digest.to_owned(),ast:Arc::new(ast),fragments,resources,disk_hit:true,resident_bytes}))
}

fn valid_descriptors(source: &str, descriptors: &[OutlineDescriptor]) -> bool {
    let mut previous = 0;
    descriptors.iter().all(|descriptor| {
        let valid = descriptor.start >= previous
            && descriptor.start <= descriptor.header_end
            && descriptor.header_end <= descriptor.end
            && descriptor.end <= source.len()
            && source.is_char_boundary(descriptor.start)
            && source.is_char_boundary(descriptor.header_end)
            && source.is_char_boundary(descriptor.end);
        previous = descriptor.end;
        valid
    })
}

fn valid_resource_spans(source: &str, spans: &[[usize; 2]]) -> bool {
    let mut previous = 0;
    spans.iter().all(|&[start, end]| {
        let valid = start >= previous
            && start < end
            && source
                .get(start..end)
                .is_some_and(|literal| literal.starts_with('\''));
        previous = end;
        valid
    })
}

fn valid_ast(source: &str, items: &[Item]) -> bool {
    items.iter().all(|item| {
        item.span.start <= item.header_span.start
            && item.header_span.end <= item.span.end
            && [
                item.span.start,
                item.span.end,
                item.header_span.start,
                item.header_span.end,
            ]
            .into_iter()
            .all(|offset| source.is_char_boundary(offset))
            && valid_ast(source, &item.children)
    })
}

fn item_bytes(items: &[Item]) -> usize {
    items
        .iter()
        .map(|item| item.header.len() + 128 + item_bytes(&item.children))
        .sum()
}

struct CachedChunk {
    parsed: Arc<ParsedChunk>,
}

/// One bounded frontend session. Source order is reconstructed from the current
/// snapshot; cache keys never contain worktree names or absolute source offsets.
pub struct OutlineSession {
    pub(crate) canonical: crate::bootstrap::canonical::CanonicalSession,
    db: crate::Database,
    cache_root: Option<PathBuf>,
    chunks: HashMap<String, CachedChunk>,
    resident_bytes: usize,
    cache_budget: usize,
    stats: OutlineStats,
    last_source: Option<Arc<str>>,
    last_layout: Vec<(usize, Arc<ParsedChunk>)>,
    last_limit: usize,
    segmented_source: Option<dm_syntax::SegmentedSource>,
    segment_chunks: dm_syntax::SegmentedChunkSession,
    last_resource_literals: Vec<String>,
    resource_queries: segmented::ResourceLiteralQueries,
}

/// Conservative retained allocation charges, separate from process/private RSS.
#[derive(Clone, Copy, Debug, Default)]
pub struct FrontendRetentionFootprint {
    pub lexical: usize,
    pub graph_decoded: usize,
    pub graph_metadata: usize,
    pub graph_encoded: usize,
    pub graph_other: usize,
    pub maps: usize,
    pub skeleton: usize,
}

impl Default for OutlineSession {
    fn default() -> Self {
        Self::new(None)
    }
}

impl OutlineSession {
    pub fn set_project_configuration(&mut self, project: &Path, configuration: &str) {
        self.canonical
            .bind_configuration(project, configuration, self.cache_root.as_deref());
    }

    pub(crate) fn cache_root(&self) -> Option<&Path> {
        self.cache_root.as_deref()
    }

    /// Full retained state, including the canonical graph and prefix. Syntax's
    /// local cache budget remains independent from the coordinator pool budget.
    pub fn retained_bytes(&self) -> usize {
        self.resident_bytes()
            .saturating_add(self.canonical.resident_bytes())
    }
    pub fn retention_footprint(&self) -> FrontendRetentionFootprint {
        let graph = self.canonical.graph.stats();
        let graph_bytes = self.canonical.graph.resident_bytes();
        let maps = self.canonical.maps.resident_bytes();
        FrontendRetentionFootprint {
            lexical: self.resident_bytes(),
            graph_decoded: graph.resident_bytes,
            graph_metadata: graph.metadata_bytes,
            graph_encoded: graph.snapshot_bytes,
            graph_other: graph_bytes
                .saturating_sub(graph.resident_bytes)
                .saturating_sub(graph.metadata_bytes)
                .saturating_sub(graph.snapshot_bytes),
            maps,
            skeleton: self
                .canonical
                .resident_bytes()
                .saturating_sub(graph_bytes)
                .saturating_sub(maps),
        }
    }
    /// Release duplicated procedure body strings, preserving the current text,
    /// compact declaration AST, boundary layout and exact body identities.
    pub fn compact_source_frames(&mut self) -> usize {
        let before = self.resident_bytes();
        let mut compact: HashMap<String, Arc<ParsedChunk>> = HashMap::new();
        for (_, chunk) in &mut self.last_layout {
            let value = compact.entry(chunk.digest.clone()).or_insert_with(|| {
                if chunk
                    .fragments
                    .iter()
                    .any(|fragment| fragment.source.is_some())
                {
                    Arc::new(chunk.without_bodies())
                } else {
                    Arc::clone(chunk)
                }
            });
            *chunk = Arc::clone(value);
        }
        for cached in self.chunks.values_mut() {
            let chunk = &cached.parsed;
            let value = compact.entry(chunk.digest.clone()).or_insert_with(|| {
                if chunk
                    .fragments
                    .iter()
                    .any(|fragment| fragment.source.is_some())
                {
                    Arc::new(chunk.without_bodies())
                } else {
                    Arc::clone(chunk)
                }
            });
            cached.parsed = Arc::clone(value);
        }
        self.resident_bytes = self
            .chunks
            .iter()
            .map(|(digest, cached)| cached.parsed.resident_bytes + digest.len() + 256)
            .sum();
        self.db = crate::Database::default();
        before.saturating_sub(self.resident_bytes())
    }
    /// Evict only decoded code values, keeping live query identities/witnesses
    /// and the frozen skeleton so a small edit does not become a cold project.
    pub fn trim_decoded_to(&mut self, limit: usize) -> usize {
        let graph = self.canonical.graph.stats().resident_bytes;
        let graph_limit = graph.min(limit);
        self.canonical
            .graph
            .trim_decoded_to(graph_limit)
            .saturating_add(
                self.canonical
                    .maps
                    .trim_decoded_to(limit.saturating_sub(graph_limit)),
            )
    }
    pub fn trim_metadata_accelerators(&mut self) -> usize {
        self.canonical.graph.trim_metadata_accelerators()
    }
    pub fn compact_validated_candidates(&mut self) -> usize {
        self.canonical.graph.compact_validated_candidates()
    }
    pub fn release_skeleton(&mut self) -> usize {
        self.canonical.release_skeleton()
    }
    pub fn release_source_frames(&mut self) {
        self.db = crate::Database::default();
        self.last_source = None;
        self.evict_segmented_payloads();
        // Compact ASTs, chunk identities and lexical transitions are semantic
        // indexes, not disposable body payloads. Keep them across pressure.
    }
    pub fn release_transient_output_buffers(&mut self) {
        self.canonical.release_transient_output_buffers();
        self.canonical.graph.release_encoded_snapshot();
        self.canonical.maps.release_encoded_snapshot();
    }
    pub fn release_encoded_snapshot(&mut self) {
        self.canonical.release_auxiliary_caches();
        self.canonical.graph.release_encoded_snapshot();
        self.canonical.maps.release_encoded_snapshot();
    }
    pub fn release_declaration_replay_buffer(&mut self) -> usize {
        self.canonical.release_declaration_replay_buffer()
    }
    pub fn trim_output_recipe_bytes(&mut self, bytes: usize) -> usize {
        self.canonical.trim_output_recipe_bytes(bytes)
    }
    pub fn new(cache_root: Option<PathBuf>) -> Self {
        Self {
            canonical: crate::bootstrap::canonical::CanonicalSession::default(),
            db: crate::Database::default(),
            resource_queries: segmented::ResourceLiteralQueries::new(cache_root.as_deref()),
            cache_root,
            chunks: HashMap::new(),
            resident_bytes: 0,
            cache_budget: MAX_CACHE_BYTES,
            stats: OutlineStats::default(),
            last_source: None,
            last_layout: Vec::new(),
            last_limit: 0,
            segmented_source: None,
            segment_chunks: dm_syntax::SegmentedChunkSession::default(),
            last_resource_literals: Vec::new(),
        }
    }

    pub fn resident_bytes(&self) -> usize {
        self.resident_bytes + self.segment_chunks.resident_bytes()+self.resource_queries.resident_bytes()
            + self.last_resource_literals.iter().map(|literal| literal.capacity()+std::mem::size_of::<String>()).sum::<usize>()
            + self
                .last_source
                .as_ref()
                .map_or(0, |source| source.len() + 16)
            + self.last_layout.capacity() * std::mem::size_of::<(usize, Arc<ParsedChunk>)>()
    }
    pub fn stats(&self) -> OutlineStats {
        self.stats
    }

    pub fn update(&mut self, project: &PreprocessedProject) -> Result<SourceOutline, String> {
        self.update_source(&project.text)
    }

    pub fn update_source(&mut self, source: &str) -> Result<SourceOutline, String> {
        self.update_source_with_snapshot(source, false)
            .map(|(_, outline)| outline)
    }

    /// Assemble a compact declaration AST from the same cached chunks used for
    /// the outline. Procedure bodies remain in source fragments, not AST nodes.
    pub fn compact_snapshot(&mut self, source: &str) -> Result<(AstFile, SourceOutline), String> {
        if let Some(segmented) = self.segmented_source.clone().filter(|value| value.len() == source.len()) {
            return self.compact_snapshot_segmented(&segmented);
        }
        self.update_source_with_snapshot(source, true)
            .map(|(ast, outline)| (ast.expect("snapshot requested"), outline))
    }

    /// Exact raw procedure digests for the current compact snapshot. Spans keep
    /// duplicate overrides distinct and follow rebased chunks after edits.
    /// Incomplete or released lexical layouts leave callers their hash fallback.
    pub(crate) fn procedure_digests(
        &self,
        source: &str,
    ) -> Option<HashMap<(usize, usize), String>> {
        if self.last_source.as_deref() != Some(source) {
            return None;
        }
        let mut digests = HashMap::new();
        for (offset, chunk) in &self.last_layout {
            for fragment in &chunk.fragments {
                let start = offset.checked_add(fragment.descriptor.start)?;
                let end = offset.checked_add(fragment.descriptor.end)?;
                if source.get(start..end).is_none()
                    || digests
                        .insert((start, end), fragment.digest.clone())
                        .is_some()
                {
                    // A malformed or ambiguous cached boundary must not select
                    // another procedure's semantic candidate.
                    return None;
                }
            }
        }
        Some(digests)
    }

    /// Resource literals in exact source order, including nested interpolation.
    /// Reuse the same lexical declaration checkpoints as structural parsing.
    pub fn resource_literals(&mut self, source: &str) -> Result<Vec<String>, String> {
        self.update_source(source)?;
        let mut literals = Vec::new();
        if self.last_source.as_deref() == Some(source) {
            for (offset, chunk) in &self.last_layout {
                for span in &chunk.resources {
                    literals.push(source[offset + span.start..offset + span.end].to_owned());
                }
            }
        } else {
            // Oversized snapshots cannot retain a complete lexical layout.
            crate::bootstrap::resource_scan::visit_resources(source, &mut |literal| {
                literals.push(literal.to_owned());
            });
        }
        Ok(literals)
    }

    fn update_source_with_snapshot(
        &mut self,
        source: &str,
        capture: bool,
    ) -> Result<(Option<AstFile>, SourceOutline), String> {
        // Replacing the database releases old Salsa inputs as well as map entries.
        if self.resident_bytes() > self.cache_budget || self.chunks.len() > 8192 {
            // Releasing lexical state must preserve the long-lived semantic
            // graph and declaration prefix belonging to this worktree.
            self.release_source_frames();
        }
        // Retained parsed chunks are owned by the content cache. Resetting this
        // query database releases old input text and query revisions, while its
        // immutable Arc syntax values remain available through that cache.
        self.db = crate::Database::default();
        self.stats = OutlineStats::default();
        let limit = std::env::var("DM_BUILD_MAX_PARSE_CHUNK_BYTES")
            .ok()
            .and_then(|value| value.parse::<usize>().ok())
            .unwrap_or(1024 * 1024);
        let edit = (self.last_limit == limit)
            .then(|| self.last_source.as_deref())
            .flatten()
            .and_then(|previous| layout::edited_layout(previous, &self.last_layout, source, limit));
        let (region, mut ordered, after, validation_bytes) = if let Some(edit) = edit {
            (edit.region, edit.before, edit.after, edit.validation_bytes)
        } else {
            (Span::new(0, source.len()), Vec::new(), Vec::new(), 0)
        };
        self.stats.chunks = ordered.len() + after.len();
        self.stats.memory_hits = self.stats.chunks;
        self.stats.boundary_scanned_bytes = validation_bytes + region.end - region.start;
        let mut failure = None;
        let report = dm_syntax::for_each_source_chunk_with_limits(
            &source[region.range()],
            CHUNK_TARGET,
            limit,
            |text, relative_offset| {
                let offset = region.start + relative_offset;
                if failure.is_some() {
                    return;
                }
                self.stats.chunks += 1;
                let digest = crate::incremental::digest(text.as_bytes());
                let parsed = if let Some(cached) = self.chunks.get(&digest) {
                    self.stats.memory_hits += 1;
                    Arc::clone(&cached.parsed)
                } else {
                    let input = ChunkInput::new(
                        &self.db,
                        Arc::<str>::from(text),
                        self.cache_root.clone(),
                        digest.clone(),
                    );
                    match parse_chunk(&self.db, input).clone() {
                        Ok(parsed) => {
                            self.stats.disk_hits += usize::from(parsed.disk_hit);
                            self.stats.parsed_chunks += usize::from(!parsed.disk_hit);
                            self.stats.scanned_procedures += parsed.fragments.len();
                            let cost = parsed.resident_bytes + digest.len() + 256;
                            if self.resident_bytes + cost + source.len() <= self.cache_budget
                                && self.chunks.len() < 8192
                            {
                                self.resident_bytes += cost;
                                self.chunks.insert(
                                    digest,
                                    CachedChunk {
                                        parsed: Arc::clone(&parsed),
                                    },
                                );
                            }
                            parsed
                        }
                        Err(error) => {
                            failure = Some(error);
                            return;
                        }
                    }
                };
                ordered.push((offset, parsed));
            },
        );
        if let Some(error) = failure {
            self.db = crate::Database::default();
            return Err(error);
        }
        if report.skipped_declarations != 0 {
            self.db = crate::Database::default();
            return Err(format!(
                "{} declarations exceed the parse chunk limit of {limit} bytes",
                report.skipped_declarations
            ));
        }
        ordered.extend(after);
        let outline = assemble_outline(source, &ordered)?;
        let snapshot = capture.then(|| compact_ast(&ordered));
        // Keep only the current snapshot's chunks: historical bodies must not
        // accumulate in either the map, retained layout or Salsa query storage.
        self.chunks.clear();
        self.resident_bytes = 0;
        let layout_bytes = ordered.capacity() * std::mem::size_of::<(usize, Arc<ParsedChunk>)>();
        let mut complete = source.len() + 16 + layout_bytes <= self.cache_budget;
        let budget = self
            .cache_budget
            .saturating_sub(source.len() + 16 + layout_bytes);
        let mut seen = std::collections::HashSet::new();
        let current_cost: usize = ordered
            .iter()
            .filter(|(_, chunk)| seen.insert(chunk.digest.as_str()))
            .map(|(_, chunk)| chunk.resident_bytes + chunk.digest.len() + 256)
            .sum();
        drop(seen);
        if current_cost > budget {
            // Keep structural syntax and body identities for every chunk while
            // releasing duplicated bodies. Outline assembly can cheaply slice
            // them from the current source without reparsing or hashing them.
            for (_, chunk) in &mut ordered {
                *chunk = Arc::new(chunk.without_bodies());
            }
        }
        for (_, parsed) in &ordered {
            if self.chunks.contains_key(&parsed.digest) {
                continue;
            }
            let cost = parsed.resident_bytes + parsed.digest.len() + 256;
            if self.resident_bytes + cost <= budget && self.chunks.len() < 8192 {
                self.resident_bytes += cost;
                self.chunks.insert(
                    parsed.digest.clone(),
                    CachedChunk {
                        parsed: Arc::clone(parsed),
                    },
                );
            } else {
                complete = false;
            }
        }
        self.db = crate::Database::default();
        if complete {
            if !self
                .last_source
                .as_deref()
                .is_some_and(|previous| previous == source)
            {
                self.last_source = Some(Arc::from(source));
            }
            self.last_layout = ordered;
            self.last_limit = limit;
        } else {
            // Oversized snapshots remain compilable through bounded disk chunks.
            self.last_source = None;
            self.last_layout = Vec::new();
            self.last_limit = 0;
        }
        debug_assert!(self.resident_bytes() <= self.cache_budget);
        Ok((snapshot, outline))
    }

    /// Syntax fragments are independently reusable by semantic tools. Spans
    /// remain relative to the fragment so moving an earlier declaration does not
    /// invalidate an unchanged AST.
    pub fn cached_ast(&self, source: &str) -> Option<Arc<AstFile>> {
        self.chunks
            .get(&crate::incremental::digest(source.as_bytes()))
            .map(|chunk| Arc::clone(&chunk.parsed.ast))
    }
}

fn compact_ast(chunks: &[(usize, Arc<ParsedChunk>)]) -> AstFile {
    fn rebase(item: &Item, offset: usize) -> Item {
        Item {
            kind: item.kind.clone(),
            header: item.header.clone(),
            span: Span::new(item.span.start + offset, item.span.end + offset),
            header_span: Span::new(
                item.header_span.start + offset,
                item.header_span.end + offset,
            ),
            indent: item.indent,
            children: item
                .children
                .iter()
                .map(|child| rebase(child, offset))
                .collect(),
        }
    }
    AstFile {
        items: chunks
            .iter()
            .flat_map(|(offset, chunk)| {
                chunk
                    .ast
                    .items
                    .iter()
                    .map(move |item| rebase(item, *offset))
            })
            .collect(),
        ..AstFile::default()
    }
}

/// Cold-process helper. Daemons should retain OutlineSession directly.
pub fn compact_snapshot_cached(
    source: &str,
    cache_root: Option<PathBuf>,
) -> Result<(AstFile, SourceOutline), String> {
    OutlineSession::new(cache_root).compact_snapshot(source)
}

fn assemble_outline(
    source: &str,
    chunks: &[(usize, Arc<ParsedChunk>)],
) -> Result<SourceOutline, String> {
    let mut counts = HashMap::<&str, usize>::new();
    for (_, chunk) in chunks {
        for fragment in &chunk.fragments {
            *counts.entry(&fragment.descriptor.path).or_default() += 1;
        }
    }
    let mut abi = Sha256::new();
    let mut procedures = BTreeMap::new();
    let mut previous_chunk = 0;
    for (offset, chunk) in chunks {
        abi.update(source[previous_chunk..*offset].as_bytes());
        let text = &source[*offset..*offset + chunk.source_len];
        let mut previous = 0;
        for fragment in &chunk.fragments {
            let descriptor = &fragment.descriptor;
            abi.update(text[previous..descriptor.start].as_bytes());
            let patchable = fragment.locally_patchable && counts[descriptor.path.as_str()] == 1;
            if patchable {
                abi.update(text[descriptor.start..descriptor.header_end].as_bytes());
                abi.update(b"\0BODY\0");
            } else {
                abi.update(text[descriptor.start..descriptor.end].as_bytes());
            }
            procedures.insert(
                descriptor.path.clone(),
                ProcedureSource {
                    source: fragment.source.as_ref().map_or_else(
                        || Arc::from(&text[descriptor.start..descriptor.end]),
                        Arc::clone,
                    ),
                    digest: fragment.digest.clone(),
                    patchable,
                },
            );
            previous = descriptor.end;
        }
        abi.update(text[previous..].as_bytes());
        previous_chunk = offset + chunk.source_len;
    }
    abi.update(source[previous_chunk..].as_bytes());
    Ok(SourceOutline {
        abi_digest: format!("{:x}", abi.finalize()),
        procedures,
    })
}

#[derive(Serialize, Deserialize)]
struct StoredNode {
    kind: u8,
    header: String,
    spans: [usize; 4],
    indent: usize,
    children: Vec<StoredNode>,
}

impl StoredNode {
    fn capture(item: &Item) -> Self {
        Self {
            kind: match item.kind {
                ItemKind::Type => 0,
                ItemKind::Proc => 1,
                ItemKind::Verb => 2,
                ItemKind::Var => 3,
                ItemKind::Statement => 4,
                ItemKind::Unknown => 5,
            },
            header: item.header.clone(),
            spans: [
                item.span.start,
                item.span.end,
                item.header_span.start,
                item.header_span.end,
            ],
            indent: item.indent,
            children: item.children.iter().map(Self::capture).collect(),
        }
    }
    fn restore(self, source_len: usize, depth: usize, nodes: &mut usize) -> Result<Item, String> {
        *nodes += 1;
        if depth > 128
            || *nodes > 100_000
            || self.spans[0] > self.spans[1]
            || self.spans[1] > source_len
            || self.spans[2] > self.spans[3]
            || self.spans[3] > source_len
        {
            return Err("invalid syntax cache node".into());
        }
        let kind = match self.kind {
            0 => ItemKind::Type,
            1 => ItemKind::Proc,
            2 => ItemKind::Verb,
            3 => ItemKind::Var,
            4 => ItemKind::Statement,
            5 => ItemKind::Unknown,
            _ => return Err("invalid syntax cache kind".into()),
        };
        Ok(Item {
            kind,
            header: self.header,
            span: Span::new(self.spans[0], self.spans[1]),
            header_span: Span::new(self.spans[2], self.spans[3]),
            indent: self.indent,
            children: self
                .children
                .into_iter()
                .map(|node| node.restore(source_len, depth + 1, nodes))
                .collect::<Result<_, _>>()?,
        })
    }
}

#[derive(Serialize, Deserialize)]
struct StoredChunk {
    version: u32,
    compiler: String,
    source_digest: String,
    source_len: usize,
    nodes: Vec<StoredNode>,
    descriptors: Vec<OutlineDescriptor>,
    resources: Vec<[usize; 2]>,
    fragments: Vec<StoredFragment>,
}
#[derive(Serialize, Deserialize)]
struct StoredFragment { digest: String, locally_patchable: bool }
impl StoredChunk {
    fn ast(&mut self) -> Result<AstFile, String> {
        let mut count = 0;
        let items = std::mem::take(&mut self.nodes)
            .into_iter()
            .map(|node| node.restore(self.source_len, 0, &mut count))
            .collect::<Result<_, _>>()?;
        Ok(AstFile {
            items,
            ..AstFile::default()
        })
    }
}

fn shard_path(root: &Path, digest: &str) -> PathBuf {
    root.join("frontend-outline-v1")
        .join(env!("DM_EMISSION_FINGERPRINT"))
        .join(format!("{digest}.json"))
}

fn read_shard(root: &Path, digest: &str, source_len: usize) -> Result<Option<StoredChunk>, String> {
    let path = shard_path(root, digest);
    if fs::metadata(&path).map_or(true, |metadata| metadata.len() > MAX_SHARD_BYTES) {
        return Ok(None);
    }
    let bytes = fs::read(path).map_err(|error| error.to_string())?;
    if bytes.len() as u64 > MAX_SHARD_BYTES {
        return Ok(None);
    }
    let Some(newline) = bytes.iter().position(|byte| *byte == b'\n') else {
        return Ok(None);
    };
    let checksum = &bytes[..newline];
    let payload = &bytes[newline + 1..];
    if checksum != crate::incremental::digest(payload).as_bytes() {
        return Ok(None);
    }
    let stored: StoredChunk = serde_json::from_slice(payload).map_err(|error| error.to_string())?;
    if stored.version != 3
        || stored.compiler != env!("DM_EMISSION_FINGERPRINT")
        || stored.source_digest != digest
        || stored.source_len != source_len
        || stored.fragments.len() != stored.descriptors.len()
        || stored.fragments.iter().any(|fragment| fragment.digest.len()!=64 || !fragment.digest.bytes().all(|byte| byte.is_ascii_hexdigit()))
    {
        return Ok(None);
    }
    Ok(Some(stored))
}

fn write_shard(
    root: &Path,
    digest: &str,
    source_len: usize,
    ast: &AstFile,
    descriptors: &[OutlineDescriptor],
    resources: &[[usize; 2]],
    fragments: &[Fragment],
) -> std::io::Result<()> {
    let path = shard_path(root, digest);
    let parent = path.parent().unwrap();
    fs::create_dir_all(parent)?;
    let stored = StoredChunk {
        version: 3,
        compiler: env!("DM_EMISSION_FINGERPRINT").into(),
        source_digest: digest.into(),
        source_len,
        nodes: ast.items.iter().map(StoredNode::capture).collect(),
        descriptors: descriptors.to_vec(),
        resources: resources.to_vec(),
        fragments: fragments.iter().map(|fragment| StoredFragment { digest: fragment.digest.clone(), locally_patchable:fragment.locally_patchable }).collect(),
    };
    let payload = serde_json::to_vec(&stored).map_err(std::io::Error::other)?;
    if payload.len() as u64 > MAX_SHARD_BYTES {
        return Ok(());
    }
    let mut bytes = crate::incremental::digest(&payload).into_bytes();
    bytes.push(b'\n');
    bytes.extend_from_slice(&payload);
    let temporary = parent.join(format!(
        ".{}-{}.tmp",
        std::process::id(),
        TEMP_SEQUENCE.fetch_add(1, Ordering::Relaxed)
    ));
    fs::write(&temporary, bytes)?;
    if let Err(error) = replace_shard(&temporary, &path) {
        let _ = fs::remove_file(&temporary);
        return Err(error);
    }
    Ok(())
}

#[cfg(windows)]
fn replace_shard(source: &Path, destination: &Path) -> std::io::Result<()> {
    use std::os::windows::ffi::OsStrExt;
    #[link(name = "Kernel32")]
    unsafe extern "system" {
        fn MoveFileExW(source: *const u16, destination: *const u16, flags: u32) -> i32;
    }
    let source: Vec<u16> = source.as_os_str().encode_wide().chain(Some(0)).collect();
    let destination: Vec<u16> = destination
        .as_os_str()
        .encode_wide()
        .chain(Some(0))
        .collect();
    if unsafe { MoveFileExW(source.as_ptr(), destination.as_ptr(), 1) } == 0 {
        Err(std::io::Error::last_os_error())
    } else {
        Ok(())
    }
}

#[cfg(not(windows))]
fn replace_shard(source: &Path, destination: &Path) -> std::io::Result<()> {
    fs::rename(source, destination)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn equivalent(source: &str, session: &mut OutlineSession) -> SourceOutline {
        let expected = crate::bootstrap::incremental_source_outline(source).unwrap();
        let actual = session.update_source(source).unwrap();
        assert_eq!(actual.abi_digest, expected.abi_digest);
        assert_eq!(actual.procedures.len(), expected.procedures.len());
        for (path, expected) in expected.procedures {
            let actual = &actual.procedures[&path];
            assert_eq!(actual.source, expected.source);
            assert_eq!(actual.digest, expected.digest);
            assert_eq!(actual.patchable, expected.patchable);
        }
        actual
    }

    #[test]
    fn body_edits_reuse_unchanged_syntax_and_match_whole_outline() {
        let prefix = format!("//{}\n", "padding".repeat(5000));
        let source = format!("/obj/root\n\tvar/count = 7\n\tproc/value()\n\t\treturn count\n{prefix}/proc/other()\n\treturn 1\n");
        let mut session = OutlineSession::default();
        let first = equivalent(&source, &mut session);
        let original = Arc::clone(&first.procedures["/obj/root/proc/value"].source);
        let edited = source.replace("return 1", "return 2");
        let second = equivalent(&edited, &mut session);
        assert!(session.stats().memory_hits > 0);
        assert!(Arc::ptr_eq(
            &original,
            &second.procedures["/obj/root/proc/value"].source
        ));
        equivalent(&edited, &mut session);
        assert_eq!(session.stats().parsed_chunks, 0);
    }

    #[test]
    fn duplicate_paths_and_unsafe_bodies_preserve_global_abi_guard() {
        let padding = format!("//{}\n", "padding".repeat(5000));
        let source = format!("/proc/duplicate() return 1\n{padding}/proc/duplicate() return 2\n/proc/resource() return 'asset.dmi'\n/proc/defaulted(x = 5) return x\n");
        equivalent(&source, &mut OutlineSession::default());
    }
}
