//! SSreactor's binds (`doc/rewrite/reactor.md`, `rust_core.md` §7): the
//! main-side [`Reactor`] (timer wheel, wake lanes, rate models, DM-owned
//! keys), the watch ports of the domains that are on the reactor, and one
//! drain per tick.
//!
//! Everything here runs on BYOND's main thread. DM holds numbers only:
//! - a **subscriber** is the datum's registry index (`reactor_id`, < 2^24);
//! - a **token** names one subscription (timer, key, model watch or domain
//!   watch) for `REACT_CANCEL`, encoded `index * 16 + (generation & 15)`;
//! - a **model** is a rate model id, encoded the same way.
//!
//! Each tick SSreactor makes one call, [`vg_react_step`], which fires due
//! timers and rate crossings, dispatches key publications, evaluates and
//! drains the domain watches, and returns the lanes' wakes for the tick as a
//! flat list of [`REACT_WAKE_STRIDE`] numbers per wake.
//!
//! Domains: the **probe** ([`REACT_DOMAIN_PROBE`]) is a small field of
//! pressure/temperature cells DM writes directly, so the watch path
//! (registration checks, frame evaluation, stale filtering, lanes) is
//! exercised end to end from DM tests. Domains that live in other crates
//! (gas, [`REACT_DOMAIN_GAS`]) register an [`ExternalDomain`] with
//! [`register_domain`]; their wakes are collected at every step.
//!
//! `react_watch_threshold`/`react_watch_difference`'s DM call convention is
//! one Rust parameter per DM argument, so their argument counts (9, 10) are
//! inherent to what `REACT_WHEN` needs, not something to bundle away without
//! also changing the generated binding (owned by `rewrite/bindings`, not
//! this audit). clippy's `too_many_arguments` still flags them because the
//! warning is generated inside `::byondapi::bind`'s own macro expansion,
//! which doesn't inherit an item-level `#[allow]` from the `#[bind]`d fn
//! (that macro isn't touched here either) -- hence the file-level allow
//! below instead of one at each function.
#![allow(clippy::too_many_arguments)]

use std::cell::RefCell;
use std::collections::HashMap;
use std::time::Instant;

use byondapi::prelude::*;
use eyre::{Result, bail, eyre};
use vg_core::channel::{ChannelId, ChannelInfo, Quantity, channel_infos};
use vg_core::channels;
use vg_core::cow::{ChunkLayout, CowStore};
use vg_core::outbox::{Lane, MAX_SUBSCRIBER, Outbox, Subscriber, Wake, WatchId, reason};
use vg_core::owner::{Applied, Domain};
use vg_core::reactor::{ModelId, RateModel, Reactor};
use vg_core::timer::{Tick, TimerId};
use vg_core::watch::{Cmp, Cond, Edge, Level, WatchPort, WatchState};

// --- DM constants ------------------------------------------------------------

/// Numbers per wake returned by `vg_react_step`:
/// `subscriber, lane, reason, source, source_kind`.
/// @dm-define REACT_WAKE_STRIDE
pub const WAKE_STRIDE: u32 = 5;

/// Reason class: a condition watch (Threshold, Band, Difference, ...).
/// @dm-define REACT_REASON_CONDITION
pub const REASON_CONDITION: u32 = 0x10_0000;
/// Reason class: a `REACT_AT` timer fired.
/// @dm-define REACT_REASON_TIMER
pub const REASON_TIMER: u32 = 0x20_0000;
/// Reason class: a DM-owned key was published.
/// @dm-define REACT_REASON_KEY
pub const REASON_KEY: u32 = 0x40_0000;
/// Reason class: a rate model crossed a watched level.
/// @dm-define REACT_REASON_RATE
pub const REASON_RATE: u32 = 0x80_0000;
/// The bits below the reason classes: channel bits, or a key's mask.
/// @dm-define REACT_REASON_DETAIL
pub const REASON_DETAIL: u32 = 0x0F_FFFF;

/// The probe domain: DM-written test cells (see the module docs).
/// @dm-define REACT_DOMAIN_PROBE
pub const DOMAIN_PROBE: u32 = 1;
/// Cells in the probe domain.
/// @dm-define REACT_PROBE_CELLS
pub const PROBE_CELLS: u32 = 256;
/// Gas: turf gas and main-owned mixtures, by gas handle (vg-gas).
/// @dm-define REACT_DOMAIN_GAS
pub const DOMAIN_GAS: u32 = 2;

// --- External domains ---------------------------------------------------------

/// A watchable domain that lives in another crate. It keeps its own watch
/// ports; the reactor host only routes registrations and collects wakes.
pub trait ExternalDomain {
    /// The domain's channel table (checks channel ids and units).
    fn channels(&self) -> Vec<ChannelInfo>;
    /// Registers a watch; returns the domain's sub-port and the watch id.
    ///
    /// # Errors
    /// If the condition names invalid cells or is rejected.
    fn watch(&mut self, sub: Subscriber, lane: Lane, cond: &Cond) -> Result<(u8, WatchId)>;
    fn unwatch(&mut self, port: u8, id: WatchId);
    /// Moves the wakes produced since the last call into `out`.
    fn take_wakes(&mut self, out: &mut Vec<Wake>);
}

