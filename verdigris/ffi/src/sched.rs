//! the OM scheduler's binds (`doc/rewrite/object_model_core.md §4.8`) over the world's own
//! scheduler (`vg_core::world::World`'s subscriptions): every subscription
//! and rate model is a world entity, and DM's token for it is that entity's
//! `vg_entity` value. Watches go through the watch port of a watchable
//! `code` (a component kind code, or [`GAS_HANDLES`]) in the registry.
//!
//! DM holds numbers only: a **subscriber** is the datum's registry index
//! (a `/datum/native_watch/world` handle, < 2^24). Each tick the OM scheduler makes one call,
//! `vg_world_step`, which fires due timers and rate crossings, dispatches
//! key publications, collects every watch port's wakes, and returns the
//! lanes' wakes for the tick, [`WAKE_STRIDE`] numbers per wake.

// The watch binds take one Rust parameter per DM argument (the generated
// DM call convention); clippy's `too_many_arguments` fires inside the bind
// macro's own expansion, which an item-level allow does not reach.
#![allow(clippy::too_many_arguments)]

use byondapi::prelude::*;
use eyre::{Result, bail, eyre};
use vg_core::channel::{ChannelId, ChannelInfo, Quantity};
use vg_core::entity::EntityId;
use vg_core::outbox::{Lane, MAX_SUBSCRIBER, Subscriber, Wake, reason};
use vg_core::rate::RateModel;
use vg_core::registry::world_kind_domain;
use vg_core::timer::Tick;
use vg_core::vg;
use vg_core::watch::{Cmp, Cond, Edge, Level};
use vg_core::world::{Subscription, World};

use crate::entity::{decode, entity_value};
use crate::registry;
use crate::world::{list, num, whole, with_world};

/// Numbers per wake returned by `vg_world_step`:
/// `subscriber, lane, reason, source, source_kind`.
/// @dm-define WORLD_WAKE_STRIDE
pub const WAKE_STRIDE: u32 = 5;

/// Reason class: a condition watch (Threshold, Band, Difference, ...).
/// @dm-define WORLD_REASON_CONDITION
pub const REASON_CONDITION: u32 = 0x10_0000;
/// Reason class: a `om_world_at` timer fired.
/// @dm-define WORLD_REASON_TIMER
pub const REASON_TIMER: u32 = 0x20_0000;
/// Reason class: a DM-owned key was published.
/// @dm-define WORLD_REASON_KEY
pub const REASON_KEY: u32 = 0x40_0000;
/// Reason class: a rate model crossed a watched level.
/// @dm-define WORLD_REASON_RATE
pub const REASON_RATE: u32 = 0x80_0000;
/// The bits below the reason classes: channel bits, or a key's mask.
/// @dm-define WORLD_REASON_DETAIL
pub const REASON_DETAIL: u32 = 0x0F_FFFF;

/// The watch code of gas handles (turf air, tanks, pipe networks; cells
/// are `/datum/gas_mixture` arena ids).
/// @dm-define VG_GAS_HANDLES
pub const GAS_HANDLES: u32 = 0x0FFF;

const _: () = {
    assert!(REASON_CONDITION == reason::CONDITION);
    assert!(REASON_TIMER == reason::TIMER);
    assert!(REASON_KEY == reason::KEY);
    assert!(REASON_RATE == reason::RATE);
    assert!(REASON_DETAIL == reason::CONDITION - 1);
};

/// A DM-written probe: a component with no simulation of its own, so the
/// watch path (registration checks, evaluation, stale filtering, lanes) is
/// exercised end to end from DM tests.
#[vg::component(domain = test_domain, kind = 1, owner = main)]
pub struct Probe {
    #[vg(config, unit = "kPa", default = 0.0, hysteresis = 0.5)]
    kpa: f32,
    #[vg(config, unit = "K", default = 0.0, hysteresis = 0.5)]
    kelvin: f32,
}

// --- Argument helpers ------------------------------------------------------------

fn subscriber(v: &ByondValue) -> Result<Subscriber> {
    let s = whole(v, "subscriber")?;
    if s == 0 || s > MAX_SUBSCRIBER {
        bail!("bad subscriber {s}");
    }
    Ok(s)
}

fn lane(v: &ByondValue) -> Result<Lane> {
    let id = whole(v, "lane")?;
    Lane::from_id(u8::try_from(id)?).ok_or_else(|| eyre!("bad lane {id}"))
}

