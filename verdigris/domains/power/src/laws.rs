//! Power's laws (`rust_architecture.md` §4.3, §6, §8.5): pure functions
//! over components and the region ledger, plus the `Law` wiring that runs
//! them over `vg_core`'s driver. No `PowerHost`, no side ledger map -- a
//! region's only state is [`PowerLedger`], the network payload. `Smes`
//! binds its own node directly for output (one per unit, like `Apc`); each
//! of its input terminals is its own entity on its own region
//! ([`vg_core::query::Foreign`] reaches the shared `Smes` row from one).

use vg_core::vg;

use crate::components::{Apc, Producer, Smes, SmesInputTerminal, setting};

/// Power's events: about a region, not a component, so domain events
/// (the DM generator dispatches them to global handlers).
#[vg::events(domain = power)]
pub enum PowerEvent {
    /// A region lost supply or was overdrawn.
    Brownout,
    /// A previously browned-out region recovered.
    Restored,
    /// An APC's channel settings changed (the shedding ladder, or a manual
    /// override).
    ApcChannelChanged,
}

/// Draws up to `watts` from a region with `avail` planned and `load`
/// delivered so far; returns what was delivered (never beyond the surplus).
fn draw(avail: f64, load: &mut f64, watts: f64) -> f64 {
    let d = watts.min(avail - *load).max(0.0);
    *load += d;
    d
}

/// `ApcTick`: the channel autoset ladder and charge mode
/// (`apc_power_distributor.tick()`). Returns `(cell_discharged,
/// cell_charged)` watts this tick, for the caller's conservation books:
/// `cell_discharged` never reaches `grid` (the cell covers the area
/// directly); `cell_charged` does, through [`draw`].
pub fn apc_tick(apc: &mut Apc, demand: [f64; 3], avail: f64, load: &mut f64) -> (f64, f64) {
    apc.oneoff = [0.0; 3];
    if !apc.active {
        return (0.0, 0.0);
    }
    let total: f64 = demand.iter().sum();
    let excess = avail - *load;
    if apc.has_cell && !apc.shorted_or_grid_check {
        with_cell(apc, excess, total, avail, load)
    } else {
        (apc.charging, apc.chargecount) = (0, 0);
        apc.channels = apc.channels.map(|v| setting::autoset(v, 0));
        apc.alarm = true;
        apc.autoflag = 0;
        (0.0, 0.0)
    }
}

fn with_cell(apc: &mut Apc, excess: f64, total: f64, avail: f64, load: &mut f64) -> (f64, f64) {
    let mut cell = apc.cell();
    let mut discharged = 0.0;
    if excess >= total {
        draw(avail, load, total);
    } else {
        let available = cell.watts_available();
        discharged = cell.discharge_out(total);
        if available + excess >= total {
            let drawn = draw(avail, load, excess);
            cell.charge = cell.capacity.min(cell.charge + cell.rate * drawn);
            apc.charging = 0;
        } else {
            (apc.charging, apc.chargecount) = (0, 0);
            apc.channels = apc.channels.map(|v| setting::autoset(v, 0));
            apc.autoflag = 0;
        }
    }
    apc.set_cell(cell);

    update_channels(apc);

    let mut cell = apc.cell();
    let mut charged = 0.0;
    if apc.chargemode && apc.charging == 1 && apc.operating {
        if excess > 0.0 {
            let ch = (excess * cell.rate).min(cell.capacity * apc.chargelevel);
            let drawn = draw(avail, load, ch / cell.rate);
            cell.charge = (cell.charge + drawn * cell.rate).min(cell.capacity.max(cell.charge));
            charged = drawn;
        } else {
            (apc.charging, apc.chargecount) = (0, 0);
        }
    }
    if cell.charge >= cell.capacity {
        cell.charge = cell.capacity;
        apc.charging = 2;
    }
    if apc.chargemode {
        if apc.charging == 0 {
            if excess > cell.capacity * apc.chargelevel {
                apc.chargecount += 1;
            } else {
                apc.chargecount = 0;
            }
            if apc.chargecount >= 10 {
                (apc.charging, apc.chargecount) = (1, 0);
            }
        }
    } else {
        (apc.charging, apc.chargecount) = (0, 0);
    }
    apc.set_cell(cell);
    (discharged, charged)
}

