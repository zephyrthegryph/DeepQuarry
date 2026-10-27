//! Process-local expansion input admission. Locator hashes never certify inputs.
//! Dependencies are adapted from the existing expansion recorder's issued record.
use super::{DirectivePlan, ExpansionRecord};
use crate::Macro;
use dm_session::{
    observations::{Observation, ObservationHost, ObservationLedger},
    ObservedArtifactStore,
};
use std::sync::Arc;

#[derive(Clone, Debug, PartialEq, Eq, PartialOrd, Ord)]
enum Query {
    Macro { segment: usize, name: Arc<str> },
    Location { ordinal: usize, file: bool },
}
#[derive(Clone, Debug, PartialEq, Eq)]
enum Answer {
    Macro(Option<Arc<Macro>>),
    Location(Option<String>),
}
type Reads = Vec<Observation<Query, Answer, ()>>;
/// Only the ordinary expansion validator can issue this receipt. No mutable
/// fields or external constructor grant admission from an arbitrary record.
struct ExpansionInputReceipt {
    segments: usize,
    record: Arc<ExpansionRecord>,
}
impl ExpansionInputReceipt {
    fn capture(
        plan: &DirectivePlan,
        index: usize,
        record: Arc<ExpansionRecord>,
    ) -> Option<(Self, Reads)> {
        let region = plan.regions.get(index)?;
        if !record.matches_current_input(plan, index) {
            return None;
        }
        let ledger = ObservationLedger::default();
        for read in record.reads() {
            ledger.record(
                Query::Macro {
                    segment: read.segment,
                    name: Arc::clone(&read.name),
                },
                Answer::Macro(read.definition.clone()),
                (),
            );
        }
        for (ordinal, file, expected) in record.location_reads() {
            ledger.record(
                Query::Location {
                    ordinal: *ordinal,
                    file: *file,
                },
                Answer::Location(Some(expected.clone())),
                (),
            );
        }
        Some((
            Self {
                segments: region.segments.len(),
                record,
            },
            ledger.reads(),
        ))
    }
    /// Exact prepared control shape, after the shared store has replayed reads.
    /// This does not certify directive planning itself.
    fn admits(&self, plan: &DirectivePlan, index: usize) -> bool {
        let Some(region) = plan.regions.get(index) else {
            return false;
        };
        if region.segments.len() != self.segments {
            return false;
        }
        self.record.matches_current_input(plan, index)
    }

    fn record(&self) -> &Arc<ExpansionRecord> {
        &self.record
    }
}