fn cmp(v: &ByondValue) -> Result<Cmp> {
    match whole(v, "cmp")? {
        0 => Ok(Cmp::Above),
        1 => Ok(Cmp::Below),
        c => bail!("bad comparison {c} (0 above, 1 below)"),
    }
}

/// Key kind (< 256) and id (< 2^24) as one key.
fn key(kind: &ByondValue, id: &ByondValue) -> Result<u64> {
    let kind = whole(kind, "key kind")?;
    if kind == 0 || kind > 255 {
        bail!("key kind must be 1..255, got {kind}");
    }
    let id = whole(id, "key id")?;
    if id > 0x00FF_FFFF {
        bail!("key id must be below 2^24, got {id}");
    }
    Ok(u64::from(kind) << 24 | u64::from(id))
}

fn token(e: EntityId) -> ByondValue {
    ByondValue::from(entity_value(e))
}

fn yes(b: bool) -> ByondValue {
    ByondValue::from(if b { 1.0f32 } else { 0.0 })
}

fn channels(code: u32) -> Result<Vec<ChannelInfo>> {
    registry::with_domain(world_kind_domain(code), |d| d.channels())
        .ok_or_else(|| eyre!("code {code} has no watch port"))
}

fn channel(chans: &[ChannelInfo], v: &ByondValue) -> Result<ChannelId> {
    let ch = whole(v, "channel")?;
    if ch as usize >= chans.len() {
        bail!("bad channel {ch}");
    }
    Ok(ChannelId(u8::try_from(ch)?))
}

fn hysteresis(v: &ByondValue) -> Result<Option<f32>> {
    let h = num(v)?;
    Ok((h >= 0.0).then_some(h))
}

fn level(
    code: u32,
    ch: &ByondValue,
    cmp_v: &ByondValue,
    value: &ByondValue,
    h: &ByondValue,
    both: bool,
) -> Result<Level> {
    let chans = channels(code)?;
    let ch = channel(&chans, ch)?;
    Ok(Level {
        ch,
        cmp: cmp(cmp_v)?,
        limit: Quantity::new(num(value)?, chans[ch.index()].unit),
        hysteresis: hysteresis(h)?,
        edge: if both { Edge::Both } else { Edge::Enter },
    })
}

fn unwatch(what: Subscription) {
    if let Subscription::Watch { code, port, id } = what {
        registry::with_domain(world_kind_domain(code), |d| d.unwatch(port, id));
    }
}

/// Registers `cond` on `code`'s watch port (outside the world borrow: a
/// port may reach the world itself) and records it as a subscription.
fn watch(
    code: &ByondValue,
    sub: &ByondValue,
    lane_v: &ByondValue,
    cond: &Cond,
) -> Result<ByondValue> {
    let code = whole(code, "code")?;
    let sub = subscriber(sub)?;
    let lane = lane(lane_v)?;
    let (port, id) = registry::with_domain(world_kind_domain(code), |d| d.watch(sub, lane, cond))
        .ok_or_else(|| eyre!("code {code} has no watch port"))?
        .map_err(|e| eyre!("{e}"))?;
    Ok(token(with_world(|w| {
        w.sched_watch(sub, code, port, id).map_err(|e| eyre!("{e}"))
    })?))
}

fn subscription(v: &ByondValue) -> Option<EntityId> {
    decode(num(v).ok()?).ok()
}

// --- Binds ---------------------------------------------------------------------

