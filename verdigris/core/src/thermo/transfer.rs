//! Conserved heat transfer between reservoirs (`temperature.md` §2.3): the
//! **one** primitive every heat flow in the workspace goes through.
//!
//! A *reservoir* is anything with a temperature and a heat capacity that can
//! take or give energy: a gas mixture (main, pipe region, turf air), a heat
//! body, a solid turf cell, or an outright infinite reservoir (space, an
//! immutable mixture). The caller adapts its storage through [`Reservoirs`];
//! this module owns the maths.
//!
//! - [`transfer`] moves `q` joules from `a` to `b` as one operation: `-q` on
//!   `a`, `+q` on `b`, capped so neither side passes absolute zero. Nothing
//!   else ever writes a reservoir's energy, so conservation holds by
//!   construction.
//! - [`Edge`]s are persistent links integrated each frame by [`step_edge`]:
//!   - [`EdgeKind::Link`]: conduction plus an optional radiative term,
//!     integrated with the exact pair solution `ΔT·h·(1 − e^(−G(1/C₁+1/C₂)dt))`
//!     (the radiative term is linearised at the pair's current temperatures,
//!     `G_r = εσA(T₁²+T₂²)(T₁+T₂)`, then integrated the same way), so any
//!     `dt` is stable and a pair never overshoots equilibrium;
//!   - [`EdgeKind::Pump`]: a heat pump/heater through
//!     [`super::Regulator::step`] (Carnot-bounded COP), its electrical work
//!     booked as external work in;
//!   - [`EdgeKind::Engine`]: a heat engine between a hot and a cold side,
//!     `η` capped at Carnot, `η·q` booked as external work out (electric
//!     output for the power domain).
//! - [`Books`] records every transfer and every external work in or out per
//!   frame; [`Books::check`] is the debug assertion that a frame's energy
//!   change equals its booked external work.

use super::{Regulator, ThermalBody};
use crate::units::{HeatCapacity, Kelvin, Seconds};

/// Stefan–Boltzmann constant, W/(m²·K⁴).
pub const STEFAN_BOLTZMANN: f64 = 5.670_374_419e-8;

/// A reservoir's state for a transfer.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct State {
    /// K.
    pub temperature: f64,
    /// J/K; `f64::INFINITY` for an outright reservoir (space, an immutable
    /// mixture), whose temperature never changes and whose energy is outside
    /// the books' conserved total.
    pub capacity: f64,
    /// The lowest temperature the storage holds, K: absolute zero for a
    /// plain body, TCMB for a gas or a heat body (whose storage clamps
    /// there). A transfer never takes a side below it.
    pub floor: f64,
}

impl State {
    #[must_use]
    pub const fn new(temperature: f64, capacity: f64) -> Self {
        Self { temperature, capacity, floor: 0.0 }
    }

    #[must_use]
    pub fn is_infinite(self) -> bool {
        !self.capacity.is_finite()
    }

    /// Energy above the floor, J: what the side can give (infinite for a
    /// reservoir).
    #[must_use]
    pub fn energy(self) -> f64 {
        if self.is_infinite() {
            f64::INFINITY
        } else {
            (self.capacity * (self.temperature - self.floor.max(0.0))).max(0.0)
        }
    }

    fn body(self) -> ThermalBody {
        ThermalBody::new(HeatCapacity(self.capacity), Kelvin(self.temperature))
    }
}

/// Storage the transfer primitive reads and writes. `R` names a reservoir.
pub trait Reservoirs<R: Copy> {
    /// The reservoir's state, or `None` if it no longer exists (a deleted
    /// mixture, a released body): an edge to it does nothing.
    fn state(&self, r: R) -> Option<State>;
    /// Adds `joules` (negative removes) to a finite reservoir. Only
    /// [`transfer`] and [`external`] call this, with amounts already capped
    /// so the reservoir stays at or above absolute zero; never called for an
    /// infinite reservoir.
    fn add(&mut self, r: R, joules: f64);
}

