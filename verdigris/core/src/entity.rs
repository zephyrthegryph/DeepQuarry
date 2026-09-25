//! Entities and components (`rust_architecture.md` §4.1–§4.2).
//!
//! A bound DM atom has one Rust *entity*: [`EntityId`], the **only** handle
//! type that crosses to DM (as `vg_entity`). Its slot holds, for each domain
//! that has attached a component to it, a small [`ComponentRef`] naming
//! which component *kind* and where that kind's own store keeps its data.
//! Domains never reach into each other's storage through DM: a component's
//! coupling step reads its entity's other components directly inside Rust.
//!
//! A component kind's own values live in that kind's store
//! ([`crate::store`]), at the entity's slot index: the row needs no
//! generation of its own, because every path that reaches it first resolves
//! the entity id, the one thing that is generation-checked. The
//! [`crate::world::World`] records its own kinds in [`crate::store::Rows`];
//! the per-domain [`ComponentRef`] slots here remain for hosts that have not
//! moved onto the world yet, plus [`WORLD_DOMAIN`], which marks an entity
//! the world holds components for.
//!
//! Grid cells are not entities (`rust_architecture.md` §4.1): they are
//! addressed by coordinate (`grid::Grid`/`CellId`), never bound here.

use std::collections::VecDeque;
use std::fmt;

/// Slot bits: 524,288 live entities addressable at once.
pub const INDEX_BITS: u32 = 19;
/// Generation bits: 32 generations per slot.
pub const GENERATION_BITS: u32 = 5;
/// Number of addressable slots (2^19).
pub const MAX_SLOTS: u32 = 1 << INDEX_BITS;
/// Largest generation value (31).
pub const MAX_GENERATION: u8 = (1 << GENERATION_BITS) - 1;
/// A freed slot is reused only once this many *other* slots have also been
/// freed since (`rust_architecture.md` §4.1's quarantined FIFO). Aliasing a
/// stale handle would need 32 reuses of one slot, each behind a quarantine
/// this long — the generation check is a debug assertion backed by a real
/// one, not the only defence.
pub const QUARANTINE: usize = 4096;

const INDEX_MASK: u32 = MAX_SLOTS - 1;
const PACKED_MASK: u32 = (1 << (INDEX_BITS + GENERATION_BITS)) - 1;

/// The DM-facing identity: a 19-bit slot index plus a 5-bit generation,
/// packed into the low 24 bits of a `u32` so it is exact as an `f32`.
/// [`EntityTable`] is the only place these are issued.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub struct EntityId(u32);

impl EntityId {
    #[must_use]
    const fn new(index: u32, generation: u8) -> Option<Self> {
        if index > INDEX_MASK || generation > MAX_GENERATION {
            return None;
        }
        Some(Self(index | ((generation as u32) << INDEX_BITS)))
    }

    /// Unpacks a raw `u32`; `None` if any bit above bit 23 is set.
    #[must_use]
    pub const fn from_bits(bits: u32) -> Option<Self> {
        if bits & !PACKED_MASK != 0 {
            return None;
        }
        Some(Self(bits))
    }

    #[must_use]
    pub const fn bits(self) -> u32 {
        self.0
    }

    #[must_use]
    pub const fn index(self) -> u32 {
        self.0 & INDEX_MASK
    }

    #[must_use]
    pub const fn generation(self) -> u8 {
        (self.0 >> INDEX_BITS) as u8
    }

    /// The id as a DM number. Exact: every packed value is below 2^24.
    #[must_use]
    #[allow(clippy::cast_precision_loss)]
    pub const fn to_f32(self) -> f32 {
        self.0 as f32
    }

    /// Reads an id back from a DM number. Rejects fractions, negatives, NaN
    /// and values that do not fit 24 bits.
    #[must_use]
    #[allow(clippy::cast_possible_truncation, clippy::cast_sign_loss)]
    pub fn from_f32(value: f32) -> Option<Self> {
        if !(0.0..=PACKED_MASK as f32).contains(&value) || value.fract() != 0.0 {
            return None;
        }
        Self::from_bits(value as u32)
    }
}

/// Domains that may attach a component to one entity. Generous headroom: an
/// unused slot costs 8 bytes (`Option<ComponentRef>`), and entities are far
/// fewer than component fields.
pub const MAX_DOMAINS: usize = 8;