/// the OM scheduler's one call per tick. Advances to tick `now` (firing timers and
/// rate crossings, dispatching key publications), collects every watch
/// port's wakes, and returns up to `budget` normal/background wakes (urgent
/// ones always) as a flat list, `WORLD_WAKE_STRIDE` numbers per wake:
/// `subscriber, lane, reason, source, source_kind`. `source` is the cell of
/// a watch wake (a gas handle, or a component's `vg_entity`), the key id of
/// a key wake (with `source_kind` its key kind), or the timer's or rate
/// model's token.
#[auxmacros::bind("/proc/world_step")]
fn world_step(now: ByondValue, budget: ByondValue) -> Result<ByondValue> {
    let now = num(&now)?;
    // `!(now >= 0.0)` also rejects NaN.
    #[allow(clippy::neg_cmp_op_on_partial_ord)]
    if !(now >= 0.0) {
        bail!("bad tick {now}");
    }
    #[allow(clippy::cast_possible_truncation, clippy::cast_sign_loss)]
    let now = now as Tick;
    let budget = whole(&budget, "budget")? as usize;
    // Phase timings (last step, microseconds) for PERF_PROFILE's rust_metrics.
    let t0 = std::time::Instant::now();
    with_world(|w| {
        w.evaluate_main_watches();
        Ok(())
    })?;
    let t1 = std::time::Instant::now();
    let mut watch_wakes: Vec<Wake> = Vec::new();
    registry::for_each(|_, d| d.take_wakes(&mut watch_wakes));
    let t2 = std::time::Instant::now();
    let wakes = with_world(|w| Ok(w.sched_step(now, budget, &watch_wakes)))?;
    {
        let metrics = crate::metrics::registry();
        metrics
            .gauge("world_step.evaluate_main_us")
            .set((t1 - t0).as_secs_f64() * 1e6);
        metrics
            .gauge("world_step.domain_wakes_us")
            .set((t2 - t1).as_secs_f64() * 1e6);
        metrics
            .gauge("world_step.sched_us")
            .set(t2.elapsed().as_secs_f64() * 1e6);
    }
    let mut flat = Vec::with_capacity(wakes.len() * WAKE_STRIDE as usize);
    for (w, e) in wakes {
        #[allow(clippy::cast_precision_loss)]
        let (source, kind) = match e {
            Some(e) => (entity_value(e), 0.0),
            None if w.reason & reason::KEY != 0 && w.source > 0x00FF_FFFF => {
                ((w.source & 0x00FF_FFFF) as f32, (w.source >> 24) as f32)
            }
            None => (w.source as f32, 0.0),
        };
        #[allow(clippy::cast_precision_loss)]
        flat.extend_from_slice(&[
            w.subscriber as f32,
            f32::from(w.lane as u8),
            w.reason as f32,
            source,
            kind,
        ]);
    }
    list(flat)
}

/// `om_world_at`: wakes `subscriber` on `lane` at tick `tick` (a past tick fires
/// at the next step). Returns the token.
#[auxmacros::bind("/proc/world_at")]
fn world_at(sub: ByondValue, lane_v: ByondValue, tick: ByondValue) -> Result<ByondValue> {
    let (sub, lane) = (subscriber(&sub)?, lane(&lane_v)?);
    let t = num(&tick)?;
    if !t.is_finite() {
        bail!("bad tick {t}");
    }
    #[allow(clippy::cast_possible_truncation, clippy::cast_sign_loss)]
    let t = t.max(0.0).ceil() as Tick;
    Ok(token(with_world(|w| {
        w.sched_at(sub, lane, t).map_err(|e| eyre!("{e}"))
    })?))
}

/// `om_world_on_key`: wakes `subscriber` when key (`kind`, `id`) is published
/// with any bit of `mask`. Returns the token.
#[auxmacros::bind("/proc/world_on_key")]
fn world_on_key(
    sub: ByondValue,
    kind: ByondValue,
    id: ByondValue,
    mask: ByondValue,
    lane_v: ByondValue,
) -> Result<ByondValue> {
    let sub = subscriber(&sub)?;
    let key = key(&kind, &id)?;
    let mask = whole(&mask, "mask")? & REASON_DETAIL;
    if mask == 0 {
        bail!("key mask must be non-zero (below WORLD_REASON_CONDITION)");
    }
    let lane = lane(&lane_v)?;
    Ok(token(with_world(|w| {
        w.sched_on_key(sub, key, mask, lane)
            .map_err(|e| eyre!("{e}"))
    })?))
}

/// `om_world_publish`: DM-owned state under key (`kind`, `id`) changed. Merged
/// per tick; a key nobody subscribes to costs a lookup and is not stored.
#[auxmacros::bind("/proc/world_publish")]
fn world_publish(kind: ByondValue, id: ByondValue, mask: ByondValue) -> Result<ByondValue> {
    let key = key(&kind, &id)?;
    let mask = whole(&mask, "mask")? & REASON_DETAIL;
    with_world(|w| {
        w.sched_publish(key, mask);
        Ok(ByondValue::null())
    })
}

/// `qdel(watch)`: drops one subscription. Returns 1 if the token was live.
#[auxmacros::bind("/proc/world_cancel")]
fn world_cancel(token_v: ByondValue) -> Result<ByondValue> {
    let Some(e) = subscription(&token_v) else {
        return Ok(yes(false));
    };
    let what = with_world(|w| Ok(w.unsubscribe(e)))?;
    if let Some(what) = what {
        unwatch(what);
    }
    Ok(yes(what.is_some()))
}

