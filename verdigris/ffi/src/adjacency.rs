//! The binds of DM's `adjacency()` declaration (`doc/rewrite/final_api.html`
//! section 6, "Lifecycle forms", form 4; `code/engine/lifeforms/adjacency.dm`).
//! The index itself is `vg_core::adjacency`; this module owns the one index
//! of the running world and converts its answers to DM lists.
//!
//! DM holds numbers only: a member is DM's handle for an atom (< 2^24), a
//! kind is the id DM gave the kind's name. Every change bind returns the
//! handles whose neighbour sets changed, so DM recomputes exactly those.

use std::cell::RefCell;

use byondapi::prelude::*;
use eyre::{Result, eyre};
use vg_core::adjacency::AdjacencyIndex;

use crate::world::{list, whole};

thread_local! {
    static INDEX: RefCell<AdjacencyIndex> = RefCell::new(AdjacencyIndex::new());
}

/// Drops every member (a world reset: `verdigris_init`, `verdigris_cleanup`).
pub fn reset() {
    INDEX.with_borrow_mut(AdjacencyIndex::clear);
}

#[allow(clippy::cast_possible_truncation)]
fn kind(v: &ByondValue) -> Result<u16> {
    let k = whole(v, "kind")?;
    u16::try_from(k).map_err(|_| eyre!("adjacency kind {k} out of range"))
}

#[allow(clippy::cast_possible_wrap)]
fn coord(v: &ByondValue, what: &str) -> Result<i32> {
    Ok(whole(v, what)? as i32)
}

#[allow(clippy::cast_precision_loss)]
fn handles(h: Vec<u32>) -> Result<ByondValue> {
    list(h.into_iter().map(|x| x as f32))
}

/// Places (or moves) `handle` of `kind` on `(x, y, z)`, looking on `dirs`. Returns the handles whose neighbour
/// sets changed: the member itself first (empty when nothing moved).
#[auxmacros::bind("/proc/vg_adjacency_place")]
fn adjacency_place(
    kind_id: ByondValue,
    handle: ByondValue,
    x: ByondValue,
    y: ByondValue,
    z: ByondValue,
    dirs: ByondValue,
) -> Result<ByondValue> {
    let k = kind(&kind_id)?;
    let h = whole(&handle, "handle")?;
    let (x, y, z) = (coord(&x, "x")?, coord(&y, "y")?, coord(&z, "z")?);
    let d = whole(&dirs, "dirs")?;
    let changed = INDEX.with_borrow_mut(|idx| idx.place(k, h, x, y, z, d));
    handles(changed)
}

/// Removes `handle` from `kind`. Returns the neighbours whose sets changed.
#[auxmacros::bind("/proc/vg_adjacency_remove")]
fn adjacency_remove(kind_id: ByondValue, handle: ByondValue) -> Result<ByondValue> {
    let k = kind(&kind_id)?;
    let h = whole(&handle, "handle")?;
    let changed = INDEX.with_borrow_mut(|idx| idx.remove(k, h));
    handles(changed)
}

/// The neighbours `handle` sees in `kind`: `[handle, junction bit, ...]`.
#[auxmacros::bind("/proc/vg_adjacency_seen")]
#[allow(clippy::cast_precision_loss)]
fn adjacency_seen(kind_id: ByondValue, handle: ByondValue) -> Result<ByondValue> {
    let k = kind(&kind_id)?;
    let h = whole(&handle, "handle")?;
    let (_, seen) = INDEX.with_borrow(|idx| idx.junction(k, h));
    list(seen.into_iter().flat_map(|s| [s.handle as f32, s.bit as f32]))
}

/// Members placed, over every kind (diagnostics, tests).
#[auxmacros::bind("/proc/vg_adjacency_count")]
#[allow(clippy::cast_precision_loss)]
fn adjacency_count() -> Result<ByondValue> {
    Ok(ByondValue::from(INDEX.with_borrow(AdjacencyIndex::len) as f32))
}

/// Drops every member (DM's round start).
#[auxmacros::bind("/proc/vg_adjacency_reset")]
fn adjacency_reset() -> Result<ByondValue> {
    reset();
    Ok(ByondValue::null())
}