/// The domain slot `vg-ffi` sets on an entity that has components in the
/// [`crate::world::World`], so the generic unbind reaches the world.
pub const WORLD_DOMAIN: usize = MAX_DOMAINS - 1;

/// Where one domain's component for an entity lives: which kind (a
/// domain-scoped numeric id generated as a DM define, e.g. `VG_GAS_PUMP`)
/// and its row in that kind's own store.
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
    /// The entity slot was freed (and maybe reused) since the id was issued.
    Stale,
    /// The index was never allocated.
    OutOfRange,
    /// Every one of the 2^19 entity slots is in use.
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
            Self::Stale => write!(f, "stale entity id"),
            Self::OutOfRange => write!(f, "entity id index out of range"),
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

struct Slot {
    generation: u8,
    live: Option<EntitySlots>,
}

/// The entity table: DM's `vg_entity` (`rust_architecture.md` §4.1). One per
/// world; every store (including this one) is dropped and rebuilt at
/// `verdigris_init()`, so no id survives a round.
pub struct EntityTable {
    slots: Vec<Slot>,
    /// Freed slots, oldest first; a slot becomes reusable once [`QUARANTINE`]
    /// others have been freed after it.
    quarantine: VecDeque<u32>,
    len: usize,
}

impl Default for EntityTable {
    fn default() -> Self {
        Self::new()
    }
}

impl EntityTable {
    #[must_use]
    pub const fn new() -> Self {
        Self {
            slots: Vec::new(),
            quarantine: VecDeque::new(),
            len: 0,
        }
    }

    /// Reserves a new, empty entity. Callers attach its components next
    /// (§4.1's "one call creates the entity and its components").
    ///
    /// # Errors
    /// [`EntityError::Full`] if every slot is in use or quarantined.
    pub fn bind(&mut self) -> Result<EntityId, EntityError> {
        let index = if self.quarantine.len() > QUARANTINE {
            self.quarantine.pop_front().expect("checked non-empty")
        } else {
            let next = self.slots.len();
            if next >= MAX_SLOTS as usize {
                return Err(EntityError::Full);
            }
            self.slots.push(Slot {
                generation: 0,
                live: None,
            });
            u32::try_from(next).expect("below MAX_SLOTS")
        };
        let slot = &mut self.slots[index as usize];
        debug_assert!(slot.live.is_none());
        slot.live = Some(EntitySlots::default());
        self.len += 1;
        Ok(EntityId::new(index, slot.generation).expect("index and generation in range"))
    }

    fn slot(&self, id: EntityId) -> Result<&Slot, EntityError> {
        let slot = self
            .slots
            .get(id.index() as usize)
            .ok_or(EntityError::OutOfRange)?;
        if slot.generation != id.generation() || slot.live.is_none() {
            return Err(EntityError::Stale);
        }
        Ok(slot)
    }

    fn slot_mut(&mut self, id: EntityId) -> Result<&mut Slot, EntityError> {
        let slot = self
            .slots
            .get_mut(id.index() as usize)
            .ok_or(EntityError::OutOfRange)?;
        if slot.generation != id.generation() || slot.live.is_none() {
            return Err(EntityError::Stale);
        }
        Ok(slot)
    }

    /// Attaches (or replaces) `domain`'s component on a live entity.
    ///
    /// # Errors
    /// [`EntityError::Stale`]/[`OutOfRange`](EntityError::OutOfRange) for a
    /// bad id, [`EntityError::BadDomain`] for `domain >= MAX_DOMAINS`.
    pub fn attach(&mut self, entity: EntityId, domain: usize, comp: ComponentRef) -> Result<(), EntityError> {
        let slots = self.slot_mut(entity)?.live.as_mut().expect("checked live");
        if !slots.set(domain, Some(comp)) {
            return Err(EntityError::BadDomain { domain });
        }
        Ok(())
    }

