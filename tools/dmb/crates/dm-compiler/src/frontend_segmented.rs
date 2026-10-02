//! Production frontend consumes shared expansion pieces. Contiguous strings
//! exist only for one bounded structural chunk or requested procedure range.
use super::*;
use dm_syntax::SegmentedSource;

impl OutlineSession {
    pub fn set_segmented_source(&mut self, source: SegmentedSource) {
        self.segmented_source = Some(source);
        self.last_source = None;
    }
    pub fn segmented_source(&self) -> Option<&SegmentedSource> {
        self.segmented_source.as_ref()
    }

    /// Immutable local-coordinate declaration fragments with a source offset
    /// sidecar. Consumers can traverse borrowed nodes and translate spans at the
    /// boundary instead of rebuilding an owned whole-project AST.
    pub fn declaration_fragments_segmented(
        &mut self,
        source: &SegmentedSource,
    ) -> Result<Vec<(usize, Arc<AstFile>)>, String> {
        self.snapshot_segmented(source, false, false)?;
        Ok(self.last_layout.iter().map(|(offset, chunk)| (*offset, Arc::clone(&chunk.ast))).collect())
    }

    /// Body identity lookup in source-order fragments, without constructing a
    /// project-sized span-to-String map for every request.
    pub fn procedure_digest_at(&self, span: Span) -> Option<&str> {
        let index = self.last_layout.partition_point(|(offset, _)| *offset <= span.start).checked_sub(1)?;
        let (offset, chunk) = &self.last_layout[index];
        let local_start = span.start.checked_sub(*offset)?;
        let index = chunk.fragments.partition_point(|fragment| fragment.descriptor.start < local_start);
        let fragment = chunk.fragments.get(index)?;
        (fragment.descriptor.start == local_start && offset+fragment.descriptor.end == span.end).then_some(fragment.digest.as_str())
    }

    /// Shared query surface for lints, documentation and analysis export.
    /// This uses the same persisted declaration fragments as native emission.
    pub fn analysis_view_segmented(&mut self,source:&SegmentedSource,builtin_image:&[u8]) -> Result<dm_analysis::FrontendView,Vec<String>> {
        self.snapshot_segmented(source,false,false).map_err(|error|vec![error])?;
        let fragments: Vec<_>=self.last_layout.iter().map(|(offset,chunk)|dm_analysis::FrontendFragment {
            id:chunk.digest.clone(),source_offset:*offset,source_len:chunk.source_len,ast:Arc::clone(&chunk.ast),
            procedures:chunk.fragments.iter().map(|fragment|dm_analysis::ProcedureFragment {
                symbol:fragment.descriptor.path.clone(),local_span:Span::new(fragment.descriptor.start,fragment.descriptor.end),body_digest:fragment.digest.clone(),
            }).collect::<Vec<_>>().into(),
        }).collect();
        let declarations=crate::declarations::lower_fragment_declarations(&fragments)?;
        let declarations=dm_semantics::DeclarationIndex::build(declarations).map_err(|errors|errors.into_iter().map(|error|format!("{error:?}")).collect::<Vec<_>>())?;
        let resolved=crate::bootstrap::analysis_resolved_model(&mut self.canonical,&fragments,source,builtin_image,self.cache_root.as_deref()).map_err(|error|vec![error])?;
        Ok(dm_analysis::FrontendView {fragments:fragments.into(),declarations:Arc::new(declarations),resolved:Some(resolved)})
    }

    pub fn evict_segmented_payloads(&mut self) {
        if let Some(source)=self.segmented_source.as_mut() {source.evict_payloads();}
    }

