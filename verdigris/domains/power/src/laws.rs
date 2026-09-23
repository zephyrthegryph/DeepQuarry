//! Power's laws (`rust_architecture.md` §4.3, §6): pure functions over
//! components and the region ledger. No `Sim`, no stepping-everything loop
//! -- each is a plain function a driver (or, today, a direct call from a
//! test or the FFI glue) applies once per tick. The per-`Law`-trait
//! scheduler wiring lands once Core B's component stores do; until then
//! these are the physics, proven by the tests alongside each one.

use vg_core::rate::RateModel;
use vg_core::units::Watts;

use crate::components::{Apc, Channel, Consumer, Smes};

/// A region as one law sees it: enough to plan and draw against, without
/// exposing the whole [`crate::kind::PowerLedger`]. `PowerBalance` (the
/// driver, once wired) is what actually owns advancing `load`.
pub trait Grid {
    /// This step's planned supply.
    fn avail(&self) -> Watts;
    /// `avail - load` so far.
    fn surplus(&self) -> Watts;
    /// Draws up to `watts`; returns what was delivered (never more than
    /// [`Grid::surplus`]).
    fn draw(&mut self, watts: Watts) -> Watts;
}

/// A grid with nothing on it (an unconnected APC/SMES terminal).
pub struct NoGrid;

impl Grid for NoGrid {
    fn avail(&self) -> Watts {
        Watts::ZERO
    }
    fn surplus(&self) -> Watts {
        Watts::ZERO
    }
    fn draw(&mut self, _: Watts) -> Watts {
        Watts::ZERO
    }
}

/// `POWER_BALANCE`'s per-region plan: registered [`Producer`]s and storage
/// offers, before any [`Consumer`] draws (`rust_architecture.md` §6).
#[must_use]
pub fn planned_supply(producers: impl IntoIterator<Item = Watts>, storage_offers: impl IntoIterator<Item = Watts>) -> Watts {
    let mut total = 0.0;
    for p in producers {
        total += p.get();
    }
    for s in storage_offers {
        total += s.get();
    }
    Watts(total)
}

/// One [`Consumer`]'s draw against a region this step: never more than the
/// grid's surplus. Priority order (highest first) is the caller's
/// responsibility -- draw consumers in the order they must be served, so a
/// starved region sheds the lowest-priority ones first.
pub fn consumer_draw(consumer: &Consumer, grid: &mut dyn Grid) -> Watts {
    let total: f64 = consumer.demand.iter().map(|w| w.get()).sum();
    grid.draw(Watts(total))
}

/// `ApcTick`: the channel autoset ladder and charge mode
/// (`apc_power_distributor.tick()`). Returns `(cell_discharged,
/// cell_charged)` watts this tick, for the caller's conservation books:
/// `cell_discharged` never reaches `grid` (the cell covers the area
/// directly); `cell_charged` does, through [`Grid::draw`].
pub fn apc_tick(apc: &mut Apc, demand: [Watts; 3], grid: &mut dyn Grid) -> (Watts, Watts) {
    let used = demand;
    apc.oneoff = [Watts::ZERO; 3];
    if !apc.active {
        return (Watts::ZERO, Watts::ZERO);
    }
    let total = Watts(used.iter().map(|w| w.get()).sum());
    let excess = grid.surplus();
    if apc.has_cell && !apc.shorted_or_grid_check {
        with_cell(apc, excess, total, grid)
    } else {
        apc.charging = 0;
        apc.chargecount = 0;
        for c in &mut apc.channels {
            *c = c.autoset(0);
        }
        apc.alarm = true;
        apc.autoflag = 0;
        (Watts::ZERO, Watts::ZERO)
    }
}

