//! Sensing (`doc/rewrite/proposals`, S5): DM reacts to a Rust-owned value crossing bands, and hears only the crossing, never the value.
//!
//! One `ThresholdSet` watch per `(code, cell, channel)` is the shared object. A subscriber (one DM key, a holder's declared `sensed()` entry)
//! registers its increasing `levels` on it as one `Above` entry per level, both edges; the subscriber's band is the number of its entries
//! the value is over. The set is refcounted: the first registration makes the watch, the last removal drops it.
//!
//! * **Registration is a batch** (`vg_sense_commit`): DM queues add, remove and forget commands and sends them once per frame. Re-registering
//!   a key on a set replaces its levels (a player edited a limit).
//! * **Each registration carries the band DM observed.** The entries it implies (the first `band` levels) start on the inside and the rest on
//!   the outside, so the first evaluation fires exactly for those the value disagrees with and the subscriber is told the band it is in. A
//!   change between DM's read and the arming is therefore never lost, in either direction.
//! * **Delivery is coalesced per subscriber.** All crossings of a key's entries in a frame fold into one `REC_SENSED` record `(key, band,
//!   previous band)`, and only when the band moved from the one DM last holds.
//! * **The sets' own wakes never reach DM**: the watches belong to [`SENSE_HUB`], whose wakes the scheduler drops, and their crossings are
//!   claimed by payload flag before the heat ledger sees them.

use std::cell::RefCell;
use std::collections::HashMap;

use byondapi::prelude::*;
use crate::held::HeldRead;
use eyre::{Result, bail, eyre};
use vg_core::channel::Quantity;
use vg_core::outbox::{Lane, MAX_SUBSCRIBER, Subscriber, WatchId};
use vg_core::registry::world_kind_domain;
use vg_core::watch::{Cmp, Cond, Edge, SetEntry};
use vg_core::world::ThresholdCrossing;

use crate::registry;
use crate::sched::{channels, hub_unwatch};
use crate::world::num;

/// The subscriber every sense set is registered under. Its wakes are dropped before they reach the scheduler's lanes.
pub(crate) const SENSE_HUB: Subscriber = MAX_SUBSCRIBER;

/// Set on the payload of every sense entry; the heat ledger's payloads never carry it, so a crossing is claimed by this bit alone.
const PAYLOAD_FLAG: u32 = 1 << 31;
/// Levels one registration may carry (the payload's low bits index them).
pub const MAX_LEVELS: usize = 24;
const LEVEL_BITS: u32 = 5;

/// Command ops of `vg_sense_commit`.
const OP_ADD: u32 = 1;
const OP_REMOVE: u32 = 2;
const OP_FORGET: u32 = 3;

/// Numbers before the levels of an ADD command: `op, code, cell, channel, key, observed band, strict mask, hysteresis (negative: the channel's), level count`.
const ADD_HEADER: usize = 9;

type SetKey = (u32, u32, u32);

struct SetState {
    port: u8,
    id: WatchId,
    /// Registrations on the set.
    regs: Vec<u32>,
}

struct Reg {
    set: SetKey,
    key: u32,
    levels: usize,
    /// Bit `i`: entry `i` has reported itself entered and not yet left.
    held: u32,
    /// The band DM holds for the key.
    reported: u32,
}

/// One band change for DM.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Sensed {
    pub key: u32,
    pub band: u32,
    pub was: u32,
}

#[derive(Default)]
struct Table {
    sets: HashMap<SetKey, SetState>,
    regs: HashMap<u32, Reg>,
    by_key: HashMap<u32, Vec<u32>>,
    next_reg: u32,
    /// Registrations whose band moved this frame (each once).
    touched: Vec<u32>,
    out: Vec<Sensed>,
}

thread_local! {
    static TABLE: RefCell<Table> = RefCell::new(Table::default());
}

fn with_table<T>(f: impl FnOnce(&mut Table) -> T) -> T {
    TABLE.with_borrow_mut(f)
}

fn payload(reg: u32, level: usize) -> u32 {
    #[allow(clippy::cast_possible_truncation)]
    {
        PAYLOAD_FLAG | (reg << LEVEL_BITS) | level as u32
    }
}

fn counter(name: &str, n: u64) {
    crate::metrics::registry().counter(name).add(n);
}

/// A sense registration as DM sends it.
#[derive(Clone, Debug, PartialEq)]
pub struct Add {
    pub code: u32,
    pub cell: u32,
    pub ch: u32,
    pub key: u32,
    pub observed: u32,
    /// Bit `i`: level `i` counts only once the value is past it.
    pub strict: u32,
    /// The distance back past a level the value must travel to leave it (`None`: the channel's own).
    pub hysteresis: Option<f32>,
    pub levels: Vec<f32>,
}

