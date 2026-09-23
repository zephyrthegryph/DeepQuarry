//! The thermal regulator primitive (`simulation.md` §7, `temperature.md`
//! §6): drive a controlled body towards a target temperature with at most
//! `max_power` watts of electrical work.
//!
//! - **Heating.** A resistive heater turns its work into heat one for one
//!   (B10: never more than it draws). A heat-pump heater moves `W · COP_h`
//!   into the controlled body, drawing `W · (COP_h − 1)` from the other side.
//! - **Cooling.** A heat pump moves `Q = W · COP_c` out of the controlled body
//!   and rejects `Q + W` to the hot side (B9: the heat is never deleted).
//!   `COP_c = η · Tc / (Th − Tc)` (a fraction `η` of Carnot), capped at
//!   `max_cop`.
//!
//! Every step satisfies `work + heat taken from the source side = heat put
//! into the sink side` exactly: [`RegulatorStep::balance`] is zero up to
//! rounding. The step never overshoots the target: the heat moved is capped
//! at what brings the controlled body exactly to it.
//!
//! H4 migrates the thermomachines, space heaters, cryo, suit coolers and
//! rigs onto this; M4 only builds and tests it.

use vg_core::thermo::ThermalBody;
use vg_core::units::{HeatCapacity, Kelvin};

/// Which directions a regulator may drive.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum RegulatorMode {
    Heat,
    Cool,
    Both,
}

/// A regulator's settings.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Regulator {
    /// K.
    pub target: f32,
    /// Largest electrical draw, W (DM scales it by part rating).
    pub max_power: f32,
    pub mode: RegulatorMode,
    /// Fraction of the Carnot COP the pump achieves, 0..1.
    pub carnot_fraction: f32,
    /// Upper bound on either COP (a pump across a tiny gap is not free).
    pub max_cop: f32,
    /// Heating by resistance (COP 1) instead of pumping heat in.
    pub resistive_heating: bool,
    /// No action within this of the target, K.
    pub deadband: f32,
}

impl Default for Regulator {
    fn default() -> Self {
        Self {
            target: 293.15,
            max_power: 0.0,
            mode: RegulatorMode::Both,
            carnot_fraction: 0.5,
            max_cop: 10.0,
            resistive_heating: true,
            deadband: 0.05,
        }
    }
}

/// One step's energy flows, J. Positive `moved` heats the controlled body.
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct RegulatorStep {
    /// Electrical work drawn (≥ 0).
    pub work: f32,
    /// Heat into the controlled body (negative: out of it).
    pub moved: f32,
    /// Heat into the other side (negative: drawn from it). For cooling this
    /// is the rejected heat `Q + W`; for pumped heating, `−(Q − W)`.
    pub other: f32,
}

impl RegulatorStep {
    /// `work − moved − other`: zero for every step (energy conservation).
    #[must_use]
    pub fn balance(&self) -> f64 {
        f64::from(self.work) - f64::from(self.moved) - f64::from(self.other)
    }
}

/// Coefficient of performance of a cooler lifting heat from `cold` to `hot`.
#[must_use]
pub fn cooling_cop(cold: f32, hot: f32, carnot_fraction: f32, max_cop: f32) -> f32 {
    let lift = hot - cold;
    if lift <= 0.0 || cold <= 0.0 {
        return max_cop;
    }
    (carnot_fraction.clamp(0.0, 1.0) * cold / lift).clamp(0.0, max_cop)
}

/// Coefficient of performance of a heat pump heating `hot` from `cold`
/// (at least 1: a pump never heats worse than a resistor).
#[must_use]
pub fn heating_cop(hot: f32, cold: f32, carnot_fraction: f32, max_cop: f32) -> f32 {
    let lift = hot - cold;
    if lift <= 0.0 || hot <= 0.0 {
        return max_cop.max(1.0);
    }
    (carnot_fraction.clamp(0.0, 1.0) * hot / lift).clamp(1.0, max_cop.max(1.0))
}

impl Regulator {
    /// The flows for one step of `dt` seconds. `controlled` is driven to the
    /// target; `other` is the hot side when cooling and the source when
    /// pump-heating (a reservoir passes an infinite capacity). Nothing is
    /// applied: see [`apply`](Self::apply).
    #[must_use]
    pub fn step(&self, controlled: ThermalBody, other: ThermalBody, dt: f32) -> RegulatorStep {
        // `ThermalBody`'s fields are `f64` (`vg_core::units`, "units
        // everywhere"); this function's own public inputs/outputs stay
        // `f32` (a regulator's settings and one step's flows are small,
        // display-facing numbers, not accumulated state), so the boundary
        // conversion happens here rather than changing this type's API.
        let (t, c) = (controlled.temperature.0, controlled.capacity.0);
        let budget = f64::from(self.max_power.max(0.0)) * f64::from(dt.max(0.0));
        if budget <= 0.0 || c <= 0.0 || !t.is_finite() {
            return RegulatorStep::default();
        }
        let gap = f64::from(self.target) - t;
        if gap.abs() <= f64::from(self.deadband) {
            return RegulatorStep::default();
        }
        let needed = gap.abs() * c;
        if gap > 0.0 && self.mode != RegulatorMode::Cool {
            if self.resistive_heating {
                let q = budget.min(needed);
                return RegulatorStep {
                    work: q as f32,
                    moved: q as f32,
                    other: 0.0,
                };
            }
            #[allow(clippy::cast_possible_truncation)]
            let cop = f64::from(heating_cop(
                t as f32,
                other.temperature.0 as f32,
                self.carnot_fraction,
                self.max_cop,
            ));
            let q = (budget * cop).min(needed);
            let w = q / cop;
            return RegulatorStep {
                work: w as f32,
                moved: q as f32,
                other: (w - q) as f32,
            };
        }
        if gap < 0.0 && self.mode != RegulatorMode::Heat {
            #[allow(clippy::cast_possible_truncation)]
            let cop = f64::from(cooling_cop(
                t as f32,
                other.temperature.0 as f32,
                self.carnot_fraction,
                self.max_cop,
            ));
            if cop <= 0.0 {
                return RegulatorStep::default();
            }
            let q = (budget * cop).min(needed);
            let w = q / cop;
            return RegulatorStep {
                work: w as f32,
                moved: -q as f32,
                other: (q + w) as f32,
            };
        }
        RegulatorStep::default()
    }

