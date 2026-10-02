//! Production frontend consumes shared expansion pieces. Contiguous strings
//! exist only for one bounded structural chunk or requested procedure range.
use super::*;
use dm_syntax::SegmentedSource;

impl OutlineSession {
    pub fn set_segmented_source(&mut self, source: SegmentedSource) {
        self.segmented_source = Some(source);
        self.last_source = None;
    }
    pub fn segmented_source(&self) -> Option<&SegmentedSource> { self.segmented_source.as_ref() }

    pub fn compact_snapshot_segmented(&mut self, source: &SegmentedSource) -> Result<(AstFile, SourceOutline), String> {
        self.snapshot_segmented(source, true, true)
    }
    /// Canonical builds need declaration nodes and body identities, never an
    /// all-procedure collection of copied body text.
    pub fn compact_declarations_segmented(&mut self, source: &SegmentedSource) -> Result<(AstFile, HashMap<(usize,usize),String>), String> {
        let (ast, _) = self.snapshot_segmented(source, false, true)?;
        let mut digests = HashMap::new();
        for (offset, chunk) in &self.last_layout {
            for fragment in &chunk.fragments {
                digests.insert((offset+fragment.descriptor.start, offset+fragment.descriptor.end), fragment.digest.clone());
            }
        }
        Ok((ast, digests))
    }
    fn snapshot_segmented(&mut self, source: &SegmentedSource, capture_bodies: bool, capture_ast: bool) -> Result<(AstFile, SourceOutline), String> {
        self.db = crate::Database::default();
        self.stats = OutlineStats::default();
        let limit = std::env::var("DM_BUILD_MAX_PARSE_CHUNK_BYTES").ok()
            .and_then(|value| value.parse::<usize>().ok()).unwrap_or(1024*1024);
        let mut ordered = Vec::new();
        let mut failure = None;
        let mut literals = Vec::new();
        // Temporarily detach the transition cache to let the callback mutate
        // syntax caches without sharing a mutable session borrow.
        let mut transitions = std::mem::take(&mut self.segment_chunks);
        let report = source.for_each_chunk_cached(&mut transitions, CHUNK_TARGET, limit, |text, offset| {
            if failure.is_some() { return; }
            self.stats.chunks += 1;
            let digest = crate::incremental::digest(text.as_bytes());
            let parsed = if let Some(cached) = self.chunks.get(&digest) {
                self.stats.memory_hits += 1;
                Arc::clone(&cached.parsed)
            } else {
                let input = ChunkInput::new(&self.db, Arc::<str>::from(text), self.cache_root.clone(), digest);
                match parse_chunk(&self.db, input).clone() {
                    Ok(parsed) => {
                        self.stats.disk_hits += usize::from(parsed.disk_hit);
                        self.stats.parsed_chunks += usize::from(!parsed.disk_hit);
                        self.stats.scanned_procedures += parsed.fragments.len();
                        parsed
                    }
                    Err(error) => { failure = Some(error); return; }
                }
            };
            for span in &parsed.resources { literals.push(text[span.range()].to_owned()); }
            ordered.push((offset, parsed));
        });
        self.stats.boundary_scanned_bytes = transitions.scanned_bytes;
        self.segment_chunks = transitions;
        let report = report?;
        if let Some(error) = failure { self.db = crate::Database::default(); return Err(error); }
        if report.skipped_declarations != 0 {
            return Err(format!("{} declarations exceed the parse chunk limit of {limit} bytes", report.skipped_declarations));
        }
        let ast = if capture_ast { compact_ast(&ordered) } else { AstFile::default() };
        let outline = if capture_bodies { assemble_segmented_outline(source, &ordered)? }
            else { SourceOutline { abi_digest: String::new(), procedures: BTreeMap::new() } };
        self.last_resource_literals = literals;
        self.chunks.clear();
        self.resident_bytes = 0;
        let layout_cost = ordered.capacity()*std::mem::size_of::<(usize, Arc<ParsedChunk>)>();
        let budget = self.cache_budget.saturating_sub(layout_cost+self.segment_chunks.resident_bytes());
        for (_, chunk) in &mut ordered {
            if self.chunks.contains_key(&chunk.digest) { continue; }
            let compact = Arc::new(chunk.without_bodies());
            let cost = compact.resident_bytes+compact.digest.len()+256;
            if self.resident_bytes+cost <= budget && self.chunks.len()<8192 {
                self.resident_bytes += cost;
                self.chunks.insert(compact.digest.clone(), CachedChunk { parsed: Arc::clone(&compact) });
                *chunk = compact;
            }
        }
        // The retained layout contains only cached compact structural nodes.
        // Over-budget nodes are released rather than escaping the cache charge.
        self.last_layout = ordered.into_iter().filter_map(|(offset, chunk)| {
            self.chunks.get(&chunk.digest).map(|cached| (offset, Arc::clone(&cached.parsed)))
        }).collect();
        self.last_limit = limit;
        self.db = crate::Database::default();
        Ok((ast, outline))
    }

    pub fn resource_literals_segmented(&mut self, source: &SegmentedSource) -> Result<Vec<String>, String> {
        self.snapshot_segmented(source, false, false)?;
        Ok(self.last_resource_literals.clone())
    }
}

fn assemble_segmented_outline(source: &SegmentedSource, chunks: &[(usize, Arc<ParsedChunk>)]) -> Result<SourceOutline, String> {
    let mut counts = HashMap::<&str, usize>::new();
    for (_, chunk) in chunks { for fragment in &chunk.fragments { *counts.entry(&fragment.descriptor.path).or_default() += 1; } }
    let mut abi = Sha256::new();
    let mut procedures = BTreeMap::new();
    let mut previous_chunk = 0;
    for (offset, chunk) in chunks {
        let gap = source.slice(Span::new(previous_chunk, *offset)).ok_or("invalid segmented chunk gap")?;
        abi.update(gap.as_bytes());
        let text = source.slice(Span::new(*offset, *offset+chunk.source_len)).ok_or("invalid segmented chunk range")?;
        let mut previous = 0;
        for fragment in &chunk.fragments {
            let descriptor = &fragment.descriptor;
            abi.update(text[previous..descriptor.start].as_bytes());
            let patchable = fragment.locally_patchable && counts[descriptor.path.as_str()] == 1;
            if patchable { abi.update(text[descriptor.start..descriptor.header_end].as_bytes()); abi.update(b"\0BODY\0"); }
            else { abi.update(text[descriptor.start..descriptor.end].as_bytes()); }
            procedures.insert(descriptor.path.clone(), ProcedureSource {
                source: fragment.source.as_ref().map_or_else(|| Arc::from(&text[descriptor.start..descriptor.end]), Arc::clone),
                digest: fragment.digest.clone(), patchable,
            });
            previous = descriptor.end;
        }
        abi.update(text[previous..].as_bytes());
        previous_chunk = offset+chunk.source_len;
    }
    abi.update(source.slice(Span::new(previous_chunk, source.len())).ok_or("invalid segmented tail")?.as_bytes());
    Ok(SourceOutline { abi_digest: format!("{:x}", abi.finalize()), procedures })
}
