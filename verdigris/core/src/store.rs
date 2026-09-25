//! Component storage (`rust_architecture.md` §4.2): one store per component
//! kind, rows indexed by **entity slot index**.
//!
//! Indexing every kind by the entity's own slot index makes joins free: a
//! law anchored on `Pump` rows reads the same entity's `Consumer` at the
//! same index, with no row↔entity map. Stores are chunked copy-on-write
//! ([`CowStore`], [`KIND_CHUNK`] rows per chunk, unallocated until a row in
//! it is written), so an index space of 2^19 costs only the chunks that
//! hold live rows.
//!
//! A kind's rows live where its [`Ownership`] says:
//! - **worker**: in a `DomainState<C::Kind>` of the world's one
//!   [`crate::sim::Sim`], stepped by frame tasks; DM writes are commands
//!   through the overlay (read-your-writes);
//! - **main**: in [`MainKind`]'s own store on the main thread, written
//!   synchronously (tanks, lungs, anything DM needs back at once).
//!
//! Either way the main thread keeps the authoritative [`Rows`] (which
//! entities have the component) and mirrors changes to the worker side
//! ([`WorkerKind`]) at each frame dispatch, together with a snapshot of a
//! main-owned store so worker laws can read it.

use std::sync::Arc;

use crate::bitset::DenseBitSet;
use crate::component::Component;
use crate::cow::{ChunkLayout, CowStore};
use crate::entity::{EntityId, MAX_SLOTS};
use crate::owner::{Applied, Domain, View, add_conserved};

/// Rows per copy-on-write chunk of a component store: small, so the first
/// write to a shared chunk in a frame copies little.
pub const KIND_CHUNK: u32 = 256;

/// The layout of every component store: one row per entity slot.
#[must_use]
pub const fn kind_layout() -> ChunkLayout {
    ChunkLayout::linear_with_chunk(MAX_SLOTS, KIND_CHUNK)
}

/// Which entity slots hold a component of one kind, and the full id bound
/// at each (for event attribution and staleness checks).
#[derive(Clone, Debug, Default)]
pub struct Rows {
    present: DenseBitSet,
    ids: Vec<u32>,
    count: usize,
}

impl Rows {
    #[must_use]
    pub fn new() -> Self {
        Self::default()
    }

    /// Marks `entity` as holding the component. Returns `false` if it
    /// already did.
    pub fn insert(&mut self, entity: EntityId) -> bool {
        let index = entity.index();
        if index >= self.present.capacity() {
            self.present
                .grow((index + 1).max(self.present.capacity() * 2).min(MAX_SLOTS));
        }
        if self.ids.len() <= index as usize {
            self.ids.resize(index as usize + 1, 0);
        }
        self.ids[index as usize] = entity.bits();
        let fresh = self.present.insert(index);
        if fresh {
            self.count += 1;
        }
        fresh
    }

    /// Clears the row at `index`, returning the entity that held it.
    pub fn remove(&mut self, index: u32) -> Option<EntityId> {
        if !self.present.remove(index) {
            return None;
        }
        self.count -= 1;
        EntityId::from_bits(self.ids[index as usize])
    }

    #[must_use]
    pub fn contains(&self, index: u32) -> bool {
        self.present.contains(index)
    }

    /// Whether exactly `entity` (index and generation) holds the row.
    #[must_use]
    pub fn holds(&self, entity: EntityId) -> bool {
        self.entity(entity.index()) == Some(entity)
    }

    /// The entity holding the row at `index`.
    #[must_use]
    pub fn entity(&self, index: u32) -> Option<EntityId> {
        if !self.contains(index) {
            return None;
        }
        EntityId::from_bits(self.ids[index as usize])
    }

    /// The `vg_entity` value (raw id + 1) of the row at `index`, or `0.0`.
    #[must_use]
    pub fn entity_value(&self, index: u32) -> f32 {
        self.entity(index).map_or(0.0, |e| e.to_f32() + 1.0)
    }

    #[must_use]
    pub const fn len(&self) -> usize {
        self.count
    }

