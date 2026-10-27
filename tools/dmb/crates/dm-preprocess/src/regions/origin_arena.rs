//! Immutable indexed line provenance, with exact wide fallback.
use super::expansion::output_lines::OutputLines;
use super::{ExpandedOrigin, MacroExpansion};
use dm_syntax::Span;
use std::{collections::HashMap, path::PathBuf, sync::Arc};

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct OriginView<'a> {
    pub output_line: usize,
    pub path: &'a Arc<PathBuf>,
    pub source_line: usize,
}
#[derive(Clone, Copy, Debug)]
pub struct ExpandedOriginView<'a> {
    pub origin: OriginView<'a>,
    pub output_span: Span,
    pub source_span: Span,
    pub region: usize,
    pub macro_expansions: &'a Arc<Vec<MacroExpansion>>,
}
#[derive(Clone, Copy, Debug)]
struct Compact {
    output_start: u32,
    output_end: u32,
    source_start: u32,
    source_end: u32,
    source_line: u32,
    region: u32,
    path: u32,
    traces: u32,
}
#[derive(Clone, Copy, Debug)]
struct Wide {
    output_line: usize,
    output_span: Span,
    source_span: Span,
    source_line: usize,
    region: usize,
    path: usize,
    traces: usize,
}
impl Compact {
    fn wide(self, index: usize) -> Wide {
        Wide {
            output_line: index + 1,
            output_span: Span::new(self.output_start as usize, self.output_end as usize),
            source_span: Span::new(self.source_start as usize, self.source_end as usize),
            source_line: self.source_line as usize,
            region: self.region as usize,
            path: self.path as usize,
            traces: self.traces as usize,
        }
    }
}
/// One region's rows in an arena: the region's shared hydrated rows (see `RowsPool`), placed at `first` (the arena index
/// of its first row) and `output_base` (where its output starts in the joined text).
#[derive(Debug, Clone)]
struct Chunk {
    lines: Arc<OutputLines>,
    /// The largest relative output end of `lines`, so a moved chunk is checked without walking its rows.
    output_len: u32,
    first: u32,
    output_base: u32,
    region: u32,
    path: u32,
}
#[derive(Debug)]
enum Records {
    Compact(Box<[Compact]>),
    Wide(Box<[Wide]>),
    /// Rows by region: a session holds one chunk per region, not one row per output line.
    Chunked { chunks: Box<[Chunk]>, len: usize },
}
#[derive(Debug)]
struct Inner {
    records: Records,
    paths: Box<[Arc<PathBuf>]>,
    traces: Box<[Arc<Vec<MacroExpansion>>]>,
    /// The chunk the last lookup landed in (lookups mostly move forward a little).
    hint: std::sync::atomic::AtomicUsize,
}
/// Clones share immutable records and the original exact path/trace allocations.
#[derive(Clone)]
pub struct ExpandedOriginArena(Arc<Inner>);
impl std::fmt::Debug for ExpandedOriginArena {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_list().entries(self.iter()).finish()
    }
}
impl Default for ExpandedOriginArena {
    fn default() -> Self {
        Self(Arc::new(Inner {
            records: Records::Compact(Box::new([])),
            paths: Box::new([]),
            traces: Box::new([]),
            hint: Default::default(),
        }))
    }
}
impl ExpandedOriginArena {
    /// Physical immutable provenance owner, never a content hash shortcut.
    pub fn same_owner(&self, other: &Self) -> bool {
        Arc::ptr_eq(&self.0, &other.0)
    }
    pub fn len(&self) -> usize {
        match &self.0.records {
            Records::Compact(v) => v.len(),
            Records::Wide(v) => v.len(),
            Records::Chunked { len, .. } => *len,
        }
    }
    /// The chunk holding row `index` (`index < len`).
    fn chunk_of(&self, chunks: &[Chunk], index: usize) -> usize {
        use std::sync::atomic::Ordering::Relaxed;
        let holds = |at: usize| {
            chunks.get(at).is_some_and(|chunk| {
                chunk.first as usize <= index && index < chunk.first as usize + chunk.lines.len()
            })
        };
        let hint = self.0.hint.load(Relaxed);
        let found = if holds(hint) {
            hint
        } else if holds(hint + 1) {
            hint + 1
        } else {
            chunks.partition_point(|chunk| chunk.first as usize <= index) - 1
        };
        if found != hint {
            self.0.hint.store(found, Relaxed);
        }
        found
    }
    pub fn is_empty(&self) -> bool {
        self.len() == 0
    }
    pub fn clear(&mut self) {
        *self = Self::default();
    }
    pub fn get(&self, index: usize) -> Option<ExpandedOriginView<'_>> {
        let value = match &self.0.records {
            Records::Compact(v) => v.get(index)?.wide(index),
            Records::Wide(v) => *v.get(index)?,
            Records::Chunked { chunks, len } => {
                if index >= *len {
                    return None;
                }
                let chunk = &chunks[self.chunk_of(chunks, index)];
                let (output, source_line, source_span, traces) =
                    chunk.lines.view(index - chunk.first as usize);
                let base = chunk.output_base as usize;
                return Some(ExpandedOriginView {
                    origin: OriginView {
                        output_line: index + 1,
                        path: &self.0.paths[chunk.path as usize],
                        source_line,
                    },
                    output_span: Span::new(base + output.start, base + output.end),
                    source_span,
                    region: chunk.region as usize,
                    macro_expansions: traces,
                });
            }
        };
        Some(ExpandedOriginView {
            origin: OriginView {
                output_line: value.output_line,
                path: &self.0.paths[value.path],
                source_line: value.source_line,
            },
            output_span: value.output_span,
            source_span: value.source_span,
            region: value.region,
            macro_expansions: &self.0.traces[value.traces],
        })
    }
    pub fn last(&self) -> Option<ExpandedOriginView<'_>> {
        self.len().checked_sub(1).and_then(|i| self.get(i))
    }
    pub fn iter(
        &self,
    ) -> impl ExactSizeIterator<Item = ExpandedOriginView<'_>>
           + DoubleEndedIterator
           + std::iter::FusedIterator
           + '_ {
        (0..self.len()).map(|i| self.get(i).expect("issued arena index"))
    }
    /// The same index as `partition_point`, found by searching outward from `hint` (the last
    /// answer): a caller that asks about increasing offsets pays a probe or two per answer.
    pub fn partition_point_near(
        &self,
        hint: usize,
        mut predicate: impl FnMut(ExpandedOriginView<'_>) -> bool,
    ) -> usize {
        let len = self.len();
        let hint = hint.min(len);
        let mut holds = |index: usize| predicate(self.get(index).expect("issued arena index"));
        // The answer is the first index where the predicate fails; it holds before it.
        let (mut left, mut right) = if hint < len && holds(hint) {
            // The answer is after `hint`: gallop forward.
            let (mut known, mut step) = (hint, 1usize);
            loop {
                let probe = known.saturating_add(step);
                if probe >= len || !holds(probe) {
                    break (known + 1, probe.min(len));
                }
                known = probe;
                step *= 2;
            }
        } else if hint > 0 && !holds(hint - 1) {
            // The answer is before `hint`: gallop backward.
            let (mut known, mut step) = (hint - 1, 1usize);
            loop {
                if known < step {
                    break (0, known);
                }
                let probe = known - step;
                if holds(probe) {
                    break (probe + 1, known);
                }
                known = probe;
                step *= 2;
            }
        } else {
            return hint;
        };
        while left < right {
            let middle = left + (right - left) / 2;
            if holds(middle) {
                left = middle + 1
            } else {
                right = middle
            }
        }
        left
    }
    pub fn partition_point(
        &self,
        mut predicate: impl FnMut(ExpandedOriginView<'_>) -> bool,
    ) -> usize {
        let (mut left, mut right) = (0, self.len());
        while left < right {
            let middle = left + (right - left) / 2;
            if predicate(self.get(middle).expect("issued arena index")) {
                left = middle + 1
            } else {
                right = middle
            }
        }
        left
    }
    /// Exact boxed backing bytes; callback receives pointer, items and exact backing bytes.
    /// Nested original Arc allocations are borrowed through views, never materialized.
    pub fn visit_storage(&self, mut visit: impl FnMut(usize, usize, usize)) {
        fn boxed<T>(v: &[T], visit: &mut impl FnMut(usize, usize, usize)) {
            let bytes = std::mem::size_of_val(v);
            visit(v.as_ptr() as usize, v.len(), bytes);
        }
        visit(
            Arc::as_ptr(&self.0) as usize,
            1,
            std::mem::size_of::<Inner>(),
        );
        match &self.0.records {
            Records::Compact(v) => boxed(v, &mut visit),
            Records::Wide(v) => boxed(v, &mut visit),
            // The rows themselves are the records' shared allocations (census: expansion records).
            Records::Chunked { chunks, .. } => boxed(chunks, &mut visit),
        }
        boxed(&self.0.paths, &mut visit);
        boxed(&self.0.traces, &mut visit);
    }
}
/// One region's rows of an assembled arena (`ExpandedOriginArena::assembled`).
pub(super) enum RowPart {
    /// Rows `rows` of the previous arena, moved `output_shift` bytes along, their region numbers
    /// moved `region_shift` along.
    Reuse {
        rows: std::ops::Range<usize>,
        output_shift: i64,
        region_shift: i64,
    },
    /// Rows of a region that was expanded again, starting at `new_start` in the joined text.
    Fresh {
        region: usize,
        new_start: usize,
        path: Arc<PathBuf>,
        lines: Arc<OutputLines>,
    },
}
impl ExpandedOriginArena {
    /// An arena made of reused row ranges of this one and freshly expanded rows, in emission
    /// order. The output line of a row is its index, so rows renumber by position alone. `None`
    /// for the wide layout or a field that would not fit the compact one (the caller expands in
    /// full). Path and trace tables carry over; entries no row names any more are dropped once
    /// they are a quarter of a table.
    pub(super) fn assembled(&self, parts: Vec<RowPart>) -> Option<Self> {
        if let Records::Chunked { chunks: old, .. } = &self.0.records {
            return self.assembled_chunks(old, parts);
        }
        let Records::Compact(old) = &self.0.records else {
            return None;
        };
        let mut records: Vec<Compact> = Vec::with_capacity(old.len() + 64);
        let mut paths = self.0.paths.to_vec();
        let mut traces = self.0.traces.to_vec();
        for part in parts {
            match part {
                RowPart::Reuse {
                    rows,
                    output_shift,
                    region_shift,
                } => {
                    for row in old.get(rows)? {
                        records.push(Compact {
                            output_start: u32::try_from(i64::from(row.output_start) + output_shift)
                                .ok()?,
                            output_end: u32::try_from(i64::from(row.output_end) + output_shift)
                                .ok()?,
                            region: u32::try_from(i64::from(row.region) + region_shift).ok()?,
                            ..*row
                        });
                    }
                }
                RowPart::Fresh {
                    region,
                    new_start,
                    path,
                    lines,
                } => {
                    let path = match paths.iter().rposition(|known| Arc::ptr_eq(known, &path)) {
                        Some(index) => index,
                        None => {
                            paths.push(path);
                            paths.len() - 1
                        }
                    };
                    let mut last_trace: Option<(usize, usize)> = None;
                    for (relative, source_line, source_span, trace) in lines.iter() {
                        let pointer = Arc::as_ptr(trace) as usize;
                        let index = match last_trace.filter(|(known, _)| *known == pointer) {
                            Some((_, index)) => index,
                            None => {
                                traces.push(Arc::clone(trace));
                                traces.len() - 1
                            }
                        };
                        last_trace = Some((pointer, index));
                        records.push(Compact {
                            output_start: u32::try_from(new_start + relative.start).ok()?,
                            output_end: u32::try_from(new_start + relative.end).ok()?,
                            source_start: u32::try_from(source_span.start).ok()?,
                            source_end: u32::try_from(source_span.end).ok()?,
                            source_line: u32::try_from(source_line).ok()?,
                            region: u32::try_from(region).ok()?,
                            path: u32::try_from(path).ok()?,
                            traces: u32::try_from(index).ok()?,
                        });
                    }
                }
            }
        }
        // Drop table entries nothing names once they are a quarter of a table.
        let mut used_paths = vec![false; paths.len()];
        let mut used_traces = vec![false; traces.len()];
        for row in &records {
            used_paths[row.path as usize] = true;
            used_traces[row.traces as usize] = true;
        }
        let waste = |used: &[bool]| used.iter().filter(|used| !**used).count() * 4 > used.len();
        if waste(&used_paths) || waste(&used_traces) {
            let remap = |used: &[bool]| {
                let mut next = 0u32;
                used.iter()
                    .map(|used| {
                        let index = next;
                        next += u32::from(*used);
                        index
                    })
                    .collect::<Vec<_>>()
            };
            let (path_map, trace_map) = (remap(&used_paths), remap(&used_traces));
            for row in &mut records {
                row.path = path_map[row.path as usize];
                row.traces = trace_map[row.traces as usize];
            }
            paths = paths
                .into_iter()
                .zip(&used_paths)
                .filter_map(|(value, used)| used.then_some(value))
                .collect();
            traces = traces
                .into_iter()
                .zip(&used_traces)
                .filter_map(|(value, used)| used.then_some(value))
                .collect();
        }
        Some(Self(Arc::new(Inner {
            records: Records::Compact(records.into_boxed_slice()),
            paths: paths.into_boxed_slice(),
            traces: traces.into_boxed_slice(),
            hint: Default::default(),
        })))
    }
    /// `assembled` for a chunked arena: reused runs move whole chunks (they are region-aligned), fresh regions add theirs.
    fn assembled_chunks(&self, old: &[Chunk], parts: Vec<RowPart>) -> Option<Self> {
        let mut paths = self.0.paths.to_vec();
        let mut chunks: Vec<Chunk> = Vec::with_capacity(old.len() + 16);
        let mut rows = 0usize;
        for part in parts {
            match part {
                RowPart::Reuse {
                    rows: range,
                    output_shift,
                    region_shift,
                } => {
                    let mut at = old.partition_point(|chunk| (chunk.first as usize) < range.start);
                    let mut end = range.start;
                    while end < range.end {
                        let chunk = old.get(at)?;
                        if chunk.first as usize != end {
                            return None;
                        }
                        let output_base = i64::from(chunk.output_base) + output_shift;
                        u32::try_from(output_base + i64::from(chunk.output_len)).ok()?;
                        chunks.push(Chunk {
                            lines: Arc::clone(&chunk.lines),
                            output_len: chunk.output_len,
                            first: u32::try_from(rows).ok()?,
                            output_base: u32::try_from(output_base).ok()?,
                            region: u32::try_from(i64::from(chunk.region) + region_shift).ok()?,
                            path: chunk.path,
                        });
                        rows += chunk.lines.len();
                        end += chunk.lines.len();
                        at += 1;
                    }
                    if end != range.end {
                        return None;
                    }
                }
                RowPart::Fresh {
                    region,
                    new_start,
                    path,
                    lines,
                } => {
                    if lines.len() == 0 {
                        continue;
                    }
                    if !matches!(*lines, OutputLines::Compact(_)) {
                        return None;
                    }
                    let output_len = u32::try_from(lines.output_end()).ok()?;
                    u32::try_from(new_start + output_len as usize).ok()?;
                    let path = match paths.iter().rposition(|known| Arc::ptr_eq(known, &path)) {
                        Some(index) => index,
                        None => {
                            paths.push(path);
                            paths.len() - 1
                        }
                    };
                    let len = lines.len();
                    chunks.push(Chunk {
                        lines,
                        output_len,
                        first: u32::try_from(rows).ok()?,
                        output_base: u32::try_from(new_start).ok()?,
                        region: u32::try_from(region).ok()?,
                        path: u32::try_from(path).ok()?,
                    });
                    rows += len;
                }
            }
        }
        u32::try_from(rows).ok()?;
        // Drop path entries nothing names once they are a quarter of the table.
        let mut used = vec![false; paths.len()];
        for chunk in &chunks {
            used[chunk.path as usize] = true;
        }
        if used.iter().filter(|used| !**used).count() * 4 > used.len() {
            let mut next = 0u32;
            let map: Vec<u32> = used
                .iter()
                .map(|used| {
                    let index = next;
                    next += u32::from(*used);
                    index
                })
                .collect();
            for chunk in &mut chunks {
                chunk.path = map[chunk.path as usize];
            }
            paths = paths.into_iter().zip(&used).filter_map(|(value, used)| used.then_some(value)).collect();
        }
        Some(Self(Arc::new(Inner {
            records: Records::Chunked {
                chunks: chunks.into_boxed_slice(),
                len: rows,
            },
            paths: paths.into_boxed_slice(),
            traces: Box::new([]),
            hint: Default::default(),
        })))
    }
}
pub struct OriginIter<'a> {
    arena: &'a ExpandedOriginArena,
    indices: std::ops::Range<usize>,
}
impl<'a> Iterator for OriginIter<'a> {
    type Item = ExpandedOriginView<'a>;
    fn next(&mut self) -> Option<Self::Item> {
        self.indices
            .next()
            .map(|i| self.arena.get(i).expect("issued arena index"))
    }
    fn size_hint(&self) -> (usize, Option<usize>) {
        self.indices.size_hint()
    }
}
impl DoubleEndedIterator for OriginIter<'_> {
    fn next_back(&mut self) -> Option<Self::Item> {
        self.indices
            .next_back()
            .map(|i| self.arena.get(i).expect("issued arena index"))
    }
}
impl ExactSizeIterator for OriginIter<'_> {}
impl std::iter::FusedIterator for OriginIter<'_> {}
impl<'a> IntoIterator for &'a ExpandedOriginArena {
    type Item = ExpandedOriginView<'a>;
    type IntoIter = OriginIter<'a>;
    fn into_iter(self) -> Self::IntoIter {
        OriginIter {
            arena: self,
            indices: 0..self.len(),
        }
    }
}
/// Only the producer owns these temporary lookup maps. They do not survive publication.
#[derive(Default)]
pub(super) struct OriginArenaBuilder {
    /// Region chunks (`push_region`); empty once rows were pushed one by one.
    chunks: Vec<Chunk>,
    chunk_rows: usize,
    compact: Vec<Compact>,
    wide: Option<Vec<Wide>>,
    paths: Vec<Arc<PathBuf>>,
    traces: Vec<Arc<Vec<MacroExpansion>>>,
    last_path: Option<(usize, usize)>,
    last_trace: Option<(usize, usize)>,
    path_indexes: HashMap<usize, usize>,
    trace_indexes: HashMap<usize, usize>,
}
impl OriginArenaBuilder {
    /// A builder for about `regions` regions.
    pub(super) fn with_capacity(regions: usize) -> Self {
        Self {
            chunks: Vec::with_capacity(regions),
            ..Self::default()
        }
    }
    pub(super) fn len(&self) -> usize {
        self.chunk_rows + self.wide.as_ref().map_or(self.compact.len(), Vec::len)
    }
    fn path_index(&mut self, path: &Arc<PathBuf>) -> usize {
        let path_pointer = Arc::as_ptr(path) as usize;
        let index = match self
            .last_path
            .filter(|(pointer, _)| *pointer == path_pointer)
        {
            Some((_, index)) => index,
            None => *self.path_indexes.entry(path_pointer).or_insert_with(|| {
                let i = self.paths.len();
                self.paths.push(Arc::clone(path));
                i
            }),
        };
        self.last_path = Some((path_pointer, index));
        index
    }
    /// One region's rows, starting at `output_base` in the joined text. The rows are held by pointer (shared with every
    /// session that hydrated the same rows); a region that does not fit the compact layout turns the arena into rows.
    pub(super) fn push_region(
        &mut self,
        lines: Arc<OutputLines>,
        output_base: usize,
        region: usize,
        path: Arc<PathBuf>,
    ) {
        if lines.len() == 0 {
            return;
        }
        let output_len = lines.output_end();
        let fits = self.wide.is_none()
            && self.compact.is_empty()
            && matches!(*lines, OutputLines::Compact(_))
            && u32::try_from(output_base + output_len).is_ok()
            && u32::try_from(region).is_ok()
            && u32::try_from(self.chunk_rows + lines.len()).is_ok();
        if !fits {
            self.unchunk();
            self.push_rows(&lines, output_base, region, &path);
            return;
        }
        let path = self.path_index(&path);
        let len = lines.len();
        self.chunks.push(Chunk {
            lines,
            output_len: output_len as u32,
            first: self.chunk_rows as u32,
            output_base: output_base as u32,
            region: region as u32,
            path: path as u32,
        });
        self.chunk_rows += len;
    }
    /// Turn the chunks pushed so far into rows (a later region needs the row layout).
    fn unchunk(&mut self) {
        let chunks = std::mem::take(&mut self.chunks);
        self.chunk_rows = 0;
        for chunk in chunks {
            let path = Arc::clone(&self.paths[chunk.path as usize]);
            self.push_rows(&chunk.lines, chunk.output_base as usize, chunk.region as usize, &path);
        }
    }
    fn push_rows(&mut self, lines: &OutputLines, output_base: usize, region: usize, path: &Arc<PathBuf>) {
        for (relative, source_line, source_span, traces) in lines.iter() {
            let output_line = self.len() + 1;
            self.push(ExpandedOrigin {
                origin: super::Origin {
                    output_line,
                    path: Arc::clone(path),
                    source_line,
                },
                output_span: Span::new(output_base + relative.start, output_base + relative.end),
                source_span,
                region,
                macro_expansions: Arc::clone(traces),
            });
        }
    }
    pub(super) fn push(&mut self, origin: ExpandedOrigin) {
        let path = self.path_index(&origin.origin.path);
        let trace_pointer = Arc::as_ptr(&origin.macro_expansions) as usize;
        let traces = match self
            .last_trace
            .filter(|(pointer, _)| *pointer == trace_pointer)
        {
            Some((_, index)) => index,
            None => *self.trace_indexes.entry(trace_pointer).or_insert_with(|| {
                let i = self.traces.len();
                self.traces.push(origin.macro_expansions);
                i
            }),
        };
        self.last_trace = Some((trace_pointer, traces));
        let wide = Wide {
            output_line: origin.origin.output_line,
            output_span: origin.output_span,
            source_span: origin.source_span,
            source_line: origin.origin.source_line,
            region: origin.region,
            path,
            traces,
        };
        let packed = (|| {
            Some(Compact {
                output_start: u32::try_from(wide.output_span.start).ok()?,
                output_end: u32::try_from(wide.output_span.end).ok()?,
                source_start: u32::try_from(wide.source_span.start).ok()?,
                source_end: u32::try_from(wide.source_span.end).ok()?,
                source_line: u32::try_from(wide.source_line).ok()?,
                region: u32::try_from(wide.region).ok()?,
                path: u32::try_from(path).ok()?,
                traces: u32::try_from(traces).ok()?,
            })
        })();
        if let Some(values) = &mut self.wide {
            values.push(wide)
        } else if let Some(packed) = packed.filter(|_| wide.output_line == self.compact.len() + 1) {
            self.compact.push(packed)
        } else {
            let mut values: Vec<_> = std::mem::take(&mut self.compact)
                .into_iter()
                .enumerate()
                .map(|(i, v)| v.wide(i))
                .collect();
            values.push(wide);
            self.wide = Some(values)
        }
    }
    pub(super) fn finish(self) -> ExpandedOriginArena {
        ExpandedOriginArena(Arc::new(Inner {
            records: match self.wide {
                Some(v) => Records::Wide(v.into_boxed_slice()),
                None if !self.chunks.is_empty() => Records::Chunked {
                    chunks: self.chunks.into_boxed_slice(),
                    len: self.chunk_rows,
                },
                None => Records::Compact(self.compact.into_boxed_slice()),
            },
            paths: self.paths.into_boxed_slice(),
            traces: self.traces.into_boxed_slice(),
            hint: Default::default(),
        }))
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    fn input(line: usize, path: Arc<PathBuf>, traces: Arc<Vec<MacroExpansion>>) -> ExpandedOrigin {
        ExpandedOrigin {
            origin: super::super::Origin {
                output_line: line,
                path,
                source_line: 17,
            },
            output_span: Span::new(3, 8),
            source_span: Span::new(10, 20),
            region: 2,
            macro_expansions: traces,
        }
    }
    #[test]
    fn borrowed_views_preserve_fields_and_original_arc_sharing() {
        let path = Arc::new(PathBuf::from("included.dm"));
        let traces = Arc::new(Vec::new());
        let mut b = OriginArenaBuilder::default();
        b.push(input(1, path.clone(), traces.clone()));
        b.push(input(2, path.clone(), traces.clone()));
        let a = b.finish();
        let v = a.get(1).unwrap();
        assert_eq!(v.origin.output_line, 2);
        assert_eq!(v.origin.source_line, 17);
        assert_eq!(v.output_span, Span::new(3, 8));
        assert_eq!(v.source_span, Span::new(10, 20));
        assert_eq!(v.region, 2);
        assert!(Arc::ptr_eq(v.origin.path, &path));
        assert!(Arc::ptr_eq(v.macro_expansions, &traces));
        assert_eq!(a.partition_point(|v| v.origin.output_line < 2), 1);
        assert_eq!(a.iter().next_back().unwrap().origin.output_line, 2);
        assert_eq!(std::mem::size_of::<Compact>(), 32);
        let clone = a.clone();
        assert!(Arc::ptr_eq(&a.0, &clone.0));
    }
    #[test]
    fn consecutive_and_alternating_pointer_rosters_preserve_distinct_equal_paths() {
        let a = Arc::new(PathBuf::from("same.dm"));
        let b = Arc::new(PathBuf::from("same.dm"));
        let x = Arc::new(Vec::new());
        let y = Arc::new(Vec::new());
        let mut builder = OriginArenaBuilder::default();
        for (index, (path, trace)) in [(&a, &x), (&a, &x), (&b, &y), (&a, &x), (&b, &x)]
            .into_iter()
            .enumerate()
        {
            builder.push(input(index + 1, Arc::clone(path), Arc::clone(trace)));
        }
        let arena = builder.finish();
        for (index, (path, trace)) in [(&a, &x), (&a, &x), (&b, &y), (&a, &x), (&b, &x)]
            .into_iter()
            .enumerate()
        {
            let view = arena.get(index).unwrap();
            assert!(Arc::ptr_eq(view.origin.path, path));
            assert!(Arc::ptr_eq(view.macro_expansions, trace));
        }
        assert_eq!(arena.0.paths.len(), 2);
        assert_eq!(arena.0.traces.len(), 2);
    }
    #[test]
    fn irregular_output_line_and_wide_usize_fields_never_truncate() {
        let path = Arc::new(PathBuf::from("x"));
        let traces = Arc::new(Vec::new());
        let mut b = OriginArenaBuilder::default();
        b.push(input(1, path.clone(), traces.clone()));
        let mut x = input(usize::MAX, path, traces);
        x.source_span = Span::new(usize::MAX - 1, usize::MAX);
        x.region = usize::MAX;
        b.push(x);
        let a = b.finish();
        assert!(matches!(a.0.records, Records::Wide(_)));
        assert_eq!(a.get(0).unwrap().origin.output_line, 1);
        let v = a.last().unwrap();
        assert_eq!(v.origin.output_line, usize::MAX);
        assert_eq!(v.source_span.end, usize::MAX);
        assert_eq!(v.region, usize::MAX);
    }
}

#[cfg(test)]
#[path = "origin_arena_tests.rs"]
mod boundary_tests;
