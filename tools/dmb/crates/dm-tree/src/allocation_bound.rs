//! Shared relative allocation leaves with checked current source bindings.
//! The ordinary owned ledger remains the compatibility representation.
use super::{AllocationEvent, AllocationEvents, AllocationKind};
use dm_syntax::Span;
use std::sync::Arc;

#[derive(Clone)]
pub(crate) struct ValidatedEventLeaf(Arc<Leaf>);
struct Leaf {
    events: AllocationEvents,
    max_endpoint: usize,
}
impl ValidatedEventLeaf {
    /// Inspect each immutable leaf once, including nested declaration spans.
    pub(crate) fn new(events: AllocationEvents) -> Self {
        let mut max_endpoint = 0;
        for event in events.iter() {
            let mut include = |span: Span| {
                max_endpoint = max_endpoint.max(span.start).max(span.end);
            };
            include(event.span);
            include(event.header_span);
            match event.kind {
                AllocationKind::Field { initializer, .. } => {
                    if let Some(span) = initializer {
                        include(span);
                    }
                }
                AllocationKind::Procedure { body, .. } => include(body),
                AllocationKind::Parent { value, .. } => include(value),
                AllocationKind::Type { .. } | AllocationKind::Namespace { .. } => {}
            }
        }
        Self(Arc::new(Leaf {
            events,
            max_endpoint,
        }))
    }
    pub(crate) fn visit_storage(&self, visit: &mut dyn FnMut(usize, usize, usize)) {
        visit(
            Arc::as_ptr(&self.0) as usize,
            1,
            std::mem::size_of::<Leaf>(),
        );
        self.0.events.visit_storage_dyn(visit);
    }
}

struct Chunk {
    leaf: ValidatedEventLeaf,
    offset: usize,
    encounter_base: usize,
}
pub(crate) struct BoundEvents {
    chunks: Box<[Chunk]>,
    /// Exclusive ends; empty leaves are omitted.
    prefix: Box<[usize]>,
    len: usize,
}
#[derive(Debug, PartialEq, Eq)]
pub(crate) enum BindError {
    SpanOverflow,
    EncounterOverflow,
}
impl BoundEvents {
    pub(crate) fn new(
        leaves: impl IntoIterator<Item = (ValidatedEventLeaf, usize)>,
    ) -> Result<Self, BindError> {
        let mut chunks = Vec::new();
        let mut prefix = Vec::new();
        let mut len: usize = 0;
        for (leaf, offset) in leaves {
            if leaf.0.events.is_empty() {
                continue;
            }
            offset
                .checked_add(leaf.0.max_endpoint)
                .ok_or(BindError::SpanOverflow)?;
            let next = checked_end(len, leaf.0.events.len())?;
            chunks.push(Chunk {
                leaf,
                offset,
                encounter_base: len,
            });
            prefix.push(next);
            len = next;
        }
        Ok(Self {
            chunks: chunks.into_boxed_slice(),
            prefix: prefix.into_boxed_slice(),
            len,
        })
    }
    pub(crate) fn len(&self) -> usize {
        self.len
    }
    pub(crate) fn get(&self, index: usize) -> Option<AllocationEvent> {
        if index >= self.len {
            return None;
        }
        let chunk = &self.chunks[self.prefix.partition_point(|end| *end <= index)];
        Some(Self::event(chunk, index))
    }
    fn event(chunk: &Chunk, index: usize) -> AllocationEvent {
        let mut event = chunk
            .leaf
            .0
            .events
            .get(index - chunk.encounter_base)
            .expect("validated bound leaf index");
        let shift = |span: Span| Span::new(span.start + chunk.offset, span.end + chunk.offset);
        event.encounter_order = index;
        event.span = shift(event.span);
        event.header_span = shift(event.header_span);
        match &mut event.kind {
            AllocationKind::Field { initializer, .. } => *initializer = initializer.map(shift),
            AllocationKind::Procedure { body, .. } => *body = shift(*body),
            AllocationKind::Parent { value, .. } => *value = shift(*value),
            AllocationKind::Type { .. } | AllocationKind::Namespace { .. } => {}
        }
        event
    }
    pub(crate) fn iter(&self) -> BoundIter<'_> {
        BoundIter {
            events: self,
            front: 0,
            back: self.len,
            front_chunk: 0,
            back_chunk: self.chunks.len().saturating_sub(1),
        }
    }
    /// Reports real allocations; callers deduplicate shared addresses.
    pub(crate) fn visit_storage(&self, visit: &mut dyn FnMut(usize, usize, usize)) {
        visit(
            self.chunks.as_ptr() as usize,
            self.chunks.len(),
            std::mem::size_of_val(self.chunks.as_ref()),
        );
        visit(
            self.prefix.as_ptr() as usize,
            self.prefix.len(),
            std::mem::size_of_val(self.prefix.as_ref()),
        );
        for chunk in &self.chunks {
            chunk.leaf.visit_storage(visit);
        }
    }
}

