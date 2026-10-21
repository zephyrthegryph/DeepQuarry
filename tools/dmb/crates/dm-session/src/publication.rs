//! Publication ownership for existing observed artifact leases.
//! A failed attempt releases its claims without replacing the last successful
//! group. This is lifecycle coordination, not an additional artifact store.
use std::sync::{Arc, Mutex, RwLock};

/// Opaque attempt identity; equality never depends on a wrapping counter.
#[derive(Clone)]
pub struct ArtifactGeneration(Arc<()>);
impl ArtifactGeneration {
    pub fn same_as(&self, other: &Self) -> bool {
        Arc::ptr_eq(&self.0, &other.0)
    }
}

struct State<L> {
    latest: Option<ArtifactGeneration>,
    published: Option<Arc<L>>,
}

pub struct ArtifactPublication<L> {
    state: Mutex<State<L>>,
}
impl<L> Default for ArtifactPublication<L> {
    fn default() -> Self {
        Self {
            state: Mutex::new(State {
                latest: None,
                published: None,
            }),
        }
    }
}
impl<L> ArtifactPublication<L> {
    pub fn begin(self: &Arc<Self>, pending: L) -> ArtifactAttempt<L> {
        let generation = ArtifactGeneration(Arc::new(()));
        self.state.lock().unwrap_or_else(|e| e.into_inner()).latest = Some(generation.clone());
        self.attempt(pending, generation)
    }

    /// Analysis may claim reusable values without superseding a build or
    /// publishing a partial program roster.
    pub fn begin_ephemeral(self: &Arc<Self>, pending: L) -> ArtifactAttempt<L> {
        self.attempt(pending, ArtifactGeneration(Arc::new(())))
    }

    fn attempt(self: &Arc<Self>, pending: L, generation: ArtifactGeneration) -> ArtifactAttempt<L> {
        ArtifactAttempt {
            owner: Arc::clone(self),
            generation,
            pending: RwLock::new(Some(Arc::new(pending))),
        }
    }

    pub fn is_latest(&self, generation: &ArtifactGeneration) -> bool {
        self.state
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .latest
            .as_ref()
            .is_some_and(|latest| latest.same_as(generation))
    }

    /// Inspect published bookkeeping only. Artifact admission must still use
    /// the request's pending lease and the ordinary observation host.
    pub fn with_published<R>(&self, inspect: impl FnOnce(&L) -> R) -> Option<R> {
        // Clone ownership under the lock, then run caller code outside it.
        let published = self
            .state
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .published
            .clone();
        published.as_deref().map(inspect)
    }
}

pub struct ArtifactAttempt<L> {
    owner: Arc<ArtifactPublication<L>>,
    generation: ArtifactGeneration,
    pending: RwLock<Option<Arc<L>>>,
}
impl<L> ArtifactAttempt<L> {
    pub fn generation(&self) -> &ArtifactGeneration {
        &self.generation
    }
    pub fn is_latest(&self) -> bool {
        self.owner.is_latest(&self.generation)
    }

    /// The read guard prevents publication while an operation is admitting or
    /// recording claims. After sealing, no operation can mutate published claims.
    pub fn with_pending<R>(&self, operation: impl FnOnce(&L) -> R) -> Option<R> {
        let pending = self.pending.read().unwrap_or_else(|e| e.into_inner());
        pending.as_deref().map(operation)
    }

    /// Explicitly release request claims while preserving successful ownership.
    /// Long-lived facades use this when their request guard is dropped.
    pub fn abort(&self) {
        let detached = self
            .pending
            .write()
            .unwrap_or_else(|e| e.into_inner())
            .take();
        drop(detached);
    }
}
impl<L: Send + Sync + 'static> ArtifactAttempt<L> {
    /// Call only after required request publication succeeds. A superseded
    /// attempt releases its claims and cannot overwrite newer ownership.
    pub fn publish_successful(&self) -> bool {
        let pending = self
            .pending
            .write()
            .unwrap_or_else(|e| e.into_inner())
            .take();
        let Some(pending) = pending else {
            return false;
        };
        let (accepted, detached) = {
            let mut state = self.owner.state.lock().unwrap_or_else(|e| e.into_inner());
            if state
                .latest
                .as_ref()
                .is_some_and(|latest| latest.same_as(&self.generation))
            {
                (true, state.published.replace(pending))
            } else {
                (false, Some(pending))
            }
        };
        // Lease destruction can acquire artifact-core locks or release other
        // backing. Neither the publication mutex nor pending guard is held.
        // The replaced group releases its claims off the request's critical
        // path (a session's previous lease holds one claim per reused artifact).
        if let Some(detached) = detached {
            release_detached(detached);
        }
        accepted
    }
}