struct Current<'a> {
    plan: &'a DirectivePlan,
    index: usize,
}
impl ObservationHost<Query, Answer, ()> for Current<'_> {
    fn answer(&self, query: &Query) -> Answer {
        let region = &self.plan.regions[self.index];
        match query {
            Query::Macro { segment, name } => Answer::Macro(
                region
                    .segments
                    .get(*segment)
                    .and_then(|segment| segment.macros.shared_definition(name)),
            ),
            Query::Location { ordinal, file } => Answer::Location(if *file {
                Some(self.plan.semantic_path(region.occurrence))
            } else {
                region
                    .segments
                    .iter()
                    .flat_map(|segment| segment.lines.iter())
                    .nth(*ordinal)
                    .map(|line| line.source_line.to_string())
            }),
        }
    }
}
type Store = ObservedArtifactStore<ExpansionInputReceipt, Query, Answer, ()>;
type Lease = dm_session::ObservedArtifactLease<ExpansionInputReceipt, Query, Answer, ()>;
/// The core every `ExpansionInputs` of a daemon leases (see [`share_expansion_inputs`]).
static SHARED: std::sync::OnceLock<Arc<Store>> = std::sync::OnceLock::new();
/// Make the expansion input admissions of every `ExpansionInputs` created from now on one shared core, the way a daemon
/// shares them between its sessions: equal regions of two sessions (a second worktree, the game and the test variant)
/// are one allocation, and every hit is still validated against the asking plan's own macros, locations and shape. A
/// process that never calls this (a one-shot compile, a unit test) keeps private admissions.
pub fn share_expansion_inputs() {
    SHARED.get_or_init(Store::shared_current_rosters);
}
enum Values {
    Local(Store),
    Shared(Lease),
}
impl Values {
    fn visit_storage(
        &self,
        visit: impl FnMut(dm_session::ObservedArtifactStorageView<'_, ExpansionInputReceipt, Query, Answer, ()>),
    ) {
        match self {
            Self::Local(store) => store.visit_storage(visit),
            Self::Shared(lease) => lease.visit_storage(visit),
        }
    }
    fn retain_current_keys<'a>(&self, keys: impl IntoIterator<Item = &'a [u8]>) {
        match self {
            Self::Local(store) => store.retain_current_keys(keys),
            Self::Shared(lease) => lease.retain_current_keys(keys),
        }
    }
    fn visit_explained(
        &self,
        key: &[u8],
        host: &Current<'_>,
        accept: &mut dyn FnMut(&Arc<ExpansionInputReceipt>) -> bool,
    ) -> (Option<Arc<ExpansionInputReceipt>>, Option<Query>) {
        match self {
            Self::Local(store) => store.visit_explained(key, host, accept),
            Self::Shared(lease) => lease.visit_explained(key, host, accept),
        }
    }
    fn insert_with(&self, key: Arc<[u8]>, reads: Reads, create: impl FnOnce() -> ExpansionInputReceipt) {
        match self {
            Self::Local(store) => {
                store.insert_with(key, reads, Vec::new(), 0, create);
            }
            Self::Shared(lease) => {
                lease.insert_with(key, reads, Vec::new(), 0, create);
            }
        }
    }
}
/// Caller-owned current-revision input admissions: private to the caller, or its lease on the daemon's shared core.
/// Keys are locators only; exact source/control shape and recorded observations
/// certify every hit. Storage weights are deliberately unreported here.
pub struct ExpansionInputs {
    joined: super::joined_text::JoinedText,
    values: Values,
}
impl Default for ExpansionInputs {
    fn default() -> Self {
        match SHARED.get() {
            Some(core) => Self::with_core(core),
            None => Self {
                joined: Default::default(),
                values: Values::Local(ObservedArtifactStore::current_revision()),
            },
        }
    }
}
impl ExpansionInputs {
    /// Admissions leased on `core`, shared with every other owner leasing it.
    fn with_core(core: &Arc<Store>) -> Self {
        Self {
            joined: Default::default(),
            values: Values::Shared(core.lease()),
        }
    }
}
impl ExpansionInputs {
    /// Explicit borrowed owner census; callbacks must not re-enter this store.
    pub fn visit_storage(&self, mut visit: impl FnMut(super::ExpansionStorageView<'_>)) {
        use super::region_memo::storage::{arc_storage, slice_storage, string_storage};
        use super::ExpansionStorageView as View;
        use dm_session::ObservedArtifactStorageView as Store;
        self.joined.visit_storage(&mut visit);
        self.values.visit_storage(|view| match view {
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
                reads.visit_storage(|storage| match storage {
                    dm_session::ReceiptStorageView::Flat(values) => visit(slice_storage(values)),
                    dm_session::ReceiptStorageView::Groups(groups) => visit(slice_storage(groups)),
                });
                visit(slice_storage(versions));
                for read in reads.iter() {
                    if let Query::Macro { name, .. } = &read.query {
                        visit(View::Text(name));
                    }
                    match &read.answer {
                        Answer::Macro(Some(definition)) => visit(View::Macro(definition)),
                        Answer::Location(Some(text)) => visit(string_storage(text)),
                        _ => {}
                    }
                }
                visit(arc_storage(value));
                visit(arc_storage(&value.record));
                value.record.visit_storage(&mut visit);
            }
        });
    }
    pub(super) fn joined_text(
        &self,
        plan: &DirectivePlan,
        outputs: &[super::expansion::RegionOutput],
    ) -> crate::SourceText {
        self.joined.assemble(plan, outputs)
    }
    fn key(plan: &DirectivePlan, index: usize) -> Option<[u8; 16]> {
        let region = plan.regions.get(index)?;
        let path = &plan.occurrences.get(region.occurrence)?.path;
        Some(
            plan.source_texts
                .get(path.as_ref())?
                .span_fingerprint(region.source_span.range())?
                .to_le_bytes(),
        )
    }
    /// Keep only the admissions of this plan's regions, and return each region's key (a region
    /// whose file text is missing has none) so the next expansion need not hash them again.
    pub(super) fn retain_current(&self, plan: &DirectivePlan) -> Vec<Option<[u8; 16]>> {
        let keys: Vec<_> = (0..plan.regions.len()).map(|i| Self::key(plan, i)).collect();
        self.retain_keys(&keys);
        keys
    }
    pub(super) fn retain_keys(&self, keys: &[Option<[u8; 16]>]) {
        self.values
            .retain_current_keys(keys.iter().flatten().map(|key| key.as_slice()));
    }
    /// The key of a region of `plan`, for a region that was not copied from an earlier plan.
    pub(super) fn region_key(plan: &DirectivePlan, index: usize) -> Option<[u8; 16]> {
        Self::key(plan, index)
    }
    pub(super) fn lookup(
        &self,
        plan: &DirectivePlan,
        index: usize,
    ) -> Option<Arc<ExpansionRecord>> {
        let key = Self::key(plan, index)?;
        let host = Current { plan, index };
        let (value, _) = self
            .values
            .visit_explained(&key, &host, &mut |receipt| receipt.admits(plan, index));
        value.map(|value| Arc::clone(value.record()))
    }
    pub(super) fn insert(&self, plan: &DirectivePlan, index: usize, record: Arc<ExpansionRecord>) {
        let Some(key) = Self::key(plan, index) else {
            return;
        };
        let Some((receipt, reads)) = ExpansionInputReceipt::capture(plan, index, record) else {
            return;
        };
        // Current-roster retention does not use this weight to budget admission.
        // Actual retained owners must be reported through the census, not a
        // fabricated serialized-size multiplier.
        self.values
            .insert_with(Arc::from(key.as_slice()), reads, || receipt);
    }
}

#[cfg(test)]
#[path = "expansion_input_tests.rs"]
mod tests;
