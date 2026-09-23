//! The mob heat body (H2): the energy-integrator thermal model this session
//! designed and now implements for DQ Medical, per `doc/rewrite/temperature.md`
//! and the R10 component model (`rust_bindings.md`).
//!
//! One model, every body plan (humanoid, simple, machine/robot, ...),
//! differing only in [`MobHeatConfig`]: a robot zeroes `metabolic_watts` and
//! sets `coolant` instead. State is core temperature plus heat capacity;
//! every input is a **flux in watts**, integrated over `dt * time_scale`
//! (never a per-tick °C delta, `temperature.md` §2.1's energy-based rule):
//!
//! - metabolic production (`metabolic_watts`, zero on a robot);
//! - conduction to the environment through `insulation` (W/K; DQ Medical
//!   aggregates per-limb worn-protection into this one number -- per-limb
//!   couplings are a follow-up once the R10 array-field macro support
//!   lands, see the module docs' open items);
//! - up to [`MOB_EXTERNAL_SOURCES`] independent external fluxes
//!   (reagents, cryo, bellies, items, afflictions), each set by
//!   [`MobHeatWorld::body_heat_add`] and persisting (like a rate, not a
//!   one-shot amount) until the source updates or zeroes it;
//! - thermoregulation: a proportional controller driving the body toward
//!   `setpoint`, clamped to `sweat_capacity_w`/`shiver_capacity_w`.
//!
//! Comfort-band crossings are ordinary [`vg_core::watch`] `Band` conditions
//! on the `TEMPERATURE` channel (registered per body by
//! [`MobHeatWorld::set_bands`]), so a crossing wakes its subscriber through
//! the exact same mechanism turf and object heat bodies already use --
//! nothing bespoke. `time_scale = 0` freezes the body exactly (the flux
//! integral is multiplied by `dt * time_scale`, so it contributes zero).
//!
//! Radiation and breath-exchange fluxes (`temperature.md`'s other two flux
//! terms) are not yet separate inputs: today they're expected to be folded
//! into `insulation`/`ambient` by the caller until DQ Medical's strategies
//! need them broken out, at which point they're two more `MobHeatCmd`
//! variants and two more terms in [`step`], not an architecture change.

use vg_core::channel::Unit;
use vg_core::cow::ChunkLayout;
use vg_core::frame::Task;
use vg_core::outbox::{Lane, Subscriber, Wake, WatchId};
use vg_core::owner::{Applied, Domain, DomainKey};
use vg_core::sim::{BuildError, Sim, SimBuilder, SimConfig, WatchKey};
use vg_core::watch::{Cond, WatchError};

use crate::consts::TCMB;

/// Independent external heat flux slots ([`MobHeatCmd::AddHeat`]'s
/// `source`): reagents, cryo, bellies, items, afflictions can each hold one
/// without clobbering the others.
pub const MOB_EXTERNAL_SOURCES: usize = 8;

/// A generous mob-body table: this is a station's living crew, not turf
/// cells or gas mixtures.
pub const MAX_MOB_BODIES: u32 = 1 << 12;
/// Body handle generation bits (index is 12 bits; `index | generation << 12`
/// stays far below 2²⁴, exact as an f32).
pub const MOB_GENERATION_BITS: u32 = 8;

/// A mob heat body's config and state. Capacity 0 is a free slot.
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct MobHeatBody {
    /// J/K.
    pub capacity: f32,
    /// K.
    pub temperature: f32,
    /// W; zero on a body with `coolant` set.
    pub metabolic_watts: f32,
    /// A machine body: no metabolic heat, config's own coolant-loop
    /// capacity communicated through `metabolic_watts` being externally
    /// managed (a coolant loop is itself a flux source, added through
    /// [`MobHeatCmd::AddHeat`] rather than a second built-in term, so it
    /// composes with everything else instead of special-casing robots in
    /// [`step`]).
    pub coolant: bool,
    /// Aggregate conductance to `ambient`, W/K.
    pub insulation: f32,
    /// K; DM pushes this from the body's local environment.
    pub ambient: f32,
    /// K; thermoregulation's target.
    pub setpoint: f32,
    /// Max active cooling effort, W.
    pub sweat_capacity_w: f32,
    /// Max active heating effort, W.
    pub shiver_capacity_w: f32,
    /// Stasis/body-clock rate multiplier on `dt`. Zero freezes the body
    /// exactly.
    pub time_scale: f32,
    pub external_watts: [f32; MOB_EXTERNAL_SOURCES],
    pub generation: u8,
}