    pub fn compact_snapshot_segmented(
        &mut self,
        source: &SegmentedSource,
    ) -> Result<(AstFile, SourceOutline), String> {
        self.snapshot_segmented(source, true, true)
    }
    /// Canonical builds need declaration nodes and body identities, never an
    /// all-procedure collection of copied body text.
    pub fn compact_declarations_segmented(
        &mut self,
        source: &SegmentedSource,
    ) -> Result<(AstFile, HashMap<(usize, usize), String>), String> {
        let (ast, _) = self.snapshot_segmented(source, false, true)?;
        let mut digests = HashMap::new();
        for (offset, chunk) in &self.last_layout {
            for fragment in &chunk.fragments {
                digests.insert(
                    (
                        offset + fragment.descriptor.start,
                        offset + fragment.descriptor.end,
                    ),
                    fragment.digest.clone(),
                );
            }
        }
        Ok((ast, digests))
    }
    fn snapshot_segmented(
        &mut self,
        source: &SegmentedSource,
        capture_bodies: bool,
        capture_ast: bool,
    ) -> Result<(AstFile, SourceOutline), String> {
        self.db = crate::Database::default();
        self.stats = OutlineStats::default();
        let limit = std::env::var("DM_BUILD_MAX_PARSE_CHUNK_BYTES")
            .ok()
            .and_then(|value| value.parse::<usize>().ok())
            .unwrap_or(1024 * 1024);
        // Jobs retain only source ranges and immutable cache references. Workers
        // borrow a single piece, allocating only a chunk crossing piece edges.
        let mut jobs = Vec::new();
        let mut transitions = std::mem::take(&mut self.segment_chunks);
        let report = source.for_each_chunk_cached(&mut transitions, CHUNK_TARGET, limit, |text, offset| {
            let digest = crate::incremental::digest(text.as_bytes());
            let cached = self.chunks.get(&digest).map(|entry| Arc::clone(&entry.parsed));
            jobs.push((offset, text.len(), digest, cached));
        });
        self.stats.boundary_scanned_bytes = transitions.scanned_bytes;
        self.segment_chunks = transitions;
        let report = report?;
        if report.skipped_declarations != 0 {
            return Err(format!("{} declarations exceed the parse chunk limit of {limit} bytes", report.skipped_declarations));
        }
        let cache_root = self.cache_root.as_deref();
        let results = dm_work::map_ordered(
            &jobs,
            dm_work::WorkLimits::configured(),
            |job| if job.3.is_some() { 1 } else { job.1.saturating_mul(16).saturating_add(4096) },
            |job| {
                if let Some(cached) = &job.3 { return Ok(Arc::clone(cached)); }
                let text = source.try_slice(Span::new(job.0, job.0+job.1))?;
                parse_fragment(&text, &job.2, cache_root)
            },
        ).map_err(|error| format!("frontend worker failure: {error:?}"))?;
        let mut ordered = Vec::with_capacity(jobs.len());
        let mut literals = Vec::new();
        for (job, result) in jobs.into_iter().zip(results) {
            let parsed = result?;
            self.stats.chunks += 1;
            if job.3.is_some() {
                self.stats.memory_hits += 1;
            } else {
                self.stats.disk_hits += usize::from(parsed.disk_hit);
                self.stats.parsed_chunks += usize::from(!parsed.disk_hit);
                self.stats.scanned_procedures += parsed.fragments.len();
            }
            for span in &parsed.resources {
                literals.push(source.try_slice(Span::new(job.0+span.start, job.0+span.end))?.into_owned());
            }
            ordered.push((job.0, parsed));
        }
        let ast = if capture_ast {
            compact_ast(&ordered)
        } else {
            AstFile::default()
        };
        let outline = if capture_bodies {
            assemble_segmented_outline(source, &ordered)?
        } else {
            SourceOutline {
                abi_digest: String::new(),
                procedures: BTreeMap::new(),
            }
        };
        self.last_resource_literals = literals;
        self.chunks.clear();
        self.resident_bytes = 0;
        let layout_cost = ordered.capacity() * std::mem::size_of::<(usize, Arc<ParsedChunk>)>();
        let budget = self
            .cache_budget
            .saturating_sub(layout_cost + self.segment_chunks.resident_bytes());
        for (_, chunk) in &mut ordered {
            if self.chunks.contains_key(&chunk.digest) {
                continue;
            }
            let compact = if chunk.fragments.iter().all(|fragment| fragment.source.is_none()) {
                Arc::clone(chunk)
            } else {
                Arc::new(chunk.without_bodies())
            };
            let cost = compact.resident_bytes + compact.digest.len() + 256;
            if self.resident_bytes + cost <= budget && self.chunks.len() < 8192 {
                self.resident_bytes += cost;
                self.chunks.insert(
                    compact.digest.clone(),
                    CachedChunk {
                        parsed: Arc::clone(&compact),
                    },
                );
                *chunk = compact;
            }
        }
        // The current semantic projection must be complete even when decoded
        // cache retention exceeds its soft budget. Trimming may release this
        // layout after publication, never silently omit declarations.
        let mut charged = std::collections::HashSet::new();
        for (_, chunk) in &ordered {
            if charged.insert(chunk.digest.as_str()) && !self.chunks.contains_key(&chunk.digest) {
                self.resident_bytes += chunk.resident_bytes+chunk.digest.len()+256;
            }
        }
        self.last_layout = ordered;
        self.last_limit = limit;
        self.db = crate::Database::default();
        Ok((ast, outline))
    }

    pub fn resource_literals_segmented(
        &mut self,
        source: &SegmentedSource,
    ) -> Result<Vec<String>, String> {
        let mut jobs = Vec::new();
        let mut transitions = std::mem::take(&mut self.segment_chunks);
        let limit = std::env::var("DM_BUILD_MAX_PARSE_CHUNK_BYTES").ok().and_then(|v| v.parse().ok()).unwrap_or(1024 * 1024);
        let result = source.for_each_chunk_cached(&mut transitions, CHUNK_TARGET, limit, |text, offset| {
            jobs.push((offset, text.len(), crate::incremental::digest(text.as_bytes())));
        });
        self.stats.boundary_scanned_bytes = transitions.scanned_bytes;
        self.segment_chunks = transitions;
        result?;
        let literals = self.resource_queries.query_ranges(source, &jobs)?;
        self.resource_queries.flush();
        self.last_resource_literals = literals.clone();
        Ok(literals)
    }
}