fn with_cell(apc: &mut Apc, excess: Watts, total: Watts, grid: &mut dyn Grid) -> (Watts, Watts) {
    let mut discharged = Watts::ZERO;
    if excess.get() >= total.get() {
        grid.draw(total);
    } else {
        let available = apc.cell.watts_available();
        discharged = Watts(apc.cell.discharge_out(total.get()));
        if available + excess.get() >= total.get() {
            let drawn = grid.draw(excess);
            apc.cell.charge = apc.cell.capacity.min(apc.cell.charge + apc.cell.rate * drawn.get());
            apc.charging = 0;
        } else {
            apc.charging = 0;
            apc.chargecount = 0;
            for c in &mut apc.channels {
                *c = c.autoset(0);
            }
            apc.autoflag = 0;
        }
    }

    update_channels(apc);

    let mut charged = Watts::ZERO;
    if apc.chargemode && apc.charging == 1 && apc.operating {
        if excess.get() > 0.0 {
            let ch = (excess.get() * apc.cell.rate).min(apc.cell.capacity * apc.chargelevel);
            let drawn = grid.draw(Watts(ch / apc.cell.rate));
            apc.cell.charge = (apc.cell.charge + drawn.get() * apc.cell.rate).min(apc.cell.capacity.max(apc.cell.charge));
            charged = drawn;
        } else {
            apc.charging = 0;
            apc.chargecount = 0;
        }
    }
    if apc.cell.charge >= apc.cell.capacity {
        apc.cell.charge = apc.cell.capacity;
        apc.charging = 2;
    }
    if apc.chargemode {
        if apc.charging == 0 {
            if excess.get() > apc.cell.capacity * apc.chargelevel {
                apc.chargecount += 1;
            } else {
                apc.chargecount = 0;
            }
            if apc.chargecount >= 10 {
                apc.chargecount = 0;
                apc.charging = 1;
            }
        }
    } else {
        apc.charging = 0;
        apc.chargecount = 0;
    }
    (discharged, charged)
}

/// `_update_channels()`: shedding tiers from the cell level and trend
/// (config policy, not hard-coded thresholds -- see [`crate::components::SheddingPolicy`]).
fn update_channels(apc: &mut Apc) {
    let policy = apc.policy;
    if apc.charging != 0 && apc.longtermpower < 10 {
        apc.longtermpower += 1;
    } else if apc.longtermpower > -10 {
        apc.longtermpower -= 2;
    }
    let pct = 100.0 * apc.cell.fraction();
    let set = |apc: &mut Apc, allow: [u8; 3]| {
        for c in Channel::ALL {
            apc.channels[c.idx()] = apc.channels[c.idx()].autoset(allow[c.idx()]);
        }
    };
    if pct > policy.full_above_pct || apc.longtermpower > 0 {
        if apc.autoflag != 3 {
            set(apc, policy.full_allow);
            apc.autoflag = 3;
            apc.alarm = false;
        }
    } else if pct <= policy.full_above_pct && pct > policy.partial_below_pct && apc.longtermpower < 0 {
        if apc.autoflag != 2 {
            set(apc, policy.partial_allow);
            apc.alarm = true;
            apc.autoflag = 2;
        }
    } else if pct <= policy.partial_below_pct {
        if apc.autoflag > 1 {
            set(apc, policy.min_allow);
            apc.alarm = true;
            apc.autoflag = 1;
        }
    } else if apc.autoflag != 0 {
        set(apc, policy.neutral_allow);
        apc.alarm = true;
        apc.autoflag = 0;
    }
}

/// SMES planning: the output offered and input requested next step, given
/// whether the unit's output/input terminals are on a region.
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct SmesPlan {
    pub offer: Watts,
    pub target_load: Watts,
}

#[must_use]
pub fn smes_plan(smes: &Smes, output_connected: bool, input_connected: bool) -> SmesPlan {
    let offer = if smes.output_enabled && output_connected && smes.charge.charge > 0.0 {
        Watts(
            (smes.charge.charge / smes.charge.rate)
                .min(smes.output_level.get())
                .max(0.0),
        )
    } else {
        Watts::ZERO
    };
    let target_load = if smes.input_enabled && input_connected {
        Watts(((smes.charge.capacity - smes.charge.charge) / smes.charge.rate).clamp(0.0, smes.input_level.get()))
    } else {
        Watts::ZERO
    };
    SmesPlan { offer, target_load }
}