impl MobHeatBody {
    #[must_use]
    pub const fn is_live(&self) -> bool {
        self.capacity > 0.0
    }
}

/// Seed values for [`MobHeatCmd::Create`].
#[derive(Clone, Copy, Debug)]
pub struct MobHeatConfig {
    pub capacity: f32,
    pub temperature: f32,
    pub metabolic_watts: f32,
    pub coolant: bool,
    pub insulation: f32,
    pub ambient: f32,
    pub setpoint: f32,
    pub sweat_capacity_w: f32,
    pub shiver_capacity_w: f32,
    pub time_scale: f32,
}

impl Default for MobHeatConfig {
    fn default() -> Self {
        Self {
            capacity: 1.0,
            temperature: TCMB,
            metabolic_watts: 0.0,
            coolant: false,
            insulation: 0.0,
            ambient: TCMB,
            setpoint: TCMB,
            sweat_capacity_w: 0.0,
            shiver_capacity_w: 0.0,
            time_scale: 1.0,
        }
    }
}

/// A command to one mob heat body.
#[derive(Clone, Copy, Debug)]
pub enum MobHeatCmd {
    /// Creates (or overwrites, on slot reuse) the body.
    Create(MobHeatConfig, u8),
    /// Frees the slot.
    Release,
    SetInsulation(f32),
    SetAmbient(f32),
    SetSetpoint(f32),
    SetSweatCapacity(f32),
    SetShiverCapacity(f32),
    SetTimeScale(f32),
    SetMetabolicWatts(f32),
    SetCoolant(bool),
    /// An external flux source's current rate, W (0 clears it). Persists
    /// (a rate, not a one-shot amount) until the source updates it again.
    AddHeat(u8, f32),
}

/// The mob heat domain (linear slots).
pub struct MobHeat;

impl Domain for MobHeat {
    type Value = MobHeatBody;
    type Command = MobHeatCmd;
    const NAME: &'static str = "heat_mob_bodies";

    fn apply(b: &mut MobHeatBody, cmd: &MobHeatCmd) -> Applied {
        match *cmd {
            MobHeatCmd::Create(cfg, generation) => {
                *b = MobHeatBody {
                    capacity: cfg.capacity.max(f32::MIN_POSITIVE),
                    temperature: cfg.temperature.max(TCMB),
                    metabolic_watts: cfg.metabolic_watts,
                    coolant: cfg.coolant,
                    insulation: cfg.insulation.max(0.0),
                    ambient: cfg.ambient,
                    setpoint: cfg.setpoint,
                    sweat_capacity_w: cfg.sweat_capacity_w.max(0.0),
                    shiver_capacity_w: cfg.shiver_capacity_w.max(0.0),
                    time_scale: cfg.time_scale.max(0.0),
                    external_watts: [0.0; MOB_EXTERNAL_SOURCES],
                    generation,
                };
                return Applied::default();
            }
            MobHeatCmd::Release => {
                let generation = b.generation;
                *b = MobHeatBody::default();
                b.generation = generation;
                return Applied::default();
            }
            _ if !b.is_live() => return Applied::default(),
            MobHeatCmd::SetInsulation(v) => b.insulation = v.max(0.0),
            MobHeatCmd::SetAmbient(v) => b.ambient = v,
            MobHeatCmd::SetSetpoint(v) => b.setpoint = v,
            MobHeatCmd::SetSweatCapacity(v) => b.sweat_capacity_w = v.max(0.0),
            MobHeatCmd::SetShiverCapacity(v) => b.shiver_capacity_w = v.max(0.0),
            MobHeatCmd::SetTimeScale(v) => b.time_scale = v.max(0.0),
            MobHeatCmd::SetMetabolicWatts(v) => b.metabolic_watts = v,
            MobHeatCmd::SetCoolant(v) => b.coolant = v,
            MobHeatCmd::AddHeat(source, watts) => {
                if let Some(slot) = b.external_watts.get_mut(source as usize) {
                    *slot = watts;
                }
            }
        }
        Applied::default()
    }
}