thread_local! {
    static EXTERNAL: RefCell<HashMap<u32, Box<dyn ExternalDomain>>> = RefCell::new(HashMap::new());
}

/// Registers (or replaces) an external domain under a `REACT_DOMAIN_*` id.
pub fn register_domain(id: u32, domain: Box<dyn ExternalDomain>) {
    EXTERNAL.with_borrow_mut(|e| {
        e.insert(id, domain);
    });
}

fn external<T>(id: u32, f: impl FnOnce(&mut dyn ExternalDomain) -> T) -> Option<T> {
    EXTERNAL.with_borrow_mut(|e| e.get_mut(&id).map(|d| f(d.as_mut())))
}

fn channel_table(domain: u32) -> Result<Vec<ChannelInfo>> {
    if domain == DOMAIN_PROBE {
        return Ok(channel_infos::<Probe>());
    }
    external(domain, |d| d.channels()).ok_or_else(|| eyre!("domain {domain} has no watch port"))
}

const _: () = {
    assert!(REASON_CONDITION == reason::CONDITION);
    assert!(REASON_TIMER == reason::TIMER);
    assert!(REASON_KEY == reason::KEY);
    assert!(REASON_RATE == reason::RATE);
    assert!(REASON_DETAIL == reason::CONDITION - 1);
};

// --- The probe domain -------------------------------------------------------

#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct ProbeCell {
    kpa: f32,
    kelvin: f32,
}

pub struct Probe;

impl Domain for Probe {
    type Value = ProbeCell;
    type Command = ();
    const NAME: &'static str = "probe";
    fn apply(_: &mut ProbeCell, (): &()) -> Applied {
        Applied::default()
    }
}

channels! { pub mod probe_ch for Probe {
    PRESSURE: Scalar<Kpa> hysteresis 0.5 => |c, o| o[0] = c.kpa,
    TEMPERATURE: Scalar<Kelvin> hysteresis 0.5 => |c, o| o[0] = c.kelvin,
}}

/// A domain store with its watches, evaluated synchronously at each step.
struct ProbeDomain {
    store: CowStore<ProbeCell>,
    state: WatchState<Probe>,
    port: WatchPort<Probe>,
    out: Outbox<ProbeCell>,
}

impl ProbeDomain {
    fn new() -> Self {
        let layout = ChunkLayout::linear_with_chunk(PROBE_CELLS, 16);
        Self {
            store: CowStore::new(layout),
            state: WatchState::new(layout),
            port: WatchPort::new(layout),
            out: Outbox::default(),
        }
    }

    /// One frame: registrations in, evaluate, drop stale records.
    fn frame(&mut self, into: &mut Reactor) -> usize {
        self.port.dispatch(&mut self.state);
        self.state.evaluate(&self.store, &mut self.out);
        let mut out = std::mem::take(&mut self.out);
        self.port.filter(&mut out);
        into.ingest(out.wakes());
        out.wakes().len()
    }
}

// --- Host tokens ------------------------------------------------------------

#[derive(Clone, Copy, Debug, PartialEq)]
enum Sub {
    Timer(TimerId),
    Key(u64),
    Rate { model: ModelId, token: u32 },
    Watch { domain: u32, port: u8, id: WatchId },
}

#[derive(Debug)]
struct Slot {
    generation: u32,
    live: Option<(Subscriber, Sub)>,
}

/// Maps DM tokens to subscriptions, with generations so a stale token never
/// cancels a newer subscription in the same slot.
#[derive(Debug, Default)]
struct Tokens {
    slots: Vec<Slot>,
    free: Vec<u32>,
    by_sub: HashMap<Subscriber, Vec<u32>>,
}

const MAX_SLOTS: u32 = 1 << 20;

fn encode(index: u32, generation: u32) -> f32 {
    #[allow(clippy::cast_precision_loss)]
    let v = (index * 16 + (generation & 15)) as f32;
    v
}

fn decode(v: f32) -> Option<(u32, u32)> {
    if !(v >= 0.0 && v < (MAX_SLOTS * 16) as f32) || v.fract() != 0.0 {
        return None;
    }
    #[allow(clippy::cast_possible_truncation, clippy::cast_sign_loss)]
    let n = v as u32;
    Some((n / 16, n % 16))
}

impl Tokens {
    fn add(&mut self, sub: Subscriber, what: Sub) -> Result<u32> {
        let index = match self.free.pop() {
            Some(i) => i,
            None => {
                let i = u32::try_from(self.slots.len())?;
                if i >= MAX_SLOTS {
                    bail!("too many reactor subscriptions");
                }
                self.slots.push(Slot {
                    generation: 0,
                    live: None,
                });
                i
            }
        };
        self.slots[index as usize].live = Some((sub, what));
        self.by_sub.entry(sub).or_default().push(index);
        Ok(index)
    }