/// Registers `add`, replacing the levels its key already has on the set.
///
/// # Errors
/// If the channel, cell or levels are refused by the domain's watch port.
pub fn add(a: &Add) -> Result<()> {
    if a.levels.is_empty() || a.levels.len() > MAX_LEVELS {
        bail!("sense: {} levels (1 to {MAX_LEVELS})", a.levels.len());
    }
    // Increasing, but a level may stand twice when the first counts at the value and the second only past it: a value on the level is in the
    // band between the two.
    let strict_at = |i: usize| a.strict & (1 << i) != 0;
    if a
        .levels
        .windows(2)
        .enumerate()
        .any(|(i, w)| w[0] > w[1] || (w[0] == w[1] && !(!strict_at(i) && strict_at(i + 1))))
    {
        bail!("sense: levels must increase (a level may repeat once, plain then strict)");
    }
    remove(a.code, a.cell, a.ch, a.key);
    let chans = channels(a.code)?;
    let info = chans
        .get(a.ch as usize)
        .ok_or_else(|| eyre!("sense: bad channel {}", a.ch))?;
    let unit = info.unit;
    let set_key = (a.code, a.cell, a.ch);
    let have = with_table(|t| t.sets.contains_key(&set_key));
    if !have {
        let cond = Cond::ThresholdSet {
            cell: a.cell,
            ch: vg_core::channel::ChannelId(u8::try_from(a.ch)?),
        };
        let (port, id) =
            registry::with_domain(world_kind_domain(a.code), |d| d.watch(SENSE_HUB, Lane::Normal, &cond))
                .ok_or_else(|| eyre!("sense: code {} has no watch port", a.code))?
                .map_err(|e| eyre!("{e}"))?;
        with_table(|t| {
            t.sets.insert(set_key, SetState { port, id, regs: Vec::new() });
        });
        counter("sense.sets_made", 1);
    }
    let (port, id, reg) = with_table(|t| {
        t.next_reg += 1;
        let reg = t.next_reg;
        let s = t.sets.get_mut(&set_key).expect("just made");
        s.regs.push(reg);
        (s.port, s.id, reg)
    });
    for (i, &level) in a.levels.iter().enumerate() {
        let cmp = if a.strict & (1 << i) != 0 { Cmp::AboveStrict } else { Cmp::Above };
        let entry = SetEntry {
            payload: payload(reg, i),
            generation: 1,
            cmp,
            limit: Quantity::new(level, unit),
            hysteresis: a.hysteresis,
            edge: Edge::Both,
            start: (i < a.observed as usize).then_some(true),
        };
        let done = registry::with_domain(world_kind_domain(a.code), |d| d.add_entry(port, id, entry))
            .ok_or_else(|| eyre!("sense: code {} has no watch port", a.code))?;
        if let Err(e) = done {
            with_table(|t| drop_reg(t, reg));
            return Err(eyre!("sense: {e}"));
        }
    }
    with_table(|t| {
        t.regs.insert(
            reg,
            Reg { set: set_key, key: a.key, levels: a.levels.len(), held: observed_bits(a.observed, a.levels.len()), reported: a.observed },
        );
        t.by_key.entry(a.key).or_default().push(reg);
    });
    counter("sense.registrations", 1);
    Ok(())
}

/// The entries DM's observed band says are held: the first `band` of `levels`.
fn observed_bits(band: u32, levels: usize) -> u32 {
    let held = (band as usize).min(levels);
    if held >= 32 { u32::MAX } else { (1_u32 << held) - 1 }
}

/// Takes registration `reg` off its set and the tables, dropping the set when it was the last.
fn drop_reg(t: &mut Table, reg: u32) {
    let Some(r) = t.regs.remove(&reg) else {
        // Never inserted (an entry was refused): still on its set's list.
        for s in t.sets.values_mut() {
            s.regs.retain(|&x| x != reg);
        }
        return;
    };
    if let Some(keys) = t.by_key.get_mut(&r.key) {
        keys.retain(|&x| x != reg);
        if keys.is_empty() {
            t.by_key.remove(&r.key);
        }
    }
    t.touched.retain(|&x| x != reg);
    let code = r.set.0;
    let mut gone = None;
    if let Some(s) = t.sets.get_mut(&r.set) {
        for i in 0..r.levels {
            let p = payload(reg, i);
            let (port, id) = (s.port, s.id);
            registry::with_domain(world_kind_domain(code), |d| d.remove_entry(port, id, p));
        }
        s.regs.retain(|&x| x != reg);
        if s.regs.is_empty() {
            gone = Some((s.port, s.id));
        }
    }
    if let Some((port, id)) = gone {
        t.sets.remove(&r.set);
        hub_unwatch(code, port, id);
        counter("sense.sets_dropped", 1);
    }
}