vg_core::channels! { pub mod mob_ch for MobHeat {
    TEMPERATURE: Scalar<Kelvin> hysteresis 0.05 => |b, o| o[0] = b.temperature,
}}

/// Thermoregulation gain, W/K: how hard the controller pushes per kelvin of
/// error before the sweat/shiver capacity clamps it. A config field (not a
/// fixed constant) is a natural follow-up once DQ Medical's strategies need
/// per-species tuning; today it's shared, matching "one model... differing
/// only in config" for every *other* field.
const THERMOREG_GAIN_W_PER_K: f32 = 40.0;

/// One frame's flux integration for a live body. `dt_eff = dt * time_scale`,
/// so `time_scale == 0` changes nothing.
fn step(b: &mut MobHeatBody, dt: f32) {
    if !b.is_live() {
        return;
    }
    let metabolic = if b.coolant { 0.0 } else { b.metabolic_watts };
    let conduction = b.insulation * (b.ambient - b.temperature);
    let error = b.setpoint - b.temperature;
    let effort = (error * THERMOREG_GAIN_W_PER_K).clamp(-b.sweat_capacity_w, b.shiver_capacity_w);
    let external: f32 = b.external_watts.iter().sum();
    let total_w = metabolic + conduction + effort + external;
    let dt_eff = dt * b.time_scale;
    if dt_eff > 0.0 {
        b.temperature = (b.temperature + total_w * dt_eff / b.capacity).max(TCMB);
    }
}

/// Mob body slots layout.
#[must_use]
pub fn layout() -> ChunkLayout {
    ChunkLayout::linear(MAX_MOB_BODIES)
}

/// Registers the mob-heat domain, its watch key (comfort bands) and frame
/// task. Returns both keys: [`MobHeatWorld`] needs the watch key to
/// register per-body `Band` conditions.
pub fn add_mob_heat(builder: &mut SimBuilder, dt: f32) -> (DomainKey<MobHeat>, WatchKey<MobHeat>) {
    let bodies = builder.add_domain::<MobHeat>(layout());
    let watch = builder.add_watches(bodies);
    let res = bodies.state();
    builder.add_task(
        Task::new("heat:mob", move |ctx| {
            let mut dom = ctx.write(res);
            let live: Vec<u32> = {
                let store = &dom.store;
                let layout = store.layout();
                (0..layout.chunk_count())
                    .filter_map(|c| store.chunk(c).map(|v| (c, v)))
                    .flat_map(|(c, v)| {
                        v.iter()
                            .enumerate()
                            .filter(|(_, b)| b.is_live())
                            .filter_map(move |(i, _)| layout.index_of(c, i))
                    })
                    .collect()
            };
            for i in live {
                let Some(mut b) = dom.store.get(i) else {
                    continue;
                };
                step(&mut b, dt);
                dom.store.set(i, b);
            }
        })
        .writes(res.id()),
    );
    (bodies, watch)
}

/// A mob heat body handle: `slot | generation << 12`, exact as an `f32`.
pub type MobHandle = u32;

fn pack(slot: u32, generation: u8) -> MobHandle {
    slot | (u32::from(generation) << 12)
}

fn unpack(h: MobHandle) -> (u32, u8) {
    #[allow(clippy::cast_possible_truncation)]
    (h & (MAX_MOB_BODIES - 1), (h >> 12) as u8)
}

#[derive(Clone, Debug, Default)]
struct Slot {
    generation: u8,
    live: bool,
    /// This body's comfort-band watch, if [`MobHeatWorld::set_bands`] has
    /// registered one.
    watch: Option<WatchId>,
}