/// Charges a SMES from `got` watts offered this step; returns watts
/// actually absorbed (bounded by room to capacity).
pub fn smes_charge_in(smes: &mut Smes, got: Watts) -> Watts {
    Watts(smes.charge.charge_in(got.get()))
}

/// Discharges a SMES for up to `share` watts; returns watts actually
/// delivered (bounded by stored charge).
pub fn smes_discharge_out(smes: &mut Smes, share: Watts) -> Watts {
    Watts(smes.charge.discharge_out(share.get()))
}

/// A SMES's charge trajectory if `net_rate` (watts into the store;
/// negative for a net discharge) holds steady from `now`
/// (`rust_architecture.md` §4.10): a driver builds this whenever the rate
/// changes (a new offer, a config edit), predicts the next crossing with
/// [`RateModel::crossing`] (empty at `0.0`, full at `smes.charge.capacity`),
/// and schedules the law to run again then instead of stepping it every
/// tick while nothing changes.
#[must_use]
pub fn smes_charge_model(smes: &Smes, net_rate: Watts, now: f64) -> RateModel {
    smes.charge.model(net_rate.get(), now)
}

/// As [`smes_charge_model`], for an APC's cell.
#[must_use]
pub fn apc_cell_model(apc: &Apc, net_rate: Watts, now: f64) -> RateModel {
    apc.cell.model(net_rate.get(), now)
}

/// A region browns out when it has no supply at all, or its planned
/// excess (`avail - load`) is meaningfully negative (overdrawn). The 1 W
/// slack absorbs float rounding across many small draws, not a real
/// tolerance for being overdrawn.
#[must_use]
pub fn brownout(avail: Watts, load: Watts) -> bool {
    avail.get() <= 0.0 || avail.get() - load.get() < -1.0
}

/// `PowerBalance`'s storage-input step: one SMES's pro-rata share of a
/// region's leftover supply (`excess`) out of everything storage in the
/// region asked for (`total_asks`), never more than its own `ask` or the
/// excess itself.
#[must_use]
pub fn storage_input_share(ask: Watts, total_asks: Watts, excess: Watts) -> Watts {
    if total_asks.get() <= 0.0 {
        return Watts::ZERO;
    }
    let fraction = (excess.get() / total_asks.get()).clamp(0.0, 1.0);
    Watts((ask.get() * fraction).min(excess.get().max(0.0)))
}

/// `PowerBalance`'s storage-output step (storage is the last supply
/// used): one SMES's share of `storage_used` (the region's load beyond
/// non-storage `avail`) proportional to its own offer out of every
/// storage unit's combined offer.
#[must_use]
pub fn storage_output_share(offer: Watts, total_offer: Watts, storage_used: Watts) -> Watts {
    if total_offer.get() <= 0.0 {
        return Watts::ZERO;
    }
    Watts(storage_used.get() * offer.get() / total_offer.get())
}

#[cfg(test)]
mod tests {
    use super::*;
    use proptest::prelude::*;
    use vg_core::rate::RateStore;

    use crate::components::ChannelSetting;

    struct TestGrid {
        avail: Watts,
        load: Watts,
    }
    impl Grid for TestGrid {
        fn avail(&self) -> Watts {
            self.avail
        }
        fn surplus(&self) -> Watts {
            Watts(self.avail.get() - self.load.get())
        }
        fn draw(&mut self, watts: Watts) -> Watts {
            let d = watts.get().min(self.avail.get() - self.load.get()).max(0.0);
            self.load = Watts(self.load.get() + d);
            Watts(d)
        }
    }

