//! SI unit newtypes. Values are `f32` (`rust_core.md` §5 memory policy); the
//! thermodynamics kernel widens to `f64` internally where precision matters.

use std::iter::Sum;
use std::ops::{Add, AddAssign, Div, Mul, Neg, Sub, SubAssign};

macro_rules! unit {
    ($(#[$meta:meta])* $name:ident, $symbol:literal) => {
        $(#[$meta])*
        #[derive(Clone, Copy, Debug, Default, PartialEq, PartialOrd)]
        #[repr(transparent)]
        pub struct $name(pub f32);

        impl $name {
            pub const ZERO: Self = Self(0.0);
            pub const SYMBOL: &'static str = $symbol;

            #[must_use]
            pub const fn get(self) -> f32 {
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
        impl Mul<f32> for $name {
            type Output = Self;
            fn mul(self, rhs: f32) -> Self {
                Self(self.0 * rhs)
            }
        }
        impl Div<f32> for $name {
            type Output = Self;
            fn div(self, rhs: f32) -> Self {
                Self(self.0 / rhs)
            }
        }
        /// Ratio of two quantities of the same unit.
        impl Div for $name {
            type Output = f32;
            fn div(self, rhs: Self) -> f32 {
                self.0 / rhs.0
            }
        }
        impl Sum for $name {
            fn sum<I: Iterator<Item = Self>>(iter: I) -> Self {
                Self(iter.map(|v| v.0).sum())
            }
        }
    };
}

unit!(
    /// Temperature.
    Kelvin, "K"
);

/// Cosmic microwave background, K. The floor of every body and gas. Single
/// source for gas and heat (`rust_core.md` §15 core consolidation; H1 dedup
/// audit finding); both `vg_heat::consts::TCMB` and `vg_gas`'s copy
/// re-export this.
/// @dm-define TCMB
pub const TCMB: f32 = 2.7;
/// 0 °C, K. Single source for gas and heat.
/// @dm-define T0C
pub const T0C: f32 = 273.15;
/// 20 °C, K. Single source for gas and heat.
/// @dm-define T20C
pub const T20C: f32 = 293.15;
unit!(
    /// Energy.
    Joules, "J"
);
unit!(
    /// Pressure.
    Pascals, "Pa"
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
    pub fn over(self, seconds: f32) -> Joules {
        Joules(self.0 * seconds)
    }
}

impl Joules {
    /// Average power if delivered over `seconds`.
    #[must_use]
    pub fn per(self, seconds: f32) -> Watts {
        Watts(self.0 / seconds)
    }
}

impl Kelvin {
    /// Converts from degrees Celsius.
    #[must_use]
    pub fn from_celsius(celsius: f32) -> Self {
        Self(celsius + 273.15)
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
        assert_eq!(Watts(50.0).over(2.0), Joules(100.0));
        assert_eq!(Joules(100.0).per(2.0), Watts(50.0));
        assert_eq!(Moles(2.0) / Moles(4.0), 0.5);
        assert_eq!(
            [Pascals(1.0), Pascals(2.0)].into_iter().sum::<Pascals>(),
            Pascals(3.0)
        );
    }
}