/// `_update_channels()`: shedding tiers from the cell level and trend
/// (config policy, not hard-coded thresholds -- see
/// the APC's `policy_*` fields).
fn update_channels(apc: &mut Apc) {
    if apc.charging != 0 && apc.longtermpower < 10 {
        apc.longtermpower += 1;
    } else if apc.longtermpower > -10 {
        apc.longtermpower -= 2;
    }
    let pct = 100.0 * apc.cell().fraction();
    let full = pct > apc.policy_full_above_pct || apc.longtermpower > 0;
    let partial = !full && pct > apc.policy_partial_below_pct && apc.longtermpower < 0;
    let (flag, allow, alarm) = if full {
        (3, apc.policy_full_allow, false)
    } else if partial {
        (2, apc.policy_partial_allow, true)
    } else if pct <= apc.policy_partial_below_pct {
        (1, apc.policy_min_allow, true)
    } else {
        (0, apc.policy_neutral_allow, true)
    };
    // The minimum tier only ever steps down (from partial or full).
    if apc.autoflag != flag && (flag != 1 || apc.autoflag > 1) {
        for (v, on) in apc.channels.iter_mut().zip(allow) {
            *v = setting::autoset(*v, on);
        }
        (apc.autoflag, apc.alarm) = (flag, alarm);
    }
}

/// What a SMES offers its output region this step.
pub fn smes_offer(smes: &Smes) -> f64 {
    if smes.output_enabled && smes.charge > 0.0 { (smes.charge / smes.rate).min(smes.output_level).max(0.0) } else { 0.0 }
}

/// What a SMES asks of its input region this step.
pub fn smes_ask(smes: &Smes) -> f64 {
    if smes.input_enabled { ((smes.capacity - smes.charge) / smes.rate).clamp(0.0, smes.input_level) } else { 0.0 }
}

/// A region browns out when it has no supply at all, or its planned
/// excess (`avail - load`) is meaningfully negative (overdrawn). The 1 W
/// slack absorbs float rounding across many small draws, not a real
/// tolerance for being overdrawn.
pub fn brownout(avail: f64, load: f64) -> bool {
    avail <= 0.0 || avail - load < -1.0
}

/// `SmesOutputApply`'s share: one output terminal's pro-rata slice of
/// `storage_used` (the region's load beyond non-storage `avail`)
/// proportional to its own offer out of every output terminal's combined
/// offer on that region.
pub fn storage_output_share(offer: f64, total_offer: f64, storage_used: f64) -> f64 {
    if total_offer > 0.0 { storage_used * offer / total_offer } else { 0.0 }
}

/// `SmesInputApply`'s share: one input terminal's pro-rata slice of a
/// region's leftover supply (`excess`) out of everything storage on that
/// region asked for (`total_asks`), never more than its own `ask` or the
/// excess itself.
pub fn storage_input_share(ask: f64, total_asks: f64, excess: f64) -> f64 {
    if total_asks > 0.0 { (ask * (excess / total_asks).clamp(0.0, 1.0)).min(excess.max(0.0)) } else { 0.0 }
}

// --- Law wiring (`rust_architecture.md` §4.3, §8.5; core::law, core::query,
// core::network::law) -------------------------------------------------------

use vg_core::law::Settle;
use vg_core::network::law::{InRegion, Payload};
use vg_core::query::Foreign;

use crate::kind::Cables;

vg_core::law! {
    /// Zeroes a region's per-step accumulators before `ProducerCredit`/
    /// `SmesOutputPlan`/`SmesInputPlan` add this step's numbers into it.
    /// Registration order (not `after`) puts this first: no other power law
    /// needs to run before it, and the driver keeps registration order absent
    /// a declared edge.
    pub PowerReset("power_reset"): () => Payload<Cables>, |ctx, _dt| {
        let ledger = &mut ctx.writes.0;
        *ledger = crate::PowerLedger { brown: ledger.brown, ..Default::default() };
        Settle::Active
    }
}

vg_core::law! {
    /// Credits a producer's registered supply, plus its one-shot pulse
    /// (consumed and reset here), into its region's `avail`.
    pub ProducerCredit("power_producer_credit"): () => (Producer, InRegion<Cables>), |ctx, _dt| {
        let (producer, region) = &mut ctx.writes;
        region.payload.avail += producer.supply + producer.pulse;
        producer.pulse = 0.0;
        Settle::Active
    }
}

