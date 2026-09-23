//! Entities and components (`rust_bindings.md` §1, §4, §13).
//!
//! A bound DM atom has one Rust *entity*: a generation-checked [`Handle`]
//! (DM's `vg_entity`) whose slot holds, for each domain that has attached a
//! component to it, a small [`ComponentRef`] naming which component *kind*
//! and where that kind's own store keeps its data. Domains never reach into
//! each other's storage through DM: a component's coupling step (its
//! `couple`, §2) reads its entity's other components directly inside Rust.
//!
//! A component kind's own values live in that kind's `MainPort<D>` (R4), at
//! the plain `u32` index a [`ComponentRef`] names. That index needs no
//! generation of its own: every path that reaches it first resolves the
//! entity handle through this table, and the entity handle is the one thing
//! that is generation-checked (§9 "handles are generation-checked, so
//! reusing a slot can't alias"). [`CellAllocator`] hands out and reuses those
//! plain indices.

use std::fmt;

use crate::arena::{Arena, ArenaError};
use crate::handle::Handle;

/// Domains that may attach a component to one entity. Generous headroom: an
/// unused slot costs 8 bytes (`Option<ComponentRef>`), and entities are far
/// fewer than component fields.
pub const MAX_DOMAINS: usize = 8;

/// Where one domain's component for an entity lives: which kind (a
/// domain-scoped numeric id generated as a DM define, e.g. `VG_GAS_PUMP`)
/// and its slot in that kind's own store.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct ComponentRef {
    pub kind: u16,
    pub cell: u32,
}

impl ComponentRef {
    #[must_use]
    pub const fn new(kind: u16, cell: u32) -> Self {
        Self { kind, cell }
    }
}

/// One entity's components, one optional slot per domain index. The
/// entity-table value type: cheap to default (every domain slot empty) and
/// to copy.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct EntitySlots {
    components: [Option<ComponentRef>; MAX_DOMAINS],
}

impl EntitySlots {
    /// The component attached for `domain`, if any. `None` (never a panic)
    /// for a `domain` past [`MAX_DOMAINS`].
    #[must_use]
    pub fn get(&self, domain: usize) -> Option<ComponentRef> {
        self.components.get(domain).copied().flatten()
    }

    fn set(&mut self, domain: usize, value: Option<ComponentRef>) -> bool {
        match self.components.get_mut(domain) {
            Some(slot) => {
                *slot = value;
                true
            }
            None => false,
        }
    }

    /// No domain has a component here (the entity is ready to be unbound).
    #[must_use]
    pub fn is_empty(&self) -> bool {
        self.components.iter().all(Option::is_none)
    }

    /// Live `(domain, component)` pairs, in domain order.
    pub fn iter(&self) -> impl Iterator<Item = (usize, ComponentRef)> + '_ {
        self.components
            .iter()
            .enumerate()
            .filter_map(|(d, c)| c.map(|c| (d, c)))
    }
}

/// Why an entity or component lookup failed (`rust_bindings.md` §9): typed,
/// so the FFI layer can report `(component, field, handle, reason)` to DM.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum EntityError {
    /// The entity slot was freed (and maybe reused) since the handle was issued.
    Stale,
    /// The index was never allocated.
    OutOfRange,
    /// Every one of the 2^20 entity slots is in use.
    Full,
    /// The entity is live but has no component for that domain.
    NoComponent { domain: usize },
    /// The entity has a component for that domain, but of a different kind
    /// than the caller expected (a `set_*` generated for one component
    /// called through an atom now holding another).
    WrongKind { domain: usize, expected: u16, found: u16 },
    /// `domain` is not a valid domain index (past [`MAX_DOMAINS`]).
    BadDomain { domain: usize },
}

impl fmt::Display for EntityError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Stale => write!(f, "stale entity handle"),
            Self::OutOfRange => write!(f, "entity handle index out of range"),
            Self::Full => write!(f, "entity table is full"),
            Self::NoComponent { domain } => write!(f, "entity has no component for domain {domain}"),
            Self::WrongKind {
                domain,
                expected,
                found,
            } => write!(
                f,
                "entity's domain {domain} component is kind {found}, expected {expected}"
            ),
            Self::BadDomain { domain } => write!(f, "domain {domain} is not a valid domain index"),
        }
    }
}

impl std::error::Error for EntityError {}

fn map_arena_err(e: ArenaError) -> EntityError {
    match e {
        ArenaError::Stale => EntityError::Stale,
        ArenaError::OutOfRange => EntityError::OutOfRange,
        ArenaError::Full => EntityError::Full,
    }
}

