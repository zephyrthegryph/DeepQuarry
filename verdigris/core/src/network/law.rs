//! Network queries (`rust_architecture.md` §4.3, §4.5): how laws read and
//! write a [`NetworkHost`]'s regions and devices.
//!
//! - A **region law** names [`Payload<K>`] (and optionally [`Summary<K>`])
//!   and runs once per region whose revision moved since it last ran there:
//!   `PowerBalance` over cable regions.
//! - A **device law** names [`Sides<K>`] (both regions a device joins) and
//!   optionally [`DeviceData<K>`] and the device entity's own components
//!   (a `Pump`'s config): the gas flow law over pipe devices. It runs once
//!   per device whose own or either side's revision moved, so a settled
//!   pump costs nothing until something on either side changes.
//!
//! Writes go through [`NetworkHost::set_payload`]/
//! [`NetworkHost::set_device_data`], which only move revisions on a real
//! change: a law that leaves a region as it was does not wake anything.

use std::any::TypeId;

use super::graph::{DeviceId, NetworkKind, RegionId};
use super::host::NetworkHost;
use crate::frame::ResourceId;
use crate::query::{Anchor, At, FrameData, Item, LawError, Query, QueryInit, WriteQuery};
use crate::slot::RawHandle;

fn host_id<K: NetworkKind>(init: &mut QueryInit<'_>, write: bool) -> Result<ResourceId, LawError> {
    let (id, phase) = init.catalog.network(TypeId::of::<K>()).ok_or(LawError::Unregistered {
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
        init.access.write(id);
    } else {
        init.access.read(id);
    }
    Ok(id)
}

fn region<K: NetworkKind>(at: At) -> Option<RegionId<K>> {
    RawHandle::from_bits(at.index).map(RegionId::from_raw)
}

fn device<K: NetworkKind>(at: At) -> Option<DeviceId<K>> {
    RawHandle::from_bits(at.index).map(DeviceId::from_raw)
}

fn list_regions<K: NetworkKind>(frame: &FrameData<'_>, host: ResourceId, out: &mut Vec<Item>) {
    let host = frame.get::<NetworkHost<K>>(host);
    out.extend(host.regions().map(|r| Item {
        at: At {
            index: r.raw().bits(),
            entity: None,
        },
        revision: host.region_revision(r),
        entity_value: 0.0,
    }));
}

fn list_devices<K: NetworkKind>(frame: &FrameData<'_>, host: ResourceId, out: &mut Vec<Item>) {
    let host = frame.get::<NetworkHost<K>>(host);
    out.extend(host.devices().map(|(d, e)| Item {
        at: At {
            index: d.raw().bits(),
            entity: Some(e.index()),
        },
        revision: host.device_revision(d),
        entity_value: e.to_f32() + 1.0,
    }));
}

fn region_revision<K: NetworkKind>(frame: &FrameData<'_>, host: ResourceId, index: u32) -> u64 {
    let host = frame.get::<NetworkHost<K>>(host);
    region::<K>(At { index, entity: None }).map_or(0, |r| host.region_revision(r))
}

fn device_revision<K: NetworkKind>(frame: &FrameData<'_>, host: ResourceId, index: u32) -> u64 {
    let host = frame.get::<NetworkHost<K>>(host);
    device::<K>(At { index, entity: None }).map_or(0, |d| host.device_revision(d))
}

/// The anchor of a region law over network `K`.
#[must_use]
pub fn region_anchor<K: NetworkKind>() -> Anchor {
    Anchor::Network {
        kind: TypeId::of::<K>(),
        name: K::NAME,
        list: list_regions::<K>,
        revision: region_revision::<K>,
    }
}

/// The anchor of a device law over network `K`.
#[must_use]
pub fn device_anchor<K: NetworkKind>() -> Anchor {
    Anchor::Network {
        kind: TypeId::of::<K>(),
        name: K::NAME,
        list: list_devices::<K>,
        revision: device_revision::<K>,
    }
}

/// A region's pooled state (anchors a region law).
#[derive(Clone, Debug, PartialEq)]
pub struct Payload<K: NetworkKind>(pub K::Payload);

impl<K: NetworkKind> Query for Payload<K> {
    type State = ResourceId;

    fn anchor() -> Option<Anchor> {
        Some(region_anchor::<K>())
    }

    fn init(init: &mut QueryInit<'_>, write: bool) -> Result<ResourceId, LawError> {
        host_id::<K>(init, write)
    }

    fn fetch(state: &ResourceId, frame: &FrameData<'_>, at: At) -> Option<Self> {
        let host = frame.get::<NetworkHost<K>>(*state);
        host.payload(region::<K>(at)?).cloned().map(Self)
    }
}

impl<K: NetworkKind> WriteQuery for Payload<K> {
    fn write(self, state: &ResourceId, frame: &mut FrameData<'_>, at: At) {
        if let Some(r) = region::<K>(at) {
            let _ = frame.get_mut::<NetworkHost<K>>(*state).set_payload(r, self.0);
        }
    }
}

/// A region's additive summary of its nodes (read-only).
#[derive(Clone, Debug, PartialEq)]
pub struct Summary<K: NetworkKind>(pub K::Summary);

impl<K: NetworkKind> Query for Summary<K> {
    type State = ResourceId;

    fn anchor() -> Option<Anchor> {
        Some(region_anchor::<K>())
    }

    fn init(init: &mut QueryInit<'_>, _write: bool) -> Result<ResourceId, LawError> {
        host_id::<K>(init, false)
    }

    fn fetch(state: &ResourceId, frame: &FrameData<'_>, at: At) -> Option<Self> {
        let host = frame.get::<NetworkHost<K>>(*state);
        let r = host.network().region(region::<K>(at)?).ok()?;
        Some(Self(r.summary().clone()))
    }
}

/// One side of a device: the region it acts on, that region's summary and
/// payload.
#[derive(Clone, Debug, PartialEq)]
pub struct Side<K: NetworkKind> {
    pub region: RegionId<K>,
    pub summary: K::Summary,
    pub payload: K::Payload,
}

/// Both sides of a device edge (anchors a device law). A device whose
/// sides are the same region, a field cell or detached is skipped.
#[derive(Clone, Debug, PartialEq)]
pub struct Sides<K: NetworkKind> {
    pub a: Side<K>,
    pub b: Side<K>,
}

impl<K: NetworkKind> Query for Sides<K> {
    type State = ResourceId;

    fn anchor() -> Option<Anchor> {
        Some(device_anchor::<K>())
    }

    fn init(init: &mut QueryInit<'_>, write: bool) -> Result<ResourceId, LawError> {
        host_id::<K>(init, write)
    }

    fn fetch(state: &ResourceId, frame: &FrameData<'_>, at: At) -> Option<Self> {
        let host = frame.get::<NetworkHost<K>>(*state);
        let [(ra, sa, pa), (rb, sb, pb)] = host.device_pair(device::<K>(at)?)?;
        Some(Self {
            a: Side {
                region: ra,
                summary: sa,
                payload: pa,
            },
            b: Side {
                region: rb,
                summary: sb,
                payload: pb,
            },
        })
    }
}

impl<K: NetworkKind> WriteQuery for Sides<K> {
    fn write(self, state: &ResourceId, frame: &mut FrameData<'_>, _at: At) {
        let host = frame.get_mut::<NetworkHost<K>>(*state);
        let _ = host.set_payload(self.a.region, self.a.payload);
        let _ = host.set_payload(self.b.region, self.b.payload);
    }
}

/// A device's parameters.
#[derive(Clone, Debug, PartialEq)]
pub struct DeviceData<K: NetworkKind>(pub K::Device);

impl<K: NetworkKind> Query for DeviceData<K> {
    type State = ResourceId;

    fn anchor() -> Option<Anchor> {
        Some(device_anchor::<K>())
    }

    fn init(init: &mut QueryInit<'_>, write: bool) -> Result<ResourceId, LawError> {
        host_id::<K>(init, write)
    }

    fn fetch(state: &ResourceId, frame: &FrameData<'_>, at: At) -> Option<Self> {
        let host = frame.get::<NetworkHost<K>>(*state);
        host.network().device(device::<K>(at)?).ok().map(|d| Self(d.data.clone()))
    }
}

impl<K: NetworkKind> WriteQuery for DeviceData<K> {
    fn write(self, state: &ResourceId, frame: &mut FrameData<'_>, at: At) {
        let host = frame.get_mut::<NetworkHost<K>>(*state);
        let Some(d) = device::<K>(at) else {
            return;
        };
        let Some(entity) = host.network().device(d).ok().and_then(|dev| super::host::decode_key(dev.key)) else {
            return;
        };
        let _ = host.set_device_data(entity, self.0);
    }
}
