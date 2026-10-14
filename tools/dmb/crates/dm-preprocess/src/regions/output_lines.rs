//! Transient region provenance: checked compact coordinates and exact fallback.
use super::MacroExpansion;
use dm_syntax::Span;
use std::sync::Arc;
type Trace = Arc<Vec<MacroExpansion>>;
pub(in crate::regions) type Line = (Span, usize, Span, Trace);
pub(in crate::regions) struct CompactLine {
    output_start: u32,
    output_end: u32,
    source_line: u32,
    source_start: u32,
    source_end: u32,
    traces: Trace,
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
pub(in crate::regions) enum OutputLineBuilder {
    Compact(Vec<CompactLine>),
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
            Self::Wide(lines) => OutputLines::Wide(lines.into_boxed_slice()),
        }
    }
    pub(in crate::regions) fn push(&mut self, line: Line) {
        if let Self::Wide(lines) = self {
            lines.push(line);
            return;
        }
        let coordinates =
            [line.0.start, line.0.end, line.1, line.2.start, line.2.end].map(u32::try_from);
        if let [Ok(output_start), Ok(output_end), Ok(source_line), Ok(source_start), Ok(source_end)] =
            coordinates
        {
            if let Self::Compact(lines) = self {
                lines.push(CompactLine {
                    output_start,
                    output_end,
                    source_line,
                    source_start,
                    source_end,
                    traces: line.3,
                });
            }
        } else {
            let Self::Compact(previous) = std::mem::take(self) else {
                unreachable!()
            };
            let mut wide = Vec::with_capacity(previous.capacity());
            wide.extend(previous.into_iter().map(CompactLine::into_line));
            wide.push(line);
            *self = Self::Wide(wide);
        }
    }
}
pub(in crate::regions) enum OutputLines {
    Compact(Box<[CompactLine]>),
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
            Self::Compact(lines) => lines.len(),
            Self::Wide(lines) => lines.len(),
        }
    }
    pub(in crate::regions) fn iter(
        &self,
    ) -> impl ExactSizeIterator<Item = (Span, usize, Span, &Trace)> + DoubleEndedIterator {
        (0..self.len()).map(|index| match self {
            Self::Compact(lines) => lines[index].view(),
            Self::Wide(lines) => {
                let line = &lines[index];
                (line.0, line.1, line.2, &line.3)
            }
        })
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
            Self::Compact(lines) => IntoLines::Compact(lines.into_vec().into_iter()),
            Self::Wide(lines) => IntoLines::Wide(lines.into_vec().into_iter()),
        }
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn compact_and_each_wide_coordinate_preserve_order_and_shared_trace() {
        let trace = Arc::new(Vec::new());
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
                OutputLines::Compact(records) => assert_eq!(records.len(), 3),
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