fn checked_end(base: usize, count: usize) -> Result<usize, BindError> {
    base.checked_add(count).ok_or(BindError::EncounterOverflow)
}
pub(crate) struct BoundIter<'a> {
    events: &'a BoundEvents,
    front: usize,
    back: usize,
    front_chunk: usize,
    back_chunk: usize,
}
impl Iterator for BoundIter<'_> {
    type Item = AllocationEvent;
    fn next(&mut self) -> Option<Self::Item> {
        if self.front == self.back {
            return None;
        }
        while self.events.prefix[self.front_chunk] <= self.front {
            self.front_chunk += 1;
        }
        let event = BoundEvents::event(&self.events.chunks[self.front_chunk], self.front);
        self.front += 1;
        Some(event)
    }
    fn size_hint(&self) -> (usize, Option<usize>) {
        let len = self.back - self.front;
        (len, Some(len))
    }
}
impl DoubleEndedIterator for BoundIter<'_> {
    fn next_back(&mut self) -> Option<Self::Item> {
        if self.front == self.back {
            return None;
        }
        self.back -= 1;
        while self.events.chunks[self.back_chunk].encounter_base > self.back {
            self.back_chunk -= 1;
        }
        Some(BoundEvents::event(
            &self.events.chunks[self.back_chunk],
            self.back,
        ))
    }
}
impl ExactSizeIterator for BoundIter<'_> {}
impl std::iter::FusedIterator for BoundIter<'_> {}