    /// Detaches `domain`'s component, returning it if there was one.
    ///
    /// # Errors
    /// As [`attach`](Self::attach).
    pub fn detach(&mut self, entity: EntityId, domain: usize) -> Result<Option<ComponentRef>, EntityError> {
        let slots = self.slot_mut(entity)?.live.as_mut().expect("checked live");
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
    /// bad id, [`EntityError::NoComponent`] if the entity has none for that
    /// domain, [`EntityError::WrongKind`] if it has a different kind.
    pub fn component(&self, entity: EntityId, domain: usize, expected_kind: u16) -> Result<ComponentRef, EntityError> {
        let slots = self.slot(entity)?.live.as_ref().expect("checked live");
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
    pub fn components(&self, entity: EntityId) -> Result<EntitySlots, EntityError> {
        Ok(*self.slot(entity)?.live.as_ref().expect("checked live"))
    }

    /// Removes the entity, queuing its slot for quarantine. Callers must
    /// have already detached every component (unbind tears its components
    /// down first, §4.1); this only asserts none are left, since a leftover
    /// component would mean a domain's store still points at a freed entity.
    ///
    /// # Errors
    /// [`EntityError::Stale`]/[`OutOfRange`](EntityError::OutOfRange) for a
    /// bad id. Returns the freed slots (debug assertion: always empty).
    pub fn unbind(&mut self, entity: EntityId) -> Result<EntitySlots, EntityError> {
        let index = entity.index();
        let slot = self.slot_mut(entity)?;
        let slots = slot.live.take().expect("checked live");
        debug_assert!(
            slots.is_empty(),
            "unbind: entity still has attached components; detach them first"
        );
        slot.generation = if slot.generation == MAX_GENERATION {
            0
        } else {
            slot.generation + 1
        };
        self.len -= 1;
        self.quarantine.push_back(index);
        Ok(slots)
    }

    #[must_use]
    pub fn contains(&self, entity: EntityId) -> bool {
        self.slot(entity).is_ok()
    }

    /// Live entities.
    #[must_use]
    pub const fn len(&self) -> usize {
        self.len
    }

    #[must_use]
    pub const fn is_empty(&self) -> bool {
        self.len == 0
    }

    /// Slots currently in quarantine (freed, not yet reusable).
    #[must_use]
    pub fn quarantined(&self) -> usize {
        self.quarantine.len().min(QUARANTINE)
    }

    /// Live entities and their components, for the reconciler and
    /// `vg_describe()`.
    pub fn iter(&self) -> impl Iterator<Item = (EntityId, &EntitySlots)> {
        self.slots.iter().enumerate().filter_map(|(i, slot)| {
            slot.live.as_ref().map(|s| {
                #[allow(clippy::cast_possible_truncation)]
                let id = EntityId::new(i as u32, slot.generation).expect("slot index in range");
                (id, s)
            })
        })
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

        assert_eq!(table.detach(e, 0).unwrap(), Some(ComponentRef::new(7, 42)));
        assert_eq!(table.detach(e, 1).unwrap(), Some(ComponentRef::new(3, 1)));
        assert!(table.unbind(e).unwrap().is_empty());
        assert!(!table.contains(e));
        assert_eq!(table.component(e, 0, 7), Err(EntityError::Stale));
    }

    #[test]
    fn a_freed_slot_is_quarantined_before_reuse() {
        let mut table = EntityTable::new();
        let a = table.bind().unwrap();
        table.unbind(a).unwrap();
        assert_eq!(table.component(a, 0, 1), Err(EntityError::Stale));

        // Bind-then-free QUARANTINE fresh entities. The quarantine queue
        // starts at [a] (length 1) and never exceeds QUARANTINE during this
        // loop, so every one of these binds allocates a brand new slot —
        // `a`'s must not come back out early.
        for _ in 0..QUARANTINE {
            let e = table.bind().unwrap();
            assert_ne!(e.index(), a.index(), "a slot was reused before its quarantine elapsed");
            table.unbind(e).unwrap();
        }

        // The queue is now [a, ...QUARANTINE frees...], length QUARANTINE + 1:
        // `a`'s slot is the oldest and is the next one handed out.
        let reused = table.bind().unwrap();
        assert_eq!(reused.index(), a.index(), "the oldest quarantined slot is reused first");
        assert_ne!(reused.generation(), a.generation(), "generation still moved on");
        assert_eq!(table.component(a, 0, 1), Err(EntityError::Stale));
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
    fn id_round_trips_through_f32() {
        let id = EntityId::new(12345, 17).unwrap();
        assert_eq!(EntityId::from_f32(id.to_f32()), Some(id));
        assert_eq!(EntityId::from_f32(-1.0), None);
        assert_eq!(EntityId::from_f32(1.5), None);
        assert_eq!(EntityId::new(MAX_SLOTS, 0), None);
        assert_eq!(EntityId::new(0, MAX_GENERATION + 1), None);
    }
}
