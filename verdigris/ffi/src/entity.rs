//! The shared entity table (`doc/rewrite/rust_architecture.md` §4.1): DM's
//! `vg_entity` handle and, generically, the domain-agnostic half of bind and
//! unbind. A component kind's own get/set/query/event binds live in its
//! domain crate (see `verdigris/domains/gas/src/kind/pump.rs`); this module
//! only knows that *some* domain has *a* component attached, through the
//! [`registry::DomainRegistry`] each domain registers an implementation of.
use std::cell::RefCell;

use byondapi::prelude::*;
use eyre::{Result, bail, eyre};
use vg_core::entity::{ComponentRef, EntityError, EntityId, EntityTable};

use crate::registry;

/// The bits of a `vg_entity` value (after subtracting the raw-plus-one
/// offset) that carry the slot index, matching `vg_core::entity::INDEX_BITS`
/// (checked in this module's tests). DM computes an entity's table index
/// with it to look up the bound atom for event dispatch, without needing to
/// know anything else about id packing.
/// @dm-define VG_ENTITY_INDEX_MASK
pub const ENTITY_INDEX_MASK: u32 = 524_287;

thread_local! {
    static ENTITIES: RefCell<EntityTable> = const { RefCell::new(EntityTable::new()) };
}

// DM's `vg_entity == 0` means "unbound". A raw id's packed bits can
// themselves be 0 (index 0, generation 0 is a perfectly ordinary id), so
// crossing it as-is would make the first-ever bound entity indistinguishable
// from "no entity" — a hand-rolled sentinel collision. Every `vg_entity`
// value is the raw id plus one; callers never see the offset.
fn decode(v: f32) -> Result<EntityId> {
    if v < 1.0 {
        bail!("entity handle {v} is not bound (0 means unbound; call sites must check that first)");
    }
    EntityId::from_f32(v - 1.0).ok_or_else(|| eyre!("bad entity handle {v}"))
}

/// Reserves a new entity, or reuses `existing` if it already names a live
/// one: the first component a bound atom gets creates the entity, and later
/// components on the same atom attach to it.
///
/// # Errors
/// If `existing` is non-zero but not a live entity.
pub fn bind_or_reuse(existing: f32) -> Result<EntityId> {
    if existing != 0.0 {
        let id = decode(existing)?;
        if ENTITIES.with_borrow(|t| t.contains(id)) {
            return Ok(id);
        }
        bail!("entity {existing} is not live");
    }
    ENTITIES.with_borrow_mut(EntityTable::bind).map_err(|e| eyre!("{e}"))
}

/// Attaches `comp` to `entity`'s `domain` slot.
///
/// # Errors
/// As [`vg_core::entity::EntityTable::attach`].
pub fn attach(entity: EntityId, domain: usize, comp: ComponentRef) -> Result<(), EntityError> {
    ENTITIES.with_borrow_mut(|t| t.attach(entity, domain, comp))
}

/// The `f32` DM should store in `vg_entity` (the raw id plus one; see
/// [`decode`]).
#[must_use]
pub fn entity_value(id: EntityId) -> f32 {
    id.to_f32() + 1.0
}

/// Resolves a `vg_entity` number to a live component, checked against the
/// caller's expected kind (§5's "resolves the handle and component").
///
/// # Errors
/// A typed [`ComponentError`](vg_core::component::ComponentError)-shaped
/// message: bad handle, stale, no such component, or wrong kind.
pub fn resolve(entity_v: f32, domain: usize, kind: u16) -> Result<ComponentRef> {
    let id = decode(entity_v)?;
    ENTITIES
        .with_borrow(|t| t.component(id, domain, kind))
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
    let id = decode(v)?;
    let slots = ENTITIES.with_borrow(|t| t.components(id)).map_err(|e| eyre!("{e}"))?;
    for (domain, comp) in slots.iter() {
        #[allow(clippy::cast_possible_truncation)]
        registry::with_domain(domain as u32, |handler| handler.detach(comp));
        let _ = ENTITIES.with_borrow_mut(|t| t.detach(id, domain));
    }
    ENTITIES.with_borrow_mut(|t| t.unbind(id)).map_err(|e| eyre!("{e}"))?;
    Ok(ByondValue::null())
}

/// `vg_describe(atom)`: every attached component's fields, as one
/// semicolon-joined line (`domain field=value, field=value; domain ...`).
#[auxmacros::bind("/proc/entity_describe")]
fn entity_describe(entity: ByondValue) -> Result<ByondValue> {
    let v = num(&entity)?;
    if v == 0.0 {
        return Ok(ByondValue::new_str("(unbound)")?);
    }
    let id = decode(v)?;
    let slots = ENTITIES.with_borrow(|t| t.components(id)).map_err(|e| eyre!("{e}"))?;
    let mut parts = Vec::new();
    for (domain, comp) in slots.iter() {
        #[allow(clippy::cast_possible_truncation)]
        let described = registry::with_domain(domain as u32, |handler| handler.describe(comp));
        if let Some(fields) = described {
            let fields: Vec<String> = fields.into_iter().map(|(k, val)| format!("{k}={val}")).collect();
            parts.push(format!("domain {domain} kind {}: {}", comp.kind, fields.join(", ")));
        }
    }
    Ok(ByondValue::new_str(parts.join("; "))?)
}

