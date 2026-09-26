//! Power's laws (`rust_architecture.md` §4.3, §6, §8.5): pure functions
//! over components and the region ledger, plus the `Law` wiring that runs
//! them over `vg_core`'s driver. No `PowerHost`, no side ledger map -- a
//! region's only state is [`PowerLedger`], the network payload. `Smes`
//! binds its own node directly for output (one per unit, like `Apc`); each
//! of its input terminals is its own entity on its own region
//! ([`vg_core::query::Foreign`] reaches the shared `Smes` row from one).

use crate::components::{Apc, Channel, Producer, Smes, SmesInputTerminal};

/// A region as one law draws against it: this step's planned supply and
/// what has been delivered so far.
pub struct Draw<'a> {
    pub avail: f64,
    pub load: &'a mut f64,
}

impl Draw<'_> {
    /// `avail - load` so far.
    #[must_use]
    pub fn surplus(&self) -> f64 {
        self.avail - *self.load
    }

    /// Draws up to `watts`; returns what was delivered (never more than the
    /// surplus).
    pub fn draw(&mut self, watts: f64) -> f64 {
        let d = watts.min(self.surplus()).max(0.0);
        *self.load += d;
        d
    }
}

/// `ApcTick`: the channel autoset ladder and charge mode
/// (`apc_power_distributor.tick()`). Returns `(cell_discharged,
/// cell_charged)` watts this tick, for the caller's conservation books:
/// `cell_discharged` never reaches `grid` (the cell covers the area
/// directly); `cell_charged` does, through [`Draw::draw`].
pub fn apc_tick(apc: &mut Apc, demand: [f64; 3], grid: &mut Draw<'_>) -> (f64, f64) {
    apc.oneoff = [0.0; 3];
    if !apc.active {
        return (0.0, 0.0);
    }
    let total: f64 = demand.iter().sum();
    let excess = grid.surplus();
    if apc.has_cell && !apc.shorted_or_grid_check {
        with_cell(apc, excess, total, grid)
    } else {
        apc.charging = 0;
        apc.chargecount = 0;
        for c in Channel::ALL {
            apc.set_channel(c, apc.channel(c).autoset(0));
        }
        apc.alarm = true;
        apc.autoflag = 0;
        (0.0, 0.0)
    }
}

fn with_cell(apc: &mut Apc, excess: f64, total: f64, grid: &mut Draw<'_>) -> (f64, f64) {
    let mut cell = apc.cell();
    let mut discharged = 0.0;
    if excess >= total {
        grid.draw(total);
    } else {
        let available = cell.watts_available();
        discharged = cell.discharge_out(total);
        if available + excess >= total {
            let drawn = grid.draw(excess);
            cell.charge = cell.capacity.min(cell.charge + cell.rate * drawn);
            apc.charging = 0;
        } else {
            apc.charging = 0;
            apc.chargecount = 0;
            for c in Channel::ALL {
                apc.set_channel(c, apc.channel(c).autoset(0));
            }
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
            let drawn = grid.draw(ch / cell.rate);
            cell.charge = (cell.charge + drawn * cell.rate).min(cell.capacity.max(cell.charge));
            charged = drawn;
        } else {
            apc.charging = 0;
            apc.chargecount = 0;
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
                apc.chargecount = 0;
                apc.charging = 1;
            }
        }
    } else {
        apc.charging = 0;
        apc.chargecount = 0;
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
    let set = |apc: &mut Apc, allow: [u8; 3]| {
        for c in Channel::ALL {
            apc.set_channel(c, apc.channel(c).autoset(allow[c.idx()]));
        }
    };
    if pct > apc.policy_full_above_pct || apc.longtermpower > 0 {
        if apc.autoflag != 3 {
            set(apc, apc.policy_full_allow);
            apc.autoflag = 3;
            apc.alarm = false;
        }
    } else if pct <= apc.policy_full_above_pct && pct > apc.policy_partial_below_pct && apc.longtermpower < 0 {
        if apc.autoflag != 2 {
            set(apc, apc.policy_partial_allow);
            apc.alarm = true;
            apc.autoflag = 2;
        }
    } else if pct <= apc.policy_partial_below_pct {
        if apc.autoflag > 1 {
            set(apc, apc.policy_min_allow);
            apc.alarm = true;
            apc.autoflag = 1;
        }
    } else if apc.autoflag != 0 {
        set(apc, apc.policy_neutral_allow);
        apc.alarm = true;
        apc.autoflag = 0;
    }
}

/// SMES planning: the output offered and input requested next step, given
/// whether the unit's output/input terminals are on a region.
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct SmesPlan {
    pub offer: f64,
    pub target_load: f64,
}

