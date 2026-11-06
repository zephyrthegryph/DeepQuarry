//! Compact private roster of already-issued parameter-relative clause facts.
//! No parser, source lookup, or new producer receipt.
use dm_syntax::{ParameterClauseSpans, Span};
use std::mem::{size_of, size_of_val};

const ABSENT: [u16; 2] = [u16::MAX; 2];

#[repr(transparent)]
struct PackedClause([[u16; 2]; 5]);

impl PackedClause {
    fn pack(parts: ParameterClauseSpans) -> Option<Self> {
        fn span(value: Span) -> Option<[u16; 2]> {
            Some([u16::try_from(value.start).ok()?, u16::try_from(value.end).ok()?])
        }
        fn marker(value: Option<Span>) -> Option<[u16; 2]> {
            match value {
                None => Some(ABSENT),
                Some(value) => span(value).filter(|pair| *pair != ABSENT),
            }
        }
        Some(Self([
            span(parts.parameter)?, marker(parts.assignment)?, marker(parts.annotation)?,
            marker(parts.source)?, marker(parts.post_source_annotation)?,
        ]))
    }

    fn unpack(&self) -> ParameterClauseSpans {
        fn span([start, end]: [u16; 2]) -> Span {
            Span::new(usize::from(start), usize::from(end))
        }
        fn marker(pair: [u16; 2]) -> Option<Span> {
            (pair != ABSENT).then(|| span(pair))
        }
        ParameterClauseSpans {
            parameter: span(self.0[0]), assignment: marker(self.0[1]),
            annotation: marker(self.0[2]), source: marker(self.0[3]),
            post_source_annotation: marker(self.0[4]),
        }
    }
}

enum Rows {
    Compact(Vec<PackedClause>),
    Full(Vec<ParameterClauseSpans>),
}
pub(crate) struct FormalClauseRows(Rows);
impl Default for FormalClauseRows {
    fn default() -> Self { Self(Rows::Compact(Vec::new())) }
}
impl FormalClauseRows {
    /// The Original observer's existing active-header envelope funds the
    /// wider fallback and its overlap with any smaller preexisting rows.
    /// Like the previous roster, this owns exact relative spans in source order.
    pub(crate) fn push(&mut self, parts: ParameterClauseSpans) {
        match &mut self.0 {
            Rows::Full(rows) => rows.push(parts),
            Rows::Compact(rows) => {
                if let Some(row) = PackedClause::pack(parts) {
                    rows.push(row);
                } else {
                    let mut full = Vec::with_capacity(rows.len() + 1);
                    full.extend(rows.iter().map(PackedClause::unpack));
                    full.push(parts);
                    self.0 = Rows::Full(full);
                }
            }
        }
    }

    pub(crate) fn len(&self) -> usize {
        match &self.0 { Rows::Compact(rows) => rows.len(), Rows::Full(rows) => rows.len() }
    }

    pub(crate) fn get(&self, ordinal: usize) -> Option<ParameterClauseSpans> {
        match &self.0 {
            Rows::Compact(rows) => rows.get(ordinal).map(PackedClause::unpack),
            Rows::Full(rows) => rows.get(ordinal).copied(),
        }
    }

    pub(crate) fn iter(&self) -> impl ExactSizeIterator<Item = ParameterClauseSpans> + '_ {
        (0..self.len()).map(|ordinal| self.get(ordinal).expect("issued clause ordinal"))
    }

    pub(crate) fn allocated_bytes(&self) -> usize {
        match &self.0 {
            Rows::Compact(rows) => rows.capacity() * size_of::<PackedClause>(),
            Rows::Full(rows) => rows.capacity() * size_of::<ParameterClauseSpans>(),
        }
    }

    pub(crate) fn visit_storage(&self, visit: impl FnOnce(usize, usize, usize)) {
        let capacity = self.allocated_bytes();
        if capacity == 0 { return; }
        let (ptr, len) = match &self.0 {
            Rows::Compact(rows) => (rows.as_ptr() as usize, size_of_val(rows.as_slice())),
            Rows::Full(rows) => (rows.as_ptr() as usize, size_of_val(rows.as_slice())),
        };
        visit(ptr, len, capacity);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn formal_clause_rows_keep_exact_optional_markers_and_wide_escape_order() {
        assert_eq!(size_of::<PackedClause>(), 20);
        assert!(size_of::<PackedClause>() < size_of::<ParameterClauseSpans>());
        let last = usize::from(u16::MAX);
        let small = ParameterClauseSpans {
            parameter: Span::new(0, last), assignment: Some(Span::new(0, 1)),
            annotation: None, source: Some(Span::new(last - 2, last)),
            post_source_annotation: None,
        };
        let ordinary = ParameterClauseSpans {
            parameter: Span::new(4, 22), assignment: None, annotation: Some(Span::new(7, 9)),
            source: Some(Span::new(12, 14)), post_source_annotation: Some(Span::new(19, 21)),
        };
        let mut rows = FormalClauseRows::default();
        rows.push(small);
        rows.push(ordinary);
        assert!(matches!(&rows.0, Rows::Compact(_)));
        assert!(rows.iter().eq([small, ordinary]));
        rows.visit_storage(|_, used, capacity| {
            assert_eq!(used, 2 * 20);
            assert_eq!(capacity, rows.allocated_bytes());
        });
        let sentinel = ParameterClauseSpans {
            parameter: Span::new(last, last), annotation: Some(Span::new(last, last)), ..small
        };
        let full_width = ParameterClauseSpans {
            parameter: Span::new(usize::MAX - 1, usize::MAX),
            assignment: Some(Span::new(usize::MAX - 1, usize::MAX)), ..small
        };
        rows.push(sentinel);
        rows.push(full_width);
        assert!(matches!(&rows.0, Rows::Full(_)));
        assert!(rows.iter().eq([small, ordinary, sentinel, full_width]));
        assert_eq!(rows.get(4), None);
    }
}
