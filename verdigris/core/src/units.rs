//! SI unit newtypes: the only way a physical quantity crosses a module or
//! FFI boundary (`rust_core.md` §15/§16: "units everywhere"). Backed by
//! `f64`: these values accumulate across many frames/binds over a round,
//! and the memory cost of a handful of scalar fields per domain state is
//! negligible next to per-cell/per-entity storage (`rust_core.md` §5's
//! `f32` policy is about *that* bulk data, not these).

use std::iter::Sum;
use std::ops::{Add, AddAssign, Div, Mul, Neg, Sub, SubAssign};

macro_rules! unit {
    ($(#[$meta:meta])* $name:ident, $symbol:literal) => {
        $(#[$meta])*
        #[derive(Clone, Copy, Debug, Default, PartialEq, PartialOrd)]
        #[repr(transparent)]
        pub struct $name(pub f64);

        impl $name {
            pub const ZERO: Self = Self(0.0);
            pub const SYMBOL: &'static str = $symbol;

            #[must_use]
            pub const fn get(self) -> f64 {
                self.0
            }

            #[must_use]
            pub fn max(self, other: Self) -> Self {
                Self(self.0.max(other.0))
            }

            #[must_use]
            pub fn min(self, other: Self) -> Self {
                Self(self.0.min(other.0))
            }

            #[must_use]
            pub fn abs(self) -> Self {
                Self(self.0.abs())
            }
        }

        impl Add for $name {
            type Output = Self;
            fn add(self, rhs: Self) -> Self {
                Self(self.0 + rhs.0)
            }
        }
        impl Sub for $name {
            type Output = Self;
            fn sub(self, rhs: Self) -> Self {
                Self(self.0 - rhs.0)
            }
        }
        impl Neg for $name {
            type Output = Self;
            fn neg(self) -> Self {
                Self(-self.0)
            }
        }
        impl AddAssign for $name {
            fn add_assign(&mut self, rhs: Self) {
                self.0 += rhs.0;
            }
        }
        impl SubAssign for $name {
            fn sub_assign(&mut self, rhs: Self) {
                self.0 -= rhs.0;
            }
        }
        impl Mul<f64> for $name {
            type Output = Self;
            fn mul(self, rhs: f64) -> Self {
                Self(self.0 * rhs)
            }
        }
        impl Div<f64> for $name {
            type Output = Self;
            fn div(self, rhs: f64) -> Self {
                Self(self.0 / rhs)
            }
        }
        /// Ratio of two quantities of the same unit.
        impl Div for $name {
            type Output = f64;
            fn div(self, rhs: Self) -> f64 {
                self.0 / rhs.0
            }
        }
        impl Sum for $name {
            fn sum<I: Iterator<Item = Self>>(iter: I) -> Self {
                Self(iter.map(|v| v.0).sum())
            }
        }

        impl From<f32> for $name {
            fn from(v: f32) -> Self {
                Self(f64::from(v))
            }
        }

        #[allow(clippy::cast_possible_truncation)]
        impl From<$name> for f32 {
            fn from(v: $name) -> f32 {
                v.0 as f32
            }
        }
    };
}

unit!(
    /// Temperature.
    Kelvin, "K"
);
unit!(
    /// Energy.
    Joules, "J"
);
unit!(
    /// Pressure.
    Pascals, "Pa"
);
unit!(
    /// Pressure, in kilopascals (gas's native pressure unit; `Pascals` is
    /// the SI base unit above).
    Kpa, "kPa"
);
unit!(
    /// Amount of substance.
    Moles, "mol"
);
unit!(
    /// Power.
    Watts, "W"
);
unit!(
    /// Heat capacity (J/K).
    HeatCapacity, "J/K"
);
unit!(
    /// Volume.
    Liters, "L"
);
unit!(
    /// Duration. Not `std::time::Duration`: this is a *simulated* quantity
    /// (a `dt` or a frame's elapsed time), which is negative-, zero- and
    /// fractional-second-safe and arithmetic like every other unit here,
    /// where `Duration` deliberately isn't.
    Seconds, "s"
);

impl Mul<Kelvin> for HeatCapacity {
    type Output = Joules;
    fn mul(self, rhs: Kelvin) -> Joules {
        Joules(self.0 * rhs.0)
    }
}

impl Mul<HeatCapacity> for Kelvin {
    type Output = Joules;
    fn mul(self, rhs: HeatCapacity) -> Joules {
        rhs * self
    }
}

/// Temperature change from adding `self` joules to a body of this capacity.
impl Div<HeatCapacity> for Joules {
    type Output = Kelvin;
    fn div(self, rhs: HeatCapacity) -> Kelvin {
        Kelvin(self.0 / rhs.0)
    }
}

impl Div<Kelvin> for Joules {
    type Output = HeatCapacity;
    fn div(self, rhs: Kelvin) -> HeatCapacity {
        HeatCapacity(self.0 / rhs.0)
    }
}

impl Watts {
    /// Energy delivered over `seconds`.
    #[must_use]
    pub fn over(self, seconds: Seconds) -> Joules {
        Joules(self.0 * seconds.0)
    }
}

impl Joules {
    /// Average power if delivered over `seconds`.
    #[must_use]
    pub fn per(self, seconds: Seconds) -> Watts {
        Watts(self.0 / seconds.0)
    }
}

impl Kelvin {
    /// Converts from degrees Celsius.
    #[must_use]
    pub fn from_celsius(celsius: f64) -> Self {
        Self(celsius + 273.15)
    }
}

impl Kpa {
    /// Converts to the SI base unit.
    #[must_use]
    pub fn to_pascals(self) -> Pascals {
        Pascals(self.0 * 1000.0)
    }
}

impl Pascals {
    /// Converts to gas's native pressure unit.
    #[must_use]
    pub fn to_kpa(self) -> Kpa {
        Kpa(self.0 / 1000.0)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn cross_unit_arithmetic() {
        let capacity = HeatCapacity(200.0);
        assert_eq!(capacity * Kelvin(3.0), Joules(600.0));
        assert_eq!(Joules(600.0) / capacity, Kelvin(3.0));
        assert_eq!(Joules(600.0) / Kelvin(3.0), capacity);
        assert_eq!(Watts(50.0).over(Seconds(2.0)), Joules(100.0));
        assert_eq!(Joules(100.0).per(Seconds(2.0)), Watts(50.0));
        assert_eq!(Moles(2.0) / Moles(4.0), 0.5);
        assert_eq!(
            [Pascals(1.0), Pascals(2.0)].into_iter().sum::<Pascals>(),
            Pascals(3.0)
        );
        assert_eq!(Kpa(1.0).to_pascals(), Pascals(1000.0));
        assert_eq!(Pascals(1000.0).to_kpa(), Kpa(1.0));
    }

    #[test]
    fn f32_boundary_conversions_round_trip_within_f32_precision() {
        let k = Kelvin::from(293.15f32);
        let back: f32 = k.into();
        assert!((back - 293.15).abs() < 1e-3);
    }
}