#[must_use]
pub fn smes_plan(smes: &Smes, output_connected: bool, input_connected: bool) -> SmesPlan {
    let cell = smes.cell();
    let offer = if smes.output_enabled && output_connected && cell.charge > 0.0 {
        (cell.charge / cell.rate).min(smes.output_level).max(0.0)
    } else {
        0.0
    };
    let target_load = if smes.input_enabled && input_connected {
        ((cell.capacity - cell.charge) / cell.rate).clamp(0.0, smes.input_level)
    } else {
        0.0
    };
    SmesPlan { offer, target_load }
}

/// Charges a SMES from `got` watts offered this step; returns watts
/// actually absorbed (bounded by room to capacity).
pub fn smes_charge_in(smes: &mut Smes, got: f64) -> f64 {
    let mut cell = smes.cell();
    let absorbed = cell.charge_in(got);
    smes.set_cell(cell);
    absorbed
}

/// Discharges a SMES for up to `share` watts; returns watts actually
/// delivered (bounded by stored charge).
pub fn smes_discharge_out(smes: &mut Smes, share: f64) -> f64 {
    let mut cell = smes.cell();
    let delivered = cell.discharge_out(share);
    smes.set_cell(cell);
    delivered
}

/// A region browns out when it has no supply at all, or its planned
/// excess (`avail - load`) is meaningfully negative (overdrawn). The 1 W
/// slack absorbs float rounding across many small draws, not a real
/// tolerance for being overdrawn.
#[must_use]
pub fn brownout(avail: f64, load: f64) -> bool {
    avail <= 0.0 || avail - load < -1.0
}

/// `SmesOutputApply`'s share: one output terminal's pro-rata slice of
/// `storage_used` (the region's load beyond non-storage `avail`)
/// proportional to its own offer out of every output terminal's combined
/// offer on that region.
#[must_use]
pub fn storage_output_share(offer: f64, total_offer: f64, storage_used: f64) -> f64 {
    if total_offer <= 0.0 {
        return 0.0;
    }
    storage_used * offer / total_offer
}

/// `SmesInputApply`'s share: one input terminal's pro-rata slice of a
/// region's leftover supply (`excess`) out of everything storage on that
/// region asked for (`total_asks`), never more than its own `ask` or the
/// excess itself.
#[must_use]
pub fn storage_input_share(ask: f64, total_asks: f64, excess: f64) -> f64 {
    if total_asks <= 0.0 {
        return 0.0;
    }
    let fraction = (excess / total_asks).clamp(0.0, 1.0);
    (ask * fraction).min(excess.max(0.0))
}

// --- Law wiring (`rust_architecture.md` §4.3, §8.5; core::law, core::query,
// core::network::law) -------------------------------------------------------

use vg_core::law::Settle;
use vg_core::network::law::{InRegion, Payload};
use vg_core::query::Foreign;

use crate::events::PowerEvent;
use crate::kind::Cables;

vg_core::law! {
    /// Zeroes a region's per-step accumulators before `ProducerCredit`/
    /// `SmesOutputPlan`/`SmesInputPlan` add this step's numbers into it.
    /// Registration order (not `after`) puts this first: no other power law
    /// needs to run before it, and the driver keeps registration order absent
    /// a declared edge.
    pub PowerReset("power_reset"): () => Payload<Cables>, |ctx, _dt| {
        let ledger = &mut ctx.writes.0;
        ledger.avail = 0.0;
        ledger.load = 0.0;
        ledger.smes_offer_total = 0.0;
        ledger.smes_ask_total = 0.0;
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
        let offer = smes_plan(ctx.reads, true, false).offer;
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
        let target = smes_plan(smes, false, true).target_load;
        ctx.writes.payload.smes_ask_total += target;
        Settle::Active
    }
}

