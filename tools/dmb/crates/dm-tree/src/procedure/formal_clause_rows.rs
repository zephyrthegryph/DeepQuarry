//! Compact private roster of already-issued parameter-relative clause facts.
//! No parser, source lookup, or new producer receipt.
use dm_syntax::{ParameterClauseSpans, Span};
use std::mem::{size_of, size_of_val};

const ABSENT: [u16; 2] = [u16::MAX; 2];

#[repr(transparent)]
#[derive(Clone, Copy)]
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
    Empty,
    // A singleton fits within the existing Vec-sized owner and is charged
    // as part of that row, including when it moves into the final directory.
    One(PackedClause),
    Compact(Vec<PackedClause>),
    Full(Vec<ParameterClauseSpans>),
}
pub(crate) struct FormalClauseRows(Rows);
impl Default for FormalClauseRows {
    fn default() -> Self { Self(Rows::Empty) }
}
impl FormalClauseRows {
    /// The Original observer's existing active-header envelope funds the
    /// wider fallback and its overlap with any smaller preexisting rows.
    /// Like the previous roster, this owns exact relative spans in source order.
    pub(crate) fn push(&mut self, parts: ParameterClauseSpans) {
        match &mut self.0 {
            Rows::Empty => {
                self.0 = match PackedClause::pack(parts) {
                    Some(row) => Rows::One(row),
                    None => Rows::Full(Vec::from([parts])),
                };
            }
            Rows::One(first) => {
                self.0 = match PackedClause::pack(parts) {
                    Some(next) => Rows::Compact(Vec::from([*first, next])),
                    None => Rows::Full(Vec::from([first.unpack(), parts])),
                };
            }
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
        match &self.0 {
            Rows::Empty => 0,
            Rows::One(_) => 1,
            Rows::Compact(rows) => rows.len(),
            Rows::Full(rows) => rows.len(),
        }
    }

    pub(crate) fn get(&self, ordinal: usize) -> Option<ParameterClauseSpans> {
        match &self.0 {
            Rows::Empty => None,
            Rows::One(row) => (ordinal == 0).then(|| row.unpack()),
            Rows::Compact(rows) => rows.get(ordinal).map(PackedClause::unpack),
            Rows::Full(rows) => rows.get(ordinal).copied(),
        }
    }

    pub(crate) fn iter(&self) -> impl ExactSizeIterator<Item = ParameterClauseSpans> + '_ {
        (0..self.len()).map(|ordinal| self.get(ordinal).expect("issued clause ordinal"))
    }

    pub(crate) fn allocated_bytes(&self) -> usize {
        match &self.0 {
            Rows::Empty | Rows::One(_) => 0,
            Rows::Compact(rows) => rows.capacity() * size_of::<PackedClause>(),
            Rows::Full(rows) => rows.capacity() * size_of::<ParameterClauseSpans>(),
        }
    }

    pub(crate) fn visit_storage(&self, visit: impl FnOnce(usize, usize, usize)) {
        let capacity = self.allocated_bytes();
        if capacity == 0 { return; }
        let (ptr, len) = match &self.0 {
            Rows::Empty | Rows::One(_) => return,
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
        // Compare against the former two Vec variants to catch an enlarged
        // signature row or clause directory row on supported hosts.
        #[allow(dead_code)]
        enum PreviousRows { Compact(Vec<PackedClause>), Full(Vec<ParameterClauseSpans>) }
        assert_eq!(size_of::<FormalClauseRows>(), size_of::<PreviousRows>());
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
        assert_eq!(rows.allocated_bytes(), 0);
        rows.push(small);
        assert_eq!(rows.len(), 1);
        assert_eq!(rows.get(0), Some(small));
        assert_eq!(rows.allocated_bytes(), 0);
        rows.visit_storage(|_, _, _| panic!("inline clause has no independent allocation"));
        rows.push(ordinary);
        assert_eq!(rows.allocated_bytes(), 2 * size_of::<PackedClause>());
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
        let mut from_single = FormalClauseRows::default();
        from_single.push(small);
        from_single.push(full_width);
        assert!(from_single.iter().eq([small, full_width]));
        assert_eq!(from_single.allocated_bytes(), 2 * size_of::<ParameterClauseSpans>());
        let mut wide_first = FormalClauseRows::default();
        wide_first.push(full_width);
        assert!(wide_first.iter().eq([full_width]));
        assert_eq!(wide_first.allocated_bytes(), size_of::<ParameterClauseSpans>());

        rows.push(sentinel);
        rows.push(full_width);
        assert!(matches!(&rows.0, Rows::Full(_)));
        assert!(rows.iter().eq([small, ordinary, sentinel, full_width]));
        assert_eq!(rows.get(4), None);
    }
}