/// `SSvg`'s per-sweep maintenance: ticks every registered domain once
/// (publishing a view, pruning the overlay for worker-owned kinds), so
/// state is never more than one sweep old even though nothing sets it per
/// idle tick.
#[auxmacros::bind("/proc/entity_tick_all")]
fn entity_tick_all() -> Result<ByondValue> {
    registry::for_each(|_, handler| handler.tick());
    Ok(ByondValue::null())
}

/// Live entities (a reconciler/test metric).
#[auxmacros::bind("/proc/entity_count")]
fn entity_count() -> Result<ByondValue> {
    #[allow(clippy::cast_precision_loss)]
    let n = ENTITIES.with_borrow(EntityTable::len) as f32;
    Ok(ByondValue::from(n))
}

/// A safe probe for whether `entity_v` currently resolves to a live
/// component of `domain`/`kind`: `FALSE` for stale, out-of-range, unbound
/// (0), wrong-component or wrong-kind, never a runtime. `resolve()` (used
/// by every generated `get_*`/`set_*`) is deliberately not this: those must
/// error loudly (§5, §9). This exists for callers — admin tools, and tests
/// that check a handle is correctly rejected — that want the answer without
/// risking one (this codebase's test harness fails a "clean" run on any
/// runtime at all, caught or not).
#[auxmacros::bind("/proc/entity_is_valid")]
fn entity_is_valid(entity: ByondValue, domain: ByondValue, kind: ByondValue) -> Result<ByondValue> {
    let v = num(&entity)?;
    #[allow(clippy::cast_possible_truncation, clippy::cast_sign_loss)]
    let domain = num(&domain)?.max(0.0) as usize;
    #[allow(clippy::cast_possible_truncation, clippy::cast_sign_loss)]
    let kind = num(&kind)?.max(0.0) as u16;
    let valid = decode(v).is_ok_and(|id| resolve(entity_value(id), domain, kind).is_ok());
    Ok(yes(valid))
}

fn yes(b: bool) -> ByondValue {
    ByondValue::from(if b { 1.0f32 } else { 0.0 })
}

fn list(values: &[f32]) -> Result<ByondValue> {
    let items: Vec<ByondValue> = values.iter().copied().map(ByondValue::from).collect();
    let list = ByondValue::new_list()?;
    list.write_list(&items)?;
    Ok(list)
}

/// `SSvg`'s per-domain event drain (§4.8): every event raised by that
/// domain's components since the last drain, as a flat
/// `[kind, entity, event_id, ...]` list. SSreactor/SSvg calls this once per
/// domain per tick (or sweep), then resolves each `entity` to its bound
/// atom and calls the generated dispatcher, checking `atom.vg_entity ==
/// entity` first (a component detached between the event firing and the
/// drain is a stale record, silently dropped by that check).
#[auxmacros::bind("/proc/entity_drain_domain_events")]
fn entity_drain_domain_events(domain: ByondValue) -> Result<ByondValue> {
    #[allow(clippy::cast_possible_truncation, clippy::cast_sign_loss)]
    let domain = num(&domain)?.max(0.0) as u32;
    let mut events = Vec::new();
    registry::with_domain(domain, |handler| handler.drain_events(&mut events));
    let mut flat = Vec::with_capacity(events.len() * 3);
    for (kind, entity, event_id) in events {
        flat.push(f32::from(kind));
        flat.push(entity);
        flat.push(f32::from(event_id));
    }
    list(&flat)
}

/// World reset (`verdigris_init`/`verdigris_cleanup`): every registered
/// domain drops its components, then the entity table itself is rebuilt, so
/// no handle survives into a new round.
pub fn reset_all() {
    registry::for_each(|_, handler| handler.reset());
    ENTITIES.with_borrow_mut(|t| *t = EntityTable::new());
}

/// Test/reconciler hook: every live entity and the domains it has a
/// component in, as `[entity, domain, kind, cell, ...]` flat groups of 4.
#[auxmacros::bind("/proc/entity_debug_list")]
fn entity_debug_list() -> Result<ByondValue> {
    #[allow(clippy::cast_precision_loss)]
    let mut flat: Vec<f32> = Vec::new();
    ENTITIES.with_borrow(|t| {
        for (id, slots) in t.iter() {
            for (domain, comp) in slots.iter() {
                flat.extend_from_slice(&[
                    entity_value(id),
                    domain as f32,
                    f32::from(comp.kind),
                    comp.cell as f32,
                ]);
            }
        }
    });
    list(&flat)
}

#[cfg(test)]
mod tests {
    use super::ENTITY_INDEX_MASK;

    #[test]
    fn index_mask_matches_vg_core_entity_packing() {
        assert_eq!(ENTITY_INDEX_MASK, vg_core::entity::MAX_SLOTS - 1);
    }
}
