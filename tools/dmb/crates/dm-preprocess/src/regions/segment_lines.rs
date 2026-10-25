//! The active text lines of one expansion segment, named by index into their prepared source.
//!
//! A segment used to own a copy of every logical line it covers (56 bytes each: span, line numbers and a text view), which
//! made the directive plan one of the largest per-session owners: millions of lines, held again by every session and variant
//! that planned the same files. The lines are exactly lines of the file's prepared source (shared across sessions by
//! `prepared_source::shared_prepared`), so a segment keeps that source and the runs of consecutive line indexes it took
//! (conditional directives and inactive text break a run). Reading a line is a lookup in the shared table, not a copy.
use super::prepared_source::{PreparedLineView, PreparedSource};
use super::RegionLine;
use std::sync::Arc;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(super) struct LineRun {
    start: u32,
    end: u32,
}
/// The lines of one segment: indexes into a prepared source, as runs (what a pass makes), or owned lines.
#[derive(Clone, Debug)]
pub struct SegmentLines(Repr);
#[derive(Clone, Debug)]
enum Repr {
    Indexed {
        source: Arc<PreparedSource>,
        runs: Arc<[LineRun]>,
        len: usize,
    },
    /// Lines that are not (all) lines of one prepared source; only constructed by tests.
    #[cfg_attr(not(test), allow(dead_code))]
    Owned(Arc<[RegionLine]>),
}
impl SegmentLines {
    pub fn len(&self) -> usize {
        match &self.0 {
            Repr::Indexed { len, .. } => *len,
            Repr::Owned(lines) => lines.len(),
        }
    }
    pub fn is_empty(&self) -> bool {
        self.len() == 0
    }
    /// The prepared source these lines index, when they are indexed.
    pub fn source(&self) -> Option<&Arc<PreparedSource>> {
        match &self.0 {
            Repr::Indexed { source, .. } => Some(source),
            Repr::Owned(_) => None,
        }
    }
    pub fn iter(&self) -> SegmentLineIter<'_> {
        match &self.0 {
            Repr::Indexed { source, runs, len } => SegmentLineIter::Indexed {
                lines: source.lines(),
                runs: runs.iter(),
                current: 0..0,
                remaining: *len,
            },
            Repr::Owned(lines) => SegmentLineIter::Owned(lines.iter()),
        }
    }
    /// Storage this owner holds itself (the run table); the source is shared and reported by its own owner.
    pub fn run_table(&self) -> Option<(usize, usize)> {
        match &self.0 {
            Repr::Indexed { runs, .. } => Some((
                runs.as_ptr() as usize,
                std::mem::size_of_val(runs.as_ref()),
            )),
            Repr::Owned(_) => None,
        }
    }
    #[cfg(test)]
    pub(crate) fn from_lines(lines: Vec<RegionLine>) -> Self {
        Self(Repr::Owned(lines.into()))
    }
    /// Test edit of one line: the segment turns into owned lines.
    #[cfg(test)]
    pub(crate) fn edit_line(&mut self, index: usize, edit: impl FnOnce(&mut RegionLine)) {
        let mut lines: Vec<RegionLine> = self
            .iter()
            .map(|line| RegionLine {
                source_span: line.source_span,
                source_line: line.source_line,
                source_lines: line.source_lines,
                text: line.text.clone(),
            })
            .collect();
        edit(&mut lines[index]);
        *self = Self::from_lines(lines);
    }
    #[cfg(test)]
    pub(crate) fn edit_lines(&mut self, mut edit: impl FnMut(&mut RegionLine)) {
        for index in 0..self.len() {
            self.edit_line(index, &mut edit);
        }
    }
}
impl<'a> IntoIterator for &'a SegmentLines {
    type Item = PreparedLineView<'a>;
    type IntoIter = SegmentLineIter<'a>;
    fn into_iter(self) -> Self::IntoIter {
        self.iter()
    }
}
pub enum SegmentLineIter<'a> {
    Indexed {
        lines: super::prepared_source::PreparedLines<'a>,
        runs: std::slice::Iter<'a, LineRun>,
        current: std::ops::Range<u32>,
        remaining: usize,
    },
    Owned(std::slice::Iter<'a, RegionLine>),
}
impl<'a> Iterator for SegmentLineIter<'a> {
    type Item = PreparedLineView<'a>;
    fn next(&mut self) -> Option<Self::Item> {
        match self {
            Self::Indexed {
                lines,
                runs,
                current,
                remaining,
            } => loop {
                if let Some(index) = current.next() {
                    *remaining -= 1;
                    return lines.get(index as usize);
                }
                let run = runs.next()?;
                *current = run.start..run.end;
            },
            Self::Owned(lines) => lines.next().map(|line| PreparedLineView {
                source_span: line.source_span,
                source_line: line.source_line,
                source_lines: line.source_lines,
                text: &line.text,
            }),
        }
    }
    fn size_hint(&self) -> (usize, Option<usize>) {
        match self {
            Self::Indexed { remaining, .. } => (*remaining, Some(*remaining)),
            Self::Owned(lines) => lines.size_hint(),
        }
    }
}
impl ExactSizeIterator for SegmentLineIter<'_> {}

/// The lines a pass has taken since the last freeze, collected as runs over one prepared source.
pub(super) struct PendingLines {
    source: Arc<PreparedSource>,
    runs: Vec<LineRun>,
    len: usize,
}
impl PendingLines {
    pub(super) fn new(source: Arc<PreparedSource>) -> Self {
        Self {
            source,
            runs: Vec::new(),
            len: 0,
        }
    }
    pub(super) fn is_empty(&self) -> bool {
        self.len == 0
    }
    /// Take line `index` of the source; consecutive indexes extend the open run.
    pub(super) fn push(&mut self, index: usize) {
        let index = u32::try_from(index).expect("prepared line index fits u32");
        match self.runs.last_mut() {
            Some(run) if run.end == index => run.end += 1,
            _ => self.runs.push(LineRun {
                start: index,
                end: index + 1,
            }),
        }
        self.len += 1;
    }
    /// The collected lines, leaving this builder empty.
    pub(super) fn take(&mut self) -> SegmentLines {
        SegmentLines(Repr::Indexed {
            source: Arc::clone(&self.source),
            runs: std::mem::take(&mut self.runs).into(),
            len: std::mem::take(&mut self.len),
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn runs_cover_exactly_the_pushed_lines_in_order() {
        let source = Arc::new(PreparedSource::new(Arc::from("a\nb\nc\nd\ne\nf\n")));
        let mut pending = PendingLines::new(Arc::clone(&source));
        for index in [0, 1, 3, 5, 4] {
            pending.push(index);
        }
        let lines = pending.take();
        assert!(pending.is_empty());
        assert_eq!(lines.len(), 5);
        assert_eq!(lines.run_table().unwrap().1, 4 * std::mem::size_of::<LineRun>());
        let texts: Vec<_> = lines.iter().map(|line| line.text.trim_end().to_owned()).collect();
        assert_eq!(texts, ["a", "b", "d", "f", "e"]);
        assert_eq!(lines.iter().len(), 5);
        assert!(Arc::ptr_eq(lines.source().unwrap(), &source));
    }
}