/// The mob-heat domain's host: creates/releases bodies, applies DQ
/// Medical's accessors, and steps frames. One [`MobHandle`] per body,
/// generation-checked the same way [`crate::world::HeatWorld`]'s body and
/// watch handles are (`consts.rs`'s dedicated `MOB_GENERATION_BITS`, not
/// reusing heat's own `BODY_GENERATION_BITS`/`MAX_BODIES`, since this is a
/// separate, much smaller table).
pub struct MobHeatWorld {
    sim: Sim,
    bodies: DomainKey<MobHeat>,
    watch: WatchKey<MobHeat>,
    dt: f32,
    slots: Vec<Slot>,
    free: Vec<u32>,
    next_slot: u32,
    wakes: Vec<Wake>,
}

impl MobHeatWorld {
    /// Builds the mob-heat sim.
    ///
    /// # Errors
    /// If the sim fails to build (a bad channel table, the frame pool).
    pub fn new(dt: f32) -> Result<Self, BuildError> {
        let mut b = SimBuilder::new(SimConfig {
            threads: 1,
            seed: 0x4d4f_4248,
            record: false,
            ..SimConfig::default()
        });
        let (bodies, watch) = add_mob_heat(&mut b, dt);
        let sim = b.build()?;
        Ok(Self {
            sim,
            bodies,
            watch,
            dt,
            slots: Vec::new(),
            free: Vec::new(),
            next_slot: 0,
            wakes: Vec::new(),
        })
    }

    fn alloc_slot(&mut self) -> u32 {
        if let Some(slot) = self.free.pop() {
            slot
        } else {
            let slot = self.next_slot;
            self.next_slot += 1;
            self.slots.push(Slot::default());
            slot
        }
    }

    fn live_slot(&self, h: MobHandle) -> Option<u32> {
        let (slot, generation) = unpack(h);
        let rec = self.slots.get(slot as usize)?;
        (rec.live && rec.generation == generation).then_some(slot)
    }

    /// Creates a body. Errors if the table is full.
    ///
    /// # Errors
    /// Out of mob body slots.
    pub fn create_body(&mut self, config: MobHeatConfig) -> Result<MobHandle, String> {
        if self.free.is_empty() && self.next_slot >= MAX_MOB_BODIES {
            return Err("out of mob heat body slots".to_owned());
        }
        let slot = self.alloc_slot();
        let generation = self.slots[slot as usize].generation;
        self.sim
            .port(self.bodies)
            .submit(slot, MobHeatCmd::Create(config, generation))
            .map_err(|e| format!("{e:?}"))?;
        self.slots[slot as usize].live = true;
        Ok(pack(slot, generation))
    }

    /// Releases a body (and its comfort-band watch, if any).
    ///
    /// # Errors
    /// A stale handle.
    pub fn release(&mut self, h: MobHandle) -> Result<(), String> {
        let slot = self.live_slot(h).ok_or("stale mob heat handle")?;
        if let Some(id) = self.slots[slot as usize].watch.take() {
            let _ = self.sim.watches(self.watch).unwatch(id);
        }
        self.sim
            .port(self.bodies)
            .submit(slot, MobHeatCmd::Release)
            .map_err(|e| format!("{e:?}"))?;
        self.slots[slot as usize].generation = self.slots[slot as usize].generation.wrapping_add(1);
        self.slots[slot as usize].live = false;
        self.free.push(slot);
        Ok(())
    }

    fn submit(&mut self, h: MobHandle, cmd: MobHeatCmd) -> Result<(), String> {
        let slot = self.live_slot(h).ok_or("stale mob heat handle")?;
        self.sim
            .port(self.bodies)
            .submit(slot, cmd)
            .map_err(|e| format!("{e:?}"))?;
        Ok(())
    }

    /// # Errors
    /// A stale handle.
    pub fn set_insulation(&mut self, h: MobHandle, w_per_k: f32) -> Result<(), String> {
        self.submit(h, MobHeatCmd::SetInsulation(w_per_k))
    }