/// Removes `key`'s registration on `(code, cell, ch)`.
pub fn remove(code: u32, cell: u32, ch: u32, key: u32) {
    with_table(|t| {
        let found: Vec<u32> = t
            .by_key
            .get(&key)
            .map(|regs| {
                regs.iter()
                    .copied()
                    .filter(|r| t.regs.get(r).is_some_and(|x| x.set == (code, cell, ch)))
                    .collect()
            })
            .unwrap_or_default();
        for reg in found {
            drop_reg(t, reg);
        }
    });
}

/// Removes every registration of `key` (its holder is gone).
pub fn forget(key: u32) {
    with_table(|t| {
        let regs = t.by_key.get(&key).cloned().unwrap_or_default();
        for reg in regs {
            drop_reg(t, reg);
        }
    });
}

/// Takes the crossings that belong to sense sets out of `all`, folds them into bands and returns the rest. Called once per frame with the
/// world's set crossings.
pub fn claim(all: Vec<ThresholdCrossing>) -> Vec<ThresholdCrossing> {
    let mut all = all;
    all.extend(crate::gas::mix::take_crossings());
    if all.is_empty() {
        return all;
    }
    let mut rest = Vec::with_capacity(all.len());
    let mut mine = 0_u64;
    with_table(|t| {
        for c in all {
            if c.payload & PAYLOAD_FLAG == 0 {
                rest.push(c);
                continue;
            }
            mine += 1;
            let reg = (c.payload & !PAYLOAD_FLAG) >> LEVEL_BITS;
            let level = c.payload & ((1 << LEVEL_BITS) - 1);
            let Some(r) = t.regs.get_mut(&reg) else {
                continue;
            };
            if c.entered {
                r.held |= 1 << level;
            } else {
                r.held &= !(1 << level);
            }
            if !t.touched.contains(&reg) {
                t.touched.push(reg);
            }
        }
        let touched = std::mem::take(&mut t.touched);
        for reg in touched {
            let Some(r) = t.regs.get_mut(&reg) else {
                continue;
            };
            let band = r.held.count_ones();
            if band != r.reported {
                let was = r.reported;
                r.reported = band;
                t.out.push(Sensed { key: r.key, band, was });
            }
        }
    });
    counter("sense.crossings_claimed", mine);
    rest
}

/// The band changes found since the last call, one per key and registration.
pub fn take_sensed() -> Vec<Sensed> {
    let out = with_table(|t| std::mem::take(&mut t.out));
    counter("sense.records_out", out.len() as u64);
    out
}

/// Live sets and registrations (tests and the audit).
pub fn live() -> (usize, usize) {
    with_table(|t| (t.sets.len(), t.regs.len()))
}

/// Forgets everything (the world was rebuilt: its watch ports went with it).
pub(crate) fn reset() {
    with_table(|t| *t = Table::default());
}

/// Whether `payload` belongs to a sense entry.
#[must_use]
pub fn is_sense_payload(payload: u32) -> bool {
    payload & PAYLOAD_FLAG != 0
}

// --- Binds ---------------------------------------------------------------------

