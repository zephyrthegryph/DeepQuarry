//! Queries (`rust_architecture.md` §4.3): how a law's `Reads` and `Writes`
//! resolve to storage.
//!
//! A [`Query`] is a type a law names as `Law::Reads` or `Law::Writes`:
//! - a component type `C` (the row of the item's entity);
//! - `Option<C>` (a join that may be absent);
//! - [`Payload<K>`]/[`Summary<K>`] (a network region's pooled state and
//!   aggregate), [`Sides<K>`]/[`DeviceData<K>`] (a device edge's two sides
//!   and its parameters), see [`crate::network::law`];
//! - [`Global<T>`], a whole resource for a once-per-frame law;
//! - tuples of the above.
//!
//! At build time [`Query::init`] resolves the type against the world's
//! registries through a [`Catalog`] and declares the resources it reads or
//! writes into an [`Access`]; the law's frame task declares exactly those,
//! so [`crate::frame::Schedule`] runs laws with disjoint access in parallel
//! and orders the rest. Per item, [`Query::fetch`] copies the values out of
//! a [`FrameData`] (the task's locked resources) and
//! [`WriteQuery::write`] stores `Writes` back (only when changed, so an
//! unchanged row keeps sharing its copy-on-write chunk with the published
//! view).
//!
//! The first query in `Writes` (else `Reads`) that has an [`Anchor`]
//! decides what the law iterates: component rows, network regions, network
//! devices, or a single item.

use std::any::{Any, TypeId};
use std::fmt;
use std::sync::{RwLockReadGuard, RwLockWriteGuard};

use crate::component::{Component, Ownership};
use crate::frame::{Erased, ResourceId, TaskCtx};
use crate::owner::DomainState;
use crate::store::{MainKind, Rows, WorkerKind};

/// Which of the driver's two phases a law runs in (§4.2's owners).
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum Phase {
    /// Synchronously on the main thread, over main-owned data.
    Main,
    /// In frames on the pool, over worker-owned data.
    Worker,
}

impl Phase {
    /// The phase that writes data of this ownership.
    #[must_use]
    pub const fn of(owner: Ownership) -> Self {
        match owner {
            Ownership::Main => Self::Main,
            Ownership::Worker => Self::Worker,
        }
    }
}

/// Why a law could not be registered.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum LawError {
    /// A query names a component or network the world has not registered.
    Unregistered { law: &'static str, what: &'static str },
    /// A law writes data owned by the other phase (a worker law writing a
    /// main-owned component, or the reverse).
    WrongOwner { law: &'static str, what: &'static str },
    /// Neither `Reads` nor `Writes` says what to iterate.
    NoAnchor { law: &'static str },
    /// The law's anchor and its declared phase disagree (a law anchored on
    /// a main-owned kind must run in the main phase).
    Ordering(crate::law::OrderCycle),
}

impl fmt::Display for LawError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Unregistered { law, what } => write!(f, "law `{law}` uses `{what}`, which is not registered"),
            Self::WrongOwner { law, what } => {
                write!(f, "law `{law}` writes `{what}`, which the other phase owns")
            }
            Self::NoAnchor { law } => write!(
                f,
                "law `{law}` has nothing to iterate: its Reads/Writes name no component, network or Global"
            ),
            Self::Ordering(c) => write!(f, "{c}"),
        }
    }
}

impl std::error::Error for LawError {}

/// Resources a law's task reads and writes.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Access {
    pub reads: Vec<ResourceId>,
    pub writes: Vec<ResourceId>,
}

impl Access {
    pub fn read(&mut self, id: ResourceId) {
        if !self.reads.contains(&id) && !self.writes.contains(&id) {
            self.reads.push(id);
        }
    }

    pub fn write(&mut self, id: ResourceId) {
        self.reads.retain(|r| *r != id);
        if !self.writes.contains(&id) {
            self.writes.push(id);
        }
    }
}