#[cfg(test)]
mod tests {
    use super::*;
    use dm_ir::SymbolId;
    fn leaf(span: Span, value: Span) -> ValidatedEventLeaf {
        ValidatedEventLeaf::new(
            vec![AllocationEvent {
                encounter_order: usize::MAX,
                span,
                header_span: span,
                kind: AllocationKind::Parent {
                    owner: SymbolId::of("/datum/test"),
                    value,
                },
            }]
            .into(),
        )
    }
    #[test]
    fn mixed_leaves_bind_source_spans_and_canonical_encounters_without_changing_originals() {
        let compact = leaf(Span::new(1, 3), Span::new(2, 3));
        let wide = leaf(Span::new(0, usize::MAX), Span::new(0, 1));
        let bound =
            BoundEvents::new([(compact.clone(), 10), (wide, 0), (compact.clone(), 30)]).unwrap();
        assert_eq!(bound.len(), 3);
        let first = bound.get(0).unwrap();
        assert_eq!(first.span, Span::new(11, 13));
        assert_eq!(first.encounter_order, 0);
        assert!(
            matches!(first.kind, AllocationKind::Parent { value, .. } if value == Span::new(12, 13))
        );
        assert_eq!(bound.get(1).unwrap().span.end, usize::MAX);
        assert_eq!(bound.get(2).unwrap().span, Span::new(31, 33));
        assert_eq!(compact.0.events.get(0).unwrap().encounter_order, usize::MAX);
        assert!(bound.get(usize::MAX).is_none());
        let mut iter = bound.iter();
        assert_eq!(iter.next_back().unwrap().encounter_order, 2);
        assert_eq!(iter.next().unwrap().encounter_order, 0);
        assert_eq!(iter.len(), 1);
        assert_eq!(iter.next().unwrap().encounter_order, 1);
        assert!(iter.next_back().is_none());
    }
    #[test]
    fn public_ledger_binding_matches_owned_events_and_reports_shared_backing() {
        let owner = SymbolId::of("/datum/test");
        let originals = vec![
            AllocationEvent {
                encounter_order: 99,
                span: Span::new(1, 9),
                header_span: Span::new(1, 3),
                kind: AllocationKind::Field {
                    owner,
                    name: SymbolId::of("field"),
                    formal: true,
                    var_namespace: false,
                    initializer: Some(Span::new(5, 9)),
                },
            },
            AllocationEvent {
                encounter_order: 4,
                span: Span::new(10, 20),
                header_span: Span::new(10, 13),
                kind: AllocationKind::Procedure {
                    owner,
                    formal: true,
                    verb: false,
                    name: SymbolId::of("probe"),
                    body: Span::new(14, 20),
                },
            },
        ];
        let owned: AllocationEvents = originals.into();
        let leaf = ValidatedEventLeaf::new(owned.clone());
        let bound = AllocationEvents::bind_leaves([(leaf.clone(), 30), (leaf, 90)]).unwrap();
        let expected: AllocationEvents = (0..4)
            .map(|index| {
                let mut event = owned.get(index % 2).unwrap();
                let offset = if index < 2 { 30 } else { 90 };
                let shift = |span: Span| Span::new(span.start + offset, span.end + offset);
                event.encounter_order = index;
                event.span = shift(event.span);
                event.header_span = shift(event.header_span);
                match &mut event.kind {
                    AllocationKind::Field { initializer, .. } => {
                        *initializer = initializer.map(shift)
                    }
                    AllocationKind::Procedure { body, .. } => *body = shift(*body),
                    _ => unreachable!(),
                }
                event
            })
            .collect();
        assert_eq!(bound, expected);
        assert_eq!(
            bound.iter().rev().collect::<Vec<_>>(),
            expected.iter().rev().collect::<Vec<_>>()
        );
        let mut owned_addresses = Vec::new();
        owned.visit_storage(|address, _, _| owned_addresses.push(address));
        let mut bound_addresses = Vec::new();
        bound.visit_storage(|address, _, _| bound_addresses.push(address));
        for address in owned_addresses {
            assert_eq!(
                bound_addresses
                    .iter()
                    .filter(|candidate| **candidate == address)
                    .count(),
                2
            );
        }
    }
    #[test]
    fn encounter_overflow_rejects_without_truncation() {
        assert_eq!(checked_end(usize::MAX, 0), Ok(usize::MAX));
        assert_eq!(
            checked_end(usize::MAX, 1),
            Err(BindError::EncounterOverflow)
        );
    }
    #[test]
    fn nested_span_overflow_rejected_and_empty_leaves_do_not_change_order() {
        let nested = leaf(Span::new(0, 1), Span::new(0, usize::MAX));
        assert!(matches!(
            BoundEvents::new([(nested, 1)]),
            Err(BindError::SpanOverflow)
        ));
        let empty = ValidatedEventLeaf::new(Vec::new().into());
        let bound = BoundEvents::new([
            (empty, usize::MAX),
            (leaf(Span::new(0, 1), Span::new(0, 1)), 4),
        ])
        .unwrap();
        assert_eq!(bound.get(0).unwrap().encounter_order, 0);
        assert_eq!(bound.len(), 1);
    }
}