/// What one frame booked: every internal transfer and every external flow.
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct Books {
    /// J moved between two finite reservoirs (absolute sum; informative).
    pub transferred: f64,
    /// J of electrical work put in (pumps, heaters).
    pub work_in: f64,
    /// J of electrical work taken out (engines).
    pub work_out: f64,
    /// J that entered from outside the finite set: an infinite reservoir
    /// giving heat, or a declared external source (a reaction, a spell).
    pub external_in: f64,
    /// J that left to outside the finite set (radiated to space, dumped
    /// into an infinite reservoir, a declared external sink).
    pub external_out: f64,
}

impl Books {
    /// The change in the finite reservoirs' total energy these books account
    /// for.
    #[must_use]
    pub fn expected_delta(&self) -> f64 {
        self.work_in - self.work_out + self.external_in - self.external_out
    }

    pub fn absorb(&mut self, other: &Self) {
        self.transferred += other.transferred;
        self.work_in += other.work_in;
        self.work_out += other.work_out;
        self.external_in += other.external_in;
        self.external_out += other.external_out;
    }

    /// The debug assertion: the finite reservoirs' total moved from `before`
    /// to `after` by exactly what these books record (within a relative
    /// tolerance for float rounding). `Err(unexplained joules)` otherwise.
    ///
    /// # Errors
    /// The unexplained energy, when the books do not account for the change.
    pub fn check(&self, before: f64, after: f64) -> Result<(), f64> {
        let unexplained = (after - before) - self.expected_delta();
        let scale = before.abs().max(after.abs()) + self.transferred + self.work_in + self.work_out + self.external_in + self.external_out;
        if unexplained.abs() <= 1e-9 * scale + 1e-6 { Ok(()) } else { Err(unexplained) }
    }

    /// Books the reservoir side of a transfer that crossed the finite set's
    /// boundary.
    fn boundary(&mut self, sa: State, sb: State, q: f64) {
        match (sa.is_infinite(), sb.is_infinite()) {
            (false, false) => self.transferred += q.abs(),
            (true, false) => {
                // From an infinite source into a finite one: +q enters.
                if q > 0.0 { self.external_in += q } else { self.external_out -= q }
            }
            (false, true) => {
                if q > 0.0 { self.external_out += q } else { self.external_in -= q }
            }
            (true, true) => {}
        }
    }
}

/// The largest `q` (J, `a` → `b`, sign included) that keeps both sides at or
/// above absolute zero.
#[must_use]
pub fn cap(sa: State, sb: State, q: f64) -> f64 {
    if !q.is_finite() {
        return 0.0;
    }
    if q > 0.0 { q.min(sa.energy()) } else { q.max(-sb.energy()) }
}

/// Moves `q` J from `a` to `b` in one operation (`-q` on `a`, `+q` on `b`),
/// capped by [`cap`], and books it. Returns the joules actually moved.
pub fn transfer<R: Copy>(res: &mut impl Reservoirs<R>, books: &mut Books, a: R, b: R, q: f64) -> f64 {
    let (Some(sa), Some(sb)) = (res.state(a), res.state(b)) else {
        return 0.0;
    };
    let q = cap(sa, sb, q);
    if q == 0.0 {
        return 0.0;
    }
    if !sa.is_infinite() {
        res.add(a, -q);
    }
    if !sb.is_infinite() {
        res.add(b, q);
    }
    books.boundary(sa, sb, q);
    q
}

/// Adds `q` J to `r` from outside the simulation (a declared external
/// source: a reaction, a spell, an admin; negative: an external sink),
/// capped at absolute zero, and books it. Returns the joules applied.
pub fn external<R: Copy>(res: &mut impl Reservoirs<R>, books: &mut Books, r: R, q: f64) -> f64 {
    let Some(s) = res.state(r) else { return 0.0 };
    if s.is_infinite() || !q.is_finite() {
        return 0.0;
    }
    let q = q.max(-s.energy());
    if q == 0.0 {
        return 0.0;
    }
    res.add(r, q);
    if q > 0.0 { books.external_in += q } else { books.external_out -= q }
    q
}