vg_core::law! {
    /// The channel autoset ladder and charge mode, per APC, every tick
    /// ([`apc_tick`]), drawing against its region's `avail` (now including
    /// every producer and SMES output offer this step).
    pub ApcTick("power_apc_tick"): () => (Apc, InRegion<Cables>), |ctx, _dt| {
        let (discharged, charged, alarm) = {
            let (apc, region) = &mut ctx.writes;
            let demand: [f64; 3] = std::array::from_fn(|i| apc.static_load[i] + apc.oneoff[i]);
            let (discharged, charged) = {
                let mut grid = Draw { avail: region.payload.avail, load: &mut region.payload.load };
                apc_tick(apc, demand, &mut grid)
            };
            (discharged, charged, apc.alarm)
        };
        // `charged`/`discharged` are watts (§4.10's `RateStore` API); the
        // conserved field is `Apc::charge`, in the cell's internal units,
        // so the ledger wants the same `rate` conversion the field itself
        // moved by.
        let rate = ctx.writes.0.rate;
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
    /// Discharges one SMES's pro-rata share of its region's storage-financed
    /// load, ordered after `PowerSettle` so `storage_used`/`smes_offer_total`
    /// are final for this step.
    pub SmesOutputApply("power_smes_output_apply"): InRegion<Cables> => Smes, |ctx, _dt| {
        let offer = smes_plan(ctx.writes, true, false).offer;
        let region = &ctx.reads.payload;
        let share = storage_output_share(offer, region.smes_offer_total, region.storage_used);
        let rate = ctx.writes.rate;
        let delivered = smes_discharge_out(ctx.writes, share);
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
        let target = smes_plan(smes, false, true).target_load;
        let region = &ctx.reads.payload;
        let share = storage_input_share(target, region.smes_ask_total, region.region_excess);
        let rate = smes.rate;
        let absorbed = smes_charge_in(smes, share);
        ctx.ledger().source("power_smes_charge", absorbed * rate);
        Settle::Active
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use proptest::prelude::*;
    use vg_core::rate::RateStore;

    use crate::components::ChannelSetting;

    struct TestGrid {
        avail: f64,
        load: f64,
    }

    fn tick(apc: &mut Apc, demand: [f64; 3], g: &mut TestGrid) -> (f64, f64) {
        apc_tick(apc, demand, &mut Draw { avail: g.avail, load: &mut g.load })
    }

    fn apc_with(max_charge: f64, charge: f64) -> Apc {
        let mut apc = Apc::default();
        apc.set_cell(RateStore {
            charge,
            capacity: max_charge,
            rate: crate::components::CELLRATE,
        });
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
        let expect = 1000.0 - 4000.0 * crate::components::CELLRATE;
        assert!((apc.cell().charge - expect).abs() < 1e-9);
    }

    #[test]
    fn a_dead_cell_settles_with_every_channel_shed() {
        let mut apc = apc_with(1000.0, 0.0);
        for c in Channel::ALL {
            apc.set_channel(c, ChannelSetting::OnAuto);
        }
        let mut grid = TestGrid { avail: 0.0, load: 0.0 };
        for _ in 0..10 {
            tick(&mut apc, [100.0; 3], &mut grid);
        }
        assert_eq!(apc.autoflag, 0);
        assert!(Channel::ALL.iter().all(|&c| !apc.channel(c).powered()), "every channel sheds once longtermpower settles");
    }

    #[test]
    fn a_slowly_draining_cell_settles_on_the_shedding_ladder_with_the_alarm_raised() {
        let mut apc = apc_with(1000.0, 1000.0);
        for c in Channel::ALL {
            apc.set_channel(c, ChannelSetting::OnAuto);
        }
        let mut grid = TestGrid { avail: 0.0, load: 0.0 };
        for _ in 0..1500 {
            tick(&mut apc, [100.0; 3], &mut grid);
            grid.load = 0.0;
        }
        assert!(apc.cell().charge > 0.0, "not yet fully depleted");
        assert!(apc.alarm);
        assert_eq!(apc.autoflag, 1, "settled at the minimum tier, not neutral or full");
        assert!(!apc.channel(Channel::Equip).powered(), "equipment sheds first");
        assert!(!apc.channel(Channel::Light).powered(), "then lighting");
        assert!(apc.channel(Channel::Environ).powered(), "environment/life support sheds last");
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
        let mut smes = smes_with(1e5, 1e6, crate::components::SMESRATE);
        assert_eq!(smes_plan(&smes, false, false).offer, 0.0, "not connected");
        let plan = smes_plan(&smes, true, false);
        assert!(plan.offer > 0.0);
        let mut cell = smes.cell();
        cell.charge = 0.0;
        smes.set_cell(cell);
        assert_eq!(smes_plan(&smes, true, false).offer, 0.0, "empty");
    }

    #[test]
    fn smes_input_targets_room_to_capacity_bounded_by_input_level() {
        let mut smes = smes_with(0.0, 1e6, crate::components::SMESRATE);
        smes.input_enabled = true;
        smes.input_level = 100.0;
        let plan = smes_plan(&smes, false, true);
        assert_eq!(plan.target_load, 100.0, "capped by input_level despite huge room");
    }

    #[test]
    fn smes_charge_round_trips_through_rate_conversion() {
        let mut smes = smes_with(0.0, 1000.0, 0.5);
        let absorbed = smes_charge_in(&mut smes, 100.0);
        assert_eq!(absorbed, 100.0);
        assert_eq!(smes.cell().charge, 50.0);
        let delivered = smes_discharge_out(&mut smes, 1000.0);
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
