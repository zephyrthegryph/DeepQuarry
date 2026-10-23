//! In-place edit of a previous plan and expansion for a changed leaf source file
//! (doc/retained_frontend.md, step F1).
//!
//! The full planner and expander visit every interval and region of the program (0.6 s and 0.3 s on
//! DeepQuarry) to learn that all but one are unchanged. When the only changed files are leaf `.dm`
//! files with no preprocessor directive before or after the edit, nothing but those files'
//! regions can differ: their text, line starts, region lines and span, the end-of-file line, and
//! (through the length delta) the joined text and the offsets after them.
//!
//! Every function here returns `None` for any precondition it cannot prove; the caller runs the
//! full pass. `DMB_FRONTEND_REVISION=verify` compares the edit with the full pass.
use super::*;
use crate::SourceText;
use prepared_source::PreparedSource;
use region_memo::RegionReceipt;

/// A plan derived from a previous one, with the regions whose text changed.
pub struct PlanEdit {
    pub plan: DirectivePlan,
    pub regions: Vec<usize>,
}

/// At most this many files may change for an edit to apply.
const MAX_CHANGED_FILES: usize = 8;

fn directive_free(prepared: &PreparedSource) -> bool {
    (0..prepared.lines().len()).all(|index| prepared.directive(index).is_none())
}

/// The previous plan with every changed leaf file replaced, or `None`.
///
/// Every file the full planner would read is requested from the provider again, so a recording
/// provider captures the same inputs; an unchanged file is recognised by `SourceText::same_view`.
pub fn plan_regions_edit<P: SourceProvider>(
    prev: &DirectivePlan,
    provider: &P,
) -> Option<PlanEdit> {
    if !prev.diagnostics.is_empty() || !prev.warnings.is_empty() {
        return None;
    }
    let mut changed: Vec<(PathBuf, Arc<PreparedSource>)> = Vec::new();
    for (path, old) in &prev.source_texts {
        let prepared = provider.prepared_source(path)?;
        if prepared.original().same_view(old) || prepared.original().as_str() == old.as_str() {
            continue;
        }
        if changed.len() == MAX_CHANGED_FILES {
            return None;
        }
        changed.push((path.clone(), prepared));
    }
    let mut plan = prev.clone();
    let mut regions = Vec::new();
    for (path, prepared) in changed {
        let occurrence = {
            let mut matching = prev
                .occurrences
                .iter()
                .enumerate()
                .filter(|(_, entry)| entry.path.as_ref() == &path);
            let (index, entry) = matching.next()?;
            if matching.next().is_some() || entry.suppressed || entry.parent.is_none() {
                return None;
            }
            index
        };
        if !path
            .extension()
            .is_some_and(|extension| extension.eq_ignore_ascii_case("dm"))
            || prev
                .occurrences
                .iter()
                .any(|entry| entry.parent == Some(occurrence))
        {
            return None;
        }
        let mut own = prev
            .regions
            .iter()
            .enumerate()
            .filter(|(_, region)| region.occurrence == occurrence);
        let (region_index, region) = own.next()?;
        if own.next().is_some()
            || region.manifest_source
            || !region.effects.is_empty()
            || region.segments.len() != 1
        {
            return None;
        }
        // The old text must have been directive free too, or its conditionals may have shaped
        // what follows.
        let old = PreparedSource::from_text(prev.source_texts.get(&path)?.clone());
        if !directive_free(&old) || !directive_free(&prepared) {
            return None;
        }
        let entry = &prev.occurrences[occurrence];
        entry.eof_cursor_line()?;
        entry.eof_cursor_encounter()?;
        let mut line_number = 0usize;
        let mut lines = Vec::with_capacity(prepared.lines().len());
        for index in 0..prepared.lines().len() {
            let logical = prepared.lines().get(index)?;
            line_number += logical.source_lines;
            lines.push(RegionLine {
                source_span: logical.source_span,
                source_line: logical.source_line,
                source_lines: logical.source_lines,
                text: SourceText::clone(logical.text),
            });
        }
        let target = &mut plan.regions[region_index];
        target.source_span = Span::new(0, prepared.original().len());
        if lines.is_empty() {
            target.segments.clear();
        } else {
            target.segments[0].lines = lines;
        }
        plan.occurrences[occurrence].eof_cursor_line = Some(line_number.checked_add(1)?);
        plan.source_line_starts
            .insert(path.clone(), prepared.line_starts().clone());
        plan.source_texts.insert(path, prepared.original().clone());
        regions.push(region_index);
    }
    Some(PlanEdit { plan, regions })
}