/// A persistent edge's behaviour.
#[derive(Clone, Copy, Debug, PartialEq)]
pub enum EdgeKind {
    /// Conduction at `conductance` W/K, plus radiation `εσA(T⁴_a − T⁴_b)`
    /// when `emissivity * area > 0` (`area` m²).
    Link { conductance: f64, emissivity: f64, area: f64 },
    /// A heat pump driving `a` (the controlled side) toward the regulator's
    /// target, rejecting to or drawing from `b`. Its work is booked in.
    Pump(Regulator),
    /// A heat engine: heat flows from the hotter side to the colder through
    /// `conductance` W/K, and `efficiency` of it (capped at Carnot,
    /// `1 − T_cold/T_hot`) leaves as work. Its work is booked out.
    Engine { efficiency: f64, conductance: f64 },
}

/// A persistent edge between two reservoirs.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Edge<R> {
    pub a: R,
    pub b: R,
    pub kind: EdgeKind,
}

/// One edge's flows over one step, J.
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct Flow {
    /// Heat that left `a` (negative: `a` gained).
    pub from_a: f64,
    /// Heat that entered `b` (negative: `b` lost).
    pub into_b: f64,
    /// Electrical work in (a pump).
    pub work_in: f64,
    /// Electrical work out (an engine).
    pub work_out: f64,
}

/// The radiative conductance of a pair linearised at its temperatures,
/// W/K: `εσA(T_a² + T_b²)(T_a + T_b)`, which gives exactly
/// `εσA(T_a⁴ − T_b⁴)` times `(T_a − T_b)` at those temperatures.
#[must_use]
pub fn radiative_conductance(emissivity: f64, area: f64, ta: f64, tb: f64) -> f64 {
    let (ta, tb) = (ta.max(0.0), tb.max(0.0));
    (emissivity.max(0.0) * area.max(0.0) * STEFAN_BOLTZMANN * (ta * ta + tb * tb) * (ta + tb)).max(0.0)
}

/// Joules moved `a` → `b` by conductance `g` over `dt`: the exact pair
/// solution [`super::pair_exchange`] (any `dt`, never past equilibrium).
#[must_use]
pub fn link_heat(sa: State, sb: State, g: f64, dt: f64) -> f64 {
    super::pair_exchange(sa.body(), sb.body(), g, Seconds(dt)).0
}

/// Integrates one edge over `dt` seconds, applying its flows to `res` and
/// booking them in `books`.
pub fn step_edge<R: Copy>(res: &mut impl Reservoirs<R>, books: &mut Books, edge: &Edge<R>, dt: f64) -> Flow {
    if !(dt > 0.0) {
        return Flow::default();
    }
    let (Some(sa), Some(sb)) = (res.state(edge.a), res.state(edge.b)) else {
        return Flow::default();
    };
    match edge.kind {
        EdgeKind::Link { conductance, emissivity, area } => {
            let g = conductance.max(0.0) + radiative_conductance(emissivity, area, sa.temperature, sb.temperature);
            let q = transfer(res, books, edge.a, edge.b, link_heat(sa, sb, g, dt));
            Flow { from_a: q, into_b: q, ..Flow::default() }
        }
        EdgeKind::Pump(reg) => pump(res, books, edge, reg, sa, sb, dt),
        EdgeKind::Engine { efficiency, conductance } => engine(res, books, edge, efficiency, conductance, sa, sb, dt),
    }
}