    #[must_use]
    pub const fn is_empty(&self) -> bool {
        self.count == 0
    }

    /// Every held index, ascending.
    pub fn iter(&self) -> impl Iterator<Item = u32> + '_ {
        self.present.iter()
    }

    fn apply(&mut self, change: RowChange) {
        match change {
            RowChange::Bound(e) => {
                self.insert(e);
            }
            RowChange::Unbound(i) => {
                self.remove(i);
            }
        }
    }
}

/// One change to a kind's [`Rows`], journaled on the main thread and
/// replayed on the worker side at dispatch.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum RowChange {
    Bound(EntityId),
    Unbound(u32),
}

/// The main-thread side of one component kind: a resource of the driver's
/// main phase.
pub struct MainKind<C: Component> {
    /// Authoritative: which entities hold the component.
    pub rows: Rows,
    journal: Vec<RowChange>,
    /// Main-owned kinds: the live rows.
    store: Option<CowStore<C>>,
    /// Whether `store` changed since the last worker snapshot.
    dirty: bool,
    /// Worker-owned kinds: the view pinned at the start of this tick (what
    /// main-phase laws read).
    view: Option<Arc<View<C>>>,
    /// Main-owned kinds: cumulative conserved change made by DM's direct
    /// writes (boundary crossings for the conservation check).
    crossings: Vec<(&'static str, f64)>,
}

impl<C: Component> MainKind<C> {
    #[must_use]
    pub fn new(main_owned: bool) -> Self {
        Self {
            rows: Rows::new(),
            journal: Vec::new(),
            store: main_owned.then(|| CowStore::new(kind_layout())),
            dirty: false,
            view: None,
            crossings: Vec::new(),
        }
    }

    #[must_use]
    pub const fn is_main_owned(&self) -> bool {
        self.store.is_some()
    }

    /// The row at `index`, if an entity holds it: the live value for a
    /// main-owned kind, the pinned view's for a worker-owned one.
    #[must_use]
    pub fn get(&self, index: u32) -> Option<C> {
        if !self.rows.contains(index) {
            return None;
        }
        match (&self.store, &self.view) {
            (Some(store), _) => store.get(index),
            (None, Some(view)) => view.get(index),
            (None, None) => None,
        }
    }

    /// Shared access to a main-owned row.
    #[must_use]
    pub fn get_ref(&self, index: u32) -> Option<&C> {
        if !self.rows.contains(index) {
            return None;
        }
        let store = self.store.as_ref()?;
        let (chunk, cell) = store.layout().locate(index)?;
        store.chunk(chunk).map(|c| &c[cell])
    }

    /// Mutable access to a main-owned row (a main-phase law's write, or a
    /// typed main-thread caller). `None` for a worker-owned kind.
    pub fn get_mut(&mut self, index: u32) -> Option<&mut C> {
        if !self.rows.contains(index) {
            return None;
        }
        let store = self.store.as_mut()?;
        self.dirty = true;
        store.get_mut(index)
    }

    /// Applies a DM command to a main-owned row, recording its effect on
    /// conserved quantities as a boundary crossing.
    pub fn apply(&mut self, index: u32, cmd: &<C::Kind as Domain>::Command) -> Option<Applied> {
        if !self.rows.contains(index) {
            return None;
        }
        let store = self.store.as_mut()?;
        let value = store.get_mut(index)?;
        self.dirty = true;
        if <C::Kind as Domain>::CONSERVES {
            add_conserved::<C::Kind>(&mut self.crossings, value, -1.0);
        }
        let applied = <C::Kind as Domain>::apply(value, cmd);
        if <C::Kind as Domain>::CONSERVES {
            add_conserved::<C::Kind>(&mut self.crossings, value, 1.0);
        }
        Some(applied)
    }