/// `watch Destroy()`: drops every subscription and pending wake of `subscriber`.
/// Returns how many subscriptions it had.
#[auxmacros::bind("/proc/world_clear")]
fn world_clear(sub: ByondValue) -> Result<ByondValue> {
    let sub = subscriber(&sub)?;
    let (n, watches) = with_world(|w| Ok((w.subscriptions(Some(sub)), w.clear_subscriber(sub))))?;
    watches.into_iter().for_each(unwatch);
    #[allow(clippy::cast_precision_loss)]
    Ok(ByondValue::from(n as f32))
}

/// Live subscriptions of `subscriber` (tests and the audit).
#[auxmacros::bind("/proc/world_subscriptions")]
fn world_subscriptions(sub: ByondValue) -> Result<ByondValue> {
    let sub = subscriber(&sub)?;
    #[allow(clippy::cast_precision_loss)]
    with_world(|w| Ok(ByondValue::from(w.subscriptions(Some(sub)) as f32)))
}

/// Scheduler counters as a flat list: timers pending, timers fired, rate
/// crossings fired, key publications, rate models, keys with subscribers,
/// live subscriptions, wakes received, merged, delivered, deferred, 0,
/// backlog urgent/normal/background, 0.
#[auxmacros::bind("/proc/world_sched_stats")]
fn world_sched_stats() -> Result<ByondValue> {
    let v = with_world(|w| {
        let r = w.sched_metrics();
        let (received, merged, delivered, deferred, b) = w.sched_lanes();
        #[allow(clippy::cast_precision_loss)]
        Ok(vec![
            r.timers_pending as f32,
            r.timers_fired as f32,
            r.crossings_fired as f32,
            r.publications as f32,
            r.models as f32,
            w.sched_keys() as f32,
            w.subscriptions(None) as f32,
            received as f32,
            merged as f32,
            delivered as f32,
            deferred as f32,
            0.0,
            b[0] as f32,
            b[1] as f32,
            b[2] as f32,
            0.0,
        ])
    })?;
    list(v)
}

// --- Watches ---------------------------------------------------------------------

/// `om_world_on_change`: wakes when any channel in `mask` of `cell` moves past its
/// hysteresis. Returns the token.
#[auxmacros::bind("/proc/world_watch_changed")]
fn world_watch_changed(
    code: ByondValue,
    sub: ByondValue,
    lane: ByondValue,
    cell: ByondValue,
    mask: ByondValue,
) -> Result<ByondValue> {
    let cond = Cond::Changed {
        cell: whole(&cell, "cell")?,
        mask: whole(&mask, "mask")?,
    };
    watch(&code, &sub, &lane, &cond)
}

/// `om_world_when` threshold: `cmp` 0 above / 1 below `value` on channel `ch`;
/// `hysteresis` < 0 takes the channel's; `both_edges` also wakes on leaving.
#[auxmacros::bind("/proc/world_watch_threshold")]
fn world_watch_threshold(
    code: ByondValue,
    sub: ByondValue,
    lane: ByondValue,
    cell: ByondValue,
    ch: ByondValue,
    cmp: ByondValue,
    value: ByondValue,
    hysteresis: ByondValue,
    both_edges: ByondValue,
) -> Result<ByondValue> {
    let c = whole(&code, "code")?;
    let cond = Cond::Threshold {
        cell: whole(&cell, "cell")?,
        level: level(c, &ch, &cmp, &value, &hysteresis, both_edges.is_true())?,
    };
    watch(&code, &sub, &lane, &cond)
}

/// `om_world_when` band: wakes when `cell`'s channel `ch` moves into a
/// different band of the increasing `levels` list (and once at registration).
#[auxmacros::bind("/proc/world_watch_band")]
fn world_watch_band(
    code: ByondValue,
    sub: ByondValue,
    lane: ByondValue,
    cell: ByondValue,
    ch: ByondValue,
    levels: ByondValue,
    hysteresis: ByondValue,
) -> Result<ByondValue> {
    let chans = channels(whole(&code, "code")?)?;
    let ch_id = channel(&chans, &ch)?;
    let levels = levels
        .get_list_values()?
        .iter()
        .map(|v| Ok(v.get_number()?))
        .collect::<Result<Vec<f32>>>()?;
    let cond = Cond::Band {
        cell: whole(&cell, "cell")?,
        ch: ch_id,
        unit: chans[ch_id.index()].unit,
        levels,
        hysteresis: self::hysteresis(&hysteresis)?,
    };
    watch(&code, &sub, &lane, &cond)
}

