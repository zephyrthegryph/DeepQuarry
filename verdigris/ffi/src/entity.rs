//! The shared entity table (`doc/rewrite/rust_bindings.md` §1, §4): DM's
//! `vg_entity` handle and, generically, the domain-agnostic half of bind and
//! unbind. A component kind's own get/set/query/event binds live in its
//! domain crate (see `verdigris/domains/gas/src/kind/pump.rs`); this module
//! only knows that *some* domain has *a* component attached, through the
//! [`EntityDomain`] trait each domain registers an implementation of.
use std::cell::RefCell;
use std::collections::BTreeMap;

use byondapi::prelude::*;
use eyre::{Result, bail, eyre};
use vg_core::entity::{ComponentRef, EntityError, EntitySlots, EntityTable};
use vg_core::handle::Handle;

/// What a domain must offer the entity table so it can tear a component down
/// generically, describe it for debugging, and reset it each round.
pub trait EntityDomain {
    /// Detaches and discards the component at `comp` (already removed from
    /// the entity's slot by the caller). Ignores an already-freed cell.
    fn detach(&mut self, comp: ComponentRef);
    /// `(field, value)` text pairs, for `vg_describe()` (§3).
    fn describe(&self, comp: ComponentRef) -> Vec<(String, String)>;
    /// Advances this domain's `Sim` by one tick and dispatches a frame,
    /// publishing a view and pruning the overlay (§6). Called from `SSvg`'s
    /// sweep, not per idle DM tick.
    fn tick(&mut self);
    /// Drops every component and resets to a fresh, empty state
    /// (`verdigris_init`/`verdigris_cleanup`, §4).
    fn reset(&mut self);
}

thread_local! {
    static ENTITIES: RefCell<EntityTable> = RefCell::new(EntityTable::new());
    static DOMAINS: RefCell<BTreeMap<usize, Box<dyn EntityDomain>>> = RefCell::new(BTreeMap::new());
}

/// Registers `handler` for `domain`. Idempotent: a domain crate calls this
/// on first use (its `thread_local` world is created once and shared with
/// the registered handler, so this never replaces a live handler with an
/// empty one — see `pump.rs`'s `ensure_registered`).
pub fn register_entity_domain(domain: usize, handler: Box<dyn EntityDomain>) {
    DOMAINS.with_borrow_mut(|d| {
        d.insert(domain, handler);
    });
}

fn decode(v: f32) -> Result<Handle<EntitySlots>> {
    Handle::from_f32(v).ok_or_else(|| eyre!("bad entity handle {v}"))
}

/// Reserves a new entity, or reuses `existing` if it already names a live
/// one: the first component a bound atom gets creates the entity, and later
/// components on the same atom attach to it (§4).
///
/// # Errors
/// If `existing` is non-zero but not a live entity.
pub fn bind_or_reuse(existing: f32) -> Result<Handle<EntitySlots>> {
    if existing != 0.0 {
        let h = decode(existing)?;
        if ENTITIES.with_borrow(|t| t.contains(h)) {
            return Ok(h);
        }
        bail!("entity {existing} is not live");
    }
    ENTITIES.with_borrow_mut(EntityTable::bind).map_err(|e| eyre!("{e}"))
}

/// Attaches `comp` to `entity`'s `domain` slot.
///
/// # Errors
/// As [`vg_core::entity::EntityTable::attach`].
pub fn attach(entity: Handle<EntitySlots>, domain: usize, comp: ComponentRef) -> Result<(), EntityError> {
    ENTITIES.with_borrow_mut(|t| t.attach(entity, domain, comp))
}

/// The `f32` DM should store in `vg_entity`.
#[must_use]
pub fn entity_value(h: Handle<EntitySlots>) -> f32 {
    h.to_f32()
}

/// Resolves a `vg_entity` number to a live component, checked against the
/// caller's expected kind (§5's "resolves the handle and component").
///
/// # Errors
/// A typed [`ComponentError`](vg_core::component::ComponentError)-shaped
/// message: bad handle, stale, no such component, or wrong kind.
pub fn resolve(entity_v: f32, domain: usize, kind: u16) -> Result<ComponentRef> {
    let h = decode(entity_v)?;
    ENTITIES
        .with_borrow(|t| t.component(h, domain, kind))
        .map_err(|e| eyre!("{e}"))
}

fn num(v: &ByondValue) -> Result<f32> {
    Ok(v.get_number()?)
}