#[allow(clippy::cast_possible_truncation)]
fn pump<R: Copy>(res: &mut impl Reservoirs<R>, books: &mut Books, edge: &Edge<R>, reg: Regulator, sa: State, sb: State, dt: f64) -> Flow {
    let step = reg.step(sa.body(), sb.body(), dt as f32);
    let (mut work, mut moved, mut other) = (f64::from(step.work), f64::from(step.moved), f64::from(step.other));
    if work <= 0.0 && moved == 0.0 && other == 0.0 {
        return Flow::default();
    }
    // Scale the whole step so neither side passes absolute zero (a pump
    // cannot draw more heat than a side holds); the balance
    // `work = moved + other` survives the scaling.
    let mut scale: f64 = 1.0;
    if moved < 0.0 && !sa.is_infinite() {
        scale = scale.min(sa.energy() / -moved);
    }
    if other < 0.0 && !sb.is_infinite() {
        scale = scale.min(sb.energy() / -other);
    }
    let scale = scale.clamp(0.0, 1.0);
    moved *= scale;
    other *= scale;
    // The regulator reports in f32; book the work as exactly what was
    // applied so the balance `work = moved + other` holds in f64.
    work = moved + other;
    // Apply as two transfers through the work "terminal": work enters, then
    // the heat lands where the regulator says. Expressed directly: +moved on
    // a, +other on b, work booked in; moved + other == work.
    if !sa.is_infinite() {
        res.add(edge.a, moved);
    } else if moved != 0.0 {
        if moved < 0.0 { books.external_in -= moved } else { books.external_out += moved }
    }
    if !sb.is_infinite() {
        res.add(edge.b, other);
    } else if other != 0.0 {
        if other < 0.0 { books.external_in -= other } else { books.external_out += other }
    }
    books.work_in += work;
    books.transferred += moved.abs().min(other.abs());
    Flow { from_a: -moved, into_b: other, work_in: work, work_out: 0.0 }
}

#[allow(clippy::too_many_arguments)]
fn engine<R: Copy>(res: &mut impl Reservoirs<R>, books: &mut Books, edge: &Edge<R>, efficiency: f64, conductance: f64, sa: State, sb: State, dt: f64) -> Flow {
    // Heat flows hot → cold through the conductance; `a` may be either side.
    let q = link_heat(sa, sb, conductance.max(0.0), dt);
    if q == 0.0 {
        return Flow::default();
    }
    let (hot, cold) = if q > 0.0 { (sa, sb) } else { (sb, sa) };
    let carnot = if hot.temperature > 0.0 { (1.0 - cold.temperature / hot.temperature).max(0.0) } else { 0.0 };
    let eta = efficiency.clamp(0.0, 1.0).min(carnot);
    let taken = cap(hot, cold, q.abs());
    let work = eta * taken;
    let delivered = taken - work;
    let (hot_r, cold_r) = if q > 0.0 { (edge.a, edge.b) } else { (edge.b, edge.a) };
    if hot.is_infinite() {
        books.external_in += taken;
    } else {
        res.add(hot_r, -taken);
    }
    if cold.is_infinite() {
        books.external_out += delivered;
    } else {
        res.add(cold_r, delivered);
    }
    books.work_out += work;
    books.transferred += delivered;
    let sign = q.signum();
    Flow { from_a: sign * taken, into_b: sign * delivered, work_in: 0.0, work_out: work }
}

/// Plain reservoirs by index: the reference [`Reservoirs`] for tests and
/// host-only simulations.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct Plain(pub Vec<State>);

impl Plain {
    /// The finite reservoirs' total energy.
    #[must_use]
    pub fn total(&self) -> f64 {
        self.0.iter().filter(|s| !s.is_infinite()).map(|s| s.capacity * s.temperature).sum()
    }
}

impl Reservoirs<usize> for Plain {
    fn state(&self, r: usize) -> Option<State> {
        self.0.get(r).copied()
    }

    fn add(&mut self, r: usize, joules: f64) {
        if let Some(s) = self.0.get_mut(r) {
            if s.capacity > 0.0 && s.capacity.is_finite() {
                s.temperature = ((s.capacity * s.temperature + joules) / s.capacity).max(0.0);
            }
        }
    }
}