/// Where a component column lives for a given phase, and how to read it.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ColumnSource {
    /// A worker-owned kind in the worker phase: `DomainState<C::Kind>` (the
    /// rows) plus `WorkerKind<C>` (presence).
    WorkerStore { store: ResourceId, rows: ResourceId },
    /// A main-owned kind in the main phase: `MainKind<C>` (read/write).
    MainStore { kind: ResourceId },
    /// A main-owned kind read by a worker law: `WorkerKind<C>`'s snapshot
    /// as of the last dispatch (read-only).
    Snapshot { rows: ResourceId },
    /// A worker-owned kind read by a main law: `MainKind<C>`'s pinned view
    /// (read-only).
    View { kind: ResourceId },
}

impl ColumnSource {
    /// Whether a law in this phase may write the column.
    #[must_use]
    pub const fn writable(self) -> bool {
        matches!(self, Self::WorkerStore { .. } | Self::MainStore { .. })
    }
}

/// The world's registries as a query sees them at build time.
pub trait Catalog {
    /// Where component type `component` lives for `phase`.
    fn column(&self, component: TypeId, phase: Phase) -> Option<ColumnSource>;
    /// The resource holding network kind `kind`'s host, and the phase that
    /// owns it.
    fn network(&self, kind: TypeId) -> Option<(ResourceId, Phase)>;
    /// The resource holding global `T`, and its phase.
    fn global(&self, ty: TypeId) -> Option<(ResourceId, Phase)>;
    /// The resources of field kind `field` (always worker-owned).
    fn field(&self, field: TypeId) -> Option<crate::field::law::FieldIds>;
}

/// Build-time context for [`Query::init`].
pub struct QueryInit<'a> {
    pub catalog: &'a dyn Catalog,
    pub phase: Phase,
    pub access: &'a mut Access,
    /// The law being registered (for errors).
    pub law: &'static str,
}

/// One item a law steps: an anchor index and, when the item belongs to an
/// entity (a component row, a device), that entity's slot index for joins.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct At {
    pub index: u32,
    pub entity: Option<u32>,
}

/// One enumerated item of a non-row anchor, with the revision it was last
/// changed at (items whose revision the law has already seen sleep).
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Item {
    pub at: At,
    pub revision: u64,
    /// The `vg_entity` value events about this item are attributed to.
    pub entity_value: f32,
}

/// Enumerates every item of a region/device anchor.
pub type ListFn = for<'f> fn(&'f FrameData<'_>, ResourceId, &mut Vec<Item>);

/// The current revision of one item of a network anchor (by its index).
pub type RevFn = for<'f> fn(&'f FrameData<'_>, ResourceId, u32) -> u64;

/// The [`Rows`] of a row anchor, as the law's phase sees them.
pub type RowsFn = for<'f> fn(&'f FrameData<'_>, ResourceId) -> &'f Rows;

/// Resolves a row anchor for a phase: the resource holding its [`Rows`] and
/// the accessor.
pub type ResolveRowsFn = fn(&dyn Catalog, Phase) -> Option<(ResourceId, RowsFn)>;

/// What a law iterates.
#[derive(Clone, Copy)]
pub enum Anchor {
    /// Rows of component `component`: iterated by activity (woken by binds,
    /// DM writes, timers and other laws), never by a full scan.
    Rows {
        component: TypeId,
        name: &'static str,
        resolve: ResolveRowsFn,
    },
    /// Regions or devices of a network: enumerated densely each run, and
    /// skipped while their revision is one the law has already seen.
    Network {
        kind: TypeId,
        name: &'static str,
        list: ListFn,
        revision: RevFn,
    },
    /// Cells of a field's active chunks, every due frame (after the field's
    /// own step): coupling laws over cells.
    Cells {
        field: TypeId,
        name: &'static str,
        list: ListFn,
    },
    /// A single item (index 0), every due frame: a law over a [`Global`].
    Global { ty: TypeId, name: &'static str },
}

impl fmt::Debug for Anchor {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Rows { name, .. } => write!(f, "Rows({name})"),
            Self::Network { name, .. } => write!(f, "Network({name})"),
            Self::Cells { name, .. } => write!(f, "Cells({name})"),
            Self::Global { name, .. } => write!(f, "Global({name})"),
        }
    }
}