static BACKGROUND_RELEASE: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(false);
/// A resident server releases replaced publication groups off the request path (see
/// [`ArtifactAttempt::publish_successful`]); otherwise they are released synchronously.
pub fn release_replaced_in_background(enabled: bool) {
    BACKGROUND_RELEASE.store(enabled, std::sync::atomic::Ordering::Relaxed);
}
/// Drop a replaced publication group. Groups held elsewhere only lose a reference; with
/// background release the last owner releases it on a short-lived thread, so publication
/// returns at once.
fn release_detached<L: Send + Sync + 'static>(detached: Arc<L>) {
    if Arc::strong_count(&detached) > 1
        || !BACKGROUND_RELEASE.load(std::sync::atomic::Ordering::Relaxed)
    {
        drop(detached);
        return;
    }
    // A failed spawn drops the closure, and the group with it, here.
    let _ = std::thread::Builder::new()
        .name("dm-session-release".into())
        .spawn(move || drop(detached));
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::{
        atomic::{AtomicUsize, Ordering},
        Weak,
    };
    struct Group {
        owner: Weak<ArtifactPublication<Group>>,
        drops: Arc<AtomicUsize>,
        value: usize,
    }
    impl Drop for Group {
        fn drop(&mut self) {
            if let Some(owner) = self.owner.upgrade() {
                assert!(
                    owner.state.try_lock().is_ok(),
                    "lease dropped under publication lock"
                );
            }
            self.drops.fetch_add(1, Ordering::Relaxed);
        }
    }
    fn begin(
        owner: &Arc<ArtifactPublication<Group>>,
        drops: &Arc<AtomicUsize>,
        value: usize,
    ) -> ArtifactAttempt<Group> {
        owner.begin(Group {
            owner: Arc::downgrade(owner),
            drops: drops.clone(),
            value,
        })
    }
    #[test]
    fn failed_and_superseded_attempts_preserve_published_ownership_and_seal_operations() {
        let owner = Arc::new(ArtifactPublication::default());
        let drops = Arc::new(AtomicUsize::new(0));
        let first = begin(&owner, &drops, 1);
        assert!(first.publish_successful());
        assert_eq!(
            first.with_pending(|_| panic!("sealed operation")),
            None::<()>
        );
        let aborted = begin(&owner, &drops, 2);
        aborted.abort();
        assert!(aborted.with_pending(|_| ()).is_none());
        assert!(!aborted.publish_successful());
        drop(aborted);
        assert_eq!(owner.with_published(|group| group.value), Some(1));
        let older = begin(&owner, &drops, 3);
        let newer = begin(&owner, &drops, 4);
        assert!(!older.generation().same_as(newer.generation()));
        assert!(newer.publish_successful());
        assert!(!older.publish_successful());
        assert_eq!(owner.with_published(|group| group.value), Some(4));
        assert!(!newer.publish_successful());
        assert_eq!(drops.load(Ordering::Relaxed), 3);
        drop(older);
        drop(newer);
        drop(first);
        drop(owner);
        assert_eq!(drops.load(Ordering::Relaxed), 4);
    }

    #[test]
    fn analysis_cannot_supersede_or_publish_a_build_roster() {
        let owner = Arc::new(ArtifactPublication::default());
        let build = owner.begin(17);
        let analysis = owner.begin_ephemeral(29);
        assert_eq!(analysis.with_pending(|value| *value), Some(29));
        assert!(build.is_latest());
        assert!(!analysis.publish_successful());
        assert!(build.publish_successful());
        assert_eq!(owner.with_published(|value| *value), Some(17));
    }
}
