//! The domain registry (`rust_architecture.md` §5): **one** table of what
//! every simulation host offers the FFI boundary, keyed by a numeric domain
//! id DM names (a generated `VG_DOMAIN_*`/`REACT_DOMAIN_*` define).
//!
//! The [`crate::world::World`] is registered here like any host: once for
//! entity lifecycle (under [`crate::entity::WORLD_DOMAIN`]) and once per
//! watchable component kind (under [`world_kind_domain`]). Hosts that have
//! not moved onto the world yet (power's, heat's, gas's turf watches)
//! register their own implementation until they port. The trait lives in
//! core, not `vg-ffi`, so a domain crate can implement it without
//! depending on the FFI crate.

use std::collections::BTreeMap;

use crate::channel::ChannelInfo;
use crate::entity::ComponentRef;
use crate::outbox::{Lane, Subscriber, Wake, WatchId};
use crate::watch::Cond;

/// Registry ids at and above this are world component kinds:
/// `WORLD_KIND_BASE | kind_code` ([`crate::world::kind_code`]).
/// @dm-define VG_WORLD_KIND_BASE
pub const WORLD_KIND_BASE: u32 = 0x1_0000;

/// The registry id of a world component kind's watch port.
#[must_use]
pub const fn world_kind_domain(code: u32) -> u32 {
    WORLD_KIND_BASE | code
}

/// Everything a registered host may offer the FFI boundary. Every method
/// has a default that says "this host doesn't do that".
#[allow(unused_variables)]
pub trait DomainRegistry {
    // --- Component lifecycle ---------------------------------------------

    /// Detaches and discards the component at `comp` (already removed from
    /// the entity's slot by the caller). Ignores an already-freed row.
    fn detach(&mut self, comp: ComponentRef) {}
    /// `(field, value)` text pairs, for `vg_describe()`.
    fn describe(&self, comp: ComponentRef) -> Vec<(String, String)> {
        Vec::new()
    }
    /// Advances the host by one sweep (hosts not yet on the world's pacer).
    fn tick(&mut self) {}
    /// Drops every component and resets to a fresh, empty state.
    fn reset(&mut self) {}

    // --- Watch port --------------------------------------------------------

    /// The host's channel table (checks channel ids and units).
    fn channels(&self) -> Vec<ChannelInfo> {
        Vec::new()
    }
    /// Registers a watch; returns the host's sub-port and the watch id.
    ///
    /// # Errors
    /// A description of why the condition was refused, or (the default)
    /// that this host has no watch port.
    fn watch(&mut self, sub: Subscriber, lane: Lane, cond: &Cond) -> Result<(u8, WatchId), String> {
        Err("this domain has no watch port".to_owned())
    }
    fn unwatch(&mut self, port: u8, id: WatchId) {}
    /// Moves the wakes produced since the last call into `out`.
    fn take_wakes(&mut self, out: &mut Vec<Wake>) {}
}

/// The table itself. `vg-ffi` keeps the one instance.
#[derive(Default)]
pub struct Registry {
    domains: BTreeMap<u32, Box<dyn DomainRegistry>>,
}

impl Registry {
    #[must_use]
    pub fn new() -> Self {
        Self::default()
    }

    /// Registers (or replaces) a host under `id`.
    pub fn register(&mut self, id: u32, host: Box<dyn DomainRegistry>) {
        self.domains.insert(id, host);
    }

    /// Removes the host under `id`.
    pub fn unregister(&mut self, id: u32) -> Option<Box<dyn DomainRegistry>> {
        self.domains.remove(&id)
    }

    pub fn get_mut(&mut self, id: u32) -> Option<&mut (dyn DomainRegistry + 'static)> {
        self.domains.get_mut(&id).map(AsMut::as_mut)
    }

    /// Every host, `(id, host)`, in id order.
    pub fn iter_mut(&mut self) -> impl Iterator<Item = (u32, &mut (dyn DomainRegistry + 'static))> {
        self.domains.iter_mut().map(|(&id, h)| (id, h.as_mut()))
    }

    #[must_use]
    pub fn contains(&self, id: u32) -> bool {
        self.domains.contains_key(&id)
    }
}