    /// # Errors
    /// A stale handle.
    pub fn set_ambient(&mut self, h: MobHandle, kelvin: f32) -> Result<(), String> {
        self.submit(h, MobHeatCmd::SetAmbient(kelvin))
    }

    /// # Errors
    /// A stale handle.
    pub fn set_setpoint(&mut self, h: MobHandle, kelvin: f32) -> Result<(), String> {
        self.submit(h, MobHeatCmd::SetSetpoint(kelvin))
    }

    /// # Errors
    /// A stale handle.
    pub fn set_sweat_capacity(&mut self, h: MobHandle, watts: f32) -> Result<(), String> {
        self.submit(h, MobHeatCmd::SetSweatCapacity(watts))
    }

    /// # Errors
    /// A stale handle.
    pub fn set_shiver_capacity(&mut self, h: MobHandle, watts: f32) -> Result<(), String> {
        self.submit(h, MobHeatCmd::SetShiverCapacity(watts))
    }

    /// # Errors
    /// A stale handle.
    pub fn set_time_scale(&mut self, h: MobHandle, scale: f32) -> Result<(), String> {
        self.submit(h, MobHeatCmd::SetTimeScale(scale))
    }

    /// # Errors
    /// A stale handle.
    pub fn set_metabolic_watts(&mut self, h: MobHandle, watts: f32) -> Result<(), String> {
        self.submit(h, MobHeatCmd::SetMetabolicWatts(watts))
    }

    /// # Errors
    /// A stale handle.
    pub fn set_coolant(&mut self, h: MobHandle, coolant: bool) -> Result<(), String> {
        self.submit(h, MobHeatCmd::SetCoolant(coolant))
    }

    /// Sets (or clears, at 0) one external flux source's current rate, W.
    /// `source` is DQ Medical's own small enum (reagents, cryo, bellies,
    /// items, afflictions, ...), `< MOB_EXTERNAL_SOURCES`.
    ///
    /// # Errors
    /// A stale handle.
    pub fn body_heat_add(&mut self, h: MobHandle, source: u8, watts: f32) -> Result<(), String> {
        self.submit(h, MobHeatCmd::AddHeat(source, watts))
    }

    /// Registers (replacing any previous one) this body's comfort bands:
    /// `levels` ascending, the band DM sees is "how many levels the
    /// temperature is at or above" (matches turf/object `Band` watches).
    /// Fires a wake ([`drain_wakes`](Self::drain_wakes), `subscriber`
    /// carried through) once immediately to report the starting band, and
    /// again on every crossing -- an ordinary `core::watch` `Band`
    /// condition on the `TEMPERATURE` channel, not a bespoke mechanism. A
    /// `Band` condition carries no payload of its own (unlike a
    /// `ThresholdSet` entry), so DM reads the current band back with its
    /// own accessor after the wake, exactly as turf/object comfort-style
    /// watches already work.
    ///
    /// # Errors
    /// A stale handle or an invalid condition (non-finite/unsorted levels).
    pub fn set_bands(
        &mut self,
        h: MobHandle,
        subscriber: Subscriber,
        lane: Lane,
        levels: &[f32],
    ) -> Result<(), String> {
        let slot = self.live_slot(h).ok_or("stale mob heat handle")?;
        if let Some(id) = self.slots[slot as usize].watch.take() {
            let _ = self.sim.watches(self.watch).unwatch(id);
        }
        let cond = Cond::Band {
            cell: slot,
            ch: mob_ch::TEMPERATURE,
            unit: Unit::Kelvin,
            levels: levels.to_vec(),
            hysteresis: None,
        };
        let id = self
            .sim
            .watches(self.watch)
            .watch(subscriber, lane, &cond)
            .map_err(|e: WatchError| format!("{e:?}"))?;
        self.slots[slot as usize].watch = Some(id);
        Ok(())
    }

    /// This body's current temperature, or `None` if the handle is stale.
    #[must_use]
    pub fn temperature(&mut self, h: MobHandle) -> Option<f32> {
        let slot = self.live_slot(h)?;
        self.sim.port(self.bodies).read(slot).map(|b| b.temperature)
    }

