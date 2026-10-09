//! Immutable compact ledger ranges; public events remain losslessly observable.
use super::{AllocationEvent, AllocationKind};
use dm_syntax::Span;
use std::{fmt, sync::Arc};
pub(crate) struct CompactEvent {
    encounter_order: usize,
    start: u32,
    end: u32,
    header_start: u32,
    header_end: u32,
    kind: AllocationKind,
}
impl CompactEvent {
    fn event(&self) -> AllocationEvent {
        AllocationEvent {
            encounter_order: self.encounter_order,
            span: Span::new(self.start as usize, self.end as usize),
            header_span: Span::new(self.header_start as usize, self.header_end as usize),
            kind: self.kind,
        }
    }
}
enum Records {
    Compact(Box<[CompactEvent]>),
    Wide(Box<[AllocationEvent]>),
}
#[derive(Clone)]
pub struct AllocationEvents(Arc<Records>);
impl fmt::Debug for AllocationEvents {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_list().entries(self.iter()).finish()
    }
}
impl PartialEq for AllocationEvents {
    fn eq(&self, other: &Self) -> bool {
        self.len() == other.len() && self.iter().eq(other.iter())
    }
}
impl Eq for AllocationEvents {}
impl AllocationEvents {
    pub fn len(&self) -> usize {
        match self.0.as_ref() {
            Records::Compact(v) => v.len(),
            Records::Wide(v) => v.len(),
        }
    }
    pub fn is_empty(&self) -> bool {
        self.len() == 0
    }
    pub fn get(&self, index: usize) -> Option<AllocationEvent> {
        match self.0.as_ref() {
            Records::Compact(v) => v.get(index).map(CompactEvent::event),
            Records::Wide(v) => v.get(index).cloned(),
        }
    }
    pub fn iter(
        &self,
    ) -> impl ExactSizeIterator<Item = AllocationEvent> + DoubleEndedIterator + '_ {
        (0..self.len()).map(|index| self.get(index).expect("issued ledger index"))
    }
    /// Allocation addresses serve diagnostic accounting only, never proof identity.
    pub fn visit_storage(&self, mut visit: impl FnMut(usize, usize, usize)) {
        visit(
            Arc::as_ptr(&self.0) as usize,
            1,
            std::mem::size_of::<Records>(),
        );
        match self.0.as_ref() {
            Records::Compact(v) => visit(
                v.as_ptr() as usize,
                v.len(),
                std::mem::size_of_val(v.as_ref()),
            ),
            Records::Wide(v) => visit(
                v.as_ptr() as usize,
                v.len(),
                std::mem::size_of_val(v.as_ref()),
            ),
        }
    }
}
impl FromIterator<AllocationEvent> for AllocationEvents {
    fn from_iter<T: IntoIterator<Item = AllocationEvent>>(events: T) -> Self {
        let mut builder = EventBuilder::new();
        for event in events {
            builder.push(event);
        }
        builder.finish()
    }
}
impl From<Vec<AllocationEvent>> for AllocationEvents {
    fn from(events: Vec<AllocationEvent>) -> Self {
        events.into_iter().collect()
    }
}
pub(crate) enum EventBuilder {
    Compact(Vec<CompactEvent>),
    Wide(Vec<AllocationEvent>),
}
impl EventBuilder {
    pub(crate) fn new() -> Self {
        Self::Compact(Vec::new())
    }
    pub(crate) fn len(&self) -> usize {
        match self {
            Self::Compact(v) => v.len(),
            Self::Wide(v) => v.len(),
        }
    }
    pub(crate) fn push(&mut self, event: AllocationEvent) {
        if let Self::Wide(v) = self {
            v.push(event);
            return;
        }
        let coords = [
            event.span.start,
            event.span.end,
            event.header_span.start,
            event.header_span.end,
        ]
        .map(u32::try_from);
        if let [Ok(start), Ok(end), Ok(header_start), Ok(header_end)] = coords {
            if let Self::Compact(v) = self {
                v.push(CompactEvent {
                    encounter_order: event.encounter_order,
                    start,
                    end,
                    header_start,
                    header_end,
                    kind: event.kind,
                });
            }
        } else {
            let Self::Compact(old) = std::mem::replace(self, Self::new()) else {
                unreachable!()
            };
            let mut wide = Vec::with_capacity(old.capacity());
            wide.extend(old.into_iter().map(|event| event.event()));
            wide.push(event);
            *self = Self::Wide(wide);
        }
    }
    pub(crate) fn finish(self) -> AllocationEvents {
        AllocationEvents(Arc::new(match self {
            Self::Compact(v) => Records::Compact(v.into_boxed_slice()),
            Self::Wide(v) => Records::Wide(v.into_boxed_slice()),
        }))
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    use dm_ir::SymbolId;
    fn event(order: usize, span: Span, header: Span) -> AllocationEvent {
        AllocationEvent {
            encounter_order: order,
            span,
            header_span: header,
            kind: AllocationKind::Parent {
                owner: SymbolId::of("/datum/probe"),
                value: Span::new(4, 7),
            },
        }
    }
    #[test]
    fn compact_and_wide_preserve_arbitrary_encounters_and_all_public_fields() {
        for overflow in 0..=4 {
            let mut coords = [1, 8, 2, 7];
            if overflow < 4 {
                coords[overflow] = usize::MAX;
            }
            let expected = [
                event(17, Span::new(0, 9), Span::new(1, 8)),
                event(
                    usize::MAX,
                    Span::new(coords[0], coords[1]),
                    Span::new(coords[2], coords[3]),
                ),
                event(3, Span::new(9, 18), Span::new(10, 17)),
            ];
            let events: AllocationEvents = expected.clone().into_iter().collect();
            assert_eq!(events.iter().collect::<Vec<_>>(), expected);
            assert_eq!(
                matches!(events.0.as_ref(), Records::Compact(_)),
                overflow == 4
            );
            assert!(events.get(usize::MAX).is_none());
            let shared = events.clone();
            assert!(Arc::ptr_eq(&events.0, &shared.0));
        }
        #[cfg(target_pointer_width = "64")]
        assert!(std::mem::size_of::<AllocationEvent>() >= std::mem::size_of::<CompactEvent>() + 16);
    }
}
