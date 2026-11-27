//! Which declarations of this revision take their origin from the previous revision (doc/retained_frontend.md, "Front end
//! edit floor").
//!
//! A region the plan copied verbatim (`PlanReuse::regions`) has the same source text, the same span in the same file and the
//! same macro environment as the previous region it copies, and its expansion is the same text. Its declarations are then the
//! previous region's declarations, in the same order and at the same offsets inside the region's output, and each one's
//! origin (source span, region hash, macro trace) is the previous one; only the include occurrence is this plan's. Regions are
//! assigned to declarations by walking the declaration starts beside the region outputs (both in output order), so no origin
//! row is looked up for them. A region whose declarations do not line up with the previous region's one for one (a
//! declaration that starts in it changed, or a declaration from the edited region runs into it) is looked up as before.
use super::*;

/// For every declaration (by index, `spans` in output order): `Some((region, previous declaration))` when its origin is the
/// previous revision's. `None` overall when the starts are not in output order.
pub(super) fn plan(
    base: &ColdFrontend,
    copies: &[Option<usize>],
    receipts: &[dm_preprocess::regions::region_memo::RegionReceipt],
    spans: &[dm_ir::Span],
) -> Option<Vec<Option<(usize, u32)>>> {
    if spans.windows(2).any(|pair| pair[0].start > pair[1].start)
        || base.declaration_starts.len() != base.declaration_regions.len()
    {
        return None;
    }
    // The previous revision: where each region's output starts, and its declarations (contiguous, in output order).
    let mut previous_output = vec![None; base.plan.regions.len()];
    for receipt in &base.expanded.receipts {
        *previous_output.get_mut(receipt.region())? = Some(receipt.output_span().start);
    }
    let mut previous_first = vec![u32::MAX; base.plan.regions.len()];
    let mut previous_count = vec![0u32; base.plan.regions.len()];
    for (index, &region) in base.declaration_regions.iter().enumerate() {
        let region = region as usize;
        if previous_first[region] == u32::MAX {
            previous_first[region] = index as u32;
        }
        previous_count[region] += 1;
    }
    // This revision: each declaration's region (the first output that ends after its start, as the origin rows answer),
    // its ordinal inside the region and its offset from the region's output start.
    let mut placed = Vec::with_capacity(spans.len());
    let mut count = vec![0u32; copies.len()];
    let mut receipt = 0usize;
    for start in spans.iter().map(|span| span.start as usize) {
        while receipt + 1 < receipts.len() && receipts[receipt].output_span().end <= start {
            receipt += 1;
        }
        let Some(current) = receipts.get(receipt) else {
            placed.push(None);
            continue;
        };
        let output = current.output_span();
        if start < output.start || start >= output.end {
            placed.push(None);
            continue;
        }
        let region = current.region();
        let ordinal = *count.get(region)?;
        count[region] += 1;
        placed.push(Some((region, ordinal, start - output.start)));
    }
    Some(
        placed
            .into_iter()
            .map(|placed| {
                let (region, ordinal, offset) = placed?;
                let old = copies.get(region).copied().flatten()?;
                if previous_count.get(old) != Some(&count[region]) || previous_first[old] == u32::MAX {
                    return None;
                }
                let index = previous_first[old] + ordinal;
                let previous_start = *base.declaration_starts.get(index as usize)? as usize;
                (previous_start.checked_sub(previous_output[old]?) == Some(offset)).then_some((region, index))
            })
            .collect(),
    )
}
