//! Re-plan only the include subtrees whose files changed (doc/incremental_core.md, migration
//! step 3).
//!
//! When the provider can name the files that changed since the previous plan was made, every
//! include subtree no changed file belongs to is already planned: the previous plan is the answer
//! for it. Each changed subtree is planned again from the state its record says it started in; if
//! it ends in the same state, visits the same files and reads the same includes, nothing after it
//! can differ (early cutoff), and the new plan is the previous one with the subtrees replaced and
//! every later position renumbered. Otherwise the caller runs the ordered pass, which adopts what
//! it can subtree by subtree.
use super::*;
use std::collections::HashMap;
use std::ops::Range;

/// A changed subtree planned again, in the numbering of its own pass: occurrence 0 is a stand-in
/// for the parent, the subtree's root is 1; regions and items start at 0.
struct SubPlan {
    occurrences: Vec<IncludeOccurrence>,
    regions: Vec<IncludeRegion>,
    items: Vec<OrderedItem>,
    entries: Vec<TraceEntry>,
    /// For each region: the previous plan's region it copies (subtrees adopted inside).
    region_map: Vec<Option<usize>>,
    texts: BTreeMap<PathBuf, crate::SourceText>,
    line_starts: BTreeMap<PathBuf, Arc<[usize]>>,
    adopted: usize,
}

/// A subtree to replace: its extents in the previous plan, and what replaces it.
struct Segment {
    occurrences: Range<usize>,
    regions: Range<usize>,
    items: Range<usize>,
    entry: TraceEntry,
    sub: SubPlan,
}
impl Segment {
    fn new_occurrences(&self) -> usize {
        self.sub.occurrences.len() - 1
    }
    fn delta_occurrences(&self) -> isize {
        self.new_occurrences() as isize - self.occurrences.len() as isize
    }
    fn delta_regions(&self) -> isize {
        self.sub.regions.len() as isize - self.regions.len() as isize
    }
    fn delta_items(&self) -> isize {
        self.sub.items.len() as isize - self.items.len() as isize
    }
}

/// How many occurrences of its file the pass had created before each previous occurrence.
fn occurrence_numbers(previous: &DirectivePlan) -> Vec<u32> {
    let mut counts: HashMap<&Path, u32> = HashMap::with_capacity(previous.source_texts.len());
    previous
        .occurrences
        .iter()
        .map(|occurrence| {
            let count = counts.entry(occurrence.path.as_path()).or_insert(0);
            let number = *count;
            *count += 1;
            number
        })
        .collect()
}

pub(super) fn patch<P: SourceProvider>(
    provider: &P,
    memo: Option<&dyn ExpansionMemo>,
    previous: &DirectivePlan,
) -> Option<(DirectivePlan, PlanReuse)> {
    let started = std::time::Instant::now();
    let revision = previous.input_revision?;
    let changed = provider.changes_since(revision)?;
    let trace = previous.trace.as_ref()?;
    if !previous.diagnostics.is_empty()
        || !previous.warnings.is_empty()
        || previous.occurrences.is_empty()
        || changed.contains(previous.occurrences[0].path.as_path())
    {
        return None;
    }
    let numbers = occurrence_numbers(previous);
    // The subtree each changed source belongs to: its own, since a file's subtree is the file and
    // what it includes. A changed file inside another changed subtree is planned with it.
    let mut found: Vec<(usize, TraceEntry)> = Vec::new();
    let mut seen: HashMap<&Path, usize> = HashMap::new();
    for (index, occurrence) in previous.occurrences.iter().enumerate() {
        if occurrence.suppressed || !changed.contains(occurrence.path.as_path()) {
            continue;
        }
        // A changed file read twice (`#pragma multiple`) is planned by the ordered pass.
        if seen.insert(occurrence.path.as_path(), index).is_some() {
            return None;
        }
        let entry = trace.get(trace_key(occurrence.path.as_path(), numbers[index]))?;
        if entry.occurrence != index {
            return None;
        }
        found.push((index, entry.clone()));
    }
    found.sort_by_key(|(index, _)| *index);
    let mut outer: Vec<(usize, TraceEntry)> = Vec::new();
    let mut end = 0usize;
    for (index, entry) in found {
        if !outer.is_empty() && index < end {
            continue;
        }
        end = index + entry.record.occurrences;
        outer.push((index, entry));
    }
    let mut replan = std::time::Duration::ZERO;
    let mut segments = Vec::with_capacity(outer.len());
    for (index, entry) in outer {
        let began = std::time::Instant::now();
        let sub = replan_subtree(provider, memo, previous, &numbers, index, &entry)?;
        replan += began.elapsed();
        segments.push(Segment {
            occurrences: index..index + entry.record.occurrences,
            regions: entry.region..entry.region + entry.record.regions,
            items: entry.item..entry.item + entry.record.items,
            entry,
            sub,
        });
    }
    let assembling = std::time::Instant::now();
    let (mut plan, mut reuse) = assemble(previous, trace, segments)?;
    reuse.timings.replan = replan;
    reuse.timings.assemble = assembling.elapsed();
    reuse.timings.adopt = started.elapsed();
    plan.input_revision = provider.revision();
    Some((plan, reuse))
}

