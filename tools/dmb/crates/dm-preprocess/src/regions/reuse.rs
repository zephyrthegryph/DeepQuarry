//! Expansion of a plan whose unchanged regions are verbatim copies of the previous plan's
//! (doc/incremental_core.md, migration step 3).
//!
//! `plan_regions_incremental` adopts unchanged include subtrees whole and says, for every region
//! of the new plan, which region of the previous plan it copies. A copied region has the same
//! lines and the same macro environments, so its expansion is the previous one: its text, its
//! receipt and its provenance rows are moved to their new place instead of being expanded or
//! rebuilt. Only the other regions go through the expansion memo, and the joined text, the
//! receipts and the origin arena are assembled around the two kinds.
//!
//! Every function returns `None` for a precondition it cannot prove; the caller then runs the
//! full expansion. `DMB_FRONTEND_VERIFY=1` compares both results.
use super::origin_arena::RowPart;
use super::*;
use crate::SourceText;
use region_memo::RegionReceipt;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::Mutex;

/// Counts of what the reuse did, for the request log.
#[derive(Clone, Copy, Debug, Default)]
pub struct ExpansionReuse {
    pub reused: usize,
    pub expanded: usize,
    pub rows_moved: usize,
    /// Where it spent its time: classifying regions, expanding the others, joining the text and
    /// receipts, assembling the origin rows.
    pub prepare: std::time::Duration,
    pub expand: std::time::Duration,
    pub text: std::time::Duration,
    pub rows: std::time::Duration,
}

fn expand_indices(
    plan: &DirectivePlan,
    indices: &[usize],
    memo: &dyn ExpansionMemo,
    executor: &dm_exec::BuildExecutor,
) -> Vec<expansion::RegionOutput> {
    let worker_count = executor.workers().min(indices.len().max(1));
    if worker_count <= 1 || indices.len() < 16 {
        return indices
            .iter()
            .map(|&index| region_memo::expand(plan, index, memo))
            .collect();
    }
    let next = AtomicUsize::new(0);
    let outputs = Mutex::new((0..indices.len()).map(|_| None).collect::<Vec<_>>());
    executor.scope(|scope| {
        for _ in 0..worker_count {
            let (next, outputs) = (&next, &outputs);
            scope.spawn(move |_| {
                let _profile = dm_profile::stage("frontend.expansion");
                loop {
                    let slot = next.fetch_add(1, Ordering::Relaxed);
                    let Some(&index) = indices.get(slot) else {
                        break;
                    };
                    let output = region_memo::expand(plan, index, memo);
                    outputs.lock().expect("expansion output lock poisoned")[slot] = Some(output);
                }
            });
        }
    });
    outputs
        .into_inner()
        .expect("expansion output lock poisoned")
        .into_iter()
        .map(|output| output.expect("every assigned region has one expansion result"))
        .collect()
}