vg_core::law! {
    /// Plans one SMES output terminal's offer this step (from the shared
    /// `Smes` row through [`Foreign`]) and credits it into its own region's
    /// `avail`/`smes_offer_total`, ordered before `PowerBalance`'s consumers
    /// so the offer is part of what they can draw against.
    pub SmesOutputPlan("power_smes_output_plan"): Smes => InRegion<Cables>, |ctx, _dt| {
        let offer = smes_offer(ctx.reads);
        ctx.writes.payload.avail += offer;
        ctx.writes.payload.smes_offer_total += offer;
        Settle::Active
    }
}

vg_core::law! {
    /// As [`SmesOutputPlan`], the input side: sums what every SMES input
    /// terminal on a region would like this step (not itself supply, so not
    /// credited into `avail`).
    pub SmesInputPlan("power_smes_input_plan"): Foreign<SmesInputTerminal, Smes> => InRegion<Cables>, |ctx, _dt| {
        let Some(smes) = &ctx.reads.value else {
            return Settle::Active;
        };
        let target = smes_ask(smes);
        ctx.writes.payload.smes_ask_total += target;
        Settle::Active
    }
}

vg_core::law! {
    /// The channel autoset ladder and charge mode, per APC, every tick
    /// ([`apc_tick`]), drawing against its region's `avail` (now including
    /// every producer and SMES output offer this step).
    pub ApcTick("power_apc_tick"): () => (Apc, Option<InRegion<Cables>>), |ctx, _dt| {
        let (apc, region) = &mut ctx.writes;
        let demand: [f64; 3] = std::array::from_fn(|i| apc.static_load[i] + apc.oneoff[i]);
        // No network: nothing available, and the load has nowhere to land.
        let mut spare_load = 0.0;
        let (avail, load) = match region {
            Some(r) => (r.payload.avail, &mut r.payload.load),
            None => (0.0, &mut spare_load),
        };
        let (discharged, charged) = apc_tick(apc, demand, avail, load);
        // Watts (`RateStore`'s API) to the cell's own units, as the field moved.
        let (rate, alarm) = (apc.rate, apc.alarm);
        ctx.ledger().source("power_apc_charge", charged * rate);
        ctx.ledger().sink("power_apc_charge", discharged * rate);
        if alarm {
            ctx.emit(PowerEvent::ApcChannelChanged);
        }
        Settle::Active
    }
}

vg_core::law! {
    /// Brownout and the settled numbers, once every region's producers, SMES
    /// offers and APC draws for this step have landed.
    pub PowerSettle("power_settle"): () => Payload<Cables>, |ctx, _dt| {
        let ledger = &mut ctx.writes.0;
        let non_storage_avail = ledger.avail - ledger.smes_offer_total;
        ledger.storage_used = (ledger.load - non_storage_avail).max(0.0);
        ledger.region_excess = ledger.avail - ledger.load;
        let was_brown = ledger.brown;
        let now_brown = brownout(ledger.avail, ledger.load);
        ledger.brown = now_brown;
        match (was_brown, now_brown) {
            (false, true) => ctx.emit(PowerEvent::Brownout),
            (true, false) => ctx.emit(PowerEvent::Restored),
            _ => {}
        }
        Settle::Active
    }
}

vg_core::law! {
    /// Zeroes each SMES's per-step flow readings (`output_used`,
    /// `input_used`, `input_available`) before the apply laws write them, so
    /// a unit whose output node is on no region, or whose terminals are all
    /// cut, reads zero rather than its last flow.
    pub SmesFlowReset("power_smes_flow_reset"): () => Smes, |ctx, _dt| {
        let smes = &mut ctx.writes;
        smes.output_used = 0.0;
        smes.input_used = 0.0;
        smes.input_available = 0.0;
        Settle::Active
    }
}

vg_core::law! {
    /// Discharges one SMES's pro-rata share of its region's storage-financed
    /// load, ordered after `PowerSettle` so `storage_used`/`smes_offer_total`
    /// are final for this step.
    pub SmesOutputApply("power_smes_output_apply"): InRegion<Cables> => Smes, |ctx, _dt| {
        let offer = smes_offer(ctx.writes);
        let region = &ctx.reads.payload;
        let share = storage_output_share(offer, region.smes_offer_total, region.storage_used);
        let rate = ctx.writes.rate;
        let delivered = ctx.writes.with_cell(|c| c.discharge_out(share));
        ctx.writes.output_used = delivered;
        ctx.ledger().sink("power_smes_charge", delivered * rate);
        Settle::Active
    }
}

