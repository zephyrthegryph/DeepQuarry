//! SAME canonical std::Arc payload, private lifetime wrappers only.
//! No production constructor issues ValueRetentionPermit: stable std::Arc does
//! not expose allocation Layout, so the source endpoint remains unavailable.
use super::no_weak_arc_owner::NoWeakArc;
use super::source_allocation::SourceLease;
pub(super) type SharedSourceLease = NoWeakArc<SourceLease>;
use super::*;
use std::{io, mem::ManuallyDrop, ops::Deref, sync::Weak};

pub(super) struct ValueOwner {
    inner: ManuallyDrop<Arc<AnswerValue>>,
}
impl ValueOwner {
    pub(super) fn new_runtime(hash: u128, positive: bool, query: dm_ir::ResolveQuery) -> Self {
        Self::from_arc(Arc::new(AnswerValue {
            hash,
            positive,
            query,
            source_retention: std::sync::OnceLock::new(),
        }))
    }
    fn from_arc(inner: Arc<AnswerValue>) -> Self {
        Self {
            inner: ManuallyDrop::new(inner),
        }
    }
    fn address(&self) -> usize {
        Arc::as_ptr(&self.inner) as usize
    }
    fn install_retention(&self, permit: ValueRetentionPermit<'_>) -> io::Result<SharedSourceLease> {
        if self.address() != permit.owner.address() {
            return Err(io::Error::other(
                "source value retention permit belongs to another original allocation",
            ));
        }
        // The payload is canonical/immutable. Only its allocation-lifetime
        // attachment is write-once; a second same-owner admission uses the
        // existing lease rather than duplicating semantic or resource storage.
        if let Some(held) = self.source_retention.get() {
            return Ok(held.clone());
        }
        let _ = self.source_retention.set(permit.retention.clone());
        Ok(SharedSourceLease::clone(
            self.source_retention
                .get()
                .expect("set or another exact-owner attachment"),
        ))
    }
    pub(super) fn census(&self, c: &mut crate::heap_census::HeapCensus) {
        c.arc_object("answers.original_value", &self.inner);
        if let Some(lease) = self.source_retention.get() {
            lease.census(c, "answers.source_retention_lease");
        }
        c.unknown("answers.original_value","std Arc control blocks and allocation Layout are not exposed; no exact source allocation contract is issued");
    }
}
impl Deref for ValueOwner {
    type Target = AnswerValue;
    fn deref(&self) -> &AnswerValue {
        self.inner.as_ref()
    }
}
impl Clone for ValueOwner {
    fn clone(&self) -> Self {
        Self::from_arc(Arc::clone(&self.inner))
    }
}
impl Drop for ValueOwner {
    fn drop(&mut self) {
        // Read at DROP time, not clone time: this includes runtime aliases that
        // predate first source retention. The temporary lease outlives the last
        // actual strong free. No naked strong Arc is exposed by this wrapper.
        let retention = self.inner.source_retention.get().cloned();
        unsafe {
            ManuallyDrop::drop(&mut self.inner);
        }
        drop(retention);
    }
}
/// The original pool entry, not an additional weak/value registry.
pub(super) struct PooledOwner {
    weak: ManuallyDrop<Weak<AnswerValue>>,
    retention: Option<SharedSourceLease>,
}
impl PooledOwner {
    pub(super) fn from_owner(owner: &ValueOwner) -> Self {
        Self {
            weak: ManuallyDrop::new(Arc::downgrade(&owner.inner)),
            retention: owner.source_retention.get().cloned(),
        }
    }
    pub(super) fn upgrade(&self) -> Option<ValueOwner> {
        self.weak.upgrade().map(ValueOwner::from_arc)
    }
    pub(super) fn strong_count(&self) -> usize {
        self.weak.strong_count()
    }
    fn matches(&self, owner: &ValueOwner) -> bool {
        self.weak.as_ptr() as usize == owner.address()
    }
    pub(super) fn census(&self, c: &mut crate::heap_census::HeapCensus) {
        if let Some(owner) = self.upgrade() {
            owner.census(c);
        } else {
            // This does not dereference dead T. Weak retains the SAME original
            // allocation; its payload region still occupies size_of(T) bytes.
            c.exposed_buffer(
                "answers.weak_only_original_value",
                self.weak.as_ptr() as usize,
                0,
                std::mem::size_of::<AnswerValue>(),
            );
            c.unknown("answers.weak_only_original_value","payload region remains allocated via original Weak; std Arc control block Layout is unavailable");
        }
        if let Some(lease) = &self.retention {
            lease.census(c, "answers.source_retention_lease");
        }
    }
}
impl Drop for PooledOwner {
    fn drop(&mut self) {
        let retention = self.retention.take();
        // Weak control allocation may die here AFTER all strong values died.
        unsafe {
            ManuallyDrop::drop(&mut self.weak);
        }
        drop(retention);
    }
}
/// Opaque and intentionally UNISSUED in production. A future supported factory
/// must pre-admit both the canonical value allocation and retention-owner
/// allocation using a real supported allocation contract, then bind this exact
/// original ValueOwner. Installed stdlib source alone is not such authority.
pub(super) struct ValueRetentionPermit<'a> {
    owner: &'a ValueOwner,
    retention: SharedSourceLease,
}
#[cfg(test)]
impl<'a> ValueRetentionPermit<'a> {
    pub(super) fn lifetime_fixture(
        owner: &'a ValueOwner,
        ledger: &Arc<SourceLedger>,
        bytes: usize,
    ) -> Self {
        // Logical charge chosen only to test lifetime ordering. NOT a claim
        // about std Arc Layout, and never a production allocation receipt.
        Self {
            owner,
            retention: SharedSourceLease::new(ledger.reserve(bytes).unwrap()),
        }
    }
}
impl AnswerValues {
    pub(super) fn retain_source_owner(
        &self,
        id: u128,
        owner: &ValueOwner,
        permit: ValueRetentionPermit<'_>,
    ) -> io::Result<()> {
        let mut pooled = self.shards[(id as usize) % VALUE_SHARDS]
            .lock()
            .unwrap_or_else(|e| e.into_inner());
        if let Some(entry) = pooled
            .get_mut(&(id as u64))
            .filter(|entry| entry.matches(owner))
        {
            let retention = owner.install_retention(permit)?;
            entry.retention = Some(retention);
            return Ok(());
        }
        // The old pool key may have been overwritten while an original marked
        // base survives. No pooled Weak to this value remains; live strong
        // wrappers still hold its allocation until their actual final drop.
        owner.install_retention(permit).map(|_| ())
    }
}