/// The expansion of `plan`, reusing the previous expansion for every region `reuse` marks as a
/// verbatim copy; or `None`.
pub fn expand_regions_reusing(
    prev: &ExpandedRegions,
    plan: &DirectivePlan,
    reuse: &PlanReuse,
    memo: &dyn ExpansionMemo,
    executor: &dm_exec::BuildExecutor,
) -> Option<(ExpandedRegions, ExpansionReuse)> {
    if !prev.diagnostics.is_empty()
        || !prev.lexical_diagnostics.is_empty()
        || !plan.diagnostics.is_empty()
        || !prev.tokens.is_empty()
        || reuse.regions.len() != plan.regions.len()
    {
        return None;
    }
    let prepare_started = std::time::Instant::now();
    // Where each previous region's text and rows are.
    let mut receipt_of: Vec<Option<usize>> = Vec::new();
    for (position, receipt) in prev.receipts.iter().enumerate() {
        if receipt.region >= receipt_of.len() {
            receipt_of.resize(receipt.region + 1, None);
        }
        receipt_of[receipt.region] = Some(position);
    }
    let mut row_starts = Vec::with_capacity(prev.receipts.len() + 1);
    let mut rows = 0usize;
    for receipt in &prev.receipts {
        row_starts.push(rows);
        rows += receipt.rows;
    }
    row_starts.push(rows);
    if rows != prev.origins.len() {
        return None;
    }
    let emission: Vec<usize> = plan.emission_regions().collect();
    let source: Vec<Option<usize>> = emission
        .iter()
        .map(|&region| {
            if let Some(previous) = reuse.regions[region] {
                return receipt_of.get(previous).copied().flatten();
            }
            // A region of a subtree adopted under other bindings: its previous expansion stands when it read none
            // of the macros whose bindings differ.
            let (previous, names) = reuse.rebased_regions.get(&region)?;
            let position = receipt_of.get(*previous).copied().flatten()?;
            prev.receipts[position]
                .record
                .reads()
                .iter()
                .all(|read| !names.contains(&read.name))
                .then_some(position)
        })
        .collect();
    let fresh: Vec<usize> = emission
        .iter()
        .zip(&source)
        .filter_map(|(&region, source)| source.is_none().then_some(region))
        .collect();
    // Admission keys: a copied region keeps its key; the others are hashed.
    let input_keys: Option<Vec<Option<[u8; 16]>>> = memo.input_admissions().and_then(|admissions| {
        if prev.input_keys.len() == 0 {
            return None;
        }
        let keys: Vec<_> = (0..plan.regions.len())
            .map(|region| match reuse.regions[region] {
                Some(previous) => prev.input_keys.get(previous).copied().flatten(),
                None => ExpansionInputs::region_key(plan, region),
            })
            .collect();
        admissions.retain_keys(&keys);
        Some(keys)
    });
    let input_keys = match input_keys {
        Some(keys) => keys,
        None => match memo.input_admissions() {
            Some(admissions) => admissions.retain_current(plan),
            None => Vec::new(),
        },
    };
    let prepare = prepare_started.elapsed();
    let expand_started = std::time::Instant::now();
    let mut outputs = expand_indices(plan, &fresh, memo, executor).into_iter();
    let expand = expand_started.elapsed();
    let text_started = std::time::Instant::now();
    // The joined text is laid out first (where each piece goes) and copied after, in parallel: one serial copy of the whole
    // text into a fresh allocation was most of this step (the copy and the first touch of every page).
    let mut pieces: Vec<SourceText> = Vec::new();
    let mut length = 0usize;
    let mut receipts = Vec::with_capacity(emission.len());
    let mut parts = Vec::new();
    let mut runs: Vec<super::CarriedRun> = Vec::new();
    let mut stats = ExpansionReuse::default();
    let mut slot = 0usize;
    while slot < emission.len() {
        let region = emission[slot];
        let Some(first) = source[slot] else {
            let output = outputs.next()?;
            if !output.diagnostics.is_empty() {
                return None;
            }
            let record = output.receipt?;
            let start = length;
            length += output.text.len();
            pieces.push(output.text.clone());
            let lines = output.lines;
            receipts.push(RegionReceipt {
                region,
                output: Span::new(start, length),
                record,
                rows: lines.len(),
            });
            parts.push(RowPart::Fresh {
                region,
                new_start: start,
                path: plan.occurrences[plan.regions[region].occurrence].path.clone(),
                lines,
            });
            stats.expanded += 1;
            slot += 1;
            continue;
        };
        // A run of regions that are consecutive in both expansions moves as one piece.
        let region_shift = region as i64 - prev.receipts[first].region as i64;
        let mut last = first;
        let mut end = slot + 1;
        while end < emission.len() {
            let next = emission[end];
            match source[end] {
                Some(position)
                    if position == last + 1
                        && next as i64 - prev.receipts[position].region as i64 == region_shift =>
                {
                    last = position;
                    end += 1;
                }
                _ => break,
            }
        }
        let from = prev.receipts[first].output.start;
        let to = prev.receipts[last].output.end;
        let start = length;
        prev.text.get(from..to)?;
        pieces.push(prev.text.checked_view(from..to)?);
        length += to - from;
        runs.push(super::CarriedRun {
            start,
            previous_start: from,
            len: to - from,
            receipts: (receipts.len(), receipts.len() + (last - first + 1)),
            previous_receipt: first,
        });
        let output_shift = start as i64 - from as i64;
        for (offset, position) in (first..=last).enumerate() {
            let old = &prev.receipts[position];
            receipts.push(RegionReceipt {
                region: emission[slot + offset],
                output: Span::new(
                    (old.output.start as i64 + output_shift) as usize,
                    (old.output.end as i64 + output_shift) as usize,
                ),
                record: Arc::clone(&old.record),
                rows: old.rows,
            });
        }
        parts.push(RowPart::Reuse {
            rows: row_starts[first]..row_starts[last + 1],
            output_shift,
            region_shift,
        });
        stats.reused += last - first + 1;
        stats.rows_moved += row_starts[last + 1] - row_starts[first];
        slot = end;
    }
    let text = joined(&pieces, length, executor);
    let text_elapsed = text_started.elapsed();
    let rows_started = std::time::Instant::now();
    let origins = prev.origins.assembled(parts)?;
    stats.prepare = prepare;
    stats.expand = expand;
    stats.text = text_elapsed;
    stats.rows = rows_started.elapsed();
    let carried = Arc::new(super::CarriedText { text: text.downgrade(), previous: prev.text.downgrade(), runs });
    Some((
        ExpandedRegions {
            input_keys: Arc::new(input_keys),
            carried: Some(carried),
            text,
            tokens: Vec::new(),
            origins,
            emission_regions: emission,
            diagnostics: Vec::new(),
            receipts,
            lexical_diagnostics: Vec::new(),
        },
        stats,
    ))
}