    fn apc_with(max_charge: f64, charge: f64) -> Apc {
        Apc {
            cell: RateStore { charge, capacity: max_charge, rate: crate::components::CELLRATE },
            ..Apc::default()
        }
    }

    #[test]
    fn a_strong_grid_carries_the_area_untouched() {
        let mut apc = apc_with(1000.0, 1000.0);
        let mut grid = TestGrid { avail: Watts(100_000.0), load: Watts::ZERO };
        let demand = [Watts(1000.0), Watts(2000.0), Watts(1000.0)];
        apc_tick(&mut apc, demand, &mut grid);
        assert_eq!(apc.cell.charge, 1000.0, "cell untouched: grid alone covers it");
        assert_eq!(grid.load, Watts(4000.0));
    }

    #[test]
    fn no_supply_drains_the_cell_by_cellrate_per_watt() {
        let mut apc = apc_with(1000.0, 1000.0);
        let mut grid = TestGrid { avail: Watts::ZERO, load: Watts::ZERO };
        let demand = [Watts(1000.0), Watts(2000.0), Watts(1000.0)];
        apc_tick(&mut apc, demand, &mut grid);
        let expect = 1000.0 - 4000.0 * crate::components::CELLRATE;
        assert!((apc.cell.charge - expect).abs() < 1e-9);
    }

    #[test]
    fn a_dead_cell_settles_with_every_channel_shed() {
        // No grid and no charge, cell can't cover any of the demand:
        // with_cell's own "can't even partly cover it" branch sheds every
        // channel and resets autoflag every tick, but longtermpower
        // starts optimistic (+10) and update_channels' full-power branch
        // (`longtermpower > 0`, independent of pct) overrides that back
        // to full for the first few ticks regardless -- the two only
        // agree once longtermpower has decayed to <= 0 (a handful of
        // ticks at -2/tick from +10), landing on update_channels' own
        // "pct in the neutral 15-30% band with longtermpower == 0"
        // fixed point once pct is 0%: every channel off, autoflag 0. That
        // asymmetry (and alarm never firing on this exact path) is the
        // ported original's real behaviour, not this port's invention.
        let mut apc = apc_with(1000.0, 0.0);
        apc.channels = [ChannelSetting::OnAuto; 3];
        let mut grid = TestGrid { avail: Watts::ZERO, load: Watts::ZERO };
        for _ in 0..10 {
            apc_tick(&mut apc, [Watts(100.0); 3], &mut grid);
        }
        assert_eq!(apc.autoflag, 0);
        assert!(apc.channels.iter().all(|c| !c.powered()), "every channel sheds once longtermpower settles");
    }

    #[test]
    fn a_slowly_draining_cell_settles_on_the_shedding_ladder_with_the_alarm_raised() {
        // No grid at all, but a nonzero cell: `available` (watts the cell
        // could give this instant) stays far above one tick's demand
        // until charge is almost exactly zero, so this exercises
        // update_channels' own longtermpower/pct ladder, not with_cell's
        // separate "can't cover any of it" branch (see the test above).
        // CELLRATE-scale draining takes ~1500 ticks to cross 30%; cheap
        // for a host-only unit test, so run it out fully rather than
        // picking a fragile mid-drain checkpoint.
        let mut apc = apc_with(1000.0, 1000.0);
        apc.channels = [ChannelSetting::OnAuto; 3];
        let mut grid = TestGrid { avail: Watts::ZERO, load: Watts::ZERO };
        for _ in 0..1500 {
            apc_tick(&mut apc, [Watts(100.0); 3], &mut grid);
            grid.load = Watts::ZERO;
        }
        assert!(apc.cell.charge > 0.0, "not yet fully depleted");
        assert!(apc.alarm);
        assert_eq!(apc.autoflag, 1, "settled at the minimum tier, not neutral or full");
        assert!(!apc.channels[Channel::Equip.idx()].powered(), "equipment sheds first");
        assert!(!apc.channels[Channel::Light.idx()].powered(), "then lighting");
        assert!(apc.channels[Channel::Environ.idx()].powered(), "environment/life support sheds last");
    }