    fn collect(&mut self) {
        // A Band condition only ever produces a wake (it has no payload to
        // carry as an Event -- see vg_core::watch::Node::Band::eval, which
        // calls `fired.add` and nothing else); DM re-reads the body's
        // temperature/band after being told which subscriber to wake, the
        // same way turf/object Band watches already work.
        let out = self.sim.drain(self.bodies);
        for w in out.wakes() {
            self.wakes.push(*w);
        }
    }

    /// Runs `n` frames, waiting for each (tests, and DM's own tick pacing).
    /// Matches [`crate::world::HeatWorld::run_frames`]'s pipeline exactly:
    /// commands queued by an accessor above are only visible to a frame's
    /// task once `begin_tick()` moves them into the idle world, so a
    /// `submit()` right before a single `dispatch_frame()` with no
    /// `wait_for_frame()`/`begin_tick()` around it would need one extra
    /// frame before it took effect.
    pub fn run_frames(&mut self, n: u32) {
        for _ in 0..n {
            self.sim.wait_for_frame();
            self.sim.begin_tick();
            self.sim.dispatch_frame();
            self.sim.wait_for_frame();
        }
        self.sim.wait_for_frame();
        self.sim.begin_tick();
        self.collect();
    }

    /// Simulated seconds per frame (for a DM-side accumulator, matching
    /// [`crate::world::HeatWorld::dims`]'s pattern of exposing its own
    /// construction-time constant).
    #[must_use]
    pub const fn dt(&self) -> f32 {
        self.dt
    }