    /// Applies a step to the two bodies (energy form, so the books balance
    /// with the work drawn). Returns the step.
    pub fn apply(step: RegulatorStep, controlled: &mut ThermalBody, other: &mut ThermalBody) {
        add_energy(controlled, step.moved);
        add_energy(other, step.other);
    }
}

fn add_energy(body: &mut ThermalBody, joules: f32) {
    let c = body.capacity.0;
    if c.is_finite() && c > 0.0 {
        body.temperature = Kelvin(body.temperature.0 + f64::from(joules) / c);
    }
}

/// A reservoir side for [`Regulator::step`].
#[must_use]
pub fn reservoir(temperature: f32) -> ThermalBody {
    ThermalBody::new(HeatCapacity(f64::INFINITY), Kelvin::from(temperature))
}

#[cfg(test)]
mod tests {
    use super::*;
    use proptest::prelude::*;

    fn body(c: f32, t: f32) -> ThermalBody {
        ThermalBody::new(HeatCapacity::from(c), Kelvin::from(t))
    }

    #[test]
    fn a_resistive_heater_never_outputs_more_than_it_draws() {
        let r = Regulator {
            target: 350.0,
            max_power: 1_000.0,
            ..Regulator::default()
        };
        let s = r.step(body(10_000.0, 300.0), reservoir(300.0), 2.0);
        assert_eq!(s.work, 2_000.0);
        assert_eq!(s.moved, 2_000.0);
        assert_eq!(s.balance(), 0.0);
    }

    #[test]
    fn a_cooler_rejects_heat_plus_work_to_the_hot_side() {
        let r = Regulator {
            target: 200.0,
            max_power: 1_000.0,
            ..Regulator::default()
        };
        let mut cold = body(10_000.0, 250.0);
        let mut hot = body(50_000.0, 300.0);
        let (e0, e1) = (cold.energy().0, hot.energy().0);
        let s = r.step(cold, hot, 1.0);
        // COP = 0.5 * 250 / 50 = 2.5: 2500 J lifted for 1000 J of work.
        assert!((s.moved + 2_500.0).abs() < 1e-3, "{s:?}");
        assert!((s.other - 3_500.0).abs() < 1e-3);
        Regulator::apply(s, &mut cold, &mut hot);
        let de = (cold.energy().0 - e0) + (hot.energy().0 - e1);
        assert!(
            (de - f64::from(s.work)).abs() < 0.5,
            "heat in = work: {de} vs {}",
            s.work
        );
    }

    #[test]
    fn it_stops_exactly_at_the_target() {
        let r = Regulator {
            target: 299.0,
            max_power: 1e9,
            ..Regulator::default()
        };
        let mut c = body(100.0, 300.0);
        let mut h = reservoir(300.0);
        let s = r.step(c, h, 1.0);
        Regulator::apply(s, &mut c, &mut h);
        assert!((c.temperature.0 - 299.0).abs() < 1e-3);
        assert_eq!(r.step(c, h, 1.0), RegulatorStep::default());
    }

    proptest! {
        /// Work in plus heat moved equals heat out, in every configuration.
        #[test]
        fn every_step_conserves_energy(
            t in 3.0f32..2000.0, other_t in 3.0f32..2000.0, target in 3.0f32..2000.0,
            c in 1.0f32..1e6, oc in 1.0f32..1e7,
            power in 0.0f32..1e6, dt in 0.01f32..10.0,
            eta in 0.0f32..1.0, max_cop in 0.5f32..20.0,
            resistive in any::<bool>(), mode in 0u8..3,
        ) {
            let r = Regulator {
                target, max_power: power, carnot_fraction: eta, max_cop,
                resistive_heating: resistive,
                mode: [RegulatorMode::Heat, RegulatorMode::Cool, RegulatorMode::Both][usize::from(mode)],
                deadband: 0.0,
            };
            let s = r.step(body(c, t), body(oc, other_t), dt);
            prop_assert!(s.work >= 0.0);
            prop_assert!(f64::from(s.work) <= f64::from(power) * f64::from(dt) * (1.0 + 1e-6));
            prop_assert!(s.balance().abs() <= 1e-6 * f64::from(s.work.abs().max(s.moved.abs()).max(1.0)),
                "{s:?}");
            // Never overshoots the target.
            let after = t + s.moved / c;
            if t < target { prop_assert!(after <= target + target * 1e-5); }
            if t > target { prop_assert!(after >= target - target * 1e-5); }
        }
    }
}
