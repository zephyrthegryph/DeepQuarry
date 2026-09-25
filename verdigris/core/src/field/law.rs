//! Field queries (`rust_architecture.md` §4.3): coupling laws over field
//! cells, and device laws between a network region and a field cell.
//!
//! - [`Cell<K>`] is one cell of field `K` (its value, capacity and
//!   reservoir flag). As an anchor it iterates every cell in the field's
//!   active chunks after the field's own step, so a coupling law (solid↔gas
//!   in the same turf, a body↔turf exchange) costs nothing where the field
//!   sleeps. A second `Cell<F>` in the same law reads another field at the
//!   same `CellId`.
//! - [`RegionCell<K, F>`] is a device edge between a region of network `K`
//!   and a cell of field `F` (a vent between a pipe network and its turf),
//!   anchored on `K`'s devices like [`crate::network::Sides`].
//!
//! Writes store the cell back only when it changed; the field's next step
//! sees the written chunk as changed (it is no longer the snapshot's
//! allocation) and wakes it, so a coupling law never has to wake the field
//! by hand.

use std::any::TypeId;

use super::{FieldKind, FieldState, Geom, Geometry};
use crate::frame::ResourceId;
use crate::network::law::device_anchor;
use crate::network::{DeviceId, Endpoint, NetworkHost, NetworkKind, RegionSide, Side};
use crate::owner::DomainState;
use crate::query::{Anchor, At, FrameData, Item, LawError, Query, QueryInit, WriteQuery};
use crate::slot::RawHandle;

/// Resource ids of a registered field.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct FieldIds {
    pub cells: ResourceId,
    pub geometry: ResourceId,
    pub state: ResourceId,
}

/// Finds a field in the catalog (fields are worker-owned).
fn field_ids<K: FieldKind>(init: &mut QueryInit<'_>, write: bool) -> Result<FieldIds, LawError> {
    let ids = init
        .catalog
        .field(TypeId::of::<K>())
        .ok_or(LawError::Unregistered {
            law: init.law,
            what: K::NAME,
        })?;
    if init.phase != crate::query::Phase::Worker {
        return Err(LawError::WrongOwner {
            law: init.law,
            what: K::NAME,
        });
    }
    if write {
        init.access.write(ids.cells);
    } else {
        init.access.read(ids.cells);
    }
    init.access.read(ids.geometry);
    Ok(ids)
}

fn list_cells<K: FieldKind>(frame: &FrameData<'_>, state: ResourceId, out: &mut Vec<Item>) {
    let st = frame.get::<FieldState<K>>(state);
    let layout = st.layout();
    for chunk in st.active_chunks() {
        for i in 0..layout.chunk_len() {
            if let Some(index) = layout.index_of(chunk, i) {
                out.push(Item {
                    at: At {
                        index,
                        entity: None,
                    },
                    revision: 0,
                    entity_value: 0.0,
                });
            }
        }
    }
}

/// The anchor of a law over field `K`'s active cells.
#[must_use]
pub fn cell_anchor<K: FieldKind>() -> Anchor {
    Anchor::Cells {
        field: TypeId::of::<K>(),
        name: K::NAME,
        list: list_cells::<K>,
    }
}

fn geom_at<K: FieldKind>(frame: &FrameData<'_>, ids: &FieldIds, cell: u32) -> Option<Geom> {
    let g = frame
        .get::<DomainState<Geometry<K>>>(ids.geometry)
        .store
        .get(cell)?;
    g.is_node().then_some(g)
}

/// One cell of field `K`.
#[derive(Clone, Debug, PartialEq)]
pub struct Cell<K: FieldKind> {
    pub value: K::Value,
    /// The cell's capacity (heat capacity, volume).
    pub capacity: f32,
    /// Exchanges but never changes: a law must not keep what it writes to a
    /// reservoir cell (the write is dropped).
    pub reservoir: bool,
}

impl<K: FieldKind> Query for Cell<K> {
    type State = FieldIds;

    fn anchor() -> Option<Anchor> {
        Some(cell_anchor::<K>())
    }