    /// Takes the wakes collected so far.
    pub fn drain_wakes(&mut self) -> Vec<Wake> {
        std::mem::take(&mut self.wakes)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn world() -> MobHeatWorld {
        MobHeatWorld::new(1.0).unwrap()
    }

    /// The integrator's own conservation: energy put in through an external
    /// flux equals the temperature rise you get out (`ΔT = ΣW·dt / C`),
    /// with no coupling to lose or gain energy against (no metabolic term,
    /// no ambient gap, no thermoregulation).
    #[test]
    fn external_heat_conserves_energy_one_to_one() {
        let mut w = world();
        let h = w
            .create_body(MobHeatConfig {
                capacity: 1000.0,
                temperature: 300.0,
                setpoint: 300.0, // no thermoreg correction
                ambient: 300.0,  // no conduction
                ..Default::default()
            })
            .unwrap();
        w.body_heat_add(h, 0, 50.0).unwrap(); // 50 W
        w.run_frames(10); // 10 s @ dt=1
        let t = w.temperature(h).unwrap();
        // 50 W * 10 s / 1000 J/K = 0.5 K.
        assert!((t - 300.5).abs() < 1e-3, "t={t}");
    }

    /// Several external sources sum instead of clobbering each other.
    #[test]
    fn external_sources_do_not_clobber_each_other() {
        let mut w = world();
        let h = w
            .create_body(MobHeatConfig {
                capacity: 100.0,
                temperature: 300.0,
                setpoint: 300.0,
                ambient: 300.0,
                ..Default::default()
            })
            .unwrap();
        w.body_heat_add(h, 0, 10.0).unwrap();
        w.body_heat_add(h, 1, 20.0).unwrap();
        w.run_frames(1);
        let t = w.temperature(h).unwrap();
        assert!((t - 300.3).abs() < 1e-3, "t={t}"); // (10+20)/100
        w.body_heat_add(h, 0, 0.0).unwrap(); // clear source 0 only
        w.run_frames(1);
        let t2 = w.temperature(h).unwrap();
        assert!((t2 - 300.5).abs() < 1e-3, "t2={t2}"); // +20/100
    }

    /// Thermoregulation converges toward the setpoint when it has the
    /// capacity to.
    #[test]
    fn thermoregulation_converges_to_setpoint() {
        let mut w = world();
        let h = w
            .create_body(MobHeatConfig {
                capacity: 3500.0,
                temperature: 305.0,
                setpoint: 310.15,
                ambient: 305.0, // no help/hindrance from the environment
                shiver_capacity_w: 200.0,
                sweat_capacity_w: 200.0,
                ..Default::default()
            })
            .unwrap();
        w.run_frames(600); // 10 minutes
        let t = w.temperature(h).unwrap();
        assert!((t - 310.15).abs() < 0.05, "did not converge: t={t}");
    }

    /// The controller never exceeds its declared capacity, however far off
    /// setpoint the body starts.
    #[test]
    fn thermoregulation_never_exceeds_its_capacity() {
        let mut w = world();
        let h = w
            .create_body(MobHeatConfig {
                capacity: 100.0,
                temperature: 200.0, // far below setpoint
                setpoint: 310.0,
                ambient: 200.0,
                shiver_capacity_w: 5.0, // small on purpose
                sweat_capacity_w: 5.0,
                ..Default::default()
            })
            .unwrap();
        w.run_frames(1);
        let t = w.temperature(h).unwrap();
        // At most 5 W * 1 s / 100 J/K = 0.05 K in one frame, however large
        // the setpoint error is (f32 rounding gets a small allowance).
        assert!(t - 200.0 <= 0.05 + 1e-4, "overshot capacity: t={t}");
    }

    /// `time_scale = 0` freezes the body exactly, even with every flux term
    /// nonzero.
    #[test]
    fn time_scale_zero_freezes_the_body() {
        let mut w = world();
        let h = w
            .create_body(MobHeatConfig {
                capacity: 100.0,
                temperature: 300.0,
                metabolic_watts: 100.0,
                setpoint: 400.0,
                ambient: 500.0,
                shiver_capacity_w: 200.0,
                sweat_capacity_w: 200.0,
                time_scale: 0.0,
                ..Default::default()
            })
            .unwrap();
        w.body_heat_add(h, 0, 1000.0).unwrap();
        w.run_frames(50);
        let t = w.temperature(h).unwrap();
        assert_eq!(t, 300.0, "a frozen body must not drift at all");
    }

    /// Comfort-band crossings arrive as ordinary watch wakes: one at
    /// registration (the starting band) and one per crossing, via the
    /// same mechanism turf/object heat watches use (a `Band` condition
    /// carries no payload, so the caller re-reads the temperature after
    /// being woken -- see `set_bands`'s doc comment).
    #[test]
    fn comfort_bands_fire_on_registration_and_on_crossing() {
        let mut w = world();
        let h = w
            .create_body(MobHeatConfig {
                capacity: 100.0,
                temperature: 300.0,
                setpoint: 300.0,
                ambient: 300.0,
                ..Default::default()
            })
            .unwrap();
        w.set_bands(h, 3, Lane::Normal, &[305.0, 315.0]).unwrap();
        w.run_frames(1);
        let first = w.drain_wakes();
        assert_eq!(
            first.iter().filter(|x| x.subscriber == 3).count(),
            1,
            "reports its starting band once: {first:?}"
        );
        assert!(
            w.temperature(h).unwrap() < 305.0,
            "300 K starts below both levels"
        );

        w.body_heat_add(h, 0, 1000.0).unwrap(); // 10 K/s
        w.run_frames(1);
        let crossed = w.drain_wakes();
        assert!(
            crossed.iter().any(|x| x.subscriber == 3),
            "should wake on crossing the first band: {crossed:?}"
        );
        assert!(
            w.temperature(h).unwrap() >= 305.0,
            "should have crossed 305 K in one 10 K/s frame"
        );
    }

    /// A released handle is rejected by every accessor, not silently
    /// resolved against whatever now occupies its slot.
    #[test]
    fn a_released_handle_is_rejected() {
        let mut w = world();
        let h = w.create_body(MobHeatConfig::default()).unwrap();
        w.release(h).unwrap();
        assert!(w.temperature(h).is_none());
        assert!(w.set_setpoint(h, 300.0).is_err());
        assert!(w.body_heat_add(h, 0, 1.0).is_err());
    }
}
