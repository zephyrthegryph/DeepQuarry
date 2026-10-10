//! Changed-output restart and suffix convergence over the shared scanner.
use super::{GrammarAnswer, GrammarDescriptors};
use dm_syntax::scan_stable_source_chunks_from;
use std::ops::ControlFlow;
pub(super) struct ScanResult {
    pub(super) descriptors: GrammarDescriptors,
    pub(super) reused: usize,
    pub(super) scanned_bytes: usize,
}
fn common_bytes(source: &str, old: &GrammarAnswer) -> Option<(usize, usize, usize)> {
    let records = old.pieces()?;
    let old_len = records
        .iter()
        .try_fold(0usize, |sum, value| sum.checked_add(value.len()))?;
    let mut prefix = 0usize;
    for record in records.iter() {
        let current = source.as_bytes().get(prefix..)?;
        let bytes = record.as_bytes();
        if current.get(..bytes.len()) == Some(bytes) {
            prefix += bytes.len();
            continue;
        }
        let count = current
            .iter()
            .zip(bytes)
            .take_while(|(a, b)| a == b)
            .count();
        prefix += count;
        if count != bytes.len() {
            break;
        }
    }
    let maximum = (source.len() - prefix).min(old_len - prefix);
    let mut suffix = 0usize;
    for record in records.iter().rev() {
        let bytes = record.as_bytes();
        let limit = bytes.len().min(maximum - suffix);
        let end = source.len() - suffix;
        let current = &source.as_bytes()[end - limit..end];
        let old = &bytes[bytes.len() - limit..];
        let count = if current == old {
            limit
        } else {
            current
                .iter()
                .rev()
                .zip(old.iter().rev())
                .take_while(|(a, b)| a == b)
                .count()
        };
        suffix += count;
        if suffix == maximum || count != record.len() {
            break;
        }
    }
    Some((prefix, suffix, old_len))
}
pub(super) fn build(
    source: &str,
    previous: Option<(&GrammarDescriptors, &GrammarAnswer)>,
) -> Result<ScanResult, &'static str> {
    let proof = previous.and_then(|(descriptors, answer)| {
        if descriptors.spans.len() != descriptors.starts.len() {
            return None;
        }
        let (prefix, suffix, len) = common_bytes(source, answer)?;
        (len == descriptors.source_len).then_some((descriptors, prefix, suffix, len))
    });
    let restart = proof.map_or(0, |(old, prefix, _, _)| {
        old.spans
            .partition_point(|&(offset, _)| offset <= prefix)
            .saturating_sub(1)
    });
    let start = proof
        .and_then(|(old, _, _, _)| old.starts.get(restart).copied())
        .unwrap_or_default();
    let mut spans = proof.map_or_else(Vec::new, |(old, _, _, _)| old.spans[..restart].to_vec());
    let mut starts = proof.map_or_else(Vec::new, |(old, _, _, _)| old.starts[..restart].to_vec());
    let mut current_start = start;
    let mut stop = None;
    let (report, status) = scan_stable_source_chunks_from(
        source,
        start,
        source.len().max(1),
        32,
        |text, offset, end| {
            spans.push((offset, text.len()));
            starts.push(current_start);
            if let Some(end) = end {
                current_start = end;
                if let Some((old, _, suffix, old_len)) = proof {
                    let new_suffix = source.len() - suffix;
                    let old_suffix = old_len - suffix;
                    if end.offset() >= new_suffix {
                        if let Some(mapped) = end
                            .offset()
                            .checked_sub(new_suffix)
                            .and_then(|relative| old_suffix.checked_add(relative))
                        {
                            if let Ok(index) = old
                                .spans
                                .binary_search_by_key(&mapped, |&(offset, _)| offset)
                            {
                                if old.starts[index].at_offset(end.offset()) == end {
                                    stop = Some((index, old_suffix, new_suffix));
                                    return ControlFlow::Break(());
                                }
                            }
                        }
                    }
                }
            }
            ControlFlow::Continue(())
        },
    )
    .map_err(|_| "invalid grammar restart checkpoint")?;
    if report.skipped_declarations != 0 {
        return Err("grammar chunker omitted a declaration");
    }
    let mut reused = restart;
    let scanned_bytes = match status {
        ControlFlow::Continue(()) => source.len() - start.offset(),
        ControlFlow::Break(()) => current_start.offset() - start.offset(),
    };
    if let (Some((old, _, _, _)), Some((index, old_suffix, new_suffix))) = (proof, stop) {
        for (&(offset, len), checkpoint) in old.spans[index..].iter().zip(&old.starts[index..]) {
            let mapped = offset
                .checked_sub(old_suffix)
                .and_then(|relative| new_suffix.checked_add(relative))
                .ok_or("grammar suffix offset overflow")?;
            let end = mapped
                .checked_add(len)
                .ok_or("grammar suffix span overflow")?;
            if source.get(mapped..end).is_none() {
                return Err("grammar suffix is outside current source");
            }
            spans.push((mapped, len));
            starts.push(checkpoint.at_offset(mapped));
        }
        reused += old.spans.len() - index;
    }
    Ok(ScanResult {
        descriptors: GrammarDescriptors {
            spans,
            starts,
            source_len: source.len(),
            reused: 0,
            scanned_bytes: 0,
        },
        reused,
        scanned_bytes,
    })
}
