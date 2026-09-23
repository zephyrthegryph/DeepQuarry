//! Exchange kernels: pure pairwise flux laws a [`FieldKind`] composes.
//!
//! Every kernel returns the flux from side `a` to side `b` over `dt`; the
//! framework applies it as `-F` to `a` and `+F` to `b`, so any kernel is
//! conservative by construction. Kernels only have to be *stable*: each one
//! clamps its flux so that one edge on its own never overshoots the pair's
//! equilibrium, and reports a stiffness (1/s) from which the framework picks
//! the sub-step (`dt * faces * stiffness <= 1`, the monotone bound of an
//! explicit scheme).
//!
//! Kernels are also *positive* whatever the sub-step: an edge never takes
//! more than [`Operand::share`] of the donor's content (the framework sets
//! it to one over the number of faces a cell can have, so all edges
//! together can empty a cell but never overdraw it). Under the monotone
//! sub-step this clamp never binds.
//!
//! A reservoir side has an inverse capacity of 0: its intensive state
//! (temperature, concentration, pressure) is used, but the pair's
//! equilibrium is the reservoir's.
//!
//! [`FieldKind`]: super::FieldKind

use std::ops::{Add, AddAssign, Neg};

/// A flux or amount vector of `N` conserved quantities (moles per gas,
/// energy, ...). The usual [`FieldKind::Flux`](super::FieldKind::Flux).
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Amounts<const N: usize>(pub [f32; N]);

impl<const N: usize> Default for Amounts<N> {
    fn default() -> Self {
        Self([0.0; N])
    }
}

impl<const N: usize> Neg for Amounts<N> {
    type Output = Self;
    fn neg(self) -> Self {
        Self(self.0.map(|v| -v))
    }
}

impl<const N: usize> Add for Amounts<N> {
    type Output = Self;
    fn add(mut self, rhs: Self) -> Self {
        self += rhs;
        self
    }
}

impl<const N: usize> AddAssign for Amounts<N> {
    fn add_assign(&mut self, rhs: Self) {
        for (a, b) in self.0.iter_mut().zip(rhs.0) {
            *a += b;
        }
    }
}

impl<const N: usize> Amounts<N> {
    /// Adds each component into `out` as `f64` (for conservation totals).
    pub fn add_to(&self, out: &mut [f64]) {
        for (o, v) in out.iter_mut().zip(self.0) {
            *o += f64::from(v);
        }
    }
}

/// One side of an edge as a kernel sees it.
#[derive(Clone, Copy, Debug)]
pub struct Operand<'a, const N: usize> {
    pub amounts: &'a [f32; N],
    /// Capacity (heat capacity, volume): intensive = amount / capacity.
    pub capacity: f32,
    /// `1 / capacity`, or 0 for a reservoir.
    pub inv_capacity: f32,
    /// The largest fraction of this side's content one edge may remove
    /// (infinite for a reservoir). A kind that sums several kernels splits
    /// it between them.
    pub share: f32,
}

impl<'a, const N: usize> Operand<'a, N> {
    /// The same side with its share scaled (for summing kernels).
    #[must_use]
    pub fn with_share(self, factor: f32) -> Self {
        Self {
            share: self.share * factor,
            ..self
        }
    }
}

/// Limits a flux of component `i` (a to b) to the donor's share.
fn limit_donor<const N: usize>(q: f32, i: usize, a: &Operand<'_, N>, b: &Operand<'_, N>) -> f32 {
    if q > 0.0 {
        q.min((a.amounts[i] * a.share).max(0.0))
    } else {
        q.max(-(b.amounts[i] * b.share).max(0.0))
    }
}

/// Limits `q` so it never exceeds `limit` (same sign) in magnitude.
fn clamp_to(q: f32, limit: f32) -> f32 {
    if !q.is_finite() || !limit.is_finite() {
        return 0.0;
    }
    if q.abs() > limit.abs() { limit } else { q }
}

/// Heat conduction: energy moved from `a` to `b` through `conductance`
/// (W/K) in `dt`, with `amounts[0]` the energy and the capacity the heat
/// capacity. Never moves more than the pair's equalizing energy.
#[must_use]
pub fn conduction(a: Operand<'_, 1>, b: Operand<'_, 1>, conductance: f32, dt: f32) -> f32 {
    let delta = a.amounts[0] / a.capacity - b.amounts[0] / b.capacity;
    let inv = a.inv_capacity + b.inv_capacity;
    if inv <= 0.0 {
        return 0.0;
    }
    limit_donor(clamp_to(conductance * dt * delta, delta / inv), 0, &a, &b)
}

/// Stiffness of [`conduction`] (and [`diffusion`]): `k * (1/Ca + 1/Cb)`.
#[must_use]
pub fn exchange_stiffness(coefficient: f32, a_inv_capacity: f32, b_inv_capacity: f32) -> f32 {
    coefficient * (a_inv_capacity + b_inv_capacity)
}