vg_core::law! {
    /// Charges one SMES input terminal's pro-rata share of its region's
    /// leftover supply, ordered after `PowerSettle`.
    pub SmesInputApply("power_smes_input_apply"): InRegion<Cables> => Foreign<SmesInputTerminal, Smes>, |ctx, _dt| {
        let Some(smes) = &mut ctx.writes.value else {
            return Settle::Active;
        };
        let target = smes_ask(smes);
        let region = &ctx.reads.payload;
        let share = storage_input_share(target, region.smes_ask_total, region.region_excess);
        let rate = smes.rate;
        let absorbed = smes.with_cell(|c| c.charge_in(share));
        smes.input_used += absorbed;
        smes.input_available += region.region_excess.max(0.0);
        ctx.ledger().source("power_smes_charge", absorbed * rate);
        Settle::Active
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use proptest::prelude::*;
    use vg_core::rate::RateStore;

    use crate::components::setting;

    struct TestGrid {
        avail: f64,
        load: f64,
    }

    fn tick(apc: &mut Apc, demand: [f64; 3], g: &mut TestGrid) -> (f64, f64) {
        apc_tick(apc, demand, g.avail, &mut g.load)
    }

    fn apc_with(max_charge: f64, charge: f64) -> Apc {
        let mut apc = Apc::default();
        apc.set_cell(RateStore { charge, capacity: max_charge, rate: 0.002 });
        apc
    }

    #[test]
    fn a_strong_grid_carries_the_area_untouched() {
        let mut apc = apc_with(1000.0, 1000.0);
        let mut grid = TestGrid { avail: 100_000.0, load: 0.0 };
        let demand = [1000.0, 2000.0, 1000.0];
        tick(&mut apc, demand, &mut grid);
        assert_eq!(apc.cell().charge, 1000.0, "cell untouched: grid alone covers it");
        assert_eq!(grid.load, 4000.0);
    }

    #[test]
    fn no_supply_drains_the_cell_by_cellrate_per_watt() {
        let mut apc = apc_with(1000.0, 1000.0);
        let mut grid = TestGrid { avail: 0.0, load: 0.0 };
        let demand = [1000.0, 2000.0, 1000.0];
        tick(&mut apc, demand, &mut grid);
        let expect = 1000.0 - 4000.0 * 0.002;
        assert!((apc.cell().charge - expect).abs() < 1e-9);
    }

    #[test]
    fn a_dead_cell_settles_with_every_channel_shed() {
        let mut apc = apc_with(1000.0, 0.0);
        apc.channels = [setting::ON_AUTO; 3];
        let mut grid = TestGrid { avail: 0.0, load: 0.0 };
        for _ in 0..10 {
            tick(&mut apc, [100.0; 3], &mut grid);
        }
        assert_eq!(apc.autoflag, 0);
        assert!(apc.channels.iter().all(|&v| !setting::powered(v)), "every channel sheds once longtermpower settles");
    }

    #[test]
    fn a_slowly_draining_cell_settles_on_the_shedding_ladder_with_the_alarm_raised() {
        let mut apc = apc_with(1000.0, 1000.0);
        apc.channels = [setting::ON_AUTO; 3];
        let mut grid = TestGrid { avail: 0.0, load: 0.0 };
        for _ in 0..1500 {
            tick(&mut apc, [100.0; 3], &mut grid);
            grid.load = 0.0;
        }
        assert!(apc.cell().charge > 0.0, "not yet fully depleted");
        assert!(apc.alarm);
        assert_eq!(apc.autoflag, 1, "settled at the minimum tier, not neutral or full");
        assert!(!setting::powered(apc.channels[0]), "equipment sheds first");
        assert!(!setting::powered(apc.channels[1]), "then lighting");
        assert!(setting::powered(apc.channels[2]), "environment/life support sheds last");
    }

    #[test]
    fn cell_charge_and_discharge_never_leave_zero_or_capacity() {
        let mut apc = apc_with(500.0, 250.0);
        let mut grid = TestGrid { avail: 10_000.0, load: 0.0 };
        for _ in 0..50 {
            tick(&mut apc, [50.0; 3], &mut grid);
            grid.load = 0.0;
            assert!((0.0..=500.0).contains(&apc.cell().charge));
        }
    }

    fn smes_with(charge: f64, capacity: f64, rate: f64) -> Smes {
        let mut smes = Smes::default();
        smes.set_cell(RateStore { charge, capacity, rate });
        smes
    }

    #[test]
    fn smes_offers_output_only_when_connected_and_charged() {
        let mut smes = smes_with(1e5, 1e6, 0.033_33);
        assert_eq!(
            {
                smes.output_enabled = false;
                let o = smes_offer(&smes);
                smes.output_enabled = true;
                o
            },
            0.0,
            "not connected"
        );
        assert!(smes_offer(&smes) > 0.0);
        let mut cell = smes.cell();
        cell.charge = 0.0;
        smes.set_cell(cell);
        assert_eq!(smes_offer(&smes), 0.0, "empty");
    }

    #[test]
    fn smes_input_targets_room_to_capacity_bounded_by_input_level() {
        let mut smes = smes_with(0.0, 1e6, 0.033_33);
        smes.input_enabled = true;
        smes.input_level = 100.0;
        assert_eq!(smes_ask(&smes), 100.0, "capped by input_level despite huge room");
    }

    #[test]
    fn smes_charge_round_trips_through_rate_conversion() {
        let mut smes = smes_with(0.0, 1000.0, 0.5);
        let absorbed = smes.with_cell(|c| c.charge_in(100.0));
        assert_eq!(absorbed, 100.0);
        assert_eq!(smes.cell().charge, 50.0);
        let delivered = smes.with_cell(|c| c.discharge_out(1000.0));
        assert_eq!(delivered, 100.0, "capped by what's stored, not the request");
        assert_eq!(smes.cell().charge, 0.0);
    }

    #[test]
    fn brownout_fires_on_no_supply_or_overdraw() {
        assert!(brownout(0.0, 0.0));
        assert!(brownout(100.0, 102.0));
        assert!(!brownout(100.0, 100.0));
        assert!(!brownout(100.0, 0.0));
    }

    #[test]
    fn storage_input_shares_never_exceed_the_ask_or_the_excess() {
        let (ask_a, ask_b, excess) = (100.0, 300.0, 120.0);
        let total = ask_a + ask_b;
        let (got_a, got_b) = (storage_input_share(ask_a, total, excess), storage_input_share(ask_b, total, excess));
        assert!(got_a <= ask_a + 1e-9);
        assert!(got_b <= ask_b + 1e-9);
        assert!((got_a + got_b - excess).abs() < 1e-9);
    }

    #[test]
    fn storage_input_share_is_zero_with_nothing_asked() {
        assert_eq!(storage_input_share(50.0, 0.0, 100.0), 0.0);
    }

    #[test]
    fn storage_output_shares_sum_to_what_storage_actually_covered() {
        let (offer_a, offer_b, used) = (200.0, 600.0, 100.0);
        let total = offer_a + offer_b;
        let (got_a, got_b) = (storage_output_share(offer_a, total, used), storage_output_share(offer_b, total, used));
        assert!((got_a - 25.0).abs() < 1e-9, "1/4 of the offer, 1/4 of the load: {got_a:?}");
        assert!((got_b - 75.0).abs() < 1e-9);
        assert!((got_a + got_b - used).abs() < 1e-9);
    }

    proptest! {
        #[test]
        fn storage_shares_conserve_for_any_split(
            ask_a in 0.0f64..1000.0, ask_b in 0.0f64..1000.0, excess in 0.0f64..1000.0,
        ) {
            let total = ask_a + ask_b;
            let got_a = storage_input_share(ask_a, total, excess);
            let got_b = storage_input_share(ask_b, total, excess);
            prop_assert!(got_a + got_b <= excess + 1e-6);
            prop_assert!(got_a <= ask_a + 1e-6);
            prop_assert!(got_b <= ask_b + 1e-6);
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
                let mut grid = TestGrid { avail, load: 0.0 };
                let d = [demand / 3.0; 3];
                tick(&mut apc, d, &mut grid);
                prop_assert!((0.0..=max_charge + 1e-6).contains(&apc.cell().charge));
                prop_assert!(grid.load <= avail + 1e-6);
            }
        }
    }
}