/// The concatenation of `pieces` (`length` bytes in all), copied in parallel blocks into an allocation that is never zeroed
/// first (zeroing 90 MB and then copying over it was most of the time).
fn joined(pieces: &[SourceText], length: usize, executor: &dm_exec::BuildExecutor) -> SourceText {
    use std::mem::MaybeUninit;
    const BLOCK: usize = 1 << 20;
    let mut bytes: Vec<u8> = Vec::with_capacity(length);
    // Every piece split into blocks of at most BLOCK bytes, each paired with its own disjoint destination.
    let mut jobs: Vec<(&[u8], &mut [MaybeUninit<u8>])> = Vec::new();
    let mut rest: &mut [MaybeUninit<u8>] = &mut bytes.spare_capacity_mut()[..length];
    for piece in pieces {
        for block in piece.as_bytes().chunks(BLOCK) {
            let (into, tail) = std::mem::take(&mut rest).split_at_mut(block.len());
            jobs.push((block, into));
            rest = tail;
        }
    }
    assert!(rest.is_empty(), "joined text pieces do not add up to its length");
    let copy = |from: &[u8], into: &mut [MaybeUninit<u8>]| {
        assert_eq!(from.len(), into.len());
        // SAFETY: `into` is exactly `from.len()` bytes of the destination that nothing else refers to, and the two never
        // overlap (one is a source text, the other a fresh allocation).
        unsafe { std::ptr::copy_nonoverlapping(from.as_ptr(), into.as_mut_ptr().cast::<u8>(), from.len()) };
    };
    let workers = executor.workers().max(1);
    if workers == 1 || length < 4 * BLOCK {
        for (from, into) in jobs {
            copy(from, into);
        }
    } else {
        let per = jobs.len().div_ceil(workers);
        executor.scope(|scope| {
            for part in jobs.chunks_mut(per) {
                scope.spawn(move |_| {
                    for (from, into) in part.iter_mut() {
                        copy(from, into);
                    }
                });
            }
        });
    }
    // SAFETY: every byte of the first `length` was written above (the jobs cover them exactly, the assert holds), and they
    // are the pieces' bytes in order, each piece a `str`: their concatenation is valid UTF-8.
    unsafe {
        bytes.set_len(length);
        SourceText::from(String::from_utf8_unchecked(bytes))
    }
}

