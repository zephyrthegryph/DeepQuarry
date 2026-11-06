//! Transient region provenance: compact coordinates, sparse primary token receipts.
use super::MacroExpansion;
use dm_syntax::Span;
use std::sync::Arc;
type Trace = Arc<Box<[MacroExpansion]>>;
pub(in crate::regions) type Line = (Span, usize, Span, Trace);
#[derive(Debug)]
pub(in crate::regions) struct CompactLine {
    output_start: u32,
    output_end: u32,
    source_line: u32,
    source_start: u32,
    source_end: u32,
    traces: Trace,
    single_physical_macro_line: bool,
}
impl CompactLine {
    fn into_line(self) -> Line {
        (
            Span::new(self.output_start as usize, self.output_end as usize),
            self.source_line as usize,
            Span::new(self.source_start as usize, self.source_end as usize),
            self.traces,
        )
    }
    fn view(&self) -> (Span, usize, Span, &Trace) {
        (
            Span::new(self.output_start as usize, self.output_end as usize),
            self.source_line as usize,
            Span::new(self.source_start as usize, self.source_end as usize),
            &self.traces,
        )
    }
}
/// One sparse entry per direct macro line, not one allocation/index per source line.
/// None means the native issuer ran but declined the transform (no retry loops).
#[derive(Debug)]
pub(in crate::regions) struct MacroRowPoints {
    row: usize,
    points: Option<Arc<[crate::macro_expansion::MacroBytePoint]>>,
}
pub(in crate::regions) enum OutputLineBuilder {
    Compact(Vec<CompactLine>),
    Certified {
        lines: Vec<CompactLine>,
        points: Vec<MacroRowPoints>,
    },
    Wide(Vec<Line>),
}
impl Default for OutputLineBuilder {
    fn default() -> Self {
        Self::Compact(Vec::new())
    }
}
impl OutputLineBuilder {
    pub(in crate::regions) fn with_capacity(capacity: usize) -> Self {
        Self::Compact(Vec::with_capacity(capacity))
    }
    pub(in crate::regions) fn finish(self) -> OutputLines {
        match self {
            Self::Compact(lines) => OutputLines::Compact(lines.into_boxed_slice()),
            Self::Certified { lines, points } => OutputLines::Certified {
                lines: lines.into_boxed_slice(),
                points: points.into_boxed_slice(),
            },
            Self::Wide(lines) => OutputLines::Wide(lines.into_boxed_slice()),
        }
    }
    pub(in crate::regions) fn push(&mut self, line: Line) {
        self.push_with_single_macro_line(line, false);
    }
    pub(in crate::regions) fn push_with_single_macro_line(&mut self, line: Line, single: bool) {
        self.push_with_macro_points(line, single, false, None);
    }
    pub(in crate::regions) fn push_with_macro_points(
        &mut self,
        line: Line,
        single: bool,
        issued: bool,
        proof: Option<Arc<[crate::macro_expansion::MacroBytePoint]>>,
    ) {
        if let Self::Wide(lines) = self {
            lines.push(line);
            return;
        }
        let coordinates =
            [line.0.start, line.0.end, line.1, line.2.start, line.2.end].map(u32::try_from);
        if let [Ok(output_start), Ok(output_end), Ok(source_line), Ok(source_start), Ok(source_end)] =
            coordinates
        {
            if issued && matches!(self, Self::Compact(_)) {
                let Self::Compact(lines) = std::mem::take(self) else {
                    unreachable!()
                };
                *self = Self::Certified {
                    lines,
                    points: Vec::new(),
                };
            }
            let lines = match self {
                Self::Compact(lines) | Self::Certified { lines, .. } => lines,
                Self::Wide(_) => unreachable!(),
            };
            let row = lines.len();
            lines.push(CompactLine {
                output_start,
                output_end,
                source_line,
                source_start,
                source_end,
                traces: line.3,
                single_physical_macro_line: single,
            });
            if issued {
                if let Self::Certified { points, .. } = self {
                    points.push(MacroRowPoints { row, points: proof });
                }
            }
        } else {
            let previous = match std::mem::take(self) {
                Self::Compact(lines) | Self::Certified { lines, .. } => lines,
                Self::Wide(_) => unreachable!(),
            };
            let mut wide = Vec::with_capacity(previous.capacity());
            wide.extend(previous.into_iter().map(CompactLine::into_line));
            wide.push(line);
            *self = Self::Wide(wide);
        }
    }
}
#[derive(Debug)]
pub(in crate::regions) enum OutputLines {
    Compact(Box<[CompactLine]>),
    Certified {
        lines: Box<[CompactLine]>,
        points: Box<[MacroRowPoints]>,
    },
    Wide(Box<[Line]>),
}
impl Default for OutputLines {
    fn default() -> Self {
        Self::Compact(Box::new([]))
    }
}
impl OutputLines {
    pub(in crate::regions) fn len(&self) -> usize {
        match self {
            Self::Compact(lines) | Self::Certified { lines, .. } => lines.len(),
            Self::Wide(lines) => lines.len(),
        }
    }
    pub(in crate::regions) fn view(&self, index: usize) -> (Span, usize, Span, &Trace) {
        match self {
            Self::Compact(lines) | Self::Certified { lines, .. } => lines[index].view(),
            Self::Wide(lines) => {
                let line = &lines[index];
                (line.0, line.1, line.2, &line.3)
            }
        }
    }
    pub(in crate::regions) fn single_physical_macro_line(&self, index: usize) -> bool {
        match self {
            Self::Compact(lines) | Self::Certified { lines, .. } => lines
                .get(index)
                .is_some_and(|l| l.single_physical_macro_line),
            Self::Wide(_) => false,
        }
    }
    fn point_entry(&self, index: usize) -> Option<&MacroRowPoints> {
        let Self::Certified { points, .. } = self else {
            return None;
        };
        points
            .binary_search_by_key(&index, |p| p.row)
            .ok()
            .map(|i| &points[i])
    }
    pub(in crate::regions) fn macro_points(
        &self,
        index: usize,
    ) -> Option<&Arc<[crate::macro_expansion::MacroBytePoint]>> {
        self.point_entry(index)?.points.as_ref()
    }
    pub(in crate::regions) fn needs_macro_point_issuance(&self) -> bool {
        (0..self.len()).any(|i| !self.view(i).3.is_empty() && self.point_entry(i).is_none())
    }
    pub(in crate::regions) fn visit_owned_storage(
        &self,
        mut visit: impl FnMut(usize, usize, usize),
    ) {
        match self {
            Self::Compact(lines) | Self::Certified { lines, .. } => visit(
                lines.as_ptr() as usize,
                lines.len(),
                std::mem::size_of_val(lines.as_ref()),
            ),
            Self::Wide(lines) => visit(
                lines.as_ptr() as usize,
                lines.len(),
                std::mem::size_of_val(lines.as_ref()),
            ),
        }
        if let Self::Certified { points, .. } = self {
            visit(
                points.as_ptr() as usize,
                points.len(),
                std::mem::size_of_val(points.as_ref()),
            );
            for proof in points.iter().filter_map(|p| p.points.as_ref()) {
                visit(
                    proof.as_ptr() as usize,
                    proof.len(),
                    std::mem::size_of_val(proof.as_ref()),
                );
            }
        }
    }
    pub(in crate::regions) fn output_end(&self) -> usize {
        self.iter().map(|(span, ..)| span.end).max().unwrap_or(0)
    }
    /// Rebind only primary-issued provenance after exact logical row/trace
    /// validation. The receiving rows retain their record-owned Arc strings
    /// and freshly hydrated CURRENT definition origins, never the issuer's
    /// incidental name/chain allocations. No text search or scalar proof.
    pub(in crate::regions) fn with_issued_provenance_from(&self, issued: &Self) -> Option<Self> {
        if self.len() != issued.len()
            || !self.iter().zip(issued.iter()).all(|(a, b)| {
                a.0 == b.0 && a.1 == b.1 && a.2 == b.2 && (Arc::ptr_eq(a.3, b.3) || a.3 == b.3)
            })
        {
            return None;
        }
        let mut result = OutputLineBuilder::with_capacity(self.len());
        for (i, (output, line, source, traces)) in self.iter().enumerate() {
            result.push_with_macro_points(
                (output, line, source, Arc::clone(traces)),
                issued.single_physical_macro_line(i),
                issued.point_entry(i).is_some(),
                issued.macro_points(i).cloned(),
            );
        }
        Some(result.finish())
    }
    pub(in crate::regions) fn same_rows(&self, other: &Self) -> bool {
        self.len() == other.len()
            && self
                .iter()
                .zip(other.iter())
                .enumerate()
                .all(|(i, (a, b))| {
                    self.single_physical_macro_line(i) == other.single_physical_macro_line(i)
                        && a.0 == b.0
                        && a.1 == b.1
                        && a.2 == b.2
                        && (Arc::ptr_eq(a.3, b.3) || a.3 == b.3)
                })
    }
    pub(in crate::regions) fn iter(
        &self,
    ) -> impl ExactSizeIterator<Item = (Span, usize, Span, &Trace)> + DoubleEndedIterator {
        (0..self.len()).map(|i| self.view(i))
    }
}
pub(in crate::regions) enum IntoLines {
    Compact(std::vec::IntoIter<CompactLine>),
    Wide(std::vec::IntoIter<Line>),
}
impl Iterator for IntoLines {
    type Item = Line;
    fn next(&mut self) -> Option<Line> {
        match self {
            Self::Compact(lines) => lines.next().map(CompactLine::into_line),
            Self::Wide(lines) => lines.next(),
        }
    }
    fn size_hint(&self) -> (usize, Option<usize>) {
        match self {
            Self::Compact(lines) => lines.size_hint(),
            Self::Wide(lines) => lines.size_hint(),
        }
    }
}
impl ExactSizeIterator for IntoLines {}
impl IntoIterator for OutputLines {
    type Item = Line;
    type IntoIter = IntoLines;
    fn into_iter(self) -> IntoLines {
        match self {
            Self::Compact(lines) | Self::Certified { lines, .. } => {
                IntoLines::Compact(lines.into_vec().into_iter())
            }
            Self::Wide(lines) => IntoLines::Wide(lines.into_vec().into_iter()),
        }
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn compact_and_each_wide_coordinate_preserve_order_and_shared_trace() {
        let trace = Arc::new(Vec::new().into_boxed_slice());
        for overflow in 0..=5 {
            let mut builder = OutputLineBuilder::with_capacity(10);
            let first = (Span::new(0, 7), 1, Span::new(10, 17), Arc::clone(&trace));
            builder.push(first.clone());
            let mut coordinates = [7, 12, 2, 17, 22];
            if overflow < 5 {
                coordinates[overflow] = usize::MAX;
            }
            let middle = (
                Span::new(coordinates[0], coordinates[1]),
                coordinates[2],
                Span::new(coordinates[3], coordinates[4]),
                Arc::clone(&trace),
            );
            builder.push(middle.clone());
            let last = (Span::new(12, 19), 3, Span::new(22, 29), Arc::clone(&trace));
            builder.push(last.clone());
            let lines = builder.finish();
            match &lines {
                OutputLines::Compact(records) | OutputLines::Certified { lines: records, .. } => {
                    assert_eq!(records.len(), 3)
                }
                OutputLines::Wide(records) => assert_eq!(records.len(), 3),
            }
            assert_eq!(matches!(lines, OutputLines::Compact(_)), overflow == 5);
            assert!(lines
                .iter()
                .all(|(_, _, _, actual)| Arc::ptr_eq(actual, &trace)));
            let actual = lines.into_iter().collect::<Vec<_>>();
            let expected = [first, middle, last];
            assert_eq!(actual.len(), expected.len());
            for (actual, expected) in actual.iter().zip(&expected) {
                assert_eq!(
                    (actual.0, actual.1, actual.2),
                    (expected.0, expected.1, expected.2)
                );
                assert!(Arc::ptr_eq(&actual.3, &expected.3));
            }
        }
        #[cfg(target_pointer_width = "64")]
        assert_eq!(
            std::mem::size_of::<Line>() - std::mem::size_of::<CompactLine>(),
            16
        );
    }
}