/// A law's `Reads` (and, with [`WriteQuery`], `Writes`).
pub trait Query: Sized + 'static {
    /// Resolved resource ids (and anything else fetch needs).
    type State: Send + Sync + 'static;

    /// What this query iterates, if it anchors a law.
    #[must_use]
    fn anchor() -> Option<Anchor> {
        None
    }

    /// Resolves against the world and declares access (`write`: this query
    /// is in the law's `Writes`).
    ///
    /// # Errors
    /// [`LawError`] if the data is unregistered or owned by the other phase.
    fn init(init: &mut QueryInit<'_>, write: bool) -> Result<Self::State, LawError>;

    /// The value for one item, or `None` if the item has no such data (the
    /// driver skips and puts the item to sleep).
    fn fetch(state: &Self::State, frame: &FrameData<'_>, at: At) -> Option<Self>;
}

/// A query a law can write.
pub trait WriteQuery: Query {
    /// Stores the stepped value back.
    fn write(self, state: &Self::State, frame: &mut FrameData<'_>, at: At);
}

enum Guard<'a> {
    Read(RwLockReadGuard<'a, Erased>),
    Write(RwLockWriteGuard<'a, Erased>),
}

/// The locked resources of one law task run.
pub struct FrameData<'a> {
    guards: Vec<(ResourceId, Guard<'a>)>,
}

impl<'a> FrameData<'a> {
    /// Locks every resource in `access` (each once) for the task behind
    /// `ctx`.
    #[must_use]
    pub fn lock(ctx: &TaskCtx<'a>, access: &Access) -> Self {
        let mut guards = Vec::with_capacity(access.reads.len() + access.writes.len());
        for &id in &access.writes {
            guards.push((id, Guard::Write(ctx.write_erased(id))));
        }
        for &id in &access.reads {
            guards.push((id, Guard::Read(ctx.read_erased(id))));
        }
        Self { guards }
    }

    fn slot(&self, id: ResourceId) -> &Erased {
        let (_, g) = self
            .guards
            .iter()
            .find(|(i, _)| *i == id)
            .unwrap_or_else(|| panic!("query reads undeclared resource {id:?}"));
        match g {
            Guard::Read(g) => g,
            Guard::Write(g) => g,
        }
    }

    /// Shared access to resource `id` as `T`.
    ///
    /// # Panics
    /// If `id` was not declared, or is not a `T`.
    #[must_use]
    pub fn get<T: Any>(&self, id: ResourceId) -> &T {
        self.slot(id).downcast_ref().expect("query resource type mismatch")
    }

    /// Exclusive access to written resource `id` as `T`.
    ///
    /// # Panics
    /// If `id` was not declared as written, or is not a `T`.
    pub fn get_mut<T: Any>(&mut self, id: ResourceId) -> &mut T {
        let (_, g) = self
            .guards
            .iter_mut()
            .find(|(i, _)| *i == id)
            .unwrap_or_else(|| panic!("query writes undeclared resource {id:?}"));
        match g {
            Guard::Write(g) => g.downcast_mut().expect("query resource type mismatch"),
            Guard::Read(_) => panic!("query writes resource {id:?} declared read-only"),
        }
    }
}

// --- Components ------------------------------------------------------------

fn rows_of_worker<'f, C: Component>(frame: &'f FrameData<'_>, id: ResourceId) -> &'f Rows {
    &frame.get::<WorkerKind<C>>(id).rows
}

fn rows_of_main<'f, C: Component>(frame: &'f FrameData<'_>, id: ResourceId) -> &'f Rows {
    &frame.get::<MainKind<C>>(id).rows
}

/// The resolved column of a component query.
#[derive(Clone, Copy, Debug)]
pub struct Column {
    source: ColumnSource,
}

impl Column {
    #[must_use]
    pub const fn source(&self) -> ColumnSource {
        self.source
    }
}

/// Resolves the anchor rows of component `C` for `phase`: the resource and
/// the accessor. Used by the driver for row-anchored laws.
#[must_use]
pub fn anchor_rows<C: Component>(catalog: &dyn Catalog, phase: Phase) -> Option<(ResourceId, RowsFn)> {
    match catalog.column(TypeId::of::<C>(), phase)? {
        ColumnSource::WorkerStore { rows, .. } | ColumnSource::Snapshot { rows } => Some((rows, rows_of_worker::<C>)),
        ColumnSource::MainStore { kind } | ColumnSource::View { kind } => Some((kind, rows_of_main::<C>)),
    }
}

impl<C: Component> Query for C {
    type State = Column;

    fn anchor() -> Option<Anchor> {
        Some(Anchor::Rows {
            component: TypeId::of::<C>(),
            name: C::NAME,
            resolve: anchor_rows::<C>,
        })
    }

    fn init(init: &mut QueryInit<'_>, write: bool) -> Result<Column, LawError> {
        let source = init.catalog.column(TypeId::of::<C>(), init.phase).ok_or(LawError::Unregistered {
            law: init.law,
            what: C::NAME,
        })?;
        if write && !source.writable() {
            return Err(LawError::WrongOwner {
                law: init.law,
                what: C::NAME,
            });
        }
        match source {
            ColumnSource::WorkerStore { store, rows } => {
                if write {
                    init.access.write(store);
                } else {
                    init.access.read(store);
                }
                init.access.read(rows);
            }
            ColumnSource::MainStore { kind } => {
                if write {
                    init.access.write(kind);
                } else {
                    init.access.read(kind);
                }
            }
            ColumnSource::Snapshot { rows } => init.access.read(rows),
            ColumnSource::View { kind } => init.access.read(kind),
        }
        Ok(Column { source })
    }

    fn fetch(state: &Column, frame: &FrameData<'_>, at: At) -> Option<Self> {
        let e = at.entity?;
        match state.source {
            ColumnSource::WorkerStore { store, rows } => {
                if !frame.get::<WorkerKind<C>>(rows).rows.contains(e) {
                    return None;
                }
                frame.get::<DomainState<C::Kind>>(store).store.get(e)
            }
            ColumnSource::MainStore { kind } | ColumnSource::View { kind } => frame.get::<MainKind<C>>(kind).get(e),
            ColumnSource::Snapshot { rows } => frame.get::<WorkerKind<C>>(rows).snapshot_get(e),
        }
    }
}

impl<C: Component> WriteQuery for C {
    fn write(self, state: &Column, frame: &mut FrameData<'_>, at: At) {
        let Some(e) = at.entity else {
            return;
        };
        match state.source {
            ColumnSource::WorkerStore { store, .. } => {
                let st = frame.get_mut::<DomainState<C::Kind>>(store);
                if st.store.with(e, |old| *old != self) == Some(true) {
                    st.store.set(e, self);
                }
            }
            ColumnSource::MainStore { kind } => {
                let k = frame.get_mut::<MainKind<C>>(kind);
                if k.get_ref(e).is_some_and(|old| *old != self)
                    && let Some(slot) = k.get_mut(e)
                {
                    *slot = self;
                }
            }
            ColumnSource::Snapshot { .. } | ColumnSource::View { .. } => {
                unreachable!("init refuses writes to a column the phase does not own")
            }
        }
    }
}

/// A join that may be absent: `Some(value)` if the item's entity has the
/// component, `None` otherwise (the item still runs).
impl<C: Component> Query for Option<C> {
    type State = Column;

    fn init(init: &mut QueryInit<'_>, write: bool) -> Result<Column, LawError> {
        <C as Query>::init(init, write)
    }

    fn fetch(state: &Column, frame: &FrameData<'_>, at: At) -> Option<Self> {
        Some(<C as Query>::fetch(state, frame, at))
    }
}

impl<C: Component> WriteQuery for Option<C> {
    fn write(self, state: &Column, frame: &mut FrameData<'_>, at: At) {
        if let Some(v) = self {
            v.write(state, frame, at);
        }
    }
}

// --- Globals -----------------------------------------------------------------

/// A whole resource, for once-per-frame laws (anchor [`Anchor::Global`]).
/// Registered with [`crate::world::WorldBuilder::add_global`].
#[derive(Clone, Debug, Default, PartialEq)]
pub struct Global<T>(pub T);

impl<T: Clone + PartialEq + Send + Sync + 'static> Query for Global<T> {
    type State = ResourceId;

    fn anchor() -> Option<Anchor> {
        Some(Anchor::Global {
            ty: TypeId::of::<T>(),
            name: std::any::type_name::<T>(),
        })
    }

    fn init(init: &mut QueryInit<'_>, write: bool) -> Result<ResourceId, LawError> {
        let (id, phase) = init.catalog.global(TypeId::of::<T>()).ok_or(LawError::Unregistered {
            law: init.law,
            what: std::any::type_name::<T>(),
        })?;
        if phase != init.phase {
            return Err(LawError::WrongOwner {
                law: init.law,
                what: std::any::type_name::<T>(),
            });
        }
        if write {
            init.access.write(id);
        } else {
            init.access.read(id);
        }
        Ok(id)
    }

    fn fetch(state: &ResourceId, frame: &FrameData<'_>, _at: At) -> Option<Self> {
        Some(Self(frame.get::<T>(*state).clone()))
    }
}

impl<T: Clone + PartialEq + Send + Sync + 'static> WriteQuery for Global<T> {
    fn write(self, state: &ResourceId, frame: &mut FrameData<'_>, _at: At) {
        let slot = frame.get_mut::<T>(*state);
        if *slot != self.0 {
            *slot = self.0;
        }
    }
}

// --- Unit and tuples -------------------------------------------------------------

impl Query for () {
    type State = ();

    fn init(_: &mut QueryInit<'_>, _: bool) -> Result<(), LawError> {
        Ok(())
    }

    fn fetch((): &(), _: &FrameData<'_>, _: At) -> Option<Self> {
        Some(())
    }
}

impl WriteQuery for () {
    fn write(self, (): &(), _: &mut FrameData<'_>, _: At) {}
}

macro_rules! tuple_query {
    ($($name:ident $idx:tt),+) => {
        impl<$($name: Query),+> Query for ($($name,)+) {
            type State = ($($name::State,)+);

            fn anchor() -> Option<Anchor> {
                None $(.or_else($name::anchor))+
            }

            fn init(init: &mut QueryInit<'_>, write: bool) -> Result<Self::State, LawError> {
                Ok(($($name::init(init, write)?,)+))
            }

            fn fetch(state: &Self::State, frame: &FrameData<'_>, at: At) -> Option<Self> {
                Some(($($name::fetch(&state.$idx, frame, at)?,)+))
            }
        }

        impl<$($name: WriteQuery),+> WriteQuery for ($($name,)+) {
            fn write(self, state: &Self::State, frame: &mut FrameData<'_>, at: At) {
                $(self.$idx.write(&state.$idx, frame, at);)+
            }
        }
    };
}

tuple_query!(A 0);
tuple_query!(A 0, B 1);
tuple_query!(A 0, B 1, C 2);
tuple_query!(A 0, B 1, C 2, D 3);
tuple_query!(A 0, B 1, C 2, D 3, E 4);
tuple_query!(A 0, B 1, C 2, D 3, E 4, F 5);
tuple_query!(A 0, B 1, C 2, D 3, E 4, F 5, G 6);
tuple_query!(A 0, B 1, C 2, D 3, E 4, F 5, G 6, H 7);
