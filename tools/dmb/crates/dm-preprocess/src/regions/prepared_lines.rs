//! Compact immutable logical-line coordinates, with exact wide fallback.
use super::PreparedLine;
use crate::SourceText;
use dm_syntax::Span;
use std::{fmt, ops::Range, sync::Arc};

#[derive(Clone, Debug)]
pub(super) struct CompactLine {
    start: u32,
    end: u32,
    line: u32,
    count: u32,
    text: SourceText,
}
impl CompactLine {
    fn into_wide(self) -> PreparedLine {
        PreparedLine {
            source_span: Span::new(self.start as usize, self.end as usize),
            source_line: self.line as usize,
            source_lines: self.count as usize,
            text: self.text,
        }
    }
}
#[derive(Clone, Debug)]
pub(super) enum LineStorage {
    Compact(Arc<[CompactLine]>),
    Wide(Arc<[PreparedLine]>),
}
impl LineStorage {
    pub(super) fn from_lines(lines: impl IntoIterator<Item = PreparedLine>) -> Self {
        let lines = lines.into_iter();
        let mut compact = Vec::with_capacity(lines.size_hint().0);
        let mut wide: Option<Vec<PreparedLine>> = None;
        for line in lines {
            if let Some(wide) = &mut wide {
                wide.push(line);
                continue;
            }
            let coordinates = [
                line.source_span.start,
                line.source_span.end,
                line.source_line,
                line.source_lines,
            ]
            .map(u32::try_from);
            if let [Ok(start), Ok(end), Ok(source_line), Ok(count)] = coordinates {
                compact.push(CompactLine {
                    start,
                    end,
                    line: source_line,
                    count,
                    text: line.text,
                });
            } else {
                let mut promoted = Vec::with_capacity(compact.capacity());
                promoted.extend(
                    std::mem::take(&mut compact)
                        .into_iter()
                        .map(CompactLine::into_wide),
                );
                promoted.push(line);
                wide = Some(promoted);
            }
        }
        match wide {
            Some(lines) => Self::Wide(lines.into()),
            None => Self::Compact(compact.into()),
        }
    }
    pub(super) fn view(&self) -> PreparedLines<'_> {
        let len = match self {
            Self::Compact(lines) => lines.len(),
            Self::Wide(lines) => lines.len(),
        };
        PreparedLines {
            storage: self,
            start: 0,
            end: len,
        }
    }
}
#[derive(Clone, Copy, Debug)]
pub struct PreparedLineView<'a> {
    pub source_span: Span,
    pub source_line: usize,
    pub source_lines: usize,
    pub text: &'a SourceText,
}
/// Borrowed logical-line range; taking a subrange never materializes records.
#[derive(Clone, Copy)]
pub struct PreparedLines<'a> {
    storage: &'a LineStorage,
    start: usize,
    end: usize,
}
impl fmt::Debug for PreparedLines<'_> {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_list().entries(self.iter()).finish()
    }
}
impl<'a> PreparedLines<'a> {
    pub fn len(self) -> usize {
        self.end - self.start
    }
    pub fn is_empty(self) -> bool {
        self.start == self.end
    }
    pub fn get(self, index: usize) -> Option<PreparedLineView<'a>> {
        if index >= self.len() {
            return None;
        }
        let index = self.start + index;
        Some(match self.storage {
            LineStorage::Compact(lines) => {
                let line = &lines[index];
                PreparedLineView {
                    source_span: Span::new(line.start as usize, line.end as usize),
                    source_line: line.line as usize,
                    source_lines: line.count as usize,
                    text: &line.text,
                }
            }
            LineStorage::Wide(lines) => {
                let line = &lines[index];
                PreparedLineView {
                    source_span: line.source_span,
                    source_line: line.source_line,
                    source_lines: line.source_lines,
                    text: &line.text,
                }
            }
        })
    }
    pub fn first(self) -> Option<PreparedLineView<'a>> {
        self.get(0)
    }
    pub fn last(self) -> Option<PreparedLineView<'a>> {
        self.len().checked_sub(1).and_then(|index| self.get(index))
    }
    pub fn slice(self, range: Range<usize>) -> Self {
        assert!(
            range.start <= range.end && range.end <= self.len(),
            "prepared line range out of bounds"
        );
        Self {
            storage: self.storage,
            start: self.start + range.start,
            end: self.start + range.end,
        }
    }
    pub fn iter(self) -> PreparedLineIter<'a> {
        PreparedLineIter { lines: self }
    }
}
pub struct PreparedLineIter<'a> {
    lines: PreparedLines<'a>,
}
impl<'a> Iterator for PreparedLineIter<'a> {
    type Item = PreparedLineView<'a>;
    fn next(&mut self) -> Option<Self::Item> {
        let first = self.lines.first()?;
        self.lines.start += 1;
        Some(first)
    }
    fn size_hint(&self) -> (usize, Option<usize>) {
        let len = self.lines.len();
        (len, Some(len))
    }
}
impl DoubleEndedIterator for PreparedLineIter<'_> {
    fn next_back(&mut self) -> Option<Self::Item> {
        let last = self.lines.last()?;
        self.lines.end -= 1;
        Some(last)
    }
}
impl ExactSizeIterator for PreparedLineIter<'_> {}
impl std::iter::FusedIterator for PreparedLineIter<'_> {}
impl<'a> IntoIterator for PreparedLines<'a> {
    type Item = PreparedLineView<'a>;
    type IntoIter = PreparedLineIter<'a>;
    fn into_iter(self) -> Self::IntoIter {
        self.iter()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    fn line(start: usize, end: usize, source_line: usize, count: usize) -> PreparedLine {
        PreparedLine {
            source_span: Span::new(start, end),
            source_line,
            source_lines: count,
            text: SourceText::from("same shared text"),
        }
    }
    #[test]
    fn compact_ranges_preserve_coordinates_text_and_bidirectional_iteration() {
        let first = line(0, 7, 1, 2);
        let original = first.text.clone();
        let storage = LineStorage::from_lines([first, line(7, 12, 3, 1), line(12, 19, 4, 2)]);
        assert!(matches!(storage, LineStorage::Compact(_)));
        #[cfg(target_pointer_width = "64")]
        assert_eq!(
            std::mem::size_of::<PreparedLine>() - std::mem::size_of::<CompactLine>(),
            16
        );
        let lines = storage.view();
        assert!(lines.first().unwrap().text.shares_backing(&original));
        assert!(lines.get(usize::MAX).is_none());
        let mut range = lines.slice(1..3).iter();
        assert_eq!(range.len(), 2);
        assert_eq!(range.next_back().unwrap().source_span, Span::new(12, 19));
        assert_eq!(range.next().unwrap().source_line, 3);
        assert!(range.next().is_none());
        assert!(range.next_back().is_none());
        assert!(lines.slice(2..2).is_empty());
    }
    #[test]
    fn every_coordinate_overflow_promotes_prior_and_future_lines_exactly() {
        for slot in 0..4 {
            let mut coordinates = [7, 12, 3, 1];
            coordinates[slot] = usize::MAX;
            let storage = LineStorage::from_lines([
                line(0, 7, 1, 2),
                line(
                    coordinates[0],
                    coordinates[1],
                    coordinates[2],
                    coordinates[3],
                ),
                line(12, 19, 4, 2),
            ]);
            assert!(matches!(storage, LineStorage::Wide(_)));
            let lines = storage.view();
            assert_eq!(lines.first().unwrap().source_span, Span::new(0, 7));
            let wide = lines.get(1).unwrap();
            assert_eq!(
                [
                    wide.source_span.start,
                    wide.source_span.end,
                    wide.source_line,
                    wide.source_lines
                ],
                coordinates
            );
            assert_eq!(lines.last().unwrap().source_line, 4);
        }
    }
}