fn replan_subtree<P: SourceProvider>(
    provider: &P,
    memo: Option<&dyn ExpansionMemo>,
    previous: &DirectivePlan,
    numbers: &[u32],
    index: usize,
    entry: &TraceEntry,
) -> Option<SubPlan> {
    let record = &entry.record;
    let old_root = &previous.occurrences[index];
    let parent = old_root.parent?;
    let mut pass = DirectivePass::new(provider, memo, Some(previous), previous.project_dir.clone());
    // The subtree's root needs a parent to hang from; it takes no part in the result.
    let mut stand_in = previous.occurrences[parent].clone();
    stand_in.parent = None;
    stand_in.return_cursor = None;
    pass.plan.occurrences.push(stand_in);
    pass.nth.push(0);
    let mut root = old_root.clone();
    root.parent = Some(0);
    root.suppressed = false;
    root.eof_cursor_line = None;
    root.eof_cursor_encounter = None;
    root.return_cursor = None;
    pass.plan.occurrences.push(root);
    pass.nth.push(numbers[index]);
    // The occurrence counts the whole pass had when it reached this subtree.
    pass.occurrence_counts
        .insert(old_root.path.as_ref().clone(), numbers[index] + 1);
    for offset in 1..record.occurrences {
        let at = index + offset;
        pass.occurrence_counts
            .entry(previous.occurrences[at].path.as_ref().clone())
            .or_insert(numbers[at]);
    }
    pass.restore(&record.state_in);
    let mut first = BTreeSet::new();
    for visit in &record.visits {
        if first.insert(visit.path.as_ref()) && visit.was_visited {
            pass.visited.insert(visit.path.as_ref().clone());
        }
    }
    pass.visit_recording(1);
    let root_entry = pass.trace.iter().find(|entry| entry.occurrence == 1)?.clone();
    let new_record = &root_entry.record;
    let same_visits = new_record.visits.len() == record.visits.len()
        && new_record.visits.iter().zip(&record.visits).all(|(new, old)| {
            new.path == old.path
                && new.was_visited == old.was_visited
                && new.proceeded == old.proceeded
        });
    if !same_visits
        || !new_record.state_out.same(&record.state_out)
        || new_record.dependencies != record.dependencies
        || root_entry.key != entry.key
    {
        return None;
    }
    let adopted = pass.reuse.subtrees;
    Some(SubPlan {
        occurrences: pass.plan.occurrences,
        regions: pass.plan.regions,
        items: pass.plan.items,
        entries: pass.trace,
        region_map: pass.region_map,
        texts: pass.plan.source_texts,
        line_starts: pass.plan.source_line_starts,
        adopted,
    })
}