/// Fickian diffusion of every component: flux_i = `coefficient * dt *
/// (a_i/Va - b_i/Vb)`, each clamped to its pair equilibrium.
#[must_use]
pub fn diffusion<const N: usize>(
    a: Operand<'_, N>,
    b: Operand<'_, N>,
    coefficient: f32,
    dt: f32,
) -> Amounts<N> {
    let inv = a.inv_capacity + b.inv_capacity;
    if inv <= 0.0 {
        return Amounts::default();
    }
    Amounts(std::array::from_fn(|i| {
        let delta = a.amounts[i] / a.capacity - b.amounts[i] / b.capacity;
        limit_donor(clamp_to(coefficient * dt * delta, delta / inv), i, &a, &b)
    }))
}

/// Pressure-driven bulk flow: `conductance * dt * (pa - pb)` carrier units
/// (moles: the sum of the first `carriers` components) move from the
/// high-pressure side, taking every component (including energy) in the
/// upwind side's proportions, at most the upwind side's share of it (a
/// reservoir upwind supplies its proportions without being depleted).
#[must_use]
pub fn pressure_flow<const N: usize>(
    a: Operand<'_, N>,
    pa: f32,
    b: Operand<'_, N>,
    pb: f32,
    carriers: usize,
    conductance: f32,
    dt: f32,
) -> Amounts<N> {
    let dp = pa - pb;
    if !dp.is_finite() || dp == 0.0 || a.inv_capacity + b.inv_capacity <= 0.0 {
        return Amounts::default();
    }
    let (up, sign) = if dp > 0.0 { (a, 1.0) } else { (b, -1.0) };
    let carried: f32 = up.amounts[..carriers.min(N)].iter().sum();
    if carried <= 0.0 {
        return Amounts::default();
    }
    let fraction = (conductance * dt * dp.abs() / carried).min(up.share);
    Amounts(up.amounts.map(|v| sign * v * fraction))
}

/// Stiffness of [`pressure_flow`] for ideal-gas sides, where `dp/dn = p/n`
/// (0 for a reservoir or an empty side).
#[must_use]
pub fn pressure_stiffness(conductance: f32, a_dp_dn: f32, b_dp_dn: f32) -> f32 {
    conductance * (a_dp_dn.max(0.0) + b_dp_dn.max(0.0))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn op(amounts: &[f32; 2], capacity: f32, reservoir: bool) -> Operand<'_, 2> {
        Operand {
            amounts,
            capacity,
            inv_capacity: if reservoir { 0.0 } else { 1.0 / capacity },
            share: if reservoir { f32::INFINITY } else { 0.25 },
        }
    }

    #[test]
    fn kernels_are_antisymmetric() {
        let (x, y) = ([10.0, 3.0], [2.0, 8.0]);
        let (a, b) = (op(&x, 1.0, false), op(&y, 2.0, false));
        assert_eq!(diffusion(a, b, 0.1, 1.0), -diffusion(b, a, 0.1, 1.0));
        assert_eq!(
            pressure_flow(a, 5.0, b, 2.0, 2, 0.1, 1.0),
            -pressure_flow(b, 2.0, a, 5.0, 2, 0.1, 1.0)
        );
        let (e, f) = ([300.0], [100.0]);
        let ea = Operand {
            amounts: &e,
            capacity: 1.0,
            inv_capacity: 1.0,
            share: 0.25,
        };
        let eb = Operand {
            amounts: &f,
            capacity: 1.0,
            inv_capacity: 1.0,
            share: 0.25,
        };
        assert!((conduction(ea, eb, 0.1, 1.0) + conduction(eb, ea, 0.1, 1.0)).abs() < 1e-6);
    }

    #[test]
    fn a_stiff_edge_stops_at_equilibrium_and_never_overdraws() {
        let (e, f) = ([300.0], [100.0]);
        let a = Operand {
            amounts: &e,
            capacity: 1.0,
            inv_capacity: 1.0,
            share: 1.0,
        };
        let b = Operand {
            amounts: &f,
            capacity: 1.0,
            inv_capacity: 1.0,
            share: 1.0,
        };
        // Equalizing energy is 100 J; a huge conductance must not pass it.
        assert_eq!(conduction(a, b, 1e6, 1.0), 100.0);
        // With a quarter share the donor gives at most 75 J.
        assert_eq!(conduction(Operand { share: 0.25, ..a }, b, 1e6, 1.0), 75.0);
    }

    #[test]
    fn a_reservoir_is_never_the_limit() {
        let (x, y) = ([100.0, 0.0], [0.0, 0.0]);
        let space = op(&y, 1.0, true);
        let room = op(&x, 1.0, false);
        // Diffusing into a reservoir: the pair equilibrium is the reservoir's
        // concentration (0), limited only by the room's share.
        assert_eq!(diffusion(room, space, 1e6, 1.0).0[0], 25.0);
        assert_eq!(diffusion(space, space, 1.0, 1.0), Amounts::default());
    }
}
