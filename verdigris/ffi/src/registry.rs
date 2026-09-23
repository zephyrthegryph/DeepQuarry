//! `DomainRegistry` (`doc/rewrite/rust_architecture.md` §5): one trait and
//! one shared table, merging what used to be two separate registries —
//! `reactor::ExternalDomain` (a domain's watch port) and `entity::
//! EntityDomain` (a domain's component lifecycle). A domain implements only
//! the half it uses; every method has a default that says "this domain
//! doesn't do that."
//!
//! Registration is still per numeric domain id (`register_domain`), and a
//! crate may register more than one id — for example gas today keeps its
//! turf-field watch port (id 2, `reactor::DOMAIN_GAS`) and its component
//! store (id 0, `entity::DOMAIN_GAS`) separate, since they are different
//! Rust objects (`domains/gas/src/turf.rs`'s `GasDomain` and `kind/pump.rs`'s
//! `Shared`) until gas's own migration unifies them under one id. Nothing
//! here requires that: the registry is one map either way.
use std::cell::RefCell;
use std::collections::BTreeMap;

use eyre::{Result, bail};
use vg_core::channel::ChannelInfo;
use vg_core::entity::ComponentRef;
use vg_core::outbox::{Lane, Subscriber, Wake, WatchId};
use vg_core::watch::Cond;

/// Everything a registered domain may offer the FFI boundary. Every method
/// has a default; a domain overrides only the ones it uses.
#[allow(unused_variables)]
pub trait DomainRegistry {
    // --- Component lifecycle (was `entity::EntityDomain`) ---------------

    /// Detaches and discards the component at `comp` (already removed from
    /// the entity's slot by the caller). Ignores an already-freed row.
    fn detach(&mut self, comp: ComponentRef) {}
    /// `(field, value)` text pairs, for `vg_describe()`.
    fn describe(&self, comp: ComponentRef) -> Vec<(String, String)> {
        Vec::new()
    }
    /// Advances this domain's store(s) by one tick (worker-owned kinds
    /// only; §4.2). Called from the driver's sweep, not per idle DM tick.
    fn tick(&mut self) {}
    /// Drops every component and resets to a fresh, empty state
    /// (`verdigris_init`/`verdigris_cleanup`).
    fn reset(&mut self) {}
    /// Moves this domain's raised events (since the last drain) into `out`,
    /// as `(kind, entity, event_id)`. `entity` is already in `vg_entity`'s
    /// raw-plus-one form.
    fn drain_events(&mut self, out: &mut Vec<(u16, f32, u8)>) {}

    // --- Watch port (was `reactor::ExternalDomain`) ----------------------

    /// The domain's channel table (checks channel ids and units).
    fn channels(&self) -> Vec<ChannelInfo> {
        Vec::new()
    }
    /// Registers a watch; returns the domain's sub-port and the watch id.
    ///
    /// # Errors
    /// If the condition names invalid cells or is rejected, or (the
    /// default) if this domain has no watch port at all.
    fn watch(&mut self, sub: Subscriber, lane: Lane, cond: &Cond) -> Result<(u8, WatchId)> {
        let _ = (sub, lane, cond);
        bail!("this domain has no watch port")
    }
    fn unwatch(&mut self, port: u8, id: WatchId) {}
    /// Moves the wakes produced since the last call into `out`.
    fn take_wakes(&mut self, out: &mut Vec<Wake>) {}
}

thread_local! {
    static DOMAINS: RefCell<BTreeMap<u32, Box<dyn DomainRegistry>>> = RefCell::new(BTreeMap::new());
}

/// Registers (or replaces) a domain under a numeric id (a generated
/// `VG_DOMAIN_*`/`REACT_DOMAIN_*` define).
pub fn register_domain(id: u32, domain: Box<dyn DomainRegistry>) {
    DOMAINS.with_borrow_mut(|d| {
        d.insert(id, domain);
    });
}

/// Runs `f` against the registered domain `id`, if any.
pub fn with_domain<T>(id: u32, f: impl FnOnce(&mut dyn DomainRegistry) -> T) -> Option<T> {
    DOMAINS.with_borrow_mut(|d| d.get_mut(&id).map(|handler| f(handler.as_mut())))
}

/// Runs `f` against every registered domain, `(id, domain)`.
pub fn for_each(mut f: impl FnMut(u32, &mut dyn DomainRegistry)) {
    DOMAINS.with_borrow_mut(|domains| {
        for (&id, handler) in domains.iter_mut() {
            f(id, handler.as_mut());
        }
    });
}