/// Applies a batch of commands, flat: `ADD: 1, code, cell, channel, key, observed band, strict mask, hysteresis, n, level * n`;
/// `REMOVE: 2, code, cell, channel, key`; `FORGET: 3, key`. Returns the keys whose ADD was refused (the reasons: `vg_sense_refused`).
#[auxmacros::bind("/proc/sense_commit")]
fn sense_commit(commands: ByondValue) -> Result<ByondValue> {
    let v = commands
        .held_list()?
        .iter()
        .map(num)
        .collect::<Result<Vec<f32>>>()?;
    let mut refused: Vec<f32> = Vec::new();
    let mut reasons = String::new();
    let mut at = 0;
    let mut commands_n = 0_u64;
    let n = |i: usize| -> Result<u32> {
        let x = *v.get(i).ok_or_else(|| eyre!("sense_commit: truncated batch"))?;
        if !(x >= 0.0 && x.fract() == 0.0 && x < 16_777_216.0) {
            bail!("sense_commit: bad number {x}");
        }
        #[allow(clippy::cast_possible_truncation, clippy::cast_sign_loss)]
        Ok(x as u32)
    };
    while at < v.len() {
        commands_n += 1;
        match n(at)? {
            OP_ADD => {
                let count = n(at + 8)? as usize;
                if at + ADD_HEADER + count > v.len() {
                    bail!("sense_commit: truncated ADD");
                }
                let a = Add {
                    code: n(at + 1)?,
                    cell: n(at + 2)?,
                    ch: n(at + 3)?,
                    key: n(at + 4)?,
                    observed: n(at + 5)?,
                    strict: n(at + 6)?,
                    hysteresis: v.get(at + 7).copied().filter(|h| *h >= 0.0),
                    levels: v[at + ADD_HEADER..at + ADD_HEADER + count].to_vec(),
                };
                if let Err(e) = add(&a) {
                    refused.push(a.key as f32);
                    reasons.push_str(&format!("{}: {e}; ", a.key));
                }
                at += ADD_HEADER + count;
            }
            OP_REMOVE => {
                remove(n(at + 1)?, n(at + 2)?, n(at + 3)?, n(at + 4)?);
                at += 5;
            }
            OP_FORGET => {
                forget(n(at + 1)?);
                at += 2;
            }
            op => return Err(eyre!("sense_commit: unknown op {op}")),
        }
    }
    counter("sense.commits", 1);
    counter("sense.commands", commands_n);
    if !reasons.is_empty() {
        LAST_REFUSED.with_borrow_mut(|r| *r = reasons);
    }
    crate::world::list(refused)
}

thread_local! {
    /// Why the last refused commands were refused (`vg_sense_refused`), for DM to log.
    static LAST_REFUSED: RefCell<String> = const { RefCell::new(String::new()) };
}

/// The reasons commands were refused since the last call (`key: reason; ...`), empty when none were.
#[auxmacros::bind("/proc/sense_refused")]
fn sense_refused() -> Result<ByondValue> {
    Ok(ByondValue::new_str(LAST_REFUSED.with_borrow_mut(std::mem::take))?)
}