/// The entity table: DM's `vg_entity` (§1, §4). One per world; every store
/// (including this one) is dropped and rebuilt at `verdigris_init()` (§4),
/// so no handle survives a round.
#[derive(Default)]
pub struct EntityTable {
    arena: Arena<EntitySlots>,
}

impl EntityTable {
    #[must_use]
    pub fn new() -> Self {
        Self::default()
    }

    /// Reserves a new, empty entity. Callers attach its components next
    /// (§4's "one call creates the entity and its components").
    ///
    /// # Errors
    /// [`EntityError::Full`] if every slot is in use.
    pub fn bind(&mut self) -> Result<Handle<EntitySlots>, EntityError> {
        self.arena.insert(EntitySlots::default()).map_err(map_arena_err)
    }

    /// Attaches (or replaces) `domain`'s component on a live entity.
    ///
    /// # Errors
    /// [`EntityError::Stale`]/[`OutOfRange`](EntityError::OutOfRange) for a
    /// bad handle, [`EntityError::BadDomain`] for `domain >= MAX_DOMAINS`.
    pub fn attach(
        &mut self,
        entity: Handle<EntitySlots>,
        domain: usize,
        comp: ComponentRef,
    ) -> Result<(), EntityError> {
        let slots = self.arena.get_mut(entity).map_err(map_arena_err)?;
        if !slots.set(domain, Some(comp)) {
            return Err(EntityError::BadDomain { domain });
        }
        Ok(())
    }

    /// Detaches `domain`'s component, returning it if there was one.
    ///
    /// # Errors
    /// As [`attach`](Self::attach).
    pub fn detach(
        &mut self,
        entity: Handle<EntitySlots>,
        domain: usize,
    ) -> Result<Option<ComponentRef>, EntityError> {
        let slots = self.arena.get_mut(entity).map_err(map_arena_err)?;
        let previous = slots.get(domain);
        if !slots.set(domain, None) {
            return Err(EntityError::BadDomain { domain });
        }
        Ok(previous)
    }

    /// The resolved component for `domain`, checked against `expected_kind`
    /// (§5 "resolves the handle and component").
    ///
    /// # Errors
    /// [`EntityError::Stale`]/[`OutOfRange`](EntityError::OutOfRange) for a
    /// bad handle, [`EntityError::NoComponent`] if the entity has none for
    /// that domain, [`EntityError::WrongKind`] if it has a different kind.
    pub fn component(
        &self,
        entity: Handle<EntitySlots>,
        domain: usize,
        expected_kind: u16,
    ) -> Result<ComponentRef, EntityError> {
        let slots = self.arena.get(entity).map_err(map_arena_err)?;
        let comp = slots.get(domain).ok_or(EntityError::NoComponent { domain })?;
        if comp.kind != expected_kind {
            return Err(EntityError::WrongKind {
                domain,
                expected: expected_kind,
                found: comp.kind,
            });
        }
        Ok(comp)
    }

    /// Every component currently attached to `entity`, in domain order.
    ///
    /// # Errors
    /// As [`component`](Self::component), minus the kind check.
    pub fn components(&self, entity: Handle<EntitySlots>) -> Result<EntitySlots, EntityError> {
        self.arena.get(entity).copied().map_err(map_arena_err)
    }

    /// Removes the entity. Callers must have already detached every
    /// component (unbind tears its components down first, §4); this only
    /// asserts none are left, since a leftover component would mean a
    /// domain's store still points at a freed entity.
    ///
    /// # Errors
    /// [`EntityError::Stale`]/[`OutOfRange`](EntityError::OutOfRange) for a
    /// bad handle. Returns the freed slots (debug assertion: always empty).
    pub fn unbind(&mut self, entity: Handle<EntitySlots>) -> Result<EntitySlots, EntityError> {
        let slots = self.arena.remove(entity).map_err(map_arena_err)?;
        debug_assert!(
            slots.is_empty(),
            "unbind: entity still has attached components; detach them first"
        );
        Ok(slots)
    }

    #[must_use]
    pub fn contains(&self, entity: Handle<EntitySlots>) -> bool {
        self.arena.contains(entity)
    }

    /// Live entities.
    #[must_use]
    pub fn len(&self) -> usize {
        self.arena.len()
    }

    #[must_use]
    pub fn is_empty(&self) -> bool {
        self.arena.is_empty()
    }

