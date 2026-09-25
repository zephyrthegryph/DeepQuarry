//! DM's `vg_entity` handle (`doc/rewrite/rust_architecture.md` §4.1) and the
//! domain-agnostic half of bind and unbind. The one entity table is the
//! [`vg_core::world::World`]'s; this module only encodes handles and walks
//! an entity's domain slots through the registry (the world's own
//! components sit behind [`vg_core::entity::WORLD_DOMAIN`]).
use byondapi::prelude::*;
use eyre::{Result, bail, eyre};
use vg_core::entity::{ComponentRef, EntityError, EntityId};

use crate::registry;
use crate::world::with_world;

/// The bits of a `vg_entity` value (after subtracting the raw-plus-one
/// offset) that carry the slot index, matching `vg_core::entity::INDEX_BITS`
/// (checked in this module's tests). DM computes an entity's table index
/// with it to look up the bound atom for event dispatch, without needing to
/// know anything else about id packing.
/// @dm-define VG_ENTITY_INDEX_MASK
pub const ENTITY_INDEX_MASK: u32 = 524_287;

// DM's `vg_entity == 0` means "unbound". A raw id's packed bits can
// themselves be 0 (index 0, generation 0 is a perfectly ordinary id), so
// crossing it as-is would make the first-ever bound entity indistinguishable
// from "no entity" — a hand-rolled sentinel collision. Every `vg_entity`
// value is the raw id plus one; callers never see the offset.
///
/// # Errors
/// For 0 (unbound) or a value that is not a packed id.
pub fn decode(v: f32) -> Result<EntityId> {
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
        if with_world(|w| Ok(w.entities().contains(id)))? {
            return Ok(id);
        }
        bail!("entity {existing} is not live");
    }
    with_world(|w| w.entities_mut().bind().map_err(|e| eyre!("{e}")))
}

/// Attaches `comp` to `entity`'s `domain` slot.
///
/// # Errors
/// As [`vg_core::entity::EntityTable::attach`].
pub fn attach(entity: EntityId, domain: usize, comp: ComponentRef) -> Result<(), EntityError> {
    with_world(|w| Ok(w.entities_mut().attach(entity, domain, comp))).unwrap_or(Err(EntityError::Stale))
}

/// Frees an entity a domain minted for itself (a node DM still names by a
/// domain key rather than a `vg_entity`), without calling back into that
/// domain's [`registry::DomainRegistry::detach`]: the caller is the domain,
/// and has already dropped its own row.
pub fn release(entity: EntityId) {
    let _ = with_world(|w| {
        let t = w.entities_mut();
        let Ok(slots) = t.components(entity) else {
            return Ok(());
        };
        for (domain, _) in slots.iter() {
            let _ = t.detach(entity, domain);
        }
        let _ = t.unbind(entity);
        Ok(())
    });
}

/// The component `entity` has in `domain`, if it is live and has one of
/// `kind`.
#[must_use]
pub fn component_of(entity: EntityId, domain: usize, kind: u16) -> Option<ComponentRef> {
    with_world(|w| Ok(w.entities().component(entity, domain, kind).ok())).ok().flatten()
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
    with_world(|w| w.entities().component(id, domain, kind).map_err(|e| eyre!("{e}")))
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
    let slots = with_world(|w| w.entities().components(id).map_err(|e| eyre!("{e}")))?;
    for (domain, comp) in slots.iter() {
        #[allow(clippy::cast_possible_truncation)]
        registry::with_domain(domain as u32, |handler| handler.detach(comp));
        with_world(|w| w.entities_mut().detach(id, domain).map(|_| ()).map_err(|e| eyre!("{e}")))?;
    }
    with_world(|w| w.entities_mut().unbind(id).map(|_| ()).map_err(|e| eyre!("{e}")))?;
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
    let slots = with_world(|w| w.entities().components(id).map_err(|e| eyre!("{e}")))?;
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

/// `SSvg`'s per-sweep maintenance for hosts not yet on the world's pacer
/// (the world itself is paced by `vg_world_tick`).
#[auxmacros::bind("/proc/entity_tick_all")]
fn entity_tick_all() -> Result<ByondValue> {
    registry::for_each(|_, handler| handler.tick());
    Ok(ByondValue::null())
}

/// Live entities (a reconciler/test metric).
#[auxmacros::bind("/proc/entity_count")]
fn entity_count() -> Result<ByondValue> {
    #[allow(clippy::cast_precision_loss)]
    let n = with_world(|w| Ok(w.entities().len()))? as f32;
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
    let valid = decode(v).is_ok_and(|id| {
        #[allow(clippy::cast_possible_truncation)]
        let code = vg_core::world::kind_code(domain as u8, kind);
        let world = with_world(|w| Ok(w.kind_by_code(code).map(|k| w.has(id, k)))).ok().flatten();
        world.unwrap_or_else(|| resolve(entity_value(id), domain, kind).is_ok())
    });
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

/// World reset (`verdigris_init`/`verdigris_cleanup`): every registered
/// domain drops its components, then the entity table itself is rebuilt, so
/// no handle survives into a new round.
///
/// # Errors
/// A world build failure (a code bug).
pub fn reset_all() -> Result<()> {
    registry::for_each(|_, handler| handler.reset());
    crate::world::reset()
}

/// Test/reconciler hook: every live entity and the domains it has a
/// component in, as `[entity, domain, kind, cell, ...]` flat groups of 4.
#[auxmacros::bind("/proc/entity_debug_list")]
fn entity_debug_list() -> Result<ByondValue> {
    #[allow(clippy::cast_precision_loss)]
    let mut flat: Vec<f32> = Vec::new();
    with_world(|w| {
        for (id, slots) in w.entities().iter() {
            for (domain, comp) in slots.iter() {
                flat.extend_from_slice(&[
                    entity_value(id),
                    domain as f32,
                    f32::from(comp.kind),
                    comp.cell as f32,
                ]);
            }
        }
        Ok(())
    })?;
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