    #[test]
    fn cell_charge_and_discharge_never_leave_zero_or_capacity() {
        let mut apc = apc_with(500.0, 250.0);
        let mut grid = TestGrid { avail: Watts(10_000.0), load: Watts::ZERO };
        for _ in 0..50 {
            apc_tick(&mut apc, [Watts(50.0); 3], &mut grid);
            grid.load = Watts::ZERO;
            assert!((0.0..=500.0).contains(&apc.cell.charge));
        }
    }

    #[test]
    fn smes_offers_output_only_when_connected_and_charged() {
        let mut smes = Smes { charge: RateStore { charge: 1e5, capacity: 1e6, rate: crate::components::SMESRATE }, ..Smes::default() };
        assert_eq!(smes_plan(&smes, false, false).offer, Watts::ZERO, "not connected");
        let plan = smes_plan(&smes, true, false);
        assert!(plan.offer.get() > 0.0);
        smes.charge.charge = 0.0;
        assert_eq!(smes_plan(&smes, true, false).offer, Watts::ZERO, "empty");
    }

    #[test]
    fn smes_input_targets_room_to_capacity_bounded_by_input_level() {
        let smes = Smes {
            input_enabled: true,
            input_level: Watts(100.0),
            charge: RateStore { charge: 0.0, capacity: 1e6, rate: crate::components::SMESRATE },
            ..Smes::default()
        };
        let plan = smes_plan(&smes, false, true);
        assert_eq!(plan.target_load, Watts(100.0), "capped by input_level despite huge room");
    }

    #[test]
    fn smes_charge_round_trips_through_rate_conversion() {
        let mut smes = Smes { charge: RateStore { charge: 0.0, capacity: 1000.0, rate: 0.5 }, ..Smes::default() };
        let absorbed = smes_charge_in(&mut smes, Watts(100.0));
        assert_eq!(absorbed, Watts(100.0));
        assert_eq!(smes.charge.charge, 50.0);
        let delivered = smes_discharge_out(&mut smes, Watts(1000.0));
        assert_eq!(delivered, Watts(100.0), "capped by what's stored, not the request");
        assert_eq!(smes.charge.charge, 0.0);
    }

    #[test]
    fn smes_charge_model_predicts_the_same_empty_time_as_manual_stepping() {
        // 1000 charge units at 0.5 rate, discharging at a steady 100 W:
        // 1000 / (0.5 * 100) = 20 ticks to empty.
        let smes = Smes { charge: RateStore { charge: 1000.0, capacity: 1000.0, rate: 0.5 }, ..Smes::default() };
        let model = smes_charge_model(&smes, Watts(-100.0), 0.0);
        let predicted = model.crossing(0.0, 0.0).expect("reaches empty");
        assert!((predicted - 20.0).abs() < 1e-9, "predicted {predicted}");

        // A driver sleeping until `predicted` and then stepping once more
        // sees the same charge a tick-by-tick simulation would.
        let mut stepped = smes.charge;
        for _ in 0..20 {
            stepped.discharge_out(100.0);
        }
        assert!((stepped.charge - model.value_at(20.0)).abs() < 1e-6);
    }

    #[test]
    fn apc_cell_model_predicts_when_a_steady_drain_empties_the_cell() {
        let apc = apc_with(500.0, 500.0);
        // Draining at 200 W with CELLRATE = 0.002: empties in
        // 500 / (0.002 * 200) = 1250 ticks.
        let model = apc_cell_model(&apc, Watts(-200.0), 0.0);
        let predicted = model.crossing(0.0, 0.0).expect("reaches empty");
        assert!((predicted - 1250.0).abs() < 1e-6, "predicted {predicted}");
    }