/// `list(live sets, live registrations)`.
#[auxmacros::bind("/proc/sense_live")]
fn sense_live() -> Result<ByondValue> {
    let (sets, regs) = live();
    #[allow(clippy::cast_precision_loss)]
    crate::world::list([sets as f32, regs as f32])
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::frame::{REC_SENSED, run};
    use crate::gas::mix::{self, MixRef};
    use crate::sched::GAS_HANDLES;
    use crate::world::with_world;
    use vg_gas::cell::gas_ch;
    use vg_gas::gas::Mixture;

    fn tank(moles: f32) -> (MixRef, Mixture) {
        with_world(|_| Ok(())).unwrap();
        reset();
        let mut m = Mixture::from_vol(70.0);
        m.set_moles(0, moles);
        m.set_temperature(293.15);
        (MixRef::Main(mix::alloc(m.clone()).unwrap()), m)
    }

    fn set_moles(r: MixRef, from: &Mixture, moles: f32) -> Mixture {
        let mut after = from.clone();
        after.set_moles(0, moles);
        mix::store(r, from, &after);
        after
    }

    fn arm(r: MixRef, key: u32, observed: u32, levels: &[f32]) {
        add(&Add {
            code: GAS_HANDLES,
            cell: r.id(),
            ch: gas_ch::PRESSURE.index() as u32,
            key,
            observed,
            strict: 0,
            hysteresis: None,
            levels: levels.to_vec(),
        })
        .unwrap();
    }

    /// The sensed records of one frame as `(key, band, was)`.
    fn frame() -> Vec<(u32, u32, u32)> {
        let page = run(0, 100).unwrap();
        let mut out = Vec::new();
        let mut at = 0;
        while at + 4 <= page.len() {
            let len = page[at + 3] as usize;
            if page[at] as u32 == REC_SENSED {
                out.push((page[at + 1] as u32, page[at + 2] as u32, page[at + 4] as u32));
            }
            at += 4 + len;
        }
        out
    }

    // 70 L at 293.15 K: 10 mol is about 348 kPa, 21 mol about 730 kPa, 2 mol about 70 kPa.
    const LEVELS: [f32; 2] = [100.0, 500.0];

    #[test]
    fn crossing_up_and_down_reports_the_band_and_nothing_inside_one() {
        let (r, t) = tank(10.0);
        arm(r, 11, 1, &LEVELS);
        assert!(frame().is_empty(), "armed on the band DM observed: nothing to say");
        let up = set_moles(r, &t, 21.0);
        assert_eq!(frame(), vec![(11, 2, 1)], "past the upper level");
        let inside = set_moles(r, &up, 20.0);
        assert!(frame().is_empty(), "a change inside a band says nothing");
        set_moles(r, &inside, 2.0);
        assert_eq!(frame(), vec![(11, 0, 2)], "straight down through both levels is one record");
    }

    #[test]
    fn a_wrong_observed_band_is_corrected_by_the_first_frame() {
        let (r, _t) = tank(10.0);
        arm(r, 12, 0, &LEVELS);
        assert_eq!(frame(), vec![(12, 1, 0)], "DM read band 0 but the value is in band 1");
        assert!(frame().is_empty(), "told once");
    }

    #[test]
    fn hysteresis_keeps_a_value_resting_on_a_level_from_chattering() {
        let (r, t) = tank(10.0);
        arm(r, 13, 1, &[348.0]);
        // 10 mol is about 348.4 kPa: on the level. A small dip stays inside the hysteresis.
        let _ = frame();
        let dip = set_moles(r, &t, 9.99);
        assert!(frame().is_empty(), "a dip of a hundredth of a kPa does not leave");
        set_moles(r, &dip, 9.0);
        assert_eq!(frame(), vec![(13, 0, 1)], "well below it does");
    }

    #[test]
    fn many_watchers_share_one_set_and_each_hears_its_own_bands() {
        let (r, t) = tank(10.0);
        arm(r, 21, 1, &LEVELS);
        arm(r, 22, 1, &[100.0, 200.0, 300.0]);
        arm(r, 23, 0, &[400.0]);
        assert_eq!(live(), (1, 3), "one set, three registrations");
        assert_eq!(frame(), vec![(22, 3, 1)], "only the watcher whose observed band was wrong is told");
        set_moles(r, &t, 21.0);
        let mut got = frame();
        got.sort_unstable();
        assert_eq!(got, vec![(21, 2, 1), (23, 1, 0)], "key 22 stays in its top band");
    }

    #[test]
    fn a_level_may_stand_twice_when_its_strictness_differs() {
        let (r, _t) = tank(10.0);
        let base = Add {
            code: GAS_HANDLES,
            cell: r.id(),
            ch: gas_ch::PRESSURE.index() as u32,
            key: 71,
            observed: 1,
            strict: 0b10,
            hysteresis: None,
            levels: vec![100.0, 100.0, 500.0],
        };
        add(&base).unwrap();
        assert_eq!(live(), (1, 1), "plain then strict at one level is kept whole");
        assert_eq!(frame(), vec![(71, 2, 1)], "348 kPa is over 100 both ways: band 2 of 3");
        let same = Add { key: 72, strict: 0, ..base.clone() };
        assert!(add(&same).is_err(), "the same level twice with the same strictness is a mistake");
        let wrong_order = Add { key: 73, strict: 0b01, ..base };
        assert!(add(&wrong_order).is_err(), "strict then plain at one level is out of order");
    }

    #[test]
    fn removing_the_last_watcher_drops_the_set() {
        let (r, _t) = tank(10.0);
        arm(r, 31, 1, &LEVELS);
        arm(r, 32, 1, &LEVELS);
        remove(GAS_HANDLES, r.id(), gas_ch::PRESSURE.index() as u32, 31);
        assert_eq!(live(), (1, 1));
        forget(32);
        assert_eq!(live(), (0, 0), "refcounted to zero");
    }

    #[test]
    fn re_registering_a_key_replaces_its_levels() {
        let (r, t) = tank(10.0);
        arm(r, 41, 1, &LEVELS);
        arm(r, 41, 1, &[600.0, 900.0]);
        assert_eq!(live(), (1, 1), "the old registration is gone, not added to");
        assert_eq!(frame(), vec![(41, 0, 1)], "348 kPa is under the new first level");
        set_moles(r, &t, 21.0);
        assert_eq!(frame(), vec![(41, 1, 0)], "730 kPa is over 600 and under 900");
    }

    #[test]
    fn a_destroyed_cell_stops_reporting() {
        let (r, t) = tank(10.0);
        arm(r, 51, 1, &LEVELS);
        let _ = frame();
        forget(51);
        set_moles(r, &t, 21.0);
        assert!(frame().is_empty(), "a forgotten key is never told");
        assert_eq!(live(), (0, 0));
    }
}
