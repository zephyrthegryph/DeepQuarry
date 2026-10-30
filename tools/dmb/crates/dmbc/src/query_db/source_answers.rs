//! Bounded original Answers source scope. No parser/model/store or public switch.
use super::*;
use super::{
    answer_value_owner::{SharedSourceLease, SourceValueReservation},
    native_arc_allocation::NativeArcAllocationPlan as Plan,
    no_weak_arc_owner::NoWeakArc,
};
use crate::runner_host::query_snapshot::{SourceAnswerPublication, SourceAnswersMode};
use dm_ir::{PackedU128, ResolveQuery as Q, Resolver};
use dm_tree::frontend::{BodyArchive, SourceExportMapping};
use std::{io, ops::Deref, sync::Weak};
pub(super) struct SourceGeneration {
    retention: SharedSourceLease,
}
pub(crate) struct SourceAnswerScope {
    db: u64,
    request: u64,
    generation: NoWeakArc<SourceGeneration>,
    retention: SharedSourceLease,
    world: u128,
    profile: PackedU128,
    pub(super) questions: Option<super::SourceQuestionRoster>,
    tree: Weak<dm_tree::SemanticTree>,
    mapping: Weak<SourceExportMapping>,
    archive: Weak<BodyArchive>,
}
pub(crate) struct SourceAnswerScopeOwner {
    inner: NoWeakArc<SourceAnswerScope>,
}
impl Deref for SourceAnswerScopeOwner {
    type Target = SourceAnswerScope;
    fn deref(&self) -> &Self::Target {
        &self.inner
    }
}
impl Clone for SourceAnswerScopeOwner {
    fn clone(&self) -> Self {
        Self {
            inner: self.inner.clone(),
        }
    }
}
impl SourceAnswerScopeOwner {
    pub(crate) fn census(&self, c: &mut crate::heap_census::HeapCensus) {
        if let Ok(plan) = Plan::source_scope() {
            self.inner
                .census_layout(c, "query_snapshot.source_answers", plan.layout());
        } else {
            self.inner.census(c, "query_snapshot.source_answers");
        }
        if let Ok(plan) = Plan::source_generation() {
            self.inner.generation.census_layout(
                c,
                "query_snapshot.source_answers.generation",
                plan.layout(),
            );
        } else {
            self.inner
                .generation
                .census(c, "query_snapshot.source_answers.generation");
        }
        self.inner.retention.census_source_lease(c);
        if let Some(questions) = &self.inner.questions {
            questions.census(c);
        }
        c.unknown("query_snapshot.source_answers","original owners only; quota reservations are not total heap/RSS and std Arc allocator rounding is excluded");
    }
}
impl SourceAnswerScope {
    pub(crate) fn has_questions(&self) -> bool {
        self.questions.is_some()
    }
    pub(super) fn require(
        &self,
        db: &QueryDb,
        current: &AnswerRequest,
        tree: &dm_tree::SemanticTree,
        mapping: &SourceExportMapping,
        archive: &BodyArchive,
    ) -> io::Result<()> {
        if self.db != db.id
            || current.request != self.request
            || current
                .source_binding
                .as_ref()
                .is_none_or(|generation| !generation.same_owner(&self.generation))
            || current.world != self.world
            || current
                .tree
                .as_ref()
                .is_none_or(|value| !std::ptr::eq(value.as_ref(), tree))
            || tree.checker_builtin_profile() != Some(self.profile)
            || !tree.intrinsic_hierarchy_certified()
            || self
                .tree
                .upgrade()
                .is_none_or(|v| !std::ptr::eq(v.as_ref(), tree))
            || self
                .mapping
                .upgrade()
                .is_none_or(|v| !std::ptr::eq(v.as_ref(), mapping))
            || self
                .archive
                .upgrade()
                .is_none_or(|v| !std::ptr::eq(v.as_ref(), archive))
            || !archive.matches_tree(tree)
            || !std::ptr::eq(archive.source_mapping().as_ref(), mapping)
        {
            return Err(io::ErrorKind::InvalidInput.into());
        }
        Ok(())
    }
}
fn source_hash(tree: &dm_tree::SemanticTree, question: Q) -> io::Result<(u128, bool)> {
    let Q::CertifiedHierarchy { kind, path } = question else {
        return Err(io::ErrorKind::Unsupported.into());
    };
    let view = tree
        .certified_hierarchy()
        .ok_or(io::ErrorKind::Unsupported)?;
    let answer = view.borrowed_answer(kind, path);
    let mut work = view
        .node_bound()
        .checked_mul(2)
        .and_then(|n| n.checked_add(2))
        .ok_or(io::ErrorKind::OutOfMemory)?;
    let mut hash = xxhash_rust::xxh3::Xxh3::new();
    answer.write_canonical(&mut work, crate::daemon::control::checkpoint, |part| {
        hash.update(part);
        Ok(())
    })?;
    Ok((hash.digest128(), answer.positive()))
}
impl QueryDb {
    pub(crate) fn source_answer_request(&self) -> u64 {
        self.answers
            .current
            .read()
            .unwrap_or_else(|e| e.into_inner())
            .request
    }
    pub(crate) fn commit_source_answer_publication(
        &self,
        publication: SourceAnswerPublication,
        publish: impl FnOnce(Option<SourceAnswerScopeOwner>),
    ) -> io::Result<()> {
        let (tree, mapping, archive, queries, eligible, query_request, mode) = publication.parts();
        if !std::ptr::eq(self, queries.as_ref())
            || !archive.matches_tree(tree)
            || !Arc::ptr_eq(archive.source_mapping(), mapping)
        {
            return Err(io::ErrorKind::InvalidInput.into());
        }
        if mode == SourceAnswersMode::NotRequested {
            let mut current = self
                .answers
                .current
                .write()
                .unwrap_or_else(|e| e.into_inner());
            if current.request != query_request {
                return Err(io::ErrorKind::InvalidInput.into());
            }
            #[cfg(test)]
            hooks::at(false);
            crate::daemon::control::begin_publication()?;
            current.source_binding = None;
            #[cfg(test)]
            hooks::at(true);
            publish(None);
            return Ok(());
        }
        if !eligible {
            return Err(io::ErrorKind::Unsupported.into());
        }
        let profile = tree
            .checker_builtin_profile()
            .ok_or(io::ErrorKind::Unsupported)?;
        let scope_layout = Plan::source_scope()
            .map_err(|_| io::ErrorKind::Unsupported)?
            .layout();
        let generation_layout = Plan::source_generation()
            .map_err(|_| io::ErrorKind::Unsupported)?
            .layout();
        let lease_layout = Plan::retention_lease()
            .map_err(|_| io::ErrorKind::Unsupported)?
            .layout();
        let scope_bytes = scope_layout
            .size()
            .checked_add(generation_layout.size())
            .and_then(|n| n.checked_add(lease_layout.size()))
            .ok_or(io::ErrorKind::OutOfMemory)?;
        let ledger = &self.answers.values.source_ledger;
        // Canonical original issued keys are borrowed directly; no path rewrite or
        // source reread. The bounded transient set is never retained in the scope.
        let sources = self.sources.lock().unwrap_or_else(|e| e.into_inner());
        let allocator = SourceAllocator::new_source(Arc::clone(ledger))?;
        let handle = allocator.clone();
        let source_mode = handle
            .source_mode()
            .map_err(|_| io::ErrorKind::WouldBlock)?;
        let hasher = self.answers.shards[0]
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .hasher()
            .clone();
        let mut seen = hashbrown::HashSet::with_hasher_in(hasher, allocator);
        seen.try_reserve(sources.len())
            .map_err(|_| io::ErrorKind::OutOfMemory)?;
        let mut visits = 0usize;
        let max_visits = mapping.source_acquisition_storage().len();
        for (path, lease) in mapping.source_acquisitions() {
            visits = visits.checked_add(1).ok_or(io::ErrorKind::OutOfMemory)?;
            if visits > max_visits {
                return Err(io::ErrorKind::InvalidInput.into());
            }
            crate::daemon::control::checkpoint()?;
            let lease = lease.ok_or(io::ErrorKind::Unsupported)?;
            let (key, (_, prepared, _)) = sources
                .get_key_value(path)
                .ok_or(io::ErrorKind::InvalidInput)?;
            if !prepared.original().same_view(lease.source_text()) {
                return Err(io::ErrorKind::InvalidInput.into());
            }
            seen.insert(key);
        }
        if seen.len() != sources.len() {
            return Err(io::ErrorKind::InvalidInput.into());
        }
        drop(seen);
        drop(source_mode);
        drop(handle);
        let mut current = self
            .answers
            .current
            .write()
            .unwrap_or_else(|e| e.into_inner());
        if current.request != query_request {
            return Err(io::ErrorKind::InvalidInput.into());
        }
        let mut world = xxhash_rust::xxh3::Xxh3::new();
        world.update(b"dm-source-structural-answers-v1\0");
        world.update(&profile.get().to_le_bytes());
        world.update(&tree.declaration_identity().to_le_bytes());
        world.update(
            &Resolver::answer_world(tree.as_ref())
                .ok_or(io::ErrorKind::Unsupported)?
                .to_le_bytes(),
        );
        let world = world.digest128();
        current.reserve_source_stamp((tree.declaration_identity(), world))?;
        let questions = publication
            .questions()
            .map(|q| q.duplicate(self))
            .transpose()?;
        let retention = SharedSourceLease::new(
            ledger
                .reserve(scope_bytes)
                .map_err(|_| io::ErrorKind::OutOfMemory)?,
        );
        let generation = NoWeakArc::new(SourceGeneration {
            retention: retention.clone(),
        });
        let scope = SourceAnswerScopeOwner {
            inner: NoWeakArc::new(SourceAnswerScope {
                db: self.id,
                request: current.request,
                generation: generation.clone(),
                retention,
                world,
                profile,
                questions,
                tree: Arc::downgrade(tree),
                mapping: Arc::downgrade(mapping),
                archive: Arc::downgrade(archive),
            }),
        };
        #[cfg(test)]
        hooks::at(false);
        crate::daemon::control::begin_publication()?;
        current.bind_source_generation(Some(Arc::clone(tree)), world, generation);
        #[cfg(test)]
        hooks::at(true);
        publish(Some(scope));
        Ok(())
    }
    pub(crate) fn source_answer_hash(
        &self,
        scope: &SourceAnswerScope,
        tree: &dm_tree::SemanticTree,
        mapping: &SourceExportMapping,
        archive: &BodyArchive,
        question: Q,
    ) -> io::Result<u128> {
        crate::daemon::control::checkpoint()?;
        if !matches!(question, Q::CertifiedHierarchy { .. }) {
            return Err(io::ErrorKind::Unsupported.into());
        }
        let current = self
            .answers
            .current
            .read()
            .unwrap_or_else(|e| e.into_inner());
        scope.require(self, &current, tree, mapping, archive)?;
        self.source_answer_hash_bound(&current, tree, question)
    }
    pub(super) fn source_answer_hash_bound(
        &self,
        current: &AnswerRequest,
        tree: &dm_tree::SemanticTree,
        question: Q,
    ) -> io::Result<u128> {
        let id = query_id(&question);
        let open = slot_request(current.request);
        let identity = current.identity();
        let mut slots = self.answers.shards[(id as usize) % ANSWER_SHARDS]
            .lock()
            .unwrap_or_else(|e| e.into_inner());
        if let Some(slot) = slots.get_mut(&id) {
            let (slot_tree, slot_world) = current.stamps[slot.stamp as usize];
            if slot.value.query == question && slot_tree == identity && slot_world == current.world
            {
                let hash = slot.value.hash;
                if verify_answers() {
                    let own = source_hash(tree, question)?.0;
                    if own != hash {
                        let n = self
                            .answers
                            .mismatches
                            .fetch_add(1, std::sync::atomic::Ordering::Relaxed);
                        if n < 8 {
                            eprintln!("native answer mismatch (scoped source proven answer): {question:?}");
                        }
                        debug_assert_eq!(
                            own, hash,
                            "answer resolvers disagree (scoped source) on {question:?}"
                        );
                    }
                }
                self.answers.values.retain_source_value(id, &slot.value)?;
                crate::daemon::control::checkpoint()?;
                if slot.request != open {
                    slot.request = open;
                    self.answers
                        .carried
                        .fetch_add(1, std::sync::atomic::Ordering::Relaxed);
                }
                return Ok(hash);
            }
        }
        let (hash, positive) = source_hash(tree, question)?;
        let mut pooled = self.answers.values.shards[(id as usize) % VALUE_SHARDS]
            .lock()
            .unwrap_or_else(|e| e.into_inner());
        let existing = pooled
            .get(&(id as u64))
            .and_then(PooledOwner::upgrade)
            .filter(|v| v.hash == hash && v.query == question);
        let reservation = if existing.as_ref().is_some_and(ValueOwner::source_admitted) {
            None
        } else {
            Some(SourceValueReservation::reserve(
                &self.answers.values.source_ledger,
            )?)
        };
        let slot_handle = slots.allocator().clone();
        let _slot_mode = slot_handle
            .source_mode()
            .map_err(|_| io::ErrorKind::WouldBlock)?;
        let slot_additional = usize::from(!slots.contains_key(&id));
        slots
            .try_reserve(slot_additional)
            .map_err(|_| io::ErrorKind::OutOfMemory)?;
        let pool_handle = pooled.allocator().clone();
        let _pool_mode = pool_handle
            .source_mode()
            .map_err(|_| io::ErrorKind::WouldBlock)?;
        let pool_additional = usize::from(!pooled.contains_key(&(id as u64)));
        pooled
            .try_reserve(pool_additional)
            .map_err(|_| io::ErrorKind::OutOfMemory)?;
        crate::daemon::control::checkpoint()?;
        let value = if let Some(value) = existing {
            if let Some(reservation) = reservation {
                pooled
                    .get_mut(&(id as u64))
                    .expect("held original pool entry")
                    .attach_reserved(&value, reservation)?;
            }
            self.answers.values.outcomes[0].fetch_add(1, std::sync::atomic::Ordering::Relaxed);
            value
        } else {
            let value = reservation
                .expect("new value reservation")
                .value(hash, positive, question);
            pooled.insert(id as u64, PooledOwner::from_owner(&value));
            value
        };
        let prior = slots.remove(&id);
        let replaced = prior.is_some();
        let slot = AnswerSlot::replaced_by(
            prior,
            AnswerSlot {
                request: open,
                stamp: current.stamp,
                value,
                born: 0,
                changed: 0,
                base: None,
            },
        );
        slots.insert(id, slot);
        self.answers
            .resolved
            .fetch_add(1, std::sync::atomic::Ordering::Relaxed);
        if replaced {
            self.answers
                .replaced
                .fetch_add(1, std::sync::atomic::Ordering::Relaxed);
        }
        Ok(hash)
    }
}
#[cfg(test)]
pub(crate) mod hooks {
    use super::*;
    thread_local! {static CANCEL:std::cell::RefCell<Option<(bool,crate::daemon::control::Cancellation)>>=const{std::cell::RefCell::new(None)};}
    pub(crate) struct Scheduled;
    impl Drop for Scheduled {
        fn drop(&mut self) {
            CANCEL.with(|v| *v.borrow_mut() = None);
        }
    }
    pub(crate) fn cancel_at(after: bool, token: crate::daemon::control::Cancellation) -> Scheduled {
        CANCEL.with(|v| {
            assert!(v.borrow().is_none());
            *v.borrow_mut() = Some((after, token));
        });
        Scheduled
    }
    pub(super) fn at(after: bool) {
        CANCEL.with(|v| {
            if let Some((when, token)) = v.borrow().as_ref() {
                if *when == after {
                    token.cancel();
                }
            }
        });
    }
}
#[cfg(test)]
#[path = "source_answer_scope_tests.rs"]
mod tests;

