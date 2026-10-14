//! One grouping rule for complete and resumed joined-stream grammar scans.
use crate::{
    audit::ChunkReport,
    boundary_scan::{scan_top_level_boundaries, BoundaryCheckpoint, BoundaryScanError},
    Span,
};
use std::ops::ControlFlow;
struct Group {
    start: usize,
    declaration_start: usize,
    count: usize,
    previous_boundary: Option<BoundaryCheckpoint>,
    limit: usize,
    maximum: usize,
}
impl Group {
    fn emit<B>(
        &self,
        source: &str,
        start: usize,
        end: usize,
        checkpoint: Option<BoundaryCheckpoint>,
        report: &mut ChunkReport,
        visit: &mut impl FnMut(&str, usize, Option<BoundaryCheckpoint>) -> ControlFlow<B>,
    ) -> ControlFlow<B> {
        if source[start..end].trim().is_empty() {
            return ControlFlow::Continue(());
        }
        report.parsed_chunks += 1;
        report.parsed_bytes += end - start;
        visit(&source[start..end], start, checkpoint)
    }
    fn boundary<B>(
        &mut self,
        source: &str,
        end: usize,
        checkpoint: Option<BoundaryCheckpoint>,
        report: &mut ChunkReport,
        visit: &mut impl FnMut(&str, usize, Option<BoundaryCheckpoint>) -> ControlFlow<B>,
    ) -> ControlFlow<B> {
        if end <= self.declaration_start {
            return ControlFlow::Continue(());
        }
        let declaration = &source[self.declaration_start..end];
        if declaration.len() > self.limit {
            if self.declaration_start > self.start {
                self.emit(
                    source,
                    self.start,
                    self.declaration_start,
                    self.previous_boundary,
                    report,
                    visit,
                )?;
            }
            report.skipped_declarations += 1;
            report.skipped_bytes += declaration.len();
            report
                .first_skipped_span
                .get_or_insert(Span::new(self.declaration_start, end));
            self.start = end;
            self.count = 0;
        } else {
            self.count += 1;
            // Fixed framing is a grouping rule, never cache authority.
            let header = declaration
                .lines()
                .find(|line| !line.trim().is_empty())
                .unwrap_or("");
            let hash = header.bytes().fold(0xcbf29ce484222325u64, |hash, byte| {
                (hash ^ u64::from(byte)).wrapping_mul(0x100000001b3)
            });
            if self.count >= self.maximum || hash & 15 == 0 {
                self.emit(source, self.start, end, checkpoint, report, visit)?;
                self.start = end;
                self.count = 0;
            }
        }
        self.declaration_start = end;
        self.previous_boundary = checkpoint;
        ControlFlow::Continue(())
    }
}
/// Restart only at a previously emitted chunk boundary with its issued scanner
/// checkpoint. There is no pending header/count there. EOF deliberately has no
/// checkpoint because an incomplete token cannot certify appended continuation.
pub fn scan_stable_source_chunks_from<B>(
    source: &str,
    start: BoundaryCheckpoint,
    max_declaration_bytes: usize,
    max_declarations: usize,
    mut visit: impl FnMut(&str, usize, Option<BoundaryCheckpoint>) -> ControlFlow<B>,
) -> Result<(ChunkReport, ControlFlow<B>), BoundaryScanError> {
    let mut report = ChunkReport::default();
    let mut group = Group {
        start: start.offset(),
        declaration_start: start.offset(),
        count: 0,
        previous_boundary: Some(start),
        limit: max_declaration_bytes.max(1),
        maximum: max_declarations.max(1),
    };
    let scanned = scan_top_level_boundaries(source, start, |checkpoint| {
        group.boundary(
            source,
            checkpoint.offset(),
            Some(checkpoint),
            &mut report,
            &mut visit,
        )
    })?;
    if let ControlFlow::Break(value) = scanned {
        return Ok((report, ControlFlow::Break(value)));
    }
    if let ControlFlow::Break(value) =
        group.boundary(source, source.len(), None, &mut report, &mut visit)
    {
        return Ok((report, ControlFlow::Break(value)));
    }
    if group.start < source.len() {
        if let ControlFlow::Break(value) = group.emit(
            source,
            group.start,
            source.len(),
            None,
            &mut report,
            &mut visit,
        ) {
            return Ok((report, ControlFlow::Break(value)));
        }
    }
    Ok((report, ControlFlow::Continue(())))
}

#[cfg(test)]
mod tests {
    use super::*;
    fn collect(
        source: &str,
        start: BoundaryCheckpoint,
        maximum: usize,
    ) -> Vec<(Span, Option<BoundaryCheckpoint>)> {
        let mut spans = Vec::new();
        let _ = scan_stable_source_chunks_from::<()>(
            source,
            start,
            source.len().max(1),
            maximum,
            |text, offset, end| {
                spans.push((Span::new(offset, offset + text.len()), end));
                ControlFlow::Continue(())
            },
        )
        .unwrap();
        spans
    }
    #[test]
    fn emitted_checkpoint_replays_the_same_grouping_suffix() {
        let source = (0..180)
            .map(|index| format!("/proc/p{index}()\n    return {index}\n"))
            .collect::<String>();
        let groups = collect(&source, BoundaryCheckpoint::default(), 32);
        assert!(groups.len() > 2);
        for (index, (_, end)) in groups.iter().enumerate() {
            if let Some(checkpoint) = end {
                assert_eq!(collect(&source, *checkpoint, 32), groups[index + 1..]);
            }
        }
        assert!(groups.last().unwrap().1.is_none());
        assert_eq!(
            groups
                .iter()
                .map(|(span, _)| &source[span.range()])
                .collect::<String>(),
            source
        );
    }
    #[test]
    fn single_declaration_groups_have_exact_root_spans_and_no_eof_checkpoint() {
        let a = "/proc/a()\n    return 1\n";
        let b = "/proc/b()\n    return 2\n";
        let source = format!("{a}{b}");
        let groups = collect(&source, BoundaryCheckpoint::default(), 1);
        assert_eq!(
            groups.iter().map(|(span, _)| *span).collect::<Vec<_>>(),
            [Span::new(0, a.len()), Span::new(a.len(), source.len())]
        );
        assert_eq!(groups[0].1.unwrap().offset(), a.len());
        assert!(groups[1].1.is_none());
    }
    #[test]
    fn oversize_and_empty_input_keep_existing_report_semantics() {
        let big = format!("/proc/big()\n    return \"{}\"\n", "x".repeat(200));
        let small = "/proc/small()\n    return 1\n";
        let source = format!("{big}{small}");
        let mut spans = Vec::new();
        let (report, status) = scan_stable_source_chunks_from::<()>(
            &source,
            BoundaryCheckpoint::default(),
            80,
            32,
            |text, offset, _| {
                spans.push(Span::new(offset, offset + text.len()));
                ControlFlow::Continue(())
            },
        )
        .unwrap();
        assert_eq!(status, ControlFlow::Continue(()));
        assert_eq!(report.skipped_declarations, 1);
        assert_eq!(report.skipped_bytes, big.len());
        assert_eq!(report.first_skipped_span, Some(Span::new(0, big.len())));
        assert_eq!(report.parsed_bytes, small.len());
        assert_eq!(spans, [Span::new(big.len(), source.len())]);
        let (empty, _) = scan_stable_source_chunks_from::<()>(
            "",
            BoundaryCheckpoint::default(),
            1,
            32,
            |_, _, _| panic!("empty source emitted a chunk"),
        )
        .unwrap();
        assert_eq!(empty.parsed_chunks, 0);
        assert_eq!(empty.skipped_declarations, 0);
    }
}