/// The previous expansion with the changed regions re-expanded, the joined text spliced and the
/// origin rows, receipts and offsets after each edit moved by its length delta; or `None`.
pub fn expand_regions_edit(
    prev: &ExpandedRegions,
    plan: &DirectivePlan,
    regions: &[usize],
    memo: &dyn ExpansionMemo,
) -> Option<ExpandedRegions> {
    if !prev.diagnostics.is_empty()
        || !prev.lexical_diagnostics.is_empty()
        || !plan.diagnostics.is_empty()
        || !prev.tokens.is_empty()
        || prev.receipts.len() != plan.emission_regions().count()
    {
        return None;
    }
    struct Replaced {
        receipt: usize,
        output: expansion::RegionOutput,
    }
    let mut replaced = Vec::with_capacity(regions.len());
    for &region in regions {
        let receipt = prev
            .receipts
            .iter()
            .position(|receipt| receipt.region == region)?;
        let output = region_memo::expand(plan, region, memo);
        if !output.diagnostics.is_empty() || output.receipt.is_none() {
            return None;
        }
        replaced.push(Replaced { receipt, output });
    }
    replaced.sort_by_key(|entry| entry.receipt);
    // Joined text and receipts, in emission order.
    let old_length = prev.text.len();
    let mut text = String::with_capacity(old_length + 4096);
    let mut cursor = 0usize;
    let mut receipts = Vec::with_capacity(prev.receipts.len());
    let mut shift = 0isize;
    let mut edits = Vec::with_capacity(replaced.len());
    let mut next = replaced.into_iter().peekable();
    for (index, receipt) in prev.receipts.iter().enumerate() {
        let (start, end) = (receipt.output.start, receipt.output.end);
        let new_start = usize::try_from(start as isize + shift).ok()?;
        if next.peek().is_some_and(|entry| entry.receipt == index) {
            let entry = next.next()?;
            text.push_str(prev.text.get(cursor..start)?);
            text.push_str(&entry.output.text);
            cursor = end;
            let delta = entry.output.text.len() as isize - (end - start) as isize;
            receipts.push(RegionReceipt {
                region: receipt.region,
                output: Span::new(new_start, new_start + entry.output.text.len()),
                record: entry.output.receipt?,
            });
            edits.push(origin_arena::RowEdit {
                region: receipt.region,
                old_start: start,
                new_start,
                delta,
                path: plan.occurrences[plan.regions[receipt.region].occurrence]
                    .path
                    .clone(),
                lines: entry.output.lines.into_iter().collect(),
            });
            shift += delta;
        } else {
            receipts.push(RegionReceipt {
                region: receipt.region,
                output: Span::new(new_start, usize::try_from(end as isize + shift).ok()?),
                record: Arc::clone(&receipt.record),
            });
        }
    }
    text.push_str(prev.text.get(cursor..)?);
    let origins = prev.origins.spliced(edits)?;
    Some(ExpandedRegions {
        text: SourceText::from(text),
        tokens: Vec::new(),
        origins,
        emission_regions: prev.emission_regions.clone(),
        diagnostics: Vec::new(),
        receipts,
        lexical_diagnostics: Vec::new(),
    })
}

/// Whether an edited expansion equals a full one (verification mode): the text, every origin row
/// field, the receipts' spans and the emission order.
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
        || a.receipts
            .iter()
            .zip(&b.receipts)
            .any(|(x, y)| x.region != y.region || x.output != y.output)
    {
        return Err("receipts differ".into());
    }
    if a.emission_regions != b.emission_regions || a.diagnostics.len() != b.diagnostics.len() {
        return Err("emission order or diagnostics differ".into());
    }
    Ok(())
}

fn same_environment(a: &MacroEnvironment, b: &MacroEnvironment) -> bool {
    if a.shares_storage_with(b) {
        return true;
    }
    if a.len() != b.len() {
        return false;
    }
    let collect = |environment: &MacroEnvironment| {
        let mut entries = BTreeMap::new();
        environment.visit_storage(|name, _, _, definition, origin| {
            entries.insert(
                name.to_string(),
                (format!("{definition:?}"), format!("{origin:?}")),
            );
        });
        entries
    };
    collect(a) == collect(b)
}

/// Whether an edited plan equals a full one (verification mode), over everything expansion and
/// the frontend read from it.
pub fn plans_equal(a: &DirectivePlan, b: &DirectivePlan, deep: &[usize]) -> Result<(), String> {
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
        for (s, t) in x.segments.iter().zip(&y.segments) {
            let environment = if deep.contains(&index) {
                same_environment(&s.macros, &t.macros)
            } else {
                // Every other region's environment is the previous plan's, shared by construction;
                // comparing millions of bindings per request would dwarf the edit.
                s.macros.len() == t.macros.len()
            };
            if s.lines.len() != t.lines.len() || !environment {
                return Err(format!("region {index} segment differs"));
            }
            for (l, m) in s.lines.iter().zip(&t.lines) {
                if l.source_span != m.source_span
                    || l.source_line != m.source_line
                    || l.text.as_str() != m.text.as_str()
                {
                    return Err(format!("region {index} line differs"));
                }
            }
        }
    }
    if a.occurrences.len() != b.occurrences.len() {
        return Err("occurrence count differs".into());
    }
    for (index, (x, y)) in a.occurrences.iter().zip(&b.occurrences).enumerate() {
        if x.path != y.path
            || x.parent != y.parent
            || x.suppressed != y.suppressed
            || x.directive_line != y.directive_line
            || x.eof_cursor_line() != y.eof_cursor_line()
            || x.eof_cursor_encounter() != y.eof_cursor_encounter()
            || x.semantic_path != y.semantic_path
        {
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
    {
        return Err("line starts, dependencies or file dirs differ".into());
    }
    Ok(())
}