impl QueryDb {
    pub(crate) fn answer_storage_census(self: &Arc<Self>, c: &mut crate::heap_census::HeapCensus) {
        c.arc_object("answers.original_query_db", self);
        c.slice("answers.original_slot_shards", &self.answers.shards, true);
        {
            let current = self
                .answers
                .current
                .read()
                .unwrap_or_else(|e| e.into_inner());
            current.stamps.allocator().census_backing(
                c,
                "answers.original_stamps",
                current.stamps.len() * std::mem::size_of::<(u128, u128)>(),
                current.stamps.len(),
            );
            if let Some(generation) = &current.source_binding {
                // The original current binding can outlive every external
                // SourceSnapshot/scope. Inventory that sole strong owner too.
                if let Ok(plan) = Plan::source_generation() {
                    generation.census_layout(
                        c,
                        "answers.original_source_generation",
                        plan.layout(),
                    );
                } else {
                    generation.census(c, "answers.original_source_generation");
                }
                generation.retention.census_source_lease(c);
            }
        }
        for shard in self.answers.shards.iter() {
            let slots = shard.lock().unwrap_or_else(|e| e.into_inner());
            slots.allocator().census_backing(
                c,
                "answers.original_slots",
                slots.len() * std::mem::size_of::<(u128, AnswerSlot)>(),
                slots.len(),
            );
            for slot in slots.values() {
                slot.value.census(c);
                if let Some(base) = &slot.base {
                    base.census(c);
                }
            }
        }
        if c.arc_object("answers.original_value_pool", &self.answers.values) {
            c.slice(
                "answers.original_value_pool_shards",
                &self.answers.values.shards,
                true,
            );
            for shard in self.answers.values.shards.iter() {
                let pooled = shard.lock().unwrap_or_else(|e| e.into_inner());
                pooled.allocator().census_backing(
                    c,
                    "answers.original_pooled_weak",
                    pooled.len() * std::mem::size_of::<(u64, PooledOwner)>(),
                    pooled.len(),
                );
                for value in pooled.values() {
                    value.census(c);
                }
            }
        }
        let stats = self.answers.values.source_ledger.snapshot();
        c.unknown("answers.source_quota",&format!("source-only admitted reservations live={} peak={}; existing uncapped runtime baseline and allocator RSS are separate",stats.live,stats.peak));
    }
}