    fn token(&self, index: u32) -> f32 {
        encode(index, self.slots[index as usize].generation)
    }

    fn get(&self, token: f32) -> Option<(u32, Subscriber, Sub)> {
        let (index, g) = decode(token)?;
        let slot = self.slots.get(index as usize)?;
        let (sub, what) = slot.live?;
        (slot.generation & 15 == g).then_some((index, sub, what))
    }

    fn release(&mut self, index: u32) {
        let slot = &mut self.slots[index as usize];
        let Some((sub, _)) = slot.live.take() else {
            return;
        };
        slot.generation = slot.generation.wrapping_add(1);
        self.free.push(index);
        if let Some(list) = self.by_sub.get_mut(&sub) {
            if let Some(i) = list.iter().position(|&x| x == index) {
                list.swap_remove(i);
            }
            if list.is_empty() {
                self.by_sub.remove(&sub);
            }
        }
    }

    fn live(&self) -> usize {
        self.slots.len() - self.free.len()
    }
}

// --- Rate model ids -----------------------------------------------------------

fn model_value(id: ModelId) -> f32 {
    encode(id.index, id.generation)
}

/// Decodes a model id; the reactor rejects a wrong generation (it compares
/// the full generation, so the low bits are matched against the live slot).
fn model_id(host: &Host, v: f32) -> Result<ModelId> {
    let (index, g) = decode(v).ok_or_else(|| eyre!("bad rate model id {v}"))?;
    let generation = *host
        .model_generations
        .get(index as usize)
        .ok_or_else(|| eyre!("unknown rate model {v}"))?;
    if generation & 15 != g {
        bail!("stale rate model {v}");
    }
    Ok(ModelId { index, generation })
}

// --- The host -----------------------------------------------------------------

struct Host {
    reactor: Reactor,
    tokens: Tokens,
    probe: ProbeDomain,
    /// Full generation per model slot (DM ids carry only 4 bits).
    model_generations: Vec<u32>,
    wakes: Vec<Wake>,
    fired: Vec<(Subscriber, u32)>,
    watch_wakes: u64,
    steps: u64,
    last_step_us: f64,
}

impl Host {
    fn new() -> Self {
        Self {
            reactor: Reactor::new(0),
            tokens: Tokens::default(),
            probe: ProbeDomain::new(),
            model_generations: Vec::new(),
            wakes: Vec::new(),
            fired: Vec::new(),
            watch_wakes: 0,
            steps: 0,
            last_step_us: 0.0,
        }
    }

    fn track_model(&mut self, id: ModelId) {
        let i = id.index as usize;
        if self.model_generations.len() <= i {
            self.model_generations.resize(i + 1, 0);
        }
        self.model_generations[i] = id.generation;
    }

    /// Drops one subscription everywhere it lives.
    fn cancel(&mut self, index: u32, what: Sub) {
        match what {
            Sub::Timer(id) => {
                self.reactor.cancel_timer(id);
            }
            Sub::Key(key) => {
                let sub = self.tokens.slots[index as usize].live.map(|l| l.0);
                if let Some(sub) = sub {
                    // Other tokens of the same subscriber on the same key
                    // share one subscription; drop it only with the last.
                    let others = self.tokens.by_sub.get(&sub).is_some_and(|l| {
                        l.iter().any(|&o| {
                            o != index
                                && matches!(self.tokens.slots[o as usize].live, Some((_, Sub::Key(k))) if k == key)
                        })
                    });
                    if !others {
                        self.reactor.unsubscribe_key(sub, key);
                    }
                }
            }
            Sub::Rate { model, token } => {
                self.reactor.unwatch_model(model, token);
            }
            Sub::Watch { domain, port, id } => unwatch(&mut self.probe, domain, port, id),
        }
        self.tokens.release(index);
    }

    fn clear(&mut self, sub: Subscriber) -> usize {
        let indices = self.tokens.by_sub.remove(&sub).unwrap_or_default();
        let n = indices.len();
        for index in indices {
            if let Some((_, Sub::Watch { domain, port, id })) =
                self.tokens.slots[index as usize].live
            {
                unwatch(&mut self.probe, domain, port, id);
            }
            let slot = &mut self.tokens.slots[index as usize];
            if slot.live.take().is_some() {
                slot.generation = slot.generation.wrapping_add(1);
                self.tokens.free.push(index);
            }
        }
        // Timers, key subscriptions, model watches and pending wakes.
        self.reactor.clear(sub);
        n
    }