    fn init(init: &mut QueryInit<'_>, write: bool) -> Result<FieldIds, LawError> {
        field_ids::<K>(init, write)
    }

    fn fetch(state: &FieldIds, frame: &FrameData<'_>, at: At) -> Option<Self> {
        let g = geom_at::<K>(frame, state, at.index)?;
        let value = frame
            .get::<DomainState<K>>(state.cells)
            .store
            .get(at.index)?;
        Some(Self {
            value,
            capacity: g.capacity,
            reservoir: g.reservoir,
        })
    }
}

impl<K: FieldKind> WriteQuery for Cell<K> {
    fn write(self, state: &FieldIds, frame: &mut FrameData<'_>, at: At) {
        if self.reservoir {
            return;
        }
        let cells = frame.get_mut::<DomainState<K>>(state.cells);
        if cells.store.with(at.index, |old| *old != self.value) == Some(true) {
            cells.store.set(at.index, self.value);
        }
    }
}

/// A device edge between a region of network `K` and a cell of field `F`.
#[derive(Clone, Debug, PartialEq)]
pub struct RegionCell<K: NetworkKind, F: FieldKind> {
    pub region: RegionSide<K>,
    pub cell: u32,
    pub value: F::Value,
    pub capacity: f32,
    pub reservoir: bool,
}

/// Resolved ids of a [`RegionCell`] query.
#[derive(Clone, Copy, Debug)]
pub struct RegionCellIds {
    host: ResourceId,
    field: FieldIds,
}

impl<K: NetworkKind, F: FieldKind> Query for RegionCell<K, F> {
    type State = RegionCellIds;

    fn anchor() -> Option<Anchor> {
        Some(device_anchor::<K>())
    }

    fn init(init: &mut QueryInit<'_>, write: bool) -> Result<RegionCellIds, LawError> {
        let (host, phase) =
            init.catalog
                .network(TypeId::of::<K>())
                .ok_or(LawError::Unregistered {
                    law: init.law,
                    what: K::NAME,
                })?;
        if phase != init.phase {
            return Err(LawError::WrongOwner {
                law: init.law,
                what: K::NAME,
            });
        }
        if write {
            init.access.write(host);
        } else {
            init.access.read(host);
        }
        let field = field_ids::<F>(init, write)?;
        Ok(RegionCellIds { host, field })
    }

    fn fetch(state: &RegionCellIds, frame: &FrameData<'_>, at: At) -> Option<Self> {
        let host = frame.get::<NetworkHost<K>>(state.host);
        let d = DeviceId::<K>::from_raw(RawHandle::from_bits(at.index)?);
        let dev = host.network().device(d).ok()?;
        let (node_end, cell) = match (dev.a, dev.b) {
            (n @ Endpoint::Node(_), Endpoint::Cell(c))
            | (Endpoint::Cell(c), n @ Endpoint::Node(_)) => (n, c),
            _ => return None,
        };
        let Side::Region(region) = host.network().resolve(node_end) else {
            return None;
        };
        let r = host.network().region(region).ok()?;
        let side = RegionSide {
            region,
            summary: r.summary().clone(),
            payload: r.payload().clone(),
        };
        let g = geom_at::<F>(frame, &state.field, cell)?;
        let value = frame
            .get::<DomainState<F>>(state.field.cells)
            .store
            .get(cell)?;
        Some(Self {
            region: side,
            cell,
            value,
            capacity: g.capacity,
            reservoir: g.reservoir,
        })
    }
}

impl<K: NetworkKind, F: FieldKind> WriteQuery for RegionCell<K, F> {
    fn write(self, state: &RegionCellIds, frame: &mut FrameData<'_>, _at: At) {
        let _ = frame
            .get_mut::<NetworkHost<K>>(state.host)
            .set_payload(self.region.region, self.region.payload);
        if self.reservoir {
            return;
        }
        let cells = frame.get_mut::<DomainState<F>>(state.field.cells);
        if cells.store.with(self.cell, |old| *old != self.value) == Some(true) {
            cells.store.set(self.cell, self.value);
        }
    }
}