fn assemble_segmented_outline(
    source: &SegmentedSource,
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
        let gap = source
            .try_slice(Span::new(previous_chunk, *offset))?;
        abi.update(gap.as_bytes());
        let text = source
            .try_slice(Span::new(*offset, *offset + chunk.source_len))?;
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
    abi.update(
        source
            .try_slice(Span::new(previous_chunk, source.len()))?
            .as_bytes(),
    );
    Ok(SourceOutline {
        abi_digest: format!("{:x}", abi.finalize()),
        procedures,
    })
}

/// Resource inventory is a lexical query, independent of declaration/body ASTs.
/// Compact results persist separately, so trimming syntax cannot discard assets.
pub(super) struct ResourceLiteralQueries {
    entries: HashMap<String, Arc<[String]>>,
    bytes: usize,
    store: Option<dm_store::Store>,
    dirty: Vec<dm_store::Change>,
    namespace: String,
}
impl ResourceLiteralQueries {
    pub fn new(root: Option<&std::path::Path>) -> Self {
        Self {
            entries: HashMap::new(),
            bytes: 0,
            store: root
                .and_then(|root| dm_store::Store::open(root.join("resource-literals.redb")).ok()),
            dirty: Vec::new(),
            namespace: format!("resource-literals-v1-{}", env!("DM_EMISSION_FINGERPRINT")),
        }
    }
    pub fn resident_bytes(&self) -> usize {
        self.bytes
            + self
                .dirty
                .iter()
                .map(|change| match change {
                    dm_store::Change::Put(_, bytes) => bytes.len() + 128,
                    _ => 128,
                })
                .sum::<usize>()
    }
    fn query_ranges(&mut self, source: &SegmentedSource, jobs: &[(usize, usize, String)]) -> Result<Vec<String>, String> {
        let missing: Vec<_> = jobs.iter().filter(|job| !self.entries.contains_key(&job.2)).map(|job| dm_store::Key::new(&self.namespace, &job.2)).collect();
        // One read transaction restores all requested lexical nodes. The store
        // never scans unrelated namespaces, and bodies remain shared ranges.
        let restored = self.store.as_ref().and_then(|store| store.read_many(&missing, None).ok());
        let mut disk = BTreeMap::new();
        if let Some(records) = restored {
            for (key, bytes) in missing.into_iter().zip(records.values) {
                if let Some(values) = bytes.and_then(|bytes| serde_json::from_slice::<Vec<String>>(&bytes).ok()) {
                    disk.insert(key, Arc::<[String]>::from(values));
                }
            }
        }
        let candidates: Vec<_> = jobs.iter().map(|job| {
            let cached = self.entries.get(&job.2).cloned().or_else(|| disk.get(&dm_store::Key::new(&self.namespace, &job.2)).cloned());
            (job, cached)
        }).collect();
        let results = dm_work::map_ordered(&candidates, dm_work::WorkLimits::configured(),
            |(job, cached)| if cached.is_some() { 1 } else { job.1.saturating_mul(2).saturating_add(1024) },
            |(job, cached)| {
                if let Some(values) = cached { return Ok((Arc::clone(values), false)); }
                let text = source.try_slice(Span::new(job.0, job.0+job.1))?;
                let mut values = Vec::new();
                crate::bootstrap::resource_scan::visit_resources(&text, &mut |value| values.push(value.to_owned()));
                Ok::<_, String>((Arc::<[String]>::from(values), true))
            }).map_err(|error| format!("resource query worker failure: {error:?}"))?;
        let mut output = Vec::new();
        for (job, result) in jobs.iter().zip(results) {
            let (values, fresh) = result?;
            output.extend(values.iter().cloned());
            if fresh {
                if let Ok(bytes) = serde_json::to_vec(&*values) {
                    self.dirty.push(dm_store::Change::Put(dm_store::Key::new(&self.namespace, &job.2), bytes));
                }
            }
            if self.entries.contains_key(&job.2) { continue; }
            let charge = job.2.len()+128+values.len()*std::mem::size_of::<String>()+values.iter().map(String::capacity).sum::<usize>();
            if self.bytes+charge > 8*1024*1024 { self.entries.clear(); self.bytes=0; }
            if charge<=8*1024*1024 { self.entries.insert(job.2.clone(),values); self.bytes+=charge; }
        }
        Ok(output)
    }
    fn flush(&mut self) {
        if let Some(store) = &self.store {
            let _ = store.commit(&[], &self.dirty, None);
        }
        self.dirty.clear();
    }
}