/// `om_world_when` difference: `a - b` (or `|a - b|` with `abs`) on channel
/// `ch` crosses `value` like a threshold.
#[auxmacros::bind("/proc/world_watch_difference")]
fn world_watch_difference(
    code: ByondValue,
    sub: ByondValue,
    lane: ByondValue,
    a: ByondValue,
    b: ByondValue,
    ch: ByondValue,
    cmp: ByondValue,
    value: ByondValue,
    hysteresis: ByondValue,
    abs: ByondValue,
) -> Result<ByondValue> {
    let c = whole(&code, "code")?;
    let cond = Cond::Difference {
        a: whole(&a, "cell a")?,
        b: whole(&b, "cell b")?,
        level: level(c, &ch, &cmp, &value, &hysteresis, false)?,
        abs: abs.is_true(),
    };
    watch(&code, &sub, &lane, &cond)
}

// --- Rate models -------------------------------------------------------------------

fn add_model(model: impl FnOnce(f64) -> RateModel) -> Result<ByondValue> {
    #[allow(clippy::cast_precision_loss)]
    let e = with_world(|w| {
        let now = w.sched_now() as f64;
        w.rate_add(model(now)).map_err(|e| eyre!("{e}"))
    })?;
    Ok(token(e))
}

fn bound(v: &ByondValue, default: f64) -> f64 {
    v.get_number().map_or(default, f64::from)
}

/// A linear model starting at `v0` now, changing by `rate` per tick,
/// clamped to [`min`, `max`] (null for unbounded). Returns the model id.
#[auxmacros::bind("/proc/world_rate_linear")]
fn world_rate_linear(
    v0: ByondValue,
    rate: ByondValue,
    min: ByondValue,
    max: ByondValue,
) -> Result<ByondValue> {
    let (v0, rate) = (f64::from(num(&v0)?), f64::from(num(&rate)?));
    let (min, max) = (bound(&min, f64::NEG_INFINITY), bound(&max, f64::INFINITY));
    add_model(|t0| RateModel::Linear {
        v0,
        rate,
        t0,
        min,
        max,
    })
}

/// A model relaxing from `v0` toward `target` at `k` per tick
/// (`target + (v0 - target) e^(-k t)`). Returns the model id.
#[auxmacros::bind("/proc/world_rate_relax")]
fn world_rate_relax(v0: ByondValue, target: ByondValue, k: ByondValue) -> Result<ByondValue> {
    let k = f64::from(num(&k)?);
    // `!(k > 0.0)` also rejects NaN.
    #[allow(clippy::neg_cmp_op_on_partial_ord)]
    if !(k > 0.0) {
        bail!("relax rate must be positive");
    }
    let (v0, target) = (f64::from(num(&v0)?), f64::from(num(&target)?));
    add_model(|t0| RateModel::Relax { target, v0, k, t0 })
}

/// A store with named inflow/outflow terms (`vg_world_rate_set_term`), clamped.
#[auxmacros::bind("/proc/world_rate_sum")]
fn world_rate_sum(v0: ByondValue, min: ByondValue, max: ByondValue) -> Result<ByondValue> {
    let v0 = f64::from(num(&v0)?);
    let (min, max) = (bound(&min, f64::NEG_INFINITY), bound(&max, f64::INFINITY));
    add_model(|t0| RateModel::Sum {
        v0,
        t0,
        terms: Vec::new(),
        min,
        max,
    })
}

fn update(
    model: &ByondValue,
    change: impl FnOnce(&mut RateModel) -> Result<()>,
) -> Result<ByondValue> {
    let e = subscription(model).ok_or_else(|| eyre!("bad rate model {model:?}"))?;
    let mut result = Ok(());
    if !with_world(|w| Ok(w.rate_update(e, |m| result = change(m))))? {
        bail!("stale rate model");
    }
    result?;
    Ok(ByondValue::null())
}

/// Sets a model's value now (the rate continues from it).
#[auxmacros::bind("/proc/world_rate_set")]
fn world_rate_set(model: ByondValue, value: ByondValue) -> Result<ByondValue> {
    let value = f64::from(num(&value)?);
    update(&model, |m| {
        match m {
            RateModel::Linear { v0, .. }
            | RateModel::Relax { v0, .. }
            | RateModel::Sum { v0, .. } => *v0 = value,
        }
        Ok(())
    })
}