    #[test]
    fn brownout_fires_on_no_supply_or_overdraw() {
        assert!(brownout(Watts::ZERO, Watts::ZERO));
        assert!(brownout(Watts(100.0), Watts(102.0)));
        assert!(!brownout(Watts(100.0), Watts(100.0)));
        assert!(!brownout(Watts(100.0), Watts::ZERO));
    }

    #[test]
    fn storage_input_shares_never_exceed_the_ask_or_the_excess() {
        // Two SMES ask for 100 and 300 of a region with only 120 excess:
        // each gets its own fraction of the shortfall, summing to the
        // excess exactly (no more, no less).
        let (ask_a, ask_b, excess) = (Watts(100.0), Watts(300.0), Watts(120.0));
        let total = Watts(ask_a.get() + ask_b.get());
        let (got_a, got_b) = (
            storage_input_share(ask_a, total, excess),
            storage_input_share(ask_b, total, excess),
        );
        assert!(got_a.get() <= ask_a.get() + 1e-9);
        assert!(got_b.get() <= ask_b.get() + 1e-9);
        assert!((got_a.get() + got_b.get() - excess.get()).abs() < 1e-9);
    }

    #[test]
    fn storage_input_share_is_zero_with_nothing_asked() {
        assert_eq!(storage_input_share(Watts(50.0), Watts::ZERO, Watts(100.0)), Watts::ZERO);
    }

    #[test]
    fn storage_output_shares_sum_to_what_storage_actually_covered() {
        // Two SMES offering 200 and 600 W cover a region's 100 W of
        // storage-financed load: split proportionally to their offers.
        let (offer_a, offer_b, used) = (Watts(200.0), Watts(600.0), Watts(100.0));
        let total = Watts(offer_a.get() + offer_b.get());
        let (got_a, got_b) = (
            storage_output_share(offer_a, total, used),
            storage_output_share(offer_b, total, used),
        );
        assert!((got_a.get() - 25.0).abs() < 1e-9, "1/4 of the offer, 1/4 of the load: {got_a:?}");
        assert!((got_b.get() - 75.0).abs() < 1e-9);
        assert!((got_a.get() + got_b.get() - used.get()).abs() < 1e-9);
    }

    proptest! {
        #[test]
        fn storage_shares_conserve_for_any_split(
            ask_a in 0.0f64..1000.0, ask_b in 0.0f64..1000.0, excess in 0.0f64..1000.0,
        ) {
            let total = Watts(ask_a + ask_b);
            let got_a = storage_input_share(Watts(ask_a), total, Watts(excess));
            let got_b = storage_input_share(Watts(ask_b), total, Watts(excess));
            prop_assert!(got_a.get() + got_b.get() <= excess + 1e-6);
            prop_assert!(got_a.get() <= ask_a + 1e-6);
            prop_assert!(got_b.get() <= ask_b + 1e-6);
        }
    }

    proptest! {
        /// The cell never leaves [0, capacity] and the grid never delivers
        /// more than its own surplus, across any demand/supply sequence.
        #[test]
        fn apc_tick_conserves_and_stays_in_bounds(
            max_charge in 10.0f64..2000.0,
            start_charge in 0.0f64..2000.0,
            avails in prop::collection::vec(0.0f64..5000.0, 1..40),
            demands in prop::collection::vec(0.0f64..5000.0, 1..40),
        ) {
            let mut apc = apc_with(max_charge, start_charge.min(max_charge));
            for (avail, demand) in avails.into_iter().zip(demands) {
                let mut grid = TestGrid { avail: Watts(avail), load: Watts::ZERO };
                let d = [Watts(demand / 3.0); 3];
                apc_tick(&mut apc, d, &mut grid);
                prop_assert!((0.0..=max_charge + 1e-6).contains(&apc.cell.charge));
                prop_assert!(grid.load.get() <= avail + 1e-6);
            }
        }
    }
}