/// The previous plan with each replaced subtree swapped for its new one. A subtree planned again
/// from the same state, visiting the same files and reading the same includes has the same
/// number of occurrences, regions and ordered items (each is made by an include directive or a
/// file visit), so nothing else moves; any other result declines and the ordered pass runs.
fn assemble(
    previous: &DirectivePlan,
    trace: &PlanTrace,
    segments: Vec<Segment>,
) -> Option<(DirectivePlan, PlanReuse)> {
    if segments.iter().any(|segment| {
        segment.delta_occurrences() != 0 || segment.delta_regions() != 0 || segment.delta_items() != 0
    }) {
        return None;
    }
    let mut reuse = PlanReuse::default();
    let mut occurrences = previous.occurrences.clone();
    let mut regions = previous.regions.clone();
    let mut items = previous.items.clone();
    let mut region_map: Vec<Option<usize>> = (0..regions.len()).map(Some).collect();
    for segment in &segments {
        let (occurrence_base, region_base, item_base) = (
            segment.occurrences.start,
            segment.regions.start,
            segment.items.start,
        );
        // The root keeps the include context it had; the end-of-file cursor is the new one.
        let planned = &segment.sub.occurrences[1];
        let root = &mut occurrences[occurrence_base];
        root.eof_cursor_line = planned.eof_cursor_line;
        root.eof_cursor_encounter = planned.eof_cursor_encounter.map(|at| item_base + at);
        for (offset, planned) in segment.sub.occurrences[2..].iter().enumerate() {
            let mut copy = planned.clone();
            copy.parent = copy.parent.map(|parent| occurrence_base + parent - 1);
            if let Some(cursor) = &mut copy.return_cursor {
                cursor.parent_occurrence = occurrence_base + cursor.parent_occurrence - 1;
                cursor.encounter_ordinal = cursor.encounter_ordinal.map(|at| item_base + at);
            }
            copy.eof_cursor_encounter = copy.eof_cursor_encounter.map(|at| item_base + at);
            occurrences[occurrence_base + 1 + offset] = copy;
        }
        for (offset, (planned, copied)) in segment
            .sub
            .regions
            .iter()
            .zip(&segment.sub.region_map)
            .enumerate()
        {
            let mut copy = planned.clone();
            copy.occurrence = occurrence_base + copy.occurrence - 1;
            copy.encounter_ordinal += item_base;
            regions[region_base + offset] = copy;
            region_map[region_base + offset] = *copied;
        }
        for (offset, planned) in segment.sub.items.iter().enumerate() {
            items[item_base + offset] = match planned {
                OrderedItem::Text(index) => OrderedItem::Text(region_base + index),
                OrderedItem::NonText {
                    occurrence: at,
                    kind,
                } => OrderedItem::NonText {
                    occurrence: occurrence_base + at - 1,
                    kind: *kind,
                },
            };
        }
        reuse.subtrees += segment.sub.adopted;
    }
    // Trace entries: the previous ones outside the replaced subtrees stay as they are; the new
    // ones replace those inside.
    let mut entries: Vec<TraceEntry> = trace
        .entries
        .iter()
        .filter(|old| {
            !segments
                .iter()
                .any(|segment| segment.occurrences.contains(&old.occurrence))
        })
        .cloned()
        .collect();
    for segment in &segments {
        for planned in &segment.sub.entries {
            entries.push(TraceEntry {
                key: planned.key,
                occurrence: segment.occurrences.start + planned.occurrence - 1,
                region: segment.regions.start + planned.region,
                item: segment.items.start + planned.item,
                record: Arc::clone(&planned.record),
            });
        }
    }
    let mut source_texts = previous.source_texts.clone();
    let mut source_line_starts = previous.source_line_starts.clone();
    for segment in &segments {
        for (path, text) in &segment.sub.texts {
            source_texts.insert(path.clone(), text.clone());
        }
        for (path, starts) in &segment.sub.line_starts {
            source_line_starts.insert(path.clone(), starts.clone());
        }
    }
    reuse.replanned = segments.len();
    reuse.rebuilt_files = Some(
        segments
            .iter()
            .flat_map(|segment| segment.sub.texts.keys().cloned())
            .collect(),
    );
    reuse.copied_regions = region_map.iter().flatten().count();
    reuse.regions = region_map;
    Some((
        DirectivePlan {
            source_texts,
            occurrences,
            regions,
            items,
            dependencies: previous.dependencies.clone(),
            source_line_starts,
            diagnostics: Vec::new(),
            warnings: Vec::new(),
            diagnostic_ordinals: Vec::new(),
            final_macros: previous.final_macros.clone(),
            file_dirs: previous.file_dirs.clone(),
            project_dir: previous.project_dir.clone(),
            trace: Some(Arc::new(PlanTrace::new(entries))),
            input_revision: None,
        },
        reuse,
    ))
}