/// Sets a linear model's rate per tick (or a relax model's target).
#[auxmacros::bind("/proc/world_rate_set_rate")]
fn world_rate_set_rate(model: ByondValue, rate: ByondValue) -> Result<ByondValue> {
    let r = f64::from(num(&rate)?);
    update(&model, |m| {
        match m {
            RateModel::Linear { rate, .. } => *rate = r,
            RateModel::Relax { target, .. } => *target = r,
            RateModel::Sum { .. } => {
                bail!("a sum model's rate is its terms; use vg_world_rate_set_term")
            }
        }
        Ok(())
    })
}

/// Sets (or, with rate 0, removes) term `term` of a sum model.
#[auxmacros::bind("/proc/world_rate_set_term")]
fn world_rate_set_term(
    model: ByondValue,
    term: ByondValue,
    rate: ByondValue,
) -> Result<ByondValue> {
    let term = whole(&term, "term")?;
    let r = f64::from(num(&rate)?);
    update(&model, |m| {
        let RateModel::Sum { terms, .. } = m else {
            bail!("not a sum model");
        };
        terms.retain(|t| t.0 != term);
        if r != 0.0 {
            terms.push((term, r));
        }
        Ok(())
    })
}

/// The model's value now.
#[auxmacros::bind("/proc/world_rate_read")]
fn world_rate_read(model: ByondValue) -> Result<ByondValue> {
    let e = subscription(&model).ok_or_else(|| eyre!("bad rate model {model:?}"))?;
    #[allow(clippy::cast_possible_truncation)]
    let v = with_world(|w| w.rate_read(e).ok_or_else(|| eyre!("stale rate model")))? as f32;
    Ok(ByondValue::from(v))
}

/// Wakes `subscriber` whenever the model enters `cmp level` (0 above: `v >=
/// level`, 1 below), at the exact predicted crossing tick; at once if it
/// already holds. Returns the token.
#[auxmacros::bind("/proc/world_rate_watch")]
fn world_rate_watch(
    model: ByondValue,
    sub: ByondValue,
    lane_v: ByondValue,
    cmp_v: ByondValue,
    level: ByondValue,
) -> Result<ByondValue> {
    let e = subscription(&model).ok_or_else(|| eyre!("bad rate model {model:?}"))?;
    let (sub, lane, cmp) = (subscriber(&sub)?, lane(&lane_v)?, cmp(&cmp_v)?);
    let level = f64::from(num(&level)?);
    let t = with_world(|w| {
        w.rate_watch(e, sub, lane, cmp, level)
            .map_err(|_| eyre!("stale rate model or bad level"))
    })?;
    Ok(token(t))
}

/// Removes a model and its watches. Returns 1 if it was live.
#[auxmacros::bind("/proc/world_rate_remove")]
fn world_rate_remove(model: ByondValue) -> Result<ByondValue> {
    let Some(e) = subscription(&model) else {
        return Ok(yes(false));
    };
    with_world(|w: &mut World| Ok(yes(w.rate_remove(e))))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::gas::mix::{self, MixRef};
    use vg_gas::cell::gas_ch;
    use vg_gas::gas::Mixture;

    #[test]
    fn a_gas_handle_watch_wakes_through_the_scheduler() {
        with_world(|_| Ok(())).unwrap();
        let mut tank = Mixture::from_vol(70.0);
        tank.set_moles(0, 10.0);
        tank.set_temperature(293.15);
        let r = MixRef::Main(mix::alloc(tank.clone()).unwrap());
        let cond = Cond::Changed {
            cell: r.id(),
            mask: gas_ch::PRESSURE.bit(),
        };
        let (port, id) = registry::with_domain(world_kind_domain(GAS_HANDLES), |d| {
            d.watch(7, Lane::Urgent, &cond)
        })
        .unwrap()
        .unwrap();
        with_world(|w| {
            w.sched_watch(7, GAS_HANDLES, port, id)
                .map_err(|e| eyre!("{e}"))
        })
        .unwrap();
        let step = |now| {
            let mut wakes = Vec::new();
            registry::for_each(|_, d| d.take_wakes(&mut wakes));
            with_world(|w| Ok(w.sched_step(now, 100, &wakes))).unwrap()
        };
        assert!(step(1).is_empty());
        let mut after = tank.clone();
        after.set_moles(0, 20.0);
        mix::store(r, &tank, &after);
        let woke = step(2);
        assert_eq!(woke.len(), 1, "{woke:?}");
    }
}