    /// Binds `entity` with `value` (main-owned: stored now; worker-owned:
    /// the caller also puts the value through the domain's port).
    pub fn bind(&mut self, entity: EntityId, value: C) {
        self.rows.insert(entity);
        self.journal.push(RowChange::Bound(entity));
        if let Some(store) = &mut self.store {
            if <C::Kind as Domain>::CONSERVES {
                add_conserved::<C::Kind>(&mut self.crossings, &value, 1.0);
            }
            store.set(entity.index(), value);
            self.dirty = true;
        }
    }

    /// Replaces a main-owned row from outside the laws (a DM or bridge
    /// transfer in), recording the conserved difference as a crossing.
    /// Returns `false` if the row is not held or the kind is worker-owned.
    pub fn replace(&mut self, index: u32, value: C) -> bool {
        if !self.rows.contains(index) {
            return false;
        }
        let Some(store) = self.store.as_mut() else {
            return false;
        };
        if <C::Kind as Domain>::CONSERVES {
            if let Some(old) = store.get(index) {
                add_conserved::<C::Kind>(&mut self.crossings, &old, -1.0);
            }
            add_conserved::<C::Kind>(&mut self.crossings, &value, 1.0);
        }
        store.set(index, value);
        self.dirty = true;
        true
    }

    /// Unbinds the row at `index`, returning its last value (main-owned).
    pub fn unbind(&mut self, index: u32) -> Option<C> {
        self.rows.remove(index)?;
        self.journal.push(RowChange::Unbound(index));
        let store = self.store.as_mut()?;
        let old = store.get(index);
        if let Some(v) = &old
            && <C::Kind as Domain>::CONSERVES
        {
            add_conserved::<C::Kind>(&mut self.crossings, v, -1.0);
        }
        store.set(index, C::default());
        self.dirty = true;
        old
    }

    /// Records the view pinned this tick (worker-owned kinds).
    pub fn set_view(&mut self, view: Arc<View<C>>) {
        self.view = Some(view);
    }

    /// The live store of a main-owned kind.
    #[must_use]
    pub fn store(&self) -> Option<&CowStore<C>> {
        self.store.as_ref()
    }

    /// Cumulative conserved change made by DM writes (main-owned kinds).
    #[must_use]
    pub fn crossings(&self) -> &[(&'static str, f64)] {
        &self.crossings
    }

    /// Moves this tick's row changes (and a snapshot of a changed
    /// main-owned store) into the worker side. The driver calls this at
    /// each frame dispatch.
    pub fn sync_worker(&mut self, worker: &mut WorkerKind<C>) {
        for change in self.journal.drain(..) {
            worker.rows.apply(change);
        }
        if self.dirty
            && let Some(store) = &self.store
        {
            worker.snapshot = Some(store.snapshot());
            self.dirty = false;
        }
    }
}

/// The worker side of one component kind: a resource of the frame world.
pub struct WorkerKind<C: Component> {
    /// Mirror of [`MainKind::rows`] as of the last dispatch.
    pub rows: Rows,
    /// Main-owned kinds: the store as of the last dispatch (worker laws
    /// read it; they never write it).
    snapshot: Option<CowStore<C>>,
}

impl<C: Component> Default for WorkerKind<C> {
    fn default() -> Self {
        Self {
            rows: Rows::new(),
            snapshot: None,
        }
    }
}

impl<C: Component> WorkerKind<C> {
    /// A main-owned kind's row as of the last dispatch.
    #[must_use]
    pub fn snapshot_get(&self, index: u32) -> Option<C> {
        if !self.rows.contains(index) {
            return None;
        }
        self.snapshot.as_ref()?.get(index)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rows_track_entities_by_slot() {
        let mut rows = Rows::new();
        let e = EntityId::from_bits(5 | (3 << crate::entity::INDEX_BITS)).unwrap();
        assert!(rows.insert(e));
        assert!(!rows.insert(e));
        assert!(rows.holds(e));
        assert_eq!(rows.entity(5), Some(e));
        assert_eq!(rows.len(), 1);
        assert_eq!(rows.iter().collect::<Vec<_>>(), vec![5]);
        assert_eq!(rows.remove(5), Some(e));
        assert!(rows.is_empty());
        assert_eq!(rows.entity_value(5), 0.0);
    }
}