/// Whether a reusing expansion equals a full one (verification mode): the text, every origin row
/// field, the receipts' spans and row counts, and the emission order.
pub fn expansions_equal(a: &ExpandedRegions, b: &ExpandedRegions) -> Result<(), String> {
    if a.text.as_str() != b.text.as_str() {
        return Err("joined text differs".into());
    }
    if a.origins.len() != b.origins.len() {
        return Err(format!(
            "origin rows {} vs {}",
            a.origins.len(),
            b.origins.len()
        ));
    }
    for (index, (x, y)) in a.origins.iter().zip(b.origins.iter()).enumerate() {
        let same = x.origin.output_line == y.origin.output_line
            && x.origin.source_line == y.origin.source_line
            && x.origin.path == y.origin.path
            && x.output_span == y.output_span
            && x.source_span == y.source_span
            && x.region == y.region
            && x.macro_expansions == y.macro_expansions;
        if !same {
            return Err(format!("origin row {index} differs"));
        }
    }
    if a.receipts.len() != b.receipts.len()
        || a.receipts.iter().zip(&b.receipts).any(|(x, y)| {
            x.region != y.region || x.output != y.output || x.rows != y.rows
        })
    {
        return Err("receipts differ".into());
    }
    if a.emission_regions != b.emission_regions || a.diagnostics.len() != b.diagnostics.len() {
        return Err("emission order or diagnostics differ".into());
    }
    Ok(())
}

/// Whether an incremental plan equals a full one (verification mode), over everything expansion
/// and the frontend read from it: every region (lines, spans, macro environments), occurrence
/// (including its include-return and end-of-file cursors), ordered item, source text, line start,
/// dependency, terminal macro and `FILE_DIR`.
pub fn plans_equal(a: &DirectivePlan, b: &DirectivePlan) -> Result<(), String> {
    if a.regions.len() != b.regions.len() || a.items.len() != b.items.len() {
        return Err("region or item count differs".into());
    }
    for (index, (x, y)) in a.regions.iter().zip(&b.regions).enumerate() {
        if x.occurrence != y.occurrence
            || x.source_span != y.source_span
            || x.encounter_ordinal != y.encounter_ordinal
            || x.manifest_source != y.manifest_source
            || x.effects.len() != y.effects.len()
            || x.segments.len() != y.segments.len()
        {
            return Err(format!("region {index} header differs"));
        }
        if format!("{:?}", x.effects) != format!("{:?}", y.effects) {
            return Err(format!("region {index} effects differ"));
        }
        for (s, t) in x.segments.iter().zip(y.segments.iter()) {
            if s.lines.len() != t.lines.len() || !s.macros.same_bindings(&t.macros) {
                return Err(format!("region {index} segment differs"));
            }
            for (l, m) in s.lines.iter().zip(&t.lines) {
                if l.source_span != m.source_span
                    || l.source_line != m.source_line
                    || l.source_lines != m.source_lines
                    || l.text.as_str() != m.text.as_str()
                {
                    return Err(format!("region {index} line differs"));
                }
            }
        }
    }
    if format!("{:?}", a.items) != format!("{:?}", b.items) {
        return Err("ordered items differ".into());
    }
    if a.occurrences.len() != b.occurrences.len() {
        return Err("occurrence count differs".into());
    }
    for (index, (x, y)) in a.occurrences.iter().zip(&b.occurrences).enumerate() {
        if format!("{x:?}") != format!("{y:?}") {
            return Err(format!("occurrence {index} differs"));
        }
    }
    if a.source_texts.len() != b.source_texts.len()
        || a.source_texts
            .iter()
            .zip(&b.source_texts)
            .any(|((p, x), (q, y))| p != q || x.as_str() != y.as_str())
    {
        return Err("source texts differ".into());
    }
    if a.source_line_starts != b.source_line_starts
        || a.dependencies != b.dependencies
        || a.file_dirs != b.file_dirs
        || a.final_macros != b.final_macros
        || a.project_dir != b.project_dir
        || format!("{:?}", a.diagnostics) != format!("{:?}", b.diagnostics)
        || format!("{:?}", a.warnings) != format!("{:?}", b.warnings)
        || a.diagnostic_ordinals != b.diagnostic_ordinals
    {
        return Err("line starts, dependencies, macros, file dirs or diagnostics differ".into());
    }
    Ok(())
}