    fn step(&mut self, now: Tick, budget: usize) -> Vec<f32> {
        let start = Instant::now();
        self.reactor.tick(now);
        self.reactor.take_fired_timers(&mut self.fired);
        let mut spent: HashMap<u32, f32> = HashMap::new();
        for (_, index) in std::mem::take(&mut self.fired) {
            // A fired timer's token is spent. Remember its DM value, which
            // the wake reports as its source.
            let is_timer = self
                .tokens
                .slots
                .get(index as usize)
                .is_some_and(|s| matches!(s.live, Some((_, Sub::Timer(_)))));
            if is_timer {
                spent.insert(index, self.tokens.token(index));
                self.tokens.release(index);
            }
        }
        self.watch_wakes += self.probe.frame(&mut self.reactor) as u64;
        let mut external_wakes = Vec::new();
        EXTERNAL.with_borrow_mut(|e| {
            for d in e.values_mut() {
                d.take_wakes(&mut external_wakes);
            }
        });
        self.watch_wakes += external_wakes.len() as u64;
        self.reactor.ingest(&external_wakes);
        self.wakes.clear();
        self.reactor.drain(budget, &mut self.wakes);
        let mut flat = Vec::with_capacity(self.wakes.len() * WAKE_STRIDE as usize);
        for w in &self.wakes {
            // The source of the wake's first reason: a key (id, kind), a
            // timer's DM token, a model id, or a watched cell.
            #[allow(clippy::cast_precision_loss)]
            let (source, kind) = if w.reason & reason::KEY != 0 && w.source > 0x00FF_FFFF {
                ((w.source & 0x00FF_FFFF) as f32, (w.source >> 24) as f32)
            } else if let Some(&token) = spent
                .get(&w.source)
                .filter(|_| w.reason & reason::TIMER != 0)
            {
                (token, 0.0)
            } else if w.reason & reason::RATE != 0 {
                let generation = self
                    .model_generations
                    .get(w.source as usize)
                    .copied()
                    .unwrap_or(0);
                (encode(w.source, generation), 0.0)
            } else {
                (w.source as f32, 0.0)
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
        self.steps += 1;
        self.last_step_us = start.elapsed().as_secs_f64() * 1e6;
        self.record_metrics();
        flat
    }

    #[allow(clippy::cast_precision_loss)]
    fn record_metrics(&self) {
        let m = crate::metrics::registry();
        let r = self.reactor.metrics();
        let lanes = self.reactor.lanes();
        let backlog = lanes.backlog();
        m.counter("reactor.timers_fired").set(r.timers_fired);
        m.counter("reactor.crossings_fired").set(r.crossings_fired);
        m.counter("reactor.publications").set(r.publications);
        m.counter("reactor.wakes_received").set(lanes.received);
        m.counter("reactor.wakes_merged").set(lanes.merged);
        m.counter("reactor.wakes_delivered").set(lanes.delivered);
        m.counter("reactor.wakes_deferred").set(lanes.deferred);
        m.counter("reactor.watch_wakes").set(self.watch_wakes);
        m.gauge("reactor.timers_pending")
            .set(r.timers_pending as f64);
        m.gauge("reactor.models").set(r.models as f64);
        m.gauge("reactor.keys").set(self.reactor.keys() as f64);
        m.gauge("reactor.subscriptions")
            .set(self.tokens.live() as f64);
        m.gauge("reactor.backlog.urgent").set(backlog[0] as f64);
        m.gauge("reactor.backlog.normal").set(backlog[1] as f64);
        m.gauge("reactor.backlog.background").set(backlog[2] as f64);
        m.gauge("reactor.step_us").set(self.last_step_us);
    }
}

thread_local! {
    static HOST: RefCell<Host> = RefCell::new(Host::new());
}

fn with<T>(f: impl FnOnce(&mut Host) -> Result<T>) -> Result<T> {
    HOST.with(|h| f(&mut h.borrow_mut()))
}

// --- Argument helpers -----------------------------------------------------------

fn num(v: &ByondValue) -> Result<f32> {
    Ok(v.get_number()?)
}

fn int(v: &ByondValue, what: &str) -> Result<u32> {
    let n = num(v)?;
    if !(n >= 0.0 && n.fract() == 0.0 && n <= 16_777_216.0) {
        bail!("{what} must be a whole number in 0..2^24, got {n}");
    }
    #[allow(clippy::cast_possible_truncation, clippy::cast_sign_loss)]
    Ok(n as u32)
}

fn subscriber(v: &ByondValue) -> Result<Subscriber> {
    let s = int(v, "subscriber")?;
    if s == 0 || s > MAX_SUBSCRIBER {
        bail!("bad subscriber {s}");
    }
    Ok(s)
}

fn lane(v: &ByondValue) -> Result<Lane> {
    let id = int(v, "lane")?;
    Lane::from_id(u8::try_from(id)?).ok_or_else(|| eyre!("bad lane {id}"))
}

fn cmp(v: &ByondValue) -> Result<Cmp> {
    match int(v, "cmp")? {
        0 => Ok(Cmp::Above),
        1 => Ok(Cmp::Below),
        c => bail!("bad comparison {c} (0 above, 1 below)"),
    }
}

/// Key kind (< 256) and id (< 2^24) as one reactor key.
fn key(kind: &ByondValue, id: &ByondValue) -> Result<u64> {
    let kind = int(kind, "key kind")?;
    if kind == 0 || kind > 255 {
        bail!("key kind must be 1..255, got {kind}");
    }
    let id = int(id, "key id")?;
    if id > 0x00FF_FFFF {
        bail!("key id must be below 2^24, got {id}");
    }
    Ok(u64::from(kind) << 24 | u64::from(id))
}

fn unwatch(probe: &mut ProbeDomain, domain: u32, port: u8, id: WatchId) {
    if domain == DOMAIN_PROBE {
        let _ = probe.port.unwatch(id);
    } else {
        external(domain, |d| d.unwatch(port, id));
    }
}

fn channel(chans: &[ChannelInfo], v: &ByondValue) -> Result<ChannelId> {
    let ch = int(v, "channel")?;
    if ch as usize >= chans.len() {
        bail!("bad channel {ch}");
    }
    Ok(ChannelId(u8::try_from(ch)?))
}

fn quantity(chans: &[ChannelInfo], ch: ChannelId, value: f32) -> Quantity {
    Quantity::new(value, chans[ch.index()].unit)
}

fn hysteresis(v: &ByondValue) -> Result<Option<f32>> {
    let h = num(v)?;
    Ok((h >= 0.0).then_some(h))
}

fn level(
    domain: &ByondValue,
    ch: &ByondValue,
    cmp_v: &ByondValue,
    value: &ByondValue,
    h: &ByondValue,
    both: bool,
) -> Result<Level> {
    let chans = channel_table(int(domain, "domain")?)?;
    let ch = channel(&chans, ch)?;
    Ok(Level {
        ch,
        cmp: cmp(cmp_v)?,
        limit: quantity(&chans, ch, num(value)?),
        hysteresis: hysteresis(h)?,
        edge: if both { Edge::Both } else { Edge::Enter },
    })
}

fn truthy(v: &ByondValue) -> bool {
    v.get_number().is_ok_and(|n| n != 0.0)
}

fn watch(
    domain: &ByondValue,
    sub: &ByondValue,
    lane_v: &ByondValue,
    cond: &Cond,
) -> Result<ByondValue> {
    let domain = int(domain, "domain")?;
    let sub = subscriber(sub)?;
    let lane = lane(lane_v)?;
    // External domains register outside the host borrow (they keep their own
    // ports and never call back into the reactor).
    let external_id = if domain == DOMAIN_PROBE {
        None
    } else {
        Some(
            external(domain, |d| d.watch(sub, lane, cond))
                .ok_or_else(|| eyre!("domain {domain} has no watch port"))??,
        )
    };
    with(|h| {
        let (port, id) = match external_id {
            Some(pid) => pid,
            None => (
                0,
                h.probe
                    .port
                    .watch(sub, lane, cond)
                    .map_err(|e| eyre!("{e:?}"))?,
            ),
        };
        let index = h.tokens.add(sub, Sub::Watch { domain, port, id })?;
        Ok(ByondValue::from(h.tokens.token(index)))
    })
}

fn yes(b: bool) -> ByondValue {
    ByondValue::from(if b { 1.0f32 } else { 0.0 })
}

fn list(values: &[f32]) -> Result<ByondValue> {
    let items: Vec<ByondValue> = values.iter().map(|&v| ByondValue::from(v)).collect();
    let list = ByondValue::new_list()?;
    list.write_list(&items)?;
    Ok(list)
}

// --- Binds ---------------------------------------------------------------------

/// SSreactor's one call per tick. Advances to tick `now` (firing timers and
/// rate crossings, dispatching key publications), evaluates the domain
/// watches, and returns up to `budget` normal/background wakes (urgent ones
/// always) as a flat list, `REACT_WAKE_STRIDE` numbers per wake:
/// `subscriber, lane, reason, source, source_kind`. `source` is the cell of a
/// watch wake, the key id of a key wake (with `source_kind` its key kind), or
/// the model of a rate wake.
#[auxmacros::bind("/proc/react_step")]
fn react_step(now: ByondValue, budget: ByondValue) -> Result<ByondValue> {
    let now = num(&now)?;
    // Deliberately `!(now >= 0.0)`: this must also reject a NaN `now` from DM,
    // which `now < 0.0` would not catch.
    #[allow(clippy::neg_cmp_op_on_partial_ord)]
    if !(now >= 0.0) {
        bail!("bad tick {now}");
    }
    #[allow(clippy::cast_possible_truncation, clippy::cast_sign_loss)]
    let now = now as Tick;
    let budget = int(&budget, "budget")? as usize;
    let flat = with(|h| Ok(h.step(now, budget)))?;
    list(&flat)
}

/// `REACT_AT`: wakes `subscriber` on `lane` at tick `tick` (a past tick fires
/// at the next step). Returns the token.
#[auxmacros::bind("/proc/react_at")]
fn react_at(sub: ByondValue, lane_v: ByondValue, tick: ByondValue) -> Result<ByondValue> {
    let sub = subscriber(&sub)?;
    let lane = lane(&lane_v)?;
    let t = num(&tick)?;
    if !t.is_finite() {
        bail!("bad tick {t}");
    }
    #[allow(clippy::cast_possible_truncation, clippy::cast_sign_loss)]
    let t = t.max(0.0).ceil() as Tick;
    with(|h| {
        // Reserve the token first so the timer carries it.
        let index = h.tokens.add(
            sub,
            Sub::Timer(TimerId {
                index: 0,
                generation: 0,
            }),
        )?;
        let id = h.reactor.at(sub, lane, t, index);
        h.tokens.slots[index as usize].live = Some((sub, Sub::Timer(id)));
        Ok(ByondValue::from(h.tokens.token(index)))
    })
}

/// `REACT_ON_KEY`: wakes `subscriber` when key (`kind`, `id`) is published
/// with any bit of `mask`. Returns the token.
#[auxmacros::bind("/proc/react_on_key")]
fn react_on_key(
    sub: ByondValue,
    kind: ByondValue,
    id: ByondValue,
    mask: ByondValue,
    lane_v: ByondValue,
) -> Result<ByondValue> {
    let sub = subscriber(&sub)?;
    let key = key(&kind, &id)?;
    let mask = int(&mask, "mask")? & REASON_DETAIL;
    if mask == 0 {
        bail!("key mask must be non-zero (below REACT_REASON_CONDITION)");
    }
    let lane = lane(&lane_v)?;
    with(|h| {
        h.reactor.subscribe_key(sub, key, mask, lane);
        let index = h.tokens.add(sub, Sub::Key(key))?;
        Ok(ByondValue::from(h.tokens.token(index)))
    })
}

/// `REACT_PUBLISH`: DM-owned state under key (`kind`, `id`) changed. Merged
/// per tick; a key nobody subscribes to costs a lookup and is not stored.
#[auxmacros::bind("/proc/react_publish")]
fn react_publish(kind: ByondValue, id: ByondValue, mask: ByondValue) -> Result<ByondValue> {
    let key = key(&kind, &id)?;
    let mask = int(&mask, "mask")? & REASON_DETAIL;
    with(|h| {
        h.reactor.publish(key, mask);
        Ok(ByondValue::null())
    })
}

/// `REACT_CANCEL`: drops one subscription. Returns 1 if the token was live.
#[auxmacros::bind("/proc/react_cancel")]
fn react_cancel(token: ByondValue) -> Result<ByondValue> {
    let token = num(&token)?;
    with(|h| {
        let Some((index, _, what)) = h.tokens.get(token) else {
            return Ok(yes(false));
        };
        h.cancel(index, what);
        Ok(yes(true))
    })
}

/// `REACT_CLEAR`: drops every subscription and pending wake of `subscriber`.
/// Returns how many subscriptions it had.
#[auxmacros::bind("/proc/react_clear")]
fn react_clear(sub: ByondValue) -> Result<ByondValue> {
    let sub = subscriber(&sub)?;
    #[allow(clippy::cast_precision_loss)]
    with(|h| Ok(ByondValue::from(h.clear(sub) as f32)))
}

/// Live subscriptions of `subscriber` (tests and the audit).
#[auxmacros::bind("/proc/react_subscriptions")]
fn react_subscriptions(sub: ByondValue) -> Result<ByondValue> {
    let sub = subscriber(&sub)?;
    #[allow(clippy::cast_precision_loss)]
    with(|h| {
        Ok(ByondValue::from(
            h.tokens.by_sub.get(&sub).map_or(0, Vec::len) as f32,
        ))
    })
}

/// Reactor counters as a flat list: timers pending, timers fired, rate
/// crossings fired, key publications, rate models, keys with subscribers,
/// live subscriptions, wakes received, merged, delivered, deferred, watch
/// wakes, backlog urgent/normal/background, last step microseconds.
#[auxmacros::bind("/proc/react_stats")]
fn react_stats() -> Result<ByondValue> {
    #[allow(clippy::cast_precision_loss)]
    let v = with(|h| {
        let r = h.reactor.metrics();
        let l = h.reactor.lanes();
        let b = l.backlog();
        Ok(vec![
            r.timers_pending as f32,
            r.timers_fired as f32,
            r.crossings_fired as f32,
            r.publications as f32,
            r.models as f32,
            h.reactor.keys() as f32,
            h.tokens.live() as f32,
            l.received as f32,
            l.merged as f32,
            l.delivered as f32,
            l.deferred as f32,
            h.watch_wakes as f32,
            b[0] as f32,
            b[1] as f32,
            b[2] as f32,
            h.last_step_us as f32,
        ])
    })?;
    list(&v)
}

// --- Watches -------------------------------------------------------------------

/// `REACT_ON`: wakes when any channel in `mask` of `cell` moves past its
/// hysteresis. Returns the token.
#[auxmacros::bind("/proc/react_watch_changed")]
fn react_watch_changed(
    domain: ByondValue,
    sub: ByondValue,
    lane: ByondValue,
    cell: ByondValue,
    mask: ByondValue,
) -> Result<ByondValue> {
    let cond = Cond::Changed {
        cell: int(&cell, "cell")?,
        mask: int(&mask, "mask")?,
    };
    watch(&domain, &sub, &lane, &cond)
}

/// `REACT_WHEN` threshold: `cmp` 0 above / 1 below `value` on channel `ch`;
/// `hysteresis` < 0 takes the channel's; `both_edges` also wakes on leaving.
#[auxmacros::bind("/proc/react_watch_threshold")]
// One Rust parameter per DM call argument -- bundling these into a struct
// would require the generated DM binding (owned by the rewrite/bindings
// branch, not touched here) to change its call convention too. See the
// file-level `#![allow(clippy::too_many_arguments)]` above: an item-level
// #[allow] here doesn't reach the function clippy actually flags, because
// it's generated inside `::byondapi::bind`'s own expansion (a macro this
// audit doesn't touch) and doesn't inherit this fn's outer attributes.
fn react_watch_threshold(
    domain: ByondValue,
    sub: ByondValue,
    lane: ByondValue,
    cell: ByondValue,
    ch: ByondValue,
    cmp: ByondValue,
    value: ByondValue,
    hysteresis: ByondValue,
    both_edges: ByondValue,
) -> Result<ByondValue> {
    let cond = Cond::Threshold {
        cell: int(&cell, "cell")?,
        level: level(&domain, &ch, &cmp, &value, &hysteresis, truthy(&both_edges))?,
    };
    watch(&domain, &sub, &lane, &cond)
}

/// `REACT_WHEN` band: wakes when `cell`'s channel `ch` moves into a
/// different band of the increasing `levels` list (and once at registration).
#[auxmacros::bind("/proc/react_watch_band")]
fn react_watch_band(
    domain: ByondValue,
    sub: ByondValue,
    lane: ByondValue,
    cell: ByondValue,
    ch: ByondValue,
    levels: ByondValue,
    hysteresis: ByondValue,
) -> Result<ByondValue> {
    let chans = channel_table(int(&domain, "domain")?)?;
    let ch_id = channel(&chans, &ch)?;
    let levels = levels
        .get_list_values()?
        .iter()
        .map(|v| Ok(v.get_number()?))
        .collect::<Result<Vec<f32>>>()?;
    let cond = Cond::Band {
        cell: int(&cell, "cell")?,
        ch: ch_id,
        unit: chans[ch_id.index()].unit,
        levels,
        hysteresis: self::hysteresis(&hysteresis)?,
    };
    watch(&domain, &sub, &lane, &cond)
}

/// `REACT_WHEN` difference: `a - b` (or `|a - b|` with `abs`) on channel
/// `ch` crosses `value` like a threshold.
#[auxmacros::bind("/proc/react_watch_difference")]
// See react_watch_threshold above: one Rust parameter per DM call
// argument, so this can't be bundled without a binding-generator change,
// and (also as above) needs the file-level allow, not an item-level one.
fn react_watch_difference(
    domain: ByondValue,
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
    let cond = Cond::Difference {
        a: int(&a, "cell a")?,
        b: int(&b, "cell b")?,
        level: level(&domain, &ch, &cmp, &value, &hysteresis, false)?,
        abs: truthy(&abs),
    };
    watch(&domain, &sub, &lane, &cond)
}

/// Writes one probe cell (the probe domain is DM-written; see module docs).
#[auxmacros::bind("/proc/react_probe_set")]
fn react_probe_set(cell: ByondValue, kpa: ByondValue, kelvin: ByondValue) -> Result<ByondValue> {
    let cell = int(&cell, "cell")?;
    let v = ProbeCell {
        kpa: num(&kpa)?,
        kelvin: num(&kelvin)?,
    };
    with(|h| {
        if !h.probe.store.set(cell, v) {
            bail!("probe cell {cell} out of range");
        }
        Ok(ByondValue::null())
    })
}

// --- Rate models ---------------------------------------------------------------

fn add_model(model: RateModel) -> Result<ByondValue> {
    with(|h| {
        let id = h.reactor.add_model(model);
        h.track_model(id);
        Ok(ByondValue::from(model_value(id)))
    })
}

#[allow(clippy::cast_precision_loss)]
fn now_f(h: &Host) -> f64 {
    h.reactor.now() as f64
}

fn bound(v: &ByondValue, default: f64) -> f64 {
    v.get_number().map_or(default, f64::from)
}

/// A linear model starting at `v0` now, changing by `rate` per tick,
/// clamped to [`min`, `max`] (null for unbounded). Returns the model id.
#[auxmacros::bind("/proc/rate_linear")]
fn rate_linear(
    v0: ByondValue,
    rate: ByondValue,
    min: ByondValue,
    max: ByondValue,
) -> Result<ByondValue> {
    let t0 = with(|h| Ok(now_f(h)))?;
    add_model(RateModel::Linear {
        v0: f64::from(num(&v0)?),
        rate: f64::from(num(&rate)?),
        t0,
        min: bound(&min, f64::NEG_INFINITY),
        max: bound(&max, f64::INFINITY),
    })
}

/// A model relaxing from `v0` toward `target` at `k` per tick
/// (`target + (v0 - target) e^(-k t)`). Returns the model id.
#[auxmacros::bind("/proc/rate_relax")]
fn rate_relax(v0: ByondValue, target: ByondValue, k: ByondValue) -> Result<ByondValue> {
    let k = f64::from(num(&k)?);
    // Deliberately `!(k > 0.0)`: this must also reject a NaN `k`, which
    // `k <= 0.0` would not catch.
    #[allow(clippy::neg_cmp_op_on_partial_ord)]
    if !(k > 0.0) {
        bail!("relax rate must be positive");
    }
    let t0 = with(|h| Ok(now_f(h)))?;
    add_model(RateModel::Relax {
        target: f64::from(num(&target)?),
        v0: f64::from(num(&v0)?),
        k,
        t0,
    })
}

/// A store with named inflow/outflow terms (`vg_rate_set_term`), clamped.
#[auxmacros::bind("/proc/rate_sum")]
fn rate_sum(v0: ByondValue, min: ByondValue, max: ByondValue) -> Result<ByondValue> {
    let t0 = with(|h| Ok(now_f(h)))?;
    add_model(RateModel::Sum {
        v0: f64::from(num(&v0)?),
        t0,
        terms: Vec::new(),
        min: bound(&min, f64::NEG_INFINITY),
        max: bound(&max, f64::INFINITY),
    })
}

fn update(
    model: &ByondValue,
    change: impl FnOnce(&mut RateModel) -> Result<()>,
) -> Result<ByondValue> {
    let v = num(model)?;
    with(|h| {
        let id = model_id(h, v)?;
        let mut result = Ok(());
        if !h.reactor.update_model(id, |m| result = change(m)) {
            bail!("stale rate model {v}");
        }
        result?;
        Ok(ByondValue::null())
    })
}

/// Sets a linear or sum model's value now (the rate continues from it).
#[auxmacros::bind("/proc/rate_set")]
fn rate_set(model: ByondValue, value: ByondValue) -> Result<ByondValue> {
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
#[auxmacros::bind("/proc/rate_set_rate")]
fn rate_set_rate(model: ByondValue, rate: ByondValue) -> Result<ByondValue> {
    let r = f64::from(num(&rate)?);
    update(&model, |m| {
        match m {
            RateModel::Linear { rate, .. } => *rate = r,
            RateModel::Relax { target, .. } => *target = r,
            RateModel::Sum { .. } => bail!("a sum model's rate is its terms; use vg_rate_set_term"),
        }
        Ok(())
    })
}

/// Sets (or, with rate 0, removes) term `term` of a sum model.
#[auxmacros::bind("/proc/rate_set_term")]
fn rate_set_term(model: ByondValue, term: ByondValue, rate: ByondValue) -> Result<ByondValue> {
    let term = int(&term, "term")?;
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
#[auxmacros::bind("/proc/rate_read")]
fn rate_read(model: ByondValue) -> Result<ByondValue> {
    let v = num(&model)?;
    with(|h| {
        let id = model_id(h, v)?;
        #[allow(clippy::cast_possible_truncation)]
        let value = h
            .reactor
            .read(id)
            .ok_or_else(|| eyre!("stale rate model {v}"))? as f32;
        Ok(ByondValue::from(value))
    })
}

/// Wakes `subscriber` whenever the model enters `cmp level` (0 above: `v >=
/// level`, 1 below), at the exact predicted crossing tick; at once if it
/// already holds. Returns the token.
#[auxmacros::bind("/proc/rate_watch")]
fn rate_watch(
    model: ByondValue,
    sub: ByondValue,
    lane_v: ByondValue,
    cmp_v: ByondValue,
    level: ByondValue,
) -> Result<ByondValue> {
    let v = num(&model)?;
    let sub = subscriber(&sub)?;
    let lane = lane(&lane_v)?;
    let cmp = cmp(&cmp_v)?;
    let level = f64::from(num(&level)?);
    with(|h| {
        let id = model_id(h, v)?;
        let token = h
            .reactor
            .watch_model(id, sub, lane, cmp, level)
            .ok_or_else(|| eyre!("stale rate model {v} or bad level"))?;
        let index = h.tokens.add(sub, Sub::Rate { model: id, token })?;
        Ok(ByondValue::from(h.tokens.token(index)))
    })
}

/// Removes a model and its watches. Returns 1 if it was live.
#[auxmacros::bind("/proc/rate_remove")]
fn rate_remove(model: ByondValue) -> Result<ByondValue> {
    let v = num(&model)?;
    with(|h| {
        let Ok(id) = model_id(h, v) else {
            return Ok(yes(false));
        };
        // Release the DM tokens of its watches.
        let stale: Vec<u32> = h
            .tokens
            .slots
            .iter()
            .enumerate()
            .filter(|(_, s)| matches!(s.live, Some((_, Sub::Rate { model, .. })) if model == id))
            .map(|(i, _)| u32::try_from(i).unwrap_or(u32::MAX))
            .collect();
        for i in stale {
            h.tokens.release(i);
        }
        let live = h.reactor.remove_model(id);
        if live {
            h.model_generations[id.index as usize] = id.generation.wrapping_add(1);
        }
        Ok(yes(live))
    })
}