/// Steps every edge once over `dt` (in order, each applied before the
/// next reads), returning the frame's books. In debug builds asserts the
/// books explain the change in the finite total.
pub fn step_all<R: Copy, T: Reservoirs<R>>(res: &mut T, edges: &[Edge<R>], dt: f64, total: impl Fn(&T) -> f64) -> (Books, Vec<Flow>) {
    let mut books = Books::default();
    let before = if cfg!(debug_assertions) { total(res) } else { 0.0 };
    let flows = edges.iter().map(|e| step_edge(res, &mut books, e, dt)).collect();
    if cfg!(debug_assertions) {
        let after = total(res);
        debug_assert!(books.check(before, after).is_ok(), "heat books do not balance: {:?} ({before} -> {after})", books.check(before, after));
    }
    (books, flows)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::thermo::RegulatorMode;
    use proptest::prelude::*;

    fn st(t: f64, c: f64) -> State {
        State::new(t, c)
    }

    fn total(r: &Plain) -> f64 {
        r.total()
    }

    #[test]
    fn a_transfer_is_capped_at_absolute_zero() {
        let mut p = Plain(vec![st(10.0, 1.0), st(300.0, 1.0)]);
        let mut books = Books::default();
        let q = transfer(&mut p, &mut books, 0, 1, 1e9);
        assert!((q - 10.0).abs() < 1e-9);
        assert_eq!(p.0[0].temperature, 0.0);
        assert!((p.total() - 310.0).abs() < 1e-9);
    }

    #[test]
    fn a_link_reaches_the_exact_exponential() {
        let mut p = Plain(vec![st(400.0, 10.0), st(300.0, 30.0)]);
        let e = Edge { a: 0, b: 1, kind: EdgeKind::Link { conductance: 2.0, emissivity: 0.0, area: 0.0 } };
        let mut books = Books::default();
        step_edge(&mut p, &mut books, &e, 5.0);
        let inv = 1.0 / 10.0 + 1.0 / 30.0;
        let gap = 100.0 * (-2.0 * inv * 5.0f64).exp();
        assert!(((p.0[0].temperature - p.0[1].temperature) - gap).abs() < 1e-9);
    }

    #[test]
    fn radiation_to_space_cools_but_never_below_the_sky() {
        let mut p = Plain(vec![st(400.0, 100.0), st(2.7, f64::INFINITY)]);
        let e = Edge { a: 0, b: 1, kind: EdgeKind::Link { conductance: 0.0, emissivity: 0.9, area: 1.0 } };
        let mut books = Books::default();
        for _ in 0..100 {
            step_edge(&mut p, &mut books, &e, 1e6);
        }
        assert!(p.0[0].temperature >= 2.7 - 1e-9 && p.0[0].temperature < 3.0);
        assert!(books.external_out > 0.0);
    }

    #[test]
    fn an_engine_never_beats_carnot_and_books_its_work() {
        let mut p = Plain(vec![st(600.0, 1000.0), st(300.0, 1000.0)]);
        let e = Edge { a: 0, b: 1, kind: EdgeKind::Engine { efficiency: 0.9, conductance: 50.0 } };
        let before = p.total();
        let mut books = Books::default();
        let f = step_edge(&mut p, &mut books, &e, 1.0);
        assert!(f.work_out > 0.0);
        assert!(f.work_out <= 0.5 * f.from_a + 1e-9, "carnot at 600/300 is 0.5");
        assert!(books.check(before, p.total()).is_ok());
    }

    #[test]
    fn a_pump_cools_against_a_hot_side_and_rejects_q_plus_w() {
        let reg = Regulator { target: 250.0, max_power: 1000.0, mode: RegulatorMode::Cool, ..Regulator::default() };
        let mut p = Plain(vec![st(300.0, 1e4), st(300.0, 1e5)]);
        let e = Edge { a: 0, b: 1, kind: EdgeKind::Pump(reg) };
        let before = p.total();
        let mut books = Books::default();
        let f = step_edge(&mut p, &mut books, &e, 1.0);
        assert!(p.0[0].temperature < 300.0 && p.0[1].temperature > 300.0);
        assert!((f.into_b - (f.from_a + f.work_in)).abs() < 1e-3);
        assert!(books.check(before, p.total()).is_ok());
    }

    #[test]
    fn an_external_source_is_booked() {
        let mut p = Plain(vec![st(300.0, 10.0)]);
        let mut books = Books::default();
        external(&mut p, &mut books, 0, 500.0);
        assert!(books.check(3000.0, p.total()).is_ok());
        external(&mut p, &mut books, 0, -1e9);
        assert_eq!(p.0[0].temperature, 0.0);
    }

    fn edge_kind() -> impl Strategy<Value = EdgeKind> {
        prop_oneof![
            (0.0..1e4f64, 0.0..1.0f64, 0.0..10.0f64).prop_map(|(g, e, a)| EdgeKind::Link { conductance: g, emissivity: e, area: a }),
            (1.0..2000.0f32, 0.0..1e5f32, 0..3u8, any::<bool>()).prop_map(|(t, w, m, r)| EdgeKind::Pump(Regulator {
                target: t,
                max_power: w,
                mode: [RegulatorMode::Heat, RegulatorMode::Cool, RegulatorMode::Both][m as usize],
                resistive_heating: r,
                ..Regulator::default()
            })),
            (0.0..1.0f64, 0.0..1e4f64).prop_map(|(e, g)| EdgeKind::Engine { efficiency: e, conductance: g }),
        ]
    }

    fn network() -> impl Strategy<Value = (Vec<State>, Vec<Edge<usize>>, f64)> {
        (2usize..10)
            .prop_flat_map(|n| {
                let states = prop::collection::vec(
                    prop_oneof![
                        9 => (1.0..5000.0f64, 1e-2..1e7f64).prop_map(|(t, c)| st(t, c)),
                        1 => (2.7..1000.0f64).prop_map(|t| st(t, f64::INFINITY)),
                    ],
                    n,
                );
                let edges = prop::collection::vec((0..n, 0..n, edge_kind()).prop_filter("distinct", |(a, b, _)| a != b).prop_map(|(a, b, kind)| Edge { a, b, kind }), 1..20);
                (states, edges, prop_oneof![Just(1e-3), Just(0.5), Just(2.0), Just(1e3), Just(1e7)])
            })
    }

    proptest! {
        #![proptest_config(ProptestConfig::with_cases(64))]

        /// Random networks of reservoirs and links over 1000 frames: every
        /// frame's change in the finite total equals its booked external
        /// work and boundary flows, and no reservoir goes below zero.
        #[test]
        fn random_networks_conserve_energy_over_1000_frames((states, edges, dt) in network()) {
            let mut p = Plain(states);
            let mut all = Books::default();
            let start = p.total();
            for _ in 0..1000 {
                let before = p.total();
                let (books, _) = step_all(&mut p, &edges, dt, total);
                let after = p.total();
                prop_assert!(books.check(before, after).is_ok(), "frame: {:?}", books.check(before, after));
                prop_assert!(p.0.iter().all(|s| s.temperature >= 0.0 && s.temperature.is_finite()));
                all.absorb(&books);
            }
            prop_assert!(all.check(start, p.total()).is_ok(), "run: {:?}", all.check(start, p.total()));
        }

        /// The exact-exponential link never overshoots for any dt: the gap
        /// keeps its sign and shrinks monotonically.
        #[test]
        fn links_are_stable_for_any_dt(ta in 1.0..5000.0f64, tb in 1.0..5000.0f64, ca in 1e-3..1e9f64, cb in 1e-3..1e9f64, g in 0.0..1e9f64, e in 0.0..1.0f64, dt in 1e-6..1e9f64) {
            let mut p = Plain(vec![st(ta, ca), st(tb, cb)]);
            let edge = Edge { a: 0, b: 1, kind: EdgeKind::Link { conductance: g, emissivity: e, area: 1.0 } };
            let mut gap = ta - tb;
            for _ in 0..50 {
                let mut books = Books::default();
                step_edge(&mut p, &mut books, &edge, dt);
                let now = p.0[0].temperature - p.0[1].temperature;
                prop_assert!(now * gap >= -1e-9 * (ta.max(tb)), "overshoot {gap} -> {now}");
                prop_assert!(now.abs() <= gap.abs() + 1e-9 * ta.max(tb));
                gap = now;
            }
        }
    }
}