    /// Live entities and their components, for the reconciler (§7) and
    /// `vg_describe()` (§3).
    pub fn iter(&self) -> impl Iterator<Item = (Handle<EntitySlots>, &EntitySlots)> {
        self.arena.iter()
    }
}

/// A free-list index allocator for a component kind's own store
/// (`rust_bindings.md` §13's "components in arenas"). Cells are plain `u32`
/// indices into that kind's `MainPort`; they carry no generation of their
/// own; see the module docs for why that's safe.
#[derive(Debug, Default, Clone)]
pub struct CellAllocator {
    next: u32,
    free: Vec<u32>,
}

impl CellAllocator {
    #[must_use]
    pub const fn new() -> Self {
        Self {
            next: 0,
            free: Vec::new(),
        }
    }

    /// Allocates a cell, reusing a freed one if any.
    pub fn alloc(&mut self) -> u32 {
        self.free.pop().unwrap_or_else(|| {
            let cell = self.next;
            self.next += 1;
            cell
        })
    }

    /// Returns a cell for reuse. Callers must have already reset its value
    /// (`MainPort::take`, §5's unbind path).
    pub fn free_cell(&mut self, cell: u32) {
        self.free.push(cell);
    }

    /// Cells currently allocated.
    #[must_use]
    pub fn live(&self) -> usize {
        (self.next as usize).saturating_sub(self.free.len())
    }

    /// One past the highest cell ever allocated (the store's high-water mark).
    #[must_use]
    pub const fn high_water(&self) -> u32 {
        self.next
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn bind_attach_detach_unbind_round_trip() {
        let mut table = EntityTable::new();
        let e = table.bind().unwrap();
        assert!(table.contains(e));
        assert_eq!(table.component(e, 0, 7), Err(EntityError::NoComponent { domain: 0 }));

        table.attach(e, 0, ComponentRef::new(7, 42)).unwrap();
        assert_eq!(table.component(e, 0, 7), Ok(ComponentRef::new(7, 42)));
        assert_eq!(
            table.component(e, 0, 8),
            Err(EntityError::WrongKind {
                domain: 0,
                expected: 8,
                found: 7
            })
        );

        table.attach(e, 1, ComponentRef::new(3, 1)).unwrap();
        let comps: Vec<_> = table.components(e).unwrap().iter().collect();
        assert_eq!(comps, vec![(0, ComponentRef::new(7, 42)), (1, ComponentRef::new(3, 1))]);

        assert_eq!(table.detach(e, 0, ).unwrap(), Some(ComponentRef::new(7, 42)));
        assert_eq!(table.detach(e, 1).unwrap(), Some(ComponentRef::new(3, 1)));
        assert!(table.unbind(e).unwrap().is_empty());
        assert!(!table.contains(e));
        assert_eq!(table.component(e, 0, 7), Err(EntityError::Stale));
    }

    #[test]
    fn stale_and_reused_handles_never_alias() {
        let mut table = EntityTable::new();
        let a = table.bind().unwrap();
        table.attach(a, 0, ComponentRef::new(1, 0)).unwrap();
        table.detach(a, 0).unwrap();
        table.unbind(a).unwrap();
        let b = table.bind().unwrap();
        assert_eq!(a.index(), b.index(), "same slot reused");
        assert_eq!(table.component(a, 0, 1), Err(EntityError::Stale));
        assert_eq!(table.component(b, 0, 1), Err(EntityError::NoComponent { domain: 0 }));
    }

    #[test]
    fn bad_domain_is_reported_not_panicked() {
        let mut table = EntityTable::new();
        let e = table.bind().unwrap();
        assert_eq!(
            table.attach(e, MAX_DOMAINS, ComponentRef::new(1, 0)),
            Err(EntityError::BadDomain { domain: MAX_DOMAINS })
        );
        assert_eq!(table.component(e, MAX_DOMAINS, 1), Err(EntityError::NoComponent { domain: MAX_DOMAINS }));
    }

    #[test]
    fn cell_allocator_reuses_freed_cells() {
        let mut a = CellAllocator::new();
        let c0 = a.alloc();
        let c1 = a.alloc();
        assert_ne!(c0, c1);
        assert_eq!(a.live(), 2);
        a.free_cell(c0);
        assert_eq!(a.live(), 1);
        let c2 = a.alloc();
        assert_eq!(c2, c0, "freed cells are reused");
        assert_eq!(a.high_water(), 2);
    }
}
