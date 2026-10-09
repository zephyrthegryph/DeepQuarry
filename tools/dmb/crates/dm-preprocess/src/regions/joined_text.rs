//! Joined text is an immutable derived contribution, never a source authority.
//! Each piece has already passed the current ordered expansion validator.
use super::{expansion::RegionOutput, DirectivePlan, OrderedItem};
use crate::SourceText;
use dm_session::{
    observations::{ObservationHost, ObservationLedger},
    ObservedArtifactStore,
};
use std::sync::Arc;
const KEY: &[u8] = b"ordered-joined-text-v1";
#[derive(Clone)]
struct Piece {
    text: SourceText,
    record: Option<Arc<super::ExpansionRecord>>,
}
impl PartialEq for Piece {
    fn eq(&self, other: &Self) -> bool {
        match (&self.record, &other.record) {
            // Private capture below proves each view is this issued record's
            // output. Pointer equality implies exact immutable output bytes.
            (Some(left), Some(right)) if Arc::ptr_eq(left, right) => true,
            _ => self.text.same_view(&other.text) || self.text == other.text,
        }
    }
}
impl Eq for Piece {}
#[derive(Clone, PartialEq, Eq)]
struct Emission(Arc<[Piece]>);
impl Emission {
    fn capture(plan: &DirectivePlan, outputs: &[RegionOutput]) -> Self {
        Self(
            plan.items
                .iter()
                .filter_map(|item| match item {
                    OrderedItem::Text(index) => {
                        let output = &outputs[*index];
                        Some(Piece {
                            text: output.text.clone(),
                            record: output.receipt.clone(),
                        })
                    }
                    _ => None,
                })
                .collect(),
        )
    }
    fn assemble(&self) -> SourceText {
        join(self.0.iter().map(|piece| &piece.text))
    }
}
#[derive(Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
enum Query {
    OrderedEmission,
}
struct Current(Emission);
impl ObservationHost<Query, Emission, ()> for Current {
    fn answer(&self, _: &Query) -> Emission {
        self.0.clone()
    }
}
pub(super) struct JoinedText {
    values: ObservedArtifactStore<SourceText, Query, Emission, ()>,
}
impl Default for JoinedText {
    fn default() -> Self {
        Self {
            values: ObservedArtifactStore::current_revision(),
        }
    }
}
fn join<'a>(pieces: impl Iterator<Item = &'a SourceText> + Clone) -> SourceText {
    let mut text = String::with_capacity(pieces.clone().map(|piece| piece.len()).sum());
    for piece in pieces {
        text.push_str(piece);
    }
    text.into()
}
pub(super) fn assemble(plan: &DirectivePlan, outputs: &[RegionOutput]) -> SourceText {
    join(plan.items.iter().filter_map(|item| match item {
        OrderedItem::Text(index) => Some(&outputs[*index].text),
        _ => None,
    }))
}
impl JoinedText {
    pub(super) fn assemble(&self, plan: &DirectivePlan, outputs: &[RegionOutput]) -> SourceText {
        let host = Current(Emission::capture(plan, outputs));
        if let Some(owner) = self.values.lookup(KEY, &host) {
            return owner.as_ref().clone();
        }
        let text = host.0.assemble();
        let ledger = ObservationLedger::default();
        ledger.record(Query::OrderedEmission, host.0.clone(), (), None);
        self.values
            .insert_with(Arc::from(KEY), ledger.reads(), Vec::new(), 0, || {
                text.clone()
            });
        text
    }
    pub(super) fn visit_storage(&self, mut visit: impl FnMut(super::ExpansionStorageView<'_>)) {
        use super::region_memo::storage::{arc_storage, slice_storage};
        use super::ExpansionStorageView as View;
        use dm_session::ObservedArtifactStorageView as Store;
        self.values.visit_storage(|entry| match entry {
            Store::Store { entries, .. } => visit(View::Index { entries }),
            Store::Bucket {
                address,
                len,
                capacity,
                element_size,
            } => visit(View::Buffer {
                address,
                payload_bytes: len.saturating_mul(element_size),
                capacity_bytes: capacity.saturating_mul(element_size),
            }),
            Store::Entry {
                key,
                reads,
                versions,
                value,
            } => {
                visit(slice_storage(key));
                visit(slice_storage(reads));
                visit(slice_storage(versions));
                visit(arc_storage(value));
                visit(View::Source(value));
                for read in reads.iter() {
                    visit(slice_storage(&read.answer.0));
                    for piece in read.answer.0.iter() {
                        visit(View::Source(&piece.text));
                        if let Some(record) = &piece.record {
                            visit(arc_storage(record));
                            record.visit_storage(&mut visit);
                        }
                    }
                }
            }
        });
    }
}

#[cfg(test)]
#[path = "joined_text_tests.rs"]
mod tests;
