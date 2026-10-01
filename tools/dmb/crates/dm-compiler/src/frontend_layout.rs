//! Reuse structural chunk boundaries after a localized expanded-source edit.

use super::ParsedChunk;
use dm_syntax::Span;
use std::sync::Arc;

pub(super) struct LayoutEdit {
    pub before: Vec<(usize, Arc<ParsedChunk>)>,
    pub region: Span,
    pub after: Vec<(usize, Arc<ParsedChunk>)>,
    pub validation_bytes: usize,
}

/// Both reused sides are byte-identical to the previous snapshot. Rescanning
/// includes neighboring chunks, then verifies that the retained suffix still
/// begins at a genuine lexical declaration boundary. Edits opening comments,
/// strings or delimiters across that boundary conservatively use a full scan.
pub(super) fn edited_layout(
    old: &str,
    chunks: &[(usize, Arc<ParsedChunk>)],
    source: &str,
    limit: usize,
) -> Option<LayoutEdit> {
    if chunks.is_empty() {
        return None;
    }
    let prefix = old
        .as_bytes()
        .iter()
        .zip(source.as_bytes())
        .take_while(|(left, right)| left == right)
        .count();
    if prefix == old.len() && old.len() == source.len() {
        return Some(LayoutEdit {
            before: chunks.to_vec(),
            region: Span::new(source.len(), source.len()),
            after: Vec::new(),
            validation_bytes: 0,
        });
    }
    let suffix = old.as_bytes()[prefix..]
        .iter()
        .rev()
        .zip(source.as_bytes()[prefix..].iter().rev())
        .take_while(|(left, right)| left == right)
        .count();
    let old_end = old.len() - suffix;
    let first = chunks
        .partition_point(|(offset, chunk)| offset + chunk.source_len <= prefix)
        .saturating_sub(1);
    let last = (chunks.partition_point(|(offset, _)| *offset < old_end) + 1).min(chunks.len());
    let start = if first == 0 { 0 } else { chunks[first].0 };
    let old_region_end = chunks.get(last).map_or(old.len(), |(offset, _)| *offset);
    let shifted = |offset: usize| {
        if source.len() >= old.len() {
            offset.checked_add(source.len() - old.len())
        } else {
            offset.checked_sub(old.len() - source.len())
        }
    };
    let end = shifted(old_region_end)?;
    source.get(start..end)?;
    let mut validation_bytes = 0;
    if last < chunks.len() {
        let lookahead_end = shifted(chunks[last].0 + chunks[last].1.source_len)?;
        let lookahead = source.get(start..lookahead_end)?;
        validation_bytes = lookahead.len();
        let required = end - start;
        let mut boundary = false;
        let report =
            dm_syntax::for_each_source_chunk_with_limits(lookahead, 1, limit, |_, offset| {
                boundary |= offset == required
            });
        if !boundary || report.skipped_declarations != 0 {
            return None;
        }
    }
    let after: Option<Vec<_>> = chunks[last..]
        .iter()
        .map(|(offset, chunk)| shifted(*offset).map(|offset| (offset, Arc::clone(chunk))))
        .collect();
    Some(LayoutEdit {
        before: chunks[..first].to_vec(),
        region: Span::new(start, end),
        after: after?,
        validation_bytes,
    })
}