/// Generic unbind (J1's `pre_destroy()`, or today's earliest guaranteed
/// point — see `on_dematerialize()` in `atom_materialize.dm`): detaches
/// every domain's component from the entity through its registered handler,
/// then frees the entity itself. A zero/null handle (never bound, or
/// already unbound) is a silent no-op.
#[auxmacros::bind("/proc/entity_unbind")]
fn entity_unbind(entity: ByondValue) -> Result<ByondValue> {
    let v = num(&entity)?;
    if v == 0.0 {
        return Ok(ByondValue::null());
    }
    let h = decode(v)?;
    let slots = ENTITIES.with_borrow(|t| t.components(h)).map_err(|e| eyre!("{e}"))?;
    for (domain, comp) in slots.iter() {
        DOMAINS.with_borrow_mut(|domains| {
            if let Some(handler) = domains.get_mut(&domain) {
                handler.detach(comp);
            }
        });
        let _ = ENTITIES.with_borrow_mut(|t| t.detach(h, domain));
    }
    ENTITIES.with_borrow_mut(|t| t.unbind(h)).map_err(|e| eyre!("{e}"))?;
    Ok(ByondValue::null())
}

/// `vg_describe(atom)` (§3): every attached component's fields, as one
/// semicolon-joined line (`domain field=value, field=value; domain ...`).
#[auxmacros::bind("/proc/entity_describe")]
fn entity_describe(entity: ByondValue) -> Result<ByondValue> {
    let v = num(&entity)?;
    if v == 0.0 {
        return Ok(ByondValue::new_str("(unbound)")?);
    }
    let h = decode(v)?;
    let slots = ENTITIES.with_borrow(|t| t.components(h)).map_err(|e| eyre!("{e}"))?;
    let mut parts = Vec::new();
    for (domain, comp) in slots.iter() {
        DOMAINS.with_borrow(|domains| {
            if let Some(handler) = domains.get(&domain) {
                let fields: Vec<String> = handler
                    .describe(comp)
                    .into_iter()
                    .map(|(k, val)| format!("{k}={val}"))
                    .collect();
                parts.push(format!("domain {domain} kind {}: {}", comp.kind, fields.join(", ")));
            }
        });
    }
    Ok(ByondValue::new_str(parts.join("; "))?)
}

/// `SSvg`'s per-sweep maintenance: ticks every registered domain's `Sim`
/// once (publishing a view, pruning the overlay), so state is never more
/// than one sweep old even though nothing sets it per idle tick.
#[auxmacros::bind("/proc/entity_tick_all")]
fn entity_tick_all() -> Result<ByondValue> {
    DOMAINS.with_borrow_mut(|domains| {
        for handler in domains.values_mut() {
            handler.tick();
        }
    });
    Ok(ByondValue::null())
}

/// Live entities (a reconciler/test metric).
#[auxmacros::bind("/proc/entity_count")]
fn entity_count() -> Result<ByondValue> {
    #[allow(clippy::cast_precision_loss)]
    let n = ENTITIES.with_borrow(EntityTable::len) as f32;
    Ok(ByondValue::from(n))
}

/// World reset (`verdigris_init`/`verdigris_cleanup`, §4): every registered
/// domain drops its components, then the entity table itself is rebuilt, so
/// no handle survives into a new round.
pub fn reset_all() {
    DOMAINS.with_borrow_mut(|domains| {
        for handler in domains.values_mut() {
            handler.reset();
        }
    });
    ENTITIES.with_borrow_mut(|t| *t = EntityTable::new());
}

/// Test/reconciler hook: every live entity and the domains it has a
/// component in, as `[entity, domain, kind, cell, ...]` flat groups of 4.
#[auxmacros::bind("/proc/entity_debug_list")]
fn entity_debug_list() -> Result<ByondValue> {
    #[allow(clippy::cast_precision_loss)]
    let mut flat: Vec<f32> = Vec::new();
    ENTITIES.with_borrow(|t| {
        for (h, slots) in t.iter() {
            for (domain, comp) in slots.iter() {
                flat.extend_from_slice(&[
                    h.to_f32(),
                    domain as f32,
                    f32::from(comp.kind),
                    comp.cell as f32,
                ]);
            }
        }
    });
    let items: Vec<ByondValue> = flat.into_iter().map(ByondValue::from).collect();
    let list = ByondValue::new_list()?;
    list.write_list(&items)?;
    Ok(list)
}
